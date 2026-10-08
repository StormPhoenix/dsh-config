#!/usr/bin/env bash
# dsh-config installer —— 幂等脚本。
#
# 首次安装与每次 `git pull` 之后执行的是同一个脚本，由 hooks/post-merge 自动调用，
# 也可以随时手动运行。每一步都「存在即跳过」，重复执行无副作用。
#
# 它做四件事：把机器专属配置落位（含数据分根）、迁移既有数据、确保记忆插件就位、
# 体检外部工具与密钥。除第 6 步用 pnpm 取一个 npm 包外不下载可执行文件；全程不写入密钥。
set -euo pipefail

# 用法：install.sh [--source-dir <deepseek-harness 源码仓库路径>]
# 路径需含 apps/cli/src/bin.ts；提供后会写入仓库内 gitignored 的 .source-dir
# 记录文件，之后 hooks/post-merge 的无参重跑会自动复用，无需每次指定。
SOURCE_DIR_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --source-dir)
      [ $# -ge 2 ] || { printf '%s\n' 'install.sh: --source-dir 需要一个路径参数' >&2; exit 2; }
      SOURCE_DIR_ARG="$2"
      shift 2
      ;;
    -h|--help)
      printf '用法：install.sh [--source-dir <deepseek-harness 源码仓库路径>]\n'
      exit 0
      ;;
    *)
      printf 'install.sh: 未知参数 %s\n用法：install.sh [--source-dir <路径>]\n' "$1" >&2
      exit 2
      ;;
  esac
done

HOME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$HOME_DIR-data"
OS_NAME="$(uname -s)"

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
ok()   { printf '   ok    %s\n' "$*"; }
warn() { printf '   warn  %s\n' "$*"; }

# ---------------------------------------------------------------------------
step "1/8 解析 DSH home"
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
step "2/8 持久化 DSH_HOME"
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
step "3/8 安装 git hook（pull 后自动执行本脚本）"
if [ -d "$HOME_DIR/.git" ]; then
  git -C "$HOME_DIR" config core.hooksPath hooks
  chmod +x "$HOME_DIR/hooks/post-merge" 2>/dev/null || true
  chmod +x "$HOME_DIR/install.sh" 2>/dev/null || true
  ok "core.hooksPath = hooks"
else
  warn "不是 git 仓库，跳过（先 git init 或 git clone）"
fi

# ---------------------------------------------------------------------------
step "4/8 准备数据根（仓库之外的不可再生数据）"
# 会话记录/附件/存储/凭据/长期记忆都放在这里，而不是 $DSH_HOME 内。
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
step "5/8 生成机器层 \$DSH_HOME/cordis.patch.yml"
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
  for ROW in session-persistence-jsonl attachment-local storage-json credentials spill-local memory; do
    grep -qs "id: $ROW" "$HOME_DIR/cordis.patch.yml" || MISSING="$MISSING $ROW"
  done
  if grep -qs '__DSH_DATA__' "$HOME_DIR/cordis.patch.yml"; then
    warn "机器层里仍有未替换的 __DSH_DATA__ 占位符，请检查 machines/${MACHINE_OS}.cordis.patch.yml"
  elif [ -n "$MISSING" ]; then
    warn "机器层缺少数据分根覆盖行：$MISSING —— 这些数据会退回 \$DSH_HOME 内"
  else
    ok "数据分根覆盖行齐全（6/6），数据根 = $DATA_DIR"
  fi
else
  warn "缺少 machines/${MACHINE_OS:-<未识别平台>}.cordis.patch.yml，机器层未生成"
fi

# ---------------------------------------------------------------------------
step "6/8 记忆插件 dsh-memory@0.1.0（精确版本豁免 + 安装）"
# 为什么需要豁免：该插件声明的 peer 是 ^0.1.0-rc.6（只覆盖 0.1.x），与本机 0.2.x 不匹配，
# 兼容性闸门会拒绝安装。豁免是「包版本 × DSH 版本」双精确的：升级插件或升级 DSH 之后
# 都要重新授予 —— 否则启动时该 bundle 被跳过（记忆功能静默停用，应用本身照常启动）。
# 为什么固定 0.1.0：该包只发布过这一个版本，且已实测在 0.2.1-alpha.1 上写入/召回正常。
# 存储路径由机器层的 memory 行改写到数据根；插件未安装时那一行被静默忽略。
MEM_PKG="dsh-memory@0.1.0"
MEM_ID="dsh-memory"
DSH_MODE=""
DSH_BIN=""
DSH_SRC=""
if [ -n "${DSH_CLI:-}" ]; then
  DSH_MODE="bin"
  DSH_BIN="$DSH_CLI"
