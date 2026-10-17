# AI 产品作品集

**从用户任务出发，把 AI 能力做成可使用、可核验、可持续迭代的产品。**

我独立推进三个项目的产品设计、工程实现与迭代：内容生产工作流、端侧语音产品和科研建模应用。每个案例都展示实际产物，以及需求范围、模型选择、质量评估和资源投入背后的判断。

| 项目 | 要解决的问题 | 已交付的成果 |
| --- | --- | --- |
| [内容生产 Agent 与 Skill 工作流](projects/01-content-agent/README.md) | 同一期内容需要多种素材，要求变化后容易返工或交错版本 | 四类真实任务；正文与卡片、演示与封面、产品稿、选题简报 |
| [StayWord](projects/02-stayword/README.md) | 录音保存后，用户仍难以快速理解、回查和复用 | 已上架 iOS 产品；本地转写与摘要、时间戳回听、三类导出；双端工程 |
| [RiverSR](projects/03-riversr/README.md) | 如何为未采样河流提供预测，并判断哪些用途得到证据支持 | 5,600 站点数据主线、冻结模型与原始预测、信息增量检验、应用基准准备 |

## 内容生产：让修改能够传递到完整交付

我将选题研究、视频改编、口播素材和产品内容组织为四条可独立进入的路径。创作者按已有材料选择任务，在规划和验收节点修改，最终取用可编辑文件。

<table>
<tr>
<td width="65%"><img src="projects/01-content-agent/demo/script-workflow/2026-10-16-version-alignment/screenshots/page-05-step-3.png" alt="Agentic Video 口播配套演示的真实播放画面" width="520"></td>
<td width="35%"><img src="projects/01-content-agent/demo/content-workflow/2026-08-27-literature-review/generated-originals/03.png" alt="视频改编生成的引用核查卡片原图" width="220"></td>
</tr>
<tr><td>口播配套演示：将修订稿转成分步讲解。</td><td>图文卡片：让图片独立完成解释。</td></tr>
</table>

**代表性判断：**将共享分析、不同形式的表达和最终验收分开；已有演示时只生成文案与封面，改稿后检查关联素材。事实核验、文件规格和保存状态分别验收，模型自评分只作为参考。

**AI 实现：**字幕优先与 Whisper 转写兜底、参考图约束、有限审改、请求退避与失败恢复。下一阶段用约定交付完成率、人工修正时间和合格交付成本判断哪些步骤值得保留。

[查看完整项目](projects/01-content-agent/README.md) · [四类实际交付](projects/01-content-agent/demo/README.md) · [需求规划与 MVP](projects/01-content-agent/docs/case-study.md)

## StayWord：把端侧 AI 的限制转成可理解的体验

我围绕“录完之后怎样继续使用”设计产品：原音频提供依据，转写用于定位，摘要用于概览。iOS 已上架，并根据用户反馈迭代倍速、分享与设置；保留一次购买、本地核心处理的定位。

<table>
<tr>
<td><img src="projects/02-stayword/demo/assets/03-transcript-playback.jpg" alt="StayWord 分段转写与时间戳回听" width="220"></td>
<td><img src="projects/02-stayword/demo/assets/04-summary.jpg" alt="StayWord 实际生成的摘要" width="220"></td>
<td><img src="projects/02-stayword/demo/assets/05-export.jpg" alt="StayWord 分别导出音频、转写与摘要" width="220"></td>
</tr>
<tr><td>核对原话</td><td>理解重点</td><td>带走所需材料</td></tr>
</table>

**代表性判断：**端侧推理减少上传依赖，同时承担安装体积、内存和等待成本。我用分段处理、任务串行与部分成果保留控制体验；摘要失败时仍交付已有转写。48 次模型级对照推理未支持一版更严格的提示词，因此没有合入候选。

**上线结果：**完成首版至 1.0.2 的发行与反馈迭代；英国区付费效率榜曾进入前 100，第三方历史采样为第 54、60 位。[榜单范围](projects/02-stayword/docs/metrics-and-experiments.md#榜单核查)

[查看完整项目](projects/02-stayword/README.md) · [观看实机介绍](projects/02-stayword/demo/assets/stayword-demo-2026-09-25.mp4) · [模型与产品取舍](projects/02-stayword/docs/case-study.md)

## RiverSR：让模型结果能够支持研究决策

在实验室与中科院合作的科研背景下，我将多来源观测整理为可重复的预测研究流程，进一步检验模型的迁移边界、新信息的增量价值和生物应用条件。

![RiverSR 真实留出预测与误差分布](projects/03-riversr/demo/assets/prediction-diagnostics.png)

**代表性判断：**早期 RF 平均误差优于对照模型，但少量高值站点贡献了大部分误差。我据此分别管理连续预测与高值发现的用途，推进信息扩展和困难环境研究。后续 Human17 在同一批站点上的配对实验未支持稳定增量，因此保留自然环境主基线。

**研究交付：**数据与特征版本、RF / XGBoost 最终模型、原始留出预测及运行记录均可查看；独立生物基准已完成整理与协议冻结，来源推断仍处于下一阶段验证范围。

[查看完整项目](projects/03-riversr/README.md) · [单站结果与模型产物](projects/03-riversr/demo/README.md) · [训练、资源与技术方案](projects/03-riversr/docs/technical-design.md)
