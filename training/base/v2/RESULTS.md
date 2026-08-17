# Base V2 — Corrected-data final result

## Final status

**ACCEPTED — release replaced from corrected-data run.**

Base V2 was rerun end to end from the corrected canonical Full50 table. The complete methodology benchmark, repeated nested Primary CV, deployment selection, five stress schemes, and full-data final RF all completed successfully. The branch-geometry conclusion, final RF recipe, and overall performance scale remain stable, so the previous r2 release has been replaced by `base_v2_full_20260817_corrected_r1_final`.

Base V2 remains an ordinary unweighted Full50 RF for new-branch generalization. It is not a high-Sr correction model, and the corrected run continues to show severe extreme-Sr compression.

## Frozen geometry and completeness

- Topology: 221 response-blind Primary branches and 2,577 branch-eligible stations.
- All reconstructed topology and fold CSV hashes are identical to r2; only corrected input/release provenance changed.
- Benchmark: 9 designs × 5 folds × 3 fixed-recipe arms = 135 fits.
- Primary: 3 repeats × 5 Outer tasks with 5 nested Purged-Branch Inner folds.
- Full workflow: 5,081 RF fits.
- Slurm: 88/88 jobs completed with exit code `0:0`; no warnings or fatal errors.

## Corrected Primary result

| Metric | Corrected run | Previous / historical r2 | Change |
|---|---:|---:|---:|
| Station-mean OOF RMSE | 0.0133358 | 0.0132624 | +0.55% |
| Station-mean OOF MAE | 0.00458687 | 0.00460586 | -0.41% |
| R² | 0.424667 | 0.430985 | -0.00632 |
| Bias | +0.0003784 | +0.0004006 | -0.0000222 |
| Branch-macro RMSE | 0.00552446 | 0.00552571 | -0.02% |
| Calibration slope | 1.00537 | 0.99502 | +0.01035 |
| Predicted maximum | 0.825436 | 0.840930 | -0.01549 |

The previous r2 result is also the formal historical result recorded in `模型优化记录final.docx`. Overall and branch-macro changes are small and mixed in direction rather than evidence of a new scientific regime.

## Methodology benchmark

Purged Branch remains better than Matched Terminal in all nine designs for all four frozen benchmark criteria:

- pooled RMSE: 9/9;
- pooled MAE: 9/9;
- absolute Bias at `Sr >= 0.75`: 9/9;
- branch-macro RMSE: 9/9.

Purged Branch still does not consistently outperform Naive Branch: RMSE 4/9, MAE 3/9, high-Sr absolute Bias 2/9, and branch-macro RMSE 3/9. For frozen `primary_s05`, the purge costs approximately 2.47% RMSE, 5.79% MAE, and 2.67% branch-macro RMSE relative to naive, while slightly improving high-Sr absolute Bias. Downstream purge is retained for strict topology isolation, not because it guarantees better prediction.

## Tail result

| Sr range | Corrected RMSE | Previous / historical RMSE | Corrected Bias | Previous Bias |
|---|---:|---:|---:|---:|
| `< 0.72` | 0.0047845 | 0.0048109 | +0.001877 | +0.001878 |
| `0.72–0.75` | 0.0143633 | 0.0146511 | -0.002652 | -0.002670 |
| `0.75–0.80` | 0.0238059 | 0.0237212 | -0.013227 | -0.012949 |
| `>= 0.80` | 0.175981 | 0.173715 | -0.152258 | -0.147928 |

At the `0.75` threshold, same-threshold recall changed from `42/71 = 59.15%` to `40/71 = 56.34%`. At `0.80`, it changed from `2/10 = 20%` to `1/10 = 10%`. This is not a promotion blocker for an ordinary Base RF, but it is explicit evidence that Base V2 does not solve high-Sr identification or tail compression.

## Stress comparison

| Validation scheme | Corrected RMSE | Previous / historical RMSE | Relative change |
|---|---:|---:|---:|
| Terminal component | 0.0180257 | 0.0180705 | -0.25% |
| Spatial 500 km | 0.0152590 | 0.0152578 | +0.01% |
| Spatial 1,000 km | 0.0173640 | 0.0173225 | +0.24% |
| Spatial 1,500 km | 0.0158323 | 0.0158116 | +0.13% |
| Reference grouped | 0.0166613 | 0.0166464 | +0.09% |

Stress behavior is effectively unchanged. Primary metrics apply only to the 2,577 branch-eligible population, while stress metrics cover all 4,485 stations; these are different validation populations and are not direct model rankings.

## Final model and release

- Recipe: `mtry=7`, `min.node.size=5`, `sample.fraction=1.0`, `replace=FALSE`.
- Recipe fingerprint: `efc54e8a75add55765290ade759d113a`, unchanged from r2.
- Final fit: 4,485 rows, 50 predictors, 4,000 trees.
- Release source: `base_v2_full_20260817_corrected_r1_final`.
- Release model SHA-256: `2a9efcf21e80a375fa56e4380400fa26397e3ff0672bf837e81c84d2aee80c62`.

## Provenance

- Training source commit: `b5b6001fd8f961ebbb77bbe599f172b5cf899161`.
- Slurm chain: `66598–66603`.
- Archive: `base_v2_base_v2_full_20260817_corrected_r1_final.tar.gz`.
- Archive size: `138,258,652` bytes.
- Archive SHA-256: `64ab1494f24b9a4fd3cd4145a94609944b1986639c94c98c34bb5696962954e1`.

The immutable run and verified archive contain complete execution evidence. The frozen release is the corrected-data deployable Base V2 snapshot.