elif command -v dsh >/dev/null 2>&1; then
  DSH_MODE="bin"
  DSH_BIN="$(command -v dsh)"
else
  # 源码目录解析顺序：--source-dir 参数 → .source-dir 记录 → DSH_SOURCE_DIR → 常见位置。
  # 记录文件让一次性的参数（或启发式命中）在 hooks/post-merge 无参重跑时也能复用。
  SOURCE_RECORD="$HOME_DIR/.source-dir"
  RECORDED=""
  [ -f "$SOURCE_RECORD" ] && RECORDED="$(tr -d '[:space:]' < "$SOURCE_RECORD")"
  if [ -n "$SOURCE_DIR_ARG" ] && [ ! -f "$SOURCE_DIR_ARG/apps/cli/src/bin.ts" ]; then
    warn "--source-dir 指定的路径缺少 apps/cli/src/bin.ts，不像 deepseek-harness 仓库: $SOURCE_DIR_ARG"
  fi
  for CAND in "$SOURCE_DIR_ARG" "$RECORDED" "${DSH_SOURCE_DIR:-}" "$HOME/Workspace/deepseek-harness" "$HOME/deepseek-harness"; do
    if [ -n "$CAND" ] && [ -f "$CAND/apps/cli/src/bin.ts" ]; then
      DSH_MODE="source"
      DSH_SRC="$(cd "$CAND" && pwd)"
      if [ "$DSH_SRC" != "$RECORDED" ]; then
        printf '%s\n' "$DSH_SRC" > "$SOURCE_RECORD"
        say "   已记录 DSH 源码目录 → $SOURCE_RECORD"
      fi
      break
    fi
  done
fi
# 子进程显式带上 DSH_HOME=本仓库：避免当前 shell 未设置或设错时把插件装到别的 home
dsh_run() {
  if [ "$DSH_MODE" = "source" ]; then
    DSH_HOME="$HOME_DIR" pnpm -C "$DSH_SRC" dsh "$@"
  else
    DSH_HOME="$HOME_DIR" "$DSH_BIN" "$@"
  fi
}
# Node 版本护栏：源码模式经 pnpm 跑 dsh，Node < 22.13 时 pnpm 自身就会崩
# （node:sqlite 等内置模块缺失），脚本只能笼统报「读不到 dsh 版本」。这里提前说清原因。
SKIP_REASON=""
if [ "$DSH_MODE" = "source" ]; then
  NODE_VER="$(node -v 2>/dev/null || true)"
  NODE_MAJOR="$(printf '%s' "$NODE_VER" | sed 's/^v\([0-9][0-9]*\)\..*$/\1/')"
  NODE_MINOR="$(printf '%s' "$NODE_VER" | sed 's/^v[0-9][0-9]*\.\([0-9][0-9]*\)\..*$/\1/')"
  NODE_OK=0
  if [ -n "$NODE_MAJOR" ] && [ -n "$NODE_MINOR" ]; then
    if [ "$NODE_MAJOR" -gt 22 ] || { [ "$NODE_MAJOR" -eq 22 ] && [ "$NODE_MINOR" -ge 13 ]; }; then
      NODE_OK=1
    fi
  fi
  if [ "$NODE_OK" -ne 1 ]; then
    SKIP_REASON="node ${NODE_VER:-缺失} 低于 22.13，源码模式的 pnpm dsh 无法运行（切换 Node 后重跑），跳过 $MEM_PKG"
  fi
fi
if [ -n "$SKIP_REASON" ]; then
  warn "$SKIP_REASON"
elif [ -z "$DSH_MODE" ]; then
  warn "找不到 dsh 命令（打包版 Desktop 不把 CLI 放进 PATH），跳过 $MEM_PKG"
  say "   手动安装（每台机器、每个 profile 各一次）："
  say "     dsh plugin --profile desktop allow-version $MEM_PKG --dsh-version <dsh -V> --accept-risk"
  say "     dsh plugin --profile desktop add $MEM_PKG"
  say "   或用 --source-dir 指定 deepseek-harness 源码仓库路径后重跑本脚本："
  say "     ./install.sh --source-dir ~/Workspace/deepseek-harness"
  say "   （也可设置 DSH_CLI / DSH_SOURCE_DIR 环境变量；命中一次后会记录到 .source-dir，之后 pull 触发的重跑自动复用）"
