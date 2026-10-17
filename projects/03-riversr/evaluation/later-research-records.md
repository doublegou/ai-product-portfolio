# 后续研究：Natural90、Human17 与应用验证记录

[返回项目](../README.md) · [研究演进](../docs/decision-timeline.md) · [训练与资源](../docs/technical-design.md#训练资源耗时与成本)

## 材料范围

这里整理后续研究的原始执行回报，用于连接早期 `river_sr` 工程与全球 isoscape 后续研究。数据来自历史工作记录中粘贴的执行结果，而非对话中的建议文字：2026-10-13 的 Natural90 共同失败重算、Human17 H13 修复与配对重分析，以及 aquatic bioarchive Round 2.5 回报。

早期 Base V0–V3 保留源码、正式运行结果与最终模型；本页后续研究则来自 **执行回报记录**。对应 HPC 目录为 `river_sr_isoscape_v3_staging/` 与 `AQUATIC_SR_BIOARCHIVE_*`，目前未附模型二进制、逐折输出或计费账单，因此尚未在本机逐项重算。Natural90 的已完成结果与原始方案中的 Core discovery / lockbox 分开记录，不能据前者认定后者全部完成。

## 1. 训练与比较人群

| 人群 | 站点数 | 用途 |
| --- | ---: | --- |
| P1 canonical | 5,600 | 河水观测总体 |
| P2 Natural90 | 5,543 | 自然环境主基线、最终共同失败分析 |
| P3 Human17 | 5,537 | 人类活动特征可用范围 |
| P4 Natural90 + Human17 matched | 5,517 | 在完全相同站点比较 M2 与 M3 的增量价值 |
| P5 Sensitivity7 support | 5,527 | 七项标准化表示的可用范围 |
| P6 Natural90 + Sensitivity7 | 5,507 | 自然变量与标准化表示的交集 |

M1 是 Natural90 主模型任务；M2 是匹配人群中的 Natural90 对照，M3 在同一人群中加入 Human17。对 M2/M3 的比较不使用不同人群的 M1 误差替代对照。RF、XGBoost、LightGBM 与五种迁移方案构成模型比较框架。

## 2. Natural90 共同失败与环境域

共同失败按精确 `scheme × repeat × outer fold` 计算：分别在每个算法内对绝对残差取 average-rank percentile，三个算法均达到 0.90 才标记该 context。水文验证保留三次重复，站点层使用 any-repeat。

| 指标 | 回报结果 |
| --- | ---: |
| 至少一个方案共同失败的站点 | 777 / 5,543 |
| 至少两个 / 三个 / 四个方案重复出现 | 508 / 326 / 196 |
| 五套方案均出现 | 74 |
| 共同失败站点中非高值 / ≥0.75 | 651 / 126 |
| 其中极高值 ≥0.80 | 20 |
| 被标记共同失败 context 的 SSE 占比 | 88.8478% |
| 任一方案共同失败站点在全部 context 的 SSE 占比 | 93.8713% |

两种 SSE 占比的集合定义不同，不能互换；残差分位数本身参与了失败定义，这些占比描述误差集中程度，不是对失败机制的独立验证。

七个环境域 HG1–HG7 的站点数分别为 418、618、177、1,168、1,196、490、1,476。HG4 的共同失败率为 371/1,168（31.76%），HG6 为 132/490（26.94%）。这两个比例是最终 P2 的 unique-site 口径；旧 P4 的 context 比例不再混用。

K=7 在揭示 Sr 前比较 K=5–8 后确定，回报给出平均 ARI 0.859226、匹配 Jaccard 0.887524、中心/剖面复现性 0.933489。未使用 Sr 或模型误差选 K。最困难河流系统中，477 个站点有 278 个共同失败站点，涉及 14 个 references/campaigns 与 22 个水文支系；最大单来源占 22.01%。

权威目录记录：`river_sr_isoscape_v3_staging/FINAL_M1_COMMON_FAILURE_HG_RECOMPUTE_AND_RECONCILIATION_V1/`。回报交付 Figure 7、Tables S15/S16 和 28 文件校验结果；图表原文件尚未随本作品集收录。

## 3. Human17：修复时间口径后重跑配对实验

H13 的坝库记录只允许 `YEAR_DAM` 或 `PRE_YEAR` 为 1–2015（含 2015）时纳入。修复前未应用该时间规则，影响了特征值：

- 障碍记录 41,145 → 17,451；水库记录 35,295 → 17,417。
- 上游坝数量在 3,554 个站点改变，上游水库面积在 2,842 个站点改变；116 个站点的 reach presence 从 1 变为 0。
- 22 条无法连接 L6 的 eligible 记录保持 unsupported，没有转为零或用近邻填补。
- 其他 Human14、Sensitivity7 以及 Natural90 主模型和全球图保持不变；配对人群重新计算后仍为 5,517。

随后重跑 210/210 个 Outer contexts、25,920/25,920 个 candidate-fold checkpoints；M2/M3 的测试身份、folds、水文 purge、候选、随机种子和判定规则保持一致。每个配对单元做 2,000 次 bootstrap。

Δ = 修正后的 M3 − M2；负值表示加入 Human17 后误差降低。

| 算法 | 迁移方案 | ΔRMSE | 95% CI | 冻结判定 |
| --- | --- | ---: | --- | --- |
| RF | 500 km | −0.0000362 | [−0.0001200, 0.0000711] | PRACTICALLY_EQUIVALENT |
| RF | 1,000 km | −0.0000291 | [−0.0002420, 0.0001480] | PRACTICALLY_EQUIVALENT |
| RF | 1,500 km | −0.0003074 | [−0.0005770, 0.0001262] | INCONCLUSIVE |
| RF | Reference | +0.0000867 | [−0.0000325, 0.0002079] | PRACTICALLY_EQUIVALENT |
| RF | Hydrological | −0.0000313 | [−0.0001161, 0.0000342] | PRACTICALLY_EQUIVALENT |
| XGBoost | 500 km | +0.0001342 | [0.0000144, 0.0002270] | INCONCLUSIVE |
| XGBoost | 1,000 km | +0.0001653 | [−0.0003506, 0.0008626] | INCONCLUSIVE |
| XGBoost | 1,500 km | −0.00000375 | [−0.0009361, 0.0005301] | PRACTICALLY_EQUIVALENT |
| XGBoost | Reference | −0.0000271 | [−0.0001997, 0.0001409] | PRACTICALLY_EQUIVALENT |
| XGBoost | Hydrological | +0.0002339 | [−0.0001817, 0.0007105] | INCONCLUSIVE |
| LightGBM | 500 km | −0.0003247 | [−0.0007873, −0.0000186] | MATERIAL_IMPROVEMENT |
| LightGBM | 1,000 km | −0.0013217 | [−0.0026329, 0.00000321] | INCONCLUSIVE |
| LightGBM | 1,500 km | +0.0001856 | [−0.0000673, 0.0005485] | INCONCLUSIVE |
| LightGBM | Reference | +0.0000385 | [−0.0000483, 0.0001177] | PRACTICALLY_EQUIVALENT |
| LightGBM | Hydrological | +0.0000134 | [−0.0003249, 0.0003751] | PRACTICALLY_EQUIVALENT |

仅 LightGBM × 500 km 为 MATERIAL_IMPROVEMENT，0/3 算法通过整体增量价值 gate。结论为 `NO_ROBUST_HUMAN_INCREMENTAL_VALUE`：当前 17 项全球人类活动代理没有提供稳定额外预测价值；不能据此推出人类活动不影响河水 Sr。

### 执行与恢复

55 个任务仅在最终输出目录写入阶段失败，随后只恢复对应索引，未重跑有效任务。后续还处理了 Rscript 路径、图形字形和 checksum 临时文件竞争，科学结果与工程交付状态分别记录。

回报交付修正后的 Tables S4/S5/S11/S12、Figure S6；55,764/55,764 文件通过最终校验。权威目录记录为 `river_sr_isoscape_v3_staging/FINAL_HUMAN17_H13_REBUILD_AND_PAIRED_REANALYSIS_V1/`，校验清单 `11_checksums/HUMAN17_REANALYSIS.sha256` 的回报哈希为 `aadb6c16f094e92cf07f763a6f296e13e56b7a521cbb3c6a011c4daf3d8d3058`。

Sensitivity7 的字段、公式和数据 QA 完成，但未恢复到冻结的模型比较协议，因此没有形成相应模型结论。Human17 主结论完成与 Sensitivity7 后续是否开展，分别管理。

## 4. 应用验证：先建立独立生物数据，再评价地图

Round 2.5 执行回报给出的冻结集合如下。B1–B3 对应不同应用证据层次，存在重叠，不能直接相加作为独立样本量。

| 集合 | Studies | Basin groups | Sites | Individuals | Measurements |
| --- | ---: | ---: | ---: | ---: | ---: |
| B1 | 2 | 2 | 76 | 76 | 76 |
| B2 | 1 | 1 | 74 | 74 | 74 |
| B3 | 1 | 1 | 74 | 74 | 74 |
| B4 · extended sensitivity | 20 | 14 | 80 | 175 | 372 |

B1 最大单研究/单流域占比均为 97.37%，B2/B3 为 100%。严格集合仍高度集中，因此不能将 B4 的研究数量拿来替代严格应用验证的独立性。另有 5 个严格候选数据未取得、14 个谱系重复案例未解决。

回报状态为 `READY_WITH_DOCUMENTED_LIMITATIONS`，已冻结 registry、study summary 和 benchmark protocol，并确认未访问全球预测、残差或模型性能。下一阶段才进行独立河网匹配及预测对照；不能把数据集准备完成写成生物溯源或迁移重建已经验证成功。

权威目录记录：`AQUATIC_SR_BIOARCHIVE_BENCHMARK_CLOSURE_V1/`，主要交付为 `09_FINAL_BENCHMARK_POPULATION_REGISTRY.csv`、`10_FINAL_STUDY_LEVEL_BENCHMARK_SUMMARY.csv`、`11_FINAL_BIOLOGICAL_BENCHMARK_PROTOCOL_FROZEN.md` 与 `12_ROUND3_READINESS.md`。
