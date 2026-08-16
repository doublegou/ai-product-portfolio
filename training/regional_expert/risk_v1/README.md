# Regional Expert — Himalaya Risk V1

本项目顺向复现喜马拉雅高-Sr区域风险信号实验。训练域固定为 `himalaya_risk_v1.csv` 的372个站点；阳性定义为 `Sr >= 0.75`。验证采用17个 exhaustive、outcome-blind regional branches的严格LOBO。

五个预注册模型臂为：GAM Spatial-only、GAM Environment-only、GAM Combined、Elastic Net Environment和Elastic Net Combined。GAM使用固定结构，不进行超参数竞争；Elastic Net仅作为低复杂度线性基线。

V1不选择Gate阈值、不校准概率、不进行hard routing、不拟合full-data expert，也不生成release。其输出只用于判断区域内是否存在可跨陌生branch迁移的风险结构。

## 顺向边界

- branch构造只读取L12 topology、station membership和station count；不读取Sr、label、reference、历史OOF或历史membership。
- bottom-up未分配站点累计达到20时在当前L12切出branch并向下游传递0；主出口剩余站点形成residual branch。
- branch冻结以后才做80/292、14 mixed + 3 all-negative的label audit。
- 历史artifact没有保存Elastic Net alpha；本次将`alpha = 0.5`作为显式顺向复现假设冻结，不使用包默认值。

## 本地准备与工程检查

```bash
Rscript data_pipeline/training/regional_expert/risk_v1/scripts/run.R
Rscript training/regional_expert/risk_v1/scripts/run.R --stage prepare
Rscript training/regional_expert/risk_v1/scripts/run.R --stage check
```

`prepare`只构建folds与task manifest，不训练模型。正式训练由HPC工作流接管。
