# Windows x64 native Hindsight installation and service launcher.
[CmdletBinding()]
param(
    [ValidateSet('Start','Stop','Status','Install','Api','Ui','RunApi','RunUi')]
    [string]$Action = 'Start',
    [string]$Provider = $(if ($env:HINDSIGHT_API_LLM_PROVIDER) { $env:HINDSIGHT_API_LLM_PROVIDER } else { 'openai-responses' }),
    [string]$BaseUrl,
    [string]$Model,
    [string]$LaunchId
)
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:USERPROFILE '.hindsight'
$native = Join-Path $root 'native'
$apiUrl = 'http://127.0.0.1:9077'
$uiUrl = 'http://127.0.0.1:9999'

function Assert-NativeExit([string]$Step) {
    if ($LASTEXITCODE -ne 0) { throw "$Step failed (exit $LASTEXITCODE)." }
}
function Test-Listening([int]$Port) {
    return [bool](Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
}
function Test-Api {
    try { return (Invoke-RestMethod "$apiUrl/health" -TimeoutSec 5).status -eq 'healthy' }
    catch { return $false }
}
function Test-Ui {
    try {
        $r = Invoke-WebRequest "$uiUrl/dashboard" -UseBasicParsing -TimeoutSec 10
        return $r.StatusCode -eq 200 -and $r.Content -match '(?i)hindsight'
    } catch { return $false }
}
function Show-Status {
    [pscustomobject]@{ Service='API'; URL=$apiUrl; Listening=(Test-Listening 9077); Ready=(Test-Api) }
    [pscustomobject]@{ Service='UI'; URL=$uiUrl; Listening=(Test-Listening 9999); Ready=(Test-Ui) }
}

if ($Action -in @('Start','Stop','Status')) {
$main = Join-Path $PSScriptRoot 'hindsight.ps1'
$root = Join-Path $env:USERPROFILE '.hindsight'
$stateDir = Join-Path $root 'launcher'
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
$services = @(
    @{ Name='API'; Port=9077; Action='Api'; URL='http://127.0.0.1:9077/health'; Entry='backend\start-backend.ps1'; Native='native\.venv\Scripts\hindsight-api.exe' },
    @{ Name='UI'; Port=9999; Action='Ui'; URL='http://127.0.0.1:9999/dashboard'; Entry='control-plane\start-ui.ps1'; Native='native\node_modules\@vectorize-io\hindsight-control-plane\bin\cli.js' }
)
function State-Path($service) { Join-Path $stateDir ($service.Name.ToLower()+'.json') }
function Read-State($service) {
    $path = State-Path $service
    if (Test-Path -LiteralPath $path) { Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
}
function Get-OwnedProcess($record) {
    if (-not $record) { return $null }
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$([int]$record.Pid)"
    if ($p -and $p.Name -ieq 'powershell.exe' -and $p.CreationDate.ToUniversalTime().Ticks.ToString() -eq $record.CreatedTicks -and
        $p.CommandLine -and $p.CommandLine.Contains($main) -and $p.CommandLine.Contains([string]$record.LaunchId)) { return $p }
    return $null
}
function Listening($service) { [bool](Get-NetTCPConnection -State Listen -LocalPort $service.Port -ErrorAction SilentlyContinue) }
function Ready($service) {
    if (-not (Listening $service)) { return $false }
    try {
        if ($service.Name -eq 'API') { return (Invoke-RestMethod $service.URL -TimeoutSec 3).status -eq 'healthy' }
        $r = Invoke-WebRequest $service.URL -UseBasicParsing -TimeoutSec 3
        return $r.StatusCode -eq 200 -and $r.Content -match '(?i)hindsight'
    } catch { return $false } # A failed probe is not readiness; log files retain service diagnostics.
}
function Show-State($service) {
    $r = Read-State $service
    $owned = Get-OwnedProcess $r
    [pscustomobject]@{Service=$service.Name; Managed=[bool]$owned; Pid=$(if($owned){$owned.ProcessId}else{$null}); Listening=(Listening $service); Ready=(Ready $service); Stdout=$(if($r){$r.Stdout}else{$null}); Stderr=$(if($r){$r.Stderr}else{$null})}
}
function Stop-Owned($service) {
    $record = Read-State $service
    $owned = Get-OwnedProcess $record
    if (-not $owned) {
        if (Listening $service) { Write-Warning "$($service.Name): listener not owned by this launcher; NOT stopped." }
        else { Write-Host "$($service.Name): no owned process is running." }
        return
    }
    # Windows taskkill is a forced tree stop, not a graceful database shutdown.
    Write-Warning "$($service.Name): forcibly stopping the verified launcher process tree. In-flight work may be interrupted."
    & "$env:SystemRoot\System32\taskkill.exe" /PID $owned.ProcessId /T /F | Out-Null
    $code = $LASTEXITCODE
    if ($code -ne 0 -and (Get-OwnedProcess $record)) { throw "$($service.Name): tree termination failed. Inspect the process and logs; state retained." }
    if (Get-OwnedProcess $record) { throw "$($service.Name): process still running; state retained." }
    if (Listening $service) { throw "$($service.Name): launcher exited but the port remains occupied; inspect it manually. State retained." }
    # Retain record for logs and diagnosis; stale identities can never authorize a stop.
    Write-Host "$($service.Name): stopped."
}
function Start-One($service) {
    $record = Read-State $service
    if (Get-OwnedProcess $record) {
        Write-Host "$($service.Name): managed process already running (ready: $(Ready $service)); skipped."
        return
    }
    if (Listening $service) {
        if (Ready $service) { Write-Warning "$($service.Name): healthy but externally managed; skipped. Stop will not terminate it."; return }
        throw "$($service.Name): port $($service.Port) occupied by an unhealthy/unrecognized service. No duplicate started."
    }
    $id = [guid]::NewGuid().ToString('N')
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfff')
    $out = Join-Path $stateDir "$($service.Name.ToLower())-$stamp-$id.stdout.log"
    $err = Join-Path $stateDir "$($service.Name.ToLower())-$stamp-$id.stderr.log"
    $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $args = "-NoLogo -NoProfile -NonInteractive -File `"$main`" -Action $($service.Action) -LaunchId $id"
    $child = Start-Process $ps -ArgumentList $args -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -WorkingDirectory $PSScriptRoot -PassThru
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$($child.Id)"
    if (-not $p) { throw "$($service.Name): process exited before registration. Inspect $err" }
    $r = @{ Pid=$child.Id; CreatedTicks=$p.CreationDate.ToUniversalTime().Ticks.ToString(); LaunchId=$id; Stdout=$out; Stderr=$err }
    # Register immediately. If writing fails, disclose the unmanaged launch rather than hiding it.
    try {
        $path = State-Path $service
        $r | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding UTF8
    } catch {
        throw "$($service.Name): process $($child.Id) was launched but state could not be saved. Inspect it manually before retrying."
    }
    Write-Host "$($service.Name): process created, PID $($child.Id); readiness is not yet confirmed."
    Write-Host "  stdout: $out"
    Write-Host "  stderr: $err"
}

# Serialize Start/Stop/Status for this user's installation.
$lockPath = Join-Path $stateDir 'manager.lock'
try { $lock = [IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
catch { throw 'Another launcher operation is active (or the lock file is inaccessible). Retry after it finishes.' }
try {
    if ($Action -eq 'Status') { foreach($s in $services){ Show-State $s }; return }
    if ($Action -eq 'Stop') { foreach($s in @($services[1],$services[0])){ Stop-Owned $s }; return }
    Write-Warning 'Launch from an external PowerShell. Hidden windows do not escape DSH Windows Job ownership.'
    # Validate both installations before creating either process.
    foreach($s in $services) {
        if (-not (Listening $s) -and -not (Test-Path (Join-Path $root $s.Entry)) -and -not (Test-Path (Join-Path $root $s.Native))) {
            throw "$($s.Name) is not installed. Run hindsight.ps1 -Action Install."
        }
        if ((Listening $s) -and -not (Ready $s)) { throw "$($s.Name): occupied port is not healthy. No services started." }
    }
    # Native credentials are collected by the visible parent, never by a hidden child.
    $names = @('HINDSIGHT_API_LLM_PROVIDER','HINDSIGHT_API_LLM_BASE_URL','HINDSIGHT_API_LLM_MODEL','HINDSIGHT_API_LLM_API_KEY')
    $prior = @{}
    foreach($name in $names){$prior[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
    try {
        $apiNeedsLaunch = -not (Get-OwnedProcess (Read-State $services[0])) -and -not (Listening $services[0])
        if ($apiNeedsLaunch -and -not (Test-Path (Join-Path $root $services[0].Entry))) {
            if (-not $BaseUrl) { $BaseUrl=$env:HINDSIGHT_API_LLM_BASE_URL }
            if (-not $Model) { $Model=$env:HINDSIGHT_API_LLM_MODEL }
            if (-not $BaseUrl) { $BaseUrl=Read-Host 'Model Base URL' }
            if (-not $Model) { $Model=Read-Host 'Model name' }
            if (-not $BaseUrl -or -not $Model) { throw 'Model Base URL and name are required.' }
            $env:HINDSIGHT_API_LLM_PROVIDER=$Provider
            $env:HINDSIGHT_API_LLM_BASE_URL=$BaseUrl
            $env:HINDSIGHT_API_LLM_MODEL=$Model
            if (-not $env:HINDSIGHT_API_LLM_API_KEY) {
                $secret=Read-Host 'Model API key (hidden)' -AsSecureString
                $env:HINDSIGHT_API_LLM_API_KEY=[System.Net.NetworkCredential]::new('',$secret).Password
            }
        }
        Start-One $services[0]
    } finally {
        foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$prior[$name],'Process')}
        Remove-Variable secret -ErrorAction SilentlyContinue
    }
    # Ensure the UI never inherits a model key, even if the caller already had one.
    $keyBefore=$env:HINDSIGHT_API_LLM_API_KEY
    try { Remove-Item Env:HINDSIGHT_API_LLM_API_KEY -ErrorAction SilentlyContinue; Start-One $services[1] }
    finally { [Environment]::SetEnvironmentVariable('HINDSIGHT_API_LLM_API_KEY',$keyBefore,'Process') }
    Write-Host 'Start requests completed. Run -Action Status to distinguish starting from ready.'
    Write-Host 'UI: http://127.0.0.1:9999'
} catch {
    Write-Warning 'Startup/stop may be partial. Existing or already-launched services are NOT automatically rolled back. Use Status and inspect logs before retrying.'
    throw
} finally { $lock.Dispose() }

return
}

if ($Action -eq 'Install') {
    foreach ($name in @('uv','node','npm')) {
        if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "Install $name first, then reopen PowerShell." }
    }
    if (Test-Path -LiteralPath $native) { throw "Installation directory exists: $native. Inspect it before retrying; nothing was overwritten." }
    New-Item -ItemType Directory -Path $native | Out-Null
    uv venv --python 3.12 "$native\.venv"
    Assert-NativeExit 'Creating Python environment'
    uv pip install --python "$native\.venv\Scripts\python.exe" 'hindsight-api-slim[local-onnx,embedded-db]==1.1.0' 'flashrank==0.2.10'
    Assert-NativeExit 'Installing API'
    $manifest = @{ name='local-hindsight-ui'; private=$true; dependencies=@{ '@vectorize-io/hindsight-control-plane'='1.1.0' } }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content "$native\package.json" -Encoding UTF8
    Push-Location $native
    try {
        npm install --ignore-scripts --no-audit --no-fund
        Assert-NativeExit 'Installing UI'
    } finally { Pop-Location }
    Write-Host 'Installed. Run hindsight.ps1 to launch both services in the background.'
    return
}

if ($Action -eq 'RunApi') { $Action = 'Api' }
if ($Action -eq 'RunUi') { $Action = 'Ui' }
$port = if ($Action -eq 'Api') { 9077 } else { 9999 }
if (Test-Listening $port) { throw "Port $port is occupied. Stop or inspect the existing service before starting another instance." }
Write-Host 'Running in this terminal. Ctrl+C stops the service. Use an external terminal to avoid DSH process-tree ownership.'
if ($Action -eq 'Ui') {
    $entry = Join-Path $root 'control-plane\start-ui.ps1'
    if (Test-Path -LiteralPath $entry) { & $entry; return }
    $cli = "$native\node_modules\@vectorize-io\hindsight-control-plane\bin\cli.js"
    if (-not (Test-Path -LiteralPath $cli)) { throw 'UI is not installed. Run hindsight.ps1 -Action Install first.' }
    & node $cli --hostname 127.0.0.1 --port 9999 --api-url $apiUrl
    Assert-NativeExit 'UI'
    return
}
$entry = Join-Path $root 'backend\start-backend.ps1'
if (Test-Path -LiteralPath $entry) { & $entry; return }
$exe = "$native\.venv\Scripts\hindsight-api.exe"
if (-not (Test-Path -LiteralPath $exe)) { throw 'API is not installed. Run hindsight.ps1 -Action Install first.' }
if (-not $BaseUrl) { $BaseUrl = $env:HINDSIGHT_API_LLM_BASE_URL }
if (-not $BaseUrl) { $BaseUrl = Read-Host 'Model API Base URL (usually ending in /v1)' }
if (-not $Model) { $Model = $env:HINDSIGHT_API_LLM_MODEL }
if (-not $Model) { $Model = Read-Host 'Model name' }
if (-not $BaseUrl -or -not $Model) { throw 'Base URL and model are required.' }
$values = @{
    PYTHONUTF8='1'; PYTHONIOENCODING='utf-8'
    HINDSIGHT_API_LLM_PROVIDER=$Provider
    HINDSIGHT_API_LLM_BASE_URL=$BaseUrl
    HINDSIGHT_API_LLM_MODEL=$Model
    HINDSIGHT_API_DATABASE_URL='pg0://hindsight-native'
    HINDSIGHT_API_EMBEDDINGS_PROVIDER='onnx'
    HINDSIGHT_API_EMBEDDINGS_ONNX_MODEL_ID='intfloat/multilingual-e5-small'
    HINDSIGHT_API_RERANKER_PROVIDER='flashrank'
    HINDSIGHT_API_LLM_MAX_CONCURRENT='2'
    HINDSIGHT_API_MODEL_INIT_TIMEOUT='900'
    HINDSIGHT_API_LOG_LEVEL='warning'
    HINDSIGHT_API_LLM_API_KEY=$env:HINDSIGHT_API_LLM_API_KEY
}
$prior = @{}
foreach ($name in $values.Keys) { $prior[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
try {
    if (-not $values.HINDSIGHT_API_LLM_API_KEY) {
        $secret = Read-Host 'Model API key (hidden)' -AsSecureString
        $values.HINDSIGHT_API_LLM_API_KEY = [System.Net.NetworkCredential]::new('', $secret).Password
    }
    foreach ($name in $values.Keys) { [Environment]::SetEnvironmentVariable($name,$values[$name],'Process') }
    & $exe --host 127.0.0.1 --port 9077
    Assert-NativeExit 'API'
} finally {
    foreach ($name in $prior.Keys) { [Environment]::SetEnvironmentVariable($name,$prior[$name],'Process') }
    $values.HINDSIGHT_API_LLM_API_KEY = $null
    Remove-Variable secret -ErrorAction SilentlyContinue
}
