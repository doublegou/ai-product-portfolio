# Regional Risk V1 — Final Result

## Final status

**SIGNAL FEASIBILITY ONLY — a moderate nonlinear Himalaya risk signal transfers across held-out regional branches, but no deployable Regional Expert is authorized.**

The forward reconstruction completed successfully under the frozen 17-branch LOBO protocol. GAM recovered useful ranking structure, while both Elastic Net arms collapsed to intercept-only models in every Outer fold. The experiment therefore establishes regional signal feasibility and stops at the pre-specified V1 boundary.

No Gate threshold was selected, probabilities were not calibrated, no hard-routing rule was evaluated, no full-data expert was fitted, and no release was created.

## Formal result

| Model | Role | PR-AUC | ROC-AUC | Brier | Log loss |
|---|---|---:|---:|---:|---:|
| GAM Combined | Ranking candidate | 0.337107 | 0.712714 | 0.173978 | 0.530183 |
| GAM Environment-only | Probability candidate | 0.310999 | 0.705801 | **0.165474** | **0.493358** |
| GAM Spatial-only | Spatial diagnostic control | 0.276435 | 0.676584 | 0.173455 | 0.501907 |
| Elastic Net Environment | Linear complexity baseline | 0.125565 | 0.151541 | 0.175542 | 0.541568 |
| Elastic Net Combined | Linear complexity baseline | 0.125565 | 0.151541 | 0.175542 | 0.541568 |

All metrics are station-equal pooled estimates from one strict LOBO prediction per station and model. The 372-station domain contains 80 positives and 292 negatives.

## Scientific interpretation

The three GAM arms reproduce the historical ordering and performance scale. Spatial-only GAM shows that location contains regional risk information. Environment-only GAM improves the point estimates for ranking and gives the best probability-quality metrics. Combined GAM gives the best PR-AUC and ROC-AUC point estimates, so it retains the frozen ranking-candidate role.

This is evidence for a real but moderate, nonlinear and regionally heterogeneous risk structure. It is not evidence that Combined GAM is definitively superior to Environment-only GAM. The branch bootstrap contrast for Combined minus Environment was:

| Metric | Point delta | 95% branch-bootstrap interval |
|---|---:|---:|
| PR-AUC | +0.026108 | [-0.046231, +0.104457] |
| ROC-AUC | +0.006914 | [-0.080035, +0.071926] |
| Brier | +0.008504 | [-0.016816, +0.034793] |
| Log loss | +0.036824 | [-0.041662, +0.129592] |

Every interval crosses zero. Spatial-versus-environment and spatial-versus-combined contrasts are likewise uncertain. The correct role labels therefore describe pre-specified point-estimate candidates, not statistically established model dominance or a proven incremental spatial contribution.

The signal is not driven by one branch alone. Across leave-one-branch sensitivity recomputations, Environment-only ROC-AUC ranges from approximately 0.672 to 0.732 and Combined ROC-AUC from approximately 0.658 to 0.744. Performance is nevertheless heterogeneous: on the 14 mixed branches, positive mean risk exceeds negative mean risk in 10/14 branches for Environment-only and Spatial-only GAM, and 9/14 for Combined GAM. This supports feasibility, not universal branch-level reliability.

## Linear baseline interpretation

Both Elastic Net arms selected zero non-intercept coefficients in 17/17 Outer folds. They therefore provide no within-branch discrimination and support the conclusion that the available risk structure is not captured by a stable low-complexity linear combination under the frozen `alpha = 0.5`, `lambda.1se` protocol.

Their pooled ROC-AUC below 0.5 must not be described as a learned inverse relationship. Each held-out branch receives a fold-specific intercept probability; differences among those intercepts can create anti-ranking when the 17 folds are pooled even though every individual fold is intercept-only.

## Numerical note

All 51 GAM fits converged and all formal predictions are finite and complete. Each GAM fit emitted `non-integer #successes in a binomial glm!` because the pre-specified branch-equalizing prior weights are non-integer. This is an expected consequence of the frozen weighting scheme, not a missing-prediction or convergence failure.

The warning means fitted-likelihood quantities such as AIC should be interpreted cautiously. The reported PR-AUC, ROC-AUC, Brier and log loss are external station-equal OOF metrics computed from predictions and remain the formal evaluation quantities. The family and weights are not changed after seeing the results merely to suppress the warning.

## Reconstruction scope

This is a forward reconstruction, not a recovery of historical branch membership or a claim of digit-for-digit identity. Regional branches were reconstructed response-blind from the frozen topology, and the historical Elastic Net alpha was unavailable and therefore frozen prospectively at 0.5.

The three GAM results closely reproduce the historical scientific pattern: Combined is best for pooled ranking, Environment-only is best for probability quality, Spatial-only contains diagnostic signal, and simple linear structure fails. That agreement is the relevant reproduction endpoint.

## Decision boundary

This result authorizes only the following actions:

- preserve and cite the strict LOBO OOF evidence as proof of Regional Risk signal feasibility;
- retain Combined GAM as a future ranking candidate, Environment-only GAM as a future probability candidate, and Spatial-only GAM as a diagnostic control;
- consider Gate design, calibration or expert integration only as a separately frozen later version with untouched validation evidence.

It does **not** authorize choosing a threshold on these OOF results, calling the probabilities calibrated, fitting a full-data Regional Expert, using hard routing, replacing Base, or creating a release.

## Provenance and completeness

- Run ID: `regional_risk_v1_20260817_r2`
- Source Git commit: `f65a770cea0335381f905f0de05519aa0c313bc7`
- Formal tasks: GAM `51/51`; Elastic Net `34/34`; total `85/85`
- Validation: 17 exhaustive response-blind regional branches; strict LOBO
- Formal OOF: 1,860 rows; 372 rows for each of five model arms; no missing or invalid probabilities
- Automated status: `SIGNAL_FEASIBILITY_ONLY`
- Final model fitted: `false`
- Gate selected: `false`
- Probability calibrated: `false`
- Release created: `false`
- Data MD5: `6fc05f714eb2f6fdc402ef0717d5369a`
- Config MD5: `1adef9744fb7d1b75b7d4f5dd2d7f81e`
- Fold manifest MD5: `4c700d640fae72bf657552572d4bc1d2`
- Archive: `regional_risk_v1_regional_risk_v1_20260817_r2.tar.gz`
- Archive size: `859,751` bytes
- Archive SHA-256: `75a553a93b5d5c8bc1ce3112d08b08786e3ebbca6cbe010a68678c82f353b056`

The failed r1 execution produced no complete scientific result. Its Elastic Net partial outputs were not reused in r2. The generated r2 reports and verified archive remain immutable execution evidence; this file is the durable scientific interpretation of that evidence.
