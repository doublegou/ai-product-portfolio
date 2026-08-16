stage_run_stress_task <- function(context, run_id, scheme, outer_fold, force = FALSE) {
  v1_assert_folds_current(context)
  outer_fold <- as.integer(outer_fold)
  valid_schemes <- c(paste0("spatial_", as.integer(unlist(context$config$validation$spatial_scales_km))), "reference")
  v1_assert(scheme %in% valid_schemes, paste("Unknown stress scheme:", scheme))
  v1_assert(outer_fold %in% seq_len(as.integer(context$config$validation$outer_folds)), "Stress outer_fold is invalid.")
  selected_path <- v1_run_dir(context, run_id, "models", "selected_params.yml")
  v1_assert(file.exists(selected_path), paste("Deployment tuning is incomplete; missing:", selected_path))
  selected <- yaml::read_yaml(selected_path)
  recipe_md5 <- v1_recipe_md5(selected)
  v1_assert(identical(as.character(selected$recipe_md5), recipe_md5), "Selected recipe fingerprint is inconsistent.")
  output_dir <- v1_stress_task_dir(context, scheme, outer_fold)
  if (v1_task_complete(output_dir, "stress") && !force) {
    existing <- jsonlite::read_json(file.path(output_dir, "task_info.json"), simplifyVector = TRUE)
    v1_assert(identical(as.character(existing$recipe_md5), recipe_md5), "Existing stress task used a different deployment recipe; archive or rerun with --force.")
    v1_log("Stress task already complete; skipped: ", scheme, " fold ", outer_fold, ".")
    return(invisible(existing))
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  options(river_sr.v1.log_file = file.path(output_dir, "run.log"))
  manifest <- data.table::fread(
    v1_output_path(context, "validation_dir", "stress", "task_manifest.csv"), data.table = FALSE
  )
  task <- manifest[manifest$scheme == scheme & manifest$outer_fold == outer_fold, , drop = FALSE]
  v1_assert(nrow(task) == 1L, "Stress task did not resolve to exactly one manifest row.")
  task_id <- as.integer(task$task_id[[1L]])

  dat <- v1_read_training_data(context)
  predictors <- v1_read_predictors(context)
  columns <- context$config$columns
  dat[[columns$row_id]] <- as.character(dat[[columns$row_id]])
  all_design <- data.table::fread(v1_fold_paths(context)[["stress"]], data.table = FALSE)
  design <- all_design[all_design$scheme == scheme, , drop = FALSE]
  test_ids <- as.character(design$row_id[design$outer_fold == outer_fold])
  train_ids <- setdiff(dat[[columns$row_id]], test_ids)
  train_units <- unique(design$validation_unit[design$row_id %in% train_ids])
  test_units <- unique(design$validation_unit[design$row_id %in% test_ids])
  v1_assert(length(intersect(train_units, test_units)) == 0L, "A stress validation unit crosses the Outer boundary.")
  train <- dat[match(train_ids, dat[[columns$row_id]]), , drop = FALSE]
  test <- dat[match(test_ids, dat[[columns$row_id]]), , drop = FALSE]
  x_train_raw <- v1_numeric_predictors(train, predictors)
  x_test_raw <- v1_numeric_predictors(test, predictors)
  medians <- v1_fit_medians(x_train_raw)
  x_train <- v1_apply_medians(x_train_raw, medians)
  x_test <- v1_apply_medians(x_test_raw, medians)
  seed <- as.integer(context$config$model$stress_seed_base) + task_id * 10000L + outer_fold
  v1_log("Stress task ", task_id, ": ", scheme, " fold ", outer_fold, " with frozen recipe ", recipe_md5, ".")
  model <- v1_fit_rf(
    x_train, train[[columns$response]], selected,
    as.integer(context$config$model$stress_trees), seed, v1_ranger_threads(context)
  )
  predicted <- as.numeric(predict(model, data = x_test, num.threads = v1_ranger_threads(context))$predictions)
  predictions <- data.frame(
    task_id = task_id,
    scheme = scheme,
    outer_fold = outer_fold,
    row_id = test[[columns$row_id]],
    site_id = test[[columns$site_id]],
    longitude = test[[columns$longitude]],
    latitude = test[[columns$latitude]],
    reference_id = test[[columns$reference]],
    observed = test[[columns$response]],
    predicted = predicted,
    residual = predicted - test[[columns$response]],
    stringsAsFactors = FALSE
  )
  metrics <- cbind(
    data.frame(
      task_id = task_id, scheme = scheme, outer_fold = outer_fold,
      mtry = as.integer(selected$mtry), min_node_size = as.integer(selected$min_node_size),
      sample_fraction = as.numeric(selected$sample_fraction), replace = as.logical(selected$replace),
      trees = as.integer(context$config$model$stress_trees), seed = seed, recipe_md5 = recipe_md5
    ),
    v1_calculate_metrics(predictions$observed, predictions$predicted)
  )
  medians_table <- data.frame(
    feature = predictors,
    training_median = as.numeric(medians[predictors]),
    n_missing_outer_train = vapply(train[predictors], function(x) sum(is.na(x)), integer(1L))
  )
  v1_write_csv(predictions, file.path(output_dir, "outer_predictions.csv"))
  v1_write_csv(metrics, file.path(output_dir, "outer_metrics.csv"))
  v1_write_csv(v1_tail_metrics(predictions, scheme), file.path(output_dir, "outer_tail_metrics.csv"))
  v1_write_csv(v1_threshold_metrics(predictions, scheme), file.path(output_dir, "outer_threshold_metrics.csv"))
  v1_write_csv(medians_table, file.path(output_dir, "outer_training_medians.csv"))
  info <- list(
    status = "complete",
    task_id = task_id,
    scheme = scheme,
    outer_fold = outer_fold,
    n_outer_train = nrow(train),
    n_outer_test = nrow(test),
    n_train_units = length(train_units),
    n_test_units = length(test_units),
    unit_leakage = 0L,
    retuned = FALSE,
    recipe_md5 = recipe_md5,
    trees = as.integer(context$config$model$stress_trees),
    seed = seed,
    completed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
  v1_write_json(info, file.path(output_dir, "task_info.json"))
  v1_log("Stress task ", task_id, " complete: RMSE=", signif(metrics$rmse, 7), ".")
  invisible(info)
}

stage_run_all_stress <- function(context, run_id, force = FALSE) {
  manifest <- data.table::fread(
    v1_output_path(context, "validation_dir", "stress", "task_manifest.csv"), data.table = FALSE
  )
  for (i in seq_len(nrow(manifest))) {
    stage_run_stress_task(
      context, run_id, manifest$scheme[[i]], manifest$outer_fold[[i]], force = force
    )
  }
  invisible(manifest)
}
