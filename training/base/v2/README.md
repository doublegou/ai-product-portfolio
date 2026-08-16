# Base Model V2

Base V2 is a method-level forward reconstruction of the historical Purged-Branch Base model. It keeps the frozen Full50 ordinary Random Forest and changes the primary generalization target from an unseen terminal system to an unseen hydrological branch with downstream-connected training rows purged.

## Frozen boundary

- Training table: `data/processed/training/sr_full50_v1.csv` (4,485 rows).
- Response: `sr87_sr86`.
- Predictors: the exact ordered Full50 manifest used by Base V0/V1.
- Learner: unweighted `ranger` regression RF; no high-Sr weighting, correction, classifier or tail-aware recipe.
- Primary: 3 repeats x 5 Purged-Branch Outer folds; 5 Purged-Branch Inner folds within every Outer analysis universe.
- Deployment: all 48 ordinary-RF recipes evaluated by one independent 5-fold Purged-Branch design.
- Stress: frozen deployment recipe on matched terminal, 500/1,000/1,500 km spatial and reference-group folds.
- Final: all 4,485 rows, 4,000 trees.

The historical branch implementation and the meanings of `3/10/40`, `4/20/80`, and `8/40/120` were not preserved. Those numbers are not reused. Current topology is reconstructed without reading Sr and is selected only by an automatic structural-anchor rule.

## Forward branch definition

HydroRIVERS `HYRIV_ID -> NEXT_DOWN` is the connectivity source of truth. `ORD_CLAS = 1` reaches form the connected-basin backbone. A station outside that backbone is traced downstream to its first backbone reach. Nearby tributary outlets are grouped by connected basin plus a prefix of the entry reach's HydroBASINS L12 Pfafstetter code.

Three topology-only scales are frozen:

| Scale | Entry Pfaf prefix | Minimum station support |
|---|---:|---:|
| Small | 7 digits | 2 |
| Primary | 6 digits | 3 |
| Large | 5 digits | 4 |

The automatic Primary rule minimizes the summed relative distance to the preserved structural anchors of approximately 219 branches and 2,568 assessment-eligible rows. It never reads the response or model predictions. These anchors define scale, not exact historical membership.

## Local preparation

HydroBASINS L12 is registered under `data_pipeline/raw_features/config/sources.yml`. Raw acquisition is separate from this project. V2 preparation processes only the current 4,485 Full50 stations and their downstream reach closure; it does not build global prediction data.

```powershell
Rscript training/base/v2/scripts/run.R --stage prepare
Rscript training/base/v2/scripts/run.R --stage check
```

`prepare` writes rebuildable checkpoints to `data/interim/` and freezes portable assignments under `training/base/v2/folds/`. Normal training never reruns preparation. Once folds are frozen, the compute cluster needs no GIS files.

Formal training is intentionally not started by preparation or checking.

## HPC stages

```text
primary:   15 array tasks (3 repeats x 5 folds)
deployment: one 48-recipe selection task
stress:    25 array tasks (5 schemes x 5 folds)
finalize:  aggregate, fit the 4,000-tree final RF, and write release-ready run artifacts
```

Primary assessment is restricted to the frozen branch-eligible population. The remaining rows are training support, or are purged when downstream of the current assessment branches. The final RF still fits all 4,485 rows.
