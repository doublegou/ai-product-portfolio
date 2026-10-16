# Regional Risk V2 on Slurm

The wrapper submits a checked 68-element array and runs aggregation only after every task succeeds. `prepare` is intentionally absent from the cluster workflow: fold and method artifacts must already be frozen locally.

```bash
bash hpc/slurm/regional_risk_v2/run.sh bootstrap
bash hpc/slurm/regional_risk_v2/run.sh check
bash hpc/slurm/regional_risk_v2/run.sh submit regional_risk_v2_YYYYMMDD_r1
bash hpc/slurm/regional_risk_v2/run.sh status regional_risk_v2_YYYYMMDD_r1
```
