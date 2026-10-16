# 内容生产工作流评测

最新：[2026-10-17 产品评测](2026-10-17-product-audit/README.md)，包括历史日志审计、12 条规则边界探针、图片规格、三次雷达实采与 Token 成本拆解。

各板块任务核验见下表及 results.csv；历史工程修订见[审查记录](release-review.md)。用户采纳、主动修正时间和完整成本对照仍待测量。目录与现有工具的离线验证见[结构验证记录](structure-check.md)，此前迁移记录见[历史记录](refactor-check.md)；工程测试不计为内容质量或传播效果成绩。

| workflow 值 | 验证对象 | 具体标准 |
| --- | --- | --- |
| content-workflow | 分析、正文、系列卡片与字幕降级 | [验收与样本](content-workflow/README.md) |
| script-workflow | HTML、发布文案、三比例封面 | [验收与样本](script-workflow/README.md) |
| content-agent | 选题研究、审改、草稿与独立发布状态 | [验收与样本](content-agent/README.md) |
| daily-trend-radar | 来源状态、热点报告和选题建议 | [验收与样本](daily-trend-radar/README.md) |

已完成的真实素材核验见[第 005 期检查记录](script-workflow/2026-10-16-sample-review.md)，展示页的桌面／手机交互与链接检查见[浏览器报告](showcase-check.json)。这些检查验证文件和展示行为，不代表业务效果评测完成。

## 首轮与对照

四个板块分别按实际任务检查输入、产物、修改与验收；每个板块逐步覆盖普通任务和真实失败／降级任务。历史材料先核对输入、版本和产物关系。链路确认后，再按各板块说明扩大样本；不将不同工作流合成一个总成功率。

比较手动流程与 Skill／程序方案时，固定输入、交付范围和人工标准，记录重复执行带来的熟悉效应。没有历史基线时先建立当前基线，不反推节省比例。

## 记录位置与口径

共用 [run-template.csv](run-template.csv) 的列结构。有真实数据后，在 `evaluation/<板块>/results.csv` 保存记录；每条的 evidence_path 相对所在 CSV 指向 `demo/<板块>/<任务>/` 或已核对的历史材料。run_id 唯一，workflow 使用表中的名称，版本记录来源提交与本地修改；涉及多个 Skill 时逐项记录在任务说明中。

旧别名 youtube-social、script-assets、product-content、trend-radar 分别对应表中四项。若发现历史数据，保留原字段并说明映射；新记录使用统一名称。空模板未填造示例成绩。

- status 使用 completed、partial、failed 或 cancelled，说明任务执行状态；quality_pass 使用 true、false 或空值，表示人工验收是否完成及结果。内部模型分数单列在任务说明中。
- 完成率：全部任务中，满足预定交付且人工验收通过的任务比例。分母包含失败和放弃，报告样本数量和范围。
- human_minutes 记录主动操作时间；elapsed_seconds 记录开始到本次任务结束的总时间，notes 说明是否包括验收等待。修改轮次注明统计范围。
- 费用包括失败重试、图片、转写等实际支出；Token 不等同费用。费用与币种分开；无法读取的字段留空，不能填 0。
- 单个合格结果成本为全部支出除以合格结果数；没有合格结果时写“不适用”。不足以计费的记录不能给出完整成本结论。

## 证据与失败

成功、部分交付和失败都保留证据；类型包括输入不可读、获取失败、依赖问题、模型请求失败、事实不符、格式错误、图片文字错误、人工放弃。实际发布不是草稿验收条件；采集配置数量不等于实时来源可用率；文件检查通过也不等于内容或视觉质量通过。
