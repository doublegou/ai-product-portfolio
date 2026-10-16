# Regional Failure Audit

## Status

`STRUCTURAL_INFORMATION_GAP_SUPPORTED`

This read-only audit begins from the frozen Regional Risk V2 Outer OOF result. It does not train a model, change a threshold or reopen Gate selection.

## Frozen failure set

The closest V2 candidate, `probability_rf__full50`, completely missed 8 positive branches containing 28 high-Sr sites. A branch is completely missed when none of its `Sr >= 0.75` sites is triggered in strict Outer OOF.

## 1. Full64 background-overlap audit

Across the missed high-Sr sites, the median fraction of 64 predictors falling inside the ordinary-background 5th-95th percentile interval was 95.3%.
Features meeting the prespecified strong univariate discrimination rule: 3/64.
Features simultaneously showing strong univariate discrimination and low background overlap: 0/64.

## 2. Cross-branch nearest-neighbor audit

Using robust-scaled Full64 Euclidean distance, excluding every query site's own branch, the high-Sr fraction among the 5 nearest neighbors was 6.4% (station-equal) and 7.5% (branch-sqrt edge-weighted).
The corresponding global high-Sr baselines were 21.5% and 21.1%.
The nearest neighborhoods of the missed high-Sr sites therefore do not show a stronger high-Sr composition than the domain baseline.

## 3. Process14 failure-case audit

Within Process14 alone, the median missed-site background-interval fraction was 100.0%; 0/14 features simultaneously met the strong-discrimination and low-overlap rules.
The Process14 cross-branch 5-neighbor high-Sr fractions were 20.0% (station-equal) and 19.5% (branch-sqrt edge-weighted).
Process14 is therefore a representative failure case: its process proxies are present, but the missed high-Sr systems remain embedded in background-like predictor neighborhoods.

## Conclusion

The shared failure of GAM, RF, and XGBoost is primarily an information problem rather than an algorithm-selection problem. The current 64-dimensional predictor space does not adequately encode the mechanisms responsible for a subset of high-Sr systems.

This result closes Regional Risk V2 and the current Regional Expert line of work. It does not justify another RF/XGBoost tuning cycle on the same 64 predictors. Any future restart must introduce genuinely new regional, branch, geological, watershed, hydrogeochemical, spatial-context or process-specific information, with the exact new inputs determined by a separate data audit.

Process14 has two distinct roles: here it is a failure diagnosis; in a future expert project it may serve as a prototype only if additional region/process-specific information is introduced. Re-fitting the same 64 variables within a region would not resolve the demonstrated representation gap.

## Provenance

- Source V2 data MD5: `889ab17f9cb72efd63580807f845d700`
- Source Outer OOF MD5: `f7261c6250c0615e4433c69059a6cbef`
- Source V2 run ID: `regional_risk_v2_20260817_corrected_r3_final`
- Primary candidate: `probability_rf__full50`
- Missed branches/sites: 8/28
- Model training performed: `false`
- Gate or threshold modified: `false`
- Full-data model fitted: `false`
- Release created: `false`
