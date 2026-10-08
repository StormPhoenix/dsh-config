# dsh-config installer (Windows) —— 幂等脚本，与 install.sh 行为一致。
#
# 首次安装与每次 `git pull` 之后执行同一个脚本，由 hooks/post-merge 自动调用。
# 做三件事：把机器专属配置落位（含数据分根）、迁移既有数据、体检外部工具与密钥。
# 不下载可执行文件；全程不写入密钥。
$ErrorActionPreference = 'Stop'

# Repository mode sets up configuration, then prepares or installs validated plugins.
if ($args.Count -gt 0 -and $args[0] -eq '--with-plugins') {
  $rest = @($args | Select-Object -Skip 1)
  & (Join-Path $PSScriptRoot 'install.ps1')
  $python = if ($env:DSH_TRANSFER_PYTHON) { $env:DSH_TRANSFER_PYTHON } else { 'python' }
  & $python (Join-Path $PSScriptRoot 'plugin-repo.py') restore @rest
  if ($LASTEXITCODE -ne 0) { throw "插件子模块恢复失败（退出码 $LASTEXITCODE）" }
  exit 0
}

# Explicit restore mode does not run environment setup or rewrite profile files.
if ($args.Count -gt 0 -and $args[0] -eq '--plugins') {
  $rest = @($args | Select-Object -Skip 1)
  $python = if ($env:DSH_TRANSFER_PYTHON) { $env:DSH_TRANSFER_PYTHON } else { 'python' }
  & $python (Join-Path $PSScriptRoot 'plugin-transfer.py') restore @rest
  if ($LASTEXITCODE -ne 0) { throw "插件恢复失败（退出码 $LASTEXITCODE）" }
  exit 0
}

$HomeDir = $PSScriptRoot
$DataDir = "$HomeDir-data"

