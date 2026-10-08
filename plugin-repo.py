#!/usr/bin/env python3
"""Export or restore the plugin submodule using the existing transfer validator."""
import argparse
import importlib.util
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import zipfile

HOME = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('transfer', HOME / 'plugin-transfer.py')
transfer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transfer)


def export(repository):
    """Write installed bundle packages to an empty archive repository."""
    if (repository / 'manifest.json').exists():
        raise ValueError('Archive already exists; export to a fresh directory and review before replacing')
    with tempfile.TemporaryDirectory() as temporary:
        archive = transfer.backup(SimpleNamespace(profile=None, out=temporary))
        manifest, payloads = transfer.validate(archive)
        repository.mkdir(parents=True, exist_ok=True)
        for relative, data in payloads.items():
            target = repository / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        (repository / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Exported installed plugins to {repository}')


def restore(repository, profile=None, cli=None, app_closed=False, verify=False):
    """Validate the checked-out LFS payloads before preparing or installing packages."""
    manifest_path = repository / 'manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    members = {'manifest.json': manifest_path.read_bytes()}
    for entry in manifest['profiles']:
        for record in entry['plugins']:
            relative = record['archive']
            transfer.safe_relative(relative)
            target = repository / relative
            if not target.resolve().is_relative_to(repository.resolve()):
                raise ValueError('Package path escapes repository')
            data = target.read_bytes()
            if data.startswith(b'version https://git-lfs.github.com/spec/v1'):
                raise ValueError('Git LFS payload missing: run git lfs pull inside the plugin submodule')
            members[relative] = data
    with tempfile.TemporaryDirectory() as temporary:
        archive = Path(temporary) / 'plugins.zip'
        with zipfile.ZipFile(archive, 'w', zipfile.ZIP_STORED) as output:
            for relative, data in members.items():
                output.writestr(relative, data)
        validated, _ = transfer.validate(archive)
        if verify:
            print('Validated profiles: ' + ', '.join(entry['name'] for entry in validated['profiles']))
            return
        transfer.restore(SimpleNamespace(archive=str(archive), profile=profile, cli=cli,
                                        app_closed=app_closed, staging=None))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['export', 'restore', 'verify'])
    parser.add_argument('--repository', type=Path, default=HOME / 'plugins')
    parser.add_argument('--profile')
    parser.add_argument('--cli')
    parser.add_argument('--app-closed', action='store_true')
    args = parser.parse_args()
    repository = args.repository.expanduser().resolve()
    if args.action == 'export':
        export(repository)
    else:
        restore(repository, args.profile, args.cli, args.app_closed, args.action == 'verify')


if __name__ == '__main__':
    main()
