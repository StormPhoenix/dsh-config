---
name: repo-knowledge-base
description: 本地代码仓库知识库建设与增量维护。读取源码和 Git 记录，使用随包工作流/模板维护概览、技术分析与变更记录。
---

## DSH 使用约定

本技能提供指令和本地资料，不注册新工具。仅调用当前会话实际提供的工具；若工具通过 `run_code` 暴露，在其中调用 `tools.<工具名>`，不要直接调用未声明的工具。

技能内的参考资料路径相对宿主提供的技能资源根目录（`Base directory for this skill`）解析；用户文件、调研结果和代码输出路径相对当前工作区或用户确认的输出目录解析，不写入技能资源目录。只按需读取资料。

读取文本使用 `read({file_path, offset, limit})`，搜索内容使用 `grep({pattern, path})`，发现文件使用 `glob({pattern, path})`；`glob` 不列目录，目录存在性或目录列表使用 `bash`。修改现有文件前先 `read`，精确修改使用 `edit({file_path, old_string, new_string})`，创建文件使用 `write({file_path, content})`。不得覆盖未经确认的已有输出；写入后重新读取验证。

# 仓库工程知识库构建器

本 Skill 提供一套可复用的方法论与模板，帮助 LLM 给任意中大型代码仓库建立结构化的工程知识库，并对后续更新做增量影响分析。

> **路径说明**：以下参考资料相对宿主提供的技能资源根目录解析，使用 `read` 时拼接绝对路径。

## 何时使用本 Skill

- 用户说"帮我给 XX 仓库建立工程知识库" / "梳理这个仓库的功能模块" / "分析仓库框架设计"
- 用户已建立知识库，问"这次 commit 是否需要更新文档" / "分析 diff 影响"
- 监控类后台任务收到新 commit 通知，需要判断影响等级

## 核心行为原则（最高优先级 · 必须遵守）

LLM 在使用本 Skill 时是**自主循环执行的 Agent**，必须遵守以下行为契约：

1. **自主判定 + 自主执行**：收到 commit 通知/更新请求时，**LLM 自己完成"等级判定 → 文档更新 → changelog 登记 → 汇报"全流程**，不得停下来征求用户确认。
2. **沉默 = 无变更**：判定为 🟢 且不触发文档更新时，可以直接静默或简短致意，不需要把判定过程冗长解释一遍。
3. **完成后报告而非请示**：写完后向用户**汇报已完成的事实**（"已更新 X 文档第 N 节"），而不是反过来问用户"我打算更新 X 文档，要继续吗？"。
4. **真实落地优先**：每一次声称的文档变更都必须**真实通过 `edit` / `write` 工具落地**——禁止只输出"我已完成"的叙述文字而不实际写入。完成后建议自检（`bash` 查询文件时间戳 / 读改后内容 / 看 changelog 末尾）。
5. **拿不准时主动深读**：workflow 04 中规定的"必须深读 diff"情形（🔴 / 接口文件 / >500 行 / 多新建文件），LLM 必须自己执行 `git show <hash>` 等命令获取信息，不得因为信息不全就停下来问用户。
6. **批量同步统一处理**：一次收到多笔 commit（如 commitCount > 1），逐笔评级后统一执行更新；不要单独问用户"是否要逐个处理"。

**反例**（禁止的行为模式）：
- ❌ "我计划做以下三件事：A/B/C，要继续吗？"
- ❌ "我已完成 X 文档更新"——但实际上没调用任何 `edit` 工具
- ❌ "信息有点不全，请你提供完整 diff 给我"——本来该自己跑 `git show`

**正例**（鼓励的行为模式）：
- ✅ 直接完成更新，然后汇报："已自主完成：更新 tech/X.md 第 5 节 + changelog 追加一笔；本次评级 🟡。"
- ✅ 多 commit 一次完成所有文档更新，最后给一份合并汇报。

## 核心方法论（必读）

本 Skill 提炼出 **6 条可复用的核心方法论**，所有 workflow 与模板都围绕它们展开：

