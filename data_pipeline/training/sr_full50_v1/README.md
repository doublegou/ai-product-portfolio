# Training / sr_full50_v1 data pipeline

把共享的原始观测和官方特征源转换为 Base Model V0 使用的 Full50 训练表。

## 边界

- 输入：`data/raw/observation/observation_v1.csv` 与 `data/raw/features/`
- 正式输出：`data/processed/training/sr_full50_v1.csv`
- 历史冻结预测因子只在 Codex 校验时读取，不作为新管线输入

## 处理规则

一次性原始数据获取不属于本处理管线。首次运行或原始数据缺失时，单独执行：

```powershell
Rscript data_pipeline/raw_features/run.R
```

Full50 的 `run.R` 只检查 raw 是否齐全，不执行下载。

管线按 `scripts/` 中的编号顺序执行：

1. `01_build_candidate_sites.R`：按两阶段测量身份规则去重，经纬度保留 5 位小数后计算稳定站点 ID，并聚合候选站点。
2. `02_assign_hydrobasins.R`：按 polygon/intersection/25 km fallback 规则正向分配当前 HydroBASINS L6，并构造目标流域及其全部上游祖先的最小处理闭包。
3. `03_extract_hydrology.R`：从 HydroRIVERS 提取河网字段，按 5 km 规则保留可用站点。
4. `04_extract_geology.R`：仅在最小流域闭包内从 GLiM 计算本地和上游岩性比例。
5. `05_extract_climate_terrain.R`：仅在最小流域闭包内构建 WorldClim、Global-AI_ET0 v3.1 与海拔的本地/上游汇总。
6. `06_extract_soil.R`：从 SoilGrids VRT overview 直接构建 5 km、0–30 cm 土壤变量，并仅汇总最小流域闭包；不下载 250 m 全球瓦片。
7. `07_extract_geologic_age.R`：解析 NRCan OF5529 岩石单元年龄，并仅在最小流域闭包内计算本地/上游年龄统计。
8. `08_assemble_full50.R`：按 5 km HydroRIVERS 规则保留正向匹配成功的站点，校验 50 个预测因子并输出训练表。

可重建中间态写入共享的 `data/interim/`；完成气候、土壤和地质年龄步骤后，统一组装并写入 `data/processed/training/`。

当前只运行轻量工程检查和必要的数据处理；全球叠加允许在超算阶段执行。历史差异比较由 Codex 临时命令完成，不在正式项目中保存参考脚本。

`config/full50_predictors.txt` 固定了旧版 `M_FULL_MECHANISTIC` 使用的 50 个变量：28 个 P0、7 个本地岩性、10 个地质年龄、1 个岩性熵和 4 个本地/上游环境变量。历史表中的两个 `r50__` 紧凑代理变量属于 Core 模型，因此不计入 Full50。

## 入口

```powershell
Rscript data_pipeline/training/sr_full50_v1/scripts/run.R
```

失败后从第一个缺失的阶段输出继续：

```powershell
Rscript data_pipeline/training/sr_full50_v1/scripts/run.R --resume
```

默认不带参数时完整重跑，避免无意复用旧中间态。`--resume` 仅用于同一轮运行失败后的断点恢复；它根据每一步成功写出的中间文件定位断点，并从第一个缺失步骤继续。也可以按编号单独运行每一步，便于检查中间状态。`common.R` 只提供各步骤共用的路径、站点 ID 和安全写出能力，不是独立处理步骤，因此不编号。
