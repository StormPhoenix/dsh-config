# dsh-config

DeepSeek Harness（DSH）的个人配置仓库。**这个目录同时就是 DSH 的 home（`$DSH_HOME`）**，因此 `git pull` 之后配置就位，无需任何拷贝或链接。而**不可再生的运行时数据（会话、附件、凭据、存储、长期记忆）放在仓库之外的 `~/.dsh-data/`**，见「数据分根」——所以即使在这个仓库里误用 `git clean -x`，数据也不会被删。

目的：在多台机器（macOS / Windows）之间共享同一套 DSH 配置 —— LLM provider 路由、模型表、默认模型、插件（MCP）——并且不受 DSH 源码仓库频繁更新、重建、`pnpm run clean` 的影响。

## 目录结构

```
$DSH_HOME/                          # = 本仓库的 clone 目录，例如 ~/.dsh
├── .gitignore                      # 白名单：只跟踪配置与脚本
├── install.sh / install.ps1        # 幂等安装脚本（首次 + 每次 pull 后运行）
├── backup.sh / backup.ps1          # 数据备份（打包数据根，默认保留最近 10 份）
├── hooks/post-merge                # git hook：pull 之后自动执行上面的脚本
├── skills/                         # 用户级技能，完整指令与参考资料随仓库同步
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

所以机器层用 6 行把不可再生数据改写到仓库之外的数据根：

| 行 id | 配置字段 | 改写到 |
|---|---|---|| `session-persistence-jsonl` | `root` | `~/.dsh-data/sessions` |
| `attachment-local` | `dshHome` | `~/.dsh-data`（附件落在 `<数据根>/attachments/v1`） |
| `storage-json` | `root` | `~/.dsh-data/storages` |
| `credentials` | `path` | `~/.dsh-data/.credentials.yaml` |
| `spill-local` | `root` | `~/.dsh-data/spill` |
| `memory` | `path` | `~/.dsh-data/memory/memory.db`（dsh-memory 插件的长期记忆库；插件未装时该行被静默忽略） |

前 5 个字段都是各插件在 bundle 层就已暴露的配置项（`packages/bundle/base/cordis.patch.yml` 里的 `dshHomePath('sessions')`、`dshHomePath('storages')` 就是它们的默认值），因此不需要补丁、软链接或 fork 任何 DSH 代码。第 6 个 `memory` 属于外部插件 `dsh-memory`，它自带的默认值是 `dshHomePath('memory/memory.db')`，同样落在 `$DSH_HOME` 内，因此也要改写。

**实测对比**（在一次性副本上跑真实命令）：

| 命令 | 分根前 | 分根后 |
|---|---|---|
| `git clean -xdf` | 会话 / 凭据 / 附件全部删除 | 数据根 4 个文件全部存活；只删掉可重建的 `dsh-runtimes/`、`profiles/*/node_modules/` 等 |
| `git reset --hard` / `git checkout -f` | 数据无恙 | 数据无恙（只丢弃已跟踪文件的未提交修改） |
| `git clean -fd`（不带 `-x`） | 无操作 | 无操作 |

数据根路径由 `machines/<os>.cordis.patch.yml` 里的 `__DSH_DATA__` 占位符表示，`install.sh` / `install.ps1` 生成机器层时替换成本机真实路径，并在最后**自检 6 行是否齐全**：将来 DSH 改了行 id，脚本会 `warn` 而不是静默退回 home。

> **代价与限制**：这偏离了 DSH「单根目录」的出厂约定。如果将来 DSH 新增了写在 home 里的数据存储，它**不会**自动被分根，需要按上表的模式补一行；自检只覆盖已知的这 6 个行 id。

## 新机器首次使用

源码开发版 Desktop 的完整初始化、首次启动、插件恢复和失败处理见[新机器指南](NEW-MACHINE-GUIDE.md)。

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

安装版 Desktop 可继续使用以上流程。源码开发版使用下一节的一参数 setup / bootstrap；DSH 源码与配置 home 分开，不把配置放进源码的 `.desktop-build`。

## 源码 Desktop：只传一个源码路径

准备现有 DSH 源码 checkout、Python 3.9+、Git / Git LFS、Node `^22.19 || >=24` 和 pnpm。源码根目录必须有 `desktop:plugin`、`dev:desktop` package scripts 和已准备好的 `node_modules`。本脚本不克隆或更新源码、不安装系统工具或源码依赖，不批准构建脚本；源码构建及其依赖需单独准备。配置仓库与源码目录不能互相嵌套。

```sh
# macOS / Linux：唯一必填位置参数是现有源码根目录
bash ~/.dsh/setup-dev.sh "$HOME/Workspace/deepseek-harness"
# 只验证并生成计划；不初始化配置，也不安装插件
bash ~/.dsh/setup-dev.sh "$HOME/Workspace/deepseek-harness" --prepare-only
```

```powershell
# Windows
& "$env:USERPROFILE\.dsh\setup-dev.ps1" 'D:\Workspace\deepseek-harness'
```

`setup-dev.py` 把 `DSH_HOME` 固定为脚本所在配置仓库，把 `DSH_SOURCE_DIR` 固定为唯一的源码参数；不需要手工 export 或第二个 home 参数。完整 setup 先拒绝配置仓库的未提交修改，然后验证全部插件归档及原生文件 OS/架构，从现有 `plugins/` 的 LFS 文件生成持久 staging（默认 `~/.dsh` 旁的 `dsh-plugin-staging/desktop-<随机值>/`），再调用原有平台 install 脚本初始化配置。可用 `--archive /path/to/backup.zip` 替代子模块，可用 `--staging /new/absolute/directory` 指定不存在且在两仓库之外的目录。`--prepare-only` 可以检查脏配置，但不会改配置文件；prepare-only 不拉取子模块或 LFS；完整 setup 会初始化固定子模块并下载 LFS，不更新到远端最新提交。

Desktop 默认 profile 必须由第一次启动创建。若还没有 `profiles/desktop/package.json`，setup 完成配置初始化后停止，不安装任何插件；按提示从源码目录用明确的 `DSH_HOME` 执行 `pnpm run dev:desktop`，确认初始化后完全退出 Desktop，审查启动写入的配置变化，再重跑 setup。已有脏 home 绝不 reset、pull 或覆盖；先自行保留、审查修改。

安装仅执行源码根的 `pnpm run desktop:plugin -- restore <plan.json>`，计划字段为 `{format:1, plugins:[{name,version,sha256,archive,enabled}], order:[启用包名]}`；`archive` 是持久 staging 中的绝对 `.tgz` 路径。该 Desktop 专用命令在批次期间持有 Desktop ownership，预验证所有包，保留目标额外插件并恢复备份中的启停状态与顺序，默认不执行安装脚本；不要替换成普通 `pnpm dsh plugin --profile desktop`。失败立即停止并返回子进程非零状态，可能保留已完成的包安装，不承诺跨包回滚。保留 staging 供重装使用；完成后重新启动 Desktop 并核对插件版本、启停状态和功能。

### 可单独下载的 bootstrap

配置远端为 `git@github.com:StormPhoenix/dsh-config.git`，需要已有 SSH 访问权限。下载并审查 `bootstrap.sh` / `bootstrap.ps1` 后执行，仍只传同一个现有源码路径；包装脚本通过 HTTPS 下载同仓库的 `bootstrap.py` 到临时文件，不修改执行策略。raw GitHub 地址必须可访问；私有仓库可通过已认证渠道下载 `bootstrap.py` 并直接运行 `python3 /path/to/bootstrap.py <source>`（Windows 用 `python`）。不要把凭据写入脚本。

```sh
curl --fail --location https://raw.githubusercontent.com/StormPhoenix/dsh-config/main/bootstrap.sh --output /tmp/dsh-bootstrap.sh
# 审查下载内容后执行；可附加 --prepare-only
bash /tmp/dsh-bootstrap.sh "$HOME/Workspace/deepseek-harness"
```

```powershell
Invoke-WebRequest 'https://raw.githubusercontent.com/StormPhoenix/dsh-config/main/bootstrap.ps1' -OutFile "$env:TEMP\dsh-bootstrap.ps1"
& "$env:TEMP\dsh-bootstrap.ps1" 'D:\Workspace\deepseek-harness'
```

bootstrap 只在默认 `~/.dsh` 不存在时克隆配置仓库；已有 home 必须是相同 origin 的干净 checkout，否则停止并保留原状。已有 checkout 不自动 `git pull`，子模块用 `update --init --recursive` 恢复已记录 commit，不用 `--remote` 更新指针，再对所有子模块执行 `git lfs pull`，最后运行配置仓库中的 setup。不会提交或推送。本配置和插件远端/LFS 对象必须先发布；远端未发布或权限不足会以非零状态停止。

隔离测试只使用临时目录与模拟子进程，不克隆、初始化真实 home 或安装插件：`python3 setup-dev.test.py`、`python3 bootstrap.test.py`（Windows 使用 `python`）。

## 用户技能

`skills/` 是 DSH 默认扫描的用户技能目录，随本仓库一起同步，不需要额外复制或安装脚本。第一批包含 13 个从 Craft 转换的技能及完整参考资料，来源库不受影响。

在聊天中输入 `/技能名` 加任务要求即可主动调用，例如 `/deep-research 请先生成大纲`。9 个工作流技能允许模型按用途加载；人物视角只允许用户显式调用 `/li-daxiao`、`/maqianzu`、`/mao-zedong-perspective`、`/xingzhongheng-perspective`。实际工具与权限由所用 DSH profile 决定，复制技能不会安装 MCP 或注册新工具。

保持包内资料相对技能根目录引用；输出写到用户工作区，不写安装目录。更新或同步前先提交个人修改，不用原 Craft 库直接覆盖 DSH 副本。

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

生效时机：patch 改动通常由 HMR 即时生效（新增一行 MCP，进程会立刻被拉起），但**数据根这类存储路径改动要重启应用**才算干净生效；**新安装的插件同样要重启**。

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
| `install.sh` 说找不到 dsh | 打包版 Desktop 不把 CLI 放进 `PATH`。设 `DSH_CLI=/path/to/dsh` 或 `DSH_SOURCE_DIR=~/Workspace/deepseek-harness` 后重跑 |
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

- **插件不会仅凭 Git 同步自动安装。** profile 的依赖清单与依赖目录不参与 Git 同步；使用下方「插件打包与跨机器恢复」生成插件归档，再通过目标机器的官方插件管理入口安装。
- **`dsh-runtimes/`（离线运行时，约 370MB）不迁移**，新 home 首次需要时会自行安装。它现在也是 `git clean -x` 唯一会波及的东西（可重建，只是慢）。
- **数据根不会自动跟随 home 移动。** 数据根 = `<本仓库目录>-data`；如果以后把仓库 clone 到别处，旧数据需要手动 `cp -R` 过去（应用退出后操作）。
- **新增的 home 数据存储不会自动分根。** DSH 若新增写在 home 里的存储，需要按「数据分根」一节的模式补一行覆盖；脚本自检只覆盖已知的 6 个行 id。

## 插件私有子模块

`plugins/` 是独立 `dsh-plugin-archive` 仓库的 submodule。配置、用户技能和安装脚本仍由本仓库管理；插件包与宠物本地修改源码由子模块管理。插件安装包和素材使用 Git LFS，不提交依赖目录、凭据、会话或插件个人数据。

新机器先安装 Git LFS、Python 3.9+ 和受支持的 Harness。两仓库发布后，使用 `git clone --recurse-submodules` 克隆本仓库，再执行 `git -C "$HOME/.dsh/plugins" lfs pull`。子模块 URL 为同账户相对路径 `../dsh-plugin-archive.git`；插件仓库已发布到 `git@github.com:StormPhoenix/dsh-plugin-archive.git`，配置仓库的新脚本和子模块指针也需提交推送后才能用于新机器。

```sh
# 先验证所有插件，再配置环境并准备 Desktop 插件安装清单
python3 ~/.dsh/plugin-repo.py verify
bash ~/.dsh/install.sh --with-plugins --profile desktop
# 打包安装版 Desktop：注册该应用提供的 CLI，初始化 profile，退出应用后自动安装
bash ~/.dsh/install.sh --with-plugins --profile desktop --cli dsh --app-closed
```

Windows 对应执行 `python plugin-repo.py verify` 和 `./install.ps1 --with-plugins --profile desktop`，自动安装时同样附加 `--cli dsh --app-closed`。不指定 profile 时准备全部归档 profile。未指定 CLI 时仅准备清单，不安装；这组旧入口对开发态 Desktop 只准备应用内安装清单；源码开发版的自动恢复请使用上方 `setup-dev.sh` / `setup-dev.ps1`，由专用 `desktop:plugin restore` 批次执行。普通 npm 或 `pnpm dsh` CLI 不能管理 Desktop。配置脚本会进行原有环境设置；插件恢复不覆盖 profile 文件、不自动豁免版本、不执行包安装脚本。

`python3 plugin-repo.py export --repository /path/to/new-staging-directory` 可从已安装插件生成新快照；已有归档不直接覆盖。审查后先提交插件仓库，再提交本仓库的 submodule 指针。发布时先推送插件仓库及 LFS 对象，再推送配置仓库。归档不是完整离线依赖镜像；恢复后仍需核对版本、启用状态与实际功能。详细包清单见子模块的 `manifest.json`。

## 插件打包与跨机器恢复

需要 Python 3.9+（Windows 默认 `python`，macOS/Linux 默认 `python3`，可用 `DSH_TRANSFER_PYTHON` 指定解释器）。插件归档与原有数据归档相互独立，不会更改正在运行的 profile。

源机器打包已经安装的外部 bundle，固定实际安装版本，不执行包的构建或发布脚本：

```powershell
# Windows：只打包 Desktop；省略 --profile 则扫描所有已初始化 profile
.\backup.ps1 --plugins --profile desktop --out D:\dsh-backups
```

```sh
# macOS / Linux
bash ./backup.sh --plugins --profile desktop --out "$HOME/dsh-backups"
```

生成 `dsh-plugins-<时间戳>.zip`，内含插件清单、启用顺序、SHA-256 校验值及每个插件的 `.tgz`。不含 `node_modules`、宿主包、版本豁免、配置、会话、凭据或插件自己的数据；插件包内部的可执行文件仍是受信任代码，归档只应来自可信机器。已安装包中的符号链接会使备份失败，而不是生成可能跨机器失效的归档。

目标机器先安装 Harness、初始化所需 profile，然后复制归档并解压校验：

```powershell
.\install.ps1 --plugins D:\dsh-backups\dsh-plugins-<时间戳>.zip --profile desktop
```

```sh
bash ./install.sh --plugins /path/to/dsh-plugins-<时间戳>.zip --profile desktop
```

不带 `--cli` 时只解压到仓库旁的 `dsh-plugin-restore-<时间戳>/`，不安装、不改 profile，并列出安装顺序，生成 `INSTALL-IN-APP.txt`；可将这份清单交给目标 Desktop 内的智能体，通过 `plugin_manager` 安装。**开发态 Desktop（包括 `pnpm run start:desktop`）请用应用的插件管理页面或应用内 `plugin_manager`，按清单顺序安装解压出的 `.tgz` 文件；原先禁用的插件安装后仍应禁用。** 不要直接覆盖 profile 的依赖清单或 `node_modules`。保留解压目录，因为安装后的本地归档来源可能在重装时使用。

打包安装版 Desktop 可先通过「Manage dsh Command」注册其 CLI，初始化 Desktop profile 后完全退出应用，再运行自动安装；普通 npm 或源码 CLI 无权管理 Desktop profile：

```powershell
.\install.ps1 --plugins D:\backup.zip --profile desktop --cli dsh --app-closed
```

```sh
# Web 等普通 profile 使用普通 dsh CLI；先退出目标 Harness
bash ./install.sh --plugins /path/to/backup.zip --profile web --cli /path/to/dsh --app-closed
```

自动安装走官方 `dsh plugin`，保留目标机器已有插件，默认阻止构建脚本；兼容性失败时停止，不自动豁免。归档包含禁用 bundle 时拒绝自动安装，改用应用插件管理入口保留启停状态。安装不是跨插件事务：中途失败时前面已成功安装的插件会保留，需检查后再继续。目标机器已有的 bundle 顺序不被覆盖。

**这不是完全离线依赖镜像。** 插件自身文件可离线带走，但传递依赖由目标包管理器解析，可能需要网络；原生文件所在包要求源/目标 OS 与架构相同，跨平台应在目标平台重新获取兼容包。插件自己下载的运行时（例如 dsh-pet 的 Electron）、用户动画、宠物配置与对话记忆也不包含；数据归档只覆盖 `<仓库>-data`，插件写入 `$DSH_HOME` 的数据需另外备份。安装后启动 Harness，在插件页核对版本、启停状态与实际功能。

测试不访问真实 profile、不执行安装：`python plugin-transfer.test.py`（macOS/Linux 使用 `python3`）。

## 备份

真正需要备份的只有两样：

| 内容 | 载体 |
|---|---|
| 配置 | git 远端（`git@github.com:StormPhoenix/dsh-config.git`）—— `git push` 即已备份 |
| 数据 | `~/.dsh-data`（会话、附件、存储、凭据、长期记忆）—— 用下面的脚本 |

```sh
./backup.sh                       # 备份到 ~/dsh-backups，保留最近 10 份
./backup.sh --keep 20             # 调整保留份数
./backup.sh --out /Volumes/USB    # 备份到外部盘
./backup.sh --list                # 查看已有备份
```

Windows 用 `.\backup.ps1`（参数相同；优先产出 `.tar.gz`，系统无 `tar` 时退回 `.zip`）。

- 归档**含明文 `~/.dsh-data/.credentials.yaml`**，所以脚本把备份目录设为 `700`、归档设为 `600`；仍请把它存在安全位置。
- 应用运行中备份是安全的（逐文件读取），但正在写入的那个会话，最后几条事件可能不完整；需要完全一致时先退出 DSH 再备份。`memory/memory.db` 是 SQLite（WAL 模式，运行中还有 `-wal`/`-shm` 侧车文件），运行中直接打包可能拿到不一致的快照 —— 要严谨就先退出 DSH。
- 恢复：先完全退出 DSH，再执行脚本末尾打印的命令（`rm -rf <数据根> && tar -xzf <归档> -C <数据根的父目录>`）。
- 建议节奏：改完配置、装过插件、或有重要会话之后跑一次即可 —— 数据量很小（当前约 8MB）。

首次迁移前的备份保留在 `~/.dsh-backup-<时间戳>/`（含当时的 `cordis.patch.yml`、历史 `.bak-*` 和明文 `credentials.yaml`）。确认新方案稳定后可自行删除。
