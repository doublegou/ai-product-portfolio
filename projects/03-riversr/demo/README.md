# RiverSR · 研究成果与应用交付

[返回项目](../README.md) · [研究需求与应用设计](../docs/case-study.md) · [Quick start](../docs/quick-start.md)

本页先展示模型结果如何影响交付，再提供数据与模型文件入口。后期 Natural90 / Human17 目前收录执行回报；下方地图则是早期合成数据原型，两者分别标明。

## 模型结果如何改变交付范围

![早期模型选择与极高值迁移诊断](assets/model-evidence.png)

**这张图回答两个不同的采用问题。** 左图中，相同完整水系隔离验证下，RF 的 pooled RMSE 为 0.017235，比 XGBoost 低 2.76%，因此选择 RF 作为 Base V3 连续预测基线。右图中，RF 训练拟合可以命中全部 29 个极高值站点，严格站点均值留出预测却为 0/29，因此没有将这一模型交付为可靠的极高值发现工具。

这个结果推动后续研究从模型修正、区域化，转向更完整输入和跨算法共同失败诊断。**保留的能力是连续预测研究基线，需要继续解决的是陌生环境与极高值迁移。**

图表由 [render_figures.py](render_figures.py) 读取 Base V3 冻结 CSV 生成。[算法比较数据](../src/river_sr/training/base/v3/validation/primary_pooled_metrics.csv) · [站点级汇总](../src/river_sr/training/base/v3/validation/primary_site_mean_metrics.csv) · [训练拟合](../src/river_sr/training/base/v3/release/training_metrics.csv)

## 从逐站结果定位信息缺口

![基于 5,600 站点真实留出预测的误差诊断](assets/prediction-diagnostics.png)

我重新从归档的逐站预测计算分层误差：实测 ≥0.75 的 **136 个站点（2.43%）贡献 82.90% 的平方误差**。其中 29 个极高值站点贡献 69.44%，且全部低估。该结果说明后续研究需要关注少数困难环境，单一平均分数无法说明各类研究任务的可用性。

这是一项事后误差诊断。分层使用已知实测值，不能直接作为未知地点的模型路由；环境机制仍需独立信息和对照实验检验。[重算结果](../evaluation/prediction-reproduction.json)

### 单站复核：输入、留出结果与使用判断

以下示例从四个固定实测区间内，分别选取绝对误差处于中位排名的站点。选择规则与全部结果一起保留，便于理解典型误差；这些是**历史评估回放**，不是新增推理或真实用户使用记录。

| 实测区间 | 站点 ID | 实测值 | 留出预测均值 | 绝对误差 |
| --- | --- | ---: | ---: | ---: |
| <0.72 | `d8a215ee07b8fdcc` | 0.707980 | 0.710396 | 0.002416 |
| 0.72–0.75 | `ea6819ff190e03fe` | 0.728140 | 0.718835 | 0.009305 |
| 0.75–0.80 | `12125c5e7c247d43` | 0.756253 | 0.713693 | 0.042560 |
| ≥0.80 | `bef26300f5bf4000` | 0.896269 | 0.724129 | 0.172140 |

复核路径：用站点 ID 在 [Full50 输入](../src/river_sr/data/processed/training/sr_full50_v2.csv)查找坐标、文献来源和 50 项特征 → 在[冻结划分](../src/river_sr/training/base/v3/folds/outer_folds.csv)确认所属水系被留出 → 对照[三次预测及均值](../src/river_sr/training/base/v3/runs/base_v3_full_20260817_r2/reports/primary/site_oof_predictions.csv) → 判断结果是否足以支持目标任务。[示例 CSV](site-review.csv)保留坐标、来源和每次预测。

例如最后一站的三次预测都约为 0.72，彼此接近却与实测 0.896269 相差很大。这说明**重复预测稳定不等于正确**，重复间波动不能直接包装成预测可信度。后续应用仍需独立误差评价与支持范围说明。

## 交付文件：从输入追溯到结论

这里提供早期 Full50 阶段的一条完整阅读路径：先确认样本与特征，再看模型配方、验证方式和最终结论。

