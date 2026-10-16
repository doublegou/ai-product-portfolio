stage_run_primary_task <- function(context, repeat_id, outer_fold, force = FALSE) {
  fold_manifest <- v1_assert_folds_current(context)
  repeat_id <- as.integer(repeat_id)
  outer_fold <- as.integer(outer_fold)
  repeats <- as.integer(context$config$validation$repeats)
  outer_k <- as.integer(context$config$validation$outer_folds)
  v1_assert(repeat_id %in% seq_len(repeats), paste("repeat must be 1-", repeats, "."))
  v1_assert(outer_fold %in% seq_len(outer_k), paste("outer_fold must be 1-", outer_k, "."))
  output_dir <- v1_primary_task_dir(context, repeat_id, outer_fold)
  if (v1_task_complete(output_dir, "primary") && !force) {
    existing <- jsonlite::read_json(file.path(output_dir, "task_info.json"), simplifyVector = TRUE)
    v1_assert(identical(as.character(existing$config_md5), as.character(fold_manifest$config$md5)), "Existing Primary task used a different V1 config.")
    v1_log("Primary task already complete; skipped: repeat ", repeat_id, " fold ", outer_fold, ".")
    return(invisible(existing))
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  options(river_sr.v1.log_file = file.path(output_dir, "run.log"))
  task_manifest <- data.table::fread(
    v1_output_path(context, "validation_dir", "primary", "task_manifest.csv"), data.table = FALSE
  )
  task <- task_manifest[task_manifest$repeat_id == repeat_id & task_manifest$outer_fold == outer_fold, , drop = FALSE]
  v1_assert(nrow(task) == 1L, "Primary task did not resolve to exactly one manifest row.")
  task_id <- as.integer(task$task_id[[1L]])

  dat <- v1_read_training_data(context)
  predictors <- v1_read_predictors(context)
  columns <- context$config$columns
  dat[[columns$row_id]] <- as.character(dat[[columns$row_id]])
  paths <- v1_fold_paths(context)
  outer_all <- data.table::fread(paths[["primary_outer"]], data.table = FALSE)
  inner_all <- data.table::fread(paths[["primary_inner"]], data.table = FALSE)
  groups <- data.table::fread(paths[["groups"]], integer64 = "character", data.table = FALSE)
  outer_design <- outer_all[outer_all$repeat_id == repeat_id, , drop = FALSE]
  inner_design <- inner_all[inner_all$repeat_id == repeat_id & inner_all$outer_fold == outer_fold, , drop = FALSE]
  outer_test_ids <- as.character(outer_design$row_id[outer_design$outer_fold == outer_fold])
  outer_train_ids <- setdiff(dat[[columns$row_id]], outer_test_ids)
  v1_assert(setequal(c(outer_train_ids, outer_test_ids), dat[[columns$row_id]]), "Primary Outer partition does not cover all rows.")
  v1_assert(setequal(inner_design$row_id, outer_train_ids), "Primary Inner rows differ from Outer training rows.")
  train_groups <- unique(groups$hydrological_group[groups$row_id %in% outer_train_ids])
  test_groups <- unique(groups$hydrological_group[groups$row_id %in% outer_test_ids])
  v1_assert(length(intersect(train_groups, test_groups)) == 0L, "A MAIN_BAS group crosses the Primary Outer boundary.")

  v1_log("Primary task ", task_id, ": repeat ", repeat_id, " fold ", outer_fold, " coarse 48-candidate search.")
  coarse_grid <- v1_coarse_grid(length(predictors), context)
  coarse <- v1_evaluate_candidates(
    dat = dat,
    predictors = predictors,
    analysis_ids = outer_train_ids,
    fold_design = inner_design,
    candidates = coarse_grid,
    fold_column = "inner_fold",
    trees = as.integer(context$config$model$coarse_trees),
    context = context,
    seed_base = as.integer(context$config$model$primary_seed_base),
    task_id = task_id,
    stage = "coarse"
  )
  refinement_grid <- v1_refinement_grid(coarse$summary, context)
  v1_log("Primary task ", task_id, ": refinement of the best ", nrow(refinement_grid), " coarse recipes.")
  refinement <- v1_evaluate_candidates(
    dat = dat,
    predictors = predictors,
    analysis_ids = outer_train_ids,
    fold_design = inner_design,
    candidates = refinement_grid,
    fold_column = "inner_fold",
    trees = as.integer(context$config$model$refinement_trees),
    context = context,
    seed_base = as.integer(context$config$model$primary_seed_base),
    task_id = task_id,
    stage = "refinement"
  )
  winner <- refinement$summary[1L, , drop = FALSE]
  selected <- list(
    task_id = task_id,
    repeat_id = repeat_id,
    outer_fold = outer_fold,
    source_grid_id = as.integer(winner$source_grid_id),
    mtry = as.integer(winner$mtry),
    min_node_size = as.integer(winner$min_node_size),
    sample_fraction = as.numeric(winner$sample_fraction),
    replace = as.logical(winner$replace),
    inner_pooled_rmse = as.numeric(winner$pooled_rmse),
    inner_pooled_mae = as.numeric(winner$pooled_mae),
    inner_pooled_r2 = as.numeric(winner$pooled_r2),
    inner_pooled_bias = as.numeric(winner$pooled_bias),
    selection_order = context$config$search$selection_order
  )
  v1_write_csv(coarse_grid, file.path(output_dir, "coarse_grid.csv"))
  v1_write_csv(coarse$fold_metrics, file.path(output_dir, "coarse_inner_fold_metrics.csv"))
  v1_write_csv(coarse$summary, file.path(output_dir, "coarse_summary.csv"))
  v1_write_csv(refinement_grid, file.path(output_dir, "refinement_grid.csv"))
  v1_write_csv(refinement$fold_metrics, file.path(output_dir, "refinement_inner_fold_metrics.csv"))
  v1_write_csv(refinement$summary, file.path(output_dir, "refinement_summary.csv"))
  v1_write_yaml(selected, file.path(output_dir, "selected_params.yml"))

  outer_train <- dat[match(outer_train_ids, dat[[columns$row_id]]), , drop = FALSE]
  outer_test <- dat[match(outer_test_ids, dat[[columns$row_id]]), , drop = FALSE]
  x_train_raw <- v1_numeric_predictors(outer_train, predictors)
  x_test_raw <- v1_numeric_predictors(outer_test, predictors)
  medians <- v1_fit_medians(x_train_raw)
  x_train <- v1_apply_medians(x_train_raw, medians)
  x_test <- v1_apply_medians(x_test_raw, medians)
  outer_seed <- as.integer(context$config$model$primary_seed_base) + task_id * 1000000L + 900000L
  model <- v1_fit_rf(
    x_train, outer_train[[columns$response]], selected,
    as.integer(context$config$model$outer_trees), outer_seed, v1_ranger_threads(context)
  )
  predicted <- as.numeric(predict(model, data = x_test, num.threads = v1_ranger_threads(context))$predictions)
  group_match <- groups[match(outer_test[[columns$row_id]], groups$row_id), , drop = FALSE]
  predictions <- data.frame(
    task_id = task_id,
    repeat_id = repeat_id,
    outer_fold = outer_fold,
    row_id = outer_test[[columns$row_id]],
    site_id = outer_test[[columns$site_id]],
    hydrological_group = group_match$hydrological_group,
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
      task_id = task_id, repeat_id = repeat_id, outer_fold = outer_fold,
      mtry = selected$mtry, min_node_size = selected$min_node_size,
      sample_fraction = selected$sample_fraction, replace = selected$replace,
      outer_trees = as.integer(context$config$model$outer_trees), seed = outer_seed
    ),
    v1_calculate_metrics(predictions$observed, predictions$predicted)
  )
  medians_table <- data.frame(
    feature = predictors,
    training_median = as.numeric(medians[predictors]),
    n_missing_outer_train = vapply(outer_train[predictors], function(x) sum(is.na(x)), integer(1L))
  )
  v1_write_csv(predictions, file.path(output_dir, "outer_predictions.csv"))
  v1_write_csv(metrics, file.path(output_dir, "outer_metrics.csv"))
  v1_write_csv(v1_tail_metrics(predictions, "primary_outer"), file.path(output_dir, "outer_tail_metrics.csv"))
  v1_write_csv(v1_threshold_metrics(predictions, "primary_outer"), file.path(output_dir, "outer_threshold_metrics.csv"))
  v1_write_csv(medians_table, file.path(output_dir, "outer_training_medians.csv"))
  info <- list(
    status = "complete",
    task_id = task_id,
    repeat_id = repeat_id,
    outer_fold = outer_fold,
    n_outer_train = nrow(outer_train),
    n_outer_test = nrow(outer_test),
    n_train_groups = length(train_groups),
    n_test_groups = length(test_groups),
    group_leakage = 0L,
    coarse_candidates = nrow(coarse_grid),
    refinement_candidates = nrow(refinement_grid),
    coarse_trees = as.integer(context$config$model$coarse_trees),
    refinement_trees = as.integer(context$config$model$refinement_trees),
    outer_trees = as.integer(context$config$model$outer_trees),
    config_md5 = fold_manifest$config$md5,
    seed = outer_seed,
    completed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
  v1_write_json(info, file.path(output_dir, "task_info.json"))
  v1_log("Primary task ", task_id, " complete: RMSE=", signif(metrics$rmse, 7), ".")
  invisible(info)
}

stage_run_all_primary <- function(context, force = FALSE) {
  manifest <- data.table::fread(
    v1_output_path(context, "validation_dir", "primary", "task_manifest.csv"), data.table = FALSE
  )
  for (i in seq_len(nrow(manifest))) {
    stage_run_primary_task(context, manifest$repeat_id[[i]], manifest$outer_fold[[i]], force = force)
  }
  invisible(manifest)
}
