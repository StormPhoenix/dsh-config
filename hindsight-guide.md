# Hindsight 隐藏后台启动与安装指南

## 当前机器：一个命令启动两个服务

从 DSH 之外的 PowerShell 执行：

```powershell
& "$env:USERPROFILE\.dsh\hindsight.ps1"
```

默认 Start 在隐藏的独立 PowerShell 进程中启动 API 和 UI，不弹出新终端窗口，创建进程后返回。创建进程不等于服务已经就绪；首次模型初始化可能需要数分钟。

```powershell
& "$env:USERPROFILE\.dsh\hindsight.ps1" -Action Status
& "$env:USERPROFILE\.dsh\hindsight.ps1" -Action Stop
```

API：http://127.0.0.1:9077。UI：http://127.0.0.1:9999。Status 显示 Managed、Pid、Listening、Ready、Stdout、Stderr。日志和进程身份记录存放于 ~/.hindsight/launcher/，每次启动使用独立日志文件，不自动轮换删除。

当前部署仍优先复用 ~/.hindsight/backend/start-backend.ps1 和 ~/.hindsight/control-plane/start-ui.ps1，后端继续读取 DSH 凭证库、使用 hindsight-dsh 数据库，没有迁移数据。已有部署的模型由原 backend.json 决定，入口的模型参数仅用于 native 新部署。

## 启动和停止的限制

Start/Stop/Status 使用文件锁避免并发管理操作。已记录的活进程不会重复创建；外部健康服务会跳过且提示不归本管理器所有，外部不健康监听会拒绝启动。后台子进程使用 NonInteractive 模式，新部署的密钥由可见父进程隐藏提示输入。

Stop 只接受 PID、创建时间、启动命令和随机 LaunchId 均匹配的进程记录，不按端口盲目杀进程。按 UI 再 API 的顺序调用 Windows taskkill /T /F 强制结束树。这不是优雅关机，正在执行的写入、抽取和反思可能中断；备份数据库前应安排后端优雅停机，而不是依赖这个强制 Stop。状态文件保留供日志定位和排错。

启动失败可能留下已经成功创建的一个服务，不自动回滚；用 Status 和日志确认后处理。状态写入失败会报告已创建进程，需人工检查，不能盲目重试。进程退出但端口仍存在时 Stop 报告未知剩余状态，不继续按端口杀进程。

从普通独立 PowerShell 启动的隐藏进程可以在启动器返回后继续运行。隐藏窗口不等于脱离 DSH 的 Windows Job；从 DSH shell 工具执行仍可能随 DSH 退出被清理。本次只使用隔离假服务验证隐藏创建、身份记录及停止逻辑，未启动实际服务，也未通过关闭外部终端验证常驻行为。

## 前台排错入口

需要观察实时输出或使用 Ctrl+C 时，先停止后台服务，再在用户自己打开的两个终端分别执行：

```powershell
& "$env:USERPROFILE\.dsh\hindsight.ps1" -Action Api
& "$env:USERPROFILE\.dsh\hindsight.ps1" -Action Ui
```

这两个命令各自前台阻塞，不自动创建新窗口。通过前台入口启动的服务不归后台管理器 Stop 所有。

## 无 Docker 的新 Windows x64 机器

安装 Node.js 22.19+（受支持 LTS）和 uv，重新打开 PowerShell。只需复制 hindsight.ps1 到新机器 ~/.dsh/。该单文件包含后台管理、安装和前台运行逻辑，无辅助脚本依赖。

```powershell
& "$env:USERPROFILE\.dsh\hindsight.ps1" -Action Install
& "$env:USERPROFILE\.dsh\hindsight.ps1" -Provider openai-responses -BaseUrl 'https://your-gateway/v1' -Model 'your-model'
```

安装创建 ~/.hindsight/native/，由 uv 下载 Python 3.12，安装 hindsight-api-slim[local-onnx,embedded-db]==1.1.0、flashrank==0.2.10 和官方预构建 UI @vectorize-io/hindsight-control-plane@1.1.0。不覆盖已有目录，失败后的部分目录保留供诊断。新机器安装分支未在另一台机器执行。

密钥仅通过 API 子进程环境传递，不写文件或命令参数；UI 不继承模型密钥。父进程环境会恢复。Chat Completions 接口使用 -Provider openai。native 路径不自动解析另一台机器的 DSH 凭证库。新数据库 pg0://hindsight-native 存于 ~/.pg0/instances/hindsight-native。

## 验证与 DSH 接入

```powershell
Invoke-RestMethod http://127.0.0.1:9077/health
npx @vectorize-io/hindsight-coding-agents install dsh --server self-hosted --api-url http://127.0.0.1:9077
```

UI 中创建合成测试 bank，验证 retain、Recall、Reflect；健康检查不证明模型兼容。重启 DSH 并验证跨会话召回；不要重复全局安装器和 profile bundle 安装。

## 安全维护

只监听回环地址且未配置鉴权，不要公开端口。云端抽取和反思发送内容到模型并产生费用。HTTP 网关无 HTTPS 保护；环境变量不防止特权本机进程读取。日志可能包含记忆内容，不应公开分享。

未安装任务计划、Windows 服务、开机自启或自动重启。重启电脑后需手动启动。不要删除 pg0 数据作为重启手段。
