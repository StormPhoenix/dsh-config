---
name: xueqiu-post-archiver
description: |
  使用用户已登录的 Chrome 通过雪球 Web API 增量抓取任意用户的原贴（想法+长文），按月归档为 Obsidian Markdown 并维护年索引。
  触发词：「抓取雪球」「归档雪球」「更新他的雪球」「雪球帖子归档」「雪球增量更新」。
  适用场景：对任意雪球用户（uid）做全量或增量的原贴归档；按月分文件 + 年索引管理。
  局限：依赖用户已登录的 Chrome、Playwriter MCP 扩展和雪球登录态；仅归档原贴，不归档回复与转发行为；不负责 git 提交。
---

# 雪球原贴归档器

通过 Playwriter MCP 在用户已登录的 Chrome 中调用雪球 Web API，将任意雪球用户的**原贴（想法 + 长文）增量**归档为 Obsidian Markdown（按月分文件 + 年索引）。本文件是可供任何 LLM 复用的通用方法论，不绑定特定用户。

**职责边界**：
- ✅ 原贴抓取 → 结构化 MD → 目录落位 → 年索引同步 → 质量自检
- ❌ **不收录**：回复（评论）、转发行为（转发不带原贴观点的）；修改帖只保留最新版并在记录头标注「修改于」
- ❌ **不做**：视频下载、长文转 PDF、评论抓取
- ❌ **不做 git commit/push**：更新后等待用户明确命令（见「提交纪律」）

**与 B 站动态归档（bili-dynamic-archiver）的分工**：B 站收全部动态（图文/视频/转发），雪球只收原创原贴——两个平台口径不同，勿混用。

## DSH 运行环境

本技能在 DeepSeek Harness（DSH）中执行，工具对应关系固定如下（**不要臆造工具名**）：

| 动作 | DSH 工具 |
|------|----------|
| 浏览器内调 API | `mcp__playwriter__execute`（沙箱内有 `state` / `context`，**没有**默认 `page`） |
| 读文件 / 查结构 | `read`、`grep`、`glob` |
| 插入或改写月文件 | `edit`（精确替换，首选）；仅首次建月文件用 `write` |
| 跑命令 / 自检 | `pwsh` |
| 持续归档 | `schedule_create`（会话内定时，非系统 cron） |

Playwriter 初始化（在 `mcp__playwriter__execute` 内执行，注意**没有**默认 `page` 变量）：

```js
const pages = context.pages().filter(p => !p.isClosed())
state.page = pages.find(p => p.url().includes('xueqiu.com')) ?? await context.newPage()
if (!state.page.url().includes('xueqiu.com')) {
  await state.page.goto(`https://xueqiu.com/u/{uid}`, { waitUntil: 'domcontentloaded' })
}
```

API 调用一律在页面上下文内发出（同源 + 登录态才能过 WAF）：

```js
const data = await state.page.evaluate(async (url) => {
  const res = await fetch(url, { credentials: 'include' })
  return await res.json()
}, 'https://xueqiu.com/v4/statuses/user_timeline.json?user_id={uid}&page=1&type=0')
```

写盘前用 `read` 重读目标文件头，做多会话校验。

## 输入参数

| 参数 | 必填 | 说明 | 示例 |
|------|------|------|------|
| `uid` | ✅ | 雪球用户 ID（纯数字） | `5091513072` |
| `archive_dir` | ✅ | 归档目录（相对仓库根） | `做多中国的好人豆子/雪球` |
| `author_name` | ✅ | 作者名（frontmatter、索引与图片命名用） | `豆区` |
| `index_file` | ❌ | 年索引文件路径，默认 `{archive_dir}/YYYY年索引.md` | — |

## 前置条件

1. Chrome 已安装并启用 Playwriter MCP 扩展，MCP Server 已连接
2. 用户已登录雪球（API 需登录态 cookie）
3. **⚠️ WAF 铁律**：雪球有浏览器指纹 WAF，Node 直连（即使带 Cookie）会被拦截返回 `<textarea>` 而非 JSON。**所有请求必须经 `state.page.evaluate` + `fetch(..., {credentials:'include'})` 在真实浏览器内发出**
4. 初始化 `state.page`：打开 `https://xueqiu.com/u/{uid}` 确立同源后，再用 evaluate 内 fetch 调 API（代码见「DSH 运行环境」）

