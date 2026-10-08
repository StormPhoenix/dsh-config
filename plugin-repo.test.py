"""Repository restore tests use owned fixtures and never install real profiles."""
import importlib.util
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('repo', Path(__file__).with_name('plugin-repo.py'))
repo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(repo)


class RepositoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        package = self.home / 'profiles/desktop/node_modules/sample'
        package.mkdir(parents=True)
        (package / 'package.json').write_text(json.dumps({'name': 'sample', 'version': '1', 'dsh': {'bundle': {'patch': './cordis.patch.yml'}}}))
        (package / 'cordis.patch.yml').write_text('[]\n')
        (package.parent.parent / 'package.json').write_text(json.dumps({'dependencies': {'sample': '1'}, 'dsh': {'profile': {'bundles': ['sample']}}}))
        self.repository = self.root / 'repository'
        self.home_patch = patch.object(repo.transfer, 'HOME', self.home)
        self.home_patch.start()
        self.addCleanup(self.home_patch.stop)
        repo.export(self.repository)

    def test_export_and_verify_without_install(self):
        with patch.object(repo.transfer.subprocess, 'run') as run:
            repo.restore(self.repository, verify=True)
            run.assert_not_called()
        self.assertEqual(json.loads((self.repository / 'manifest.json').read_text())['profiles'][0]['plugins'][0]['version'], '1')

    def test_lfs_pointer_refuses_restore(self):
        package = next((self.repository / 'packages').glob('*.tgz'))
        package.write_text('version https://git-lfs.github.com/spec/v1\n')
        with self.assertRaisesRegex(ValueError, 'Git LFS'):
            repo.restore(self.repository, verify=True)

    def test_tampered_payload_refuses_before_cli(self):
        next((self.repository / 'packages').glob('*.tgz')).write_bytes(b'tampered')
        with patch.object(repo.transfer.subprocess, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'checksum'):
                repo.restore(self.repository, cli='dsh', app_closed=True)
            run.assert_not_called()

    def test_existing_export_not_overwritten(self):
        with self.assertRaisesRegex(ValueError, 'already exists'):
            repo.export(self.repository)

    def test_supported_cli_receives_target_home(self):
        with patch.object(repo.transfer.subprocess, 'run') as run:
            repo.restore(self.repository, profile='desktop', cli='dsh', app_closed=True)
            self.assertEqual(run.call_args.args[0][1:4], ['plugin', '--profile', 'desktop'])
            self.assertEqual(run.call_args.args[0][-1], '--ignore-scripts')
            self.assertEqual(run.call_args.kwargs['env']['DSH_HOME'], str(self.home))


if __name__ == '__main__':
    unittest.main()
