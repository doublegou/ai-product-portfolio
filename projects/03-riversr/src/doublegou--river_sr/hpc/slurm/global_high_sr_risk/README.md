# Global High-Sr Risk V1 on Slurm

The formal dependency chain is:

1. no-training engineering check;
2. 15 Elastic-net Outer tasks and 15 probability-RF Outer tasks in parallel arrays;
3. complete repeat-level OOF aggregation;
4. frozen six-gate feasibility decision.

The default RF request is intentionally larger than the Elastic-net request because each RF Outer task fits 24 candidates across three Inner folds at 1,000 trees, then one 2,000-tree Outer model. Adjust array concurrency to the cluster quota before changing per-task CPUs.

```bash
bash hpc/slurm/global_high_sr_risk/run.sh bootstrap
bash hpc/slurm/global_high_sr_risk/run.sh submit risk_v1_full_YYYYMMDD_r1
bash hpc/slurm/global_high_sr_risk/run.sh status risk_v1_full_YYYYMMDD_r1
bash hpc/slurm/global_high_sr_risk/run.sh archive risk_v1_full_YYYYMMDD_r1
```

Do not run `--stage prepare` on the cluster. The committed folds must pass `--stage check` unchanged. The returned archive contains folds, all 30 task outputs, six complete OOF prediction sets, repeat/model summaries, the decision report and Slurm logs; it contains no deployable model.
