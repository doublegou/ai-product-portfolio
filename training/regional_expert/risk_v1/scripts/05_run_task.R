stage_rrisk_run_task <- function(context, task_id, force = FALSE) {
  frozen <- rrisk_assert_folds_current(context)
  task_id <- as.integer(task_id)
  task <- frozen$tasks[frozen$tasks$task_id == task_id, , drop = FALSE]
  rrisk_assert(nrow(task) == 1L, "task_id must resolve to exactly one Regional Risk V1 task.")
  output_dir <- rrisk_task_dir(context, task$model_id[[1L]], task$outer_fold[[1L]])
  if (rrisk_task_complete(output_dir) && !force) {
    rrisk_log("Regional Risk V1 task already complete; skipped: ", task_id, ".")
    return(invisible(jsonlite::read_json(file.path(output_dir, "task_info.json"), simplifyVector = TRUE)))
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  options(river_sr.regional_risk_v1.log_file = file.path(output_dir, "run.log"))
  dat <- frozen$validated$data
  branch_map <- frozen$branches[match(dat[[context$config$columns$row_id]], frozen$branches$row_id), , drop = FALSE]
  rrisk_assert(!anyNA(branch_map$row_id), "Task branch-map join is incomplete.")
  dat$.regional_branch_id <- branch_map$regional_branch_id
  heldout <- unique(branch_map$regional_branch_id[branch_map$branch_order == task$outer_fold[[1L]]])
  rrisk_assert(length(heldout) == 1L, "Outer fold does not identify one held-out branch.")
  task$heldout_branch <- heldout
  test_index <- dat$.regional_branch_id == heldout
  outer_train <- dat[!test_index, , drop = FALSE]; outer_test <- dat[test_index, , drop = FALSE]
  rrisk_assert(length(intersect(unique(outer_train$.regional_branch_id), unique(outer_test$.regional_branch_id))) == 0L, "A regional branch crosses the Outer boundary.")
  raw_train_weight <- 1 / sqrt(as.numeric(table(outer_train$.regional_branch_id)[outer_train$.regional_branch_id]))
  normalizer <- mean(raw_train_weight)
  outer_train$.weight <- raw_train_weight / normalizer
  outer_test$.weight <- (1 / sqrt(nrow(outer_test))) / normalizer
  rrisk_assert(abs(mean(outer_train$.weight) - 1) < 1e-12, "Outer branch weights are not normalized to mean one.")
  rrisk_log("Starting task ", task_id, ": ", task$model_id[[1L]], ", held out ", heldout, ".")
  result <- if (identical(task$model_type[[1L]], "gam")) rrisk_run_gam(outer_train, outer_test, task, context) else rrisk_run_elastic(outer_train, outer_test, task, context)
  predictions <- data.frame(
    task_id = task_id, row_id = outer_test[[context$config$columns$row_id]], site_id = outer_test[[context$config$columns$site_id]],
    regional_branch_id = outer_test$.regional_branch_id, outer_fold = task$outer_fold[[1L]], heldout_branch = heldout,
    observed_sr = outer_test$.observed, high_sr_label = outer_test$.label, branch_sqrt_weight = outer_test$.weight,
    model_type = task$model_type[[1L]], feature_set = task$feature_set[[1L]], model_id = task$model_id[[1L]],
    p_high = result$probability, stringsAsFactors = FALSE
  )
  medians <- data.frame(
    feature = names(result$medians), training_median = as.numeric(result$medians),
    n_missing_outer_train = vapply(outer_train[names(result$medians)], function(x) sum(is.na(x)), integer(1L)), stringsAsFactors = FALSE
  )
  rrisk_write_csv(predictions, file.path(output_dir, "outer_predictions.csv"))
  rrisk_write_csv(result$diagnostics, file.path(output_dir, "model_diagnostics.csv"))
  rrisk_write_csv(medians, file.path(output_dir, "outer_training_medians.csv"))
  if (!is.null(result$inner_assignments)) rrisk_write_csv(result$inner_assignments, file.path(output_dir, "inner_assignments.csv"))
  if (!is.null(result$selected)) rrisk_write_csv(result$selected, file.path(output_dir, "selected_params.csv"))
  info <- list(
    status = "complete", task_id = task_id, model_id = task$model_id[[1L]], model_type = task$model_type[[1L]],
    feature_set = task$feature_set[[1L]], outer_fold = as.integer(task$outer_fold[[1L]]), heldout_branch = heldout,
    n_outer_train = nrow(outer_train), n_outer_test = nrow(outer_test), n_train_branches = length(unique(outer_train$.regional_branch_id)),
    branch_leakage = 0L, weight_mean_outer_train = mean(outer_train$.weight),
    data_md5 = frozen$manifest$input$md5, config_md5 = frozen$manifest$config$md5,
    fold_manifest_md5 = rrisk_text_signature(rrisk_fold_paths(context)[["manifest"]])$md5,
    completed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), runtime = rrisk_runtime_info()
  )
  rrisk_write_json(info, file.path(output_dir, "task_info.json"))
  rrisk_log("Task ", task_id, " complete.")
  invisible(info)
}
