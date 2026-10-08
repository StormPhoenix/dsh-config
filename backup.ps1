# dsh-config 数据备份 (Windows) —— 与 backup.sh 行为一致。
#
# 备份内容：数据根（默认 <本仓库目录>-data，即 %USERPROFILE%\.dsh-data）——
#           会话历史、附件、存储状态、明文凭据。
# 不含：配置（已在 git 远端）、dsh-runtimes 与 node_modules（可再生）。
#
# 用法：
#   .\backup.ps1                    备份到 %USERPROFILE%\dsh-backups，保留最近 10 份
#   .\backup.ps1 --out D:\dsh-bak   指定输出目录
#   .\backup.ps1 --keep 20          指定保留份数
#   .\backup.ps1 --list             列出已有备份
#
# 环境变量：DSH_BACKUP_DIR 同 --out；DSH_BACKUP_KEEP 同 --keep
#
# 恢复：先退出 DSH，再解开归档覆盖数据根（见脚本末尾打印的命令）。
$ErrorActionPreference = 'Stop'

$HomeDir = $PSScriptRoot
$DataDir = "$HomeDir-data"
$OutDir = if ($env:DSH_BACKUP_DIR) { $env:DSH_BACKUP_DIR } else { Join-Path $env:USERPROFILE 'dsh-backups' }
$Keep = if ($env:DSH_BACKUP_KEEP) { [int]$env:DSH_BACKUP_KEEP } else { 10 }

function Say ($m) { Write-Host $m }

for ($i = 0; $i -lt $args.Count; $i++) {
  switch ($args[$i]) {
    '--out' { $OutDir = $args[++$i] }
    '--keep' { $Keep = [int]$args[++$i] }
    '--list' {
      if ((Test-Path $OutDir) -and (Get-ChildItem $OutDir -Filter 'dsh-data-*' -ErrorAction SilentlyContinue)) {
        Get-ChildItem $OutDir -Filter 'dsh-data-*' | Sort-Object LastWriteTime -Descending | ForEach-Object {
          Say ("  {0,10}  {1}" -f $_.Length, $_.Name)
        }
      } else {
        Say "（$OutDir 下暂无备份）"
      }
      exit 0
    }
    '--help' {
      Say "用法: .\backup.ps1 [--out 目录] [--keep 份数] [--list]"
      exit 0
    }
    default { Write-Error "未知参数：$($args[$i])（用 --help 看用法）" }
  }
}

if (-not (Test-Path $DataDir)) {
  Write-Error "找不到数据根 $DataDir —— 请先运行 .\install.ps1"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

# 优先用 Windows 自带的 tar（Win10 1803+），产物与 macOS 的 .tar.gz 一致；
# 没有则退回 Compress-Archive 的 .zip。
if (Get-Command tar -ErrorAction SilentlyContinue) {
  $archive = Join-Path $OutDir "dsh-data-$stamp.tar.gz"
  tar -czf $archive -C (Split-Path $DataDir -Parent) (Split-Path $DataDir -Leaf)
  if ($LASTEXITCODE -ne 0) { Write-Error "tar 打包失败（退出码 $LASTEXITCODE）" }
  $entries = (tar -tzf $archive | Measure-Object -Line).Lines
} else {
  $archive = Join-Path $OutDir "dsh-data-$stamp.zip"
  Compress-Archive -Path $DataDir -DestinationPath $archive -Force
  $entries = (Get-ChildItem $DataDir -Recurse -File | Measure-Object).Count
}

if ($entries -lt 2) {
  Remove-Item $archive -Force
  Write-Error "归档校验失败（条目数 $entries），已删除：$archive"
}
$sizeMB = [math]::Round((Get-Item $archive).Length / 1MB, 2)
Say "已备份 -> $archive"
Say "  条目 ${entries}，大小 ${sizeMB} MB"

# 保留最近 Keep 份
$stale = Get-ChildItem $OutDir -Filter 'dsh-data-*' | Sort-Object LastWriteTime -Descending | Select-Object -Skip $Keep
if ($stale) {
  $stale | Remove-Item -Force
  Say "  已清理 $($stale.Count) 份最旧备份（保留 $Keep 份）"
}

Say ""
Say "恢复方式（先完全退出 DSH）："
if ($archive.EndsWith('.zip')) {
  Say "  Expand-Archive -Path `"$archive`" -DestinationPath `"$(Split-Path $DataDir -Parent)`" -Force"
} else {
  Say "  tar -xzf `"$archive`" -C `"$(Split-Path $DataDir -Parent)`""
}
Say "归档内含明文 .credentials.yaml —— 请存放在安全位置。"
