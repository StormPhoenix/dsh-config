---
name: bili-dynamic-archiver
description: |
  使用用户已登录的 Chrome 通过 B 站动态 API 增量抓取任意 UP 主的动态（图文/视频/转发），按月归档为 Obsidian Markdown。
  触发词：「抓取B站动态」「归档B站动态」「更新他的动态」「B站动态归档」「增量更新动态」。
  适用场景：对任意 B 站用户（uid）做全量或增量动态归档；按月分文件管理；可选图片下载到 Attachments/。
  局限：依赖用户已登录的 Chrome、Playwriter MCP 扩展和 B 站登录态；仅归档动态，不含视频下载、转录总结、评论抓取；不负责 git 提交。
---

# B 站动态归档器

通过 Playwriter MCP 在用户已登录的 Chrome 中调用 B 站动态 Web API，将任意 UP 主的动态**增量**归档为 Obsidian Markdown（按月分文件）。本文件是可供任何 LLM 复用的通用方法论，不绑定特定 UP 主。

**职责边界**：
- ✅ 动态抓取（图文/视频/转发）→ 结构化 MD → 目录落位 → 质量自检
- ❌ 不做：视频下载（用 `bili-archiver`）、转录总结（用 `live-knowledge-distiller`）、雪球归档（雪球只归原创长文，平台口径不同）、评论抓取
- ❌ **不做 git commit/push**：更新后等待用户明确命令（详见「提交纪律」）

## 输入参数

调用方（用户或主 agent）需提供：

| 参数 | 必填 | 说明 | 示例 |
|------|------|------|------|
| `uid` | ✅ | 目标 B 站用户 ID（纯数字） | `519457153` |
| `archive_dir` | ✅ | 归档目录（相对仓库根） | `做多中国的好人豆子/想法` |
| `author_name` | ✅ | 作者名（frontmatter 与图片命名用） | `做多中国的好人豆子` |
| `download_images` | ❌ | 是否下载图片到 `Attachments/`，默认 `false` | `true` |

## 前置条件

1. Chrome 已安装并启用 Playwriter MCP 扩展，MCP Server 状态为已连接
2. 用户已登录 B 站（API 需携带登录态 cookie）
3. 初始化 `state.page`：

```js
const pages = context.pages().filter(p=>!p.isClosed());
state.page = pages.find(p=>p.url().includes('bilibili')) ?? await context.newPage();
if(!state.page.url().includes('bilibili'))
  await state.page.goto(`https://space.bilibili.com/${uid}/dynamic`,{waitUntil:'domcontentloaded'});
```

所有 API 请求通过 `state.page.evaluate` 内的 `fetch(..., {credentials:'include'})` 发出，自动携带登录态。

## 抓取内容（API 口径定版）

### 列表接口

```
https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/all?host_mid={uid}&offset={offset}&platform=web&features=itemOpusStyle
```

- 翻页：取响应中 `data.offset` 作为下一页参数，直至目标时间或 offset 为空
- **过滤规则**：丢弃纯点赞/投币类无正文动态；`FORWARD`（转发）保留
- 列表仅用于**发现新动态 id 与时间**，不作为正文来源

### ⚠️ 铁律 A：时间换算

动态时间取 `modules.module_author.pub_ts`（Unix 秒），**必须 +28800 换算北京时间**：

```js
const f = t => new Date((Number(t)+28800)*1000).toISOString().slice(5,16).replace('T',' '); // "MM-DD HH:MM"
```

❌ 禁止用响应中的其他 UTC 日期字段切分月份/日期——曾导致 7 条动态被误标到前一天。

### ⚠️ 铁律 B：详情兜底

DRAW/OPUS 类型动态在**列表接口中正文经常为空**（带图帖子 desc 为空是常态），必须逐条调用详情接口兜底：

```
https://api.bilibili.com/x/polymer/web-dynamic/v1/detail?id={id}&features=itemOpusStyle
```

- **每批 ≤10 条**，条间间隔 ≥400ms（限速防风控）
- ⚠️ detail 请求**必须带** `features=itemOpusStyle`，否则返回老格式（正文在 `desc.text` 而非 opus 结构），口径不一致

### 正文与附件提取优先级

| 内容 | 提取路径 |
|------|----------|
| 标题 | `major.opus.title` |
| 正文 | `major.opus.summary.text` > `module_dynamic.desc.text` |
| 图片 | `major.draw.items[].src` 或 `major.opus.pics[].url` |
| 视频 | `major.archive`（`bvid` / `title` / `duration_text`），链接 `https://www.bilibili.com/video/{bvid}` |
| 转发原文 | `item.orig`：被转发者 `orig.modules.module_author.name` + 原文（同上优先级），原内容可能已不可见（取不到时标注「原内容已不可见」） |

## 增量更新协议

