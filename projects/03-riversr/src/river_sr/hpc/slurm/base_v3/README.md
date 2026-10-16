# Base V3 Slurm workflow

The formal dependency graph is:

```text
check
  ├─ RF Primary[1-15] ─┐
  └─ XGB Primary[1-15] ┴─ aggregate
                           ├─ RF deployment ─ RF stress[1-20] ┐
                           └─ XGB deployment ─ XGB stress[1-20]┴─ finalize ─ check results
```

From the HPC repository root:

```bash
bash hpc/slurm/base_v3/run.sh bootstrap
bash hpc/slurm/base_v3/run.sh submit base_v3_full_YYYYMMDD_r1
bash hpc/slurm/base_v3/run.sh status base_v3_full_YYYYMMDD_r1
bash hpc/slurm/base_v3/run.sh archive base_v3_full_YYYYMMDD_r1
```

`training/base/v3/folds/manifest.json` and every listed fold artifact must be
transferred unchanged. The formal jobs do not regenerate folds.

Resource defaults are conservative and can be overridden with the environment
variables documented by `run.sh`. Candidate summaries are checkpointed after
each candidate, so resubmitting the same task/run ID resumes completed work.
