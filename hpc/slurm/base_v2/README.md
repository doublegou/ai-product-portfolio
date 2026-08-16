# Base V2 Slurm workflow

Base V2 topology and folds are prepared and frozen locally. The cluster must not rebuild GIS topology and does not need HydroRIVERS or HydroBASINS.

```bash
bash hpc/slurm/base_v2/run.sh bootstrap
bash hpc/slurm/base_v2/run.sh submit base_v2_full_YYYYMMDD_r1
bash hpc/slurm/base_v2/run.sh status base_v2_full_YYYYMMDD_r1
bash hpc/slurm/base_v2/run.sh archive base_v2_full_YYYYMMDD_r1
```

The dependency chain is:

```text
check
  -> primary array (15 tasks)
  -> deployment (all 48 recipes)
  -> stress array (25 tasks)
  -> finalize (aggregate + 4,000-tree final model)
```

Defaults request up to 15 x 32 CPUs for Primary and 25 x 16 CPUs for stress. Concurrency and CPUs can be overridden through the `V2_*` environment variables documented by `run.sh`.
