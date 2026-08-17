# Global High-Sr Risk V1 — Corrected-data final result

## Final status

**STOP — transferable signal insufficient.**

Retraining acceptance: **ACCEPTED — the corrected-data result reproduces the previous/historical scientific conclusion and supersedes the prior execution evidence.**

The complete frozen experiment was rerun after correcting the canonical `sr_full50_v1.csv` predictors. Both candidate models again passed `0/3` repeat-level feasibility gates. The corrected 47 non-spatial predictors therefore still do not support a reliable, hydrologically transferable High-Sr classifier under this protocol.

This is a completed negative feasibility result, not a failed computation. No full-data classifier, deployment threshold, probability calibration, model bundle, or release was created.

## Corrected-data result

| Model | Repeats passed | Mean Recall | Mean Precision | Mean background FPR | Mean PR-AUC | Mean positive systems detected | Mean extreme systems detected |
|---|---:|---:|---:|---:|---:|---:|---:|
| Elastic-net logistic regression | 0/3 | 0.0214 | 0.1453 | 0.0411 | 0.0259 | 1.67/12 | 0.33/4 |
| Probability Random Forest | 0/3 | 0.0520 | 0.0874 | 0.0085 | 0.0644 | 2.33/12 | 0.33/4 |

The frozen gate required, within the same repeat: Recall `>= 0.60`, Precision `>= 0.15`, background FPR `<= 0.05`, PR-AUC `>= 0.10`, at least `6/12` positive hydrological systems detected, and at least `2/4` extreme-Sr systems detected. A model required at least two passing repeats. Neither model had one passing repeat.

## Corrected versus previous and historical formal result

The previous formal run (`risk_v1_full_20260816_r1`) is also the run recorded in `模型优化记录final.docx`; consequently it is both the immediately previous result and the authoritative historical comparison.

| Model / metric | Corrected data | Previous / historical | Absolute change |
|---|---:|---:|---:|
| Elastic-net Recall | 0.0214 | 0.0306 | -0.0092 |
| Elastic-net Precision | 0.1453 | 0.1276 | +0.0177 |
| Elastic-net background FPR | 0.0411 | 0.0684 | -0.0274 |
| Elastic-net PR-AUC | 0.0259 | 0.0264 | -0.0005 |
| Elastic-net positive systems | 1.67/12 | 1.67/12 | 0.00 |
| Elastic-net extreme systems | 0.33/4 | 0.00/4 | +0.33 |
| Probability RF Recall | 0.0520 | 0.0459 | +0.0061 |
| Probability RF Precision | 0.0874 | 0.2185 | -0.1311 |
| Probability RF background FPR | 0.0085 | 0.0071 | +0.0014 |
| Probability RF PR-AUC | 0.0644 | 0.0619 | +0.0024 |
| Probability RF positive systems | 2.33/12 | 2.67/12 | -0.33 |
| Probability RF extreme systems | 0.33/4 | 0.33/4 | 0.00 |

The correction changed some selected thresholds and therefore operating-point Precision/FPR. It did not change the feasibility conclusion: both models remain far below the required Recall, PR-AUC, positive-system coverage, and extreme-system coverage. Probability RF continues to show only a weak nonlinear ranking signal above the positive prevalence of `109/4485 = 0.0243`.

## Numerical note

Five `glmnet` warnings occurred in Elastic-net tasks 1, 7, and 11: only the final lambda value in the affected path failed to converge at `maxit = 100000`, and solutions for larger lambdas were returned. All 30 tasks completed, all six formal OOF sets contain 4,485 rows, and all integrity assertions passed. The independent Probability RF arm also failed all three repeats by wide margins, so these warnings cannot provide affirmative feasibility evidence.

## Decision boundary

This result authorizes preserving and citing the corrected-data OOF evidence. It does **not** authorize threshold relaxation, wider post-hoc search on the same evidence, full-data classifier fitting, probability calibration, deployment mapping, or replacement of a Base model. Reopening this branch would require materially new predictors, more positive hydrological systems, or a newly specified scientific hypothesis.

## Provenance and completeness

- Run ID: `risk_v1_full_20260817_corrected_r1_final`
- Source Git commit: `a4f5bb7ca931d48e5e212355c38f7d22186f125a`
- Slurm chain: `66517–66521`, all `COMPLETED / 0:0`
- Training tasks: `30/30` complete
- Formal OOF sets: `6/6`, each containing 4,485 rows
- Automated decision: `transferable_signal_insufficient_stop`
- Final model fitted: `false`
- Release created: `false`
- Archive: `global_high_sr_risk_risk_v1_full_20260817_corrected_r1_final.tar.gz`
- Archive size: `5,377,115` bytes
- SHA-256: `7dba5a17e102210b44b246e2f607edec42f55f1a897e150e84c6ae290a116702`

The immutable run directory and archive contain the complete execution evidence. This file is the durable scientific interpretation of that evidence.
