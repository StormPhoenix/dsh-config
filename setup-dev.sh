#!/usr/bin/env bash
# The coordinator owns validation and all setup behavior.
set -euo pipefail
exec "${DSH_TRANSFER_PYTHON:-python3}" "$(dirname "${BASH_SOURCE[0]}")/setup-dev.py" "$@"
