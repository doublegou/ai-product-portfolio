# Base Model V1 — corrected-data result

## Active result

- Decision: `PASS_REPLACE_RELEASE`
- Active run: `v1_full_20260817_corrected_r1_final`
- Canonical input normalized MD5: `dc80c73dfc64a3180efb4c5bb9fe5902`
- Primary station-mean hydrological OOF RMSE: `0.0180022858`
- Primary MAE: `0.0060135276`
- Primary R²: `0.0642143133`
- Primary Bias: `-0.0013348328`
- Final recipe: `mtry=12`, `min.node.size=5`, `sample.fraction=1`, `replace=FALSE`, 4,000 trees

Relative to the superseded-data run, primary RMSE improves by `0.40%`, MAE improves by `1.18%`, and the final recipe is unchanged. Stress-scheme RMSE shifts are all below `0.42%`.

The corrected run also reproduces the preserved historical boundary: background-Sr RMSE remains `0.00434`, while `Sr>=0.80` RMSE remains about `0.227`. Base V1 therefore continues to provide a valid ordinary Full50 RF baseline, but it does not solve terminal-system high-Sr transfer or extreme-tail compression.

All 15 Primary, 20 stress, deployment and final-fit tasks completed successfully. Detailed comparison is stored in `runs/v1_full_20260817_corrected_r1_final/reports/comparison_conclusion.md`.
