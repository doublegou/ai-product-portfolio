# Observation data projects

观测数据项目把不可变的 `data/raw/observation/` 输入转换为带来源审计和训练准入标记的正式观测 release。

- `sr_supplement_v1/`：九个公开来源的 1,950 条补充河流/溪流水观测。

训练数据管线只能读取这里生成的 `data/processed/observation/` 成果，不读取 `reference/`。
