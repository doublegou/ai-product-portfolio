# Regional Risk V1 decision

Run ID: `regional_risk_v1_20260817_r2`

## Status

`SIGNAL_FEASIBILITY_ONLY`

本实验只评估喜马拉雅区域高-Sr风险结构在完整陌生regional branch上的迁移能力。它不产生Gate、校准器、hard routing、full-data expert或release。

## Pooled station-equal LOBO metrics

| Model | PR-AUC | ROC-AUC | Brier | Log loss |
|---|---:|---:|---:|---:|
| elastic_combined | 0.125565 | 0.151541 | 0.175542 | 0.541568 |
| elastic_environment | 0.125565 | 0.151541 | 0.175542 | 0.541568 |
| gam_combined | 0.337107 | 0.712714 | 0.173978 | 0.530183 |
| gam_environment | 0.310999 | 0.705801 | 0.165474 | 0.493358 |
| gam_spatial_only | 0.276435 | 0.676584 | 0.173455 | 0.501907 |

## Frozen candidate roles

- `ranking_candidate`: `gam_combined` — Best pooled OOF PR-AUC point estimate among Environment and Combined GAM; ROC-AUC secondary.
- `probability_candidate`: `gam_environment` — Lowest pooled OOF Brier among Environment and Combined GAM; log loss secondary; not calibrated.
- `spatial_diagnostic_control`: `gam_spatial_only` — Diagnostic only; ineligible for winner selection.
- `linear_complexity_baseline_environment`: `elastic_environment` — Intercept-only in 17/17 Outer folds.
- `linear_complexity_baseline_combined`: `elastic_combined` — Intercept-only in 17/17 Outer folds.

## Interpretation boundary

候选角色依据预先冻结的点估计规则产生。模型间bootstrap contrast用于不确定性诊断；point-estimate winner不等于统计学上确定优于另一GAM。Elastic Net仅回答简单线性结构是否足够。

Elastic Net alpha固定为`0.5`；状态：`forward_reconstruction_frozen_assumption_historical_value_not_preserved`。

最终结论不得表述为可部署Regional Expert。