else
  DSH_VER="$(dsh_run -V 2>/dev/null | tail -1 | tr -d '[:space:]')"
  case "$DSH_VER" in
    0.*|1.*|2.*|3.*) ;;
    *) DSH_VER="" ;;
  esac
  if [ -z "$DSH_VER" ]; then
    warn "读不到 dsh 版本（模式：${DSH_MODE}），跳过 $MEM_PKG"
  else
    TOUCHED=0
    INITIALIZED=0
    for PDIR in "$HOME_DIR"/profiles/*/; do
      [ -d "$PDIR" ] || continue
      [ -f "$PDIR/package.json" ] || continue
      INITIALIZED=$((INITIALIZED + 1))
      PNAME="$(basename "$PDIR")"
      LOG="$(mktemp)"
      if ! dsh_run plugin --profile "$PNAME" allow-version "$MEM_PKG" --dsh-version "$DSH_VER" --accept-risk >"$LOG" 2>&1; then
        if grep -qs 'managed exclusively by the Electron application' "$LOG"; then
          # 设计使然：desktop profile 只归 Electron 应用自己管，CLI 一律拒（apps/cli/src/args.ts）
          warn "$PNAME: 由 Desktop 应用独占管理，CLI 无法代劳（设计使然，不是失败）"
          say "   请在 Desktop 应用内让 agent 用 plugin_manager 工具执行（该工具只在应用内 + 默认智能体组合中存在）："
          say "     action=set_version_exemption target=$MEM_PKG runtimeVersion=$DSH_VER enabled=true acceptRisk=true"
          say "     action=install_bundle        target=$MEM_PKG"
          say "   若没有该工具，见 README「长期记忆」一节的手动步骤"
        else
          warn "$PNAME: 授予 $MEM_PKG 豁免失败（dsh = ${DSH_VER}），错误末 3 行："
          tail -3 "$LOG" | sed 's/^/     /'
        fi
        rm -f "$LOG"
        continue
      fi
      if [ -d "$PDIR/node_modules/$MEM_ID" ]; then
        ok "$PNAME: $MEM_ID 已安装（豁免已确认 = ${DSH_VER}）"
        rm -f "$LOG"
      elif dsh_run plugin --profile "$PNAME" add "$MEM_PKG" >"$LOG" 2>&1; then
        ok "$PNAME: 已安装 ${MEM_PKG}（重启 DSH 后生效）"
        rm -f "$LOG"
      else
        warn "$PNAME: 安装 $MEM_PKG 失败，错误末 3 行："
        tail -3 "$LOG" | sed 's/^/     /'
        say "   手动执行：dsh plugin --profile $PNAME add $MEM_PKG"
        rm -f "$LOG"
      fi
      TOUCHED=$((TOUCHED + 1))
    done
    if [ "$TOUCHED" -eq 0 ] && [ "$INITIALIZED" -eq 0 ]; then
      warn "profile 还没初始化（profiles/*/package.json 不存在），本次跳过 $MEM_PKG"
      say "   新机器首次运行时这是正常的：profile 由 DSH 自己创建，仓库只跟踪 profiles/*/cordis.patch.yml。"
      say "   启动一次 DSH（Desktop 应用，或 dsh --profile <名字>）后再跑一次本脚本，就会自动装上；"
      say "   之后每次 git pull 也会由 hooks/post-merge 自动重跑。"
      say "   注意：desktop profile 即使已初始化，CLI 也无权管理，仍需应用内安装或手动步骤（见 README）。"
    fi
  fi
fi

# ---------------------------------------------------------------------------
step "7/8 外部工具体检（只报告，不安装）"
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
step "8/8 密钥体检（只报告，绝不写入）"
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
  printf '数据分根、机器层与插件改动需要重启 DSH 才会生效；首次安装还需重开终端让 DSH_HOME 生效。\n'
else
  printf '\n'
fi
printf '备份数据（建议定期执行）：./backup.sh   数据根：%s\n' "$DATA_DIR"
