# Workflow 01 · 仓库初始扫描

本文档指导 LLM 完成首扫阶段——把一个陌生仓库的全貌摸清楚，为后续的 overview 与 tech 文档编写打基础。

## 目标

- 摸清仓库的**顶层结构**（语言、构建系统、是否 monorepo）
- 摸清仓库的**逻辑模块边界**（哪些目录代表"功能模块"，哪些是配套设施）
- 摸清仓库**已有的官方文档资产**（README、docs、ADR），避免重复造轮子
- 形成一份**模块候选清单**，供后续 overview 与 tech 选题使用

## 必读优先级（自上而下）

请按顺序读取，**先看顶层、再看入口、最后选择性下钻**。不要一头扎进具体源码。

### Step 1 · 顶层结构（必做）

```
列目录（depth=2）       仓库根
读取                    README.md 全文
读取                    package.json / Cargo.toml / pyproject.toml / go.mod / pom.xml 等构建清单
读取（如存在）          docs/ 下所有 .md 文件清单（不读全文，先列）
读取（如存在）          ARCHITECTURE.md / CONTRIBUTING.md / docs/architecture/
列目录                  scripts/ / tools/（构建脚本入口）
```

**判断点**：
- monorepo 还是单包？（看 packages/ workspaces 字段、Cargo workspace 等）
- 主语言 + 主框架是什么？
- 是否有官方架构文档？（**有的话必读，不要重复编写**）

### Step 2 · 入口与依赖图（必做）

针对每个发现的"包"或"应用"，找到入口文件并粗读：

```
应用层入口          src/main.* / index.* / app.ts / cmd/main.go
库的导出层          src/index.* / lib.rs / __init__.py
框架挂载点          electron 的 main.ts、Vue 的 App.vue、Spring 的 Application.java
```

**目的**：从入口顺藤摸瓜，建立"哪些目录是被入口直接调用的、哪些是间接的"的初步图谱。

### Step 3 · 关键约定文件（选做）

- `tsconfig.json` / `babel.config.*` —— 看 path alias、模块边界
- `.eslintrc` / 规则文件 —— 推断团队风格
- `Makefile` / `justfile` / `npm scripts` —— 看常用命令对应什么模块
- `CHANGELOG.md` —— 看最近的迭代主题，辅助判断模块成熟度

### Step 4 · 测试目录（选做）

测试目录的组织方式经常**直接揭示模块划分**：
- `app/test/foo.test.ts` 暗示 `app/src/foo` 是一个独立模块
- `packages/agent/test/plugin/*.test.ts` 暗示 plugin 是 agent 的子模块

读测试**目录树**（不读测试代码本身），快速识别模块粒度。

## 如何识别"逻辑模块边界"

不要把每个文件夹都当成一个模块，应当用以下信号合并/拆分：

### ✅ 是一个独立模块（应该出现在 overview 模块清单里）

- 有自己的 README / 设计文档
- 有独立的 entry/index 文件，被外部调用
- 在测试目录里有专属子目录
- 在 commit 历史里被频繁单独命名（如 "feat: 优化 plugin 系统"）
- 内部文件 ≥ 3 个且语义聚合

### ❌ 不是独立模块（不应单列）

- 仅放工具函数或类型定义的 utils/ types/
- 单个组件文件夹（除非该组件是核心抽象）
- 配置文件目录
- 自动生成的代码

### 模块粒度建议

中大型仓库通常能识别出 **8 - 20 个模块**。如果识别出超过 25 个，说明粒度太细，需要合并；如果少于 5 个，说明粒度太粗或仓库太小。

## 推荐工具调用模板

```
通过 bash 列出目录 path=<repo_root>, depth=2（将目标路径转为绝对路径；不使用 shell 读取文件正文）            # 顶层结构
read({file_path: "<repo_root>/README.md",})
read({file_path: "<repo_root>/package.json",})        # 或对应构建清单
通过 bash 列出目录 path=<repo_root>/docs, depth=3（将目标路径转为绝对路径；不使用 shell 读取文件正文）       # 列官方文档
glob({pattern: "**/*ARCHITECTURE*", path: "<repo_root>"})
glob({pattern: "**/*README*", path: "<repo_root>"})

# 选择性下钻（每个候选模块 1-2 次）
通过 bash 列出目录 path=<候选模块>, depth=2（将目标路径转为绝对路径；不使用 shell 读取文件正文）
read({file_path: "<候选模块的入口文件>", limit: 200,})
```

## 完成本阶段的产出

在脑内或用 TODO 形式记下：

1. **仓库一句话定位**（语言 / 框架 / 用途）
2. **模块候选清单**（8-20 个，每个一句话职责）
3. **官方文档清单**（哪些 docs 已经写过，避免重复）
4. **重点关注的模块**（commit 历史频繁、明显有架构亮点的，作为 tech 单篇候选）
5. **可疑边界**（不确定要不要算独立模块的，留待 overview 阶段决定）

完成后进入 `02-overview-writing.md`。

## 注意事项

- **不要在首扫阶段写文档**，专注摸清结构。先扫完再动笔，避免边扫边写视野被局部带偏。
- **不要读完每一个源码文件**，那样会浪费大量 token。首扫只需读"足以判断模块边界"的最少文件。
- **遇到官方架构文档要重视**，它通常已经把模块切分讲清楚了，你只需要二次组织而非重新发明。
- **monorepo 要注意层级**，每个包内部可能再有自己的子模块（如 `packages/agent/src/plugin/`）。
