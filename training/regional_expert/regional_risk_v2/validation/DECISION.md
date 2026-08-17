# Regional Risk V2 decision

Run ID: `regional_risk_v2_20260817_corrected_r3`

## Status

`NO_CANDIDATE_MET_COMPLETE_REGIONAL_GATE`

Four prespecified candidates were evaluated under strict nested Leave-One-Branch-Out validation. Each outer threshold was selected only from its outer-training branches.

| Candidate | Background FPR | Recall | Precision | Positive branches | Extreme systems | Gate |
|---|---:|---:|---:|---:|---:|---|
| probability_rf__full50 | 7.0% | 45.5% | 45.8% | 6/14 | 2/4 | no |
| probability_rf__full50_process | 7.1% | 38.1% | 40.8% | 6/14 | 1/4 | no |
| shallow_boosting__full50 | 8.0% | 34.6% | 34.0% | 5/14 | 2/4 | no |
| shallow_boosting__full50_process | 10.9% | 34.3% | 32.4% | 4/14 | 2/4 | no |

## Interpretation

No frozen candidate met every Gate criterion. Ranking improvements alone do not qualify a Regional Risk Gate; stop further tuning within these algorithms and feature sets, preserve the experiment, and only then consider a separate failure audit.

No full-data release model was fitted. Ranking metrics are secondary diagnostics.

Ranking metric rows: 4
