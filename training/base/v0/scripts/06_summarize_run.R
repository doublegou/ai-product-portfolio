stage_summarize_run <- function(context, run_id) {
  v0_log("Summarizing the 20 V0 validation tasks.")
  manifest <- data.table::fread(v0_output_path(context, "validation_dir", "task_manifest.csv"), data.table = FALSE)
  metric_records <- list()
  prediction_records <- list()
  for (i in seq_len(nrow(manifest))) {
    task_dir <- v0_task_dir(context, manifest$scheme[[i]], manifest$outer_fold[[i]])
    v0_assert(v0_task_complete(task_dir), paste("Incomplete validation task:", task_dir))
    metric_records[[i]] <- data.table::fread(file.path(task_dir, "outer_metrics.csv"), data.table = FALSE)
    prediction_records[[i]] <- data.table::fread(file.path(task_dir, "outer_predictions.csv"), data.table = FALSE)
  }
  fold_metrics <- do.call(rbind, metric_records)
  predictions <- do.call(rbind, prediction_records)
  schemes <- unique(manifest$scheme)
  summaries <- do.call(rbind, lapply(schemes, function(scheme) {
    current_metrics <- fold_metrics[fold_metrics$scheme == scheme, , drop = FALSE]
    current_predictions <- predictions[predictions$scheme == scheme, , drop = FALSE]
    pooled <- v0_calculate_metrics(current_predictions$observed, current_predictions$predicted)
    data.frame(
      scheme = scheme,
      role = if (scheme == context$config$validation$primary_scheme) "primary" else "stress",
      n_outer_folds = nrow(current_metrics),
      n_predictions = nrow(current_predictions),
      pooled_rmse = pooled$rmse,
      pooled_mae = pooled$mae,
      pooled_r2 = pooled$r2,
      pooled_bias = pooled$bias,
      mean_fold_rmse = mean(current_metrics$rmse),
      mean_fold_mae = mean(current_metrics$mae),
      mean_fold_r2 = mean(current_metrics$r2, na.rm = TRUE)
    )
  }))
  reports_dir <- v0_run_dir(context, run_id, "reports")
  dir.create(reports_dir, recursive = TRUE, showWarnings = FALSE)
  v0_write_csv(fold_metrics, file.path(reports_dir, "outer_fold_metrics.csv"))
  v0_write_csv(predictions, file.path(reports_dir, "outer_predictions.csv"))
  v0_write_csv(summaries, file.path(reports_dir, "validation_summary.csv"))
  selected <- yaml::read_yaml(v0_run_dir(context, run_id, "models", "selected_params.yml"))
  primary <- summaries[summaries$scheme == context$config$validation$primary_scheme, , drop = FALSE]
  lines <- c(
    "# Base Model V0 run summary",
    "",
    paste0("- Run: `", run_id, "`"),
    "- Model: Full50 unweighted ranger Random Forest",
    paste0("- Primary evaluation: `", context$config$validation$primary_scheme, "`"),
    paste0("- Primary pooled RMSE: ", signif(primary$pooled_rmse, 7)),
    paste0("- Primary pooled MAE: ", signif(primary$pooled_mae, 7)),
    paste0("- Primary pooled R²: ", signif(primary$pooled_r2, 7)),
    paste0("- Final mtry: ", selected$mtry),
    paste0("- Final min.node.size: ", selected$min_node_size),
    paste0("- Final sample.fraction: ", selected$sample_fraction),
    paste0("- Consensus support: ", selected$n_tasks_supporting, "/15 spatial tasks"),
    "- Reference-group CV did not participate in final parameter selection.",
    "",
    "Final-model in-sample metrics are sanity checks only; report predictive performance from nested CV."
  )
  writeLines(lines, file.path(reports_dir, "run_summary.md"), useBytes = TRUE)
  v0_log("Run report written: ", reports_dir)
  invisible(summaries)
}

stage_release_run <- function(context, run_id, force = FALSE) {
  source_dir <- v0_run_dir(context, run_id)
  required <- c(
    model = file.path(source_dir, "models", "full50_rf_model.rds"),
    parameters = file.path(source_dir, "models", "selected_params.yml"),
    summary = file.path(source_dir, "reports", "validation_summary.csv"),
    config = file.path(source_dir, "config_used.yml")
  )
  v0_assert(all(file.exists(required)), paste("Run is not release-ready; missing:", paste(required[!file.exists(required)], collapse = ", ")))
  release_dir <- v0_output_path(context, "release_dir")
  release_targets <- c(
    file.path(release_dir, "model_bundle.rds"),
    file.path(release_dir, "selected_params.yml"),
    file.path(release_dir, "validation_summary.csv"),
    file.path(release_dir, "config_used.yml"),
    file.path(release_dir, "release_info.json")
  )
  existing <- release_targets[file.exists(release_targets)]
  existing <- existing[basename(existing) != "README.md"]
  v0_assert(length(existing) == 0L || force, "A frozen V0 release already exists. Refusing to overwrite it without --force.")
  dir.create(release_dir, recursive = TRUE, showWarnings = FALSE)
  destinations <- c(
    file.path(release_dir, "model_bundle.rds"),
    file.path(release_dir, "selected_params.yml"),
    file.path(release_dir, "validation_summary.csv"),
    file.path(release_dir, "config_used.yml")
  )
  copied <- file.copy(unname(required), destinations, overwrite = force)
  v0_assert(all(copied), "Failed to copy one or more release artifacts.")
  v0_write_json(
    list(
      status = "frozen",
      source_run = run_id,
      released_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      model_md5 = unname(tools::md5sum(file.path(release_dir, "model_bundle.rds")))
    ),
    file.path(release_dir, "release_info.json")
  )
  v0_log("Frozen V0 release created directly in: ", release_dir)
  invisible(release_dir)
}
