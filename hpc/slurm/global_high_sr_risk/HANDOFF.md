# HPC thread handoff

## What must exist on the cluster

- the Git revision containing this project;
- `data/processed/training/sr_full50_v1.csv`;
- `data_pipeline/training/sr_full50_v1/config/full50_predictors.txt`;
- the frozen Base V1 `fold_manifest.json`, `primary_outer_assignments.csv`, and `hydrological_groups.csv`;
- the committed Risk V1 `config/` and `folds/` directories;
- `env/renv.lock` and a working `R-4.4.3` module.

Raw HydroBASINS GIS files are not required. Do not run `--stage prepare` and do not run a smoke model on the cluster.

## Standard takeover sequence

```bash
git pull --ff-only
bash hpc/slurm/global_high_sr_risk/run.sh bootstrap
bash hpc/slurm/global_high_sr_risk/run.sh check
bash hpc/slurm/global_high_sr_risk/run.sh submit risk_v1_full_YYYYMMDD_r1
bash hpc/slurm/global_high_sr_risk/run.sh status risk_v1_full_YYYYMMDD_r1
```

Default maximum concurrent allocation is approximately 15 Elastic tasks x 4 CPUs plus 10 RF tasks x 16 CPUs while both arrays overlap. Lower `RISK_ELASTIC_PARALLEL` or `RISK_RF_PARALLEL` when the account quota is smaller. Per-task defaults are 12 GB/4 hours for Elastic and 24 GB/12 hours for RF. The control jobs use at most 12 GB and one hour.

Completed task outputs are idempotent. If a task or downstream dependency fails after the cause is fixed, submitting the same run ID again safely skips complete task directories and reruns missing work. Use `--force` only when intentionally replacing a complete task generated from the same frozen signatures.

## Completion contract

The workflow is complete only when:

- all 30 `task_info.json` files report `complete`;
- each model has three 4,485-row `oof_predictions.csv` files;
- `validation/repeat_metrics.csv`, `model_summary.csv`, `selected_tasks.csv`, and `oof_manifest.json` exist;
- `runs/<run_id>/reports/decision.json` and `decision.md` exist;
- `run_info.json` reports `complete`, `training_tasks = 30`, and `final_model_fitted = false`.

Package and return the evidence with:

```bash
bash hpc/slurm/global_high_sr_risk/run.sh archive risk_v1_full_YYYYMMDD_r1
sha256sum --check hpc/transfer/global_high_sr_risk_risk_v1_full_YYYYMMDD_r1.tar.gz.sha256
```

Download both the archive and its SHA-256 file. The archive includes frozen folds, shared validation outputs, reports, task logs and Slurm logs; no model bundle is expected.
