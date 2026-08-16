# Training data

本目录保存 `data_pipeline/training/sr_full50_v1` 的正式数据成果及其数据集 manifest。

训练项目只读这里的数据。目录内容由数据管线生成，不应被手工编辑。

正式成果统一命名为 `sr_full50_v1.csv`：它应由 6,283 条原始观测和 `data/raw/features/` 中的原始特征源生成，最终保留 4,485 个 Full50 训练站点。

当前 `sr_full50_v1.csv` 已由正式数据管线完整重建并通过历史口径校验，是 Base Model V0 的冻结训练输入。`data/processed/` 属于项目正式数据资产，随项目版本管理；如需更新，必须重新运行对应数据管线，不手工修改 CSV。

`himalaya_risk_v1.csv` 由 `data_pipeline/training/regional_expert/risk_v1` 从 Full50 与 Base V2 response-blind site topology 顺向派生。它固定包含 `terminal_component_id = 4060025450` 的 372 个喜马拉雅站点，其中 `Sr >= 0.75` 为 80 行。Regional branch membership 不属于数据资产，由对应训练项目在冻结 LOBO 设计时独立生成。

`himalaya_risk_v2.csv` 由 `data_pipeline/training/regional_expert/risk_v2` 在冻结的 V1 区域表上追加 Process14，并保留全部 V1 列和值不变。该 processed CSV 是正式训练所需的完整数据资产；本地 interim 构建记录只服务于数据管线复核，不是训练依赖。
