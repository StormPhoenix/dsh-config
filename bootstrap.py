#!/usr/bin/env python3
"""Clone the config home, hydrate pinned submodules/LFS, then run source Desktop setup.

Requires an existing source checkout and already installed Git/LFS, Node, pnpm and
Python 3.9+. Existing config homes are inspected, never pulled, reset or replaced.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys

REMOTE = 'git@github.com:StormPhoenix/dsh-config.git'


def run(argv, cwd, env, capture=False):
    return subprocess.run(argv, cwd=cwd, env=env, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None)


def bootstrap(source, home=None, prepare_only=False):
    """Use the sole source path; clone only an absent default ~/.dsh home."""
    source = source.expanduser().resolve()
    home = (home or Path.home() / '.dsh').expanduser().resolve()
    if not (source / 'package.json').is_file():
        raise ValueError(f'Existing DSH source checkout required: {source}')
    if source.is_relative_to(home) or home.is_relative_to(source):
        raise ValueError('Source and config home must be separate, non-nested directories')
    git = shutil.which('git')
    if not git:
        raise ValueError('Git and Git LFS must already be installed')
    env = {**os.environ, 'DSH_HOME': str(home), 'DSH_SOURCE_DIR': str(source), 'GIT_LFS_SKIP_SMUDGE': '1'}
    run([git, 'lfs', 'version'], source, env, capture=True)
    if home.exists():
        if not (home / '.git').exists():
            raise ValueError(f'Existing home is not a config Git checkout; preserve it and stop: {home}')
        remote = run([git, 'remote', 'get-url', 'origin'], home, env, capture=True).stdout.strip()
        if remote != REMOTE:
            raise ValueError(f'Existing home origin differs from {REMOTE}; nothing replaced')
        status = run([git, 'status', '--porcelain', '--untracked-files=all'], home, env, capture=True).stdout
        if status.strip():
            raise ValueError('Existing config home is dirty; nothing reset, pulled or overwritten')
    else:
        run([git, 'clone', '--', REMOTE, str(home)], source, env)
    # update --init checks out recorded commits; --remote would change those pins.
    run([git, 'submodule', 'update', '--init', '--recursive'], home, env)
    run([git, 'submodule', 'foreach', '--recursive', 'git lfs pull'], home, env)
    coordinator = home / 'setup-dev.py'
    if not coordinator.is_file():
        raise ValueError('Config checkout lacks setup-dev.py; update it manually without discarding local changes')
    argv = [sys.executable, str(coordinator), str(source)]
    if prepare_only:
        argv.append('--prepare-only')
    run(argv, home, env)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='Required existing DSH source checkout root')
    parser.add_argument('--prepare-only', action='store_true', help='Clone/hydrate and stage without config initialization or plugin installation')
    args = parser.parse_args()
    try:
        bootstrap(args.source, prepare_only=args.prepare_only)
    except subprocess.CalledProcessError as error:
        parser.exit(error.returncode if error.returncode > 0 else 1, f'Bootstrap failed: child exited {error.returncode}: {error.cmd}\n')
    except (OSError, ValueError) as error:
        parser.exit(1, f'Bootstrap failed: {error}\n')


if __name__ == '__main__':
    main()
