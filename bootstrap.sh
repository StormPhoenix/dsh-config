#!/usr/bin/env bash
# Standalone download entry; the Python coordinator owns bootstrap behavior.
set -euo pipefail
if [ "$#" -lt 1 ]; then
  printf 'Usage: bash bootstrap.sh <existing-source-root> [--prepare-only]\n' >&2
  exit 2
fi
python="${DSH_TRANSFER_PYTHON:-python3}"
command -v "$python" >/dev/null || { printf 'Python 3.9+ is required\n' >&2; exit 1; }
command -v curl >/dev/null || { printf 'curl is required for downloading the coordinator\n' >&2; exit 1; }
script="$(mktemp "${TMPDIR:-/tmp}/dsh-bootstrap.XXXXXXXX")"
trap 'rm -f -- "$script"' EXIT
curl --fail --location --silent --show-error 'https://raw.githubusercontent.com/StormPhoenix/dsh-config/main/bootstrap.py' --output "$script"
"$python" "$script" "$@"
