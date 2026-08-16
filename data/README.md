# Data

数据层只保留三种状态：

## raw

全项目共享的原始输入，只保留一份。raw 数据不可被数据管线原地修改。

## interim

可由数据管线重新生成的临时中间状态。当前先使用共享的 `interim/` 一层，不提前按项目分目录；实际开发时如果中间文件发生冲突，再依据真实需要拆分。

## processed

数据管线的正式训练表统一放在 `processed/training/`。训练项目只读 processed 数据，不向这里写入模型结果。

当前 raw 数据集登记在 `manifest.yml`。不设置 `model_input/` 层。
