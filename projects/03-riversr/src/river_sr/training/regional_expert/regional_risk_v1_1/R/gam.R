rrisk11_gam_formula <- function(feature_set, context) {
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
  terms <- switch(
    feature_set,
    environment = environment_terms,
    combined = c(spatial_term, environment_terms),
    stop("Unsupported frozen V1.1 GAM feature set: ", feature_set, call. = FALSE)
  )
  stats::as.formula(paste(".label ~", paste(terms, collapse = " + ")))
}

rrisk11_gam_predictors <- function(feature_set, context) {
  environment <- rrisk11_environment_predictors(context)
  spatial <- c(context$config$columns$regional_x, context$config$columns$regional_y)
  switch(feature_set, environment = environment, combined = c(spatial, environment), stop("Unsupported feature set.", call. = FALSE))
}

rrisk11_fit_gam <- function(train, assessment, feature_set, context, outer_fold, inner_fold = NA_integer_) {
  predictors <- rrisk11_gam_predictors(feature_set, context)
  train <- rrisk11_add_fit_weights(train)
  train_raw <- rrisk11_numeric_predictors(train, predictors)
  assessment_raw <- rrisk11_numeric_predictors(assessment, predictors)
  medians <- rrisk11_fit_medians(train_raw)
  train[predictors] <- rrisk11_apply_medians(train_raw, medians)
  assessment[predictors] <- rrisk11_apply_medians(assessment_raw, medians)
  warnings <- character()
  fitted <- withCallingHandlers(
    mgcv::gam(
      formula = rrisk11_gam_formula(feature_set, context), data = train, weights = .fit_weight,
      family = stats::binomial(), method = as.character(context$config$gam$method),
      select = isTRUE(context$config$gam$select), na.action = stats::na.fail
    ),
    warning = function(w) { warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning") }
  )
  probability <- as.numeric(stats::predict(fitted, newdata = assessment, type = "response"))
  rrisk11_assert(length(probability) == nrow(assessment) && all(is.finite(probability)), "GAM returned incomplete probabilities.")
  rrisk11_assert(all(probability >= 0 & probability <= 1), "GAM returned probabilities outside [0,1].")
  summary_fit <- summary(fitted)
  diagnostics <- data.frame(
    outer_fold = as.integer(outer_fold), inner_fold = as.integer(inner_fold), fit_role = if (is.na(inner_fold)) "outer" else "inner",
    feature_set = feature_set, n_train = nrow(train), n_assessment = nrow(assessment),
    n_train_branches = length(unique(train$.regional_branch_id)), n_assessment_branches = length(unique(assessment$.regional_branch_id)),
    converged = isTRUE(fitted$converged), n_coefficients = length(stats::coef(fitted)), effective_df = sum(fitted$edf),
    deviance_explained = unname(summary_fit$dev.expl), aic = stats::AIC(fitted), warning_count = length(warnings),
    warnings = paste(unique(warnings), collapse = " | "), stringsAsFactors = FALSE
  )
  list(probability = probability, diagnostics = diagnostics, medians = medians)
}

rrisk11_check_gam_interface <- function(context) {
  n <- 112L
  synthetic <- data.frame(.label = as.integer((seq_len(n) %% 5L) < 2L), stringsAsFactors = FALSE)
  synthetic$.regional_branch_id <- sprintf("synthetic_%02d", rep(seq_len(7L), length.out = n))
  predictors <- unique(c(rrisk11_environment_predictors(context), context$config$columns$regional_x, context$config$columns$regional_y))
  for (j in seq_along(predictors)) synthetic[[predictors[[j]]]] <- sin(seq_len(n) / (3 + j)) + cos(seq_len(n) * (j + 1) / 37) + j / 10
  synthetic[[context$config$columns$regional_x]] <- rep(seq(-200, 200, length.out = 16L), 7L)
  synthetic[[context$config$columns$regional_y]] <- rep(seq(-120, 120, length.out = 7L), each = 16L)
  train <- synthetic[1:96, , drop = FALSE]
  assessment <- synthetic[97:112, , drop = FALSE]
  for (feature_set in c("environment", "combined")) {
    result <- rrisk11_fit_gam(train, assessment, feature_set, context, outer_fold = 0L)
    rrisk11_assert(length(result$probability) == 16L && nrow(result$diagnostics) == 1L, paste("Synthetic GAM contract failed:", feature_set))
  }
  invisible(TRUE)
}
