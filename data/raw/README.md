# Raw data

本目录保存全项目共享、不可原地修改的原始输入，只保留一份物理副本。

`observation/observation_v1.csv` 是第一版原始观测数据。它由 `world_river_water_sr_solute.xlsx` 中 `Solute_river_stream!A1:U6284` 导出为 UTF-8 CSV：字段顺序、6,283 条数据记录和所有单元格值保持一致；Excel 样式和非数据工作表不属于 CSV 内容。

`features/` 保存 Full50 实际需要的官方原始特征源。这里不是旧工程数据仓库的全量镜像；冻结预测因子快照属于历史校验材料，已放回 `reference/`。

Base V2 additionally registers HydroBASINS L12 under `features/hydrography/`. L12 and HydroRIVERS are used only to construct response-blind branch/purge validation geometry for the existing 4,485 Full50 stations; they are not additional predictors and are not a global prediction dataset.
