# AI 产品作品集

**为创作者交付内容，为个人整理录音，为研究者补足预测，为 AI 使用者比较服务。**

我独立推进下面四个项目，从用户问题、产品范围和核心体验，到 AI / 数据方案、工程交付与迭代验证。这里既有已上线的产品，也有真实使用中的工作流和实验室研究；每个案例都说明解决了什么、为什么这样做，以及结果如何影响下一步选择。

| 产品 | 为谁，在什么场景 | 解决什么问题，怎样交付价值 |
| --- | --- | --- |
| [内容生产 Agent 与 Skill 工作流](projects/01-content-agent/README.md)<br>**创作者内容生产工作流** | 独立知识 / 产品创作者，把视频、口播稿或产品资料制作成一期内容时 | 将研究、改编、演示、图文与发布素材组织成可修改的交付流程，减少重复说明与版本交接负担。**四类个人真实任务已跑通。** |
| [StayWord](projects/02-stayword/README.md)<br>**端侧 AI 录音笔记** | 个人用户，在会议、访谈或学习后，需要整理和回查谈话时 | 将录音转成可阅读的全文与摘要，通过时间戳回听、编辑和导出继续使用。**iOS 已上架，核心 AI 本地运行。** |
| [RiverSR](projects/03-riversr/README.md)<br>**河水锶同位素预测研究** | 环境与生物来源研究者，需要为缺少采样的河流建立同位素参考时 | 用环境数据建立预测，并通过水系隔离验证解释适用范围，为后续来源研究提供基线。**中科院合作实验室项目，已有模型与留出结果。** |
| [PriceMap AI](projects/04-pricemapai/README.md)<br>**AI 订阅与 API 比价工具** | 个人用户选购 / 续订 AI 服务，开发者选择模型 API 渠道时 | 集中分散报价，解释交付规格、计费单位与时效，帮助找到可回查的候选。**双路径网站已上线，持续采集与更新。** |

## 内容生产：从一份资料到一期可用素材

独立创作者制作一期内容，往往要在资料理解、正文、配图、演示和封面之间反复交接。我把选题研究、视频改编、口播素材和产品稿组织为四条可独立进入的路径，按已有材料和所需产物交付，并保留规划、修改与验收节点。

<table>
<tr>
<td width="65%"><img src="projects/01-content-agent/demo/script-workflow/2026-10-16-version-alignment/screenshots/page-05-step-3.png" alt="Agentic Video 口播配套演示的真实播放画面" width="520"></td>
<td width="35%"><img src="projects/01-content-agent/demo/content-workflow/2026-08-27-literature-review/generated-originals/03.png" alt="视频改编生成的引用核查卡片原图" width="220"></td>
</tr>
<tr><td>口播配套演示：将修订稿转成分步讲解。</td><td>图文卡片：让图片独立完成解释。</td></tr>
</table>

**代表性判断**：将共享分析、不同形式的表达和最终验收分开；已有演示时只生成文案与封面，改稿后检查关联素材。事实核验、文件规格和保存状态分别验收，模型自评分只作为参考。

**AI 实现**：字幕优先与 Whisper 转写兜底、参考图约束、有限审改、请求退避与失败恢复。下一阶段用约定交付完成率、人工修正时间和合格交付成本判断哪些步骤值得保留。

[查看完整项目](projects/01-content-agent/README.md) · [四类实际交付](projects/01-content-agent/demo/README.md) · [需求规划与 MVP](projects/01-content-agent/docs/case-study.md)

## StayWord：让录音成为能回查、能复用的笔记

面向需要整理中文谈话的个人用户，我把录音、转写、摘要和回听放在同一条记录里：会后找行动、访谈后核对引语、学习后复习重点。产品以本地核心处理和一次购买切入，iOS 已上架，并根据反馈迭代倍速、分享与设置。

