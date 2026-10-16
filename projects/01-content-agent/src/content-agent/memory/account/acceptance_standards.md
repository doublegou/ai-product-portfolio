# Acceptance Standards

## Minimum Passing Standard

一篇草稿必须同时通过：

- Product fit：明确服务 ISS Tracker、BirdTracker、Math Puzzle、Soulnio 之一，或服务整个产品宇宙
- Persona fit：像独立产品创作者，不像工具推荐号、AI 教程号、赚钱号
- Platform fit：标题、封面、开头有小红书点击理由
- Specificity：正文有具体场景、功能、动作和边界
- Factual safety：所有产品事实都能被产品资产支持
- Usefulness：读者看完知道它适合谁、什么时候用、怎么开始
- Spreadability：标题、封面、开头和正文结构要有明确点击理由、保存价值或自然讨论点

## Required Fields Quality

product:

- 必须是 ISS Tracker、BirdTracker、Math Puzzle、Soulnio、Product Universe 之一
- 单产品帖子必须写具体产品，不要用 Product Universe 回避选择

post_archetype:

- 必须说明本篇内容类型，例如 场景种草、功能解释、使用教程、产品故事、设计取舍、兴趣入门、系列栏目
- 内容类型要和正文结构一致

target_scene:

- 必须命名一个具体使用场景或读者瞬间
- 不要只写“产品推广”“独立开发者”“普通用户”

traffic_hook:

- 必须说明本篇的点击理由、封面理由、讨论点或收藏理由
- 不要写空泛营销判断，例如“吸引用户点击”

topic:

- 必须具体到产品和场景
- 不要只写“产品推广”或“独立开发”

title:

- 需要能让目标用户知道为什么点开
- 不使用夸张收益、恐吓、伪爆款话术

hook:

- 必须命名一个真实场景、问题或好奇心
- 不要直接进入功能清单

body:

- 至少 300 个中文字符
- 必须包含一个明确生活瞬间
- 必须写 1-3 个真实功能
- 必须包含一个使用步骤或观察建议
- 必须包含一个边界说明

takeaways:

- 3-5 条
- 每条是读者能记住的产品价值或使用方法

hashtags:

- 至少 4 个
- 至少 2 个与产品领域相关
- 至少 1 个与平台人群或使用场景相关

cover_text:

- 优先 12 个中文字符以内
- 适合直接放封面
- 不要像广告语

reason:

- 必须说明为什么这个角度适合当前产品和账号

## Review Score Rules

通过标准（与 src/create/runtime.py 的默认门槛一致；模型评分仅用于流程判定）：

- overall_score >= 8.6
- safety_score >= 9.2
- publishability_score >= 8.4
- virality_score >= 8.2
- title_score >= 8.0
- hook_score >= 8.0
- save_value_score >= 7.8
- differentiation_score >= 7.8
- blocking_issues 为空
- 本地 quality_guard 没有事实风险

优秀标准：

- overall_score >= 8.8
- virality_score >= 8.5
- title_score >= 8.4
- hook_score >= 8.4
- save_value_score >= 8.2
- comment_potential_score >= 8.0
- 读者场景清楚
- 产品边界清楚
- 标题和正文有一个可复用的方法

## Blocking Issues

出现以下任意情况必须打回：

- 写成 content-agent 或 AI 工作流本身
- 写成小众 App 推荐合集
- 写成 AI 工具教程
- 写成赚钱、收入、下载量、排名故事
- 编造用户反馈、评论区、真实经历
- 编造产品未确认功能
- 承诺一定看见、一定识别、一定提升、一定疗愈
- Soulnio 写成算命或结果预测
- Math Puzzle 写成提高智商或成绩
- BirdTracker 写成专业识别保证
- ISS Tracker 写成 NASA 官方合作或保证裸眼可见

## Revision Priorities

改稿顺序：

1. 先删掉事实风险
2. 再拉回产品场景
3. 再增强标题和开头
4. 再补使用步骤和边界
5. 最后调整语气和标签

不要为了追求小红书感牺牲事实准确性。
