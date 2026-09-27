# Raw feature sources

本目录只保存 Base Full50 管线实际使用的官方原始特征源。它不是旧工程全部数据的镜像。文件由
首次准备时由独立入口 `data_pipeline/raw_features/run.R` 下载。Full50 处理管线只读取这里的数据，不触发下载。下载内容不提交 Git，也不应手工修改。

当前数据源包括 HydroRIVERS v1、HydroBASINS v1c level 6、GLiM v1、WorldClim 2.1、Global AI/ET0 v3、SoilGrids 2.0，以及 NRCan Open File 5529。部分官方发布只提供整包，因此压缩包内部可能带有少量本项目不用的伴随文件。下载地址、状态和落盘位置统一记录在 `data_pipeline/raw_features/config/sources.yml` 与本目录的 `download_inventory.csv`。

WorldClim 的官方服务器在当前网络下不可达，因此 BIO 整包经公开 release 镜像传输，海拔单层经 Zenodo 数据集传输；两者都在清单中保留官方 `canonical_url` 并锁定校验值。BIO 整包只解压 Full50 使用的 1、4、12、15 四层。SoilGrids 只保存 VRT 与 overview，不下载约数 GB 的 250 m 全球瓦片。
