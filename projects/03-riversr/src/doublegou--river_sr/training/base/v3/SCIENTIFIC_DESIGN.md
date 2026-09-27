# Base V3 scientific design

## Objective

Base V3 tests whether a larger, globally distributed river-observation dataset
and the Full50 predictor set can support transferable continuous Sr prediction,
with particular attention to independent high-Sr hydrological systems.

## Training population

- 5,600 sites: 4,485 baseline sites and 1,115 newly added sites.
- 50 frozen predictors.
- Sr bands: 4,756 `<0.72`, 708 `0.72–0.75`, 107 `0.75–0.80`, and 29
  `>=0.80` sites.
- Hydrological systems are defined by HydroBASINS level-6 `MAIN_BAS` and frozen
  before model fitting.

## Weight competition

W0 is unweighted. W1 moderately emphasizes the upper tail. W2 strongly
emphasizes it. Weight scheme is selected together with structural parameters
inside Inner CV; all assessment metrics remain unweighted.

## Primary validation

- Three repeats of five hydrological-system-isolated Outer folds: 15 tasks.
- Five hydrological-system-isolated Inner folds within each Outer training set.
- Inner pooled OOF predictions select parameters and weight scheme.
- Locked Outer tests are used once, after selection.
- Each site receives three strict Outer-OOF predictions.

## Model competition

- Random Forest: 378 structures, 48 coarse structures per Outer task, followed
  by 16 refinement structures.
- XGBoost: 1,728 structures and the same 48-to-16 search budget, with Inner-fold
  early stopping.
- Every structure is evaluated with W0, W1 and W2.
- Global RMSE is primary; candidates in the accuracy shortlist are separated by
  upper-tail system/site detection, false-high control, bias and MAE.

## Deployment and stress validation

Primary results select the algorithm. A separate grouped tuning pass freezes one
deployment recipe per model without being reported as generalization evidence.
Each frozen recipe is then tested in five folds under four stress schemes:

- 500 km spatial blocks;
- 1,000 km spatial blocks;
- 1,500 km spatial blocks;
- reference groups.

Stress results characterize deployment risk and cannot trigger retuning.

## Final models

After Primary and stress validation, both model families receive full-data fits
for fit-capacity diagnostics. The selected deployment model is approved only
after strict OOF and stress results have been reviewed.
