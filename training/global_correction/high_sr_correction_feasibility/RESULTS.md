# High-Sr Correction Feasibility V1 — Final Result

## Final status

**STOP — stable residual signal exists, but no candidate safely improves on Raw Base.**

The strict-nested forward reconstruction completed successfully. All four Env47/Full50 candidates passed the historical residual-signal gate relative to their same-family BasePred-only correction, but none passed the separately frozen Raw-Base safety gate. The experiment therefore terminates as `SIGNAL_ONLY_BUT_NOT_USEFUL`.

This is a completed negative promotion result, not a failed computation and not evidence that the predictors contain no residual information. Base V1 remains unchanged. No full-data correction model was fitted, no model bundle was created, and no release was published.

## Formal result

| Model | Features | Signal improvement | Signal repeats | Mean improvement vs Raw Base | Safety repeats | Promotion |
|---|---|---:|---:|---:|---:|---|
| Elastic Net | Env47 | 21.17% | 3/3 | -4.15% | 0/3 | Fail |
| Elastic Net | Full50 | 18.94% | 3/3 | -7.11% | 0/3 | Fail |
| Residual RF | Env47 | 23.83% | 3/3 | -2.64% | 0/3 | Fail |
| Residual RF | Full50 | 24.57% | 3/3 | -1.64% | 1/3 | Fail |

The historical signal gate required at least 5% hydrological-group macro MAE improvement over the same-family BasePred-only correction in at least two of three repeats, with positive mean improvement. The promotion safety gate required the same candidate to be no worse than untouched Raw Base in at least two repeats and to have strictly positive mean Raw-Base improvement. Promotion required both gates for the same candidate.

Residual RF with Full50 was the closest candidate, but its Raw-Base improvements were `+0.78%`, `-0.32%`, and `-5.38%` across the three repeats. One favorable repeat and a negative mean do not meet the frozen safety requirement.

## Scientific interpretation

Env47 and Full50 contain reproducible information about the residual left by Base V1. This is demonstrated by the 19%–25% improvement over BasePred-only correction across all three repeats and both model families. That comparison is a residual-signal control, not the promotion baseline: BasePred-only correction itself is materially worse than leaving Base V1 untouched.

The correction models therefore answer two distinct questions differently:

- residual structure is learnable beyond BasePred alone;
- the learned nonnegative correction is not hydrologically safe enough to improve Raw Base.

The second answer controls the experiment-level decision. A model that explains residual variation but raises hydrological-group macro MAE cannot replace or augment Base V1 under this protocol.

## Tail diagnostics

Mean hydrological-group macro improvement relative to Raw Base across repeats was:

| Model | Features | Sr 0.72–0.75 | Sr 0.75–0.80 | Sr >= 0.80 |
|---|---|---:|---:|---:|
| Elastic Net | Env47 | -11.52% | +33.53% | +7.52% |
| Elastic Net | Full50 | -15.74% | +33.62% | +7.08% |
| Residual RF | Env47 | -8.62% | +32.43% | +9.58% |
| Residual RF | Full50 | -7.32% | +33.65% | +9.42% |

The candidates improve the `0.75–0.80` range and modestly reduce error at `Sr >= 0.80`, but the extreme tail remains severely underestimated. Across candidates, the mean correction in the extreme tail is only about `0.010–0.014`, compared with a Raw-Base mean bias of approximately `-0.204`.

The safety failure is concentrated in the near-high `0.72–0.75` range, which contains `562/671` Oracle rows and 85 hydrological groups. In this range the candidates improve station-weighted MAE by roughly 25% while worsening group-macro MAE by about 7%–16%. These statements are compatible: station MAE weights rows equally, whereas group-macro MAE gives each hydrological group equal weight. The correction helps many rows but imposes larger losses on enough hydrological groups to fail the frozen primary metric.

Overall station MAE also improves by approximately 19.5%–21.8% across the four candidates. Station and tail metrics were explicitly frozen as diagnostic only, so these improvements cannot override the failed hydrological-group safety gate.

## Reconstruction scope

This result is the forward reconstruction under the final strict-nested protocol, not a claim of numerical identity with the earlier historical experiment. In particular, its model-specific residual-signal magnitudes differ from the historical notes. The r2 values are retained as the result of the frozen implementation and are not reconciled post hoc by changing comparators, folds, thresholds, or tuning rules.

The scientific endpoint is nevertheless unambiguous under the protocol that was frozen before execution: no candidate is eligible for a future deployable correction study.

## Decision boundary

This result authorizes only the following actions:

- preserve the OOF evidence, frozen configuration and folds, logs, reports, and verified archive;
- cite the branch as evidence that residual signal exists but is not safely actionable with the evaluated correction design;
- retain Base V1 without modification;
- revisit correction only as a new version with a materially new hypothesis, additional extreme-Sr hydrological systems, new predictors, or a newly pre-specified correction mechanism.

It does **not** authorize post-hoc relaxation of the group-macro safety gate, selection by station MAE, further tuning on the same Outer OOF evidence, fitting a full-data correction model, or publishing a correction release.

## Provenance and completeness

- Run ID: `high_sr_corr_20260816_r2`
- Source Git commit: `8a39ef69d7d1ebd87815848e96fd513e21169a81`
- Slurm chain: `65723–65728`, all `COMPLETED / 0:0`
- Base tasks: `15/15`, comprising 240 canonical Base fits
- Correction tasks: Elastic Net `15/15`; residual RF `15/15`
- Formal evaluation: three repeated grouped five-fold Outer OOF evaluations; 4,485 rows and 671 Oracle elevated-Sr rows per feature/model repeat
- Automated status: `SIGNAL_ONLY_BUT_NOT_USEFUL`
- Automated outcome: `STOP`
- Final model fitted: `false`
- Base V1 replaced: `false`
- Release created: `false`
- Archive: `high_sr_correction_feasibility_high_sr_corr_20260816_r2.tar.gz`
- Archive size: `33,919,223` bytes
- SHA-256: `2672545ed73eca52cc0c2397690c4494ae14996d5e2e2fc31b2f3b3b13724c6e`
- Frozen config MD5: `3bb1df5dc08742193c03d3789527b2b2`
- Implementation MD5: `25c7a205728e7bfa258c5b10fbb46ede`
- Fold manifest MD5: `506f047e43f44bad17e4ac9d582a2577`

The failed r1 execution produced no scientific result. Its remote task outputs were deleted before r2 submission and were not reused. The generated r2 reports and verified archive remain immutable execution evidence; this file is the durable scientific interpretation of that evidence.
