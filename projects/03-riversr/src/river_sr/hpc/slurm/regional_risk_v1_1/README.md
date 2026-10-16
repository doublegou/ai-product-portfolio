# Regional Risk V1.1 on Slurm

正式依赖链：

1. 无正式训练的工程检查；
2. 34 个 `Outer branch × frozen GAM` 数组任务；
3. 聚合 744 条 Outer OOF predictions 并生成 V1.1 decision。

每个数组任务内部执行 16 个 Inner GAM、1 个 branch-sqrt-weighted Platt calibrator、2 个 inner-only thresholds 和 1 个 Outer GAM。

```bash
bash hpc/slurm/regional_risk_v1_1/run.sh bootstrap
bash hpc/slurm/regional_risk_v1_1/run.sh check
bash hpc/slurm/regional_risk_v1_1/run.sh submit regional_risk_v1_1_YYYYMMDD_r1
bash hpc/slurm/regional_risk_v1_1/run.sh status regional_risk_v1_1_YYYYMMDD_r1
bash hpc/slurm/regional_risk_v1_1/run.sh archive regional_risk_v1_1_YYYYMMDD_r1
```

集群禁止运行 `--stage prepare`。提交前必须提交本地冻结的 `folds/`。本项目不读取 Regional Risk V2，不拟合 full-data expert，也不创建 release。
