rrisk_gam_formula <- function(feature_set, context) {
  cfg <- context$config$gam
  smooth <- as.character(unlist(cfg$smooth_predictors))
  linear <- as.character(unlist(cfg$linear_predictors))
  environment_terms <- c(
    sprintf("s(%s, k = %d, bs = '%s')", smooth, as.integer(cfg$environment_k), as.character(cfg$environment_basis)),
    linear
  )
  spatial_term <- sprintf(
    "s(%s, %s, k = %d, bs = '%s')", context$config$columns$regional_x, context$config$columns$regional_y,
    as.integer(cfg$spatial_k), as.character(cfg$spatial_basis)
  )
  terms <- switch(feature_set,
    spatial_only = spatial_term,
    environment = environment_terms,
    combined = c(spatial_term, environment_terms),
    stop("Unsupported GAM feature set: ", feature_set, call. = FALSE)
  )
  stats::as.formula(paste(".label ~", paste(terms, collapse = " + ")))
}

rrisk_gam_predictors <- function(feature_set, context) {
  environment <- rrisk_environment_predictors(context)
  spatial <- c(context$config$columns$regional_x, context$config$columns$regional_y)
  switch(feature_set, spatial_only = spatial, environment = environment, combined = c(spatial, environment))
}

rrisk_run_gam <- function(outer_train, outer_test, task, context) {
  predictors <- rrisk_gam_predictors(task$feature_set[[1L]], context)
  train_raw <- rrisk_numeric_predictors(outer_train, predictors)
  test_raw <- rrisk_numeric_predictors(outer_test, predictors)
  medians <- rrisk_fit_medians(train_raw)
  outer_train[predictors] <- rrisk_apply_medians(train_raw, medians)
  outer_test[predictors] <- rrisk_apply_medians(test_raw, medians)
  warnings <- character()
  fitted <- withCallingHandlers(
    mgcv::gam(
      formula = rrisk_gam_formula(task$feature_set[[1L]], context), data = outer_train,
      weights = .weight, family = stats::binomial(), method = as.character(context$config$gam$method),
      select = isTRUE(context$config$gam$select), na.action = stats::na.fail
    ),
    warning = function(w) { warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning") }
  )
  probability <- as.numeric(stats::predict(fitted, newdata = outer_test, type = "response"))
  rrisk_assert(length(probability) == nrow(outer_test) && all(is.finite(probability)), "GAM returned incomplete probabilities.")
  summary_fit <- summary(fitted)
  diagnostics <- data.frame(
    model_type = "gam", feature_set = task$feature_set[[1L]], model_id = task$model_id[[1L]], outer_fold = task$outer_fold[[1L]],
    converged = isTRUE(fitted$converged), n_coefficients = length(stats::coef(fitted)),
    effective_df = sum(fitted$edf), deviance_explained = unname(summary_fit$dev.expl), aic = stats::AIC(fitted),
    warning_count = length(warnings), warnings = paste(unique(warnings), collapse = " | "),
    intercept_only = FALSE, selected_lambda = NA_real_, selected_alpha = NA_real_, inner_folds = NA_integer_,
    stringsAsFactors = FALSE
  )
  list(probability = probability, diagnostics = diagnostics, medians = medians, inner_assignments = NULL, selected = NULL)
}

rrisk_check_gam_interface <- function(context) {
  grid <- expand.grid(x_index = seq_len(8L), y_index = seq_len(6L))
  synthetic <- data.frame(
    .label = as.integer((grid$x_index + 2L * grid$y_index) %% 5L < 2L),
    .weight = 0.75 + ((seq_len(nrow(grid)) - 1L) %% 7L) / 10,
    stringsAsFactors = FALSE
  )
  synthetic[[context$config$columns$regional_x]] <- (grid$x_index - mean(grid$x_index)) * 40
  synthetic[[context$config$columns$regional_y]] <- (grid$y_index - mean(grid$y_index)) * 40
  task <- data.frame(
    feature_set = "spatial_only", model_id = "gam_spatial_contract", outer_fold = 0L,
    stringsAsFactors = FALSE
  )
  result <- rrisk_run_gam(synthetic[1:40, , drop = FALSE], synthetic[41:48, , drop = FALSE], task, context)
  rrisk_assert(length(result$probability) == 8L, "GAM interface contract returned an unexpected prediction count.")
  rrisk_assert(all(result$probability >= 0 & result$probability <= 1), "GAM interface contract returned invalid probabilities.")
  rrisk_assert(nrow(result$diagnostics) == 1L, "GAM interface contract did not return diagnostics.")
  invisible(TRUE)
}
