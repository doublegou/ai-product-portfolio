numeric_matrix_fit <- function(dat, predictors) {
  x <- dat[, predictors, drop=FALSE]
  bad <- predictors[!vapply(x, is.numeric, logical(1))]
  if (length(bad)) stop("All predictors must be numeric. Non-numeric: ", paste(bad, collapse=", "))
  med <- vapply(x, function(z) stats::median(z, na.rm=TRUE), numeric(1))
  med[!is.finite(med)] <- 0
  for (j in seq_along(x)) x[[j]][!is.finite(x[[j]])] <- med[[j]]
  list(x = as.matrix(x), medians = med, columns = predictors)
}

numeric_matrix_apply <- function(dat, prep) {
  x <- dat[, prep$columns, drop=FALSE]
  for (j in seq_along(x)) x[[j]][!is.finite(x[[j]])] <- prep$medians[[j]]
  as.matrix(x)
}

expand_model_grid <- function(cfg, algorithm) {
  g <- cfg$models[[algorithm]]
  if (algorithm == "RF") {
    return(expand.grid(num_trees=g$num_trees, mtry_fraction=g$mtry_fraction,
                       min_node_size=g$min_node_size, KEEP.OUT.ATTRS=FALSE))
  }
  if (algorithm == "Cubist") {
    return(expand.grid(committees=g$committees, neighbors=g$neighbors, KEEP.OUT.ATTRS=FALSE))
  }
  if (algorithm == "XGBoost") {
    return(expand.grid(nrounds=g$nrounds, max_depth=g$max_depth, eta=g$eta,
                       min_child_weight=g$min_child_weight, subsample=g$subsample,
                       colsample_bytree=g$colsample_bytree, KEEP.OUT.ATTRS=FALSE))
  }
  if (algorithm == "LLF") {
    return(expand.grid(num_trees=g$num_trees, mtry_fraction=g$mtry_fraction,
                       min_node_size=g$min_node_size, ll_lambda=g$ll_lambda,
                       KEEP.OUT.ATTRS=FALSE))
  }
  stop("Unknown algorithm: ", algorithm)
}

fit_one_model <- function(train, predictors, outcome, algorithm, params,
                          weights = NULL, threads = 1L, seed = 1L) {
  prep <- numeric_matrix_fit(train, predictors)
  X <- prep$x
  y <- train[[outcome]]
  if (is.null(weights)) weights <- rep(1, length(y))
  set.seed(seed)

  model <- switch(
    algorithm,
    RF = ranger::ranger(
      x = as.data.frame(X), y = y, case.weights = weights,
      num.trees = as.integer(params$num_trees),
      mtry = max(1L, round(ncol(X) * params$mtry_fraction)),
      min.node.size = as.integer(params$min_node_size),
      importance = "permutation", num.threads = threads, seed = seed
    ),
    Cubist = Cubist::cubist(
      x = as.data.frame(X), y = y, weights = weights,
      committees = as.integer(params$committees)
    ),
    XGBoost = {
      dtrain <- xgboost::xgb.DMatrix(X, label = y, weight = weights)
      xgboost::xgb.train(
        params = list(
          objective = "reg:squarederror", eval_metric = "rmse",
          max_depth = as.integer(params$max_depth), eta = params$eta,
          min_child_weight = params$min_child_weight,
          subsample = params$subsample,
          colsample_bytree = params$colsample_bytree,
          nthread = threads
        ),
        data = dtrain, nrounds = as.integer(params$nrounds), verbose = 0
      )
    },
    LLF = grf::ll_regression_forest(
      X = X, Y = y, num.trees = as.integer(params$num_trees),
      mtry = max(1L, round(ncol(X) * params$mtry_fraction)),
      min.node.size = as.integer(params$min_node_size),
      num.threads = threads, seed = seed
    ),
    stop("Unknown algorithm: ", algorithm)
  )
  structure(list(model=model, prep=prep, algorithm=algorithm, params=params), class="river_sr_model")
}

