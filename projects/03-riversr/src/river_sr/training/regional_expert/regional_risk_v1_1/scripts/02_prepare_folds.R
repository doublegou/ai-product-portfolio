stage_rrisk11_prepare_folds <- function(context, validated = rrisk11_validate_input(context), force = FALSE) {
  paths <- rrisk11_fold_paths(context)
  if (all(file.exists(paths)) && !force) {
    current <- tryCatch(rrisk11_assert_folds_current(context), error = function(error) NULL)
    if (!is.null(current)) {
      rrisk11_log("Regional Risk V1.1 prepare artifacts are current; skipped.")
      return(invisible(current))
    }
    rrisk11_assert(FALSE, "Existing V1.1 prepare artifacts are stale. Re-run --stage prepare --force locally.")
  }
  tasks <- rrisk11_task_manifest(context)
  outer <- rrisk11_outer_assignments(validated$branches)
  rrisk11_assert(nrow(tasks) == 34L && nrow(outer) == 6324L, "Prepared task or Outer assignment count is invalid.")
  rrisk11_write_csv(validated$branches, paths[["branches"]])
  rrisk11_write_csv(outer, paths[["outer"]])
  rrisk11_write_csv(tasks, paths[["tasks"]])
  manifest <- list(
    status = "FROZEN_REGIONAL_RISK_V1_1_METHOD", prepared_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    upstream = validated$signatures, config = rrisk11_text_signature(context$config_path),
    implementation = rrisk11_implementation_signature(context), audit = validated$audit,
    validation = list(
      design = context$config$validation$design, outer_folds = 17L, inner_folds_per_outer = 16L,
      models = 2L, tasks = 34L, expected_gam_fits = 578L, expected_calibrators = 34L,
      expected_thresholds = 68L, expected_outer_oof_rows = 744L
    ),
    calibration = context$config$calibration, threshold = context$config$threshold,
    evidence_targets = context$config$evidence_targets,
    v2_dependency = FALSE, formal_model_fitted = FALSE
  )
  rrisk11_write_json(manifest, paths[["manifest"]])
  rrisk11_log("Prepared 17 frozen Outer folds and 34 Outer-by-model tasks; no model fitted.")
  invisible(list(manifest = manifest, validated = validated, branches = validated$branches, outer = outer, tasks = tasks))
}
