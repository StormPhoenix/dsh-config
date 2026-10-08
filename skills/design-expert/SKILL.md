---
name: design-expert
description: 品牌设计系统参考库。用户指定品牌风格、需要设计 Token 或生成一致 UI 时使用；按需读取 54 份本地设计资料。
---

## DSH 使用约定

本技能提供指令和本地资料，不注册新工具。仅调用当前会话实际提供的工具；若工具通过 `run_code` 暴露，在其中调用 `tools.<工具名>`，不要直接调用未声明的工具。

技能内的参考资料路径相对宿主提供的技能资源根目录（`Base directory for this skill`）解析；用户文件、调研结果和代码输出路径相对当前工作区或用户确认的输出目录解析，不写入技能资源目录。只按需读取资料。

读取文本使用 `read({file_path, offset, limit})`，搜索内容使用 `grep({pattern, path})`，发现文件使用 `glob({pattern, path})`；`glob` 不列目录，目录存在性或目录列表使用 `bash`。修改现有文件前先 `read`，精确修改使用 `edit({file_path, old_string, new_string})`，创建文件使用 `write({file_path, content})`。不得覆盖未经确认的已有输出；写入后重新读取验证。

# 品牌设计风格专家

内置 **54 个知名网站的 DESIGN.md 设计系统规范**，一键复用品牌级 UI 风格。

## 什么是 DESIGN.md？

