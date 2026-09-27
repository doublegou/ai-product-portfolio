---
name: note-images
description: Plan and generate a Xiaohongshu image-card series directly from an existing task-folder analysis.md. Use when the user asks for 小红书配图、图文卡片、图片规划、plan.md, or images for a YouTube-derived note. First write plan.md beside analysis.md; save prompt records in task-level prompts/ and confirmed raster images in result/.
---

# 小红书图片规划与生成

本 Skill 基于 `baoyu-xhs-images` 的卡片拆解、视觉风格和版式方法，适配本项目固定管线。

## 输入输出契约（最高优先级）

输入是一个任务目录中的 `analysis.md`。任务目录通常形如：

`<project-root>/YYYY-MM-DD_HHmm_中文主题/`

只允许按下列结构工作：

```text
任务目录/
├── analysis.md          # 唯一内容来源，由 yt-analysis 生成
├── plan.md              # 本 Skill 的图片内容规划
├── prompts/
│   └── NN-type-slug.md  # 每张图片的完整生成提示词
└── result/
    ├── post.md          # note-writer 可能并行生成；不得改动
    └── NN-type-slug.png
```

- 不创建第二份 `analysis.md`、`outline.md`、`source.md` 或独立的 `image-cards/` 工程。
- `plan.md` 必须和 `analysis.md` 同级。
- 只有用户确认 `plan.md` 后，才创建提示词和图片。
- 提示词写入任务目录下的 `prompts/`，与 `result/` 平级；图片只写入 `result/`。不得覆盖或改写 `result/post.md`。
- 如果 `plan.md`、提示词或目标图片已存在，直接用新版本替换旧版本，不创建 `backup`、版本化副本或其他历史文件。
- 重新规划或重新生成后，删除不再属于最终方案的旧提示词和旧图片。任务目录最终只保留当前有效的 `analysis.md`、`plan.md`、规范提示词、最终图片以及可能存在的 `result/post.md`。

## 第一步：独立读取并规划

1. 确认任务目录里存在且仅选中正确的 `analysis.md`。若用户给的是文件路径，以其父目录为任务目录。
2. 完整读取 `analysis.md`，重点使用三部分：概述、带时间戳的完整转译、二创方向。
3. 在不依赖 `post.md` 的情况下，提炼：主题、目标读者、最有价值的 1–2 个内容支点、封面钩子、收藏价值、可视化机会和滑动叙事。
4. 保留原内容的事实、因果、限定条件和关键例子，但重新组织为可脱离来源独立发布的小红书表达。页面最终文案不得出现“视频”“讲述者”“原视频”“原作者”“作者”“博主”“这期内容”“素材里”“字幕中”“分析文件显示”等来源依附表达。直接陈述可以成立的观点；需要保留数据边界时使用中性限定，不得伪装成用户亲自完成的调查。
5. 不编造个人体验、身份、数据或案例。没有用户提供的一手经历时，不写“我亲测”“我用了几个月”“我的客户”等。
6. 页数由内容体量和叙事层次决定，不设固定上限。短视频或单一主题通常使用 5–6 张；接近一小时、信息密集或包含多个完整章节的内容，可以使用 8 张或更多。始终选择能完整讲清主题的最少页数：每增加一页都要有独立价值，信息不足时减少，不为凑页数注水；也不要为了压页数牺牲必要解释。
7. 选择适合内容的风格、版式和配色。可用风格包括 `cute`、`fresh`、`warm`、`bold`、`minimal`、`retro`、`pop`、`notion`、`chalkboard`、`study-notes`、`screen-print`、`sketch-notes`；版式包括 `sparse`、`balanced`、`dense`、`list`、`comparison`、`flow`、`mindmap`、`quadrant`。
8. 写入前检查全部“页面文字、主标题、副标题与钩子”，搜索“视频、讲述者、原作者、作者、博主、素材、字幕、这期、analysis、YouTube”等来源痕迹；用于指代内容来源时必须先改写。通过检查后写入 `plan.md`，不要开始出图。

## `plan.md` 格式

```markdown
# 图片内容规划

## 整体方案

- 主题：
- 目标读者：
- 内容支点：
- 卡片数量：
- 叙事结构：
- 视觉风格：
- 默认版式：
- 配色：
- 选择理由：

## 第 1 张｜封面

- 文件名：01-cover-topic.png
- 页面目的：
- 版式：sparse
- 主标题：
- 副标题：
- 页面文字：
- 视觉构想：
- 下一页钩子：

## 第 N 张｜内容/结尾

- 文件名：NN-content-topic.png
- 页面目的：
- 版式：
- 主标题：
- 页面文字：
- 视觉构想：
- 下一页钩子：
```

页面文字必须是准备用在图上的最终文案，而不是抽象说明或关键词草稿。每张只承担一个主要任务；封面优先简洁、强钩子，内容页优先完整、可独立阅读，结尾负责总结或形成可执行清单。不要为了“爆款”制造夸张数字、伪造权威或虚假体验。

除封面外，每张内容页都必须满足以下要求：

- 让读者不看 `post.md`，只按顺序阅读图片，也能理解整篇内容在讲什么、为什么以及怎么做。
- 使用完整句子或有明确逻辑关系的信息块，保留必要的因果、限定条件、方法和结论；不要只堆名词、短语、口号或关键词。
- 在同一页内形成一个闭合的小主题：先说明问题或结论，再给解释、步骤或判断依据。不能把理解当前页所必需的信息全部推到下一页。
- 页数减少时优先合并重复的铺垫、案例或总结页，不得通过删掉关键解释把内容压缩成提纲。
- 控制单页文字层级与可读性，但“短”不是最高目标；内容完整、逻辑清楚高于刻意留白。

## 第二步：确认闸门

写完 `plan.md` 后，在聊天中给出可点击路径，并简洁汇报：卡片数量、叙事结构、风格、配色和各页主题。然后停止，等待用户确认或调整。

除非用户在当前请求中明确说“直接生成”“不用确认”“按默认出图”或同义表达，否则不得生成任何图片。

## 第三步：生成图片

得到确认后：

1. 完整读取 [references/workflows/prompt-assembly.md](references/workflows/prompt-assembly.md) 与 [references/elements/canvas.md](references/elements/canvas.md)。
2. 根据选定风格读取对应的 `references/presets/<style>.md`；如指定配色，再读取 `references/palettes/<palette>.md`。
3. 在任务目录下的 `prompts/` 中先写好并核验每张图的完整提示词，命名为 `NN-type-slug.md`。
4. 使用当前 Codex 的原生 `imagegen` Skill/工具生成位图，默认比例 `3:4`。禁止用 SVG、HTML、Canvas 或代码绘图替代。
5. 先生成第 1 张封面，再把封面作为第 2 张及之后图片的风格参考，以保持人物、线条和配色一致。
6. 每张图都以 `plan.md` 的最终页面文字为准。文字错误、乱码或可读性差时，直接修订原提示词并替换失败图片；不保留失败提示词或失败图片，禁止在成图上用代码覆盖文字。
7. 只重试失败项一次，不重复生成已成功的图片。
8. 完成后检查文件数量、命名、比例、文字可读性、内容准确性和系列一致性；同时确认任务目录中没有 `backup`、旧版本或不再使用的图片，再给出所有最终结果文件的链接。

## 与正文分支的关系

`note-images` 与 `note-writer` 都直接读取同一份 `analysis.md`，两者互不依赖。需要同时创作时，可在同一轮分别产出 `plan.md` 和 `result/post.md`；正文完成不代表图片方案已确认，图片确认也不授权改写正文。