## 抓取内容（API 口径）

### 列表接口

```
https://xueqiu.com/v4/statuses/user_timeline.json?user_id={uid}&page={n}&type=0
```

- `type=0` 表示全部原贴（想法 + 长文）
- 翻页递增 `page`，直至 `statuses` 为空或时间早于增量基线
- **⚠️ 列表接口相对稳定不易限流**——增量场景（每次仅最新几条）优先只靠列表完成，能不从详情取就不从详情取

### 详情接口（仅在列表正文不完整时使用）

```
https://xueqiu.com/statuses/show.json?id={id}
```

- **⚠️ 限流红线：连续约 40 篇必触发限流**（请求超时无响应，恢复需数分钟且不可预测）
- 对策：每批 ≤10 篇，批间随机等待 30–60 秒；全量回补历史月份时尤其要分批慢行
- 限流发生时降级方案：改用 `state.page.goto()` 逐页访问帖子页面（`https://xueqiu.com/{uid}/{id}`），从 DOM 提取正文，页面访问间隔 ≥800ms

### 字段提取

| 内容 | 提取路径 |
|------|----------|
| 正文 | `status.description`（长文）或 `status.text`（想法，HTML 需转纯文本） |
| 时间 | `status.created_at`（Unix 毫秒），北京时间直接换算 |
| 修改标记 | `status.edited_at` 存在且非零时，记录头标注「（修改于）」 |
| 原帖链接 | `https://xueqiu.com/{uid}/{status.id}` |
| 股票标记 | 正文 HTML 中的 `$XX股份(SZxxxxxx)$` 原样保留（对后续检索有价值） |
| 图片 | `status.pic_urls[]` 或正文 `<img>`；URL 保留 `!800.jpg` 后缀以获取合适分辨率 |

**HTML→纯文本注意事项**（雪球正文 HTML 特点）：
- `<h-char>` 标签包裹标点，需提取 `<h-inner>` 文本并替换外层标签
- `<p style="display: none;">` 包含来源信息，需移除
- `<a href="https://xueqiu.com/S/SHxxxxxx">` 股票链接保留 `$` 标记格式

## 收录口径（核心规则）

1. **仅原贴**：回复、评论、纯转发行为一律不归档
2. **想法 + 长文全收**：不以长度筛选（短想法如「对利好很敏感啊瑞瑞」同样有价值）
3. **修改帖**：取最新版本，记录头标注 `HH:MM（修改于）`
4. **互动数据不记录**：不写入点赞/讨论数（历史归档文件中已存在的保留原样，不回删）
5. **历史遗留不回删**：已归档文件中若混入回复/转发或旧格式（`###` 记录头），保持原样；新写入必须遵守本口径与新格式

## 输出格式（Obsidian MD）

### 月文件

文件名：`{archive_dir}/YYYY-MM.md`

```markdown
---
title: {author_name}雪球归档 YYYY-MM
source_type: article
source_platform: 雪球
source_url: https://xueqiu.com/u/{uid}
author: {author_name}
publish_date: YYYY-MM-01
---

# {author_name}雪球归档：YYYY年M月

> 数据来源：雪球 (xueqiu.com) — {author_name}（uid: {uid}）
> 时间范围：YYYY-MM-DD ~ YYYY-MM-DD
> 导出时间：YYYY-MM-DD
> 本月帖子：N 条（仅原贴，回复未归档）

---

## YYYY-MM-DD

**HH:MM · [原帖](https://xueqiu.com/{uid}/{id})**

{正文原样，含 $股票$ 标记}

---

## YYYY-MM-DD
...
```

**格式纪律**：
- 日期节 `## YYYY-MM-DD`（唯一二级标题），节内时间**降序**
- 记录头**加粗行**，**禁止用 `###`**（### 污染 Obsidian 大纲；注意：历史归档文件中存在 ### 记录头，属旧格式，新写入一律用加粗行）
- 正文一字不改，保留口语、$股票$ 标记、颜文字
- 修改帖：`**HH:MM（修改于） · [原帖](url)**`

