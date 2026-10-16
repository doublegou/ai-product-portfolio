# Sr Supplement V1 observation pipeline

本项目冻结九个公开来源的补充河流/溪流水观测，并生成可被 Full50 V2 数据管线读取的正式观测 release。

## 边界

- 不可变输入：`data/raw/observation/observation_supplement_v1.csv`
- 正式输出：`data/processed/observation/sr_supplement_v1.csv`
- 构建 manifest：`data/processed/observation/sr_supplement_v1_manifest.json`
- `reference/` 只用于工程完成后的外部核对，不是运行输入。

raw CSV 是从九个公开来源恢复的规范化观测快照。它保留原始来源记录号、DOI、URL、许可证、坐标、日期、化学字段、单位换算结果和 QC 备注；其角色与由原工作簿导出的 `observation_v1.csv` 相同，属于不可原地修改的观测输入。

## 处理规则

1. 校验 1,950 行、九来源计数、坐标、Sr 范围、来源 URL/许可证和唯一 `supplement_id`。
2. 生成与第一版观测兼容的 21 个标准字段，同时完整保留补充来源字段。
3. `possible_existing_match=yes` 的 10 行保留在正式观测 release 中，但设置 `qc_include_training=FALSE`，避免改变原 4,485 站点的响应。
4. 训练准入记录应为 1,940 行、1,122 个五位小数坐标点；最终能否进入 Full50 由后续 5 km HydroRIVERS 匹配决定。

## 入口

```powershell
Rscript data_pipeline/observation/sr_supplement_v1/scripts/run.R
```

可单独运行 `--stage validate`、`--stage build` 或 `--stage check`。默认完整重建；正式输出采用临时文件加原子替换。
