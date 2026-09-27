stage_run_nested_cv_task <- function(
  context, scheme, outer_fold, output_dir = NULL, inner_trees = NULL,
  outer_trees = NULL, force = FALSE, mode = "full"
) {
  v0_assert_folds_current(context)
  outer_fold <- as.integer(outer_fold)
  valid_schemes <- c(
    paste0("spatial_", as.integer(unlist(context$config$validation$spatial_scales_km))),
    "reference"
  )
  v0_assert(scheme %in% valid_schemes, paste("Unknown validation scheme:", scheme))
  v0_assert(outer_fold %in% seq_len(as.integer(context$config$validation$outer_folds)), "outer_fold must be 1-5.")
  if (is.null(output_dir)) output_dir <- v0_task_dir(context, scheme, outer_fold)
  if (is.null(inner_trees)) inner_trees <- as.integer(context$config$model$inner_trees)
  if (is.null(outer_trees)) outer_trees <- as.integer(context$config$model$outer_trees)
  if (v0_task_complete(output_dir) && !force) {
    existing <- jsonlite::read_json(file.path(output_dir, "task_info.json"), simplifyVector = TRUE)
    v0_assert(
      identical(as.integer(existing$inner_trees), as.integer(inner_trees)) &&
        identical(as.integer(existing$outer_trees), as.integer(outer_trees)),
      paste("Existing task used different tree counts; rerun explicitly with --force:", scheme, outer_fold)
    )
    v0_log("Validation task already complete; skipped: ", scheme, " fold ", outer_fold)
    return(invisible(existing))
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  task_manifest <- data.table::fread(v0_output_path(context, "validation_dir", "task_manifest.csv"), data.table = FALSE)
  task <- task_manifest[task_manifest$scheme == scheme & task_manifest$outer_fold == outer_fold, , drop = FALSE]
  v0_assert(nrow(task) == 1L, "Validation task did not resolve to exactly one manifest row.")
  task_id <- as.integer(task$task_id[[1L]])
  dat <- v0_read_training_data(context)
  predictors <- v0_read_predictors(context)
  columns <- context$config$columns
  dat[[columns$row_id]] <- as.character(dat[[columns$row_id]])
  outer_all <- data.table::fread(v0_output_path(context, "folds_dir", "outer_assignments.csv"), data.table = FALSE)
  inner_all <- data.table::fread(v0_output_path(context, "folds_dir", "inner_assignments.csv"), data.table = FALSE)
  outer_design <- outer_all[outer_all$scheme == scheme, , drop = FALSE]
  inner_design <- inner_all[inner_all$scheme == scheme & inner_all$outer_fold == outer_fold, , drop = FALSE]
  outer_test_ids <- as.character(outer_design$row_id[outer_design$outer_fold == outer_fold])
  outer_train_ids <- setdiff(dat[[columns$row_id]], outer_test_ids)
  v0_assert(length(intersect(outer_train_ids, outer_test_ids)) == 0L, "Outer train and test rows overlap.")
  v0_assert(setequal(c(outer_train_ids, outer_test_ids), dat[[columns$row_id]]), "Outer partition does not cover all rows.")
  v0_assert(setequal(as.character(inner_design$row_id), outer_train_ids), "Inner rows differ from outer-training rows.")
  if (scheme == "reference") {
    train_units <- unique(outer_design$validation_unit[outer_design$outer_fold != outer_fold])
    test_units <- unique(outer_design$validation_unit[outer_design$outer_fold == outer_fold])
    v0_assert(length(intersect(train_units, test_units)) == 0L, "A reference group crosses the outer boundary.")
  }

  v0_log("Running ", mode, " task ", task_id, ": ", scheme, " fold ", outer_fold, ".")
  tuning <- v0_tune_outer_task(
    dat, predictors, outer_train_ids, inner_design, context, task_id, as.integer(inner_trees)
  )
  selected <- tuning$selected
  selected_record <- list(
    task_id = task_id,
    scheme = scheme,
    outer_fold = outer_fold,
    mtry = as.integer(selected$mtry[[1L]]),
    min_node_size = as.integer(selected$min_node_size[[1L]]),
    sample_fraction = as.numeric(selected$sample_fraction[[1L]]),
    mean_rmse = as.numeric(selected$mean_rmse[[1L]]),
    mean_mae = as.numeric(selected$mean_mae[[1L]]),
    mean_r2 = as.numeric(selected$mean_r2[[1L]]),
    selection_order = "mean_rmse asc, mean_mae asc, mean_r2 desc, mtry asc, min_node_size asc, sample_fraction asc"
  )
  v0_write_csv(tuning$grid, file.path(output_dir, "tuning_grid.csv"))
  v0_write_csv(tuning$inner_metrics, file.path(output_dir, "inner_fold_metrics.csv"))
  v0_write_csv(tuning$summary, file.path(output_dir, "tuning_summary.csv"))
  v0_write_yaml(selected_record, file.path(output_dir, "selected_params.yml"))

  outer_train <- dat[match(outer_train_ids, dat[[columns$row_id]]), , drop = FALSE]
  outer_test <- dat[match(outer_test_ids, dat[[columns$row_id]]), , drop = FALSE]
  x_train_raw <- v0_numeric_predictors(outer_train, predictors)
  x_test_raw <- v0_numeric_predictors(outer_test, predictors)
  medians <- v0_fit_medians(x_train_raw)
  x_train <- v0_apply_medians(x_train_raw, medians)
  x_test <- v0_apply_medians(x_test_raw, medians)
  seed_base <- if (scheme == "reference") {
    as.integer(context$config$model$reference_seed_base)
  } else {
    as.integer(context$config$model$spatial_seed_base)
  }
  outer_seed <- seed_base + task_id * 1000L + 999L
  model <- v0_fit_rf(
    x_train, outer_train[[columns$response]], selected_record, outer_trees,
    outer_seed, v0_ranger_threads(context), write_forest = TRUE
  )
  predicted <- as.numeric(predict(model, data = x_test, num.threads = v0_ranger_threads(context))$predictions)
  predictions <- data.frame(
    task_id = task_id,
    scheme = scheme,
    outer_fold = outer_fold,
    row_id = outer_test[[columns$row_id]],
    site_id = outer_test[[columns$site_id]],
    longitude = outer_test[[columns$longitude]],
    latitude = outer_test[[columns$latitude]],
    reference_id = outer_test[[columns$reference]],
    observed = outer_test[[columns$response]],
    predicted = predicted,
    residual = predicted - outer_test[[columns$response]],
    stringsAsFactors = FALSE
  )
  metrics <- cbind(
    data.frame(
      task_id = task_id, scheme = scheme, outer_fold = outer_fold,
      mtry = selected_record$mtry, min_node_size = selected_record$min_node_size,
      sample_fraction = selected_record$sample_fraction, outer_trees = as.integer(outer_trees), seed = outer_seed
    ),
    v0_calculate_metrics(predictions$observed, predictions$predicted)
  )
  median_table <- data.frame(
    feature = predictors,
    training_median = as.numeric(medians[predictors]),
    n_missing_outer_train = vapply(outer_train[predictors], function(x) sum(is.na(x)), integer(1L))
  )
  v0_write_csv(predictions, file.path(output_dir, "outer_predictions.csv"))
  v0_write_csv(metrics, file.path(output_dir, "outer_metrics.csv"))
  v0_write_csv(median_table, file.path(output_dir, "outer_training_medians.csv"))
  info <- list(
    status = "complete", mode = mode, task_id = task_id, scheme = scheme, outer_fold = outer_fold,
    n_outer_train = nrow(outer_train), n_outer_test = nrow(outer_test),
    inner_trees = as.integer(inner_trees), outer_trees = as.integer(outer_trees),
    seed = outer_seed, completed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
  v0_write_json(info, file.path(output_dir, "task_info.json"))
  v0_log("Completed task ", task_id, ": RMSE=", signif(metrics$rmse, 7), ".")
  invisible(info)
}

stage_run_all_validation <- function(context, force = FALSE) {
  manifest <- data.table::fread(v0_output_path(context, "validation_dir", "task_manifest.csv"), data.table = FALSE)
  for (i in seq_len(nrow(manifest))) {
    stage_run_nested_cv_task(
      context, manifest$scheme[[i]], manifest$outer_fold[[i]], force = force, mode = "full"
    )
  }
  invisible(manifest)
}
