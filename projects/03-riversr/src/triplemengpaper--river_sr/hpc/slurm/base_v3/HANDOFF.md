# Base V3 HPC handoff

| Stage | Jobs | Scientific role | Retuning allowed |
|---|---:|---|---|
| Check | 1 | Verify frozen data, config, pools and folds | No |
| RF Primary | 15 | 3x5 hydrological Nested CV, 48→16 search | Inner only |
| XGB Primary | 15 | Parallel 3x5 Nested CV with early stopping | Inner only |
| Aggregate | 1 | Build pooled strict OOF and choose algorithm | No structure tuning |
| Deployment | 2 | Freeze one RF and one XGB recipe from Primary-supported shortlist | Yes; labelled tuning only |
| Stress | 40 | 500/1000/1500 km and reference, five folds each | No |
| Finalize | 1 | Stress aggregation and two full-data sanity fits | No |
| Check results | 1 | Integrity checks and scientific review report | No |

Expected formal fit scale per Primary Outer task:

- Coarse: `48 structures x 3 weights x 5 Inner folds`.
- Refinement: `16 structures x 3 weights x 5 Inner folds`.
- One locked Outer refit.

Do not publish `release/` from the cluster automatically. Return the checked
archive; scientific review of strict OOF and stress results happens in Codex.
