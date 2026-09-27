rrisk2_fit_rf <- function(train_x, train_y, weights, seed, context) {
  cfg <- context$config$probability_rf
  p <- ncol(train_x); mtry <- max(1L, floor(sqrt(p)))
  frame <- as.data.frame(train_x); frame$.label <- factor(as.integer(train_y), levels = c(0L, 1L))
  fit <- ranger::ranger(
    .label ~ ., data = frame, probability = TRUE, case.weights = as.numeric(weights),
    num.trees = as.integer(cfg$num_trees), mtry = mtry, min.node.size = as.integer(cfg$min_node_size),
    sample.fraction = as.numeric(cfg$sample_fraction), replace = isTRUE(cfg$replace), splitrule = cfg$splitrule,
    importance = cfg$importance, num.threads = as.integer(cfg$num_threads), seed = as.integer(seed)
  )
  list(engine = "probability_rf", fit = fit, mtry = mtry)
}

rrisk2_predict_rf <- function(model, new_x) {
  p <- predict(model$fit, data = as.data.frame(new_x), num.threads = 1L)$predictions
  rrisk2_assert(is.matrix(p) && "1" %in% colnames(p), "RF probability output lacks positive class.")
  as.numeric(p[, "1"])
}

rrisk2_importance_rf <- function(model, predictors) data.frame(feature = predictors, importance = as.numeric(model$fit$variable.importance[predictors]), stringsAsFactors = FALSE)
