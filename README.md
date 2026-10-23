# AI 产品作品集

**AI 产品经理：从用户问题与产品机制，到工程交付与模型效果判断。**

在九章云极，我推进创作者产品迭代与开发者平台流程设计；在种梦星辰，我独立完成端侧 AI 应用、内容生产 Skills 及科研合作中的模型实验。下面的案例分别展示我的具体职责、方案取舍和交付结果。

## 工作经历与代表项目

| 经历 | 代表项目 | 个人贡献与结果 |
| --- | --- | --- |
| **种梦星辰 · Founder / AIPM**<br>2026.05–2026.10 | [StayWord](projects/02-stayword/README.md) · [Multi-Skill Content Agent](projects/01-content-agent/README.md) · [RiverSR](projects/03-riversr/README.md) | 独立完成 AI 应用设计、开发与发行；设计可复用 Skills、人工确认与失败处理；通过隔离评估和配对实验判断模型是否值得采用。RiverSR 为这一阶段的中国科学院合作项目。 |
| **九章云极 · AIPM**<br>2025.06–2026.05 | [BaicaiInfer](projects/05-baicaiinfer/README.md) · [Lab4AI](projects/06-lab4ai/README.md) | 将 AIGC 能力封装为创作入口，推动内测功能与计费规则迭代；设计开发者复现流程与独立送审机制，承担电影节业务探索与渠道合作。 |
| **中路交科 · 交通工程师**<br>2024.09–2025.05 | 交通咨询与养护决策 Agent | 主导或参与 30+ 项交通咨询，参与交通运输部《公路养护合同范本》编制；以 Coze 知识库辅助养护方案生成，初稿编制效率提升约 50%。 |

## 独立产品与技术实践

| 产品 | 目标用户与核心场景 | 核心价值与产品进展 |
| --- | --- | --- |
| [Multi-Skill Content Agent](projects/01-content-agent/README.md)<br>**跨平台内容生产** | 独立知识 / 产品创作者，把视频、口播稿或产品资料制作成一期内容时 | 内容分析、正文创作、图片规划与生成三个 Skills 复用同一分析稿，配合口播素材与产品稿流程。**实际生产 50+ 次，较原 Browser Agent 方案 Token 降约 60%。** |
| [StayWord](projects/02-stayword/README.md)<br>**端侧 AI 录音笔记** | 个人用户，在会议、访谈或学习后，需要整理和回查谈话时 | 将录音转成可阅读的全文与摘要，通过时间戳回听、编辑和导出继续使用。**iOS 已上架，核心 AI 本地运行。** |
| [RiverSR](projects/03-riversr/README.md)<br>**河水锶同位素预测研究** | 环境与生物来源研究者，需要为缺少采样的河流建立同位素参考时 | 5,600 个站点建模与水系隔离评估，识别高值漏判并通过配对实验取舍新增特征。**中国科学院合作项目，交付可复现基线与适用范围判断。** |
| [PriceMap AI](projects/04-pricemapai/README.md)<br>**补充案例：AI 订阅与 API 比价工具** | 个人用户选购 / 续订 AI 服务，开发者选择模型 API 渠道时 | 集中分散报价，解释交付规格、计费单位与时效，帮助找到可回查的候选。**双路径网站已上线，持续采集与更新。** |

## 九章云极：创作者产品与开发者平台

**[BaicaiInfer｜AIGC 创作平台与场景工作流](projects/05-baicaiinfer/README.md)**：把 ComfyUI 节点配置封装为“风格选择—素材输入—结果生成”入口，独立交付 3 个、协作交付 6 个场景工作流镜像。通过 43 名 KOC 内测推动历史记录持久化、放大预览、拖拽上传、5–15 秒逐秒时长选择及积分计费规范化；牵头电影节业务探索，交付产品方案与可交互原型。最终拓展 8 条渠道、23 位代理，渠道用户增长 3 万+，贡献团队同期渠道拉新成果 90% 以上。

**[Lab4AI｜AI 开发者项目复现平台](projects/06-lab4ai/README.md)**：设计任务申领至成果上架的角色、状态和交接标准；以“一键提交—自动复制—独立送审”解决开发目录持续修改与审核版本固定之间的冲突，复用已有存储避免新建上传通道。独立复现 Kronos 验证全链路、识别 10+ 项卡点；相关业务平均周期缩短约 15%，单项目协作由约 6 人降至 2 人，平台累计支撑 1 万+ 次复现。

## 内容生产：从一份资料到一期可用素材

独立创作者制作一期内容，往往要在资料理解、正文、配图、演示和封面之间反复交接。我以内容分析、正文创作、图片规划与生成三个 Skills 共享分析结果，将字幕获取、文件处理及校验交给脚本；口播素材和产品稿保留独立的执行与审改流程。选题雷达作为补充研究工具单独展示。

<table>
<tr>
<td width="65%"><img src="projects/01-content-agent/demo/script-workflow/2026-10-16-version-alignment/screenshots/page-05-step-3.png" alt="Agentic Video 口播配套演示的真实播放画面" width="520"></td>
<td width="35%"><img src="projects/01-content-agent/demo/content-workflow/2026-08-27-literature-review/generated-originals/03.png" alt="视频改编生成的引用核查卡片原图" width="220"></td>
</tr>
<tr><td>口播配套演示：将修订稿转成分步讲解。</td><td>图文卡片：让图片独立完成解释。</td></tr>
</table>

**代表性判断**：将共享分析、不同形式的表达和最终验收分开；已有演示时只生成文案与封面，改稿后检查关联素材。事实核验、文件规格和保存状态分别验收，模型自评分只作为参考。

**AI 实现与结果**：出图前确认规划，无字幕时经确认启用 Whisper；保留的生图 API 实现支持接口回退与限次重试，产品稿采用规则校验与限轮审改。个人内容生产累计运行 50+ 次，较原 Browser Agent 方案 Token 降约 60%，同类内容制作约 3 小时缩至 10 分钟以内。[实践成果与统计范围](projects/01-content-agent/README.md#个人贡献与生产结果)

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

**上线结果**：独立完成移动端开发及 iOS 上架迭代，曾进入 App Store 效率类付费榜 **Top 10**；根据回听与分享反馈交付 0.5–2 倍六档播放控制，支持原始音频、转写全文与摘要分别导出。[榜单范围](projects/02-stayword/docs/metrics-and-experiments.md#榜单核查)

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
