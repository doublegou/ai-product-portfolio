# Training data

本目录保存 `data_pipeline/training/sr_full50_v1` 的正式数据成果及其数据集 manifest。

训练项目只读这里的数据。目录内容由数据管线生成，不应被手工编辑。

正式成果统一命名为 `sr_full50_v1.csv`：它应由 6,283 条原始观测和 `data/raw/features/` 中的原始特征源生成，最终保留 4,485 个 Full50 训练站点。

当前 `sr_full50_v1.csv` 已由正式数据管线完整重建并通过历史口径校验，是 Base Model V0 的冻结训练输入。`data/processed/` 属于项目正式数据资产，随项目版本管理；如需更新，必须重新运行对应数据管线，不手工修改 CSV。
