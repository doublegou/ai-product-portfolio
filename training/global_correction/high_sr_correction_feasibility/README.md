# High-Sr Correction Feasibility V1

**Completed: stable residual signal detected, but no correction was safe relative to Raw Base; branch stopped.** See [`RESULTS.md`](RESULTS.md) for the frozen scientific conclusion and provenance.

This is the forward reconstruction of the High-Sr second-layer feasibility experiment. It asks whether the frozen Base V1 prediction plus current Env47/Full50 covariates contain stable residual information on the intentionally privileged Oracle population `observed Sr >= 0.72`.

It is not a deployable gate or correction model. Observed Sr defines the Oracle training/evaluation population and is never a predictor. A successful experiment only makes a future, independent deployable study eligible; this project has no release model.

## Strict nested design

The exact Base V1 hydrological `3 repeats x grouped 5-fold Outer CV` is reused. Each of the 15 Outer tasks fits the frozen Base V1 deployment recipe without tuning:

- five single-exclusion Inner models provide standard Outer-train Base OOF predictions;
- ten canonical pair-exclusion models provide context-specific meta-features for strict correction hyperparameter selection;
- one complete Outer-train model predicts the untouched Outer test.

For correction assessment fold `E`, correction-training rows in fold `A` receive a Base prediction from a model trained on `B+C+D`, while assessment rows in `E` receive the single-exclusion prediction from `A+B+C+D`. Pair models are keyed by the unordered excluded-fold pair and fitted once. Nested meta-features are indexed by `(outer_task, correction_assessment_fold, row_id)` and must never be collapsed to one prediction per row.

After hyperparameters are selected, the final Outer correction model is fitted on the standard five-fold Base OOF predictions for the complete elevated Outer train. Nested pair artifacts are selection-only. The untouched Outer test uses the complete Outer-train Base prediction.

## Models and controls

Each Elastic Net and residual-RF task evaluates `BasePred`, `BasePred + Env47`, and `BasePred + Full50` in the same task context. Predicted residuals are converted before every selection/evaluation metric:

```text
correction = max(0, predicted_residual)
final_prediction = base_prediction + correction
```

There is no upper clipping: `87Sr/86Sr` is not a probability and the frozen observations extend above 1.

`glmnet` requires a design matrix with at least two columns. The scientific BasePred-only Elastic Net remains a one-predictor model: after training-only preprocessing, the implementation appends an identically zero `.glmnet_zero_dummy` column and passes that column through `exclude`, forcing its coefficient out of both the pilot and explicit lambda fits. The dummy is absent from predictor manifests, preprocessing summaries and active-coefficient counts. `check` verifies this matrix/exclusion contract without fitting a model.

The historical residual-signal criterion is preserved: candidate group-macro MAE must improve by at least 5% over the same-family BasePred-only model in at least two of three repeats, with positive mean improvement. A separate pre-frozen promotion guard requires the same candidate to be no worse than raw Base group-macro MAE in at least two repeats and to have positive mean raw-Base improvement. Station and tail metrics are diagnostic only.

## Engineering-only preparation

```powershell
& "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" training/global_correction/high_sr_correction_feasibility/scripts/run.R --stage prepare
& "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" training/global_correction/high_sr_correction_feasibility/scripts/run.R --stage check
```

These commands fit no models. Formal training is handed to `hpc/slurm/high_sr_correction_feasibility/run.sh`. There is intentionally no smoke mode.

## Final outcomes

The only experiment-level outcomes are `STOP` and `ELIGIBLE_FOR_FUTURE_DEPLOYABLE_STUDY`. Neither outcome replaces Base V1 or fits a full-data correction model.
