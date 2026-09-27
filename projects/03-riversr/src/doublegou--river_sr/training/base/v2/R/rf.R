v2_ranger_threads <- function(context) {
  value <- suppressWarnings(as.integer(Sys.getenv(
    "SLURM_CPUS_PER_TASK", unset = as.character(context$config$model$threads)
  )))
  if (is.na(value) || value < 1L) 1L else value
}

v2_coarse_grid <- function(p, context) {
  raw <- unlist(context$config$search$mtry_fractions)
  mtry_values <- vapply(raw, function(value) {
    if (identical(as.character(value), "sqrt")) sqrt(p) else as.numeric(value) * p
  }, numeric(1L))
  mtry_values <- sort(unique(pmax(1L, pmin(p, as.integer(round(mtry_values))))))
  grid <- tidyr::expand_grid(
    mtry = mtry_values,
    min_node_size = as.integer(unlist(context$config$search$min_node_size)),
    sample_fraction = as.numeric(unlist(context$config$search$sample_fraction)),
    replace = as.logical(unlist(context$config$search$replace))
  )
  grid <- as.data.frame(grid)
  grid$grid_id <- seq_len(nrow(grid))
  grid <- grid[c("grid_id", "mtry", "min_node_size", "sample_fraction", "replace")]
  v2_assert(nrow(grid) == 48L, paste("The formal V2 coarse grid must contain 48 recipes; found", nrow(grid)))
  grid
}

v2_fit_rf <- function(x, y, parameters, trees, seed, threads) {
  ranger::ranger(
    x = x,
    y = as.numeric(y),
    num.trees = as.integer(trees),
    mtry = as.integer(parameters$mtry),
    min.node.size = as.integer(parameters$min_node_size),
    sample.fraction = as.numeric(parameters$sample_fraction),
    replace = as.logical(parameters$replace),
    splitrule = "variance",
    importance = "none",
    num.threads = as.integer(threads),
    seed = as.integer(seed),
    write.forest = TRUE,
    verbose = FALSE
  )
}

v2_parameter_key <- function(x) {
  paste(
    as.integer(x$mtry), as.integer(x$min_node_size),
    format(as.numeric(x$sample_fraction), trim = TRUE, scientific = FALSE),
    tolower(as.character(as.logical(x$replace))), sep = "__"
  )
}

v2_recipe_md5 <- function(parameters) {
  payload <- list(
    mtry = as.integer(parameters$mtry),
    min_node_size = as.integer(parameters$min_node_size),
    sample_fraction = as.numeric(parameters$sample_fraction),
    replace = as.logical(parameters$replace)
  )
  digest::digest(jsonlite::toJSON(payload, auto_unbox = TRUE), algo = "md5", serialize = FALSE)
}

