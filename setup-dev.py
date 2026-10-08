#!/usr/bin/env python3
"""Configure a source Desktop against this config home and restore validated bundles.

Preparation stages immutable archives outside both checkouts. Installation uses only
DSH's desktop:plugin batch command; it never edits profile manifests directly.
"""
import argparse
import importlib.util
import io
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
import zipfile

HOME = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('dev_transfer', HOME / 'plugin-transfer.py')
transfer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transfer)


def command(argv, cwd, env, capture=False):
    """Run a checked child, retaining its exit status for CLI diagnostics."""
    return subprocess.run(argv, cwd=cwd, env=env, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None)


def prerequisite(source, env):
    """Reject missing source scripts, dependencies and unsupported Node versions."""
    manifest = transfer.read_json(source / 'package.json')
    scripts = manifest.get('scripts', {})
    for script in ('desktop:plugin', 'dev:desktop'):
        if not isinstance(scripts.get(script), str) or not scripts[script].strip():
            raise ValueError(f'Source root package.json requires script {script}: {source}')
    if not (source / 'node_modules').is_dir():
        raise ValueError('Source dependencies missing; prepare them separately (no dependency installation is automatic)')
    node = shutil.which('node')
    pnpm = shutil.which('pnpm')
    if not node or not pnpm:
        raise ValueError('Node and pnpm must already be available on PATH')
    version = command([node, '--version'], source, env, capture=True).stdout.strip()
    match = re.fullmatch(r'v(\d+)\.(\d+)\.(\d+)', version)
    if not match or not (int(match[1]) >= 24 or (int(match[1]) == 22 and int(match[2]) >= 19)):
        raise ValueError(f'Unsupported Node version {version}; require Node ^22.19 or >=24')
    command([pnpm, '--version'], source, env, capture=True)
    return pnpm


def repository_archive(repository, destination):
    """Construct a ZIP for the existing transfer validator without changing the repository."""
    manifest_path = repository / 'manifest.json'
    manifest = transfer.read_json(manifest_path)
    with zipfile.ZipFile(destination, 'w', zipfile.ZIP_STORED) as output:
        output.writestr('manifest.json', manifest_path.read_bytes())
        for profile in manifest['profiles']:
            for record in profile['plugins']:
                relative = record['archive']
                transfer.safe_relative(relative)
                target = repository / relative
                if not target.resolve().is_relative_to(repository.resolve()):
                    raise ValueError('Package path escapes plugin repository')
                data = target.read_bytes()
                if data.startswith(b'version https://git-lfs.github.com/spec/v1'):
                    raise ValueError('Git LFS payload missing; run git lfs pull in the plugins submodule')
                output.writestr(relative, data)


def stage(source, home, archive=None, staging=None):
    """Validate the entire backup, then stage Desktop archives and a batch plan."""
    with tempfile.TemporaryDirectory() as temporary:
        if archive is None:
            archive = Path(temporary) / 'plugins.zip'
            repository_archive(home / 'plugins', archive)
        manifest, payloads = transfer.validate(archive)
    selected = [profile for profile in manifest['profiles'] if profile['name'] == 'desktop']
    if not selected:
        raise ValueError('Plugin archive has no Desktop profile')
    profile = selected[0]
    for entry in manifest['profiles']:
        for record in entry['plugins']:
            if type(record.get('enabled')) is not bool or type(record.get('native')) is not bool:
                raise ValueError('Plugin enabled/native fields must be booleans')
            with tarfile.open(fileobj=io.BytesIO(payloads[record['archive']]), mode='r:gz') as package:
                native = any(Path(member.name).suffix.lower() in ('.node', '.dll', '.exe', '.dylib', '.so')
                             for member in package.getmembers())
            if (record['native'] or native) and (manifest.get('platform') != sys.platform or manifest.get('machine') != ('AMD64' if sys.platform == 'win32' else platform.machine())):
                raise ValueError(f"Native package requires matching OS/architecture: {record['name']}")
    parent = home.parent / 'dsh-plugin-staging'
    if staging is None:
        for checkout in (source, home):
            if parent.resolve().is_relative_to(checkout):
                raise ValueError('Default staging would be inside a checkout; supply --staging outside both')
        parent.mkdir(parents=True, exist_ok=True)
        destination = Path(tempfile.mkdtemp(prefix='desktop-', dir=parent))
    else:
        destination = staging.resolve()
        for checkout in (source, home):
            if destination.is_relative_to(checkout):
                raise ValueError('Staging must be outside source and config checkouts')
        destination.mkdir(parents=True, exist_ok=False)
    destination.chmod(0o700)
    records = []
    for record in profile['plugins']:
        package = destination / record['archive']
        package.parent.mkdir(parents=True, exist_ok=True)
        package.write_bytes(payloads[record['archive']])
        package.chmod(0o600)
        records.append({key: record[key] for key in ('name', 'version', 'sha256', 'enabled')})
        records[-1]['archive'] = str(package.resolve())
    plan = destination / 'plan.json'
    plan.write_text(json.dumps({'format': 1, 'platform': manifest['platform'], 'machine': manifest['machine'], 'plugins': records, 'order': profile['order']}, indent=2) + '\n', encoding='utf-8')
    plan.chmod(0o600)
    return plan


