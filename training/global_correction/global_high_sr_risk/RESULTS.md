# Global High-Sr Risk V1 — Final Result

## Final status

**STOP — transferable signal insufficient.**

The frozen experiment completed successfully, but neither candidate model passed any of the three repeat-level feasibility gates. The 47 non-spatial predictors therefore do not support a sufficiently reliable, hydrologically transferable High-Sr classifier under this protocol.

This is a negative feasibility result, not a failed computation. The branch is closed without fitting a full-data classifier, selecting a deployment threshold, calibrating probabilities, creating a model bundle, or publishing a release.

## Formal result

| Model | Repeats passed | Mean Recall | Mean Precision | Mean background FPR | Mean PR-AUC | Mean positive systems detected | Mean extreme systems detected |
|---|---:|---:|---:|---:|---:|---:|---:|
| Elastic-net logistic regression | 0/3 | 0.0306 | 0.1276 | 0.0684 | 0.0264 | 1.67/12 | 0.00/4 |
| Probability Random Forest | 0/3 | 0.0459 | 0.2185 | 0.0071 | 0.0619 | 2.67/12 | 0.33/4 |

The frozen gate required, within the same repeat: Recall `>= 0.60`, Precision `>= 0.15`, background FPR `<= 0.05`, PR-AUC `>= 0.10`, at least `6/12` positive hydrological systems detected, and at least `2/4` extreme-Sr systems detected. A model required at least two passing repeats. Neither model had one passing repeat.

## Scientific interpretation

Probability RF contains a weak nonlinear ranking signal: its mean PR-AUC is above the positive prevalence of `109/4485 = 0.0243`, and it generally controls clear-background FPR. That signal is nevertheless far below the required operating standard. Recall remains below 6.5% in every repeat, no repeat detects more than 3 of 12 positive hydrological systems, and no repeat detects more than 1 of 4 extreme-Sr systems.

Elastic-net provides no stable low-complexity linear signal. Its mean PR-AUC is close to class prevalence, and its threshold behavior is unstable across repeats.

The correct conclusion is not that the 47 variables contain absolutely no High-Sr information. It is that any information present is too weak and too hydrologically concentrated to support reliable cross-system identification with these two model classes and this frozen dataset.

## Numerical note

Five `glmnet` convergence warnings occurred across Elastic-net tasks 1, 11, and 15. All tasks completed and all formal OOF completeness assertions passed. Under the one-run policy, the observed Elastic-net metrics are retained and their exact values should be interpreted with this numerical caveat rather than used for fine model comparison.

The Probability RF arm had no analogous convergence warning and independently failed all three repeats by wide margins on Recall, PR-AUC, positive-system coverage, and extreme-system coverage. The numerical note therefore does not supply affirmative feasibility evidence and does not justify proceeding to a production classifier.

## Decision boundary

This result authorizes only the following actions:

- preserve the OOF evidence, configuration, folds, logs, reports, and archive;
- cite this branch as a completed negative feasibility experiment;
- revisit High-Sr classification only as a new version based on materially new predictors, additional positive hydrological systems, or a newly specified scientific hypothesis.

It does **not** authorize post-hoc threshold relaxation, a wider search on the same evidence, full-data classifier fitting, probability calibration, deployment mapping, or replacement of Base V1.

## Provenance and completeness

- Run ID: `risk_v1_full_20260816_r1`
- Source Git commit: `4b7af1125a08c995f0a65feb78af824cc163a348`
- Slurm chain: `65488–65492`, all `COMPLETED / 0:0`
- Training tasks: `30/30` complete
- Formal OOF sets: `6/6`, each containing 4,485 rows
- Automated decision: `transferable_signal_insufficient_stop`
- Final model fitted: `false`
- Release created: `false`
- Archive: `global_high_sr_risk_risk_v1_full_20260816_r1.tar.gz`
- Archive size: `5,355,502` bytes
- SHA-256: `dc92a5accafc0988a8c317be10b87709987f2d042ce015891b379fbf899734f0`

The generated run reports and archive remain immutable execution evidence. This file is the durable scientific interpretation of that evidence.
