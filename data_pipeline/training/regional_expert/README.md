# Regional expert data pipelines

本目录按区域专家实验版本组织可重建训练数据。当前仅实现 `risk_v1/`；研究区域固定为喜马拉雅，因此区域名写入正式数据集名称，不再重复出现在目录层级。

`risk_v1/` 从已冻结的 `sr_full50_v1.csv` 与 Base V2 response-blind site topology 中顺向筛选 `terminal_component_id = 4060025450` 的 372 个站点，生成 `data/processed/training/himalaya_risk_v1.csv`。它不读取历史 Regional V1 OOF、Sr 派生的 branch 统计或任何历史 station-to-branch membership。

运行：

```bash
Rscript data_pipeline/training/regional_expert/risk_v1/scripts/run.R
```

该管线只生成区域训练表。Regional branch reconstruction、LOBO assignments 与模型任务属于 `training/regional_expert/regional_risk_v1/`。
