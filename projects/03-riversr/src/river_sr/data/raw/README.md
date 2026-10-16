# Raw data

本目录保存全项目共享、不可原地修改的原始输入，只保留一份物理副本。

`observation/observation_v1.csv` 是第一版原始观测数据。它由 `world_river_water_sr_solute.xlsx` 中 `Solute_river_stream!A1:U6284` 导出为 UTF-8 CSV：字段顺序、6,283 条数据记录和所有单元格值保持一致；Excel 样式和非数据工作表不属于 CSV 内容。

`observation/observation_supplement_v1.csv` 是九个公开来源恢复的规范化补充观测快照，共 1,950 行。它保留来源记录号、DOI、URL、许可证、坐标、日期、单位换算结果和 QC 备注，由 `data_pipeline/observation/sr_supplement_v1` 校验并生成正式观测 release。

`features/` 保存 Full50 forward-audit 使用的官方原始特征源。这里不是旧工程数据仓库的全量镜像。

`model_inputs/` 保存已经恢复但无法由现存中间成果逐值再生的冻结模型输入：V1 的 4,527 站预测因子块与 V2 的 5,600 站快照。两份文件保留原始哈希；正式数据管线从这里读取，不从 `reference/` 读取。

Base V2 additionally registers HydroBASINS L12 under `features/hydrography/`. L12 and HydroRIVERS are used only to construct response-blind branch/purge validation geometry for the existing 4,485 Full50 stations; they are not additional predictors and are not a global prediction dataset.
