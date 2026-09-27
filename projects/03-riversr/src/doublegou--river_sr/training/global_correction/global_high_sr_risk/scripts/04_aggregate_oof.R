stage_risk_aggregate_oof <- function(context, run_id, force = FALSE) {
  frozen <- risk_assert_folds_current(context)
  risk_begin_run(context, run_id, commandArgs(trailingOnly = TRUE))
  options(river_sr.risk_v1.log_file = risk_run_dir(context, run_id, "logs", "run.log"))
  tasks <- data.table::fread(risk_fold_paths(context)[["tasks"]], data.table = FALSE)
  incomplete <- logical(nrow(tasks))
  for (i in seq_len(nrow(tasks))) {
    path <- risk_task_dir(context, tasks$model[[i]], tasks$repeat_id[[i]], tasks$outer_fold[[i]])
    incomplete[[i]] <- !risk_task_complete(path)
  }
  risk_assert(!any(incomplete), paste("Cannot aggregate; incomplete task IDs:", paste(tasks$task_id[incomplete], collapse = ", ")))
  validated <- frozen$validated
  expected_rows <- as.character(validated$data[[context$config$columns$row_id]])
  repeat_records <- list()
  selected_records <- list()
  repeat_index <- 0L
  selected_index <- 0L
  for (model in c("elastic_net", "probability_rf")) {
    for (repeat_id in seq_len(as.integer(context$config$validation$repeats))) {
      fold_predictions <- list()
      for (outer_fold in seq_len(as.integer(context$config$validation$outer_folds))) {
        task_dir <- risk_task_dir(context, model, repeat_id, outer_fold)
        fold_predictions[[outer_fold]] <- data.table::fread(file.path(task_dir, "outer_predictions.csv"), integer64 = "character", data.table = FALSE)
        selected <- yaml::read_yaml(file.path(task_dir, "selected_params.yml"))
        selected_index <- selected_index + 1L
        selected_records[[selected_index]] <- as.data.frame(selected, stringsAsFactors = FALSE)
      }
      oof <- data.table::rbindlist(fold_predictions, use.names = TRUE, fill = TRUE)
      oof <- as.data.frame(oof)
      oof$row_id <- as.character(oof$row_id)
      risk_assert(nrow(oof) == length(expected_rows) && !anyDuplicated(oof$row_id) && setequal(oof$row_id, expected_rows), paste("Incomplete full OOF coverage:", model, repeat_id))
      oof <- oof[match(expected_rows, oof$row_id), , drop = FALSE]
      oof$triggered <- as.logical(oof$triggered)
      metrics <- risk_metrics_from_triggers(oof$observed, oof$probability, oof$triggered, oof$hydrological_group, context)
      repeat_index <- repeat_index + 1L
      repeat_records[[repeat_index]] <- cbind(
        data.frame(model = model, repeat_id = repeat_id, stringsAsFactors = FALSE), metrics
      )
      repeat_dir <- risk_output_path(context, "validation_dir", model, sprintf("repeat_%02d", repeat_id))
      risk_write_csv(oof, file.path(repeat_dir, "oof_predictions.csv"))
      risk_log("Aggregated complete OOF: ", model, " repeat ", repeat_id, ".")
    }
  }
  repeat_metrics <- risk_apply_promotion_gates(do.call(rbind, repeat_records), context)
  model_summary <- risk_model_summary(repeat_metrics, context)
  selected_tasks <- as.data.frame(data.table::rbindlist(selected_records, use.names = TRUE, fill = TRUE))
  validation_dir <- risk_output_path(context, "validation_dir")
  risk_write_csv(repeat_metrics, file.path(validation_dir, "repeat_metrics.csv"))
  risk_write_csv(model_summary, file.path(validation_dir, "model_summary.csv"))
  risk_write_csv(selected_tasks, file.path(validation_dir, "selected_tasks.csv"))
  aggregate_manifest <- list(
    status = "complete", aggregated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), run_id = run_id,
    task_count = nrow(tasks), models = 2L, repeats_per_model = 3L,
    oof_rows_per_model = length(expected_rows) * 3L, total_oof_rows = length(expected_rows) * 3L * 2L,
    data_md5 = frozen$manifest$input$md5, config_md5 = frozen$manifest$config$md5,
    fold_manifest_md5 = risk_text_signature(risk_fold_paths(context)[["manifest"]])$md5,
    probability_averaging_across_repeats = FALSE
  )
  risk_write_json(aggregate_manifest, file.path(validation_dir, "oof_manifest.json"))
  reports <- risk_run_dir(context, run_id, "reports")
  risk_write_csv(repeat_metrics, file.path(reports, "repeat_metrics.csv"))
  risk_write_csv(model_summary, file.path(reports, "model_summary.csv"))
  risk_write_csv(selected_tasks, file.path(reports, "selected_tasks.csv"))
  risk_write_json(aggregate_manifest, file.path(reports, "oof_manifest.json"))
  invisible(list(repeat_metrics = repeat_metrics, model_summary = model_summary))
}
