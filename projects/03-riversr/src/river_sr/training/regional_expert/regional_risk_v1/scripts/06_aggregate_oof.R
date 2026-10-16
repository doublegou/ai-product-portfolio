stage_rrisk_aggregate_oof <- function(context, run_id) {
  frozen <- rrisk_assert_folds_current(context)
  rrisk_begin_run(context, run_id, commandArgs(trailingOnly = TRUE))
  options(river_sr.regional_risk_v1.log_file = rrisk_run_dir(context, run_id, "logs", "run.log"))
  tasks <- frozen$tasks
  incomplete <- vapply(seq_len(nrow(tasks)), function(i) !rrisk_task_complete(rrisk_task_dir(context, tasks$model_id[[i]], tasks$outer_fold[[i]])), logical(1L))
  rrisk_assert(!any(incomplete), paste("Cannot aggregate; incomplete task IDs:", paste(tasks$task_id[incomplete], collapse = ", ")))
  predictions <- vector("list", nrow(tasks)); diagnostics <- vector("list", nrow(tasks)); selected <- list(); selected_index <- 0L
  for (i in seq_len(nrow(tasks))) {
    task_dir <- rrisk_task_dir(context, tasks$model_id[[i]], tasks$outer_fold[[i]])
    predictions[[i]] <- rrisk_read_csv(file.path(task_dir, "outer_predictions.csv"))
    diagnostics[[i]] <- rrisk_read_csv(file.path(task_dir, "model_diagnostics.csv"))
    selected_path <- file.path(task_dir, "selected_params.csv")
    if (file.exists(selected_path)) { selected_index <- selected_index + 1L; selected[[selected_index]] <- rrisk_read_csv(selected_path) }
  }
  oof <- as.data.frame(data.table::rbindlist(predictions, use.names = TRUE, fill = TRUE))
  model_diagnostics <- as.data.frame(data.table::rbindlist(diagnostics, use.names = TRUE, fill = TRUE))
  expected_rows <- frozen$validated$data[[context$config$columns$row_id]]
  for (model in unique(oof$model_id)) {
    current <- oof[oof$model_id == model, , drop = FALSE]
    rrisk_assert(nrow(current) == 372L && !anyDuplicated(current$row_id) && setequal(current$row_id, expected_rows), paste("Incomplete LOBO coverage:", model))
  }
  rrisk_assert(nrow(oof) == as.integer(context$config$validation$expected_oof_rows), "Regional Risk V1 must aggregate 1,860 OOF predictions.")
  oof <- oof[order(match(oof$model_id, unique(tasks$model_id)), oof$outer_fold, oof$row_id), , drop = FALSE]
  pooled <- rrisk_pooled_metrics(oof, context)
  branch_metrics <- rrisk_mixed_branch_metrics(oof, frozen$labels, context)
  macro <- rrisk_mixed_macro_metrics(branch_metrics)
  coverage <- rrisk_positive_branch_coverage(oof, frozen$labels)
  sensitivity <- rrisk_leave_one_branch_sensitivity(oof, context)
  bootstrap <- rrisk_branch_bootstrap(oof, context)
  intervals <- rrisk_bootstrap_intervals(bootstrap, context)
  contrasts <- rrisk_paired_contrasts(pooled, bootstrap, context)
  roles <- rrisk_role_summary(pooled, model_diagnostics)
  validation_dir <- rrisk_output_path(context, "validation_dir")
  outputs <- list(
    oof_predictions = oof, lobo_manifest = frozen$labels, pooled_metrics = pooled,
    model_diagnostics = model_diagnostics, mixed_branch_metrics = branch_metrics,
    mixed_branch_macro_metrics = macro, positive_branch_coverage = coverage,
    leave_one_branch_sensitivity = sensitivity, branch_bootstrap_metrics = bootstrap,
    branch_bootstrap_intervals = intervals, paired_model_contrasts = contrasts, candidate_roles = roles
  )
  for (name in names(outputs)) rrisk_write_csv(outputs[[name]], file.path(validation_dir, paste0(name, ".csv")))
  if (length(selected)) rrisk_write_csv(as.data.frame(data.table::rbindlist(selected, use.names = TRUE, fill = TRUE)), file.path(validation_dir, "elastic_selected_params.csv"))
  manifest <- list(
    status = "complete", run_id = run_id, aggregated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    tasks = 85L, models = 5L, outer_folds = 17L, oof_rows = nrow(oof),
    data_md5 = frozen$manifest$input$md5, config_md5 = frozen$manifest$config$md5,
    fold_manifest_md5 = rrisk_text_signature(rrisk_fold_paths(context)[["manifest"]])$md5,
    station_equal_pooled_metrics = TRUE, probability_averaging = FALSE, final_model_fitted = FALSE
  )
  rrisk_write_json(manifest, file.path(validation_dir, "oof_manifest.json"))
  reports <- rrisk_run_dir(context, run_id, "reports")
  for (name in setdiff(names(outputs), "branch_bootstrap_metrics")) rrisk_write_csv(outputs[[name]], file.path(reports, paste0(name, ".csv")))
  rrisk_write_json(manifest, file.path(reports, "oof_manifest.json"))
  rrisk_write_yaml(manifest, file.path(reports, "run_manifest.yml"))
  rrisk_log("Aggregated 85 tasks into 1,860 strict LOBO predictions.")
  invisible(list(pooled = pooled, macro = macro, roles = roles, contrasts = contrasts))
}
