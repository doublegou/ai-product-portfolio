# AI 产品作品集

三个独立完成的项目，分别探索 AI 工作流、端侧语音产品和科研建模应用。每个案例从具体使用任务出发，展示产品取舍、实际产物、技术实现与验证结果。

| 项目 | 核心问题 | 值得先看的证据 |
| --- | --- | --- |
| [内容生产 Agent 与 Skill 工作流](projects/01-content-agent/README.md) | 如何将内容任务拆成可复用、可修改、可验收的工作流 | 四类真实任务；图文、演示、文案与多比例封面；失败恢复与模型降级 |
| [StayWord](projects/02-stayword/README.md) | 如何在手机资源与后台限制下，交付本地录音、转写、摘要体验 | 实机视频与六步使用过程；双端模型路由；中断恢复与降级方案 |
| [RiverSR](projects/03-riversr/README.md) | 如何判断模型进入陌生水系后还能承担哪些任务 | 5,600 站点严格验证；RF / XGBoost 比较；尾部失败与不发布决策 |

## 从结果继续深入

**内容工作流：**从资料到可发布准备的多种产物，处理需求变更、部分执行和交接。[阅读完整案例](projects/01-content-agent/docs/case-study.md)

**StayWord：**从音频到可核验的本地笔记，把模型能力、系统限制和用户等待体验一起设计。[观看实机演示](projects/02-stayword/demo/assets/stayword-demo-2026-09-25.mp4) · [阅读技术方案](projects/02-stayword/docs/technical-design.md)

**RiverSR：**从数据与验证条件出发选模型；平均误差改善仍不足以批准高值筛查。[查看结果与复核](projects/03-riversr/evaluation/README.md)

各项目首页可以独立阅读；源码、运行指南与证据放在项目内。历史演示、当前实现、本轮验证与后续方案分别标注，没有将规划值或推测写成已测成绩。

<details>
<summary>维护、来源与运行说明</summary>

- [优化标准](PORTFOLIO_PLAN.md) · [进度与后续验证](ROADMAP.md)
- [来源与版本](SOURCES.md) · [一致性核对](SOURCE_CHECK.md) · [来源清单](sources.json)

本仓库独立维护，修改不回推源工程。源码、模型和素材保留各自作者、许可与版本记录，未统一重新授权。StayWord 模型和原生库使用 Git LFS；RiverSR 的完整 HPC 模型归档不等同于仓库内紧凑验证材料。运行要求见各项目 Quick start。

当前仓库保持私有；作品集整理完成不代表已授权公开所有素材。

</details>
