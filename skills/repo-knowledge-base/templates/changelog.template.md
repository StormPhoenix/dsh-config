# Changelog · {YYYY} 年 {MM} 月

> 本月共同步 {N} 笔 commit。🔴 高影响 {X} 笔 / 🟡 中影响 {Y} 笔 / 🟢 低影响 {Z} 笔。

## 主线总结

> 月度有 ≥ 10 笔 commit 时建议补充本节，否则可省略。
>
> 写作要点：
> - 本月 2-3 条主要工作主线（结合 commit 标题归纳）
> - 是否有设计层面的重大变化（🔴 commit）
> - 是否进入新阶段（发布准备 / 生态建设 / 技术债清理 / 功能爆发）

{此处填写本月主线总结}

## 详细条目

### 第 1 周（{YYYY-MM-DD} ~ {YYYY-MM-DD}）

- {YYYY-MM-DD} `{shortHash}` 🟢 {commit subject}
- {YYYY-MM-DD} `{shortHash}` 🟡 {commit subject} → {文档更新动作}
- {YYYY-MM-DD} `{shortHash}` 🔴 {commit subject} → {文档更新动作}

### 第 2 周（{YYYY-MM-DD} ~ {YYYY-MM-DD}）

- ...

### 第 3 周（{YYYY-MM-DD} ~ {YYYY-MM-DD}）

- ...

### 第 4 周（{YYYY-MM-DD} ~ {YYYY-MM-DD}）

- ...

---

> 条目格式约定（详见 Skill 的 workflows/05-changelog-rules.md）：
>
> - 标准格式：`- {YYYY-MM-DD} \`{shortHash}\` {color} {标题}{补充说明}`
> - shortHash：取前 7-10 位
> - color：🟢 / 🟡 / 🔴 三选一
> - 标题：commit message 的第一行（subject），原文照抄
> - 补充说明：仅 🟡 / 🔴 必须，紧跟在标题后，说明文档更新动作
>
> 多笔同主线 commit 可分组缩进展示：
>
> ```markdown
> **{主线主题}（{日期}）**：
> - {YYYY-MM-DD} `{hash}` 🟡 {subject} → {文档动作}
> - {YYYY-MM-DD} `{hash}` 🟢 {subject}
> ```
