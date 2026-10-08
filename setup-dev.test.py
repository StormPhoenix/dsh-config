"""Source Desktop setup tests use private temporary checkouts and mocked children."""
import importlib.util
import io
import json
from pathlib import Path
import platform
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location('setup', Path(__file__).with_name('setup-dev.py'))
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.source = self.root / 'source'
        self.home = self.root / 'config'
        self.source.mkdir()
        self.home.mkdir()
        (self.source / 'node_modules').mkdir()
        (self.source / 'package.json').write_text(json.dumps({'scripts': {'desktop:plugin': 'command', 'dev:desktop': 'command'}}))
        (self.home / 'profiles/desktop').mkdir(parents=True)
        (self.home / 'profiles/desktop/package.json').write_text('{}')
        self.archive = self.root / 'archive.zip'
        self.make_archive()
        self.which = patch.object(setup.shutil, 'which', side_effect=lambda name: name)
        self.which.start()
        self.addCleanup(self.which.stop)
        self.run = patch.object(setup.subprocess, 'run', side_effect=self.child)
        self.mock_run = self.run.start()
        self.addCleanup(self.run.stop)

    def child(self, argv, **kwargs):
        stdout = 'v24.1.0\n' if argv[-1] == '--version' and argv[0] == 'node' else ''
        return subprocess.CompletedProcess(argv, 0, stdout=stdout)

    def make_archive(self, native=False, mismatch=False, enabled=True, corrupt=False):
        records = []
        payloads = {}
        for name, active in [('sample', enabled), ('disabled', False)]:
            buffer = io.BytesIO()
            with tarfile.open(fileobj=buffer, mode='w:gz') as package:
                manifest = json.dumps({'name': name, 'version': '1.2.3', 'dsh': {'bundle': {'patch': './cordis.patch.yml'}}}).encode()
                for filename, data in [('package/package.json', manifest), ('package/cordis.patch.yml', b'[]\n')] + ([('package/addon.node', b'native')] if native else []):
                    member = tarfile.TarInfo(filename)
                    member.size = len(data)
                    package.addfile(member, io.BytesIO(data))
            data = buffer.getvalue()
            filename = f'packages/{name}.tgz'
            payloads[filename] = data if not corrupt else b'bad'
            records.append({'name': name, 'version': '1.2.3', 'sha256': setup.transfer.digest(data), 'archive': filename, 'enabled': active, 'native': False})
        manifest = {'format': 1, 'platform': 'foreign' if mismatch else sys.platform, 'machine': platform.machine(),
                    'profiles': [{'name': 'desktop', 'plugins': records, 'order': ['sample'] if enabled else []}]}
        with zipfile.ZipFile(self.archive, 'w') as archive:
            archive.writestr('manifest.json', json.dumps(manifest))
            for filename, data in payloads.items():
                archive.writestr(filename, data)

    def invoke(self, **kwargs):
        return setup.setup(self.source, home=self.home, archive=self.archive, **kwargs)

    def test_batch_preserves_enabled_order_and_uses_config_home(self):
        plan = self.invoke()
        data = json.loads(plan.read_text())
        self.assertEqual(data['format'], 1)
        self.assertEqual(data['order'], ['sample'])
        self.assertEqual([entry['enabled'] for entry in data['plugins']], [True, False])
        for entry in data['plugins']:
            target = Path(entry['archive'])
            self.assertTrue(target.is_absolute())
            self.assertFalse(target.is_relative_to(self.home))
            self.assertFalse(target.is_relative_to(self.source))
            self.assertEqual(setup.transfer.digest(target.read_bytes()), entry['sha256'])
        call = self.mock_run.call_args
        self.assertEqual(call.args[0], ['pnpm', 'run', 'desktop:plugin', '--', 'restore', str(plan)])
        self.assertEqual(call.kwargs['cwd'], self.source)
        self.assertEqual(call.kwargs['env']['DSH_HOME'], str(self.home))
        self.assertTrue(call.kwargs['check'])
        self.assertEqual((self.home / 'profiles/desktop/package.json').read_text(), '{}')

    def test_prepare_only_never_initializes_or_installs(self):
        self.invoke(prepare_only=True)
        self.assertEqual([call.args[0] for call in self.mock_run.call_args_list], [['node', '--version'], ['pnpm', '--version']])

    def test_requires_source_script_before_other_work(self):
        (self.source / 'package.json').write_text('{}')
        with self.assertRaisesRegex(ValueError, 'desktop:plugin'):
            self.invoke()
        self.mock_run.assert_not_called()

    def test_requires_dependencies_and_tools(self):
        with patch.object(setup.shutil, 'which', return_value=None):
            with self.assertRaisesRegex(ValueError, 'PATH'):
                self.invoke()
        (self.source / 'node_modules').rmdir()
        with self.assertRaisesRegex(ValueError, 'dependencies missing'):
            self.invoke()

    def test_unsupported_node_fails_before_setup(self):
        with patch.object(setup.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, stdout='v23.0.0')):
            with self.assertRaisesRegex(ValueError, 'Unsupported Node'):
                self.invoke()

    def test_dirty_home_stops_before_staging_or_init(self):
        def child(argv, **kwargs):
            result = self.child(argv, **kwargs)
            if 'status' in argv:
                result.stdout = ' M profiles/desktop/cordis.patch.yml\n'
            return result
        self.mock_run.side_effect = child
        with self.assertRaisesRegex(ValueError, 'dirty'):
            self.invoke()
        self.assertFalse((self.root / 'dsh-plugin-staging').exists())
        self.assertFalse(any('install.sh' in ' '.join(call.args[0]) for call in self.mock_run.call_args_list))

    def test_corrupt_archive_fails_before_init(self):
        self.make_archive(corrupt=True)
        with self.assertRaisesRegex(ValueError, 'checksum'):
            self.invoke()
        self.assertFalse(any('restore' in call.args[0] for call in self.mock_run.call_args_list))

    def test_native_files_detected_even_when_record_claims_portable(self):
        self.make_archive(native=True, mismatch=True)
        with self.assertRaisesRegex(ValueError, 'matching OS'):
            self.invoke(prepare_only=True)
        self.assertFalse((self.root / 'dsh-plugin-staging').exists())

    def test_invalid_enabled_flag_refused(self):
        self.make_archive(enabled='yes')
        with self.assertRaisesRegex(ValueError, 'booleans'):
            self.invoke(prepare_only=True)

    def test_nested_or_existing_staging_refused(self):
        for staging in [self.source / 'staging', self.home / 'staging', self.root]:
            with self.assertRaises((ValueError, FileExistsError)):
                self.invoke(prepare_only=True, staging=staging)

    def test_first_launch_is_required_without_plugin_mutation(self):
        (self.home / 'profiles/desktop/package.json').unlink()
        with self.assertRaisesRegex(ValueError, 'first launch'):
            self.invoke()
        self.assertFalse(any('restore' in call.args[0] for call in self.mock_run.call_args_list))

    def test_nonzero_batch_is_not_swallowed(self):
        def child(argv, **kwargs):
            if 'restore' in argv:
                raise subprocess.CalledProcessError(7, argv)
            return self.child(argv, **kwargs)
        self.mock_run.side_effect = child
        with self.assertRaises(subprocess.CalledProcessError) as raised:
            self.invoke()
        self.assertEqual(raised.exception.returncode, 7)

    def test_cli_propagates_child_nonzero_and_requires_source(self):
        with patch.object(sys, 'argv', ['setup-dev.py', str(self.source)]), patch.object(setup, 'setup', side_effect=subprocess.CalledProcessError(7, ['pnpm'])):
            with self.assertRaises(SystemExit) as raised:
                setup.main()
            self.assertEqual(raised.exception.code, 7)
        with patch.object(sys, 'argv', ['setup-dev.py']):
            with self.assertRaises(SystemExit) as raised:
                setup.main()
            self.assertEqual(raised.exception.code, 2)

    def test_setup_initializes_pinned_submodule_and_downloads_lfs(self):
        plugins = self.home / 'plugins'
        plugins.mkdir()
        with zipfile.ZipFile(self.archive) as archive:
            archive.extractall(plugins)
        setup.setup(self.source, home=self.home)
        calls = [call.args[0] for call in self.mock_run.call_args_list]
        self.assertIn(['git', 'submodule', 'update', '--init', '--recursive'], calls)
        self.assertIn(['git', '-C', str(plugins), 'lfs', 'pull'], calls)
        self.assertFalse(any('--remote' in call for call in calls))

    def test_repository_validation_reads_lfs_payload_without_changes(self):
        plugins = self.home / 'plugins'
        plugins.mkdir()
        with zipfile.ZipFile(self.archive) as archive:
            archive.extractall(plugins)
        plan = setup.setup(self.source, home=self.home, prepare_only=True)
        self.assertTrue(plan.is_file())
        (plugins / 'packages/sample.tgz').write_text('version https://git-lfs.github.com/spec/v1\n')
        with self.assertRaisesRegex(ValueError, 'LFS payload missing'):
            setup.setup(self.source, home=self.home, prepare_only=True)


if __name__ == '__main__':
    unittest.main()
