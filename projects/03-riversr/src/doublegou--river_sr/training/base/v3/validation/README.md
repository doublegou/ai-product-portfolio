# Base V3 canonical validation summaries

Source run: `base_v3_full_20260817_r2`

This directory contains the compact, approved validation summaries copied from
the immutable formal run:

- `primary_pooled_metrics.csv`: strict Outer-OOF metrics over 16,800 pooled
  predictions (5,600 sites × three repeats);
- `primary_site_mean_metrics.csv`: the same Primary evidence after averaging
  each site's three predictions, preserving a 5,600-site denominator;
- `primary_repeat_metrics.csv`: one result per model and Outer repeat;
- `outer_selected_recipes.csv`: the independently selected recipe in each of
  the 30 model/task combinations;
- `stress_scheme_metrics.csv`: four fixed-recipe stress schemes per model;
- `integrity_checks.csv`: seven final engineering checks.

Primary OOF is the algorithm comparison evidence. Deployment tuning selects a
full-data recipe and is not an unbiased performance estimate. Training metrics
are fit-capacity diagnostics only.