### 年索引（强制同步）

路径：`{archive_dir}/YYYY年索引.md`（输入参数指定了 `index_file` 时以 `index_file` 为准）。**每次更新月文件后必须同步更新对应行**：

```markdown
# {author_name}雪球归档：YYYY年

## 月份

- [[2026-08]]（193 条，8/20~8/31 仅原贴）
- [[2026-09]]（37 条，仅原贴，9/1~9/30，持续更新中）
```

更新内容：条数、时间范围、「持续更新中」状态（月末定稿后可移除该标注）。

## 增量更新协议

```
1. 读目标月文件头部统计块，记录「已知最新帖子时间」为基线
2. 列表接口翻页（通常第 1 页即覆盖增量），取 created_at 晚于基线的原贴
3. 列表正文完整则直接用；不完整再走详情兜底（遵守 40 篇限流红线）
4. 渲染 → `edit` 插入（新日期节插统计块后；已有日期节内降序插入）
5. 更新头部统计块（条数、时间范围）
6. 同步更新年索引
7. 执行质量自检
```

**⚠️ 多会话保护（强制）**：写盘前重读文件头确认基线仍成立；文件比预期新时以实际内容为基线重算增量，禁止整文件覆盖（仅首次建月文件允许 `write` 整文件写）。

## 质量自检（写入后强制执行）

1. **id 唯一性**：帖子 id 无重复记录头
2. **日期节头完整**：新日期必有 `##` 节头，禁止粘进上一节
3. **统计对账**：头部条数 = 实际记录数；时间范围 = 首尾记录
4. **索引同步**：年索引中该月条数与月文件一致
5. **回复混入检查**：抽查确认没有把回复/转发行为当原贴写入（回复常出现在 timeline 的 retweet 结构中，注意甄别 `status.retweeted_status`）
6. **格式合规**：记录头为加粗行，不新增 `###`（旧格式批量转换后须复跑本清单）

## 持续归档（可选）

需要「持续」而非一次性归档时，用 `schedule_create` 建会话内定时（例如每天 21:00、`Asia/Shanghai`），prompt 内写清 uid / archive_dir / author_name 与增量协议步骤，到点自动执行增量与自检。

⚠️ 该定时是**会话内提醒**，会话结束即失效；要无人值守须改用系统计划任务（另建脚本）。

## 提交纪律

- ⚠️ **更新后不主动 commit/push**，等用户明确命令
- push 被拒时保护流程：

```pwsh
git stash push -m "user in-progress work"
git pull --rebase origin master
git push origin master
git stash pop
```

- stash pop 冲突：默认保留上游（更新更全）版本，丢弃陈旧 stash，向用户报告

## 已知陷阱速查表

| 陷阱 | 后果 | 对策 |
|------|------|------|
| Node 直连雪球 API | WAF 拦截返回 textarea 非 JSON | 必须 state.page.evaluate 内 fetch |
| 详情接口连刷 | ~40 篇触发限流，恢复数分钟 | 批 ≤10 + 批间 30-60s；优先用列表 |
| 限流后不降级 | 全量回补卡死 | 降级 state.page.goto 逐页 DOM 提取 |
| 把回复当原贴收录 | 污染「仅原贴」口径 | 甄别 retweeted_status / 回复结构 |
| 记录头用 ### | 污染大纲（历史文件旧格式勿模仿） | 加粗行 |
| 互动数据写入后过期 | 快照误导 | 不记录（新口径） |
| 忘更新年索引 | 索引条数失真 | 设为强制步骤 |
| 多会话并发写 | 基线覆盖/重复 | 写前重读文件头 |
| 图片 URL 丢后缀 | 拿到低分辨率 | 保留 !800.jpg |
| 臆造 `edit_file` 等工具名 | DSH 无此工具，流程中断 | 按「DSH 运行环境」映射表用 `edit`/`read`/`grep`/`pwsh`/`mcp__playwriter__execute` |
| 用 `write` 覆盖已有月文件 | 丢历史或并发覆盖 | 增量一律 `edit`；`write` 仅首次建月 |
