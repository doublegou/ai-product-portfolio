stage_rrisk11_aggregate <- function(context, run_id) {
  frozen <- rrisk11_assert_folds_current(context)
  rrisk11_begin_run(context, run_id, commandArgs(trailingOnly = TRUE))
  options(river_sr.regional_risk_v1_1.log_file = rrisk11_run_dir(context, run_id, "logs", "run.log"))
  tasks <- frozen$tasks
  incomplete <- vapply(seq_len(nrow(tasks)), function(i) {
    !rrisk11_task_complete(rrisk11_task_dir(context, tasks$model_id[[i]], tasks$outer_fold[[i]]))
  }, logical(1L))
  rrisk11_assert(!any(incomplete), paste("Cannot aggregate; incomplete task IDs:", paste(tasks$task_id[incomplete], collapse = ", ")))

  prediction_records <- vector("list", nrow(tasks)); calibrator_records <- vector("list", nrow(tasks))
  threshold_records <- vector("list", nrow(tasks)); diagnostic_records <- vector("list", nrow(tasks))
  for (i in seq_len(nrow(tasks))) {
    task_dir <- rrisk11_task_dir(context, tasks$model_id[[i]], tasks$outer_fold[[i]])
    prediction_records[[i]] <- rrisk11_read_csv(file.path(task_dir, "outer_predictions.csv"))
    calibrator_records[[i]] <- rrisk11_read_csv(file.path(task_dir, "calibrator.csv"))
    threshold_records[[i]] <- rrisk11_read_csv(file.path(task_dir, "thresholds.csv"))
    diagnostic_records[[i]] <- rrisk11_read_csv(file.path(task_dir, "gam_diagnostics.csv"))
  }
  oof <- as.data.frame(data.table::rbindlist(prediction_records, use.names = TRUE, fill = TRUE))
  calibrators <- as.data.frame(data.table::rbindlist(calibrator_records, use.names = TRUE, fill = TRUE))
  selected_thresholds <- as.data.frame(data.table::rbindlist(threshold_records, use.names = TRUE, fill = TRUE))
  diagnostics <- as.data.frame(data.table::rbindlist(diagnostic_records, use.names = TRUE, fill = TRUE))
  expected_rows <- frozen$validated$data[[context$config$columns$row_id]]
  for (model in c("gam_environment", "gam_combined")) {
    current <- oof[oof$model_id == model, , drop = FALSE]
    rrisk11_assert(nrow(current) == 372L && !anyDuplicated(current$row_id) && setequal(current$row_id, expected_rows), paste("Incomplete Outer OOF coverage:", model))
  }
  rrisk11_assert(nrow(oof) == 744L, "Regional Risk V1.1 must aggregate 744 Outer OOF rows.")
  rrisk11_assert(nrow(calibrators) == 34L && all(calibrators$converged) && all(calibrators$positive_slope), "Expected 34 converged positive-slope Platt calibrators.")
  rrisk11_assert(nrow(selected_thresholds) == 68L, "Expected 68 selected thresholds.")
  rrisk11_assert(nrow(diagnostics) == 578L, "Expected 578 GAM diagnostics rows.")
  oof <- oof[order(match(oof$model_id, c("gam_environment", "gam_combined")), oof$outer_fold, oof$row_id), , drop = FALSE]

  probability_records <- list(); gate_records <- list(); branch_records <- list()
  probability_index <- gate_index <- branch_index <- 0L
  for (model in c("gam_environment", "gam_combined")) {
    current <- oof[oof$model_id == model, , drop = FALSE]
    for (probability_column in c("raw_probability", "calibrated_probability")) {
      probability_index <- probability_index + 1L
      probability_records[[probability_index]] <- cbind(
        data.frame(model_id = model, stringsAsFactors = FALSE),
        rrisk11_probability_metrics(current, probability_column, context)
      )
    }
    for (operating_point in c("primary", "strict")) {
      gate_index <- gate_index + 1L
      metrics <- rrisk11_gate_metrics(current, operating_point, context)
      if (operating_point == "primary") metrics <- rrisk11_apply_primary_targets(metrics, context)
      gate_records[[gate_index]] <- cbind(data.frame(model_id = model, stringsAsFactors = FALSE), metrics)
      branch_index <- branch_index + 1L
      branch_records[[branch_index]] <- cbind(
        data.frame(model_id = model, stringsAsFactors = FALSE), rrisk11_branch_metrics(current, operating_point, context)
      )
    }
  }
  probability_metrics <- as.data.frame(data.table::rbindlist(probability_records, use.names = TRUE, fill = TRUE))
  gate_metrics <- as.data.frame(data.table::rbindlist(gate_records, use.names = TRUE, fill = TRUE))
  branch_metrics <- as.data.frame(data.table::rbindlist(branch_records, use.names = TRUE, fill = TRUE))
  extreme_audit <- oof[oof$observed_sr >= as.numeric(context$config$domain$extreme_lower), c(
    "model_id", "outer_fold", "regional_branch_id", "row_id", "site_id", "observed_sr", "raw_probability",
    "calibrated_probability", "primary_threshold", "strict_threshold", "trigger_primary", "trigger_strict"
  ), drop = FALSE]

  validation_dir <- rrisk11_output_path(context, "validation_dir")
  outputs <- list(
    oof_predictions = oof, probability_metrics = probability_metrics, gate_metrics = gate_metrics,
    branch_metrics = branch_metrics, extreme_audit = extreme_audit, calibrators = calibrators,
    selected_thresholds = selected_thresholds, gam_diagnostics = diagnostics
  )
  for (name in names(outputs)) rrisk11_write_csv(outputs[[name]], file.path(validation_dir, paste0(name, ".csv")))
  manifest <- list(
    status = "complete", run_id = run_id, aggregated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    tasks = 34L, models = 2L, outer_folds = 17L, inner_folds_per_task = 16L,
    gam_fits = nrow(diagnostics), calibrators = nrow(calibrators), thresholds = nrow(selected_thresholds), outer_oof_rows = nrow(oof),
    data_md5 = frozen$manifest$upstream$table$md5, config_md5 = frozen$manifest$config$md5,
    fold_manifest_md5 = rrisk11_text_signature(rrisk11_fold_paths(context)[["manifest"]])$md5,
    branch_sqrt_weighted_gate_metrics = TRUE, station_equal_probability_ranking_metrics = TRUE,
    v2_dependency = FALSE, final_model_fitted = FALSE, release_created = FALSE
  )
  rrisk11_write_json(manifest, file.path(validation_dir, "oof_manifest.json"))
  reports <- rrisk11_run_dir(context, run_id, "reports")
  for (name in setdiff(names(outputs), c("oof_predictions", "gam_diagnostics"))) rrisk11_write_csv(outputs[[name]], file.path(reports, paste0(name, ".csv")))
  rrisk11_write_json(manifest, file.path(reports, "oof_manifest.json"))
  rrisk11_write_yaml(manifest, file.path(reports, "run_manifest.yml"))
  rrisk11_log("Aggregated 34 tasks into 744 strict Outer OOF predictions.")
  invisible(list(gate_metrics = gate_metrics, probability_metrics = probability_metrics))
}
