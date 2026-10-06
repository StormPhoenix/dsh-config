#!/usr/bin/env bash
# dsh-config installer —— 幂等脚本。
#
# 首次安装与每次 `git pull` 之后执行的是同一个脚本，由 hooks/post-merge 自动调用，
# 也可以随时手动运行。每一步都「存在即跳过」，重复执行无副作用。
#
# 它只做配置落位与体检：不下载可执行文件，不写入任何密钥。
set -euo pipefail

HOME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS_NAME="$(uname -s)"

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
ok()   { printf '   ok    %s\n' "$*"; }
warn() { printf '   warn  %s\n' "$*"; }

# ---------------------------------------------------------------------------
step "1/6 解析 DSH home"
say "   本仓库（= DSH home）: $HOME_DIR"
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
step "2/6 持久化 DSH_HOME"
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
step "3/6 安装 git hook（pull 后自动执行本脚本）"
if [ -d "$HOME_DIR/.git" ]; then
  git -C "$HOME_DIR" config core.hooksPath hooks
  chmod +x "$HOME_DIR/hooks/post-merge" 2>/dev/null || true
  chmod +x "$HOME_DIR/install.sh" 2>/dev/null || true
  ok "core.hooksPath = hooks"
else
  warn "不是 git 仓库，跳过（先 git init 或 git clone）"
fi

# ---------------------------------------------------------------------------
step "4/6 生成机器层 \$DSH_HOME/cordis.patch.yml"
case "$OS_NAME" in
  Darwin) MACHINE_OS="macos" ;;
  Linux)  MACHINE_OS="linux" ;;
  *)      MACHINE_OS="" ;;
esac
SRC="$HOME_DIR/machines/$MACHINE_OS.cordis.patch.yml"
if [ -n "$MACHINE_OS" ] && [ -f "$SRC" ]; then
  if [ -f "$HOME_DIR/cordis.patch.yml" ] && cmp -s "$SRC" "$HOME_DIR/cordis.patch.yml"; then
    ok "机器层已是最新（$MACHINE_OS）"
  else
    cp "$SRC" "$HOME_DIR/cordis.patch.yml"
    ok "已由 machines/$MACHINE_OS.cordis.patch.yml 生成"
  fi
else
  warn "缺少 machines/${MACHINE_OS:-<未识别平台>}.cordis.patch.yml，机器层未生成"
fi

# ---------------------------------------------------------------------------
step "5/6 外部工具体检（只报告，不安装）"
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
step "6/6 密钥体检（只报告，绝不写入）"
for KEY in TX_GATEWAY_API_KEY DEEPSEEK_API_KEY; do
  if [ -n "${!KEY:-}" ]; then
    ok "$KEY 已从环境变量提供"
  elif [ -f "$HOME_DIR/.credentials.yaml" ] && grep -qs "$KEY" "$HOME_DIR/.credentials.yaml"; then
    ok "$KEY 已在本机 .credentials.yaml 中"
  else
    warn "$KEY 缺失：在 shell 里导出，或确认 \$DSH_HOME/.credentials.yaml 已同步"
  fi
done

# ---------------------------------------------------------------------------
printf '\n完成。'
if [ "$OS_NAME" = "Darwin" ] || [ "$OS_NAME" = "Linux" ]; then
  printf '若这是首次安装，请重开终端让 DSH_HOME 生效。\n'
else
  printf '\n'
fi
