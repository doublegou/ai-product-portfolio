rrisk_elastic_predictors <- function(feature_set, context) {
  environment <- rrisk_environment_predictors(context)
  if (identical(feature_set, "environment")) return(environment)
  if (identical(feature_set, "combined")) return(c(environment, context$config$columns$regional_x, context$config$columns$regional_y))
  stop("Unsupported Elastic feature set: ", feature_set, call. = FALSE)
}

rrisk_run_elastic <- function(outer_train, outer_test, task, context) {
  predictors <- rrisk_elastic_predictors(task$feature_set[[1L]], context)
  train_raw <- rrisk_numeric_predictors(outer_train, predictors)
  test_raw <- rrisk_numeric_predictors(outer_test, predictors)
  medians <- rrisk_fit_medians(train_raw)
  x_train <- as.matrix(rrisk_apply_medians(train_raw, medians))
  x_test <- as.matrix(rrisk_apply_medians(test_raw, medians))
  inner <- rrisk_build_inner_folds(outer_train, task$heldout_branch[[1L]], context)
  foldid <- inner$assignments$inner_fold[match(outer_train[[context$config$columns$row_id]], inner$assignments$row_id)]
  rrisk_assert(!anyNA(foldid), "Elastic Inner fold join is incomplete.")
  set.seed(inner$seed)
  warnings <- character()
  fitted <- withCallingHandlers(
    glmnet::cv.glmnet(
      x = x_train, y = outer_train$.label, weights = outer_train$.weight,
      family = "binomial", alpha = as.numeric(context$config$elastic_net$alpha), foldid = foldid,
      type.measure = as.character(context$config$elastic_net$type_measure),
      standardize = isTRUE(context$config$elastic_net$standardize), keep = TRUE, parallel = FALSE
    ),
    warning = function(w) { warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning") }
  )
  rrisk_assert(is.finite(fitted$lambda.1se) && fitted$lambda.1se > 0, "Elastic Net did not produce a finite lambda.1se.")
  probability <- as.numeric(stats::predict(fitted, newx = x_test, s = "lambda.1se", type = "response"))
  rrisk_assert(length(probability) == nrow(outer_test) && all(is.finite(probability)), "Elastic Net returned incomplete probabilities.")
  coefficient_matrix <- as.matrix(stats::coef(fitted, s = "lambda.1se"))
  rrisk_assert(nrow(coefficient_matrix) == ncol(x_train) + 1L, "Elastic coefficient vector has the wrong size.")
  nonzero <- sum(abs(coefficient_matrix[-1L, 1L]) > 0)
  diagnostics <- data.frame(
    model_type = "elastic_net", feature_set = task$feature_set[[1L]], model_id = task$model_id[[1L]], outer_fold = task$outer_fold[[1L]],
    converged = TRUE, n_coefficients = nonzero, effective_df = NA_real_, deviance_explained = NA_real_, aic = NA_real_,
    warning_count = length(warnings), warnings = paste(unique(warnings), collapse = " | "),
    intercept_only = nonzero == 0L, selected_lambda = as.numeric(fitted$lambda.1se),
    selected_alpha = as.numeric(context$config$elastic_net$alpha), inner_folds = inner$k,
    stringsAsFactors = FALSE
  )
  selected <- data.frame(
    model_id = task$model_id[[1L]], outer_fold = task$outer_fold[[1L]], alpha = as.numeric(context$config$elastic_net$alpha),
    alpha_status = as.character(context$config$elastic_net$alpha_status), lambda_min = as.numeric(fitted$lambda.min),
    lambda_1se = as.numeric(fitted$lambda.1se), selected = "lambda.1se", inner_folds = inner$k,
    inner_seed = inner$seed, inner_assignment_attempts = inner$attempts, nonzero_predictors = nonzero,
    stringsAsFactors = FALSE
  )
  list(probability = probability, diagnostics = diagnostics, medians = medians, inner_assignments = inner$assignments, selected = selected)
}