def setup(source, prepare_only=False, archive=None, staging=None, home=HOME):
    """Initialize config and invoke one Desktop-owned batch, or only prepare its plan."""
    source, home = source.expanduser().resolve(), home.resolve()
    if source.is_relative_to(home) or home.is_relative_to(source):
        raise ValueError('Source and config home must be separate, non-nested directories')
    env = {**os.environ, 'DSH_HOME': str(home), 'DSH_SOURCE_DIR': str(source)}
    pnpm = prerequisite(source, env)
    if not prepare_only:
        git = shutil.which('git')
        if not git:
            raise ValueError('Git is required to check existing config changes')
        status = command([git, 'status', '--porcelain', '--untracked-files=all'], home, env, capture=True).stdout
        if status.strip():
            raise ValueError('Config checkout is dirty; review and preserve local changes before setup (nothing reset or overwritten)')
    if not prepare_only and archive is None:
        command([git, 'submodule', 'update', '--init', '--recursive'], home, env)
        command([git, '-C', str(home / 'plugins'), 'lfs', 'pull'], home, env)
    plan = stage(source, home, archive, staging)
    print(f'Validated Desktop batch plan: {plan}')
    print('Keep this staging directory: local archive paths may be needed for reinstalls.')
    if prepare_only:
        print('Preparation only: no config initialization or plugin installation.')
        return plan
    if os.name == 'nt':
        shell = shutil.which('pwsh') or shutil.which('powershell')
        if not shell:
            raise ValueError('PowerShell is required for config initialization')
        init = [shell, '-NoProfile', '-File', str(home / 'install.ps1')]
    else:
        shell = shutil.which('bash')
        if not shell:
            raise ValueError('Bash is required for config initialization')
        init = [shell, str(home / 'install.sh')]
    command(init, home, env)
    if not (home / 'profiles/desktop/package.json').is_file():
        launch = f'DSH_HOME={shlex.quote(str(home))} pnpm run dev:desktop' if os.name != 'nt' else f'$env:DSH_HOME={json.dumps(str(home))}; pnpm run dev:desktop'
        raise ValueError(f'Desktop requires first launch to initialize its profile. From {source}, run {launch}; fully quit Desktop, then rerun setup. No plugins installed.')
    command([pnpm, 'run', 'desktop:plugin', '--', 'restore', str(plan)], source, env)
    print('Desktop batch completed. Restart Desktop and verify versions, enabled states and functionality.')
    return plan


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='Required existing DSH source checkout root')
    parser.add_argument('--prepare-only', action='store_true', help='Validate and stage only; do not initialize config or install')
    parser.add_argument('--archive', type=Path, help='Plugin backup ZIP instead of the plugins submodule')
    parser.add_argument('--staging', type=Path, help='New durable directory outside both checkouts')
    args = parser.parse_args()
    try:
        setup(args.source, args.prepare_only, args.archive.expanduser().resolve() if args.archive else None,
              args.staging.expanduser().resolve() if args.staging else None)
    except subprocess.CalledProcessError as error:
        parser.exit(error.returncode if error.returncode > 0 else 1, f'Desktop setup failed: child exited {error.returncode}: {error.cmd}\n')
    except (OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile, tarfile.TarError) as error:
        parser.exit(1, f'Desktop setup failed: {error}\n')


if __name__ == '__main__':
    main()
