# dsh-config

DeepSeek Harness（DSH）的个人配置仓库。**这个目录同时就是 DSH 的 home（`$DSH_HOME`）**，因此 `git pull` 之后配置就位，无需任何拷贝或链接。而**不可再生的运行时数据（会话、附件、凭据、存储）放在仓库之外的 `~/.dsh-data/`**，见「数据分根」——所以即使在这个仓库里误用 `git clean -x`，数据也不会被删。

目的：在多台机器（macOS / Windows）之间共享同一套 DSH 配置 —— LLM provider 路由、模型表、默认模型、插件（MCP 等）——并且不受 DSH 源码仓库频繁更新、重建、`pnpm run clean` 的影响。

## 目录结构

```
$DSH_HOME/                          # = 本仓库的 clone 目录，例如 ~/.dsh
├── .gitignore                      # 白名单：只跟踪配置与脚本
├── install.sh / install.ps1        # 幂等安装脚本（首次 + 每次 pull 后运行）
├── backup.sh / backup.ps1          # 数据备份（打包数据根，默认保留最近 10 份）
├── hooks/post-merge                # git hook：pull 之后自动执行上面的脚本
├── machines/
│   ├── macos.cordis.patch.yml      # macOS 机器层（含数据分根覆盖行）
│   └── windows.cordis.patch.yml    # Windows 机器层（含数据分根覆盖行）
├── cordis.patch.yml                # ← 由脚本按平台从 machines/ 生成（不跟踪）
└── profiles/
    └── desktop/cordis.patch.yml    # 共享层：所有机器一致的配置

~/.dsh-data/                        # 数据根：仓库之外，任何 git 命令都碰不到
├── sessions/                       # 会话历史（不可再生）
├── attachments/                    # 图片等附件（不可再生）
├── storages/                       # 工作区等持久化状态
├── spill/                          # 溢出文件
└── .credentials.yaml               # 明文凭据，权限必须 600
```

**不可再生的数据只在 `~/.dsh-data/`；`$DSH_HOME` 里剩下的都是配置和可再生产物**（`dsh-runtimes/`、`profiles/*/node_modules/`、`settings.yaml`、`.anonymous-user-id`、`cache/`）。

## 分层：配置放哪里

DSH 按顺序叠加四层，**后一层按行覆盖前一层**：

| 顺序 | 层 | 本仓库对应文件 | 放什么 |
|---|---|---|---|
| 1 | bundle 层 | （无） | 由 DSH 安装包提供 |
| 2 | profile 层 | `profiles/desktop/cordis.patch.yml` | **所有机器一致**的配置：LLM 路由、模型表、默认模型、跨平台插件行 |
| 3 | home 层 | `cordis.patch.yml`（由 `machines/<os>.cordis.patch.yml` 生成） | **本机专属**：绝对路径、OS 特有的插件行 |
| 4 | `--patch` | （无） | 单次启动的临时覆盖，不要用来存个人配置 |

判断标准很简单：**行里出现绝对路径或 OS 差异 → 放机器层；否则放共享层。**

## 数据分根（为什么不可再生数据不在 home 里）

DSH 的出厂设计是「所有用户数据放在同一个 `$DSH_HOME` 下」，而本仓库把 `$DSH_HOME` 当成了仓库工作树。两者叠加的后果是：**在仓库里跑一条 `git clean -xdf`，会话历史、凭据、附件会被一起删掉** —— `-x` 连被忽略的文件都删。

所以机器层用 5 行把不可再生数据改写到仓库之外的数据根：

| 行 id | 配置字段 | 改写到 |
|---|---|---|
| `session-persistence-jsonl` | `root` | `~/.dsh-data/sessions` |
| `attachment-local` | `dshHome` | `~/.dsh-data`（附件落在 `<数据根>/attachments/v1`） |
| `storage-json` | `root` | `~/.dsh-data/storages` |
| `credentials` | `path` | `~/.dsh-data/.credentials.yaml` |
| `spill-local` | `root` | `~/.dsh-data/spill` |

这 5 个字段都是各插件在 bundle 层就已暴露的配置项（`packages/bundle/base/cordis.patch.yml` 里的 `dshHomePath('sessions')`、`dshHomePath('storages')` 就是它们的默认值），因此不需要补丁、软链接或 fork 任何 DSH 代码。

**实测对比**（在一次性副本上跑真实命令）：

