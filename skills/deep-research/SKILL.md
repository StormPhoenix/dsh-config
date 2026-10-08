---
name: deep-research
description: 结构化深度调研。确认对象和字段后并行搜索、保存逐项结果、支持断点恢复并汇总报告；支持追加对象或字段。
---

## DSH 使用约定

本技能提供指令和本地资料，不注册新工具。仅调用当前会话实际提供的工具；若工具通过 `run_code` 暴露，在其中调用 `tools.<工具名>`，不要直接调用未声明的工具。

技能内的参考资料路径相对宿主提供的技能资源根目录（`Base directory for this skill`）解析；用户文件、调研结果和代码输出路径相对当前工作区或用户确认的输出目录解析，不写入技能资源目录。只按需读取资料。

读取文本使用 `read({file_path, offset, limit})`，搜索内容使用 `grep({pattern, path})`，发现文件使用 `glob({pattern, path})`；`glob` 不列目录，目录存在性或目录列表使用 `bash`。修改现有文件前先 `read`，精确修改使用 `edit({file_path, old_string, new_string})`，创建文件使用 `write({file_path, content})`。不得覆盖未经确认的已有输出；写入后重新读取验证。

用户可以通过 `/deep-research` 加自然语言指定阶段；下文阶段名称不是额外注册的 slash 命令。

独立搜索按 `batch_size` 分批并行；直接并行只读搜索或使用当前可用的 `subagent` 按 `items_per_agent` 分片，不隐式创建 Agent Teams。为不同分片指定不同结果文件，等待/收集全部必需结果后汇总。恢复时读取现存逐项 JSON，只有结构完整、字段符合当前 fields.yaml 的条目才跳过，损坏或过期字段结果重新收集。

搜索使用 `web_search({queries: [查询]})`（每次 1–4 个查询），全文阅读使用 `web_fetch({url})`。JavaScript 动态页面或登录页面使用当前已连接的 Playwriter 工具，先观察、再操作、再观察；不接管用户未指定的已有标签页，不绕过访问限制。网络不足时标记信息缺口，不编造来源或数据。

# Deep Research — 结构化深度调研工作流

提供人机协作的结构化调研能力，适用于需要系统性调研的场景。

## 工作流阶段

| 阶段 | 说明 |
|------|------|
| `大纲阶段 <topic>` | 初步调研，生成 outline.yaml + fields.yaml |
| `深度搜索阶段` | 并行深度搜索，逐项收集数据 |
| `报告汇总阶段` | 汇总生成 Markdown 报告 |
| `追加对象阶段` | 追加调研条目 |
| `追加字段阶段` | 追加调研字段 |

## 工作流程

```
大纲阶段 "AI Agent 2025"
    ↓ 生成大纲（items + fields）
    ↓ 用户确认/修改
深度搜索阶段
    ↓ 使用 web_search 逐项搜索
    ↓ 结果写入 results/
报告汇总阶段
    ↓ 汇总为 report.md
```

## 适用场景

- **学术调研**：论文综述、Benchmark 对比
- **技术选型**：框架评估、工具对比
- **市场调研**：竞品分析、行业趋势
- **尽职调查**：公司研究、投资分析

### 示例对话

- "帮我调研一下 2025 年主流 AI Agent 框架" → `大纲阶段 "AI Agent 2025"`
- "深度调研一下特斯拉的商业模式" → `大纲阶段 "Tesla 商业模式"`
- "对比一下 React 和 Vue 的优劣" → `大纲阶段 "React vs Vue"`

## 注意事项

- 单次调研建议不超过 20 个条目，避免搜索时间过长
- 深度搜索阶段每个条目需 2-3 次 web_search，总耗时与条目数成正比
- 搜索失败的条目会标注 `[数据不足]`，不会阻断整个流程
- 断点续传：如果中途中断，重新执行 `深度搜索阶段` 会跳过已完成的条目

## 大纲阶段 流程

### Step 1: 内部知识生成框架
基于 topic，利用已有知识生成：
- 该领域的主要研究对象/items 列表
- 建议的调研字段框架
- 询问用户确认：items 列表是否需要增减？字段框架是否满足需求？

### Step 2: Web Search 补充
询问用户时间范围（如：最近 6 个月、2024 年至今、不限）。
使用 web_search 搜索补充最新 items 和推荐调研字段。

### Step 3: 生成 Outline
合并所有信息，生成两个文件：
- **outline.yaml**：items 列表 + execution 配置（batch_size、items_per_agent、output_dir）
- **fields.yaml**：字段分类和定义（每个字段含 name、description、detail_level）

保存到 `./{topic_slug}/` 目录。

## 深度搜索阶段 流程

1. 按“调研项目与结果定位”选择唯一 outline.yaml，锁定调研根目录与 output_dir
2. 断点续传：跳过已完成的 items
3. 对每个 item 使用 web_search 逐项深度搜索
4. 按 fields.yaml 定义的字段输出结构化 JSON 到 `results/` 目录
5. 不确定的字段值标注 `[不确定]`

## 报告汇总阶段 流程

1. 从锁定的 output_dir 读取当前 outline 对象对应的 JSON，忽略已移除对象或其他项目的残留结果
2. 询问用户目录中需要显示哪些摘要字段
3. 使用 `write` 创建 Python 转换脚本，通过 `load_workspace_dependencies` 获取可用 Python 路径，再用 `bash({description, command, workdir})` 执行并检查退出码
4. 输出 `report.md`：目录（带锚点 + 摘要字段）+ 详细内容

## 调研项目与结果定位

每次执行先锁定唯一调研根目录：用户指定路径时优先使用；否则用 `glob` 查找工作区内 outline.yaml，多个候选必须请用户选择。新项目默认创建于工作区的 topic_slug 目录，已有项目不自动换目录。所有后续阶段使用同一个根目录，不能扫描并混合多个项目。

outline.yaml 中的 output_dir 相对该调研根目录解析（绝对路径须用户确认），未设置时使用该根目录下 results/。逐项结果包含稳定 item_id；恢复和汇总只读取当前 outline 的对象对应结果，忽略已移除对象的残留文件。核对 item_id、主题和当前 fields.yaml 后才认定完成；缺失/损坏结果重新检索，字段不足明确标注。报告始终写入锁定的调研根目录。

## 追加对象阶段

读取当前项目的 outline.yaml 和 fields.yaml，向用户确认新增对象；按稳定标识去重，以 `edit` 合并对象列表，保留已有对象、配置和结果。仅为新增或未完成对象运行深度搜索阶段，随后重新汇总报告。

## 追加字段阶段

读取 fields.yaml 并确认新字段的名称、含义和 detail_level；按名称合并字段定义，不覆盖已有定义。逐个读取已有结果，保留旧数据，为新增字段补充检索；只有满足当前字段定义的结果才标为完成。所有受影响结果完成或明确标注信息不足后，重新汇总报告。

## 输出结构

```
{topic_slug}/
├── outline.yaml    # 调研条目 + 执行配置
├── fields.yaml     # 字段定义
├── results/        # 逐项搜索结果 JSON
│   ├── item_1.json
│   └── ...
└── report.md       # 最终报告
```
