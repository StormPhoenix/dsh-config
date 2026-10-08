# 新机器初始化与 dev Desktop 插件恢复指南

本文面向从 DeepSeek Harness 源码启动 dev Desktop 的使用者。目标是将本仓库作为 `DSH_HOME`，通过插件子模块恢复已备份的 Desktop 插件，同时让源码、配置、安装包来源和个人数据分别存放。

## 开始前

- 新机器需要 Git、Git LFS、Python 3.9+、Node.js `^22.19` 或 `>=24`、pnpm，以及 DSH 开发环境要求的系统工具。
- 配置仓库和插件仓库均通过 GitHub SSH 获取；新机器的 SSH 密钥必须有访问权限。不要把密钥、API Key 或 token 提交到仓库。
- DSH 源码必须包含 `desktop:plugin` 根脚本，本配置仓库必须包含 `setup-dev.py`。在原机器将这些改动审查、提交并推送后，新机器才能获得完整入口；插件仓库及其 LFS 对象需要先于配置仓库的子模块指针发布。
- 本指南不自动安装系统工具，不克隆 DSH 源码，不执行插件构建脚本，不恢复个人会话、凭据、书库或插件自己的数据。
- macOS 的隔离 Electron 插件恢复测试已运行；Windows 入口和 PowerShell 命令尚未实机验证。Linux 不属于此 Desktop 开发入口支持的构建目标。

## 目录安排

建议采用以下布局；源码位置可以自选，但不能与配置仓库互相嵌套：

```text
~/Workspace/deepseek-harness/       DSH 源码和构建产物
~/.dsh/                            本配置仓库，也是 DSH_HOME
~/.dsh/plugins/                    插件归档 Git submodule
~/.dsh-data/                       单独迁移的个人数据
~/dsh-plugin-staging/              setup 生成的稳定安装包及批量计划
```

安装包暂存目录由 setup 创建，不放进 DSH 源码或配置仓库。安装后的本地包来源可能仍引用此目录，因此不能当作普通临时目录删除。

## 1. 检查工具和 SSH 权限

macOS 终端执行：

```bash
git --version
git lfs install
node --version
pnpm --version
python3 --version
ssh -T git@github.com
```

GitHub 的 SSH 成功消息可能伴随非零退出码，以认证结果为准。脚本实际克隆或下载失败时会停止；需要先修复权限、网络或 LFS 配额问题。

## 2. 准备 DSH 源码

通过你日常使用的源码远端克隆包含新命令的分支，然后在源码根目录安装开发依赖。以下路径只是示例：

```bash
cd "$HOME/Workspace/deepseek-harness"
pnpm install
```

确认根脚本中存在 `desktop:plugin` 和 `dev:desktop`。不需要全局安装 npm 版 `dsh` 来管理 Desktop；普通 npm 或源码 `pnpm dsh plugin --profile desktop` 仍不是受支持入口。

## 3. 克隆配置与插件子模块

仅在 `~/.dsh` 不存在时执行：

```bash
GIT_LFS_SKIP_SMUDGE=1 git clone \
  git@github.com:StormPhoenix/dsh-config.git "$HOME/.dsh"

git -C "$HOME/.dsh" submodule update --init --recursive
git -C "$HOME/.dsh/plugins" lfs pull
```

子模块检出配置仓库记录的固定提交；不要用 `submodule update --remote` 替代。Git LFS 将指针文件还原成实际 `.tgz` 和素材。只克隆 Git 而没有下载 LFS 对象，不能安装备份。

已有 `~/.dsh` 时，先检查它是否为正确配置仓库以及 `git status` 是否干净。不要覆盖、reset 或删除现有目录；保留本地改动，审查后再继续。setup 和 bootstrap 都会拒绝有未提交改动的配置仓库。

## 4. 初始化机器配置

```bash
bash "$HOME/.dsh/install.sh"
```

此脚本执行原有配置设置，包括生成机器层、设置数据根和环境变量。它不是插件安装命令。个人凭据需要另行安全配置或迁移；新配置 home 不意味着旧个人数据已经恢复。

## 5. 首次启动 Desktop 初始化 profile

```bash
cd "$HOME/Workspace/deepseek-harness"
DSH_HOME="$HOME/.dsh" pnpm run dev:desktop
```

首次启动构建开发环境并初始化 Desktop profile。完成后完全退出 Desktop，包括托盘或菜单栏后台应用，再执行安装。不能只关闭窗口。

如果启动失败，先按 DSH 的开发文档修复构建、依赖或配置问题，不要手工创建或覆盖 profile 的依赖清单。若首次启动修改了受跟踪配置，先审查并保留这些改动，使配置仓库恢复干净，再运行 setup。

## 6. 校验并自动安装备份插件

唯一必填参数是 DSH 源码根目录：

```bash
bash "$HOME/.dsh/setup-dev.sh" "$HOME/Workspace/deepseek-harness"
```

setup 会检查源码和工具、初始化固定插件子模块并下载 LFS、校验所有归档、生成稳定安装来源、再次运行配置初始化，然后通过 `desktop:plugin restore` 在一个 Desktop 所有权持有期间批量恢复插件。恢复只选择归档的 Desktop profile；Web 和 Headless 安装记录不会随此命令安装。

安装会保留不在清单中的插件，恢复清单中的启用状态和顺序。所有归档在安装前校验 SHA-256 和包身份，原生包还需匹配实际 Electron 平台与架构。生命周期脚本默认禁用，不自动批准构建脚本或版本豁免。失败立即停止后续项，不回滚已经完成的安装；输出真实错误，修复后可重跑。不要把重跑理解为自动降级保护：清单中的版本就是目标版本，应先审查清单。

只校验并准备计划，不修改配置或安装插件：