1. **三色影响等级**（🟢/🟡/🔴）—— 决定 commit 是否触发文档更新
2. **三列模块索引表**（模块 / 关键路径 / 设计分析）—— overview 的核心结构
3. **tech 单篇四段式**（设计动机 → 核心抽象 → 优点总结 → 监控信号）—— 框架分析的标准结构
4. **首扫三阶段**（仓库扫描 → overview 编写 → tech 拆篇）
5. **changelog 写法规范**（hash + 标题 + 影响等级 + 文档更新动作）
6. **何时主动深读 diff**（避免一律读全 diff 浪费 token，也避免轻判）

详细规则见 `workflows/` 目录。

## 两种触发路径

### 路径 A：首次建立知识库

触发词：「给 X 仓库建知识库」「梳理这个仓库」

**询问用户的关键信息**（缺一不可）：
1. 仓库的本地绝对路径（如 `/Users/x/Dev/repo`）
2. 知识库输出位置（用户指定，本 Skill 不预设默认值）
3. 仓库简短描述（一句话定位，帮助判断深度）

**执行流程**（依次读取并遵循）：
- `workflows/01-initial-scan.md` —— 全仓扫描方法论
- `workflows/02-overview-writing.md` —— overview.md 编写规范
- `workflows/03-tech-analysis.md` —— tech/ 单篇分析规范
- 引用 `templates/overview.template.md` 与 `templates/tech-doc.template.md` 作为骨架

**最终产出**：
```
<用户指定的知识库目录>/
├── overview.md
├── maintenance.md
├── tech/
│   └── <module>.md  × N
└── changelog/
    └── YYYY-MM.md
```

### 路径 B：增量更新分析

触发词：「这次 commit 要不要更新文档」「分析 commit 影响」「commit 是否需要同步知识库」

**前提**：知识库已存在，使用者会提供 commit hash / diff / commit message。

**执行流程**：
- `workflows/04-incremental-update.md` —— commit 影响判定与文档更新方法
- `workflows/05-changelog-rules.md` —— changelog 写作规则
- 必要时回到 `workflows/03-tech-analysis.md` 重做某模块的 tech 文档

**输出动作**（择一或组合）：
- 🟢 低影响 → 仅追加 changelog 一笔
- 🟡 中影响 → 修改相关 tech 文档对应章节 + changelog
- 🔴 高影响 → 修改 tech 文档 / 新增 tech 文档 / 必要时更新 overview + changelog

## 工作守则

1. **不臆造**：所有"模块结构""设计动机"必须以源码、官方架构文档、commit 记录为依据；推测时必须明示 "推测"。
2. **三色判断要保守**：拿不准时上调一级（🟡 优先于 🟢），宁可多更新文档也不漏掉重要变化。
3. **保持中立**：tech 文档讨论"为什么这样设计、有何优点"，不评价代码作者、不输出主观褒贬。
4. **对齐已有结构**：增量更新时，新文档段落要与已有 tech 文档的写作风格、缩进、标题层级一致。
5. **优先官方架构文档**：很多仓库 `docs/architecture/` 已经有官方设计说明，应先读再做二次梳理，不要重复发明。
6. **写入必验证**：声称完成的每笔文档变更，都要用 `read`（必要时用 `bash` 查询文件时间戳） 验证已落盘，不能只依赖工具调用的成功返回——避免"幻觉式汇报"。

## 文件索引

```
SKILL.md                                # 本文件
workflows/
  01-initial-scan.md                    # 阶段 1：全仓扫描方法论
  02-overview-writing.md                # 阶段 2：overview.md 编写规范
  03-tech-analysis.md                   # 阶段 3：tech/ 单篇分析规范
  04-incremental-update.md              # 阶段 4：commit 影响分析
  05-changelog-rules.md                 # 阶段 5：changelog 写作规则
templates/
  overview.template.md                  # overview 骨架
  tech-doc.template.md                  # tech 单篇骨架
  maintenance.template.md               # maintenance.md 骨架
  changelog.template.md                 # changelog 月度文件骨架
```

激活本 Skill 后，按照"路径 A 或 B"读取对应 workflow 文档，并对照模板执行。