predict.river_sr_model <- function(object, newdata, ...) {
  X <- numeric_matrix_apply(newdata, object$prep)
  switch(
    object$algorithm,
    RF = as.numeric(predict(object$model, data=as.data.frame(X))$predictions),
    Cubist = as.numeric(predict(object$model, newdata=as.data.frame(X),
                                neighbors=as.integer(object$params$neighbors))),
    XGBoost = as.numeric(predict(object$model, xgboost::xgb.DMatrix(X))),
    LLF = {
      pp <- predict(object$model, newdata=X, ll.lambda=object$params$ll_lambda)
      if (is.list(pp) && "predictions" %in% names(pp)) as.numeric(pp$predictions) else as.numeric(pp)
    },
    stop("Unknown algorithm")
  )
}

inner_cv_metrics <- function(train, inner_folds, predictors, outcome, algorithm,
                             grid, cfg, weights = NULL, seed = 1L) {
  out <- list()
  for (p in seq_len(nrow(grid))) {
    params <- as.list(grid[p,,drop=FALSE])
    param_id <- paste0("p", p)
    for (f in sort(unique(inner_folds$fold))) {
      test_ids <- inner_folds$row_id[inner_folds$fold == f]
      tr <- train[!train$row_id %in% test_ids,,drop=FALSE]
      va <- train[train$row_id %in% test_ids,,drop=FALSE]
      w <- if (is.null(weights)) NULL else weights[match(tr$row_id, train$row_id)]
      fit <- fit_one_model(tr, predictors, outcome, algorithm, params, w,
                           cfg$project$threads, seed + p*100 + f)
      pred <- predict(fit, va)
      out[[length(out)+1L]] <- dplyr::bind_cols(
        tibble::tibble(param_id=param_id, fold=f),
        metric_row(va[[outcome]], pred, cfg$selection$high_threshold)
      )
    }
  }
  dplyr::bind_rows(out)
}

run_nested_cv <- function(dat, folds, predictors, outcome, algorithm, cfg,
                          case_weight_fun = NULL, seed = 1L) {
  grid <- expand_model_grid(cfg, algorithm)
  outer_predictions <- list()
  tuning_records <- list()
  outer_values <- sort(unique(folds$fold))

  for (outer_fold in outer_values) {
    log_msg("Algorithm=", algorithm, " outer fold=", outer_fold)
    test_ids <- folds$row_id[folds$fold == outer_fold]
    train <- dat[!dat$row_id %in% test_ids,,drop=FALSE]
    test <- dat[dat$row_id %in% test_ids,,drop=FALSE]

    inner <- make_spatial_folds(
      train, cfg$folds$inner_block_size_km, cfg$folds$n_folds,
      cfg$folds$equal_area_crs, seed + outer_fold,
      cfg$selection$high_threshold
    )
    all_weights <- if (is.null(case_weight_fun)) NULL else case_weight_fun(train)
    tune <- inner_cv_metrics(train, inner, predictors, outcome, algorithm, grid, cfg,
                             all_weights, seed + outer_fold*1000)
    best_id <- select_params_guardrail(tune, cfg$selection$rmse_tolerance_fraction)
    best_index <- as.integer(sub("^p","",best_id))
    best_params <- as.list(grid[best_index,,drop=FALSE])
    final_weights <- if (is.null(case_weight_fun)) NULL else case_weight_fun(train)
    fit <- fit_one_model(train, predictors, outcome, algorithm, best_params,
                         final_weights, cfg$project$threads, seed + outer_fold)
    pred <- predict(fit, test)
    outer_predictions[[length(outer_predictions)+1L]] <- test |>
      dplyr::transmute(row_id, observed=.data[[outcome]], predicted=pred,
                       outer_fold=outer_fold, algorithm=algorithm,
                       best_param_id=best_id)
    tuning_records[[length(tuning_records)+1L]] <- tune |>
      dplyr::mutate(outer_fold=outer_fold, algorithm=algorithm)
  }
  list(predictions=dplyr::bind_rows(outer_predictions),
       tuning=dplyr::bind_rows(tuning_records))
}