| 命令 | 分根前 | 分根后 |
|---|---|---|
| `git clean -xdf` | 会话 / 凭据 / 附件全部删除 | 数据根 4 个文件全部存活；只删掉可重建的 `dsh-runtimes/`、`profiles/*/node_modules/` 等 |
| `git reset --hard` / `git checkout -f` | 数据无恙 | 数据无恙（只丢弃已跟踪文件的未提交修改） |
| `git clean -fd`（不带 `-x`） | 无操作 | 无操作 |

数据根路径由 `machines/<os>.cordis.patch.yml` 里的 `__DSH_DATA__` 占位符表示，`install.sh` / `install.ps1` 生成机器层时替换成本机真实路径，并在最后**自检 5 行是否齐全**：将来 DSH 改了行 id，脚本会 `warn` 而不是静默退回 home。

> **代价与限制**：这偏离了 DSH「单根目录」的出厂约定。如果将来 DSH 新增了写在 home 里的数据存储，它**不会**自动被分根，需要按上表的模式补一行；自检只覆盖已知的这 5 个行 id。

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

`pull` 之后 `hooks/post-merge` 会自动执行 `install.sh` / `install.ps1`：准备数据根并迁移既有数据、按当前平台重新生成机器层、体检外部工具与密钥。

**布局升级（一次性，只有 pull 到含「数据分根」版本的那一次）**：脚本会把 home 里的 `sessions/`、`attachments/`、`storages/`、`.credentials.yaml` 复制到 `~/.dsh-data/`，并让机器层指向新数据根。复制规则是「目标不存在才复制」，绝不覆盖已有数据。稳妥顺序是**先退出 DSH，再手动跑一次脚本，然后启动**：

```sh
cd ~/.dsh && ./install.sh      # Windows: .\install.ps1
```

旧的 home 内副本会保留作安全网；确认会话列表、凭据都正常后可自行删除。

生效时机：patch 改动通常由 HMR 即时生效（新增一行 MCP，进程会立刻被拉起），但**数据根这类存储路径改动要重启应用**才算干净生效。

## 红线

1. **不要在本仓库运行 `git clean -xdf`。** 数据已分根，所以这条命令现在只会删掉可重建的运行时（`dsh-runtimes/`、`profiles/*/node_modules/`）和生成文件——**不再有数据损失**。但也没有理由运行它。
   - 与直觉相反的是：`git reset --hard` 和 `git checkout -f` 对运行时数据**完全无害**，它们只影响**已跟踪**的配置文件（改动都可以从 git 历史恢复）。真正会删文件的只有带 `-x` 的 `clean`；不带 `-x` 的 `git clean -fd` 在本仓库是无操作（白名单 `.gitignore` 让所有运行时数据都处于 ignored 状态）。
2. **密钥不入库。** 凭据在 `~/.dsh-data/.credentials.yaml`，是明文且必须保持 `600` 权限（DSH 会拒绝加载权限过宽的文件）。更推荐根本不落盘：在 `~/.zprofile`（macOS）或用户环境变量（Windows）里导出 `TX_GATEWAY_API_KEY` / `DEEPSEEK_API_KEY`。
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
| `git status` 经常显示 patch 文件被改 | **正常现象**：应用会在启动或设置变化时把改动的行写回这个文件。想同步就 `git add -A && git commit && git push` |
| `git pull` 报 `Your local changes would be overwritten` | 本机应用也写入了同一行，但还没提交。先丢弃本机这份未提交改动再拉取（远端版本已包含同样的配置）：<br>`git checkout -- profiles/desktop/cordis.patch.yml && git pull` |
| 会话列表空了 / 历史不见了 | 先看 `ls ~/.dsh-data/sessions`：数据在那里说明只是没被读到，重启应用即可；数据仍在 `~/.dsh/sessions` 说明分根覆盖行没生效，跑 `bash ~/.dsh/install.sh` 看自检结果 |
| 数据根在哪、怎么改 | 数据根固定为 `<本仓库目录>-data`（`~/.dsh` → `~/.dsh-data`）。要改路径就改 `machines/<os>.cordis.patch.yml` 里的覆盖行（不要用 `__DSH_DATA__` 之外的绝对路径写法），再跑一次 `install.sh` |
| 换了 home 之后旧数据要不要搬 | 数据根跟着仓库目录走。换位置后把旧的 `*-data` 目录 `cp -R` 到新数据根即可（应用退出后操作） |

## 切换 home 后如何生效（每台机器只做一次）

`install.sh` 会把 `export DSH_HOME=...` 写进 `~/.zprofile`（Windows 写进用户环境变量）。但 Desktop 应用只在**启动时**确定 home，所以必须重启，而且启动方式有讲究：

