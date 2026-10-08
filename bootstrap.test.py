"""Bootstrap children are mocked; tests never clone or initialize the real home."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('bootstrap', Path(__file__).with_name('bootstrap.py'))
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.source = self.root / 'source'
        self.source.mkdir()
        (self.source / 'package.json').write_text('{}')
        self.home = self.root / 'home'
        self.which = patch.object(bootstrap.shutil, 'which', return_value='git')
        self.which.start()
        self.addCleanup(self.which.stop)
        self.calls = []
        self.mock = patch.object(bootstrap.subprocess, 'run', side_effect=self.child)
        self.run = self.mock.start()
        self.addCleanup(self.mock.stop)

    def checkout(self):
        self.home.mkdir()
        (self.home / '.git').mkdir()
        (self.home / 'setup-dev.py').write_text('')

    def child(self, argv, **kwargs):
        self.calls.append((argv, kwargs))
        if 'clone' in argv:
            self.checkout()
        stdout = bootstrap.REMOTE if 'get-url' in argv else ''
        return subprocess.CompletedProcess(argv, 0, stdout=stdout)

    def test_new_home_cloned_then_pinned_submodules_and_lfs_then_setup(self):
        bootstrap.bootstrap(self.source, self.home, prepare_only=True)
        argv = [call[0] for call in self.calls]
        self.assertEqual(argv[1], ['git', 'clone', '--', bootstrap.REMOTE, str(self.home)])
        self.assertEqual(argv[2], ['git', 'submodule', 'update', '--init', '--recursive'])
        self.assertEqual(argv[3], ['git', 'submodule', 'foreach', '--recursive', 'git lfs pull'])
        self.assertEqual(argv[4][-2:], [str(self.source), '--prepare-only'])
        self.assertFalse(any('--remote' in command or 'pull' in command or 'reset' in command for command in argv))
        self.assertTrue(all(call[1]['env']['DSH_HOME'] == str(self.home) for call in self.calls))
        self.assertTrue(all(call[1]['check'] for call in self.calls))

    def test_existing_clean_home_not_cloned_or_pulled(self):
        self.checkout()
        bootstrap.bootstrap(self.source, self.home)
        self.assertFalse(any('clone' in argv or 'pull' in argv for argv, _ in self.calls))
        self.assertTrue(any('status' in argv for argv, _ in self.calls))

    def test_existing_nonrepo_home_preserved(self):
        self.home.mkdir()
        sentinel = self.home / 'sentinel'
        sentinel.write_text('existing')
        with self.assertRaisesRegex(ValueError, 'not a config Git'):
            bootstrap.bootstrap(self.source, self.home)
        self.assertEqual(sentinel.read_text(), 'existing')
        self.assertEqual(len(self.calls), 1)

    def test_dirty_home_stops_before_submodule_mutation(self):
        self.checkout()
        def child(argv, **kwargs):
            result = self.child(argv, **kwargs)
            if 'status' in argv:
                result.stdout = ' M local\n'
            return result
        self.run.side_effect = child
        with self.assertRaisesRegex(ValueError, 'dirty'):
            bootstrap.bootstrap(self.source, self.home)
        self.assertFalse(any('submodule' in argv for argv, _ in self.calls))

    def test_other_remote_refused(self):
        self.checkout()
        def child(argv, **kwargs):
            result = self.child(argv, **kwargs)
            if 'get-url' in argv:
                result.stdout = 'another-remote'
            return result
        self.run.side_effect = child
        with self.assertRaisesRegex(ValueError, 'origin differs'):
            bootstrap.bootstrap(self.source, self.home)

    def test_nonzero_git_exit_stops_bootstrap(self):
        self.run.side_effect = subprocess.CalledProcessError(9, ['git', 'lfs', 'version'])
        with self.assertRaises(subprocess.CalledProcessError) as raised:
            bootstrap.bootstrap(self.source, self.home)
        self.assertEqual(raised.exception.returncode, 9)
        self.assertFalse(self.home.exists())

    def test_cli_propagates_nonzero_child_exit(self):
        with patch.object(bootstrap.sys, 'argv', ['bootstrap.py', str(self.source)]), patch.object(bootstrap, 'bootstrap', side_effect=subprocess.CalledProcessError(9, ['git'])):
            with self.assertRaises(SystemExit) as raised:
                bootstrap.main()
            self.assertEqual(raised.exception.code, 9)

    def test_missing_source_never_runs_children(self):
        with self.assertRaisesRegex(ValueError, 'Existing DSH source'):
            bootstrap.bootstrap(self.root / 'missing', self.home)
        self.run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
