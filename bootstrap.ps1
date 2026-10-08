# Standalone download entry; the Python coordinator owns bootstrap behavior.
$ErrorActionPreference = 'Stop'
if ($args.Count -lt 1) { Write-Error 'Usage: .\bootstrap.ps1 <existing-source-root> [--prepare-only]'; exit 2 }
$python = if ($env:DSH_TRANSFER_PYTHON) { $env:DSH_TRANSFER_PYTHON } else { 'python' }
if (-not (Get-Command $python -ErrorAction SilentlyContinue)) { Write-Error 'Python 3.9+ is required'; exit 1 }
$script = Join-Path ([IO.Path]::GetTempPath()) ('dsh-bootstrap-' + [guid]::NewGuid().ToString('N') + '.py')
try {
  Invoke-WebRequest 'https://raw.githubusercontent.com/StormPhoenix/dsh-config/main/bootstrap.py' -OutFile $script
  & $python $script @args
  $code = $LASTEXITCODE
} finally {
  if (Test-Path -LiteralPath $script) { Remove-Item -LiteralPath $script }
}
exit $code
