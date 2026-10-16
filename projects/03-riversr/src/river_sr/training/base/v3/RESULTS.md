# Base V3 — Final Result

## Final status

**ACCEPTED — Random Forest adopted and release frozen for global continuous Sr regression.**

Source run: `base_v3_full_20260817_r2`

Training commit: `c4d5744`

Decision: `ACCEPT_RF_WITH_HIGH_SR_LIMITATION`

The complete 5,600-site RF versus XGBoost experiment finished under the frozen
hydrological-system-isolated protocol. Random Forest is the better of the two
global continuous-regression models and is released as the Base V3 model. It is
not approved as a high-Sr detector: both algorithms missed every independent
`Sr >= 0.80` site and hydrological system in strict Primary validation.

## Execution and integrity

- All 76 Slurm job units completed with exit code `0:0`.
- Primary used up to 480 requested CPUs; Stress used up to 640 requested CPUs.
- No fatal error or out-of-memory event occurred.
- All 7 result-integrity checks passed.
- The abandoned `base_v3_full_20260817_r1` run contributed no artifact or
  checkpoint to the accepted run.

## Model competition

Strict pooled Outer-OOF contains three predictions for each of 5,600 sites.

| Model | RMSE | MAE | Bias | R2 | Calibration slope | Prediction max |
|---|---:|---:|---:|---:|---:|---:|
| RF | 0.017235 | 0.006295 | -0.000566 | 0.0800 | 0.8545 | 0.8109 |
| XGBoost | 0.017723 | 0.006554 | -0.001061 | 0.0271 | 0.6062 | 0.8474 |

RF has 2.76% lower pooled RMSE and 3.95% lower pooled MAE. It wins all three
Outer repeats and 13 of the 15 paired Outer tasks, so the algorithm decision is
not driven by one split.

For the station-level summary below, each site's three strict OOF predictions
are averaged before scoring. This preserves the frozen 5,600-site denominator.

| Model | RMSE | MAE | Low-Sr RMSE | False high among 4,756 low sites | `0.72–0.75` hits | `0.75–0.80` hits | `>=0.80` hits |
|---|---:|---:|---:|---:|---:|---:|---:|
| RF | 0.017197 | 0.006263 | 0.005554 | 2 | 317/708 | 4/107 | 0/29 |
| XGBoost | 0.017430 | 0.006370 | 0.005573 | 5 | 218/708 | 3/107 | 0/29 |

## Upper-tail result

The upper-tail limitation is decisive:

- RF detects 2/13 systems containing `Sr >= 0.75`; XGBoost also detects 2/13.
- Both models detect 0/5 systems containing `Sr >= 0.80`.
- RF high-Sr median bias is -0.04575 and its median prediction for observed
  `Sr >= 0.80` sites is 0.72260.
- XGBoost high-Sr median bias is -0.04679 and its corresponding median
  prediction is 0.72114.
- RF produces an OOF prediction above 0.80, but it belongs to a site observed at
  0.7543. XGBoost's five pooled predictions above 0.80 also belong to sites
  observed between 0.7178 and 0.7543.

The models therefore have sufficient output range but do not transfer the
upper-tail signal to independent hydrological systems.

## Frozen recipes and fit-capacity check

| Model | Structure | Weight | Final fit |
|---|---|---|---|
| RF | `rf_110`: mtry 12, min node 1, no replacement, fraction 0.8 | W2 | 4,000 trees |
| XGBoost | `xgb_1535`: depth 8, eta 0.05, child weight 5, full row/column sampling, lambda 1, alpha 0.1, gamma 0 | W1 | 118 iterations |

W2 is selected in 10/15 RF Outer tasks, W1 in three and W0 in two. The final
RF W2 choice is consequently supported by repeated Primary evidence, although
it does not solve independent high-Sr transfer.

The full-data RF fits all 29 `Sr >= 0.80` training sites above the threshold;
XGBoost fits 28/29. Their strict OOF recall is nevertheless 0/29. Training
metrics are therefore retained only as evidence of fit capacity, not as a
generalization estimate.

## Frozen-recipe stress tests

| Scheme | RF RMSE | XGBoost RMSE | Better pooled result |
|---|---:|---:|---|
| Spatial 500 km | 0.015956 | 0.017881 | RF |
| Spatial 1,000 km | 0.016822 | 0.018169 | RF |
| Spatial 1,500 km | 0.017571 | 0.017850 | RF |
| Reference grouped | 0.016076 | 0.015564 | XGBoost |

Stress tests used the frozen deployment recipes without retuning. Reference
grouping addresses a different transfer axis and does not override the strict
hydrological-system-isolated Primary result.

## Release and provenance

- Released model: RF `rf_110 / W2`.
- Model bundle SHA-256:
  `3b39a68d4e5cebc7bc0c4282e268db5d33f7b31996ee9189b51a7fff645a8139`.
- The XGBoost comparison bundle remains in the immutable run archive and is not
  the deployed Base V3 model.
- Archive: `base_v3_base_v3_full_20260817_r2.tar.gz`.
- Archive SHA-256:
  `846bd9f334adbe86cfe500b06add19ee5689904ec3b4985be328902d0294c1ab`.

Base V3 is accepted as the final 5,600-site global continuous-regression model
competition. Its release scope explicitly excludes high-Sr system discovery,
classification and risk screening.
