# dsh-config

DeepSeek Harness（DSH）的个人配置仓库。**这个目录同时就是 DSH 的 home（`$DSH_HOME`）**，因此 `git pull` 之后配置就位，无需任何拷贝或链接。

目的：在多台机器（macOS / Windows）之间共享同一套 DSH 配置 —— LLM provider 路由、模型表、默认模型、插件（MCP 等）——并且不受 DSH 源码仓库频繁更新、重建、`pnpm run clean` 的影响。

## 目录结构

```
$DSH_HOME/                          # = 本仓库的 clone 目录，例如 ~/.dsh
├── .gitignore                      # 白名单：只跟踪配置与脚本
├── install.sh / install.ps1        # 幂等安装脚本（首次 + 每次 pull 后运行）
├── hooks/post-merge                # git hook：pull 之后自动执行上面的脚本
├── machines/
│   ├── macos.cordis.patch.yml      # macOS 机器层
│   └── windows.cordis.patch.yml    # Windows 机器层
├── cordis.patch.yml                # ← 由脚本按平台从 machines/ 生成（不跟踪）
└── profiles/
    └── desktop/cordis.patch.yml    # 共享层：所有机器一致的配置
```

其余内容（`sessions/`、`storages/`、`attachments/`、`.credentials.yaml`、`dsh-runtimes/`、`node_modules/`）都是本机运行时数据，被 `.gitignore` 排除，永不入库。

## 分层：配置放哪里

DSH 按顺序叠加四层，**后一层按行覆盖前一层**：

| 顺序 | 层 | 本仓库对应文件 | 放什么 |
|---|---|---|---|
| 1 | bundle 层 | （无） | 由 DSH 安装包提供 |
| 2 | profile 层 | `profiles/desktop/cordis.patch.yml` | **所有机器一致**的配置：LLM 路由、模型表、默认模型、跨平台插件行 |
| 3 | home 层 | `cordis.patch.yml`（由 `machines/<os>.cordis.patch.yml` 生成） | **本机专属**：绝对路径、OS 特有的插件行 |
| 4 | `--patch` | （无） | 单次启动的临时覆盖，不要用来存个人配置 |

判断标准很简单：**行里出现绝对路径或 OS 差异 → 放机器层；否则放共享层。**

## 新机器首次使用

```sh
# macOS / Linux
git clone git@github.com:StormPhoenix/dsh-config.git "$HOME/.dsh"
cd "$HOME/.dsh" && ./install.sh
```

```powershell
# Windows (PowerShell)
git clone git@github.com:StormPhoenix/dsh-config.git "$env:USERPROFILE\.dsh"
cd "$env:USERPROFILE\.dsh"; .\install.ps1
```

之后**重开终端**（让 `DSH_HOME` 生效）；如果之前已经启动过 Desktop，也重启一次。

首次这两条命令无法再自动化：脚本必须先存在于 home 里，而 home 的位置本身由 `DSH_HOME` 决定。

DSH 源码仓库照常克隆和构建（`pnpm install`、`pnpm run build` / `pnpm run dev:desktop`），与本仓库互不影响。

## 日常同步

**机器 A（改配置）**

改完 `~/.dsh/profiles/desktop/cordis.patch.yml` —— 无论直接编辑，还是在 DSH 设置页里改（设置页写的就是这个文件）—— 然后：

```sh
cd ~/.dsh && git add -A && git commit -m "..." && git push
```

**机器 B（取配置）**

```sh
cd ~/.dsh && git pull
```

`pull` 之后 `hooks/post-merge` 会自动执行 `install.sh` / `install.ps1`：按当前平台重新生成机器层、体检外部工具与密钥。

生效时机：patch 改动通常由 HMR 即时生效（新增一行 MCP，进程会立刻被拉起），个别结构性改动重启应用即可。

## 红线

1. **永远不要在本仓库运行 `git clean -xdf`。** 会话记录、凭据、附件都和配置在同一个目录树里，`-x` 会连忽略的文件一起删掉。同理慎用 `git checkout -f` / `git reset --hard`。
2. **密钥不入库。** `.credentials.yaml` 是明文，已被忽略。推荐做法是根本不搬它：在 `~/.zprofile`（macOS）或用户环境变量（Windows）里导出 `TX_GATEWAY_API_KEY` / `DEEPSEEK_API_KEY`。
3. **同一时间只在一台机器上改配置**，改完立刻 commit + push。两台同时改同一个文件必然冲突。
4. **`post-merge` 会自动执行代码。** 本仓库是私有的、只有你自己推送，所以默认开启；如果将来有其他人能写这个仓库，请关闭自动执行：
   ```sh
   git -C ~/.dsh config --unset core.hooksPath
   ```
   改为手动运行 `./install.sh`。

## 排错

| 现象 | 检查 |
|---|---|
| 配置完全不生效 | `echo $DSH_HOME` 是否等于 `~/.dsh`；桌面应用需重启，终端需重开 |
| pull 之后脚本没跑 | `git -C ~/.dsh config core.hooksPath` 应输出 `hooks` |
| 机器层没更新 | `ls ~/.dsh/cordis.patch.yml` 存在且内容等于 `machines/<os>.cordis.patch.yml` |
| Windows 上某个插件行报错 | Windows 通常没有 `HOME`，表达式要写成 `!!js (process.env.HOME ?? process.env.USERPROFILE)` |
| 生效了但某些行被覆盖 | 检查机器层是否也定义了同一个 `id`（机器层优先级更高） |

## 已知限制

- **通过界面安装的 bundle（插件包）不会跟着同步。** `profiles/desktop/package.json` 里的 `dsh.profile.bundles` 由 DSH 自己维护，容易被 `pnpm install` 改写，所以不在跟踪范围内。如果你以后用 `dsh plugin add` 装了外部插件包，需要在每台机器上分别装一次。纯配置（本仓库目前的全部内容）不受影响。
- **`dsh-runtimes/`（离线运行时，约 370MB）不迁移**，新 home 首次需要时会自行安装。

## 备份

首次迁移前的备份保留在 `~/.dsh-backup-<时间戳>/`（含当时的 `cordis.patch.yml`、历史 `.bak-*` 和明文 `credentials.yaml`）。确认新方案稳定后可自行删除。
