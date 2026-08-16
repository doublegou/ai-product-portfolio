# Raw feature acquisition

这是共享原始特征的一次性获取入口，不属于任何训练数据处理管线。

首次准备、原始文件缺失或明确升级数据版本时运行：

```powershell
Rscript data_pipeline/raw_features/run.R
```

入口按照 `config/sources.yml` 下载、选择性解压并校验文件，最终更新
`data/raw/features/download_inventory.csv`。正常执行
`data_pipeline/training/sr_full50_v1/scripts/run.R` 时不会调用这里。

下载默认读取当前 Windows 系统代理；其他环境可通过
`RIVER_SR_DOWNLOAD_PROXY` 显式指定代理。AI/ET0 固定使用经校验的
Global-AI_ET0 annual v3.1。
