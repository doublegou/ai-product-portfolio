corr_lambda_ratios <- function(context) {
  exp(seq(log(as.numeric(context$config$elastic_net$lambda_ratio_max)),
          log(as.numeric(context$config$elastic_net$lambda_ratio_min)),
          length.out = as.integer(context$config$elastic_net$lambda_ratio_count)))
}

corr_prepare_glmnet_design <- function(train, assessment, context) {
  train <- as.matrix(train); assessment <- as.matrix(assessment)
  storage.mode(train) <- "double"; storage.mode(assessment) <- "double"
  corr_assert(nrow(train) > 0L && nrow(assessment) > 0L, "glmnet design matrices must contain rows.")
  corr_assert(ncol(train) == ncol(assessment) && identical(colnames(train), colnames(assessment)), "glmnet train/assessment columns differ.")
  corr_assert(all(is.finite(train)) && all(is.finite(assessment)), "glmnet design contains non-finite values.")
  scientific_columns <- ncol(train)
  minimum <- as.integer(context$config$elastic_net$minimum_glmnet_columns)
  corr_assert(minimum == 2L, "The frozen glmnet minimum-column contract must equal two.")
  padding_added <- scientific_columns < minimum
  excluded <- integer(0L)
  if (padding_added) {
    corr_assert(scientific_columns == 1L, "Only the frozen one-predictor Elastic Net branch may receive padding.")
    dummy <- as.character(context$config$elastic_net$zero_dummy_column)
    corr_assert(nzchar(dummy) && !dummy %in% colnames(train), "Invalid or colliding glmnet zero-dummy column name.")
    train <- cbind(train, stats::setNames(data.frame(rep(0, nrow(train))), dummy))
    assessment <- cbind(assessment, stats::setNames(data.frame(rep(0, nrow(assessment))), dummy))
    train <- as.matrix(train); assessment <- as.matrix(assessment)
    storage.mode(train) <- "double"; storage.mode(assessment) <- "double"
    excluded <- ncol(train)
    corr_assert(all(train[, excluded] == 0) && all(assessment[, excluded] == 0), "glmnet dummy column must be identically zero.")
  }
  corr_assert(ncol(train) >= minimum && ncol(assessment) >= minimum, "glmnet design must have at least two columns.")
  list(train = train, assessment = assessment, exclude = as.integer(excluded),
       scientific_columns = scientific_columns, glmnet_columns = ncol(train), padding_added = padding_added)
}

corr_check_elastic_design_contract <- function(context) {
  one_train <- matrix(c(-1, 0, 1), ncol = 1L, dimnames = list(NULL, "base_prediction"))
  one_assessment <- matrix(c(-0.5, 0.5), ncol = 1L, dimnames = list(NULL, "base_prediction"))
  padded <- corr_prepare_glmnet_design(one_train, one_assessment, context)
  corr_assert(padded$scientific_columns == 1L && padded$glmnet_columns == 2L && isTRUE(padded$padding_added), "Single-predictor glmnet padding contract failed.")
  corr_assert(identical(padded$exclude, 2L) && identical(padded$train[, 1L], one_train[, 1L]), "Single-predictor glmnet exclusion contract failed.")
  corr_assert(all(padded$train[, 2L] == 0) && all(padded$assessment[, 2L] == 0), "Single-predictor glmnet dummy is not zero.")
  two_train <- cbind(a = c(-1, 0, 1), b = c(1, 0, -1))
  two_assessment <- cbind(a = c(-0.5, 0.5), b = c(0.5, -0.5))
  unchanged <- corr_prepare_glmnet_design(two_train, two_assessment, context)
  corr_assert(!unchanged$padding_added && unchanged$glmnet_columns == 2L && length(unchanged$exclude) == 0L, "Multi-predictor glmnet design must remain unchanged.")
  corr_assert(identical(unchanged$train, two_train) && identical(unchanged$assessment, two_assessment), "Multi-predictor glmnet values changed.")
  invisible(TRUE)
}

corr_glmnet_path <- function(x, y, alpha, ratios, context, exclude = integer(0L)) {
  corr_assert(is.matrix(x) && ncol(x) >= as.integer(context$config$elastic_net$minimum_glmnet_columns), "glmnet path received fewer than two columns.")
  pilot <- glmnet::glmnet(
    x = x, y = as.numeric(y), family = "gaussian", alpha = as.numeric(alpha),
    nlambda = length(ratios), lambda.min.ratio = min(ratios), intercept = TRUE,
    standardize = FALSE, exclude = as.integer(exclude)
  )
  lambda_max <- max(pilot$lambda)
  corr_assert(is.finite(lambda_max) && lambda_max > 0, "glmnet did not provide a finite positive lambda_max.")
  lambda <- lambda_max * ratios
  fit <- glmnet::glmnet(
    x = x, y = as.numeric(y), family = "gaussian", alpha = as.numeric(alpha),
    lambda = lambda, intercept = TRUE, standardize = FALSE, exclude = as.integer(exclude)
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
  design_contract <- NULL
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
    design <- corr_prepare_glmnet_design(matrices$train, matrices$assessment, context)
    current_contract <- c(design$scientific_columns, design$glmnet_columns, as.integer(design$padding_added), paste(design$exclude, collapse = "+"))
    if (is.null(design_contract)) design_contract <- current_contract else corr_assert(identical(design_contract, current_contract), "glmnet design contract changed across Inner folds.")
    for (alpha_index in seq_along(alphas)) {
      alpha <- alphas[[alpha_index]]
      path <- corr_glmnet_path(design$train, train$residual_observed, alpha, ratios, context, design$exclude)
      predicted <- as.matrix(predict(path$fit, newx = design$assessment, s = path$lambda, type = "response"))
      coefficients <- as.matrix(stats::coef(path$fit, s = path$lambda))[-1L, , drop = FALSE]
      scientific_rows <- rownames(coefficients) %in% colnames(matrices$train)
      active <- colSums(abs(coefficients[scientific_rows, , drop = FALSE]) > 0)
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
        lambda_ratio_index = seq_along(ratios), lambda_ratio = ratios, lambda = path$lambda,
        scientific_predictors = design$scientific_columns, glmnet_design_columns = design$glmnet_columns,
        glmnet_padding_added = design$padding_added, glmnet_excluded_columns = paste(design$exclude, collapse = "+"), stringsAsFactors = FALSE
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
      mean_active_coefficients = active_sum[[candidate_id]] / inner_k,
      scientific_predictors = as.integer(design_contract[[1L]]), glmnet_design_columns = as.integer(design_contract[[2L]]),
      glmnet_padding_added = as.logical(as.integer(design_contract[[3L]])), glmnet_excluded_columns = design_contract[[4L]], stringsAsFactors = FALSE)
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
  design <- corr_prepare_glmnet_design(matrices$train, matrices$assessment, context)
  ratios <- corr_lambda_ratios(context)
  path <- corr_glmnet_path(design$train, train$residual_observed, as.numeric(selected$alpha), ratios, context, design$exclude)
  ratio_index <- as.integer(selected$lambda_ratio_index)
  predicted <- as.numeric(predict(path$fit, newx = design$assessment, s = path$lambda[[ratio_index]], type = "response"))
  list(predicted_residual = predicted, correction = pmax(0, predicted), lambda_max = path$lambda_max,
       lambda = path$lambda[[ratio_index]], medians = matrices$medians, scaler = matrices$scaler,
       glmnet_padding_added = design$padding_added, glmnet_design_columns = design$glmnet_columns,
       glmnet_excluded_columns = paste(design$exclude, collapse = "+"))
}