```
1. 读目标月文件头部统计块，记录「已知最新动态时间」作为基线
2. 列表翻页，取所有 pub_ts 晚于基线的动态 id
3. 分批详情兜底（≤10 条/批）
4. 渲染为 MD 记录（见输出格式）
5. edit_file 插入：新日期节插到文件头部统计块之后；已有日期节内按时间降序插入
6. 更新头部统计块（条数、时间范围）
7. 执行质量自检（见下）
```

**⚠️ 多会话保护（强制）**：写盘前必须重新读目标文件头，确认基线统计与已知最新 id 仍然成立。多轮会话/并行会话可能已更新过文件——若发现文件比预期新，以**实际文件内容**为基线重算增量，禁止覆盖写入（整文件 overwrite 仅限首次建月文件）。曾发生两次并行会话覆盖冲突，此步不可跳过。

## 输出格式（Obsidian MD）

### 月文件结构

文件名：`{archive_dir}/YYYY-MM.md`（按动态发布时间的北京时间归月；新月份自动建文件）

```markdown
---
title: {author_name}B站动态归档 YYYY-MM
source_type: article
source_platform: Bilibili
source_url: https://space.bilibili.com/{uid}/dynamic
author: {author_name}
publish_date: YYYY-MM-01
---

# {author_name}B站动态归档：YYYY年M月

> 数据来源：哔哩哔哩 (bilibili.com) — {author_name} (uid: {uid})
> 时间范围：YYYY-MM-DD ~ YYYY-MM-DD
> 导出时间：YYYY-MM-DD
> 本月动态：N 条（其中 X 条为转发）

---

## YYYY-MM-DD

**HH:MM · [原帖](https://t.bilibili.com/{id})**

**{标题（无标题则省略此行）}**

{正文，原样保留}

![](图片URL)

---

**HH:MM · [原帖](https://t.bilibili.com/{id2})**

...
```

### 记录级格式规则

- **日期节**：`## YYYY-MM-DD`（唯一允许的二级标题），节内严格按发布时间**降序**
- **记录头**：`**HH:MM · [原帖](https://t.bilibili.com/{id})**` —— **加粗行，禁止用 `###`**（`###` 会污染 Obsidian 大纲，曾 354 处返工）
- **标题**：动态有标题时单独加粗一行
- **正文**：一字不改，保留口语、颜文字、复读刷屏（人格色彩是归档价值的一部分）；超长复读可省略标注 `……（复读刷屏）`
- **视频**：`**HH:MM · [视频](url)｜《{title}》**` + 时长 + 一句话内容概述
- **转发**：正文后加 `> ↪️ **转发自**：{name} — {原内容概述或原文}`
- **图片**：`![](URL)`（原始链接保留）；`download_images=true` 时下载到 Attachments 并改用 WikiLink（见下）

### 可选：图片下载（download_images=true）

- 目标目录：仓库 `Attachments/`（**扁平存放**，遵循仓库图片规范）
- 命名：`{author_name}_dynamic_{yyyymmdd}_{N}.jpg`（描述性前缀防重名）
- MD 引用切换为 Obsidian WikiLink：`![[{文件名}.jpg]]`

## 质量自检（写入后强制执行）

1. **id 唯一性**：search_content 检查记录头中的动态 id，无重复
2. **日期节头完整**：新日期必须有 `##` 节头，禁止粘进上一日期节（曾发生 `---###` 粘连与节头丢失）
3. **占位符污染扫描**：检查 WAIT / BROKEN / STRIPPED / TODO 等生成过程残片
4. **头部统计对账**：统计块条数 = 实际记录数；时间范围 = 首尾记录时间
5. **id 差集对账**（增量场景）：本轮取到的全部新 id 均已落盘

## 提交纪律

- ⚠️ **更新后不主动 commit/push**，必须等用户明确命令（如「提交」「push」）
- push 被拒（远端有新提交）时执行保护流程：

```bash
git stash push -m "user in-progress work"
git pull --rebase origin master
git push origin master
git stash pop
```

- stash pop 冲突时：先读冲突内容判断新旧，**默认保留上游（更新更全）版本**，丢弃陈旧 stash，并向用户报告

## 已知陷阱速查表

| 陷阱 | 后果 | 对策 |
|------|------|------|
| 用 UTC 字段切日期 | 日期节整体错位 | pub_ts + 28800 |
| 空正文不做详情兜底 | 大批内容缺失 | detail ≤10 条/批 |
| detail 缺 features 参数 | 返回老格式口径混乱 | 始终带 features=itemOpusStyle |
| 多会话并发写 | 基线覆盖/重复插入 | 写前重读文件头校验 |
| `###` 作记录头 | 破坏 Obsidian 大纲 | 强制加粗行 |
| 长输出单次写盘 | 截断/占位符污染 | 分批 edit_file |
| 空写后残留旧重复记录 | 同 id 双份 | 修复时删旧位 + 全文 id 校验 |
| push 被拒硬 push | 丢远端提交/冲突 | stash→rebase→push→pop |