```bash
bash "$HOME/.dsh/setup-dev.sh" "$HOME/Workspace/deepseek-harness" --prepare-only
```

prepare-only 不拉取子模块或 LFS，因此需先完成第 3 步。它仍会在稳定目录中生成安装包和 `plan.json`。源码检查和完整插件归档校验仍会执行。

## 7. 启动与验收

```bash
cd "$HOME/Workspace/deepseek-harness"
DSH_HOME="$HOME/.dsh" pnpm run dev:desktop
```

检查插件页面中的包版本、启用状态、加载错误，以及实际功能。以后源码开发启动始终使用相同的 `DSH_HOME`，避免落到源码中的隔离开发 home。macOS 不要双击之前生成、绑定旧 home 的 `Harness Dev.app`；从终端重新运行开发启动器会重新生成对应启动设置。

完全退出 Desktop 后，可以在源码根目录通过正式终端入口查看和管理插件：

```bash
DSH_HOME="$HOME/.dsh" pnpm run desktop:plugin -- list
DSH_HOME="$HOME/.dsh" pnpm run desktop:plugin -- add /absolute/path/plugin.tgz --ignore-scripts
DSH_HOME="$HOME/.dsh" pnpm run desktop:plugin -- remove example-plugin
```

## 可选：bootstrap 合并克隆和恢复步骤

[bootstrap.py](bootstrap.py) 是可单独获取的初始化入口，唯一必填参数同样是已有 DSH 源码位置：

```bash
python3 /path/to/downloaded/bootstrap.py "$HOME/Workspace/deepseek-harness"
```

它克隆缺失的 `~/.dsh`，检查已有仓库的 origin 和未提交改动，初始化固定子模块、下载 LFS，并调用 setup。已有仓库不会自动 pull、reset 或替换。源码和开发依赖必须预先准备好；缺少 Desktop profile 时会在配置初始化后提示首次启动，尚未安装插件。按第 5 步启动、退出后，再执行第 6 步即可。

[bootstrap.sh](bootstrap.sh) 和 [bootstrap.ps1](bootstrap.ps1) 会从 GitHub raw URL 下载 Python 入口。私有配置仓库的匿名 raw 下载可能返回 404；推荐通过已认证方式下载并审查 `bootstrap.py`，或直接使用第 3 步的 SSH 克隆流程。SSH 克隆权限不等于匿名 HTTPS raw 下载权限。

## Windows 对应命令（未实机验证）

在 PowerShell 中完成同样的工具准备和源码克隆，然后执行：

```powershell
$source = "$HOME\Workspace\deepseek-harness"
$env:GIT_LFS_SKIP_SMUDGE = '1'
git clone git@github.com:StormPhoenix/dsh-config.git "$HOME\.dsh"
Remove-Item Env:GIT_LFS_SKIP_SMUDGE
git -C "$HOME\.dsh" submodule update --init --recursive
git -C "$HOME\.dsh\plugins" lfs pull
& "$HOME\.dsh\install.ps1"

Set-Location $source
$env:DSH_HOME = "$HOME\.dsh"
pnpm run dev:desktop
# 完全退出 Desktop 后继续
& "$HOME\.dsh\setup-dev.ps1" $source
pnpm run dev:desktop
```

脚本默认使用 `python`；需要其他解释器时先设置 `DSH_TRANSFER_PYTHON`。按系统既有策略允许执行已审查的 PowerShell 脚本，不要全局关闭执行策略。Windows Desktop 的开发构建目标固定为 x64；原生归档的最终兼容性由 Electron 恢复入口检查。

## 失败处理

| 提示或现象 | 处理 |
|---|---|
| 缺少 `desktop:plugin` | 获取包含新入口的 DSH 分支，不改用普通 npm CLI |
| 缺少构建产物或准备运行时 | 先执行一次 `pnpm run dev:desktop`，处理启动错误后退出 |
| Desktop profile 未初始化 | 显式指定 `DSH_HOME` 首次启动，再完全退出并重跑 setup |
| 配置仓库 dirty | 审查并保留未提交改动，不自动 reset |
| LFS payload missing | 在插件子模块执行 `git lfs pull`，检查权限、网络和额度 |
| Desktop ownership 或 package process 被占用 | 完全退出应用，等待其他命令和包写入进程结束；不要盲删锁或运行记录 |
| 校验和、包身份或原生架构不匹配 | 停止安装，检查可信备份来源和目标平台，不跳过校验 |
| 兼容性或包安装失败 | 检查诊断，修复后重跑；不要自动豁免版本或批准脚本 |
| 插件安装完成但功能不可用 | 重启并查看插件加载错误、配置及其单独的数据要求 |

## 数据迁移与后续更新

配置和插件 Git/LFS 仓库只同步配置与插件代码。会话、附件、凭据、长期记忆、书库和插件个人数据不在插件归档中；需在应用退出后，通过单独可信备份迁移。部分插件数据仍可能位于 profile 下，不能假设全部都由 `~/.dsh-data` 覆盖。

更新前先检查两仓库的本地改动。插件归档刷新时先审查并发布插件仓库及 LFS 对象，再发布配置仓库的新子模块指针。新机器更新配置后重新运行 setup，不需要重做源码克隆和首次 profile 初始化；它仍要求应用退出和配置工作区干净。

## 实测范围

已在 macOS 隔离环境执行 Electron 归档恢复、禁用状态恢复、列出、移除、所有权竞争拒绝以及遗留包进程检查；setup 和 bootstrap 的流程通过临时目录和模拟子进程测试，真实备份完成过 prepare-only 校验。本指南的完整“全新机器克隆到启动”流程尚未在空白机器上验收；Windows PowerShell 亦未实机验证。执行第 1 至第 7 步的使用者负责在新机器完成最终验收。
