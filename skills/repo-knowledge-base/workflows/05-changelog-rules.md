# Workflow 05 · changelog 写作规则

本文档规定知识库 `changelog/` 目录下文件的组织与写作规范，用于持续记录 commit 同步与文档更新历史。

## 文件组织

```
changelog/
├── YYYY-MM.md       # 按月分文件，如 2026-06.md
├── YYYY-MM.md
└── ...
```

- **按月切分**，一个月一个文件，避免单文件无限增长
- 文件名严格 `YYYY-MM.md`（4 位年 + 减号 + 2 位月）
- **不要按周或按季度**，月度是经过验证的合理粒度

## 单条 changelog 条目格式

每条 commit 占一行（或 1-3 行），标准格式：

```markdown
- {YYYY-MM-DD} `{shortHash}` {color} {标题}{补充说明}
```

### 字段规则

- **日期**：commit author date 的日期部分（不带时间）
- **shortHash**：取前 7-10 位
- **color**：🟢 / 🟡 / 🔴 三选一
- **标题**：commit message 的第一行（subject），原文照抄
- **补充说明**（仅 🟡 / 🔴 必须）：紧跟在标题后，说明文档更新动作

### 示例

```markdown
- 2026-06-12 `5a82192` 🟢 style: 调整消息操作区布局并优化样式支持换行
- 2026-06-12 `76bca4b` 🔴 feat: 迁移 LLM Wiki 为资源内置插件 → 更新 overview 模块清单 + 新增 tech/llm-wiki.md 引用
- 2026-06-13 `c0c2218` 🟡 feat: 支持快捷键切换资源预览 → 更新 tech/electron-main-architecture.md 第 5 节
- 2026-06-14 `00c8e51` 🔴 refactor: 继续拆分 main 进程职责 → 更新 tech/electron-main-architecture.md 模块图
```

## 月度文件结构

每个 `YYYY-MM.md` 内部使用以下结构：

```markdown
# Changelog · YYYY 年 MM 月

> 本月共同步 N 笔 commit。🔴 高影响 X 笔 / 🟡 中影响 Y 笔 / 🟢 低影响 Z 笔。

## 主线总结

{每月初/末由 LLM 简要总结：本月作者主要在做什么主题，哪些是设计层面的重要变化}

## 详细条目

### 第 1 周（YYYY-MM-DD ~ YYYY-MM-DD）

- ...

### 第 2 周（YYYY-MM-DD ~ YYYY-MM-DD）

- ...
```

> "主线总结"非强制，月度有 ≥ 10 笔 commit 时建议补一段。

## 何时新建月度文件

- 当本月第一笔 commit 进入时，自动新建 `YYYY-MM.md`
- 跨月时不要在旧文件里追加新月份的条目
- 新建时使用 `templates/changelog.template.md` 作为骨架

## 写作要点

### ✅ 推荐做法

1. **保留原始 commit 标题**，不要二次改写——它是溯源依据
2. **🟡/🔴 必须写文档更新动作**，否则后续审计无法快速判断
3. **多笔 commit 主线相关时，可以分组缩进**：

```markdown
**插件工具策略改造主线（2026-06-14）**：
- 2026-06-14 `ccda038` 🟡 refactor: 调整插件工具策略保存入口 → 更新 tech/plugin-system.md 状态机小节
- 2026-06-14 `0db68d3` 🟢 fix: 同步插件工具策略保存状态
```

### ❌ 避免

- 把同一笔 commit 写成多行散记
- 用过于浪漫化的语言（"作者非常勤奋地" 之类）
- 在 changelog 里写设计分析（那是 tech 文档的事）
- 漏标 color

## 增量同步时的写入策略

每次收到新 commit 时：

1. 查 `changelog/YYYY-MM.md` 是否存在（按 commit author date 的月份）
2. 不存在 → `write` 创建（用模板）
3. 存在 → `edit` 在"详细条目"末尾追加
4. **追加位置在文件末尾的对应周组**，不要插到中间
5. 如果同一笔 commit 之前已记录（重复触发），跳过

## 月度总结的时机

- 每月最后一周，LLM 在处理新 commit 时，可以**主动**补写本月的"主线总结"段落
- 跨月第一笔 commit 进来时，**强烈建议**为上月补写主线总结（如果还没写）
- 主线总结要点：
  - 本月主要工作主题（2-3 条主线）
  - 是否有设计层面的重大变化
  - 是否进入了新阶段（如发布准备、生态建设、技术债清理）

## 常见错误

- **错误 1：把 changelog 当 release notes 写**
  → changelog 是开发轨迹日志，不是面向用户的发布说明
- **错误 2：每条都写一大段**
  → 单笔 commit 的 changelog 一行为主，最多 3 行；详细分析应该在 tech 文档或对话回复里
- **错误 3：色标省略**
  → 即便是 🟢，也必须写明，不能省

## 与其他工作流的关系

- 📥 **输入**：来自 `04-incremental-update.md` 的判定结果
- 📤 **输出**：成为 `maintenance.md` 历史回溯的依据
- 🔄 **不要**在 changelog 里重新做影响等级判断（在 04 已经判好了）
