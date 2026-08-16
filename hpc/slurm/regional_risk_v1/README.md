# Regional Risk V1 on Slurm

正式依赖链为：

1. 无训练工程检查；
2. 51个GAM LOBO任务与34个Elastic Net LOBO任务并行；
3. 汇总完整1,860条OOF predictions并生成branch bootstrap与V1结论。

```bash
bash hpc/slurm/regional_risk_v1/run.sh bootstrap
bash hpc/slurm/regional_risk_v1/run.sh check
bash hpc/slurm/regional_risk_v1/run.sh submit regional_risk_v1_YYYYMMDD_r1
bash hpc/slurm/regional_risk_v1/run.sh status regional_risk_v1_YYYYMMDD_r1
bash hpc/slurm/regional_risk_v1/run.sh archive regional_risk_v1_YYYYMMDD_r1
```

集群禁止运行`--stage prepare`。提交前必须已有版本管理中的`himalaya_risk_v1.csv`和完整`folds/`。本项目不产生Gate、校准器、最终模型或release。