v2_evaluate_candidates <- function(
  dat, predictors, role_design, candidates, fold_column,
  trees, context, seed_base, task_id, stage
) {
  columns <- context$config$columns
  row_column <- columns$row_id
  response <- columns$response
  threads <- v2_ranger_threads(context)
  folds <- sort(unique(as.integer(role_design[[fold_column]])))
  v2_assert(length(folds) >= 2L && identical(folds, seq_len(length(folds))), paste("Invalid", stage, "fold labels."))
  candidate_id_column <- if ("candidate_id" %in% names(candidates)) "candidate_id" else "grid_id"
  fold_records <- vector("list", nrow(candidates) * length(folds))
  summaries <- vector("list", nrow(candidates))
  fold_index <- 0L
  stage_offset <- switch(stage, coarse = 100000L, refinement = 200000L, deployment = 300000L, 400000L)

  for (candidate_row in seq_len(nrow(candidates))) {
    parameters <- candidates[candidate_row, , drop = FALSE]
    candidate_id <- as.integer(parameters[[candidate_id_column]][[1L]])
    oof_observed <- numeric(0L)
    oof_predicted <- numeric(0L)
    oof_branch <- character(0L)
    for (fold in folds) {
      current_design <- role_design[role_design[[fold_column]] == fold, , drop = FALSE]
      fold_analysis_ids <- as.character(current_design$row_id[current_design$role == "analysis"])
      assessment_ids <- as.character(current_design$row_id[current_design$role == "assessment"])
      purged_ids <- as.character(current_design$row_id[current_design$role == "purged_downstream"])
      v2_assert(length(fold_analysis_ids) > 0L && length(assessment_ids) > 0L, paste(stage, "fold lacks analysis or assessment rows."))
      v2_assert(length(intersect(fold_analysis_ids, assessment_ids)) == 0L, paste(stage, "analysis and assessment overlap."))
      v2_assert(length(intersect(fold_analysis_ids, purged_ids)) == 0L, paste(stage, "analysis and downstream purge overlap."))
      analysis <- dat[match(fold_analysis_ids, dat[[row_column]]), , drop = FALSE]
      assessment <- dat[match(assessment_ids, dat[[row_column]]), , drop = FALSE]
      x_analysis_raw <- v2_numeric_predictors(analysis, predictors)
      x_assessment_raw <- v2_numeric_predictors(assessment, predictors)
      medians <- v2_fit_medians(x_analysis_raw)
      x_analysis <- v2_apply_medians(x_analysis_raw, medians)
      x_assessment <- v2_apply_medians(x_assessment_raw, medians)
      fit_seed <- as.integer(seed_base + task_id * 1000000L + stage_offset + candidate_id * 100L + fold)
      model <- v2_fit_rf(x_analysis, analysis[[response]], parameters, trees, fit_seed, threads)
      prediction <- as.numeric(predict(model, data = x_assessment, num.threads = threads)$predictions)
      fold_index <- fold_index + 1L
      fold_records[[fold_index]] <- cbind(
        data.frame(
          stage = stage, task_id = task_id, candidate_id = candidate_id,
          mtry = as.integer(parameters$mtry), min_node_size = as.integer(parameters$min_node_size),
          sample_fraction = as.numeric(parameters$sample_fraction), replace = as.logical(parameters$replace),
          fold = fold, n_analysis = nrow(analysis), n_assessment = nrow(assessment), n_purged = length(purged_ids),
          trees = as.integer(trees), seed = fit_seed
        ),
        v2_calculate_metrics(assessment[[response]], prediction)
      )
      oof_observed <- c(oof_observed, as.numeric(assessment[[response]]))
      oof_predicted <- c(oof_predicted, prediction)
      oof_branch <- c(oof_branch, as.character(current_design$branch_id[match(assessment_ids, current_design$row_id)]))
      rm(model)
    }
    pooled <- v2_calculate_metrics(oof_observed, oof_predicted)
    branch_macro <- v2_branch_macro_metrics(oof_observed, oof_predicted, oof_branch)
    threshold <- v2_threshold_metrics(data.frame(observed = oof_observed, predicted = oof_predicted))
    summaries[[candidate_row]] <- data.frame(
      candidate_id = candidate_id,
      source_grid_id = if ("grid_id" %in% names(parameters)) as.integer(parameters$grid_id) else NA_integer_,
      mtry = as.integer(parameters$mtry),
      min_node_size = as.integer(parameters$min_node_size),
      sample_fraction = as.numeric(parameters$sample_fraction),
      replace = as.logical(parameters$replace),
      pooled_rmse = pooled$rmse,
      branch_macro_rmse = branch_macro$branch_macro_rmse,
      branch_macro_mae = branch_macro$branch_macro_mae,
      pooled_mae = pooled$mae,
      pooled_r2 = pooled$r2,
      pooled_bias = pooled$bias,
      calibration_slope = pooled$calibration_slope,
      bias_ge_0_72 = threshold$bias[threshold$threshold == 0.72],
      bias_ge_0_75 = threshold$bias[threshold$threshold == 0.75],
      bias_ge_0_80 = threshold$bias[threshold$threshold == 0.80],
      stringsAsFactors = FALSE
    )
  }
  list(
    fold_metrics = do.call(rbind, fold_records),
    summary = v2_rank_summaries(do.call(rbind, summaries))
  )
}

v2_refinement_grid <- function(coarse_summary, context) {
  n <- as.integer(context$config$search$refinement_candidates)
  v2_assert(nrow(coarse_summary) >= n, "Coarse search did not produce enough candidates for refinement.")
  selected <- coarse_summary[seq_len(n), c(
    "source_grid_id", "mtry", "min_node_size", "sample_fraction", "replace"
  ), drop = FALSE]
  names(selected)[names(selected) == "source_grid_id"] <- "grid_id"
  selected$candidate_id <- seq_len(nrow(selected))
  selected <- selected[c("candidate_id", "grid_id", "mtry", "min_node_size", "sample_fraction", "replace")]
  selected
}
