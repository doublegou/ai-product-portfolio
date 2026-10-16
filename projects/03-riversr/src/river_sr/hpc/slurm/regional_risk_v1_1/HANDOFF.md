# Regional Risk V1.1 HPC thread handoff

## Required committed assets

- `data/processed/training/himalaya_risk_v1.csv`；
- `training/regional_expert/regional_risk_v1/config/`与`folds/branch_map.csv`，仅作为冻结上游；
- `training/regional_expert/regional_risk_v1_1/config/`、`R/`、`scripts/`和本地生成的`folds/`；
- `hpc/slurm/regional_risk_v1_1/`；
- `env/renv.lock`和可用的`R-4.4.3`module。

Regional Risk V2不是依赖项。集群不得运行`prepare`，不得修改校准器、阈值、FPR caps或evidence targets。

## Takeover sequence

```bash
git pull --ff-only
bash hpc/slurm/regional_risk_v1_1/run.sh bootstrap
bash hpc/slurm/regional_risk_v1_1/run.sh check
bash hpc/slurm/regional_risk_v1_1/run.sh submit regional_risk_v1_1_YYYYMMDD_r1
bash hpc/slurm/regional_risk_v1_1/run.sh status regional_risk_v1_1_YYYYMMDD_r1
```

## Completion contract

- 34个`task_info.json`全部为`complete`；
- 每个任务有16条Inner branch predictions集合、1个正斜率Platt、2个thresholds和17行GAM diagnostics；
- 合计578行GAM diagnostics、34个calibrators、68个thresholds；
- 每个模型各372条Outer OOF predictions，合计744条；
- `gate_metrics.csv`、`branch_metrics.csv`、`extreme_audit.csv`和`DECISION.md`齐全；
- `final_model_fitted=false`、`release_created=false`、`v2_dependency=false`。

完成后归档并校验：

```bash
bash hpc/slurm/regional_risk_v1_1/run.sh archive regional_risk_v1_1_YYYYMMDD_r1
sha256sum --check hpc/transfer/regional_risk_v1_1_regional_risk_v1_1_YYYYMMDD_r1.tar.gz.sha256
```
