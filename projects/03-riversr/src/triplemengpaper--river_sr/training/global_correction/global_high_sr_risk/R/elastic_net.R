risk_lambda_ratios <- function(context) {
  cfg <- context$config$elastic_net
  exp(seq(
    log(as.numeric(cfg$lambda_ratio_max)), log(as.numeric(cfg$lambda_ratio_min)),
    length.out = as.integer(cfg$lambda_ratio_count)
  ))
}

risk_fit_elastic_grid <- function(x, y, alpha, lambda_ratios, context) {
  risk_assert(length(unique(y)) == 2L, "Elastic-net training fold does not contain both classes.")
  seed <- as.integer(context$config$model$elastic_seed_base)
  set.seed(seed)
  automatic <- glmnet::glmnet(
    x = as.matrix(x), y = as.integer(y), family = "binomial", alpha = as.numeric(alpha),
    nlambda = as.integer(context$config$elastic_net$lambda_ratio_count),
    lambda.min.ratio = as.numeric(context$config$elastic_net$lambda_ratio_min),
    standardize = isTRUE(context$config$elastic_net$standardize), intercept = TRUE
  )
  lambda_path_max <- as.numeric(automatic$lambda[[1L]])
  risk_assert(is.finite(lambda_path_max) && lambda_path_max > 0, "glmnet did not return a finite path upper bound.")
  lambda <- lambda_path_max * lambda_ratios
  fit <- glmnet::glmnet(
    x = as.matrix(x), y = as.integer(y), family = "binomial", alpha = as.numeric(alpha),
    lambda = lambda, standardize = isTRUE(context$config$elastic_net$standardize), intercept = TRUE
  )
  list(fit = fit, lambda_path_max = lambda_path_max, lambda = lambda)
}

risk_predict_elastic_grid <- function(fitted, x) {
  result <- predict(fitted$fit, newx = as.matrix(x), type = "response", s = fitted$lambda)
  result <- as.matrix(result)
  if (nrow(result) != nrow(x) && ncol(result) == nrow(x)) result <- t(result)
  risk_assert(nrow(result) == nrow(x), "glmnet prediction matrix has the wrong row count.")
  result
}

