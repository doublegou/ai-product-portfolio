# Base Model V1

Base V1 is the forward reconstruction of the original Random Forest Train V1 design. It keeps the frozen 4,485-row Full50 regression problem and upgrades Base V0 with hydrological-system grouped repeated nested validation, a two-stage RF search, independent deployment tuning, and fixed-recipe spatial/reference stress tests.

## Scope

- Response: `sr87_sr86`.
- Predictors: the frozen ordered Full50 manifest.
- Model: one unweighted `ranger` regression Random Forest.
- Primary validation: 355 `MAIN_BAS` hydrological systems, 3 repeats x 5 grouped Outer folds, with 5 grouped Inner folds inside every Outer training set.
- Search: 48 coarse recipes x 500 trees; the best 16 are re-evaluated x 1,000 trees; the winning Outer recipe is fitted with 2,000 trees.
- Deployment tuning: unique Primary Outer winners are compared with an independent fixed-seed 5-fold hydrological-group CV using 2,000 trees.
- Stress tests: the frozen deployment recipe is evaluated without retuning on 500/1,000/1,500 km and reference-group 5-fold designs, with 2,000 trees.
- Final model: the frozen deployment recipe is fitted once on all 4,485 rows with 4,000 trees.

It does not contain Branch-Purged CV, case weights, tail-aware selection, a classifier, residual correction, XGBoost, regional experts, or the later 5,600-row dataset.

## Historical basis

The scientific design follows the original Random Forest Train V1 record. Low-level search and deployment details that were not preserved are formally re-specified here. Historical metrics are comparison benchmarks, not numerical golden values.

## Directories

- `config/`: the frozen current V1 specification.
- `R/`: validation, fold, RF, metric and IO functions.
- `scripts/`: numbered stages and the single `run.R` entry.
- `folds/`: frozen hydrological mapping and all resampling assignments.
- `validation/primary/`: 15 reusable repeated nested-CV task outputs.
- `validation/stress/`: 20 fixed-recipe stress task outputs.
- `runs/<run_id>/`: deployment tuning, final model, reports and logs for one formal run.
- `release/`: the single manually approved V1 model snapshot.

## Prepare folds locally

The only stage requiring local HydroBASINS shapefiles is `prepare`. It maps the Full50 L6 basin IDs to `MAIN_BAS`, verifies exactly 355 complete hydrological systems, freezes the mapping under `folds/`, and builds all Primary, Inner, deployment and stress assignments.

```powershell
& "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" training/base/v1/scripts/run.R --stage prepare
```

After this, formal training consumes only the Full50 table plus the frozen V1 folds; raw GIS data is not required on the compute cluster.

## Formal execution

The HPC workflow calls the same entry for scoped Primary and stress tasks, deployment selection, and finalization. A local full sequential mode is available for reproducibility but is not used for the formal cluster run.
