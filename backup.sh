#!/usr/bin/env bash
# dsh-config 数据备份 —— 把仓库之外的数据根打包成带时间戳的归档。
#
# 备份内容：数据根（默认 <本仓库目录>-data，即 ~/.dsh-data）——
#           会话历史、附件、存储状态、明文凭据。
# 不含：配置（已在 git 远端）、dsh-runtimes 与 node_modules（可再生）。
#
# 用法：
#   ./backup.sh                    备份到 ~/dsh-backups，保留最近 10 份
#   ./backup.sh --out /Volumes/USB 指定输出目录
#   ./backup.sh --keep 20          指定保留份数
#   ./backup.sh --list             列出已有备份
#
# 环境变量：DSH_BACKUP_DIR 同 --out；DSH_BACKUP_KEEP 同 --keep
#
# 恢复：先退出 DSH，再
#   tar -xzf <归档> -C <数据根的父目录>
#
# 说明：应用运行中备份是安全的（逐文件读取），但正在写入的那个会话，其最后几条
# 事件可能不完整；需要完全一致时先退出 DSH 再备份。
set -euo pipefail

# Plugin archives are separate from data archives containing credentials.
if [ "${1:-}" = "--plugins" ]; then
  shift
  exec "${DSH_TRANSFER_PYTHON:-python3}" "$(dirname "${BASH_SOURCE[0]}")/plugin-transfer.py" backup "$@"
fi

HOME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$HOME_DIR-data"
OUT_DIR="${DSH_BACKUP_DIR:-$HOME/dsh-backups}"
KEEP="${DSH_BACKUP_KEEP:-10}"
GLOB="dsh-data-*"

say() { printf '%s\n' "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --out)
      OUT_DIR="${2:?--out 需要一个目录}"
      shift 2
      ;;
    --keep)
      KEEP="${2:?--keep 需要一个数字}"
      shift 2
      ;;
    --list)
      if compgen -G "$OUT_DIR/$GLOB.tar.gz" > /dev/null; then
        ls -lht "$OUT_DIR"/$GLOB.tar.gz | awk '{ printf "  %8s  %s\n", $5, $9 }'
      else
        say "（$OUT_DIR 下暂无备份）"
      fi
      exit 0
      ;;
    -h | --help)
      sed -n '2,19p' "$0"
      exit 0
      ;;
    *)
      printf '未知参数：%s（用 --help 看用法）\n' "$1" >&2
      exit 2
      ;;
  esac
done

if [ ! -d "$DATA_DIR" ]; then
  printf '找不到数据根 %s —— 请先运行 ./install.sh\n' "$DATA_DIR" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
# 归档里含明文凭据：目录与文件都收紧权限
chmod 700 "$OUT_DIR" 2> /dev/null || true
ARCHIVE="$OUT_DIR/dsh-data-$(date +%Y%m%d-%H%M%S).tar.gz"

tar -czf "$ARCHIVE" -C "$(dirname "$DATA_DIR")" "$(basename "$DATA_DIR")"
chmod 600 "$ARCHIVE" 2> /dev/null || true

# 校验：归档必须真的能列出内容，否则视为失败并删除半成品
ENTRIES="$(tar -tzf "$ARCHIVE" | wc -l | tr -d ' ')"
if [ "$ENTRIES" -lt 2 ]; then
  printf '归档校验失败（条目数 %s），已删除：%s\n' "$ENTRIES" "$ARCHIVE" >&2
  rm -f "$ARCHIVE"
  exit 1
fi
say "已备份 → $ARCHIVE"
say "  条目 ${ENTRIES}，大小 $(du -h "$ARCHIVE" | cut -f1)"

# 保留最近 KEEP 份
PRUNED=0
while IFS= read -r old; do
  rm -f "$old"
  PRUNED=$((PRUNED + 1))
done < <(ls -1t "$OUT_DIR"/$GLOB.tar.gz 2> /dev/null | tail -n +"$((KEEP + 1))")
if [ "$PRUNED" -gt 0 ]; then
  say "  已清理 $PRUNED 份最旧备份（保留 $KEEP 份）"
fi

say ""
say "恢复方式（先完全退出 DSH）："
say "  rm -rf \"$DATA_DIR\" && tar -xzf \"$ARCHIVE\" -C \"$(dirname "$DATA_DIR")\""
say "归档内含明文 .credentials.yaml —— 请存放在安全位置。"