risk_run_elastic_task <- function(dat, predictors, inner_design, outer_train_ids, outer_test_ids, task, context) {
  columns <- context$config$columns
  row_id <- columns$row_id
  alphas <- as.numeric(unlist(context$config$elastic_net$alpha))
  ratios <- risk_lambda_ratios(context)
  analysis <- dat[match(outer_train_ids, dat[[row_id]]), , drop = FALSE]
  inner_design <- inner_design[match(analysis[[row_id]], inner_design$row_id), , drop = FALSE]
  risk_assert(identical(as.character(inner_design$row_id), as.character(analysis[[row_id]])), "Elastic Inner design order differs from Outer training rows.")
  predictions <- lapply(alphas, function(alpha) matrix(NA_real_, nrow = nrow(analysis), ncol = length(ratios)))
  path_diagnostics <- list()
  diagnostic_index <- 0L
  for (inner_fold in seq_len(as.integer(context$config$validation$inner_folds))) {
    assessment_index <- which(inner_design$inner_fold == inner_fold)
    training_index <- setdiff(seq_len(nrow(analysis)), assessment_index)
    x_train_raw <- risk_numeric_predictors(analysis[training_index, , drop = FALSE], predictors)
    x_assess_raw <- risk_numeric_predictors(analysis[assessment_index, , drop = FALSE], predictors)
    medians <- risk_fit_medians(x_train_raw)
    x_train <- risk_apply_medians(x_train_raw, medians)
    x_assess <- risk_apply_medians(x_assess_raw, medians)
    y_train <- analysis$.positive[training_index]
    for (alpha_index in seq_along(alphas)) {
      fitted <- risk_fit_elastic_grid(x_train, y_train, alphas[[alpha_index]], ratios, context)
      predictions[[alpha_index]][assessment_index, ] <- risk_predict_elastic_grid(fitted, x_assess)
      diagnostic_index <- diagnostic_index + 1L
      path_diagnostics[[diagnostic_index]] <- data.frame(
        inner_fold = inner_fold, alpha = alphas[[alpha_index]],
        lambda_path_max = fitted$lambda_path_max, stringsAsFactors = FALSE
      )
    }
  }

  summaries <- list()
  prediction_store <- list()
  index <- 0L
  for (alpha_index in seq_along(alphas)) {
    risk_assert(!anyNA(predictions[[alpha_index]]), "Elastic Inner OOF probability matrix is incomplete.")
    for (ratio_index in seq_along(ratios)) {
      index <- index + 1L
      candidate_id <- sprintf("en_a%02d_l%03d", alpha_index, ratio_index)
      probability <- predictions[[alpha_index]][, ratio_index]
      summaries[[index]] <- risk_candidate_metrics(
        candidate_id, "elastic_net", analysis$.observed, probability, analysis$.hydrological_group,
        context, list(alpha = alphas[[alpha_index]], lambda_ratio = ratios[[ratio_index]])
      )
      prediction_store[[candidate_id]] <- probability
    }
  }
  summary <- risk_rank_candidates(do.call(rbind, summaries), "elastic_net")
  winner <- summary[1L, , drop = FALSE]
  inner_probability <- prediction_store[[winner$candidate_id[[1L]]]]
  inner_winner <- data.frame(
    task_id = task$task_id, model = "elastic_net", repeat_id = task$repeat_id, outer_fold = task$outer_fold,
    row_id = analysis[[row_id]], hydrological_group = analysis$.hydrological_group,
    observed = analysis$.observed, probability = inner_probability,
    threshold = winner$threshold, triggered = inner_probability >= winner$threshold,
    stringsAsFactors = FALSE
  )

  outer_train <- analysis
  outer_test <- dat[match(outer_test_ids, dat[[row_id]]), , drop = FALSE]
  x_train_raw <- risk_numeric_predictors(outer_train, predictors)
  x_test_raw <- risk_numeric_predictors(outer_test, predictors)
  medians <- risk_fit_medians(x_train_raw)
  x_train <- risk_apply_medians(x_train_raw, medians)
  x_test <- risk_apply_medians(x_test_raw, medians)
  fitted <- risk_fit_elastic_grid(x_train, outer_train$.positive, winner$alpha, winner$lambda_ratio, context)
  probability <- as.numeric(risk_predict_elastic_grid(fitted, x_test)[, 1L])
  triggered <- probability >= winner$threshold
  outer_predictions <- data.frame(
    task_id = task$task_id, model = "elastic_net", repeat_id = task$repeat_id, outer_fold = task$outer_fold,
    row_id = outer_test[[row_id]], site_id = outer_test[[columns$site_id]],
    hydrological_group = outer_test$.hydrological_group,
    longitude = outer_test[[columns$longitude]], latitude = outer_test[[columns$latitude]],
    reference_id = outer_test[[columns$reference]], observed = outer_test$.observed,
    probability = probability, threshold = winner$threshold, triggered = triggered,
    stringsAsFactors = FALSE
  )
  metrics <- cbind(
    data.frame(
      task_id = task$task_id, model = "elastic_net", repeat_id = task$repeat_id, outer_fold = task$outer_fold,
      alpha = winner$alpha, lambda_ratio = winner$lambda_ratio, threshold = winner$threshold,
      inner_gate_feasible = winner$inner_gate_feasible, threshold_selection_mode = winner$threshold_selection_mode,
      stringsAsFactors = FALSE
    ),
    risk_metrics_from_triggers(outer_test$.observed, probability, triggered, outer_test$.hydrological_group, context)
  )
  selected <- list(
    task_id = as.integer(task$task_id), model = "elastic_net", repeat_id = as.integer(task$repeat_id),
    outer_fold = as.integer(task$outer_fold), candidate_id = winner$candidate_id,
    alpha = as.numeric(winner$alpha), lambda_ratio = as.numeric(winner$lambda_ratio),
    threshold = as.numeric(winner$threshold), inner_gate_feasible = as.logical(winner$inner_gate_feasible),
    threshold_selection_mode = winner$threshold_selection_mode, fallback_reason = winner$fallback_reason,
    selection_order = context$config$selection$between_candidate_order
  )
  list(
    candidate_summary = summary, inner_winner = inner_winner, outer_predictions = outer_predictions,
    outer_metrics = metrics, selected = selected, medians = medians,
    path_diagnostics = do.call(rbind, path_diagnostics)
  )
}
