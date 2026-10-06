#!/usr/bin/env bash
# dsh-config installer —— 幂等脚本。
#
# 首次安装与每次 `git pull` 之后执行的是同一个脚本，由 hooks/post-merge 自动调用，
# 也可以随时手动运行。每一步都「存在即跳过」，重复执行无副作用。
#
# 它只做三件事：把机器专属配置落位（含数据分根）、迁移既有数据、体检外部工具与密钥。
# 不下载可执行文件，不写入任何密钥。
set -euo pipefail

HOME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$HOME_DIR-data"
OS_NAME="$(uname -s)"

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
ok()   { printf '   ok    %s\n' "$*"; }
warn() { printf '   warn  %s\n' "$*"; }

# ---------------------------------------------------------------------------
step "1/7 解析 DSH home"
say "   本仓库（= DSH home）: $HOME_DIR"
say "   数据根（仓库之外）:  $DATA_DIR"
if [ -n "${DSH_HOME:-}" ]; then
  resolved="$(cd "$DSH_HOME" 2>/dev/null && pwd || printf '%s' "$DSH_HOME")"
  if [ "$resolved" = "$HOME_DIR" ]; then
    ok "DSH_HOME 已指向本仓库"
  else
    warn "当前环境变量 DSH_HOME=$resolved 与本仓库位置不一致"
    warn "二者必须一致，否则本仓库的配置不会生效"
  fi
else
  warn "当前 shell 未设置 DSH_HOME（第 2 步会持久化，需要重开终端）"
fi

# ---------------------------------------------------------------------------
step "2/7 持久化 DSH_HOME"
if [ "$OS_NAME" = "Darwin" ] || [ "$OS_NAME" = "Linux" ]; then
  PROFILE_FILE="${ZDOTDIR:-$HOME}/.zprofile"
  WANT="export DSH_HOME=\"$HOME_DIR\""
  if [ ! -e "$PROFILE_FILE" ]; then
    : > "$PROFILE_FILE"
  fi
  if grep -qs '^export DSH_HOME=' "$PROFILE_FILE"; then
    HAVE="$(grep -s '^export DSH_HOME=' "$PROFILE_FILE" | tail -1)"
    if [ "$HAVE" = "$WANT" ]; then
      ok "$PROFILE_FILE 已包含正确的 DSH_HOME"
    else
      warn "$PROFILE_FILE 已存在不同的设置：$HAVE"
      warn "请手动改为：$WANT"
    fi
  else
    printf '\n# DeepSeek Harness home（由 dsh-config/install.sh 写入）\n%s\n' "$WANT" >> "$PROFILE_FILE"
    ok "已写入 $PROFILE_FILE —— 重开终端后生效"
  fi
else
  warn "非 macOS/Linux，请改用 install.ps1"
fi

# ---------------------------------------------------------------------------
step "3/7 安装 git hook（pull 后自动执行本脚本）"
if [ -d "$HOME_DIR/.git" ]; then
  git -C "$HOME_DIR" config core.hooksPath hooks
  chmod +x "$HOME_DIR/hooks/post-merge" 2>/dev/null || true
  chmod +x "$HOME_DIR/install.sh" 2>/dev/null || true
  ok "core.hooksPath = hooks"
else
  warn "不是 git 仓库，跳过（先 git init 或 git clone）"
fi

# ---------------------------------------------------------------------------
step "4/7 准备数据根（仓库之外的不可再生数据）"
# 会话记录/附件/存储/凭据都放在这里，而不是 $DSH_HOME 内。
# 于是仓库里的 `git clean -x` 之类的操作永远不可能删到它们。
if [ -d "$DATA_DIR" ]; then
  ok "$DATA_DIR 已存在"
else
  mkdir -p "$DATA_DIR"
  ok "已创建 $DATA_DIR"
fi
# 一次性迁移：只在目标缺失时复制，绝不覆盖已有数据（幂等，可安全重复执行）
for SUB in sessions attachments storages; do
  if [ -e "$HOME_DIR/$SUB" ] && [ ! -e "$DATA_DIR/$SUB" ]; then
    cp -R "$HOME_DIR/$SUB" "$DATA_DIR/$SUB"
    ok "已迁移 $SUB → $DATA_DIR/$SUB"
  fi
done
if [ -f "$DATA_DIR/.credentials.yaml" ]; then
  chmod 600 "$DATA_DIR/.credentials.yaml" 2>/dev/null || true
  ok "凭据已在数据根（权限已确保 600）"
elif [ -f "$HOME_DIR/.credentials.yaml" ]; then
  cp "$HOME_DIR/.credentials.yaml" "$DATA_DIR/.credentials.yaml"
  chmod 600 "$DATA_DIR/.credentials.yaml" 2>/dev/null || true
  ok "已迁移 .credentials.yaml（权限 600）"
else
  ok "尚无凭据文件（可用环境变量提供密钥）"
