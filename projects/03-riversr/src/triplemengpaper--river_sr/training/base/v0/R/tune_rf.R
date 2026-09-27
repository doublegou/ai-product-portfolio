v0_tuning_grid <- function(p) {
  v0_require_packages("tidyr")
  mtry_values <- sort(unique(pmax(1L, pmin(p, as.integer(round(c(sqrt(p), p / 4, p / 2)))))))
  grid <- tidyr::expand_grid(
    mtry = mtry_values,
    min_node_size = c(5L, 15L),
    sample_fraction = c(0.70, 1.00)
  )
  grid$grid_id <- seq_len(nrow(grid))
  grid[c("grid_id", "mtry", "min_node_size", "sample_fraction")]
}

v0_ranger_threads <- function(context) {
  value <- suppressWarnings(as.integer(Sys.getenv(
    "SLURM_CPUS_PER_TASK", unset = as.character(context$config$model$threads)
  )))
  if (is.na(value) || value < 1L) 1L else value
}

v0_fit_rf <- function(x, y, parameters, trees, seed, threads, write_forest = TRUE) {
  ranger::ranger(
    x = x,
    y = as.numeric(y),
    num.trees = as.integer(trees),
    mtry = as.integer(parameters$mtry),
    min.node.size = as.integer(parameters$min_node_size),
    sample.fraction = as.numeric(parameters$sample_fraction),
    replace = FALSE,
    splitrule = "variance",
    importance = "none",
    num.threads = as.integer(threads),
    seed = as.integer(seed),
    write.forest = write_forest,
    verbose = FALSE
  )
}

v0_tune_outer_task <- function(dat, predictors, outer_train_ids, inner_design, context, task_id, trees) {
  columns <- context$config$columns
  row_column <- columns$row_id
  response <- columns$response
  grid <- v0_tuning_grid(length(predictors))
  inner_folds <- as.integer(context$config$validation$inner_folds)
  threads <- v0_ranger_threads(context)
  seed_base <- if (unique(inner_design$scheme) == "reference") {
    as.integer(context$config$model$reference_seed_base)
  } else {
    as.integer(context$config$model$spatial_seed_base)
  }
  records <- vector("list", nrow(grid) * inner_folds)
  index <- 0L

  for (grid_row in seq_len(nrow(grid))) {
    parameters <- grid[grid_row, , drop = FALSE]
    for (inner_fold in seq_len(inner_folds)) {
      validation_ids <- as.character(inner_design$row_id[inner_design$inner_fold == inner_fold])
      analysis_ids <- setdiff(outer_train_ids, validation_ids)
      analysis <- dat[match(analysis_ids, dat[[row_column]]), , drop = FALSE]
      assessment <- dat[match(validation_ids, dat[[row_column]]), , drop = FALSE]
      x_analysis_raw <- v0_numeric_predictors(analysis, predictors)
      x_assessment_raw <- v0_numeric_predictors(assessment, predictors)
      medians <- v0_fit_medians(x_analysis_raw)
      x_analysis <- v0_apply_medians(x_analysis_raw, medians)
      x_assessment <- v0_apply_medians(x_assessment_raw, medians)
      fit_seed <- seed_base + task_id * 1000L + parameters$grid_id[[1L]] * 10L + inner_fold
      model <- v0_fit_rf(
        x_analysis, analysis[[response]], parameters, trees, fit_seed, threads, write_forest = TRUE
      )
      prediction <- as.numeric(predict(model, data = x_assessment, num.threads = threads)$predictions)
      index <- index + 1L
      records[[index]] <- cbind(
        data.frame(
          task_id = task_id,
          grid_id = parameters$grid_id[[1L]],
          mtry = parameters$mtry[[1L]],
          min_node_size = parameters$min_node_size[[1L]],
          sample_fraction = parameters$sample_fraction[[1L]],
          inner_fold = inner_fold,
          n_analysis = nrow(analysis),
          n_validation = nrow(assessment),
          seed = fit_seed
        ),
        v0_calculate_metrics(assessment[[response]], prediction)
      )
    }
  }

  metrics <- do.call(rbind, records)
  groups <- split(metrics, metrics$grid_id)
  summary <- do.call(rbind, lapply(groups, function(x) data.frame(
    grid_id = x$grid_id[[1L]],
    mtry = x$mtry[[1L]],
    min_node_size = x$min_node_size[[1L]],
    sample_fraction = x$sample_fraction[[1L]],
    mean_rmse = mean(x$rmse),
    mean_mae = mean(x$mae),
    mean_r2 = mean(x$r2, na.rm = TRUE),
    mean_bias = mean(x$bias)
  )))
  summary <- summary[order(
    summary$mean_rmse,
    summary$mean_mae,
    -summary$mean_r2,
    summary$mtry,
    summary$min_node_size,
    summary$sample_fraction
  ), , drop = FALSE]
  summary$tuning_rank <- seq_len(nrow(summary))
  list(grid = grid, inner_metrics = metrics, summary = summary, selected = summary[1L, , drop = FALSE])
}
