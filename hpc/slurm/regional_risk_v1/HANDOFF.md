# HPC thread handoff

## Required committed assets

- `data/processed/training/himalaya_risk_v1.csv`；
- `training/regional_expert/risk_v1/config/`；
- 已冻结的`training/regional_expert/risk_v1/folds/`；
- Regional Risk V1的`R/`、`scripts/`与本Slurm目录；
- `env/renv.lock`和可用的`R-4.4.3`module。

集群不需要历史OOF、Base predictions、HydroBASINS原始DBF或Base V2 interim topology。branch map已经本地顺向生成并提交；禁止在集群重新prepare，也不运行smoke model。

## Takeover sequence

```bash
git pull --ff-only
bash hpc/slurm/regional_risk_v1/run.sh bootstrap
bash hpc/slurm/regional_risk_v1/run.sh check
bash hpc/slurm/regional_risk_v1/run.sh submit regional_risk_v1_YYYYMMDD_r1
bash hpc/slurm/regional_risk_v1/run.sh status regional_risk_v1_YYYYMMDD_r1
```

默认并发为51个GAM任务×2 CPUs与34个Elastic任务×2 CPUs，两组数组可同时运行。配额较低时通过`REGIONAL_GAM_PARALLEL`和`REGIONAL_ELASTIC_PARALLEL`下调并发，不改变冻结任务。

## Completion contract

- 85个`task_info.json`全部`complete`；
- 每个模型臂恰有372条严格LOBO predictions；
- 合并`oof_predictions.csv`恰有1,860行；
- pooled、mixed-branch、sensitivity、bootstrap与paired contrast文件齐全；
- `runs/<run_id>/reports/DECISION.md`存在；
- `run_info.json`为`complete`且`final_model_fitted=false`、`gate_selected=false`、`release_created=false`。

完成后执行：

```bash
bash hpc/slurm/regional_risk_v1/run.sh archive regional_risk_v1_YYYYMMDD_r1
sha256sum --check hpc/transfer/regional_risk_v1_regional_risk_v1_YYYYMMDD_r1.tar.gz.sha256
```
