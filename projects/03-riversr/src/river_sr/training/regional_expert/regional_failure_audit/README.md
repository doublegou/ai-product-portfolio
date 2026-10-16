# Regional Failure Audit

This is a standalone read-only diagnostic project under `training/regional_expert/`. It begins only after the four Regional Risk V2 candidates and their Outer OOF predictions have been frozen.

The audit answers one question: did the shared Gate failure arise mainly from a poor decision boundary, or does the frozen 64-dimensional representation fail to distinguish the completely missed high-Sr systems?

It performs exactly three analyses:

1. Full64 background-overlap and univariate-separation audit.
2. Cross-branch nearest-neighbor audit.
3. Process14-specific failure-case audit.

No learner, threshold, Gate, feature or response definition is fitted or modified. The failure set is defined from the closest frozen V2 candidate, `probability_rf__full50`: a positive branch is completely missed when none of its `Sr >= 0.75` stations is triggered in strict Outer OOF.

The corrected forward V2 run (`regional_risk_v2_20260817_corrected_r3_final`) contains 8 completely missed branches and 28 high-Sr sites. These counts are derived directly from the frozen strict Outer OOF predictions.

```text
Rscript training/regional_expert/regional_failure_audit/scripts/run.R --stage validate
Rscript training/regional_expert/regional_failure_audit/scripts/run.R --stage audit
Rscript training/regional_expert/regional_failure_audit/scripts/run.R --stage summarize
```
