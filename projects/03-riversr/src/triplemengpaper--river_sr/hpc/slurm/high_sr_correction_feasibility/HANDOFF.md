# HPC thread handoff

## Required cluster state

- the pushed Git revision containing this project;
- `data/processed/training/sr_full50_v1.csv`;
- the committed Base V1 release metadata and all frozen Primary fold files;
- this project's committed `config/` and `folds/` directories;
- `env/renv.lock` and the cluster `R-4.4.3` module.

Raw HydroBASINS files and the Global High-Sr Risk outputs are not required. `reference/` is not a runtime dependency.

## Takeover

```bash
git pull --ff-only
bash hpc/slurm/high_sr_correction_feasibility/run.sh bootstrap
bash hpc/slurm/high_sr_correction_feasibility/run.sh check
bash hpc/slurm/high_sr_correction_feasibility/run.sh submit high_sr_corr_YYYYMMDD_r1
bash hpc/slurm/high_sr_correction_feasibility/run.sh status high_sr_corr_YYYYMMDD_r1
```

The default concurrency can allocate roughly 10x16 CPUs for Base tasks, then 15x4 CPUs for Elastic and 5x16 CPUs for RF while both correction arrays overlap. Reduce `CORR_BASE_PARALLEL`, `CORR_ELASTIC_PARALLEL`, or `CORR_RF_PARALLEL` to meet quota. Base/RF jobs request 32 GB and 24 hours; Elastic jobs request 12 GB and 6 hours.

Completed tasks are idempotent and signature-checked. Resubmitting the same run ID skips complete tasks and runs missing work. Never use `--force` unless intentionally replacing a complete task after a reviewed code/config change.

## Completion contract

- 15 Base task directories each contain `task_info.json` with 16 unique Base fits;
- 30 correction task directories are complete;
- each model has three complete 4,485-row OOF files, with 671 Oracle rows per feature set/repeat;
- validation contains repeat, candidate, tail, group, selected-task and OOF-manifest outputs;
- `runs/<run_id>/reports/decision.json` and `decision.md` exist;
- `run_info.json` reports 45 training tasks, 240 unique Base fits and `final_model_fitted=false`.

Return the archive and checksum produced by:

```bash
bash hpc/slurm/high_sr_correction_feasibility/run.sh archive high_sr_corr_YYYYMMDD_r1
sha256sum --check hpc/transfer/high_sr_correction_feasibility_high_sr_corr_YYYYMMDD_r1.tar.gz.sha256
```
