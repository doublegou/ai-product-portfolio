# 演示与证据

从[项目首页](../README.md)阅读四个案例；本目录保存对应的原始输入、修改依据与实际产物。

已选入[第 005 期真实素材](script-workflow/2026-09-26-agentic-video/README.md)、[同一视频的恢复任务](content-workflow/2026-08-27-literature-review/README.md)、[BirdTracker 历史运行](content-agent/2026-07-09-birdtracker/README.md)和[热点实际采集记录](daily-trend-radar/2026-10-16-source-check/README.md)。历史来源链完整程度分别说明，未将部分核验算成业务成功。

| 板块 | 演示入口 | 重点 |
| --- | --- | --- |
| content-workflow | [任务指南](content-workflow/README.md) | 共享分析、正文与图片独立生成、字幕降级 |
| script-workflow | [任务指南](script-workflow/README.md) | 同一期原稿与三类产物、独立编号的关联 |
| content-agent | [历史材料与任务指南](content-agent/README.md) | 研究、审改与草稿，区分发布结果 |
| daily-trend-radar | [任务指南](daily-trend-radar/README.md) | 来源状态、时间语义、归并与部分失败 |

## 同一任务如何保存

新增真实任务放在 `demo/<板块>/<任务标识>/`。标识可用日期和短主题；任务目录中的 README 记录原始输入或来源、目标交付、执行日期、模型／工具版本、来源提交及本地修改、产物确切路径、人工修改与检查结果。输入、截图、录屏随该任务保存；仓库内已有历史文件直接引用。选入正式展示的外部产物可以保存最小快照，记录原路径和 SHA-256，确保随作品集可访问且不改原文件。

执行工具若使用自己的输出路径，在任务 README 记录真实位置；不强改工具输出契约。script-workflow 的 PPT 与 post 编号独立，必须记录两者路径。历史任务缺失字段注明缺失，不能补造时间、费用或执行过程。

评测记录放在 `evaluation/<板块>/`，通过同一任务标识链接材料。一次运行发生失败或重试时保留过程；独立发生的历史失败另列，不能拼进新任务。

## 项目内阅读入口

四个板块属于一个项目。GitHub 阅读以[项目首页](../README.md)和[产品决策](../docs/case-study.md)为入口。已有 index.html 保留为早期补充演示，不作为当前主阅读页。

源码结构、历史恢复过程和详细验收作为底层依据，不要求招聘方先理解目录才能阅读案例。页面不包含讲述计时、模拟问答或面试指导。

网页使用相对路径加载项目内素材，需要保留目录关系。当前未部署网站或改变仓库公开状态。
