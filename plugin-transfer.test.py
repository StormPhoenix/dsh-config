"""Fixture tests; never install into a real Harness profile."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location("transfer", Path(__file__).with_name("plugin-transfer.py"))
transfer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transfer)


class TransferTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        profile = self.home / "profiles" / "desktop"
        package = profile / "node_modules" / "sample-pet"
        package.mkdir(parents=True)
        (profile / "package.json").write_text(json.dumps({"dependencies": {"sample-pet": "^1.0.0"}, "dsh": {"profile": {"bundles": ["sample-pet"]}}}))
        (package / "package.json").write_text(json.dumps({"name": "sample-pet", "version": "1.0.0", "dsh": {"bundle": {"patch": "cordis.patch.yml"}}}))
        (package / "cordis.patch.yml").write_text("[]\n")
        (package / "node_modules").mkdir()
        (package / "node_modules" / "excluded.txt").write_text("dependency")
        self.patcher = patch.object(transfer, "HOME", self.home)
        self.patcher.start()
        self.addCleanup(self.patcher.stop)

    def backup(self):
        return transfer.backup(type("Args", (), {"profile": "desktop", "out": str(self.root / "output")})())

    def args(self, archive):
        return type("Args", (), {"archive": str(archive), "profile": None, "staging": str(self.root / "restored"), "cli": None, "app_closed": False})()

    def test_round_trip_prepares_without_installing(self):
        archive = self.backup()
        manifest, payloads = transfer.validate(archive)
        self.assertEqual(manifest["profiles"][0]["plugins"][0]["version"], "1.0.0")
        import io
        import tarfile
        with tarfile.open(fileobj=io.BytesIO(next(iter(payloads.values())))) as tar:
            self.assertNotIn("package/node_modules/excluded.txt", tar.getnames())
        with patch.object(transfer.subprocess, "run") as run:
            target = transfer.restore(self.args(archive))
            run.assert_not_called()
        self.assertTrue((target / "manifest.json").is_file())
        self.assertEqual(json.loads((self.home / "profiles/desktop/package.json").read_text())["dependencies"], {"sample-pet": "^1.0.0"})

    def test_tampered_package_rejected_before_extraction(self):
        archive = self.backup()
        with zipfile.ZipFile(archive) as zip:
            contents = {name: zip.read(name) for name in zip.namelist()}
        contents[next(name for name in contents if name.endswith(".tgz"))] = b"tampered"
        with zipfile.ZipFile(archive, "w") as zip:
            for name, data in contents.items():
                zip.writestr(name, data)
        with self.assertRaisesRegex(ValueError, "checksum"):
            transfer.restore(self.args(archive))
        self.assertFalse((self.root / "restored").exists())

    def test_unexpected_outer_member_rejected(self):
        archive = self.backup()
        with zipfile.ZipFile(archive, "a") as zip:
            zip.writestr("../escape", "bad")
        with self.assertRaisesRegex(ValueError, "Unexpected"):
            transfer.validate(archive)

    def test_package_traversal_rejected(self):
        archive = self.backup()
        import io
        import tarfile
        with zipfile.ZipFile(archive) as zip:
            contents = {name: zip.read(name) for name in zip.namelist()}
        manifest = json.loads(contents['manifest.json'])
        record = manifest['profiles'][0]['plugins'][0]
        data = io.BytesIO()
        with tarfile.open(fileobj=data, mode='w:gz') as tar:
            info = tarfile.TarInfo('package/../../escape')
            info.size = 1
            tar.addfile(info, io.BytesIO(b'x'))
        contents[record['archive']] = data.getvalue()
        record['sha256'] = transfer.digest(data.getvalue())
        contents['manifest.json'] = json.dumps(manifest).encode()
        with zipfile.ZipFile(archive, 'w') as zip:
            for name, value in contents.items():
                zip.writestr(name, value)
        with self.assertRaisesRegex(ValueError, 'Unsafe'):
            transfer.validate(archive)

    def test_disabled_bundle_refuses_automatic_install(self):
        path = self.home / 'profiles/desktop/package.json'
        manifest = json.loads(path.read_text())
        manifest['dsh']['profile']['bundles'] = []
        path.write_text(json.dumps(manifest))
        args = self.args(self.backup())
        args.cli = 'dsh'
        args.app_closed = True
        with patch.object(transfer.subprocess, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'disabled'):
                transfer.restore(args)
            run.assert_not_called()

    def test_cli_requires_closed_app(self):
        archive = self.backup()
        args = self.args(archive)
        args.cli = "dsh"
        with patch.object(transfer.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "app-closed"):
                transfer.restore(args)
            run.assert_not_called()

    def test_cli_install_uses_target_home_and_blocks_scripts(self):
        archive = self.backup()
        args = self.args(archive)
        args.cli = "dsh"
        args.app_closed = True
        with patch.object(transfer.subprocess, "run") as run:
            transfer.restore(args)
            self.assertEqual(run.call_args.args[0][1:4], ["plugin", "--profile", "desktop"])
            self.assertEqual(run.call_args.args[0][-1], "--ignore-scripts")
            self.assertEqual(run.call_args.kwargs["env"]["DSH_HOME"], str(self.home))


if __name__ == "__main__":
    unittest.main()
