# Training data

本目录保存各训练数据管线的正式数据成果及其数据集 manifest。

训练项目只读这里的数据。目录内容由数据管线生成，不应被手工编辑。

正式成果统一命名为 `sr_full50_v1.csv`：它应由 6,283 条原始观测和 `data/raw/features/` 中的原始特征源生成，最终保留 4,485 个 Full50 训练站点。

当前 `sr_full50_v1.csv` 由原始观测正向聚合并连接恢复的 V1 冻结预测因子块，已与历史 4,485 × 121 表逐字段校验，是 Base Model V0 的冻结训练输入。官方栅格重算属于 forward audit，不替代该 release。

`sr_full50_v2.csv` 由 `data_pipeline/training/sr_full50_v2` 构建，是 Base Model V3 的冻结候选输入。它包含原 4,485 站和新增 1,115 站，共 5,600 行、50 个 Full50 predictors；预测变量对齐历史 V2 5,600 release，而不是错误地强制等于 V1。输入/输出签名、Sr 分层、来源保留数和版本差异记录在 `sr_full50_v2_manifest.json`。

`himalaya_risk_v1.csv` 由 `data_pipeline/training/regional_expert/risk_v1` 从 Full50 与 Base V2 response-blind site topology 顺向派生。它固定包含 `terminal_component_id = 4060025450` 的 372 个喜马拉雅站点，其中 `Sr >= 0.75` 为 80 行。Regional branch membership 不属于数据资产，由对应训练项目在冻结 LOBO 设计时独立生成；输入、输出及拓扑签名记录在 `himalaya_risk_v1_manifest.json`。

`himalaya_risk_v2.csv` 由 `data_pipeline/training/regional_expert/risk_v2` 在冻结的 V1 区域表上追加 Process14，并保留全部 V1 列和值不变。该 processed CSV 是正式训练所需的完整数据资产；`himalaya_risk_v2_manifest.json` 记录 V1/branch map、Full50/Process14 字段清单、公式字典及输出签名。
