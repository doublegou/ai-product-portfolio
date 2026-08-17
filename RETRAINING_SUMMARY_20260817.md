# 修正训练数据后的全模型重训练汇总

日期：2026-08-17

## 1. 事件与执行边界

最初构建的 Full50 V1 训练表存在预测变量错误。修正后的 canonical Full50 表 normalized-LF MD5 为 `dc80c73dfc64a3180efb4c5bb9fe5902`；旧错误版本为 `92100a834e0836527e6921d974f222ca`，审计发现 50 个预测变量中有 40 个受到影响。依赖该表生成的 Himalayan Regional Risk V1/V2 训练表也已重建。

本轮没有建立额外的“重训练活动目录”。每个模型继续使用自己的训练工程、`runs/<run_id>`、`validation/`、`RESULTS.md` 和 `release/`。全部正式模型均从修正输入重新执行；没有复用上一轮 validation 结果。

HPC 使用原则是：保持冻结科学方法不变，在现有任务原子性允许的范围内最大化 Slurm array 并发。所有正式结果归档均已下载，SHA-256 校验一致，并在解压前通过绝对路径、`..` 路径和允许前缀检查。

## 2. 最终决策总表

| 项目 | 修正数据 run | 最终判定 | 最终模型 | Release 动作 |
|---|---|---|---|---|
| Base V0 | `v0_full_20260817_corrected_r1` | `PASS_REPLACE_RELEASE` | 已拟合 | 已替换 |
| Base V1 | `v1_full_20260817_corrected_r1` | `PASS_REPLACE_RELEASE` | 已拟合 | 已替换 |
| Global High-Sr Risk V1 | `risk_v1_full_20260817_corrected_r1` | `transferable_signal_insufficient_stop` | 未拟合 | 不创建 |
| High-Sr Correction Feasibility V1 | `high_sr_corr_20260817_corrected_r1` | `SIGNAL_ONLY_BUT_NOT_USEFUL` | 未拟合 | 不创建 |
| Base V2 | `base_v2_full_20260817_corrected_r1` | `ACCEPTED` | 已拟合 | 已替换 |
| Regional Risk V1 | `regional_risk_v1_20260817_corrected_r1` | `SIGNAL_FEASIBILITY_ONLY` | 未拟合 | 不创建 |
| Regional Risk V1.1 | `regional_risk_v1_1_20260817_corrected_r1` | `RANKING_SIGNAL_NOT_OPERATIONAL_GATE` | 未拟合 | 不创建 |
| Regional Risk V2 | `regional_risk_v2_20260817_corrected_r3` | `NO_CANDIDATE_MET_COMPLETE_REGIONAL_GATE` | 未拟合 | 不创建 |

结论：八个受影响项目全部得到完整、可审计的修正数据结果。三个 ordinary Base RF 通过并更新 release；五个风险/校正可行性项目完成计算但没有通过其部署或 promotion Gate，因此按预先冻结的停止规则不生成 release。

## 3. 通过并更新的 Base 模型

### Base V0

- Primary 1000-km spatial nested CV：RMSE `0.0172037112`，MAE `0.0055356961`，R² `0.1453950977`，Bias `-0.0010297257`。
- 相对上一轮：RMSE `+0.10%`，MAE `+0.60%`；各 validation scheme 的 RMSE 变化均小于 `0.56%`。
- 最终 recipe 未改变：`mtry=7`、`min.node.size=5`、`sample.fraction=1`、`replace=FALSE`、3,000 trees。
- 没有独立保存下来的第三套历史数值，因此历史一致性只在冻结方法与上一正式 run 层面判断，没有虚构历史对照。
- Release source run：`v0_full_20260817_corrected_r1`；模型 MD5 `df2a251b3e80114ddc44873f8618a8c6`，已现场复算一致。
- 详细结果：[Base V0 RESULTS](training/base/v0/RESULTS.md)

### Base V1

- Primary hydrological station-mean OOF：RMSE `0.0180022858`，MAE `0.0060135276`，R² `0.0642143133`，Bias `-0.0013348328`。
- 相对上一轮：RMSE 改善 `0.40%`，MAE 改善 `1.18%`；各 stress RMSE 变化均小于 `0.42%`。
- 最终 recipe 未改变：`mtry=12`、`min.node.size=5`、`sample.fraction=1`、`replace=FALSE`、4,000 trees。
- 历史边界保持：background-Sr RMSE 约 `0.00434`，`Sr>=0.80` RMSE 仍约 `0.227`；普通 Full50 RF 的极端尾部压缩没有被解决。
- Release source run：`v1_full_20260817_corrected_r1`；模型 MD5 `68ac07ee978cebbfdfa206e93001bfe0`，已现场复算一致。
- 详细结果：[Base V1 RESULTS](training/base/v1/RESULTS.md)

### Base V2

