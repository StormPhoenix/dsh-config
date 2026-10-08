# dsh-config installer (Windows) —— 幂等脚本，与 install.sh 行为一致。
#
# 首次安装与每次 `git pull` 之后执行同一个脚本，由 hooks/post-merge 自动调用。
# 做四件事：把机器专属配置落位（含数据分根）、迁移既有数据、确保记忆插件就位、
# 体检外部工具与密钥。除第 6 步用 pnpm 取一个 npm 包外不下载可执行文件；全程不写入密钥。
$ErrorActionPreference = 'Stop'

$HomeDir = $PSScriptRoot
$DataDir = "$HomeDir-data"

function Say  ($m) { Write-Host $m }
function Step ($m) { Write-Host "`n== $m" }
function Ok   ($m) { Write-Host "   ok    $m" }
function Warn ($m) { Write-Host "   warn  $m" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
Step "1/8 解析 DSH home"
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
Step "2/8 持久化 DSH_HOME（用户级环境变量）"
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
Step "3/8 安装 git hook（pull 后自动执行本脚本）"
if (Test-Path (Join-Path $HomeDir '.git')) {
  git -C $HomeDir config core.hooksPath hooks
  Ok "core.hooksPath = hooks"
} else {
  Warn "不是 git 仓库，跳过"
}

# ---------------------------------------------------------------------------
Step "4/8 准备数据根（仓库之外的不可再生数据）"
# 会话记录/附件/存储/凭据/长期记忆都放在这里，而不是 $DSH_HOME 内。
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
Step "5/8 生成机器层 `$DSH_HOME/cordis.patch.yml"
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
  foreach ($row in @('session-persistence-jsonl', 'attachment-local', 'storage-json', 'credentials', 'spill-local', 'memory')) {
    if (-not (Select-String -Path $dst -Pattern "id: $row" -Quiet)) { $missing += $row }
  }
  if (Select-String -Path $dst -Pattern '__DSH_DATA__' -Quiet) {
    Warn "机器层里仍有未替换的 __DSH_DATA__ 占位符，请检查 machines\windows.cordis.patch.yml"
  } elseif ($missing.Count -gt 0) {
    Warn "机器层缺少数据分根覆盖行：$($missing -join ', ') —— 这些数据会退回 `$DSH_HOME 内"
  } else {
    Ok "数据分根覆盖行齐全（6/6），数据根 = $DataDir"
  }
} else {
  Warn "缺少 machines\windows.cordis.patch.yml，机器层未生成"
}

