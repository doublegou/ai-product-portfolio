# Training / sr_full50_v2 data pipeline

把 4,485 站 Base 观测与九来源补充观测合并，构建 Base Model V3 的 5,600 站历史兼容 Full50 训练 release。

## 边界

- 基础观测：`data/raw/observation/observation_v1.csv`
- 补充观测：`data/processed/observation/sr_supplement_v1.csv`
- 官方特征：`data/raw/features/`
- 恢复的 V2 模型输入：`data/raw/model_inputs/full50_v2_5600_snapshot.csv`
- 正式输出：`data/processed/training/sr_full50_v2.csv`
- 构建 manifest：`data/processed/training/sr_full50_v2_manifest.json`
- 正式运行不读取 `reference/`；恢复的不可再生 V2 快照已提升为带哈希 raw model-input 资产。

## 冻结数据合同

- 1,950 条补充观测中，10 条可能与 V1 重复的记录不进入训练候选。
- 1,940 条准入记录形成 1,122 个新候选坐标点。
- V1 与补充数据合计形成 5,649 个候选站点。
- 5 km HydroRIVERS 匹配后应保留原 4,485 站和新增 1,115 站，最终 5,600 行。
- 原 4,485 站的稳定站点 ID和响应保持不变。
- V2 的 50 个预测变量必须对齐历史 5,600 站 V2 release。历史 V2 曾重新抽取旧 4,485 站特征，因此“V2 predictor 必须等于 V1”不是有效合同。

## 处理步骤

1. `01_build_candidate_sites.R`：合并两个正式观测 release，排除已标记的跨版本可能重复记录，按五位小数坐标聚合。
2. `02_assign_hydrobasins.R`：分配 HydroBASINS L6，并构造全部目标流域的最小上游闭包。
3. `03_extract_hydrology.R`：在 HydroRIVERS 上做 5 km 正向河网匹配。
4. `04_extract_geology.R`：从 GLiM 计算局地及上游岩性。
5. `05_extract_climate_terrain.R`：提取 WorldClim、Global-AI_ET0 和高程。
6. `06_extract_soil.R`：提取 SoilGrids 0–30 cm clay/pH。
7. `07_extract_geologic_age.R`：提取 NRCan 地质年龄。
8. `08_assemble_full50.R`：用坐标键对齐恢复的 V2 Full50 块，保留正向构建的稳定 ID、来源和水文元数据，写出完整表。
9. `09_validate_release.R`：校验 5,600 行、Sr 分层、50 predictors、旧站响应以及历史 V2 predictor 对齐，并写出 SHA256 manifest。

## 本机运行

```powershell
Rscript data_pipeline/observation/sr_supplement_v1/scripts/run.R
Rscript data_pipeline/training/sr_full50_v2/scripts/run.R
```

中断后使用：

```powershell
Rscript data_pipeline/training/sr_full50_v2/scripts/run.R --resume
```

默认完整重跑；`--resume` 从第一个缺失的 V2 专属 checkpoint 继续。V1 中间文件不会被读取或覆盖。
