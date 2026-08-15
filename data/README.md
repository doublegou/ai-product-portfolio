# Data

数据层只保留三种状态：

## raw

全项目共享的原始输入，只保留一份。raw 数据不可被数据管线原地修改。

## interim

可由数据管线重新生成的中间状态。目录按数据管线项目隔离，例如 `interim/base_observations/`。

## processed

数据管线的正式输出。目录与数据管线项目一一对应。训练项目只读 processed 数据，不向这里写入模型结果。

当前 raw 数据集登记在 `manifest.yml`。不设置 `model_input/` 层。