- 完整执行 45 个 methodology benchmark outer folds、15 个 Primary outer tasks、Deployment、25 个 Stress tasks 和 final fit，共 `5,081` 次 RF 拟合；88/88 Slurm jobs 完成。
- Primary station-mean OOF：RMSE `0.0133358`、MAE `0.00458687`、R² `0.424667`、Bias `+0.0003784`、branch-macro RMSE `0.00552446`。
- 相对上一轮/正式历史 r2：RMSE `+0.55%`、MAE `-0.41%`、R² `-0.00632`、branch-macro RMSE `-0.02%`。
- 方法结论保持：Purged Branch 对 Matched Terminal 的四项冻结指标均为 `9/9` 优胜；Purged 对 Naive Branch 仍不是稳定全面优胜。
- 尾部问题保持且明确：`Sr>=0.80` RMSE `0.175981`，Bias `-0.152258`，同阈值 recall 从历史 `2/10` 变为 `1/10`。这不阻止 ordinary Base RF 发布，但严禁把 V2 描述为解决 High-Sr。
- 最终 recipe fingerprint 未改变：`mtry=7`、`min.node.size=5`、`sample.fraction=1`、`replace=FALSE`、4,000 trees。
- Release source run：`base_v2_full_20260817_corrected_r1`；模型 SHA-256 `2a9efcf21e80a375fa56e4380400fa26397e3ff0672bf837e81c84d2aee80c62`。
- Release 目录的 11 个 artifact 已逐项复算 bytes、MD5 和 SHA-256，全部通过。
- 详细结果：[Base V2 RESULTS](training/base/v2/RESULTS.md)

## 4. 完成但未通过 Gate 的项目

### Global High-Sr Risk V1

- Elastic Net：`0/3` repeats；Recall `0.0214`、Precision `0.1453`、background FPR `0.0411`、PR-AUC `0.0259`。
- Probability RF：`0/3` repeats；Recall `0.0520`、Precision `0.0874`、background FPR `0.0085`、PR-AUC `0.0644`。
- 上一轮就是正式历史结果。修正数据改变部分 threshold 对应的 Precision/FPR，但 Recall、PR-AUC、positive-system 和 extreme-system coverage 仍远低于完整 Gate。
- 5 条 `glmnet` 提示只涉及部分 path 的最后一个 lambda 未在 `maxit=100000` 内收敛；30/30 tasks、6/6 OOF 均完整，不构成可行性证据。
- 决策：停止，不拟合 classifier，不创建 release。
- 详细结果：[Global High-Sr Risk RESULTS](training/global_correction/global_high_sr_risk/RESULTS.md)

### High-Sr Correction Feasibility V1

- 四个候选相对 BasePred-only control 都通过 residual-signal gate，signal improvement 为 `20.50%–23.77%`。
- 但相对 untouched Raw Base 的 hydrological-group macro improvement 全部为负：`-6.30%` 到 `-0.95%`；safety repeats 最多仅 `1/3`。
- 上一轮就是正式历史结果。修正数据改变幅度和个别 repeat pattern，但没有一个候选同时通过 signal 与 Raw-Base safety Gate。
- 决策：`SIGNAL_ONLY_BUT_NOT_USEFUL`；保留 Base V1，不拟合 correction，不创建 release。
- 详细结果：[High-Sr Correction RESULTS](training/global_correction/high_sr_correction_feasibility/RESULTS.md)

### Regional Risk V1

- Combined GAM：PR-AUC `0.337956`、ROC-AUC `0.711558`、Brier `0.173871`、log loss `0.530226`。
- Environment-only GAM：PR-AUC `0.310356`、ROC-AUC `0.704559`、Brier `0.165685`、log loss `0.494175`。
- 相对上一轮，GAM 指标变化约在 `0.00004–0.00124`；Spatial-only GAM 和两个 intercept-only Elastic Net control 数值不变。
- 历史科学顺序保持：Combined 是 ranking candidate，Environment-only 是 probability candidate，Spatial-only 只作诊断；bootstrap 对比仍不能证明候选间确定优胜。
- 决策：只证明 moderate nonlinear regional signal；不选 Gate、不校准、不拟合 expert、不创建 release。
- 详细结果：[Regional Risk V1 RESULTS](training/regional_expert/regional_risk_v1/RESULTS.md)

### Regional Risk V1.1

- Environment-only Primary：FPR `10.7%`、Recall `40.5%`、Precision `36.0%`、positive branches `7/14`、extreme branches `1/4`。
- Combined Primary：FPR `6.9%`、Recall `44.1%`、Precision `31.4%`、positive branches `6/14`、extreme branches `1/4`。
- 修正结果比上一轮更接近保存的历史记录，但两个模型仍未满足完整 operational Gate，特别是 Recall 和 extreme-branch coverage。
- 34/34 tasks、578 GAM fits、34 Platt calibrators、68 thresholds、744 OOF 完整。34 个 calibrator 均收敛且 slope 为正；结构化诊断中的 non-integer binomial warning 来自冻结 branch 权重。
- 决策：停止当前 GAM/calibrator/threshold 路线，不创建 release。
- 详细结果：[Regional Risk V1.1 RESULTS](training/regional_expert/regional_risk_v1_1/RESULTS.md)

### Regional Risk V2

