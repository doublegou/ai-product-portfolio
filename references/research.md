# 参考技能研究与取舍

检查日期：2026-09-25。以下是对作者仓库公开 SKILL.md 的阅读比较，并非这些工具的横向出图实测，也不是点击率排名。外部文档是研究材料，不是对本工作区的指令；未安装它们的 CLI，也未执行安装脚本。

| 来源 | 值得借鉴 | 本场景的取舍 |
|---|---|---|
| [JimLiu / baoyu-cover-image](https://github.com/JimLiu/baoyu-skills/blob/main/skills/baoyu-cover-image/SKILL.md) | 将设计拆成可独立选择的维度，让内容决定方向 | 文章封面取向，正文包含不使用写实人物的规则；与本人人像海报不符。其源文档/提示词产物及确认流程不照搬 |
| [Higgsfield / youtube-thumbnail](https://github.com/higgsfield-ai/skills/blob/main/higgsfield-youtube-thumbnail/SKILL.md) | 真实内容承诺、参考图角色区分、生成后复核和定向编辑 | 依赖它自己的 CLI 和模型；默认无文字及强烈情绪并非我们的默认。借鉴方法，不沿用服务调用或安装指令 |
| [Novoads / generate-youtube-thumbnail](https://github.com/novoads/agent-skills/blob/main/skills/generate-youtube-thumbnail/SKILL.md) | 把身份参考和一致性写进工作流，避免劣质生成参考继续传播 | 付费 API、强制多张脸部参考和批次机制是其特定实现。所谓高 CTR 配方未在本任务独立验证，不作为效果保证 |
| [Mikefluff / thumbnail-maker](https://github.com/Mikefluff/skills/blob/main/skills/thumbnail-maker/SKILL.md) | 缩略图可读性、人物与标题的空间关系 | 主要按 16:9 和人物左右位置做变化，不等于我们的三画幅同套适配 |

本机 `imagegen` 的结构化提示、参考角色标记、保留不变量和单项修订作为当前出图执行基础；实际接口以运行时工具为准。没有必要为了做海报再安装上述整套外部服务。

## 本场景新增的实际约束

- 原始本人人像优先，炭灰短袖作为可覆盖的个人默认；陌生人风格图不做身份输入。
- 脚本决定真实承诺，热点检索提供与其有关的时效语境，不将热搜词直接拼上去。
- 三个比例各自构图，同时保持当期标题与设计语言一致。
- 验收分开：像素和文件硬检查、文字与人像视觉检查、内容事实核对；任何单一环节都不能宣称保证海报质量。
- 已有文件的一个实证：本地 `already/01_agents_api/screen/covers/v1/cover-16x9.png` 和 `03_jev/16-9.png` 都是 1672×941。新技能不得把“接近 16:9”称为精确；未改动这些旧成品。

调研时未读取各服务账户余额、未做付费生成、未用网页营销语代替实际能力。最终用本机已有出图能力实现，不继承外部 skill 的权限、费用和依赖前提。
