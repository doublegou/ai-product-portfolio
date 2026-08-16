# Base Model V2

Base V2 is a method-level forward reconstruction of the historical Purged-Branch Base model. It keeps the frozen Full50 ordinary Random Forest and changes the primary generalization target from an unseen hydrological terminal component to an unseen station-supported tributary frontier with downstream-connected training rows purged.

## Frozen boundary

- Training table: `data/processed/training/sr_full50_v1.csv` (4,485 rows).
- Response: `sr87_sr86`.
- Predictors: the exact ordered Full50 manifest used by Base V0/V1.
- Learner: unweighted `ranger` regression RF; no high-Sr weighting, correction, classifier or tail-aware recipe.
- Methodology benchmark: 9 response-blind branch designs x 5 folds, each comparing Purged Branch, naive unpurged branch, and matched terminal validation with one frozen Base V1 RF recipe. It is diagnostic only and never selects V2 parameters.
- Primary: 3 repeats x 5 Purged-Branch Outer folds; 5 Purged-Branch Inner folds within every Outer analysis universe.
- Deployment: all 48 ordinary-RF recipes evaluated by one independent 5-fold Purged-Branch design.
- Stress: frozen deployment recipe on matched terminal, 500/1,000/1,500 km spatial and reference-group folds.
- Final: all 4,485 rows, 4,000 trees.

The historical branch implementation and the meanings of `3/10/40`, `4/20/80`, and `8/40/120` were not preserved. Those numbers are not reused. Current topology is reconstructed without reading Sr and is selected only by an automatic structural-anchor rule.

## Forward branch definition

HydroRIVERS `HYRIV_ID -> NEXT_DOWN` is the connectivity source of truth. For every retained reach, the algorithm counts how many of the current 4,485 station paths pass through it. Reaches at or above a scale-specific station-support threshold form a validation trunk. Every connected upstream frontier immediately before that trunk is an independent candidate branch, identified by its outlet reach. Stations already on the trunk are training support. Candidate frontiers below the minimum station support remain training support and are never merged across independent outlets.

HydroBASINS L6/L12 are retained only for structural auditing. They do not define branch membership, do not use Sr, and are not added to Full50.

Three topology-only scales are frozen:

| Scale | Station-trunk support | Minimum branch support |
|---|---:|---:|
| Small | 10 | 4 |
| Primary | 20 | 5 |
| Large | 40 | 9 |

The automatic Primary rule minimizes the summed relative distance to the preserved structural anchors of approximately 219 branches and 2,568 assessment-eligible rows. It never reads the response or model predictions. The frozen result is 221 Primary branches and 2,577 eligible rows, with a hard maximum of 19 stations in any branch. These anchors define scale, not exact historical membership.

The separate branch-geometry benchmark uses nine predeclared variants around these three scale families: Small minimum support 3/4/5, Primary 4/5/6, and Large 8/9/10. Every variant is constructed before model evaluation and uses the same frozen Base V1 recipe (`mtry=12`, `min.node.size=5`, `sample.fraction=1`, `replace=FALSE`). Thus, its comparisons isolate validation geometry rather than a new tuning result.

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
benchmark: 45 array tasks (9 designs x 5 folds; 3 fixed-recipe fits per task)
primary:   15 array tasks (3 repeats x 5 folds)
deployment: one 48-recipe selection task
stress:    25 array tasks (5 schemes x 5 folds)
finalize:  aggregate, fit the 4,000-tree final RF, and write release-ready run artifacts
```

Primary assessment is restricted to the frozen branch-eligible population. The remaining rows are training support, or are purged when downstream of the current assessment branches. The final RF still fits all 4,485 rows.

One complete formal run contains 5,216 RF fits: 135 benchmark fits plus the unchanged 5,081-fit Primary/deployment/stress/final pipeline. The benchmark does not alter the V2 final recipe or final-model fitting path.
