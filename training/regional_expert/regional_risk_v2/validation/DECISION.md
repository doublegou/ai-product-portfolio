# Regional Risk V2 decision

Run ID: `regional_risk_v2_20260817_r1`

## Status

`NO_CANDIDATE_MET_COMPLETE_REGIONAL_GATE`

Four prespecified candidates were evaluated under strict nested Leave-One-Branch-Out validation. Each outer threshold was selected only from its outer-training branches.

| Candidate | Background FPR | Recall | Precision | Positive branches | Extreme systems | Gate |
|---|---:|---:|---:|---:|---:|---|
| probability_rf__full50 | 6.0% | 45.5% | 48.2% | 6/14 | 2/4 | no |
| probability_rf__full50_process | 6.1% | 38.1% | 40.9% | 6/14 | 1/4 | no |
| shallow_boosting__full50 | 10.0% | 34.6% | 33.2% | 5/14 | 2/4 | no |
| shallow_boosting__full50_process | 9.9% | 31.6% | 30.0% | 4/14 | 2/4 | no |

## Interpretation

No frozen candidate met every Gate criterion. Ranking improvements alone do not qualify a Regional Risk Gate; stop further tuning within these algorithms and feature sets, preserve the experiment, and only then consider a separate failure audit.

No full-data release model was fitted. Ranking metrics are secondary diagnostics.

Ranking metric rows: 4