fi
if [ -e "$HOME_DIR/sessions" ] && [ -e "$DATA_DIR/sessions" ]; then
  say "   提示：$HOME_DIR/sessions 仍在原处，仅作安全网；确认新布局正常后可自行删除"
fi

# ---------------------------------------------------------------------------
step "5/7 生成机器层 \$DSH_HOME/cordis.patch.yml"
case "$OS_NAME" in
  Darwin) MACHINE_OS="macos" ;;
  Linux)  MACHINE_OS="linux" ;;
  *)      MACHINE_OS="" ;;
esac
SRC="$HOME_DIR/machines/$MACHINE_OS.cordis.patch.yml"
if [ -n "$MACHINE_OS" ] && [ -f "$SRC" ]; then
  TMP_FILE="$(mktemp)"
  DATA_ESC="${DATA_DIR//&/\\&}"
  sed "s|__DSH_DATA__|$DATA_ESC|g" "$SRC" > "$TMP_FILE"
  if [ -f "$HOME_DIR/cordis.patch.yml" ] && cmp -s "$TMP_FILE" "$HOME_DIR/cordis.patch.yml"; then
    ok "机器层已是最新（${MACHINE_OS}）"
    rm -f "$TMP_FILE"
  else
    mv "$TMP_FILE" "$HOME_DIR/cordis.patch.yml"
    ok "已由 machines/${MACHINE_OS}.cordis.patch.yml 生成"
  fi
  # 自检：数据分根覆盖行是否齐全（行 id 一旦被 DSH 改名，这里会响铃）
  MISSING=""
  for ROW in session-persistence-jsonl attachment-local storage-json credentials spill-local; do
    grep -qs "id: $ROW" "$HOME_DIR/cordis.patch.yml" || MISSING="$MISSING $ROW"
  done
  if grep -qs '__DSH_DATA__' "$HOME_DIR/cordis.patch.yml"; then
    warn "机器层里仍有未替换的 __DSH_DATA__ 占位符，请检查 machines/${MACHINE_OS}.cordis.patch.yml"
  elif [ -n "$MISSING" ]; then
    warn "机器层缺少数据分根覆盖行：$MISSING —— 这些数据会退回 \$DSH_HOME 内"
  else
    ok "数据分根覆盖行齐全（5/5），数据根 = $DATA_DIR"
  fi
else
  warn "缺少 machines/${MACHINE_OS:-<未识别平台>}.cordis.patch.yml，机器层未生成"
fi

# ---------------------------------------------------------------------------
step "6/7 外部工具体检（只报告，不安装）"
PLAYWRITER_ENTRY="$HOME/.local/lib/node_modules/playwriter/bin.js"
if [ -f "$PLAYWRITER_ENTRY" ]; then
  ok "playwriter 入口存在：$PLAYWRITER_ENTRY"
else
  if [ "$MACHINE_OS" = "macos" ]; then
    warn "缺少 $PLAYWRITER_ENTRY —— 机器层里的路径需要修正，或先安装："
    warn "  npm i -g --prefix \"\$HOME/.local\" playwriter"
  fi
fi
EXT_DIR="$HOME/Library/Application Support/Google/Chrome/Default/Extensions/jfeammnjpkecdekppnclgkkffahnhfhe"
if [ "$MACHINE_OS" = "macos" ]; then
  if [ -d "$EXT_DIR" ]; then
    ok "Chrome 已安装 Playwriter 扩展"
  else
    warn "Chrome 未安装 Playwriter 扩展（chrome://extensions → 加载已解压的扩展程序）"
    warn "  扩展目录：$HOME/.local/lib/node_modules/playwriter/dist/extension"
  fi
fi

# ---------------------------------------------------------------------------
step "7/7 密钥体检（只报告，绝不写入）"
for KEY in TX_GATEWAY_API_KEY DEEPSEEK_API_KEY; do
  if [ -n "${!KEY:-}" ]; then
    ok "$KEY 已从环境变量提供"
  elif [ -f "$DATA_DIR/.credentials.yaml" ] && grep -qs "$KEY" "$DATA_DIR/.credentials.yaml"; then
    ok "$KEY 已在数据根 .credentials.yaml 中"
  elif [ -f "$HOME_DIR/.credentials.yaml" ] && grep -qs "$KEY" "$HOME_DIR/.credentials.yaml"; then
    ok "$KEY 在旧位置 .credentials.yaml 中（配置已指向数据根，注意迁移）"
  else
    warn "$KEY 缺失：在 shell 里导出，或确认 $DATA_DIR/.credentials.yaml 已同步"
  fi
done

# ---------------------------------------------------------------------------
printf '\n完成。'
if [ "$MACHINE_OS" = "macos" ] || [ "$MACHINE_OS" = "linux" ]; then
  printf '数据分根与机器层改动需要重启 DSH 才会生效；首次安装还需重开终端让 DSH_HOME 生效。\n'
else
  printf '\n'
fi
printf '备份数据（建议定期执行）：./backup.sh   数据根：%s\n' "$DATA_DIR"
