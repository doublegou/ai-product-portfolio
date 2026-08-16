corr_rf_mtry <- function(p) sort(unique(as.integer(pmax(1L, pmin(p, as.integer(round(c(sqrt(p), p / 4, p / 2))))))))

corr_residual_rf_grid <- function(p, context) {
  grid <- expand.grid(
    mtry = corr_rf_mtry(p), min_node_size = as.integer(unlist(context$config$residual_rf$min_node_size)),
    sample_fraction = as.numeric(unlist(context$config$residual_rf$sample_fraction)),
    KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE
  )
  grid$replace <- FALSE
  grid$candidate_id <- seq_len(nrow(grid))
  grid[c("candidate_id", "mtry", "min_node_size", "sample_fraction", "replace")]
}

corr_rank_residual_rf <- function(summary) {
  summary[order(summary$group_macro_mae, summary$station_mae, abs(summary$bias),
                -summary$min_node_size, summary$mtry, summary$sample_fraction, summary$candidate_id), , drop = FALSE]
}

corr_rf_inner_seed <- function(context, task_id, feature_id, candidate_id, inner_fold) {
  as.integer(context$config$residual_rf$inner_seed_base) + task_id * 10000L + feature_id * 1000L + candidate_id * 10L + inner_fold
}

corr_rf_outer_seed <- function(context, task_id, feature_id) {
  as.integer(context$config$residual_rf$outer_seed_base) + task_id * 100L + feature_id
}

corr_tune_residual_rf <- function(meta, original, predictors, context, task_id, feature_id) {
  model_predictors <- c("base_prediction", predictors)
  grid <- corr_residual_rf_grid(length(model_predictors), context)
  prediction_records <- vector("list", nrow(grid))
  inner_k <- as.integer(context$config$validation$inner_folds)
  for (assessment_fold in seq_len(inner_k)) {
    scoped <- meta[meta$correction_assessment_fold == assessment_fold & meta$oracle_elevated, , drop = FALSE]
    train <- scoped[scoped$role == "correction_train", , drop = FALSE]
    assessment <- scoped[scoped$role == "correction_assessment", , drop = FALSE]
    train <- cbind(train, original[match(train$row_id, original$row_id), predictors, drop = FALSE])
    assessment <- cbind(assessment, original[match(assessment$row_id, original$row_id), predictors, drop = FALSE])
    matrices <- corr_prepare_matrices(train, assessment, model_predictors, standardize = FALSE)
    for (candidate_row in seq_len(nrow(grid))) {
      parameters <- grid[candidate_row, , drop = FALSE]
      seed <- corr_rf_inner_seed(context, task_id, feature_id, parameters$candidate_id, assessment_fold)
      fit <- corr_fit_ranger(matrices$train, train$residual_observed, parameters,
        as.integer(context$config$residual_rf$inner_trees), seed, corr_threads(context), "variance")
      predicted <- corr_predict_ranger(fit, matrices$assessment, corr_threads(context))
      correction <- pmax(0, predicted)
      record <- data.frame(
        candidate_id = parameters$candidate_id, mtry = parameters$mtry, min_node_size = parameters$min_node_size,
        sample_fraction = parameters$sample_fraction, replace = parameters$replace,
        correction_assessment_fold = assessment_fold, row_id = assessment$row_id, observed = assessment$observed,
        hydrological_group = assessment$hydrological_group, base_prediction = assessment$base_prediction,
        predicted_residual = predicted, correction = correction, final_prediction = assessment$base_prediction + correction,
        seed = seed, stringsAsFactors = FALSE
      )
      prediction_records[[parameters$candidate_id]] <- rbind(prediction_records[[parameters$candidate_id]], record)
      rm(fit)
    }
  }
  summaries <- lapply(seq_len(nrow(grid)), function(candidate_id) {
    oof <- prediction_records[[candidate_id]]
    corr_assert(!anyDuplicated(oof$row_id), "RF Inner OOF contains duplicate rows.")
    metrics <- corr_system_metrics(oof$observed, oof$final_prediction, oof$hydrological_group)
    parameters <- grid[grid$candidate_id == candidate_id, , drop = FALSE]
    data.frame(candidate_id = candidate_id, mtry = parameters$mtry, min_node_size = parameters$min_node_size,
      sample_fraction = parameters$sample_fraction, replace = parameters$replace,
      group_macro_mae = metrics$group_macro_mae, station_mae = metrics$station_mae,
      rmse = metrics$rmse, bias = metrics$bias, stringsAsFactors = FALSE)
  })
  summary <- corr_rank_residual_rf(do.call(rbind, summaries))
  winner <- summary[1L, , drop = FALSE]
  list(summary = summary, selected = winner, winner_oof = prediction_records[[winner$candidate_id]], grid = grid)
}

corr_fit_final_residual_rf <- function(train, assessment, predictors, selected, context, task_id, feature_id) {
  model_predictors <- c("base_prediction", predictors)
  matrices <- corr_prepare_matrices(train, assessment, model_predictors, standardize = FALSE)
  seed <- corr_rf_outer_seed(context, task_id, feature_id)
  fit <- corr_fit_ranger(matrices$train, train$residual_observed, selected,
    as.integer(context$config$residual_rf$outer_trees), seed, corr_threads(context), "variance")
  predicted <- corr_predict_ranger(fit, matrices$assessment, corr_threads(context))
  list(predicted_residual = predicted, correction = pmax(0, predicted), seed = seed, medians = matrices$medians)
}