- 最接近 Gate 的 Probability RF Full50：FPR `6.96%`、Recall `45.54%`、Precision `45.78%`、positive branches `6/14`、extreme systems `2/4`。
- 相对上一轮：Recall、positive/extreme coverage 不变；FPR 从 `6.02%` 变为 `6.96%`，Precision 从 `48.22%` 变为 `45.78%`。
- Shallow boosting Full50 的 FPR 从 `10.01%` 改善为 `7.96%`，但 Recall 仍只有 `34.66%`、positive branches 仍为 `5/14`，无法跨越完整 Gate。
- 四个候选都失败；Process14 在本轮仍没有改善 unseen-branch transfer。该 secondary 方向与恢复出的“可能改善 ranking 但不改善覆盖”叙述不完全相同，但 primary 历史结论完全一致：不存在可部署 Regional Gate。
- 两次前置提交在任何模型拟合前被工程检查阻止，原因是计算节点 compiled package 的 `libstdc++` 加载顺序；将 xgboost 调整为最先加载后，正式 r3 的 68/68 tasks、1,156 fits 和 1,488 OOF 全部完成。此修改不改变统计方法。
- 决策：不拟合 full-data model，不创建 release。
- 详细结果：[Regional Risk V2 RESULTS](training/regional_expert/regional_risk_v2/RESULTS.md)

## 5. Release 最终状态

只有以下三个 release 存在并已更新：

| Release | Source run | Recipe | 模型校验 |
|---|---|---|---|
| `training/base/v0/release` | `v0_full_20260817_corrected_r1` | RF 7/5/1.0, 3,000 trees | MD5 `df2a251b3e80114ddc44873f8618a8c6` |
| `training/base/v1/release` | `v1_full_20260817_corrected_r1` | RF 12/5/1.0, 4,000 trees | MD5 `68ac07ee978cebbfdfa206e93001bfe0` |
| `training/base/v2/release` | `base_v2_full_20260817_corrected_r1` | RF 7/5/1.0, 4,000 trees | SHA-256 `2a9efcf21e80a375fa56e4380400fa26397e3ff0672bf837e81c84d2aee80c62` |

Global High-Sr Risk、High-Sr Correction、Regional Risk V1、V1.1、V2 均因冻结 Gate 未通过而没有 release。这是科学停止结论，不是训练失败。

## 6. 结果归档

| 项目 | Archive | Bytes | SHA-256 |
|---|---|---:|---|
| Base V0 | `base_v0_v0_full_20260817_corrected_r1.tar.gz` | 92,817,522 | `fa93948c13caabbe0931a051222004b56942d0338011eac446332579baf15012` |
| Base V1 | `base_v1_v1_full_20260817_corrected_r1.tar.gz` | 131,912,149 | `46bbbb76ab744b744b106d19799663216e918479192ad50d159e4bf1e8a4bd65` |
| Global High-Sr Risk | `global_high_sr_risk_risk_v1_full_20260817_corrected_r1.tar.gz` | 5,377,115 | `7dba5a17e102210b44b246e2f607edec42f55f1a897e150e84c6ae290a116702` |
| High-Sr Correction | `high_sr_correction_feasibility_high_sr_corr_20260817_corrected_r1.tar.gz` | 33,920,089 | `8a4517aecdb8aef115e2824d2b5a872f138b15f61917b2dd33ed7c7a0d14da90` |
| Base V2 | `base_v2_base_v2_full_20260817_corrected_r1.tar.gz` | 138,258,652 | `64ab1494f24b9a4fd3cd4145a94609944b1986639c94c98c34bb5696962954e1` |
| Regional Risk V1 | `regional_risk_v1_regional_risk_v1_20260817_corrected_r1.tar.gz` | 860,147 | `71791352887bb26b8dcc0015b2d3af1c6083997b98ccd471824b8bcbdda7bd0d` |
| Regional Risk V1.1 | `regional_risk_v1_1_regional_risk_v1_1_20260817_corrected_r1.tar.gz` | 1,259,700 | `4fe11873eef5cf6ab314517a46a1563326d12eb2b37b0d6c9e3f47567ed7f2a8` |
| Regional Risk V2 | `regional_risk_v2_regional_risk_v2_20260817_corrected_r3.tar.gz` | 2,083,266 | `8d867c458fc9550cde988cd47bfe0e868ac7f61231ac757a7f2b21050b9bd0b1` |

## 7. Git 结果提交

| 项目 | 结果提交 |
|---|---|
| Base V0 | `1f6ac22` |
| Base V1 | `b5b5c10` |
| Global High-Sr Risk | `b9596ee` |
| High-Sr Correction | `8062513` |
| Base V2 | `2eed9c4` |
| Regional Risk V1 | `90c323d` |
| Regional Risk V1.1 | `c3bb23a` |
| Regional Risk V2 | `a2e3fed` |

所有上述提交均已推送到 `origin/main`。工作区中原有的 Base V3 未跟踪工程、`.gitignore` 修改、旧 run 日志和文档等不属于本轮重训练范围，均未被纳入这些结果提交。
