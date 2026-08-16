# Data pipelines

每个数据管线都是独立项目，并具有自己的配置和按执行顺序编号的脚本。

`raw_features/` 是一次性原始特征获取入口，不属于训练数据处理链路；正常情况下只在首次准备或显式更新原始版本时运行。

数据管线只从 `data/raw/` 读取共享原始数据，将可重建中间态写入共享的 `data/interim/`，将正式成果写入 `data/processed/` 下对应的项目目录。管线目录本身不保存数据副本。

当前管线按用途与数据集版本分层：`training/sr_full50_v1/` 负责生成历史兼容的 4,485 站第一版 Full50；`observation/sr_supplement_v1/` 冻结九来源补充观测；`training/sr_full50_v2/` 将两版观测处理为 Base V3 使用的历史兼容 5,600 站 Full50；`training/regional_expert/` 保存区域专家数据项目。官方特征重算用于 forward audit；不可再生的冻结预测因子由 `data/raw/model_inputs/` 提供并记录哈希。

Base V2 不新增训练表。HydroBASINS L12 由 `raw_features/` 登记获取；仅针对 4,485 个 Full50 站点生成的 reach/L12/branch 拓扑属于可重建 `data/interim/` 与 `training/base/v2/folds/`，不写入 `data/processed/`。

后续若进入 feature discovery，再单独建立 `global_covariates` 项目；不得把新变量直接追加进已经冻结的 Full50 V2 数据管线。
