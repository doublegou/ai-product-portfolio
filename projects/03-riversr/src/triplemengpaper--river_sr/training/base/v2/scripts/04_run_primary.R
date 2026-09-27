stage_run_primary_task <- function(context, repeat_id, outer_fold, force = FALSE) {
  fold_manifest <- v2_assert_folds_current(context)
  repeat_id <- as.integer(repeat_id)
  outer_fold <- as.integer(outer_fold)
  repeats <- as.integer(context$config$validation$repeats)
  outer_k <- as.integer(context$config$validation$outer_folds)
  v2_assert(repeat_id %in% seq_len(repeats), paste("repeat must be 1-", repeats, "."))
  v2_assert(outer_fold %in% seq_len(outer_k), paste("outer_fold must be 1-", outer_k, "."))
  output_dir <- v2_primary_task_dir(context, repeat_id, outer_fold)
  if (v2_task_complete(output_dir, "primary") && !force) {
    existing <- jsonlite::read_json(file.path(output_dir, "task_info.json"), simplifyVector = TRUE)
    v2_assert(identical(as.character(existing$config_md5), as.character(fold_manifest$config$md5)), "Existing Primary task used a different V2 config.")
    v2_log("Primary task already complete; skipped: repeat ", repeat_id, " fold ", outer_fold, ".")
    return(invisible(existing))
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  options(river_sr.v2.log_file = file.path(output_dir, "run.log"))
  task_manifest <- data.table::fread(v2_output_path(context, "validation_dir", "primary", "task_manifest.csv"), data.table = FALSE)
  task <- task_manifest[task_manifest$repeat_id == repeat_id & task_manifest$outer_fold == outer_fold, , drop = FALSE]
  v2_assert(nrow(task) == 1L, "Primary task did not resolve to exactly one manifest row.")
  task_id <- as.integer(task$task_id[[1L]])

  dat <- v2_read_training_data(context)
  predictors <- v2_read_predictors(context)
  columns <- context$config$columns
  dat[[columns$row_id]] <- as.character(dat[[columns$row_id]])
  paths <- v2_fold_paths(context)
  outer_all <- data.table::fread(paths[["primary_outer"]], integer64 = "character", data.table = FALSE)
  inner_all <- data.table::fread(paths[["primary_inner"]], integer64 = "character", data.table = FALSE)
  catalog <- data.table::fread(paths[["branch_catalog"]], integer64 = "character", data.table = FALSE)
  selected_scale <- fold_manifest$topology$selected_scale
  groups <- catalog[catalog$scale == selected_scale, c("row_id", "branch_id", "terminal_component_id", "assessment_eligible"), drop = FALSE]
  outer_design <- outer_all[outer_all$repeat_id == repeat_id & outer_all$outer_fold == outer_fold, , drop = FALSE]
  inner_design <- inner_all[inner_all$repeat_id == repeat_id & inner_all$outer_fold == outer_fold, , drop = FALSE]
  outer_train_ids <- as.character(outer_design$row_id[outer_design$role == "analysis"])
  outer_test_ids <- as.character(outer_design$row_id[outer_design$role == "assessment"])
  outer_purge_ids <- as.character(outer_design$row_id[outer_design$role == "purged_downstream"])
  v2_assert(length(intersect(outer_train_ids, outer_test_ids)) == 0L, "Outer analysis and assessment overlap.")
  v2_assert(length(intersect(outer_train_ids, outer_purge_ids)) == 0L, "Outer analysis and purge overlap.")
  v2_assert(setequal(unique(inner_design$row_id), outer_train_ids), "Primary Inner universe differs from the Outer analysis rows.")
  train_branches <- unique(groups$branch_id[groups$row_id %in% outer_train_ids & !is.na(groups$branch_id)])
  test_branches <- unique(groups$branch_id[groups$row_id %in% outer_test_ids & !is.na(groups$branch_id)])
  v2_assert(length(intersect(train_branches, test_branches)) == 0L, "A Primary branch crosses the Outer boundary.")

  v2_log("Primary task ", task_id, ": repeat ", repeat_id, " fold ", outer_fold, " coarse 48-recipe Purged-Branch search.")
  coarse_grid <- v2_coarse_grid(length(predictors), context)
  coarse <- v2_evaluate_candidates(
    dat = dat, predictors = predictors, role_design = inner_design,
    candidates = coarse_grid, fold_column = "inner_fold",
    trees = as.integer(context$config$model$coarse_trees), context = context,
    seed_base = as.integer(context$config$model$primary_seed_base), task_id = task_id, stage = "coarse"
  )
  refinement_grid <- v2_refinement_grid(coarse$summary, context)
  v2_log("Primary task ", task_id, ": refinement of the best ", nrow(refinement_grid), " recipes.")
  refinement <- v2_evaluate_candidates(
    dat = dat, predictors = predictors, role_design = inner_design,
    candidates = refinement_grid, fold_column = "inner_fold",
    trees = as.integer(context$config$model$refinement_trees), context = context,
    seed_base = as.integer(context$config$model$primary_seed_base), task_id = task_id, stage = "refinement"
  )
  winner <- refinement$summary[1L, , drop = FALSE]
  selected <- list(
    task_id = task_id, repeat_id = repeat_id, outer_fold = outer_fold,
    source_grid_id = as.integer(winner$source_grid_id),
    mtry = as.integer(winner$mtry), min_node_size = as.integer(winner$min_node_size),
    sample_fraction = as.numeric(winner$sample_fraction), replace = as.logical(winner$replace),
    inner_pooled_rmse = as.numeric(winner$pooled_rmse),
    inner_branch_macro_rmse = as.numeric(winner$branch_macro_rmse),
    inner_pooled_mae = as.numeric(winner$pooled_mae),
    inner_pooled_r2 = as.numeric(winner$pooled_r2),
    inner_pooled_bias = as.numeric(winner$pooled_bias),
    selection_order = context$config$search$selection_order
  )
  v2_write_csv(coarse_grid, file.path(output_dir, "coarse_grid.csv"))
  v2_write_csv(coarse$fold_metrics, file.path(output_dir, "coarse_inner_fold_metrics.csv"))
  v2_write_csv(coarse$summary, file.path(output_dir, "coarse_summary.csv"))
  v2_write_csv(refinement_grid, file.path(output_dir, "refinement_grid.csv"))
  v2_write_csv(refinement$fold_metrics, file.path(output_dir, "refinement_inner_fold_metrics.csv"))
  v2_write_csv(refinement$summary, file.path(output_dir, "refinement_summary.csv"))
  v2_write_yaml(selected, file.path(output_dir, "selected_params.yml"))

  outer_train <- dat[match(outer_train_ids, dat[[columns$row_id]]), , drop = FALSE]
  outer_test <- dat[match(outer_test_ids, dat[[columns$row_id]]), , drop = FALSE]
  x_train_raw <- v2_numeric_predictors(outer_train, predictors)
  x_test_raw <- v2_numeric_predictors(outer_test, predictors)
  medians <- v2_fit_medians(x_train_raw)
  x_train <- v2_apply_medians(x_train_raw, medians)
  x_test <- v2_apply_medians(x_test_raw, medians)
  outer_seed <- as.integer(context$config$model$primary_seed_base) + task_id * 1000000L + 900000L
  model <- v2_fit_rf(x_train, outer_train[[columns$response]], selected, as.integer(context$config$model$outer_trees), outer_seed, v2_ranger_threads(context))
  predicted <- as.numeric(predict(model, data = x_test, num.threads = v2_ranger_threads(context))$predictions)
  group_match <- groups[match(outer_test[[columns$row_id]], groups$row_id), , drop = FALSE]
  predictions <- data.frame(
    task_id = task_id, repeat_id = repeat_id, outer_fold = outer_fold,
    row_id = outer_test[[columns$row_id]], site_id = outer_test[[columns$site_id]],
    branch_id = group_match$branch_id, terminal_component_id = group_match$terminal_component_id,
    longitude = outer_test[[columns$longitude]], latitude = outer_test[[columns$latitude]],
    reference_id = outer_test[[columns$reference]], observed = outer_test[[columns$response]],
    predicted = predicted, residual = predicted - outer_test[[columns$response]],
    assessment_eligible = TRUE, stringsAsFactors = FALSE
  )
  metrics <- cbind(
    data.frame(
      task_id = task_id, repeat_id = repeat_id, outer_fold = outer_fold,
      mtry = selected$mtry, min_node_size = selected$min_node_size,
      sample_fraction = selected$sample_fraction, replace = selected$replace,
      outer_trees = as.integer(context$config$model$outer_trees), seed = outer_seed,
      n_outer_analysis = length(outer_train_ids), n_outer_assessment = length(outer_test_ids),
      n_outer_purged = length(outer_purge_ids)
    ),
    v2_calculate_metrics(predictions$observed, predictions$predicted),
    v2_branch_macro_metrics(predictions$observed, predictions$predicted, predictions$branch_id)
  )
  medians_table <- data.frame(
    feature = predictors, training_median = as.numeric(medians[predictors]),
    n_missing_outer_train = vapply(outer_train[predictors], function(x) sum(is.na(x)), integer(1L))
  )
  v2_write_csv(predictions, file.path(output_dir, "outer_predictions.csv"))
  v2_write_csv(metrics, file.path(output_dir, "outer_metrics.csv"))
  v2_write_csv(v2_tail_metrics(predictions, "primary_outer"), file.path(output_dir, "outer_tail_metrics.csv"))
  v2_write_csv(v2_threshold_metrics(predictions, "primary_outer"), file.path(output_dir, "outer_threshold_metrics.csv"))
  v2_write_csv(medians_table, file.path(output_dir, "outer_training_medians.csv"))
  info <- list(
    status = "complete", task_id = task_id, repeat_id = repeat_id, outer_fold = outer_fold,
    n_outer_analysis = length(outer_train_ids), n_outer_assessment = length(outer_test_ids),
    n_outer_purged = length(outer_purge_ids), n_analysis_branches = length(train_branches),
    n_assessment_branches = length(test_branches), branch_leakage = 0L, downstream_purge_leakage = 0L,
    coarse_candidates = nrow(coarse_grid), refinement_candidates = nrow(refinement_grid),
    coarse_trees = as.integer(context$config$model$coarse_trees),
    refinement_trees = as.integer(context$config$model$refinement_trees),
    outer_trees = as.integer(context$config$model$outer_trees),
    config_md5 = fold_manifest$config$md5, seed = outer_seed,
    completed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
  v2_write_json(info, file.path(output_dir, "task_info.json"))
  v2_log("Primary task ", task_id, " complete: RMSE=", signif(metrics$rmse, 7), ".")
  invisible(info)
}

stage_run_all_primary <- function(context, force = FALSE) {
  manifest <- data.table::fread(v2_output_path(context, "validation_dir", "primary", "task_manifest.csv"), data.table = FALSE)
  for (i in seq_len(nrow(manifest))) stage_run_primary_task(context, manifest$repeat_id[[i]], manifest$outer_fold[[i]], force = force)
  invisible(manifest)
}
