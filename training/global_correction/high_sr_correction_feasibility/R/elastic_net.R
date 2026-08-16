corr_lambda_ratios <- function(context) {
  exp(seq(log(as.numeric(context$config$elastic_net$lambda_ratio_max)),
          log(as.numeric(context$config$elastic_net$lambda_ratio_min)),
          length.out = as.integer(context$config$elastic_net$lambda_ratio_count)))
}

corr_glmnet_path <- function(x, y, alpha, ratios, context) {
  pilot <- glmnet::glmnet(
    x = x, y = as.numeric(y), family = "gaussian", alpha = as.numeric(alpha),
    nlambda = length(ratios), lambda.min.ratio = min(ratios), intercept = TRUE,
    standardize = FALSE
  )
  lambda_max <- max(pilot$lambda)
  corr_assert(is.finite(lambda_max) && lambda_max > 0, "glmnet did not provide a finite positive lambda_max.")
  lambda <- lambda_max * ratios
  fit <- glmnet::glmnet(
    x = x, y = as.numeric(y), family = "gaussian", alpha = as.numeric(alpha),
    lambda = lambda, intercept = TRUE, standardize = FALSE
  )
  list(fit = fit, lambda_max = lambda_max, lambda = lambda)
}

corr_rank_elastic <- function(summary) {
  summary[order(summary$group_macro_mae, summary$station_mae, abs(summary$bias),
                summary$mean_active_coefficients, -summary$lambda_ratio, summary$alpha, summary$candidate_id), , drop = FALSE]
}

corr_tune_elastic <- function(meta, original, predictors, context) {
  ratios <- corr_lambda_ratios(context); alphas <- as.numeric(unlist(context$config$elastic_net$alpha))
  n_candidates <- length(ratios) * length(alphas)
  prediction_records <- vector("list", n_candidates); active_sum <- numeric(n_candidates); lambda_records <- list()
  inner_k <- as.integer(context$config$validation$inner_folds)
  for (assessment_fold in seq_len(inner_k)) {
    scoped <- meta[meta$correction_assessment_fold == assessment_fold & meta$oracle_elevated, , drop = FALSE]
    train <- scoped[scoped$role == "correction_train", , drop = FALSE]
    assessment <- scoped[scoped$role == "correction_assessment", , drop = FALSE]
    train <- cbind(train, original[match(train$row_id, original$row_id), predictors, drop = FALSE])
    assessment <- cbind(assessment, original[match(assessment$row_id, original$row_id), predictors, drop = FALSE])
    model_predictors <- c("base_prediction", predictors)
    matrices <- corr_prepare_matrices(train, assessment, model_predictors, standardize = TRUE,
      tolerance = as.numeric(context$config$elastic_net$zero_sd_tolerance))
    for (alpha_index in seq_along(alphas)) {
      alpha <- alphas[[alpha_index]]
      path <- corr_glmnet_path(matrices$train, train$residual_observed, alpha, ratios, context)
      predicted <- as.matrix(predict(path$fit, newx = matrices$assessment, s = path$lambda, type = "response"))
      coefficients <- as.matrix(stats::coef(path$fit, s = path$lambda))[-1L, , drop = FALSE]
      active <- colSums(abs(coefficients) > 0)
      corr_assert(ncol(predicted) == length(ratios), "glmnet prediction path length changed.")
      for (ratio_index in seq_along(ratios)) {
        candidate_id <- (alpha_index - 1L) * length(ratios) + ratio_index
        correction <- pmax(0, predicted[, ratio_index])
        record <- data.frame(
          candidate_id = candidate_id, alpha = alpha, lambda_ratio_index = ratio_index,
          lambda_ratio = ratios[[ratio_index]], correction_assessment_fold = assessment_fold,
          row_id = assessment$row_id, observed = assessment$observed,
          hydrological_group = assessment$hydrological_group, base_prediction = assessment$base_prediction,
          predicted_residual = predicted[, ratio_index], correction = correction,
          final_prediction = assessment$base_prediction + correction, stringsAsFactors = FALSE
        )
        prediction_records[[candidate_id]] <- rbind(prediction_records[[candidate_id]], record)
        active_sum[[candidate_id]] <- active_sum[[candidate_id]] + active[[ratio_index]]
      }
      lambda_records[[length(lambda_records) + 1L]] <- data.frame(
        correction_assessment_fold = assessment_fold, alpha = alpha, lambda_max = path$lambda_max,
        lambda_ratio_index = seq_along(ratios), lambda_ratio = ratios, lambda = path$lambda, stringsAsFactors = FALSE
      )
    }
  }
  summaries <- lapply(seq_len(n_candidates), function(candidate_id) {
    oof <- prediction_records[[candidate_id]]
    corr_assert(!anyDuplicated(oof$row_id), "Elastic Inner OOF contains duplicate rows.")
    metrics <- corr_system_metrics(oof$observed, oof$final_prediction, oof$hydrological_group)
    data.frame(candidate_id = candidate_id, alpha = oof$alpha[[1L]], lambda_ratio_index = oof$lambda_ratio_index[[1L]],
      lambda_ratio = oof$lambda_ratio[[1L]], group_macro_mae = metrics$group_macro_mae,
      station_mae = metrics$station_mae, rmse = metrics$rmse, bias = metrics$bias,
      mean_active_coefficients = active_sum[[candidate_id]] / inner_k, stringsAsFactors = FALSE)
  })
  summary <- corr_rank_elastic(do.call(rbind, summaries))
  winner <- summary[1L, , drop = FALSE]
  list(summary = summary, selected = winner, winner_oof = prediction_records[[winner$candidate_id]],
       lambda_diagnostics = do.call(rbind, lambda_records))
}

corr_fit_final_elastic <- function(train, assessment, predictors, selected, context) {
  model_predictors <- c("base_prediction", predictors)
  matrices <- corr_prepare_matrices(train, assessment, model_predictors, standardize = TRUE,
    tolerance = as.numeric(context$config$elastic_net$zero_sd_tolerance))
  ratios <- corr_lambda_ratios(context)
  path <- corr_glmnet_path(matrices$train, train$residual_observed, as.numeric(selected$alpha), ratios, context)
  ratio_index <- as.integer(selected$lambda_ratio_index)
  predicted <- as.numeric(predict(path$fit, newx = matrices$assessment, s = path$lambda[[ratio_index]], type = "response"))
  list(predicted_residual = predicted, correction = pmax(0, predicted), lambda_max = path$lambda_max,
       lambda = path$lambda[[ratio_index]], medians = matrices$medians, scaler = matrices$scaler)
}
