# Base Model V0 — corrected-data result

## Active result

- Decision: `PASS_REPLACE_RELEASE`
- Active run: `v0_full_20260817_corrected_r1_final`
- Canonical input normalized MD5: `dc80c73dfc64a3180efb4c5bb9fe5902`
- Primary validation: 1000-km spatial nested CV
- Primary RMSE: `0.0172037112`
- Primary MAE: `0.0055356961`
- Primary R²: `0.1453950977`
- Primary Bias: `-0.0010297257`
- Final RF: `mtry=7`, `min.node.size=5`, `sample.fraction=1`, `replace=FALSE`, 3,000 trees

The corrected run replaces `v0_full_20260816_r2`, whose model was fitted from the superseded Full50 table. Relative to that run, primary RMSE changes by `+0.10%` and MAE by `+0.60%`; all validation-scheme RMSE changes are below `0.56%`. The selected deployment recipe is unchanged, so the corrected data do not alter the V0 scientific interpretation.

All 20 validation tasks and the final fit completed successfully. The combined report contains 17,940 OOF predictions, and the Slurm/log integrity audit found no failed task or runtime warning/error.

Detailed comparison is stored with the run at `runs/v0_full_20260817_corrected_r1_final/reports/comparison_conclusion.md`. No independent historical V0 numerical output survives outside the previous formal run; historical agreement is therefore asserted only at the frozen-method level, not by inventing a third numerical baseline.
