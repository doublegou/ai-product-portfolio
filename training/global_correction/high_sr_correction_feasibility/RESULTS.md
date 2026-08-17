# High-Sr Correction Feasibility V1 — Corrected-data final result

## Final status

**STOP — stable residual signal exists, but no candidate safely improves on Raw Base.**

Retraining acceptance: **ACCEPTED — the corrected-data result reproduces the previous/historical scientific conclusion and supersedes the prior execution evidence.**

The complete strict-nested experiment was rerun from corrected canonical predictors and the corrected Base V1 release recipe. All four Env47/Full50 candidates again passed the residual-signal gate relative to their same-family BasePred-only correction, but none passed the separately frozen Raw-Base safety gate. The automated status remains `SIGNAL_ONLY_BUT_NOT_USEFUL`.

This is a completed negative promotion result, not a failed computation. Base V1 remains unchanged. No full-data correction model, model bundle, or release was created.

## Corrected-data result

| Model | Features | Signal improvement | Signal repeats | Mean improvement vs Raw Base | Safety repeats | Promotion |
|---|---|---:|---:|---:|---:|---|
| Elastic Net | Env47 | 23.77% | 3/3 | -4.13% | 0/3 | Fail |
| Elastic Net | Full50 | 22.19% | 3/3 | -6.30% | 0/3 | Fail |
| Residual RF | Env47 | 20.50% | 3/3 | -2.68% | 1/3 | Fail |
| Residual RF | Full50 | 21.76% | 3/3 | -0.95% | 1/3 | Fail |

The residual-signal gate required at least 5% hydrological-group macro MAE improvement over the same-family BasePred-only correction in at least two of three repeats, with positive mean improvement. The promotion safety gate required the same candidate to be no worse than untouched Raw Base in at least two repeats and to have strictly positive mean Raw-Base improvement. Promotion required both gates for the same candidate.

Residual RF with Full50 remains the closest candidate. Its corrected-data Raw-Base improvements are `-0.62%`, `+4.09%`, and `-6.33%`. One favorable repeat and a negative mean do not meet the frozen safety requirement.

## Corrected versus previous and historical formal result

The previous completed run (`high_sr_corr_20260816_r2`) is also the result recorded in `模型优化记录final.docx`; it is therefore both the immediately previous and the authoritative historical formal comparison.

| Candidate | Corrected signal | Previous / historical signal | Corrected Raw-Base | Previous / historical Raw-Base | Corrected safety | Previous safety |
|---|---:|---:|---:|---:|---:|---:|
| Env47 Elastic Net | +23.77% | +21.17% | -4.13% | -4.15% | 0/3 | 0/3 |
| Full50 Elastic Net | +22.19% | +18.94% | -6.30% | -7.11% | 0/3 | 0/3 |
| Env47 Residual RF | +20.50% | +23.83% | -2.68% | -2.64% | 1/3 | 0/3 |
| Full50 Residual RF | +21.76% | +24.57% | -0.95% | -1.64% | 1/3 | 1/3 |

The corrected predictors change the magnitude and repeat pattern of individual improvements, but not the scientific endpoint. Every candidate still has negative mean hydrological-group macro improvement relative to Raw Base. The best mean result remains below zero and has only one non-worse repeat, far from the joint promotion gate.

## Scientific interpretation

Env47 and Full50 continue to contain reproducible information about the residual left by Base V1. That is a residual-signal control result, not a promotion result: BasePred-only correction is itself materially worse than leaving Base V1 untouched.

The correction models therefore answer two questions differently:

- residual structure is learnable beyond BasePred alone;
- the learned nonnegative correction is not hydrologically safe enough to improve Raw Base.

The second answer controls the decision. A correction that lowers station-weighted error but raises hydrological-group macro MAE cannot replace or augment Base V1 under this protocol.

## Tail diagnostics

Mean hydrological-group macro improvement relative to Raw Base across repeats was:

| Model | Features | Sr 0.72–0.75 | Sr 0.75–0.80 | Sr >= 0.80 |
|---|---|---:|---:|---:|
| Elastic Net | Env47 | -12.29% | +34.94% | +7.43% |
| Elastic Net | Full50 | -15.07% | +33.30% | +6.76% |
| Residual RF | Env47 | -10.49% | +35.41% | +11.89% |
| Residual RF | Full50 | -7.09% | +35.08% | +10.90% |

The candidates improve the `0.75–0.80` range and modestly reduce error at `Sr >= 0.80`, but the extreme tail remains severely underestimated. The safety failure remains concentrated in the near-high `0.72–0.75` range, which contains `562/671` Oracle rows and 85 hydrological groups.

Overall station MAE improves by approximately 18.9%–21.6% across the four candidates. Station and tail metrics were frozen as diagnostic only and cannot override the failed hydrological-group safety gate.

## Decision boundary

This result authorizes preserving and citing the corrected-data OOF evidence and retaining Base V1 unchanged. It does **not** authorize relaxing the group-macro safety gate, selecting by station MAE, further tuning on the same Outer OOF evidence, fitting a full-data correction model, or publishing a correction release. Reopening correction requires a materially new hypothesis, new predictors, more extreme-Sr hydrological systems, or a newly pre-specified correction mechanism.

## Provenance and completeness

- Run ID: `high_sr_corr_20260817_corrected_r1_final`
- Source Git commit: `c8c22ba9f27903e6d97fb31226912f8d2dc68ec1`
- Slurm chain: `66550–66555`, all `COMPLETED / 0:0`
- Base tasks: `15/15`, comprising 240 canonical strict-nested Base fits
- Correction tasks: Elastic Net `15/15`; residual RF `15/15`
- Formal evaluation: three repeated grouped five-fold Outer OOF evaluations; 4,485 rows and 671 Oracle elevated-Sr rows per feature/model repeat
- Automated status: `SIGNAL_ONLY_BUT_NOT_USEFUL`
- Automated outcome: `STOP`
- Final model fitted: `false`
- Base V1 replaced: `false`
- Release created: `false`
- Log audit: no warnings or fatal errors
- Archive: `high_sr_correction_feasibility_high_sr_corr_20260817_corrected_r1_final.tar.gz`
- Archive size: `33,920,089` bytes
- SHA-256: `8a4517aecdb8aef115e2824d2b5a872f138b15f61917b2dd33ed7c7a0d14da90`
- Frozen config MD5: `3bb1df5dc08742193c03d3789527b2b2`
- Implementation MD5: `25c7a205728e7bfa258c5b10fbb46ede`
- Fold manifest MD5: `d02024584a00033d83c629673750ce71`

The immutable run directory and verified archive contain the full evidence. This file is the durable scientific interpretation of the corrected-data experiment.