| 阅读顺序 | 可直接查看的产物 | 能回答的问题 |
| --- | --- | --- |
| 1 · 输入 | [5,600 站点 manifest](../src/river_sr/data/processed/training/sr_full50_v2_manifest.json) · [Full50 定义](../src/river_sr/training/base/v3/release/full50_predictors.txt) | 训练使用了哪些样本与信息？ |
| 2 · 模型 | [RF 模型（LFS）](../src/river_sr/training/base/v3/release/model_bundle.rds) · [RF 配方](../src/river_sr/training/base/v3/release/rf_recipe.json) · [预处理统计](../src/river_sr/training/base/v3/release/training_medians.csv) | 参数、缺失处理与最终配方是什么？ |
| 3 · 验证 | [科学设计](../src/river_sr/training/base/v3/SCIENTIFIC_DESIGN.md) · [严格验证摘要](../src/river_sr/training/base/v3/validation/README.md) | 结果对应哪种预测情境，有没有泄漏？ |
| 4 · 结论 | [冻结结论](../src/river_sr/training/base/v3/release/scientific_conclusion.md) · [版本与哈希](../src/river_sr/training/base/v3/release/final_manifest.json) | 哪些能力得到支持，这些结果属于哪个版本？ |

**模型与原始结果已收录。** RF bundle 为 126,650,268 字节，XGBoost 对照 bundle 为 155,584 字节，均与原始 release 中的 SHA-256 一致；RF 发布副本与运行副本是同一 LFS 对象。正式运行的逐折输出、选参汇总、152 份 Slurm 标准输出/错误日志及版本文件已保留。逐折训练模型与其他历史/smoke 归档可从[原仓库固定版本](https://github.com/triplemengpaper/river_sr/tree/ad120936a965608ba43794742b18d5caebe68b9d)获取。

[Quick start](../docs/quick-start.md)提供模型下载与逐站重算入口。运行阶段的 `final_manifest.json` 记录“待科学审核”，随后 release 的 [final_manifest.json](../src/river_sr/training/base/v3/release/final_manifest.json)记录正式冻结与用途限制；最终交付状态以 release 为准。

## 后续成果：自然基线、信息增量与应用基准

| 研究交付 | 当前可读结果 | 对应原始成果 |
| --- | --- | --- |
| Natural90 可靠性 | [5,543 站点、三算法共同失败与环境域](../evaluation/later-research-records.md#2-natural90-共同失败与环境域) | 回报中的 Figure 7、Tables S15/S16；后期全球预测图需补回对应原件 |
| Human17 增量价值 | [15 个算法×迁移组合的配对结果](../evaluation/later-research-records.md#3-human17修复时间口径后重跑配对实验) | 时间规则修复后的 Tables S4/S5/S11/S12、Figure S6 与校验清单 |
| 生物应用准备 | [严格/扩展集合与独立性限制](../evaluation/later-research-records.md#4-应用验证先建立独立生物数据再评价地图) | 冻结 population registry、study summary 与 benchmark protocol |

这部分依据历史执行回报整理，原图、完整模型与逐折结果尚未随仓库收录。生物基准目前完成数据与协议准备，尚未完成预测对照和来源验证。

## 地图原型：探索研究结果的查询方式

**已有合成数据原型，尚未连接真实模型。**

![RiverSR 地图交互原型，使用合成数据](assets/map-prototype.png)

使用流程：输入同位素条件 → 点击 Run → 查看空间展示 → 修改条件并重新查询。截图来自 2026-10-17 运行的 `sr_o_map_web_pro`，Strontium central 50% 输入 0.7100，其余输入为空。

原型已经组织了输入与地图展示，但地图颜色尚未直接消费查询输出，不能据此解释实际来源概率。真实接入需依次完成：查询数值与颜色一致、坐标与特征版本一致、预测与支持范围一致，最后才是经过已知来源验证的来源查询。逐步验收条件见[目标使用流程](../docs/case-study.md#一次研究使用应拿到什么)。