[DESIGN.md](https://stitch.withgoogle.com/docs/design-md/overview/) 是 Google Stitch 提出的概念 — 一份纯文本格式的设计系统文档，AI Agent 可以读取它来生成风格一致的 UI。只需将它放到项目根目录，任何 AI 编码工具就能理解你的 UI 应该长什么样。

## 使用方法

### 1. 用户指定品牌 → 直接匹配

```
用户："做一个 Stripe 风格的落地页"
→ 读取 references/stripe.md
→ 将内容复制到用户项目根目录作为 DESIGN.md
→ 使用其中的设计 Token 生成 UI 代码
```

### 2. 用户想浏览 → 筛选推荐

```
用户："有哪些暗色风格的设计系统？"
→ 推荐：Vercel、Cursor、ElevenLabs、Resend、Warp、Supabase 等
→ 用户选择后，加载对应参考文件
```

### 3. 用户未指定风格 → 智能推荐

当用户要求构建 UI **但没有指定品牌或风格**（如"帮我做一个落地页"、"写一个 dashboard"），**主动推荐** 3-5 个设计系统：

| 项目类型 | 推荐风格 | 原因 |
|---|---|---|
| **SaaS 官网 / 落地页** | Stripe、Vercel、Linear | 经典高转化 SaaS 风格，简洁专业 |
| **开发者工具 / 技术产品** | Vercel、Cursor、Raycast、Supabase | 暗色系、代码友好、极客气质 |
| **AI 产品 / 聊天界面** | Claude、Mistral AI、ElevenLabs | AI 原生设计语言，温暖或未来感 |
| **金融科技产品** | Stripe、Revolut、Coinbase | 信任感、精密感、数据密集 |
| **效率工具 / 生产力产品** | Notion、Linear、Superhuman | 极简、信息密度高、键盘优先 |
| **电商 / 消费品牌** | Airbnb、Apple、Spotify | 视觉驱动、大图、情感化设计 |
| **内部后台 / 仪表盘** | Sentry、PostHog、ClickHouse | 数据密集型、暗色仪表盘 |
| **创意 / 设计工具** | Figma、Framer、Clay | 大胆配色、动感十足 |
| **企业级 / B2B** | IBM、HashiCorp、MongoDB | 稳重、结构化、设计系统成熟 |

**推荐流程示例：**

```
用户："帮我做一个 AI 聊天产品的界面"
→ 助手回复："推荐以下设计风格供你选择：
   1. 🟠 Claude — 温暖柔和的赤陶色调，编辑式布局，适合对话产品
   2. 🟣 Mistral AI — 法式工程极简，紫色调，优雅专业
   3. 🎬 ElevenLabs — 暗色电影感，波形美学，适合音频/多模态
   4. ⬛ Vercel — 黑白精准，极致简约
   5. 🟢 VoltAgent — 终端风格，翠绿高亮，适合技术型 AI
   选一个编号，我用对应的设计系统帮你生成。"
→ 用户选择后 → 加载参考文件 → 生成 UI
```

**如果用户说"随便"或"你决定"：**
- 默认使用 **Vercel**（最安全的通用选择：简洁、现代、专业）
- 告知选择并提供更换选项："我先用 Vercel 风格（简约黑白），不喜欢随时换。"

## 可用的设计系统

### AI 与机器学习

| 网站 | 参考文件 | 风格特点 |
|------|----------|----------|
| Claude | `references/claude.md` | 温暖赤陶色调，干净的编辑式布局 |
| Cohere | `references/cohere.md` | 鲜明渐变色，数据密集型仪表盘风格 |
| ElevenLabs | `references/elevenlabs.md` | 暗色电影风 UI，音频波形美学 |
| Minimax | `references/minimax.md` | 大胆暗色界面配霓虹高亮 |
| Mistral AI | `references/mistral.ai.md` | 法式工程极简主义，紫色调 |
| Ollama | `references/ollama.md` | 终端优先，黑白极简 |
| OpenCode AI | `references/opencode.ai.md` | 开发者导向暗色主题 |
| Replicate | `references/replicate.md` | 干净白底，代码优先 |
| RunwayML | `references/runwayml.md` | 电影风暗色 UI，富媒体布局 |
| Together AI | `references/together.ai.md` | 技术感，蓝图风格设计 |
| VoltAgent | `references/voltagent.md` | 深黑画布，翠绿高亮，终端原生 |
| xAI | `references/x.ai.md` | 纯粹黑白，未来主义极简 |

### 开发者工具与平台

| 网站 | 参考文件 | 风格特点 |
|------|----------|----------|
| Cursor | `references/cursor.md` | 流畅暗色界面，渐变高亮 |
| Expo | `references/expo.md` | 暗色主题，紧凑字距，代码中心 |
| Linear | `references/linear.app.md` | 超级极简，精准，紫色点缀 |
| Lovable | `references/lovable.md` | 活泼渐变，友好开发者风格 |
| Mintlify | `references/mintlify.md` | 干净，绿色点缀，阅读优化 |
| PostHog | `references/posthog.md` | 有趣的刺猬品牌，开发者友好暗色 UI |
| Raycast | `references/raycast.md` | 流畅暗色镀铬，鲜明渐变高亮 |
| Resend | `references/resend.md` | 极简暗色主题，等宽字体点缀 |
| Sentry | `references/sentry.md` | 暗色仪表盘，数据密集，粉紫高亮 |
| Supabase | `references/supabase.md` | 暗色翠绿主题，代码优先 |
| Superhuman | `references/superhuman.md` | 高端暗色 UI，键盘优先，紫光效果 |
| Vercel | `references/vercel.md` | 黑白精准，Geist 字体 |
| Warp | `references/warp.md` | 暗色 IDE 风格界面，块状命令 UI |
| Zapier | `references/zapier.md` | 温暖橙色，插画驱动的友好风格 |

### 基础设施与云服务

| 网站 | 参考文件 | 风格特点 |
|------|----------|----------|
| ClickHouse | `references/clickhouse.md` | 黄色点缀，技术文档风格 |
| Composio | `references/composio.md` | 现代暗色搭配彩色集成图标 |
| HashiCorp | `references/hashicorp.md` | 企业级简洁，黑白风格 |
| MongoDB | `references/mongodb.md` | 绿叶品牌，开发者文档导向 |
| Sanity | `references/sanity.md` | 红色点缀，内容优先编辑式布局 |
| Stripe | `references/stripe.md` | 标志性紫色渐变，300 字重的优雅 |

### 设计与生产力

| 网站 | 参考文件 | 风格特点 |
|------|----------|----------|
| Airtable | `references/airtable.md` | 多彩、友好、结构化数据风格 |
| Cal.com | `references/cal.md` | 干净中性 UI，开发者导向简约 |
| Clay | `references/clay.md` | 有机形状，柔和渐变，艺术指导布局 |
| Figma | `references/figma.md` | 鲜明多色，活泼且专业 |
| Framer | `references/framer.md` | 大胆黑蓝，动效优先，设计导向 |
| Intercom | `references/intercom.md` | 友好蓝色调，对话式 UI 模式 |
| Miro | `references/miro.md` | 明亮黄色点缀，无限画布风格 |
| Notion | `references/notion.md` | 温暖极简，衬线标题，柔和表面 |
| Pinterest | `references/pinterest.md` | 红色点缀，瀑布流网格，图片优先 |
| Webflow | `references/webflow.md` | 蓝色点缀，精致的营销网站风格 |

### 金融科技与加密

| 网站 | 参考文件 | 风格特点 |
|------|----------|----------|
| Coinbase | `references/coinbase.md` | 干净蓝色身份，信任感，机构风格 |
| Kraken | `references/kraken.md` | 紫色点缀暗色 UI，数据密集仪表盘 |
| Revolut | `references/revolut.md` | 流畅暗色界面，渐变卡片，金融精度 |
| Wise | `references/wise.md` | 明亮绿色点缀，友好且清晰 |

### 企业与消费

| 网站 | 参考文件 | 风格特点 |
|------|----------|----------|
| Airbnb | `references/airbnb.md` | 温暖珊瑚色点缀，摄影驱动，圆角 UI |
| Apple | `references/apple.md` | 高端留白，SF Pro 字体，电影级图像 |
| BMW | `references/bmw.md` | 暗色高端表面，精密德国工程美学 |
| IBM | `references/ibm.md` | Carbon 设计系统，结构化蓝色调 |
| NVIDIA | `references/nvidia.md` | 绿黑能量感，技术力量美学 |
| SpaceX | `references/spacex.md` | 纯粹黑白，全幅图像，未来感 |
| Spotify | `references/spotify.md` | 鲜明绿色暗底，大胆字体，专辑封面驱动 |
| Uber | `references/uber.md` | 大胆黑白，紧凑字体，都市能量 |

## 每个 DESIGN.md 包含的内容

每个文件遵循 [Google Stitch DESIGN.md 格式](https://stitch.withgoogle.com/docs/design-md/format/)，包含 9 大板块：

1. **视觉主题与氛围** — 整体调性、信息密度、设计哲学
2. **色彩系统与角色** — 语义化名称 + 色值 + 功能角色
3. **字体规则** — 字体家族、完整层级表
4. **组件样式** — 按钮、卡片、输入框、导航及各种状态
5. **布局原则** — 间距刻度、网格、留白哲学
6. **层次与阴影** — 阴影系统、表面层级
7. **设计规范与禁忌** — 设计护栏和反面案例
8. **响应式行为** — 断点、触摸目标、折叠策略
9. **Agent 提示指南** — 快速色彩参考、可直接使用的生成提示

## 注意事项

- 每个参考文件较大（数百行），请按需读取单个文件，不要一次加载全部
- 参考文件中的色值、字体等信息基于采集时间，实际品牌可能已更新
- 设计 Token 可直接用于 CSS / Tailwind / Vue 组件开发
- 推荐先阅读"Agent 提示指南"（第 9 节）获取快速上手信息
