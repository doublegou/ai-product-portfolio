# Data pipelines

每个数据管线都是独立项目，并具有自己的 README、配置、实现、测试和唯一运行入口。

数据管线只从 `data/raw/` 读取共享原始数据，只向与项目同名的 `data/interim/` 和 `data/processed/` 目录写入结果。管线目录本身不保存数据副本。

项目包括：

- `base_observations`
- `supplement_observations`
- `global_covariates`

每个项目均有独立的 `run.R`。当前未实现的入口会明确停止并报告 scaffold 状态。