# ---------------------------------------------------------------------------
Step "6/8 记忆插件 dsh-memory@0.1.0（精确版本豁免 + 安装）"
# 为什么需要豁免：该插件声明的 peer 是 ^0.1.0-rc.6（只覆盖 0.1.x），与本机 0.2.x 不匹配，
# 兼容性闸门会拒绝安装。豁免是「包版本 × DSH 版本」双精确的：升级插件或升级 DSH 之后
# 都要重新授予 —— 否则启动时该 bundle 被跳过（记忆功能静默停用，应用本身照常启动）。
# 为什么固定 0.1.0：该包只发布过这一个版本，且已实测在 0.2.1-alpha.1 上写入/召回正常。
# 存储路径由机器层的 memory 行改写到数据根；插件未安装时那一行被静默忽略。
$memPkg = 'dsh-memory@0.1.0'
$memId = 'dsh-memory'
$dshMode = ''
$dshBin = ''
$dshSrc = ''
if ($env:DSH_CLI) {
  $dshMode = 'bin'
  $dshBin = $env:DSH_CLI
} elseif (Get-Command dsh -ErrorAction SilentlyContinue) {
  $dshMode = 'bin'
  $dshBin = (Get-Command dsh).Source
} else {
  $cands = @($env:DSH_SOURCE_DIR, (Join-Path $env:USERPROFILE 'Workspace\deepseek-harness'), (Join-Path $env:USERPROFILE 'deepseek-harness'))
  foreach ($c in $cands) {
    if ($c -and (Test-Path (Join-Path $c 'apps\cli\src\bin.ts'))) {
      $dshMode = 'source'
      $dshSrc = $c
      break
    }
  }
}
function Invoke-Dsh {
  param([Parameter(ValueFromRemainingArguments = $true)] $Rest)
  if ($dshMode -eq 'source') { & pnpm -C $dshSrc dsh @Rest } else { & $dshBin @Rest }
}
if (-not $dshMode) {
  Warn "找不到 dsh 命令（打包版 Desktop 不把 CLI 放进 PATH），跳过 $memPkg"
  Say "   手动安装（每台机器、每个 profile 各一次）："
  Say "     dsh plugin --profile desktop allow-version $memPkg --dsh-version <dsh -V> --accept-risk"
  Say "     dsh plugin --profile desktop add $memPkg"
  Say "   或设置 DSH_CLI（dsh 可执行文件路径）/ DSH_SOURCE_DIR（DSH 源码目录）后重跑本脚本"
} else {
  # 原生命令写到 stderr 的内容在 $ErrorActionPreference='Stop' 下可能被当成终止错误，这里放宽
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  # 子进程显式带上 DSH_HOME=本仓库：避免未设置或设错时把插件装到别的 home
  $prevHome = $env:DSH_HOME
  $env:DSH_HOME = $HomeDir
  $dshVer = (Invoke-Dsh -V 2>$null | Select-Object -Last 1)
  if ($dshVer) { $dshVer = $dshVer.Trim() }
  if (-not $dshVer -or $dshVer -notmatch '^[0-9]+\.[0-9]') {
    Warn "读不到 dsh 版本（模式：${dshMode}），跳过 $memPkg"
  } else {
    $touched = 0
    foreach ($pdir in (Get-ChildItem (Join-Path $HomeDir 'profiles') -Directory -ErrorAction SilentlyContinue)) {
      if (-not (Test-Path (Join-Path $pdir.FullName 'package.json'))) { continue }
      $name = $pdir.Name
      $log = [System.IO.Path]::GetTempFileName()
      Invoke-Dsh plugin --profile $name allow-version $memPkg --dsh-version $dshVer --accept-risk *> $log
      if ($LASTEXITCODE -ne 0) {
        if (Select-String -Path $log -Pattern 'managed exclusively by the Electron application' -Quiet) {
          # 设计使然：desktop profile 只归 Electron 应用自己管，CLI 一律拒（apps/cli/src/args.ts）
          Warn "${name}: 由 Desktop 应用独占管理，CLI 无法代劳（设计使然，不是失败）"
          Say "   请在 Desktop 应用内让 agent 用 plugin_manager 工具执行（该工具只在应用内 + 默认智能体组合中存在）："
          Say "     action=set_version_exemption target=$memPkg runtimeVersion=$dshVer enabled=true acceptRisk=true"
          Say "     action=install_bundle        target=$memPkg"
          Say "   若没有该工具，见 README「长期记忆」一节的手动步骤"
        } else {
          Warn "${name}: 授予 $memPkg 豁免失败（dsh = ${dshVer}），错误末 3 行："
          Get-Content $log -Tail 3 | ForEach-Object { Say "     $_" }
        }
        Remove-Item $log -Force
        continue
      }
      if (Test-Path (Join-Path $pdir.FullName "node_modules\$memId")) {
        Ok "${name}: $memId 已安装（豁免已确认 = ${dshVer}）"
        Remove-Item $log -Force
      } else {
        Invoke-Dsh plugin --profile $name add $memPkg *> $log
        if ($LASTEXITCODE -eq 0) {
          Ok "${name}: 已安装 ${memPkg}（重启 DSH 后生效）"
        } else {
          Warn "${name}: 安装 $memPkg 失败，错误末 3 行："
          Get-Content $log -Tail 3 | ForEach-Object { Say "     $_" }
          Say "   手动执行：dsh plugin --profile $name add $memPkg"
        }
        Remove-Item $log -Force
      }
      $touched++
    }
    if ($touched -eq 0) {
      Warn "profile 还没初始化（profiles\*\package.json 不存在），本次跳过 $memPkg"
      Say "   新机器首次运行时这是正常的：profile 由 DSH 自己创建，仓库只跟踪 profiles\*\cordis.patch.yml。"
      Say "   启动一次 DSH（Desktop 应用，或 dsh --profile <名字>）后再跑一次本脚本，就会自动装上；"
      Say "   之后每次 git pull 也会由 hooks/post-merge 自动重跑。"
      Say "   注意：desktop profile 即使已初始化，CLI 也无权管理，仍需应用内安装或手动步骤（见 README）。"
    }
  }
  $env:DSH_HOME = $prevHome
  $ErrorActionPreference = $prevEap
}

# ---------------------------------------------------------------------------
Step "7/8 外部工具体检（只报告，不安装）"
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
Step "8/8 密钥体检（只报告，绝不写入）"
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

Write-Host "`n完成。数据分根、机器层与插件改动需要重启 Desktop 才会生效；首次安装还需重开终端让 DSH_HOME 生效。"
Write-Host "备份数据（建议定期执行）：.\backup.ps1   数据根：$DataDir"
