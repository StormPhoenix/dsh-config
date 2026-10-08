# The coordinator owns validation and all setup behavior.
$ErrorActionPreference = 'Stop'
$python = if ($env:DSH_TRANSFER_PYTHON) { $env:DSH_TRANSFER_PYTHON } else { 'python' }
& $python (Join-Path $PSScriptRoot 'setup-dev.py') @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
