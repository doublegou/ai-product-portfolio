# High-Sr Correction Feasibility on Slurm

The formal chain is `check -> 15 strict-nested Base tasks -> 15 Elastic and 15 residual-RF tasks -> aggregate -> decide`. Each Base task fits 16 unique 2,000-tree Base RFs. Each RF correction task evaluates 28 total candidate recipes across the three feature sets and five strict correction contexts, then fits three 2,000-tree Outer correction models.

```bash
bash hpc/slurm/high_sr_correction_feasibility/run.sh bootstrap
bash hpc/slurm/high_sr_correction_feasibility/run.sh check
bash hpc/slurm/high_sr_correction_feasibility/run.sh submit high_sr_corr_YYYYMMDD_r1
bash hpc/slurm/high_sr_correction_feasibility/run.sh status high_sr_corr_YYYYMMDD_r1
bash hpc/slurm/high_sr_correction_feasibility/run.sh archive high_sr_corr_YYYYMMDD_r1
```

Do not run `prepare` or any ad-hoc model on the cluster. The committed task manifests must pass `check` unchanged. Lower array concurrency first when account quota is constrained; do not change the frozen statistical configuration.
