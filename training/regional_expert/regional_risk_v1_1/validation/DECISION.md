# Regional Risk V1.1 decision

Run ID: `regional_risk_v1_1_20260817_corrected_r1`

## Status

`RANKING_SIGNAL_NOT_OPERATIONAL_GATE`

V1.1 is independent of Regional Risk V2. It evaluates only the two frozen V1 GAM candidates under strict Nested LOBO, inner-only Platt calibration and inner-only threshold selection.

## Primary Gate

| Model | Background FPR | Recall | Precision | Positive branches | Extreme branches | Pass |
|---|---:|---:|---:|---:|---:|---|
| gam_environment | 10.7% | 40.5% | 36.0% | 7/14 | 1/4 | no |
| gam_combined | 6.9% | 44.1% | 31.4% | 6/14 | 1/4 | no |

## Interpretation boundary

Neither frozen GAM met all independent V1.1 Primary Gate targets. Stop tuning the GAM specification, calibrator and threshold rule; preserve V1 and V1.1 unchanged.

The 5% Strict Gate is diagnostic only. Regional Risk V2 criteria, algorithms and features are not used in this decision.

## Provenance

- Probability metric rows: 4
- Final model fitted: false
- Release created: false
