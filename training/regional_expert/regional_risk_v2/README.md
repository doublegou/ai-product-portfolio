# Regional Risk V2

This project tests whether stronger nonlinear learners and 14 prespecified process features can produce a transferable regional high-Sr Gate.

The experiment is a frozen 2 x 2 comparison: probability RF versus shallow boosting, each with Full50 versus Full50 + Process14. Evaluation uses 17 strict outer Leave-One-Branch-Out folds. Every outer threshold is selected only from exhaustive inner Leave-One-Branch-Out predictions under a weighted 10% background-FPR constraint.

The four candidates must be judged against the complete predefined Gate. Ranking metrics are diagnostic and cannot replace Gate qualification. This project does not fit a full-data release model and does not modify the data or method after seeing formal V2 results.

## Local engineering sequence

```text
Rscript training/regional_expert/regional_risk_v2/scripts/run.R --stage prepare --force
Rscript training/regional_expert/regional_risk_v2/scripts/run.R --stage check
```

Formal cluster work runs task IDs 1..68, then `aggregate` and `summarize`.