function Say  ($m) { Write-Host $m }
function Step ($m) { Write-Host "`n== $m" }
function Ok   ($m) { Write-Host "   ok    $m" }
function Warn ($m) { Write-Host "   warn  $m" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
Step "1/7 解析 DSH home"
Say "   本仓库（= DSH home）: $HomeDir"
Say "   数据根（仓库之外）:  $DataDir"
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
Step "2/7 持久化 DSH_HOME（用户级环境变量）"
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
Step "3/7 安装 git hook（pull 后自动执行本脚本）"
if (Test-Path (Join-Path $HomeDir '.git')) {
  git -C $HomeDir config core.hooksPath hooks
  Ok "core.hooksPath = hooks"
} else {
  Warn "不是 git 仓库，跳过"
}

# ---------------------------------------------------------------------------
Step "4/7 准备数据根（仓库之外的不可再生数据）"
# 会话记录/附件/存储/凭据都放在这里，而不是 $DSH_HOME 内。
# 于是仓库里的 `git clean -x` 之类的操作永远不可能删到它们。
if (Test-Path $DataDir) {
  Ok "$DataDir 已存在"
} else {
  New-Item -ItemType Directory -Path $DataDir | Out-Null
  Ok "已创建 $DataDir"
}
# 一次性迁移：只在目标缺失时复制，绝不覆盖已有数据（幂等，可安全重复执行）
foreach ($sub in @('sessions', 'attachments', 'storages')) {
  $from = Join-Path $HomeDir $sub
  $to = Join-Path $DataDir $sub
  if ((Test-Path $from) -and -not (Test-Path $to)) {
    Copy-Item $from $to -Recurse
    Ok "已迁移 $sub -> $to"
  }
}
$credsData = Join-Path $DataDir '.credentials.yaml'
$credsHome = Join-Path $HomeDir '.credentials.yaml'
if (Test-Path $credsData) {
  Ok "凭据已在数据根：$credsData"
} elseif (Test-Path $credsHome) {
  Copy-Item $credsHome $credsData
  Ok "已迁移 .credentials.yaml 到数据根（请确认其 ACL 仅本人可读）"
} else {
  Ok "尚无凭据文件（可用用户环境变量提供密钥）"
}
if ((Test-Path (Join-Path $HomeDir 'sessions')) -and (Test-Path (Join-Path $DataDir 'sessions'))) {
  Say "   提示：$HomeDir\sessions 仍在原处，仅作安全网；确认新布局正常后可自行删除"
}

# ---------------------------------------------------------------------------
Step "5/7 生成机器层 `$DSH_HOME/cordis.patch.yml"
$src = Join-Path $HomeDir 'machines\windows.cordis.patch.yml'
$dst = Join-Path $HomeDir 'cordis.patch.yml'
if (Test-Path $src) {
  # __DSH_DATA__ → 数据根（正斜杠，Node 在 Windows 上同样接受）
  $dataYaml = $DataDir.Replace('\', '/')
  # -replace 的替换串里 $ 有特殊含义，需转义为 $$；其余字符原样
  $replacement = $dataYaml.Replace('$', '$$')
  # -Encoding UTF8：PS 5.1 默认按 ANSI 读无 BOM 文件，会把 UTF-8 中文注释读成乱码
  $content = (Get-Content $src -Raw -Encoding UTF8) -replace '__DSH_DATA__', $replacement
  $content = ($content -replace "`r`n", "`n")
  $changed = -not (Test-Path $dst)
  if (-not $changed) {
    $changed = ((Get-Content $dst -Raw) -ne $content)
  }
  if ($changed) {
    # 无 BOM 写入，避免 YAML 解析器读到 BOM
    [System.IO.File]::WriteAllText($dst, $content, (New-Object System.Text.UTF8Encoding($false)))
    Ok "已由 machines\windows.cordis.patch.yml 生成"
  } else {
    Ok "机器层已是最新（windows）"
  }
  # 自检：数据分根覆盖行是否齐全（行 id 一旦被 DSH 改名，这里会响铃）
  $missing = @()
  foreach ($row in @('session-persistence-jsonl', 'attachment-local', 'storage-json', 'credentials', 'spill-local')) {
    if (-not (Select-String -Path $dst -Pattern "id: $row" -Quiet)) { $missing += $row }
  }
  if (Select-String -Path $dst -Pattern '__DSH_DATA__' -Quiet) {
    Warn "机器层里仍有未替换的 __DSH_DATA__ 占位符，请检查 machines\windows.cordis.patch.yml"
  } elseif ($missing.Count -gt 0) {
    Warn "机器层缺少数据分根覆盖行：$($missing -join ', ') —— 这些数据会退回 `$DSH_HOME 内"
  } else {
    Ok "数据分根覆盖行齐全（5/5），数据根 = $DataDir"
  }
} else {
  Warn "缺少 machines\windows.cordis.patch.yml，机器层未生成"
}

# ---------------------------------------------------------------------------
Step "6/7 外部工具体检（只报告，不安装）"
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
Step "7/7 密钥体检（只报告，绝不写入）"
foreach ($key in @('TX_GATEWAY_API_KEY', 'DEEPSEEK_API_KEY')) {
  $envValue = [Environment]::GetEnvironmentVariable($key, 'User')
  if ($envValue) {
    Ok "$key 已从用户环境变量提供"
  } elseif ((Test-Path $credsData) -and (Select-String -Path $credsData -Pattern $key -Quiet)) {
    Ok "$key 已在数据根 .credentials.yaml 中"
  } elseif ((Test-Path $credsHome) -and (Select-String -Path $credsHome -Pattern $key -Quiet)) {
    Ok "$key 在旧位置 .credentials.yaml 中（配置已指向数据根，注意迁移）"
  } else {
    Warn "$key 缺失：设置用户环境变量，或确认 $DataDir\.credentials.yaml 已同步"
  }
}

Write-Host "`n完成。数据分根与机器层改动需要重启 Desktop 才会生效；首次安装还需重开终端让 DSH_HOME 生效。"
Write-Host "备份数据（建议定期执行）：.\backup.ps1   数据根：$DataDir"
