# 新机器配置与手动插件安装

本仓库是 DSH 配置 home。它同步机器层、共享 profile 配置、用户技能和配置/数据备份脚本，不同步插件源码、插件归档或依赖树。插件在每台机器上手动安装。

## 目录安排

```text
~/Workspace/deepseek-harness/   DSH 源码和构建产物
~/.dsh/                        本配置仓库与本机运行产物
~/.dsh-data/                   会话、附件、凭据、持久化数据
~/dsh-local-packages/          可选：手动安装的本地插件包，需保留
```

本机运行时和 `profiles/*/node_modules` 可存在于 DSH home，但不进入配置仓库。不要执行 `git clean -xdf`；它可能删除本机安装和运行产物。

## 初始化配置

先准备 Git 和所需版本的 DSH。源码构建所需的 Node、pnpm 与平台依赖以选定版本的官方文档为准。本仓库不安装系统工具、不克隆 DSH 源码，也不恢复插件。

```sh
git clone git@github.com:StormPhoenix/dsh-config.git "$HOME/.dsh"
bash "$HOME/.dsh/install.sh"
```

```powershell
git clone git@github.com:StormPhoenix/dsh-config.git "$env:USERPROFILE\.dsh"
& "$env:USERPROFILE\.dsh\install.ps1"
```

已有配置 checkout 时先保留本机配置修改，再正常 `git pull`。不使用 `--recurse-submodules`，不运行 Git LFS 或插件恢复脚本。安装脚本生成本机 home patch 并配置数据分根；共享 profile patch 与技能直接从仓库读取。

## 启动与插件安装

重开终端，使 `DSH_HOME` 指向本仓库。从选定的 DSH 源码目录使用该版本的开发启动命令，例如 `pnpm run dev:desktop`；首次启动由应用初始化本机 profile。打包版 Desktop 使用其自身启动入口。

在目标 Desktop 的插件管理页面或应用内 `plugin_manager` 手动安装需要的插件。不要覆盖 profile 的依赖清单或 `node_modules`，也不要用普通 Web CLI 管理 Desktop profile。插件兼容性失败时优先寻找兼容版本，不批量授予版本豁免。

本仓库的共享 patch 只保存配置，不安装插件。每台机器自行决定版本和启停状态，缺失插件的配置覆盖不会替代安装。若使用本地 `.tgz`，把文件放在仓库之外的持久目录；后续重装可能仍需要这个来源。

## 验证与数据迁移

1. 确认 `DSH_HOME` 指向本配置仓库，home patch 已生成。
2. 确认机器层的数据路径指向 `~/.dsh-data`，而不是源码目录。
3. 在目标应用插件页核对安装版本、启停状态，并测试实际功能。
4. 在应用退出后，另行迁移或恢复个人数据与凭据；本仓库不携带这些数据。
5. 更新配置后检查 `git status`，确认没有插件源码、归档、依赖目录或凭据进入暂存区。

旧插件源码和归档可保存在 DSH home 之外的独立备份目录，不再作为此配置仓库的子模块。移除子模块不删除远端插件仓库或 Git 历史。
