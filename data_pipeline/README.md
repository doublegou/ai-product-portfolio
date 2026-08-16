# Data pipelines

每个数据管线都是独立项目，并具有自己的配置和按执行顺序编号的脚本。

`raw_features/` 是一次性原始特征获取入口，不属于训练数据处理链路；正常情况下只在首次准备或显式更新原始版本时运行。

数据管线只从 `data/raw/` 读取共享原始数据，将可重建中间态写入共享的 `data/interim/`，将正式成果写入 `data/processed/` 下对应的项目目录。管线目录本身不保存数据副本。

当前管线按用途与数据集版本分层：`training/sr_full50_v1/` 负责构建 Base V0 使用的 Full50 训练数据。

Base V2 不新增训练表。HydroBASINS L12 由 `raw_features/` 登记获取；仅针对 4,485 个 Full50 站点生成的 reach/L12/branch 拓扑属于可重建 `data/interim/` 与 `training/base/v2/folds/`，不写入 `data/processed/`。

计划中的后续项目为：

- `supplement_observations`
- `global_covariates`

后续项目轮到时再建立目录。
