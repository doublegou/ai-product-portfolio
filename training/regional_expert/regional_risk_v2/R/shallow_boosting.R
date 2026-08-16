rrisk2_fit_boost <- function(train_x, train_y, weights, seed, context) {
  cfg <- context$config$shallow_boosting
  matrix <- xgboost::xgb.DMatrix(train_x, label = as.numeric(train_y), weight = as.numeric(weights), feature_names = colnames(train_x))
  params <- list(
    objective = "binary:logistic", eval_metric = cfg$eval_metric, max_depth = as.integer(cfg$max_depth),
    eta = as.numeric(cfg$eta), min_child_weight = as.numeric(cfg$min_child_weight), subsample = as.numeric(cfg$subsample),
    colsample_bytree = as.numeric(cfg$colsample_bytree), lambda = as.numeric(cfg$lambda), alpha = as.numeric(cfg$alpha),
    gamma = as.numeric(cfg$gamma), base_score = as.numeric(cfg$base_score), nthread = as.integer(cfg$nthread), seed = as.integer(seed)
  )
  fit <- xgboost::xgb.train(params = params, data = matrix, nrounds = as.integer(cfg$nrounds), verbose = 0)
  list(engine = "shallow_boosting", fit = fit)
}

rrisk2_predict_boost <- function(model, new_x) as.numeric(predict(model$fit, xgboost::xgb.DMatrix(new_x, feature_names = colnames(new_x))))

rrisk2_importance_boost <- function(model, predictors) {
  raw <- xgboost::xgb.importance(feature_names = predictors, model = model$fit)
  result <- data.frame(feature = predictors, importance = 0, stringsAsFactors = FALSE)
  if (nrow(raw)) result$importance[match(raw$Feature, result$feature)] <- raw$Gain
  result
}

rrisk2_fit_model <- function(algorithm, train_x, train_y, weights, seed, context) {
  if (identical(algorithm, "probability_rf")) return(rrisk2_fit_rf(train_x, train_y, weights, seed, context))
  if (identical(algorithm, "shallow_boosting")) return(rrisk2_fit_boost(train_x, train_y, weights, seed, context))
  rrisk2_assert(FALSE, paste("Unknown algorithm:", algorithm))
}

rrisk2_predict_model <- function(model, new_x) {
  p <- if (identical(model$engine, "probability_rf")) rrisk2_predict_rf(model, new_x) else rrisk2_predict_boost(model, new_x)
  rrisk2_assert(length(p) == nrow(new_x) && all(is.finite(p)) && all(p >= 0 & p <= 1), "Invalid probability predictions.")
  p
}

rrisk2_importance_model <- function(model, predictors) {
  if (identical(model$engine, "probability_rf")) rrisk2_importance_rf(model, predictors) else rrisk2_importance_boost(model, predictors)
}