<table>
<tr>
<td><img src="projects/02-stayword/demo/assets/03-transcript-playback.jpg" alt="StayWord 分段转写与时间戳回听" width="220"></td>
<td><img src="projects/02-stayword/demo/assets/04-summary.jpg" alt="StayWord 实际生成的摘要" width="220"></td>
<td><img src="projects/02-stayword/demo/assets/05-export.jpg" alt="StayWord 分别导出音频、转写与摘要" width="220"></td>
</tr>
<tr><td>核对原话</td><td>理解重点</td><td>带走所需材料</td></tr>
</table>

**代表性判断**：端侧推理减少上传依赖，同时承担安装体积、内存和等待成本。我用分段处理、任务串行与部分成果保留控制体验；摘要失败时仍交付已有转写。48 次模型级对照推理未支持一版更严格的提示词，因此没有合入候选。

**上线结果**：完成首版至 1.0.2 的发行与反馈迭代；英国区付费效率榜曾进入前 100，第三方历史采样为第 54、60 位。[榜单范围](projects/02-stayword/docs/metrics-and-experiments.md#榜单核查)

[查看完整项目](projects/02-stayword/README.md) · [观看实机介绍](projects/02-stayword/demo/assets/stayword-demo-2026-09-25.mp4) · [模型与产品取舍](projects/02-stayword/docs/case-study.md)

## RiverSR：为未采样河流建立有适用范围的预测

河水锶同位素可为环境差异与生物来源研究提供线索，但实测站点不足以覆盖所有河流。在实验室与中科院合作背景下，我以环境数据建立预测基线，并检验新水系上的迁移表现，帮助研究者区分哪些结果可以继续使用、哪些环境需要补采或验证。

![RiverSR 真实留出预测与误差分布](projects/03-riversr/demo/assets/prediction-diagnostics.png)

**代表性判断**：早期 RF 平均误差优于对照模型，但少量高值站点贡献了大部分误差。我据此分别管理连续预测与高值发现的用途，推进信息扩展和困难环境研究。后续 Human17 在同一批站点上的配对实验未支持稳定增量，因此保留自然环境主基线。

**研究交付**：数据与特征版本、RF / XGBoost 最终模型、原始留出预测及运行记录均可查看；独立生物基准已完成整理与协议冻结，来源推断仍处于下一阶段验证范围。

[查看完整项目](projects/03-riversr/README.md) · [单站结果与模型产物](projects/03-riversr/demo/README.md) · [训练、资源与技术方案](projects/03-riversr/docs/technical-design.md)

## PriceMap AI：让 AI 订阅与 API 渠道更容易比较

个人续订 AI 服务时，需要分清充值、成品号与共享账号；开发者选择 API 时，需要看懂模型、分组、额度和真实计费单位。我将两类任务设计成独立查询路径，集中原站报价与关键条件，让用户从逐家找信息进入候选比较，再到原站确认。

[![PriceMap AI 官网首页：订阅与 API 两类查询入口](projects/04-pricemapai/demo/assets/00-homepage-2026-10-17.jpg)](https://pricemapai.com)

**代表性判断**：目录覆盖与同规格可比性分开评价，API 现金价格与余额单位分开换算，商家监测与模型质量分开解释。修复购买路径时，验收延伸到正确商品，而非止于页面可打开。

**持续运营**：从统一采集演进到按关注、价格变化与库存分档更新，公开访问读取静态快照，后台采用增量发布和预算上限。10 月 17 日公开快照包含 4,822 条订阅报价、27 家 API 中转站；回放也暴露了规格覆盖与最低价标签的差异，因此下一步优先改善比较质量。

[查看完整项目](projects/04-pricemapai/README.md) · [观看实际演示](projects/04-pricemapai/demo/assets/pricemapai-demo-2026-10-10.mp4) · [用户、MVP 与需求规划](projects/04-pricemapai/docs/product-design.md) · [架构与资源取舍](projects/04-pricemapai/docs/technical-design.md)