| 启动方式 | home 来源 | 切换后怎么办 |
|---|---|---|
| 打包版 Desktop（双击图标） | 默认就是 `~/.dsh`，与本仓库位置天然一致 | 直接重启应用即可 |
| 开发版 Desktop（`pnpm run dev:desktop`） | `dev.ts` 启动时读 `process.env.DSH_HOME`，并把它**写进生成的 `Harness Dev.app` 启动脚本** | **必须新开终端**再执行 `pnpm run dev:desktop` |

开发版特别注意：**不要直接双击旧的 `Harness Dev.app`**，它内部写死的还是生成时的旧 home。正确步骤是：

```sh
# 1. 完全退出 Desktop
# 2. 新开一个终端（让 ~/.zprofile 里的 DSH_HOME 生效）
echo $DSH_HOME            # 应输出 /Users/<你>/.dsh
cd ~/Workspace/deepseek-harness && pnpm run dev:desktop
```

原因见 DSH 源码仓库的 `apps/desktop/README.md`：Desktop 会读取登录 shell 的环境，但**启动方自有的 `DSH_*` 变量不会被 shell 值覆盖**，因为它在读取之前就已经用 `DSH_HOME` 解析好了路径。

## 新机器验证清单

装完后依次确认：

1. `echo $DSH_HOME` → 输出本仓库目录（不是 DSH 源码仓库里的 `.desktop-build`）
2. `ls "$DSH_HOME/cordis.patch.yml"` → 文件存在（机器层已由脚本生成）
3. `git -C "$DSH_HOME" config core.hooksPath` → 输出 `hooks`
4. `ls ~/.dsh-data` → 存在 `sessions/`、`.credentials.yaml`（数据分根已生效）
5. 启动 DSH 后，模型列表里能看到 `tx-gateway` 与 `tx-gateway-completions` 两套路由的模型
6. 重启后会话列表里能看到历史会话（证明确实读的是新数据根）
7. macOS 上启用 Playwriter 时，工具列表里出现 `mcp__playwriter__execute`

## 已知限制

- **通过界面安装的 bundle（插件包）不会跟着同步。** `profiles/desktop/package.json` 里的 `dsh.profile.bundles` 由 DSH 自己维护，容易被 `pnpm install` 改写，所以不在跟踪范围内。如果你以后用 `dsh plugin add` 装了外部插件包，需要在每台机器上分别装一次。纯配置（本仓库目前的全部内容）不受影响。
- **`dsh-runtimes/`（离线运行时，约 370MB）不迁移**，新 home 首次需要时会自行安装。它现在也是 `git clean -x` 唯一会波及的东西（可重建，只是慢）。
- **数据根不会自动跟随 home 移动。** 数据根 = `<本仓库目录>-data`；如果以后把仓库 clone 到别处，旧数据需要手动 `cp -R` 过去（应用退出后操作）。
- **新增的 home 数据存储不会自动分根。** DSH 若新增写在 home 里的存储，需要按「数据分根」一节的模式补一行覆盖；脚本自检只覆盖已知的 5 个行 id。

## 备份

真正需要备份的只有两样：

| 内容 | 载体 |
|---|---|
| 配置 | git 远端（`git@github.com:StormPhoenix/dsh-config.git`）—— `git push` 即已备份 |
| 数据 | `~/.dsh-data`（会话、附件、存储、凭据）—— 用下面的脚本 |

```sh
./backup.sh                       # 备份到 ~/dsh-backups，保留最近 10 份
./backup.sh --keep 20             # 调整保留份数
./backup.sh --out /Volumes/USB    # 备份到外部盘
./backup.sh --list                # 查看已有备份
```

Windows 用 `.\backup.ps1`（参数相同；优先产出 `.tar.gz`，系统无 `tar` 时退回 `.zip`）。

- 归档**含明文 `~/.dsh-data/.credentials.yaml`**，所以脚本把备份目录设为 `700`、归档设为 `600`；仍请把它存在安全位置。
- 应用运行中备份是安全的（逐文件读取），但正在写入的那个会话，最后几条事件可能不完整；需要完全一致时先退出 DSH 再备份。
- 恢复：先完全退出 DSH，再执行脚本末尾打印的命令（`rm -rf <数据根> && tar -xzf <归档> -C <数据根的父目录>`）。
- 建议节奏：改完配置、装过插件、或有重要会话之后跑一次即可 —— 数据量很小（当前约 8MB）。

首次迁移前的备份保留在 `~/.dsh-backup-<时间戳>/`（含当时的 `cordis.patch.yml`、历史 `.bak-*` 和明文 `credentials.yaml`）。确认新方案稳定后可自行删除。
