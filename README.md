# AI 产品作品集

我独立完成了三个项目，分别探索 AI 工作流、端侧语音产品和科研建模应用。这里记录我如何定义问题、选择方案、交付产品，以及根据使用和实验结果调整方向。

| 项目 | 核心问题 | 主要成果与决策 |
| --- | --- | --- |
| [内容生产 Agent 与 Skill 工作流](projects/01-content-agent/README.md) | 如何将内容任务拆成可复用、可修改、可验收的工作流 | 四类真实任务；图文、演示、文案与多比例封面；失败恢复与模型降级 |
| [StayWord](projects/02-stayword/README.md) | 如何在手机资源与后台限制下，交付本地录音、转写、摘要体验 | 从首版到 App Store 发行与反馈迭代；英国区付费效率榜前 100（第三方记录）；双端 AI 与资源取舍 |
| [RiverSR](projects/03-riversr/README.md) | 如何判断模型进入陌生水系后还能承担哪些任务 | 5,600 站点严格验证；RF / XGBoost 比较；尾部失败与不发布决策 |

## 从结果继续深入

**内容工作流：**从资料到可发布准备的多种产物，处理需求变更、部分执行和交接。[阅读完整案例](projects/01-content-agent/docs/case-study.md)

**StayWord：**从音频到可核验的本地笔记，把模型能力、系统限制和用户等待体验一起设计。[观看实机演示](projects/02-stayword/demo/assets/stayword-demo-2026-09-25.mp4) · [阅读技术方案](projects/02-stayword/docs/technical-design.md)

**RiverSR：**从数据与验证条件出发选模型；平均误差改善仍不足以批准高值筛查。[查看结果与复核](projects/03-riversr/evaluation/README.md)

各项目首页呈现产品过程与关键决策，关联页面提供技术实现、实际产物和实验依据。

<details>
<summary>维护、来源与运行说明</summary>

- [优化标准](PORTFOLIO_PLAN.md) · [进度与后续验证](ROADMAP.md)
- [来源与版本](SOURCES.md) · [一致性核对](SOURCE_CHECK.md) · [来源清单](sources.json)

本仓库独立维护，修改不回推源工程。源码、模型和素材保留各自作者、许可与版本记录，未统一重新授权。StayWord 模型和原生库使用 Git LFS；RiverSR 的完整 HPC 模型归档不等同于仓库内紧凑验证材料。运行要求见各项目 Quick start。

当前仓库保持私有；作品集整理完成不代表已授权公开所有素材。

</details>
