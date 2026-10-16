# Global river-water Sr isoscape checkpoint

## 已完成

- 全球河水 Sr 样点清洗与 HydroRIVERS snap
- 4465 个独立建模站点
- random CV 与 1000 km spatial block CV
- L6 local/upstream GLiM geology
- L6 local/upstream climate and terrain
- climate/terrain 挂接到全部 4465 个站点
- 气候地形增量模型比较
- 选定 upstream geology + upstream environment 为主模型候选
- 0–30 cm SoilGrids pH 与 clay 合成
- 九区 L6 local/upstream soil 汇总
- soil 挂接到全部 4465 个站点

## 当前重要结果

主模型候选：
space + hydrology + upstream geology + upstream climate/terrain

Spatial block CV:
R2 = 0.164
RMSE = 0.00961

完整复杂模型：
local/upstream geology + local/upstream environment

Spatial block CV:
R2 = 0.172
RMSE = 0.00957

Soil site coverage:
- all sites = 4465
- soil predictors complete = 4465
- coverage >= 0.8 = 4034
- coverage >= 0.9 = 3137

## 当前核心站点文件

data_processed/global/global_model_sites_5km_with_geology_climate_terrain_soil_complete.rds

## 明天下一步

建立并运行：
scripts/18_global_soil_models.R
slurm/18_global_soil_models.sbatch

目标：
在相同的 4465 个站点和相同 CV 框架下，测试 upstream/local pH 和 clay 是否提高 spatial block CV。

若 soil 有增益：
再对 coverage >= 0.8 的 4034 个站点做敏感性分析。

若 soil 无增益：
不将 soil 纳入最终主模型。
