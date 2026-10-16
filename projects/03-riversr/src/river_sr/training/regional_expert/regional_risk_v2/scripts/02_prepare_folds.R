stage_rrisk2_prepare_folds <- function(context, validated = rrisk2_validate_input(context), force = FALSE) {
  paths <- rrisk2_fold_paths(context)
  if (all(file.exists(paths)) && !force) {
    current <- tryCatch(rrisk2_assert_folds_current(context), error = function(e) NULL)
    if (!is.null(current)) { rrisk2_log("V2 prepared artifacts are current; skipped."); return(invisible(current)) }
    rrisk2_assert(FALSE, "Existing V2 artifacts are stale. Re-run --stage prepare --force before training.")
  }
  tasks <- rrisk2_task_manifest(context); outer <- rrisk2_outer_assignments(validated$branches); fits <- rrisk2_fit_plan(tasks)
  rrisk2_assert(nrow(tasks) == 68L && nrow(outer) == 6324L && sum(fits$total_fits) == 1156L, "Prepared counts are invalid.")
  rrisk2_write_csv(validated$branches, paths[["branches"]]); rrisk2_write_csv(outer, paths[["outer"]]); rrisk2_write_csv(tasks, paths[["tasks"]]); rrisk2_write_csv(fits, paths[["fits"]])
  manifest <- list(
    status = "FROZEN_REGIONAL_RISK_V2_METHOD", prepared_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    inputs = validated$signatures, config = rrisk2_text_signature(context$config_path), implementation = rrisk2_implementation_signature(context),
    audit = validated$audit, candidates = rrisk2_candidate_manifest(), validation = context$config$validation,
    model_recipes = list(probability_rf = context$config$probability_rf, shallow_boosting = context$config$shallow_boosting),
    threshold = context$config$threshold, evidence_targets = context$config$evidence_targets,
    formal_model_fitted = FALSE, outer_predictions_observed = FALSE, full_data_model_fitted = FALSE
  )
  rrisk2_write_json(manifest, paths[["manifest"]])
  rrisk2_log("Prepared 17 outer folds, 68 tasks and 1,156 expected fixed-recipe fits; no model fitted.")
  invisible(list(manifest = manifest, validated = validated, branches = validated$branches, outer = outer, tasks = tasks, fits = fits))
}
