# Regional Risk V1 — Final Result

## Final status

**SIGNAL FEASIBILITY ONLY — a moderate nonlinear Himalaya risk signal transfers across held-out regional branches, but no deployable Regional Expert is authorized.**

Run acceptance: **ACCEPTED — the final result reproduces the previous/historical scientific conclusion and is adopted as the active execution evidence.**

The forward reconstruction completed successfully under the frozen 17-branch LOBO protocol. GAM recovered useful ranking structure, while both Elastic Net arms collapsed to intercept-only models in every Outer fold. The experiment therefore establishes regional signal feasibility and stops at the pre-specified V1 boundary.

No Gate threshold was selected, probabilities were not calibrated, no hard-routing rule was evaluated, no full-data expert was fitted, and no release was created.

## Formal result

| Model | Role | PR-AUC | ROC-AUC | Brier | Log loss |
|---|---|---:|---:|---:|---:|
| GAM Combined | Ranking candidate | 0.337956 | 0.711558 | 0.173871 | 0.530226 |
| GAM Environment-only | Probability candidate | 0.310356 | 0.704559 | **0.165685** | **0.494175** |
| GAM Spatial-only | Spatial diagnostic control | 0.276435 | 0.676584 | 0.173455 | 0.501907 |
| Elastic Net Environment | Linear complexity baseline | 0.125565 | 0.151541 | 0.175542 | 0.541568 |
| Elastic Net Combined | Linear complexity baseline | 0.125565 | 0.151541 | 0.175542 | 0.541568 |

All metrics are station-equal pooled estimates from one strict LOBO prediction per station and model. The 372-station domain contains 80 positives and 292 negatives.

## Final-run comparison

The final run preserves the previous and historical scientific pattern. Relative to the immediately preceding formal run, Combined GAM PR-AUC changed by `+0.000849`, ROC-AUC by `-0.001156`, Brier by `-0.000108`, and log loss by `+0.000044`. Environment-only GAM PR-AUC changed by `-0.000643`, ROC-AUC by `-0.001241`, Brier by `+0.000211`, and log loss by `+0.000816`. Spatial-only GAM and both intercept-only Elastic Net controls are numerically unchanged.

These changes are small, preserve every frozen candidate role, and do not alter the decision boundary. The final run is therefore adopted as the active evidence while retaining `SIGNAL_FEASIBILITY_ONLY`; it does not authorize a production model or release.

## Scientific interpretation

The three GAM arms reproduce the historical ordering and performance scale. Spatial-only GAM shows that location contains regional risk information. Environment-only GAM improves the point estimates for ranking and gives the best probability-quality metrics. Combined GAM gives the best PR-AUC and ROC-AUC point estimates, so it retains the frozen ranking-candidate role.

This is evidence for a real but moderate, nonlinear and regionally heterogeneous risk structure. It is not evidence that Combined GAM is definitively superior to Environment-only GAM. The branch bootstrap contrast for Combined minus Environment was:

| Metric | Point delta | 95% branch-bootstrap interval |
|---|---:|---:|
| PR-AUC | +0.027600 | [-0.046636, +0.107417] |
| ROC-AUC | +0.006999 | [-0.080034, +0.072794] |
| Brier | +0.008185 | [-0.017190, +0.034566] |
| Log loss | +0.036052 | [-0.042504, +0.128845] |

Every interval crosses zero. Spatial-versus-environment and spatial-versus-combined contrasts are likewise uncertain. The correct role labels therefore describe pre-specified point-estimate candidates, not statistically established model dominance or a proven incremental spatial contribution.

The signal is not driven by one branch alone. Across leave-one-branch sensitivity recomputations, Environment-only ROC-AUC ranges from approximately 0.671 to 0.731 and Combined ROC-AUC from approximately 0.656 to 0.743. Performance is nevertheless heterogeneous: on the 14 mixed branches, positive mean risk exceeds negative mean risk in 10/14 branches for Environment-only and Spatial-only GAM, and 9/14 for Combined GAM. This supports feasibility, not universal branch-level reliability.

## Linear baseline interpretation

Both Elastic Net arms selected zero non-intercept coefficients in 17/17 Outer folds. They therefore provide no within-branch discrimination and support the conclusion that the available risk structure is not captured by a stable low-complexity linear combination under the frozen `alpha = 0.5`, `lambda.1se` protocol.

Their pooled ROC-AUC below 0.5 must not be described as a learned inverse relationship. Each held-out branch receives a fold-specific intercept probability; differences among those intercepts can create anti-ranking when the 17 folds are pooled even though every individual fold is intercept-only.

## Numerical note

All 51 GAM fits converged and all formal predictions are finite and complete. The Slurm stdout/stderr audit contains no fatal error or warning line. The pre-specified branch-equalizing prior weights remain non-integer; this is part of the frozen weighting scheme and does not affect the completeness of the external OOF evaluation.

The underlying non-integer-weight likelihood caveat means fitted-likelihood quantities such as AIC should be interpreted cautiously. The reported PR-AUC, ROC-AUC, Brier and log loss are external station-equal OOF metrics computed from predictions and remain the formal evaluation quantities. The family and weights are not changed after seeing the results merely to alter this caveat.

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

- Run ID: `regional_risk_v1_20260817_corrected_r1_final`
- Source Git commit: `63581e2a4a5ce9f28130892d738caf021456a2a8`
- Formal tasks: GAM `51/51`; Elastic Net `34/34`; total `85/85`
- Validation: 17 exhaustive response-blind regional branches; strict LOBO
- Formal OOF: 1,860 rows; 372 rows for each of five model arms; no missing or invalid probabilities
- Automated status: `SIGNAL_FEASIBILITY_ONLY`
- Final model fitted: `false`
- Gate selected: `false`
- Probability calibrated: `false`
- Release created: `false`
- Data MD5: `6fe0d27c33b47956f21d0e8d6e832ec5`
- Config MD5: `1adef9744fb7d1b75b7d4f5dd2d7f81e`
- Fold manifest MD5: `ecb0a305e86513dcaaf7b0cc1673ba1b`
- Archive: `regional_risk_v1_regional_risk_v1_20260817_corrected_r1_final.tar.gz`
- Archive size: `778,372` bytes
- Archive SHA-256: `a8a7785166ba5fa8d77b653fb2f3eec5e0084fa4724208c03d4218bb61e62ad6`

The final run used the frozen manifests and did not reuse previous validation output. The generated reports and verified archive remain immutable execution evidence; this file is the durable scientific interpretation of that evidence.
