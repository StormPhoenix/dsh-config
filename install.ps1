# dsh-config installer (Windows) —— 幂等脚本，与 install.sh 行为一致。
#
# 首次安装与每次 `git pull` 之后执行同一个脚本，由 hooks/post-merge 自动调用。
# 只做配置落位与体检：不下载可执行文件，不写入任何密钥。
$ErrorActionPreference = 'Stop'

$HomeDir = $PSScriptRoot

function Say  ($m) { Write-Host $m }
function Step ($m) { Write-Host "`n== $m" }
function Ok   ($m) { Write-Host "   ok    $m" }
function Warn ($m) { Write-Host "   warn  $m" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
Step "1/6 解析 DSH home"
Say "   本仓库（= DSH home）: $HomeDir"
if ($env:DSH_HOME) {
  if ($env:DSH_HOME.TrimEnd('\') -ieq $HomeDir.TrimEnd('\')) {
    Ok "DSH_HOME 已指向本仓库"
  } else {
    Warn "当前 DSH_HOME=$env:DSH_HOME 与本仓库位置不一致，配置不会生效"
  }
} else {
  Warn "当前进程未设置 DSH_HOME（第 2 步会持久化，需要重启应用/终端）"
}

# ---------------------------------------------------------------------------
Step "2/6 持久化 DSH_HOME（用户级环境变量）"
$persisted = [Environment]::GetEnvironmentVariable('DSH_HOME', 'User')
if ($persisted -and $persisted.TrimEnd('\') -ieq $HomeDir.TrimEnd('\')) {
  Ok "用户环境变量 DSH_HOME 已正确设置"
} elseif ($persisted) {
  Warn "用户环境变量 DSH_HOME 已存在且不同: $persisted"
  Warn "请手动改为: $HomeDir"
} else {
  [Environment]::SetEnvironmentVariable('DSH_HOME', $HomeDir, 'User')
  $env:DSH_HOME = $HomeDir
  Ok "已写入用户环境变量 DSH_HOME —— 重新启动 Desktop 后生效"
}

# ---------------------------------------------------------------------------
Step "3/6 安装 git hook（pull 后自动执行本脚本）"
if (Test-Path (Join-Path $HomeDir '.git')) {
  git -C $HomeDir config core.hooksPath hooks
  Ok "core.hooksPath = hooks"
} else {
  Warn "不是 git 仓库，跳过"
}

# ---------------------------------------------------------------------------
Step "4/6 生成机器层 `$DSH_HOME/cordis.patch.yml`"
$src = Join-Path $HomeDir 'machines\windows.cordis.patch.yml'
$dst = Join-Path $HomeDir 'cordis.patch.yml'
if (Test-Path $src) {
  $same = (Test-Path $dst) -and ((Get-FileHash $src).Hash -eq (Get-FileHash $dst).Hash)
  if ($same) {
    Ok "机器层已是最新（windows）"
  } else {
    Copy-Item $src $dst -Force
    Ok "已由 machines\windows.cordis.patch.yml 生成"
  }
} else {
  Warn "缺少 machines\windows.cordis.patch.yml，机器层未生成"
}

# ---------------------------------------------------------------------------
Step "5/6 外部工具体检（只报告，不安装）"
if (Get-Command node -ErrorAction SilentlyContinue) {
  Ok "node: $((Get-Command node).Source)"
} else {
  Warn "PATH 中没有 node —— Desktop 自带运行时可用，但机器层若引用系统 node 需修正"
}
$pw = Join-Path $env:USERPROFILE '.local\lib\node_modules\playwriter\bin.js'
if (Test-Path $pw) {
  Ok "playwriter 入口存在: $pw"
} else {
  Warn "未发现 $pw —— 启用 Playwriter 时需先安装并修正 machines\windows.cordis.patch.yml"
}

# ---------------------------------------------------------------------------
Step "6/6 密钥体检（只报告，绝不写入）"
foreach ($key in @('TX_GATEWAY_API_KEY', 'DEEPSEEK_API_KEY')) {
  $envValue = [Environment]::GetEnvironmentVariable($key, 'User')
  $creds = Join-Path $HomeDir '.credentials.yaml'
  if ($envValue) {
    Ok "$key 已从用户环境变量提供"
  } elseif ((Test-Path $creds) -and (Select-String -Path $creds -Pattern $key -Quiet)) {
    Ok "$key 已在本机 .credentials.yaml 中"
  } else {
    Warn "$key 缺失：设置用户环境变量，或确认 `$DSH_HOME/.credentials.yaml` 已同步"
  }
}

Write-Host "`n完成。若这是首次安装，请重新打开终端并重启 Desktop。"
