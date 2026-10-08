# {仓库名} 工程知识库 · Overview

> 本文档是 {仓库名} 工程知识库的入口与索引。
> 仓库本地路径：`{绝对路径}`
> 知识库最后更新：{YYYY-MM-DD}

## 1. 仓库定位

{用 1-2 段说清：这个仓库是什么、解决什么问题、目标用户是谁、与同类项目的差异（如果有）}

示例：
> Paras 是一个面向 LLM Agent 的 Electron 桌面应用框架，主打"harness 与 LLM 边界清晰"的运行时设计……

## 2. 顶层结构

```
{绘制 depth=2 的目录树，仅保留有意义的目录，去掉 dist/node_modules/.git 等}

repo-root/
├── packages/
│   ├── agent/           # 核心 Agent 运行时
│   ├── protocol/        # 协议定义
│   └── ...
├── app/                 # Electron 应用层
├── docs/                # 官方文档
├── examples/            # 示例资源
└── scripts/             # 构建/发布脚本
```

仓库类型：{单包 / monorepo（pnpm workspaces / Cargo workspace / Lerna / 其他）}

## 3. 核心模块清单

| 模块 | 关键路径 | 设计分析 |
|---|---|---|
| {模块 A} | `{path}` | 见 [tech/{a}.md](tech/{a}.md) |
| {模块 B} | `{path}` | 见 [tech/{b}.md](tech/{b}.md) |
| {模块 C} | `{path}` | （暂未单独分析）{一句话职责} |
| ... | ... | ... |

> 排序原则：核心抽象 → 业务功能 → 集成边界。
> 三列含义：模块名 / 主要源码路径 / 是否有专门 tech 文档。

## 4. 辅助模块

- `{path1}` —— {一句话用途}
- `{path2}` —— {一句话用途}
- `{path3}` —— {一句话用途}

> 辅助模块不写专门的 tech 文档。

## 5. 关键技术栈

- **语言**：{TypeScript / Rust / Go / ...}
- **运行时**：{Node / Electron / Browser / Tauri / ...}
- **核心框架**：{Vue 3 / React / Axum / Spring Boot / ...}
- **关键库**：
  - `{lib-1}` —— {作用}
  - `{lib-2}` —— {作用}

## 6. 官方文档索引

> 指向**仓库内置**的设计文档（不是本知识库的产出）。

- [{相对仓库路径}](#) —— {一句话说明}
- [{相对仓库路径}](#) —— {一句话说明}

> 如仓库无官方架构文档，本节写："（仓库无官方架构文档）"。

## 7. tech 文档索引

### {分组主题 1：如内核与协议}

- [tech/{file-1}.md](tech/{file-1}.md) —— {一句话主题}
- [tech/{file-2}.md](tech/{file-2}.md) —— {一句话主题}

### {分组主题 2：如工具与扩展}

- [tech/{file-3}.md](tech/{file-3}.md) —— {一句话主题}

### {分组主题 3：如 UI 与桌面}

- [tech/{file-4}.md](tech/{file-4}.md) —— {一句话主题}

## 8. 维护提示

- 本知识库的更新规则与 commit 影响判定方法见 [maintenance.md](maintenance.md)
- 历次更新记录见 [changelog/](changelog/)
- 后续 commit 监控应严格按 maintenance.md 的三色规则执行

---

> 模板字段约定：
> - `{仓库名}` —— 替换为实际仓库名
> - `{绝对路径}` —— 替换为本地仓库路径
> - `{YYYY-MM-DD}` —— 替换为知识库最后更新日期
> - `{模块 A}` / `{path}` 等 —— 按实际填充
