# Global High-Sr Risk V1

**Completed: feasibility not supported; branch stopped.** See [`RESULTS.md`](RESULTS.md) for the frozen scientific conclusion and provenance.

This project asks one narrow question: after removing absolute spatial coordinates, do the frozen Base V1 predictors contain a transferable signal for identifying high-Sr hydrological systems?

It is a signal-feasibility experiment, not a deployable classifier. A failed experiment produces OOF evidence and a stop decision. A passed experiment opens a separate V1.1 calibration/deployment stage; this directory never fits a full-data production model and has no `release/`.

## Frozen scientific design

- Input: the frozen 4,485-row Base V1 table.
- Target: positive at `Sr >= 0.75`; `Sr < 0.72` is clear background; `0.72 <= Sr < 0.75` is a diagnostic gray zone; `Sr >= 0.80` is the extreme-Sr diagnostic.
- Predictors: ordered Full50 minus `p0__sp_x`, `p0__sp_y`, and `p0__sp_z` (47 predictors). Longitude and latitude are copied into OOF output for diagnostics only.
- Outer validation: the exact Base V1 hydrological `3 repeats x 5 folds` assignments.
- Inner validation: risk-specific 3-fold grouped assignments rebuilt inside each Outer training set. Positive hydrological systems are distributed first, then all remaining systems are balanced by row count.
- Models: unweighted Elastic-net logistic regression and unweighted `ranger` probability Random Forest.
- No case weighting, resampling, SMOTE, probability calibration, coordinate predictors, final model, or deployment threshold.

Each candidate first selects its own threshold from pooled Inner OOF predictions. A feasible threshold must satisfy background FPR `<= 5%` and Precision `>= 15%`; among feasible thresholds Recall is maximized. Candidate hyperparameters are then selected in a separate ranking layer, so raw thresholds from different probability models are never compared.

Formal metrics are computed once per model and repeat from the complete 4,485-row OOF prediction set. A repeat passes only when all six gates in `config/default.yml` pass. A model passes in at least two of three repeats; the experiment passes when either model passes.

## Layout

- `config/`: frozen design and ordered NonSpatial47 predictor manifest.
- `R/`: IO, validation, grouped folds, preprocessing, metrics, threshold selection, two models and decision logic.
- `scripts/`: preparation, one scoped training task, OOF aggregation and feasibility decision.
- `folds/`: portable risk-specific Inner folds plus references to the frozen Base V1 Outer assignments.
- `validation/<model>/repeat_XX/fold_XX/`: 30 reusable Nested-CV task outputs.
- `runs/<run_id>/reports/`: one aggregation/decision record. Runs contain no trained model.

## Local preparation (no model fitting)

```powershell
& "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" training/global_correction/global_high_sr_risk/scripts/run.R --stage prepare
& "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" training/global_correction/global_high_sr_risk/scripts/run.R --stage check
```

The committed `folds/` directory is then sufficient for cluster execution; the cluster must not rebuild folds. Formal training is handed to `hpc/slurm/global_high_sr_risk/run.sh`.
