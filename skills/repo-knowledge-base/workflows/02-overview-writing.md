# Workflow 02 · overview.md 编写规范

本文档指导 LLM 把首扫得出的模块候选清单整理成正式的 `overview.md`。这是知识库的入口文档，必须做到"读完它就能在脑内建立仓库的全貌"。

## 设计原则

1. **入口性**：overview 是知识库的目录，不应包含框架设计深度分析（那些放 tech/）
2. **可索引性**：每个模块条目都应能链到对应的源码路径与 tech 文档
3. **稳定性**：overview 的结构应稳定，**不应每次 commit 都改**——只在新增/合并模块时更新
4. **结构化**：用表格而非散文罗列模块，让 LLM 后续检索更容易

## 标准章节顺序

按以下章节顺序编写，缺一不可：

1. **仓库定位**（1 段）
2. **顶层结构**（目录树或表格）
3. **核心模块清单**（三列索引表 —— 必填，本文档核心）
4. **辅助模块清单**（轻量列表）
5. **关键技术栈**（一句话点名）
6. **官方文档索引**（指向仓库内已有的设计文档）
7. **tech 文档索引**（指向本知识库 tech/ 下的深度分析）
8. **维护提示**（一句话指向 maintenance.md）

## 第 3 章 · 核心模块清单（最关键）

这是 overview 的核心，必须采用**三列索引表**形式：

| 模块 | 关键路径 | 设计分析 |
|---|---|---|
| 模块 A | `path/to/module-a/` | 见 [tech/module-a.md](tech/module-a.md) |
| 模块 B | `path/to/module-b/` | 见 [tech/module-b.md](tech/module-b.md) |
| 模块 C | `path/to/module-c/` | （暂未单独分析）一句话职责 |

### 三列的写作规范

- **模块**：使用人类可读的中文/英文名，不要直接抄目录名（除非目录名本身就是好的命名）
- **关键路径**：用反引号包住相对路径，monorepo 要写完整（如 `packages/agent/src/plugin/`）；多个路径用逗号分隔，不超过 3 个
- **设计分析**：
  - 已有 tech 文档 → 写 markdown 链接 `见 [tech/xxx.md](tech/xxx.md)`
  - 暂无 tech 文档 → 写一句话职责描述（≤ 30 字），并在末尾标注 "（暂未单独分析）"

### 排序规则

模块按**重要性 + 依赖关系**排序：
1. 核心抽象模块在前（如协议层、内核、上下文编排）
2. 业务功能模块居中（如 plugin 系统、工具体系）
3. 集成 / 边界模块在后（如 IPC、UI、持久化）

## 第 4 章 · 辅助模块清单

辅助模块用简单列表，不需要表格：

```markdown
## 辅助模块

- `scripts/` —— 开发与构建脚本（dev、release、自动修复）
- `examples/` —— 示例资源（如 X 主题、Y 模板）
- `docs/` —— 官方文档源
```

辅助模块**不写 tech 文档**，永远不需要。

## 第 5 章 · 关键技术栈

只写**对理解架构有帮助的**，不要罗列 package.json 里所有依赖：

```markdown
## 关键技术栈

- **语言**：TypeScript 5.x（严格模式）
- **运行时**：Electron 主进程 + Node.js + 浏览器渲染进程
- **框架**：Vue 3 (Composition API) / Vite
- **核心库**：xx（用于 yy） / zz（用于 ww）
```

## 第 6 章 · 官方文档索引

指向仓库**内置**的设计文档（不是本知识库的产出）：

```markdown
## 官方文档索引

- [docs/architecture/overview.md](../<repo>/docs/architecture/overview.md) —— 官方架构总览
- [docs/architecture/plugin-system.md](../<repo>/docs/architecture/plugin-system.md) —— 插件系统设计
```

如果仓库没有官方文档，本节写 "（仓库无官方架构文档）"。

## 第 7 章 · tech 文档索引

列出本知识库 `tech/` 目录下所有深度分析文档，按主题分组：

```markdown
## tech 文档索引

### 内核与协议
- [tech/harness-and-runsession.md](tech/harness-and-runsession.md)
- [tech/protocol-and-ipc.md](tech/protocol-and-ipc.md)

### 工具与扩展
- [tech/plugin-system.md](tech/plugin-system.md)
- [tech/tools-and-permissions.md](tech/tools-and-permissions.md)

### UI 与桌面
- [tech/electron-main-architecture.md](tech/electron-main-architecture.md)
```

## 第 8 章 · 维护提示

简短一段：

```markdown
## 维护提示

- 本知识库的更新规则与 commit 影响判定方法见 [maintenance.md](maintenance.md)
- 历次更新记录见 [changelog/](changelog/)
- 后续 commit 监控应严格按 maintenance.md 的三色规则执行
```

## 长度控制

- overview.md 总长度建议 **300 - 600 行**之间
- 太短（< 200）→ 模块清单不充分，回去补
- 太长（> 800）→ 把深度分析下放 tech 文档

## 何时需要更新 overview

只有在以下情况才修改 overview：

- 🔴 新增或删除一个核心模块（更新第 3 章索引表）
- 🔴 模块大面积重命名 / 路径迁移
- 🔴 新增 tech 文档（更新第 7 章索引）
- 🔴 关键技术栈变更（如换框架、升级到不兼容的大版本）
- 🟡 模块职责发生明显变化（更新对应行的"设计分析"一句话）

普通 commit **不应**触发 overview 修改——它是稳态文档。

## 工具调用建议

完成 overview 通常只需要：

```
read({file_path: "<repo>/README.md"})
read({file_path: "<repo>/package.json"})
通过 bash 列出目录 <repo>, depth=3（将目标路径转为绝对路径；不使用 shell 读取文件正文）
通过 bash 列出目录 <repo>/<每个模块>, depth=2（将目标路径转为绝对路径；不使用 shell 读取文件正文）
read({file_path: "<重点入口文件>", limit: 150})
```

不需要读源码细节——细节留给 tech 文档。

完成 overview 后进入 `03-tech-analysis.md`。
