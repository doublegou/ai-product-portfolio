# Base V3 result review — base_v3_full_20260817_r2

Status: engineering checks passed; scientific approval is intentionally manual.

## Frozen deployment recipes

| model | structure | weight | best iteration |
|---|---:|---:|---:|
| rf | rf_110 | W2 | — |
| xgb | xgb_1535 | W1 | 118 |

## Strict Primary pooled OOF

| model | RMSE | MAE | bias | prediction max | >=0.80 hits | >=0.80 systems |
|---|---:|---:|---:|---:|---:|---:|
| rf | 0.017235 | 0.006295 | -0.000566 | 0.8109 | 0 | 0 |
| xgb | 0.017723 | 0.006554 | -0.001061 | 0.8474 | 0 | 0 |

## Interpretation guardrail

Training metrics are not generalization evidence. Compare Primary OOF first, then use the four frozen-recipe stress schemes to characterize deployment risk.
