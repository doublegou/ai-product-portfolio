# Global river-water Sr isoscape v2 — cluster project

This folder implements the staged framework:

1. rebuild and audit the response dataset;
2. compare predictor architectures before comparing many algorithms;
3. diagnose high-value and hydrogeological residual structure;
4. add experts only when spatial OOF evidence supports them;
5. finish with AOA-aware HydroRIVERS prediction.

## What is ready immediately

The original workbooks are already included:

- `data/raw/world_river_water_sr_full.xlsx` — full archive
- `data/raw/world_river_water_sr_solute.xlsx` — primary dissolved river/stream dataset

Stage 01 reads the strict solute workbook, preserves every valid measurement, adds duplicate and tail flags, and writes QC tables and figures. It does **not** automatically delete duplicates.

## What is intentionally not fabricated

The uploaded Excel files contain observations, not the external spatial predictors, upstream catchment summaries, HydroRIVERS prediction table, basin IDs or hydrogeological regimes. Therefore:

- QC runs now.
- Predictor/model stages run after `data/external/predictors_at_samples.rds` is supplied.
- D/E/final stages are guarded and stop with a clear message when required inputs are absent.

## Create the reproducible environment

From the repository root, run:

```bash
./bootstrap.sh
```

This creates the `sr_rf` Conda environment, restores the locked R packages, and
runs the software-only environment check. Runtime binaries and installed R
packages remain outside the Git repository.

## Put it on the cluster

```bash
# On your computer: unzip this folder, then upload it
scp -r river_sr_isoscape_v2_cluster USER@CLUSTER:~/

# On the cluster
cd ~/river_sr_isoscape_v2_cluster
micromamba create -f environment.yml
micromamba activate sr_rf
Rscript install_packages.R
Rscript R/00_setup_check.R
```

Edit `slurm/common_env.sh` if the project path or environment name differs.

## Run the data QC first

```bash
bash slurm/submit_qc.sh
```

Expected main outputs:

```text
data/processed/river_sr_observations_clean.rds
outputs/qc/qc_summary.csv
outputs/qc/observations_with_qc_flags.csv
outputs/qc/tail_audit_ge_0.718.csv
outputs/qc/tail_audit_ge_0.720.csv
outputs/qc/tail_audit_ge_0.722.csv
outputs/qc/reference_summary.csv
outputs/qc/sr_distribution.png
outputs/qc/raw_observation_map.png
data/external/predictors_at_samples_TEMPLATE.csv
```

## Add predictors

Use `data/external/predictors_at_samples_TEMPLATE.csv` as the join-key template. Save the completed predictor table as:

```text
data/external/predictors_at_samples.rds
```

Read `data/external/README.md` for the required prefix convention.

## Submit the model pipeline

```bash
bash slurm/submit_pipeline.sh
```

This submits through experiment C using Slurm dependencies. D, E and final mapping are not auto-submitted because they require additional regime, weighting and HydroRIVERS inputs.

## Stage commands

```bash
Rscript R/99_run_stage.R qc
Rscript R/99_run_stage.R table
Rscript R/99_run_stage.R folds
Rscript R/99_run_stage.R A
Rscript R/99_run_stage.R B
Rscript R/99_run_stage.R diagnose
Rscript R/99_run_stage.R C
Rscript R/99_run_stage.R D
Rscript R/99_run_stage.R E
Rscript R/99_run_stage.R final
```

## Important modelling choices

- `sample_id` and exact-measurement duplicates are flagged, not silently removed.
- Spatial folds balance total observations and ≥0.720 observations.
- Hyperparameters are selected inside each outer fold.
- The C2 residual expert is cross-fitted by held-out spatial expert folds on global OOF residuals.
- Candidate models within 5% of the best inner RMSE are separated by tail bias and range compression.
- Concentration-based Sr-flux weighting is disabled until units are independently verified.
- The final script outputs a global prediction plus DI/AOA/LPD. Expert correction and calibrated predictive intervals remain separate outputs rather than being hidden inside the global prediction.

## Before a full production run

Edit:

- `config/project.yml` for CPU count, block sizes and thresholds;
- Slurm partition, memory and walltime;
- predictor prefixes only if you also update the scripts;
- the external input manifests.

The code was structured for transparent staged comparisons, not for a single opaque “best model” run.
