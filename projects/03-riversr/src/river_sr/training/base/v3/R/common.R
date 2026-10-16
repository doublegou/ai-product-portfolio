v3_find_root <- function(start = getwd()) {
  current <- normalizePath(start, winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(current, "env", "renv.lock"))) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) stop("Cannot find RiverSR repository root.", call. = FALSE)
    current <- parent
  }
}

v3_activate <- function(root = v3_find_root()) {
  source(file.path(root, "env", "activate.R"), local = FALSE)
  river_sr_activate(root)
  invisible(root)
}

v3_assert <- function(ok, message) {
  if (!isTRUE(ok)) stop(message, call. = FALSE)
}

v3_context <- function(root = v3_find_root()) {
  v3_activate(root)
  config_path <- file.path(root, "training", "base", "v3", "config", "base_v3.yml")
  config <- yaml::read_yaml(config_path)
  v3_assert(requireNamespace("bit64", quietly = TRUE),
            "Base V3 requires package 'bit64'. Restore the frozen R environment before running.")
  list(
    root = root,
    config = config,
    config_path = config_path,
    base = file.path(root, "training", "base", "v3")
  )
}

v3_path <- function(context, relative) file.path(context$root, relative)

v3_threads <- function(context) {
  value <- suppressWarnings(as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", "")))
  if (!is.finite(value) || value < 1L) value <- as.integer(context$config$runtime$default_threads)
  max(1L, value)
}

v3_sha256 <- function(path) digest::digest(file = path, algo = "sha256", serialize = FALSE)

v3_sha256_text <- function(path) {
  size <- file.info(path)$size
  v3_assert(is.finite(size), paste("Cannot stat text input:", path))
  bytes <- readBin(path, what = "raw", n = size)
  if (length(bytes)) {
    values <- as.integer(bytes)
    next_is_lf <- c(values[-1L] == 10L, FALSE)
    crlf_cr <- values == 13L & next_is_lf
    lone_cr <- values == 13L & !crlf_cr
    values[lone_cr] <- 10L
    bytes <- as.raw(values[!crlf_cr])
  }
  digest::digest(bytes, algo = "sha256", serialize = FALSE)
}

v3_source_sha256 <- function(context) {
  files <- sort(c(
    list.files(file.path(context$base, "R"), pattern = "[.]R$", full.names = TRUE, recursive = TRUE),
    list.files(file.path(context$base, "scripts"), pattern = "[.]R$", full.names = TRUE, recursive = TRUE)
  ))
  hashes <- vapply(files, v3_sha256_text, character(1))
  digest::digest(paste(basename(files), hashes, sep = "=", collapse = "\n"), algo = "sha256", serialize = FALSE)
}

v3_atomic_fwrite <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- paste0(path, ".tmp-", Sys.getpid())
  data.table::fwrite(x, temporary)
  if (file.exists(path)) file.remove(path)
  v3_assert(file.rename(temporary, path), paste("Could not publish", path))
  invisible(path)
}

v3_atomic_json <- function(x, path, pretty = TRUE) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- paste0(path, ".tmp-", Sys.getpid())
  jsonlite::write_json(x, temporary, auto_unbox = TRUE, pretty = pretty, digits = NA, null = "null")
  if (file.exists(path)) file.remove(path)
  v3_assert(file.rename(temporary, path), paste("Could not publish", path))
  invisible(path)
}

v3_atomic_rds <- function(x, path, compress = "xz") {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- paste0(path, ".tmp-", Sys.getpid())
  saveRDS(x, temporary, compress = compress)
  if (file.exists(path)) file.remove(path)
  v3_assert(file.rename(temporary, path), paste("Could not publish", path))
  invisible(path)
}

v3_predictors <- function(context) {
  path <- v3_path(context, context$config$input$predictors)
  predictors <- trimws(readLines(path, warn = FALSE))
  predictors <- predictors[nzchar(predictors)]
  v3_assert(length(predictors) == context$config$contract$predictors, "Predictor manifest must contain 50 names.")
  v3_assert(!anyDuplicated(predictors), "Predictor manifest contains duplicates.")
  predictors
}

v3_read_training <- function(context) {
  path <- v3_path(context, context$config$input$training_csv)
  data <- data.table::fread(path)
  required <- unique(c(
    unlist(context$config$columns, use.names = FALSE),
    v3_predictors(context), "short_references", "source_datasets"
  ))
  missing <- setdiff(required, names(data))
  v3_assert(!length(missing), paste("Training table lacks:", paste(missing, collapse = ", ")))
  v3_assert(nrow(data) == context$config$contract$rows, "Training row-count contract failed.")
  id <- context$config$columns$id
  response <- context$config$columns$response
  v3_assert(!anyNA(data[[id]]) && !anyDuplicated(data[[id]]), "site_id must be complete and unique.")
  v3_assert(all(is.finite(data[[response]])), "Response contains non-finite values.")
  data
}

v3_sr_band <- function(y) {
  factor(
    ifelse(y < 0.72, "lt_072", ifelse(y < 0.75, "072_075", ifelse(y < 0.80, "075_080", "ge_080"))),
    levels = c("lt_072", "072_075", "075_080", "ge_080")
  )
}

v3_case_weights <- function(y, scheme, context) {
  band <- v3_sr_band(y)
  values <- as.numeric(unlist(context$config$weights[[scheme]], use.names = FALSE))
  v3_assert(length(values) == 4L, paste("Invalid weight scheme", scheme))
  values[as.integer(band)]
}

v3_read_main_basins <- function(context) {
  directory <- v3_path(context, context$config$input$hydrobasins_directory)
  archives <- sort(list.files(directory, pattern = "\\.zip$", full.names = TRUE))
  v3_assert(length(archives) == 9L, "Expected nine HydroBASINS level-6 archives.")
  parts <- lapply(archives, function(archive) {
    listing <- utils::unzip(archive, list = TRUE)
    dbf <- listing$Name[grepl("\\.dbf$", listing$Name, ignore.case = TRUE)]
    v3_assert(length(dbf) == 1L, paste("Expected one DBF in", basename(archive)))
    target <- tempfile("base-v3-hybas-")
    dir.create(target)
    utils::unzip(archive, files = dbf, exdir = target, junkpaths = TRUE)
    table <- foreign::read.dbf(file.path(target, basename(dbf)), as.is = TRUE)
    unlink(target, recursive = TRUE, force = TRUE)
    v3_assert(all(c("HYBAS_ID", "MAIN_BAS") %in% names(table)), paste("MAIN_BAS missing in", basename(archive)))
    data.table::data.table(
      basin_l6 = sprintf("%.0f", as.numeric(table$HYBAS_ID)),
      hydro_system_id = sprintf("%.0f", as.numeric(table$MAIN_BAS))
    )
  })
  mapping <- data.table::rbindlist(parts)
  v3_assert(!anyDuplicated(mapping$basin_l6), "HydroBASINS level-6 IDs are duplicated across archives.")
  mapping
}

v3_group_summary <- function(index, group_column = "hydro_system_id") {
  index[, .(
    n = .N,
    n_072 = sum(sr87_sr86 >= 0.72),
    n_075 = sum(sr87_sr86 >= 0.75),
    n_080 = sum(sr87_sr86 >= 0.80)
  ), by = group_column]
}

v3_balance_groups <- function(summary, group_column, folds, seed) {
  set.seed(seed)
  work <- data.table::copy(summary)
  work[, jitter := stats::runif(.N)]
  work[, priority := 1000 * (n_080 > 0) + 100 * (n_075 > 0) + 10 * (n_072 > 0) + log1p(n) + 0.25 * jitter]
  data.table::setorderv(work, c("priority", "jitter"), c(-1L, 1L))
  totals <- colSums(as.matrix(work[, .(n, n_072, n_075, n_080)]))
  targets <- totals / folds
  # Whole high-Sr systems can be large and cannot be split. Row balance is the
  # primary objective; tail counts are secondary diagnostics in the same score.
  importance <- c(n = 1000, n_072 = 1, n_075 = 1, n_080 = 1)
  loads <- matrix(0, nrow = folds, ncol = 4L, dimnames = list(NULL, names(importance)))
  assignment <- integer(nrow(work))
  for (i in seq_len(nrow(work))) {
    item <- as.numeric(work[i, .(n, n_072, n_075, n_080)])
    scores <- vapply(seq_len(folds), function(fold) {
      proposed <- loads[fold, ] + item
      sum(importance * (proposed / pmax(targets, 1))^2) + stats::runif(1L, 0, 1e-6)
    }, numeric(1))
    chosen <- which.min(scores)
    assignment[i] <- chosen
    loads[chosen, ] <- loads[chosen, ] + item
  }
  work[, fold := assignment]
  work[, c(group_column, "fold"), with = FALSE]
}

v3_rf_pool <- function(context) {
  cfg <- context$config$rf
  pool <- data.table::CJ(
    mtry = as.integer(unlist(cfg$mtry)),
    min_node_size = as.integer(unlist(cfg$min_node_size)),
    replace = as.logical(unlist(cfg$replace)),
    sample_fraction = as.numeric(unlist(cfg$sample_fraction)),
    sorted = TRUE
  )
  pool[, structure_id := sprintf("rf_%03d", .I)]
  data.table::setcolorder(pool, c("structure_id", setdiff(names(pool), "structure_id")))
  v3_assert(nrow(pool) == 378L, "RF pool must contain 378 structures.")
  pool
}

v3_xgb_pool <- function(context) {
  cfg <- context$config$xgb
  pool <- data.table::CJ(
    max_depth = as.integer(unlist(cfg$max_depth)),
    eta = as.numeric(unlist(cfg$eta)),
    min_child_weight = as.numeric(unlist(cfg$min_child_weight)),
    subsample = as.numeric(unlist(cfg$subsample)),
    colsample_bytree = as.numeric(unlist(cfg$colsample_bytree)),
    lambda = as.numeric(unlist(cfg$lambda)),
    alpha = as.numeric(unlist(cfg$alpha)),
    gamma = as.numeric(unlist(cfg$gamma)),
    sorted = TRUE
  )
  pool[, structure_id := sprintf("xgb_%04d", .I)]
  data.table::setcolorder(pool, c("structure_id", setdiff(names(pool), "structure_id")))
  v3_assert(nrow(pool) == 1728L, "XGBoost pool must contain 1,728 structures.")
  pool
}

v3_parameter_matrix <- function(pool) {
  columns <- setdiff(names(pool), "structure_id")
  matrix <- as.matrix(pool[, ..columns])
  storage.mode(matrix) <- "double"
  for (j in seq_len(ncol(matrix))) {
    span <- diff(range(matrix[, j]))
    matrix[, j] <- if (span == 0) 0 else (matrix[, j] - min(matrix[, j])) / span
  }
  matrix
}

v3_maximin <- function(pool, n, seed) {
  v3_assert(n <= nrow(pool), "Maximin request exceeds candidate pool.")
  matrix <- v3_parameter_matrix(pool)
  set.seed(seed)
  centre <- colMeans(matrix)
  distance_to_centre <- rowSums((matrix - matrix(centre, nrow(matrix), ncol(matrix), byrow = TRUE))^2)
  selected <- which.min(distance_to_centre + stats::runif(nrow(matrix), 0, 1e-8))
  minimum_distance <- rowSums(sweep(matrix, 2L, matrix[selected, ], "-")^2)
  while (length(selected) < n) {
    minimum_distance[selected] <- -Inf
    next_one <- which.max(minimum_distance + stats::runif(nrow(matrix), 0, 1e-10))
    selected <- c(selected, next_one)
    distance <- rowSums(sweep(matrix, 2L, matrix[next_one, ], "-")^2)
    minimum_distance <- pmin(minimum_distance, distance)
  }
  pool[selected]
}

v3_select_refinement <- function(pool, coarse_summary, n = 16L) {
  best_by_structure <- coarse_summary[order(selection_rank, candidate_id), .SD[1L], by = structure_id]
  anchors <- head(best_by_structure$structure_id, 4L)
  matrix <- v3_parameter_matrix(pool)
  rownames(matrix) <- pool$structure_id
  selected <- character()
  for (anchor in anchors) {
    distances <- rowSums(sweep(matrix, 2L, matrix[anchor, ], "-")^2)
    candidates <- names(sort(distances))
    for (candidate in candidates) {
      if (!candidate %in% selected) selected <- c(selected, candidate)
      if (length(selected) >= n) break
    }
    if (length(selected) >= n) break
  }
  if (length(selected) < n) {
    fill <- setdiff(pool$structure_id, selected)
    selected <- c(selected, head(fill, n - length(selected)))
  }
  pool[match(selected[seq_len(n)], structure_id)]
}

v3_fold_medians <- function(x) {
  medians <- apply(x, 2L, stats::median, na.rm = TRUE)
  v3_assert(all(is.finite(medians)), "At least one predictor has no finite analysis value.")
  medians
}

v3_apply_medians <- function(x, medians) {
  x <- as.matrix(x)
  storage.mode(x) <- "double"
  for (j in seq_len(ncol(x))) {
    bad <- !is.finite(x[, j])
    if (any(bad)) x[bad, j] <- medians[[j]]
  }
  x
}

v3_metrics <- function(observed, predicted, hydro_system_id) {
  keep <- is.finite(observed) & is.finite(predicted)
  observed <- observed[keep]
  predicted <- predicted[keep]
  hydro_system_id <- as.character(hydro_system_id[keep])
  error <- predicted - observed
  slope <- if (stats::sd(predicted) > 0) unname(stats::coef(stats::lm(observed ~ predicted))[[2L]]) else NA_real_
  high75_systems <- unique(hydro_system_id[observed >= 0.75])
  high80_systems <- unique(hydro_system_id[observed >= 0.80])
  detected75 <- unique(hydro_system_id[observed >= 0.75 & predicted >= 0.75])
  detected80 <- unique(hydro_system_id[observed >= 0.80 & predicted >= 0.80])
  low <- observed < 0.72
  band72 <- observed >= 0.72 & observed < 0.75
  band75 <- observed >= 0.75 & observed < 0.80
  extreme <- observed >= 0.80
  data.table::data.table(
    n = length(observed),
    rmse = sqrt(mean(error^2)),
    mae = mean(abs(error)),
    bias = mean(error),
    r2 = 1 - sum(error^2) / sum((observed - mean(observed))^2),
    calibration_slope = slope,
    prediction_min = min(predicted),
    prediction_max = max(predicted),
    low_rmse = sqrt(mean(error[low]^2)),
    false_high_low_count = sum(low & predicted >= 0.75),
    false_high_low_rate = mean(predicted[low] >= 0.75),
    hit_072_075_count = sum(band72 & predicted >= 0.72),
    hit_072_075_rate = mean(predicted[band72] >= 0.72),
    hit_075_080_count = sum(band75 & predicted >= 0.75),
    hit_075_080_rate = mean(predicted[band75] >= 0.75),
    hit_080_count = sum(extreme & predicted >= 0.80),
    hit_080_rate = mean(predicted[extreme] >= 0.80),
    hit_075_system_count = sum(high75_systems %in% detected75),
    hit_075_system_rate = mean(high75_systems %in% detected75),
    hit_080_system_count = sum(high80_systems %in% detected80),
    hit_080_system_rate = mean(high80_systems %in% detected80),
    high_median_bias = stats::median(error[observed >= 0.75]),
    extreme_prediction_median = stats::median(predicted[extreme])
  )
}

v3_rank_candidates <- function(summary, context) {
  result <- data.table::copy(summary)
  best_rmse <- min(result$rmse)
  tolerance <- as.numeric(context$config$validation$rmse_shortlist_fraction)
  result[, rmse_eligible := rmse <= best_rmse * (1 + tolerance)]
  data.table::setorderv(
    result,
    c("rmse_eligible", "hit_080_system_count", "hit_075_system_count", "hit_080_rate",
      "hit_075_080_rate", "hit_072_075_rate", "false_high_low_rate", "high_bias_abs",
      "bias_abs", "mae", "rmse", "candidate_id"),
    c(-1L, -1L, -1L, -1L, -1L, -1L, 1L, 1L, 1L, 1L, 1L, 1L)
  )
  result[, selection_rank := seq_len(.N)]
  result
}

v3_summarise_deployment_evidence <- function(structure_evidence) {
  required <- c("structure_id", "selection_rank")
  missing <- setdiff(required, names(structure_evidence))
  v3_assert(!length(missing), paste("Deployment evidence lacks:", paste(missing, collapse = ", ")))
  ranks <- as.double(structure_evidence$selection_rank)
  v3_assert(length(ranks) > 0L && all(is.finite(ranks)) && all(ranks >= 1),
            "Deployment evidence contains invalid selection ranks.")

  ranking <- structure_evidence[, {
    group_ranks <- as.double(selection_rank)
    .(
      tasks_evaluated = as.integer(.N),
      winner_count = as.integer(sum(group_ranks == 1)),
      median_rank = as.double(stats::median(group_ranks)),
      mean_rank_fraction = as.double(mean(group_ranks / max(group_ranks)))
    )
  }, by = structure_id]

  v3_assert(
    identical(typeof(ranking$tasks_evaluated), "integer") &&
      identical(typeof(ranking$winner_count), "integer") &&
      identical(typeof(ranking$median_rank), "double") &&
      identical(typeof(ranking$mean_rank_fraction), "double"),
    "Deployment ranking columns have unstable storage types."
  )
  ranking
}

v3_model_seed <- function(model, task, stage, candidate, fold = 0L) {
  model_offset <- if (model == "rf") 100000L else 200000L
  stage_offset <- switch(stage, coarse = 10000L, refinement = 20000L, outer = 30000L,
                         deployment = 40000L, stress = 50000L, final = 60000L, 0L)
  as.integer(model_offset + stage_offset + task * 1000L + candidate * 10L + fold)
}

v3_fit_predict <- function(model, parameters, analysis_x, analysis_y, assessment_x,
                           weights, context, stage, seed, trees = NULL,
                           xgb_rounds = NULL, smoke = FALSE) {
  medians <- v3_fold_medians(analysis_x)
  train_x <- v3_apply_medians(analysis_x, medians)
  test_x <- v3_apply_medians(assessment_x, medians)
  threads <- v3_threads(context)
  if (model == "rf") {
    fit <- ranger::ranger(
      x = as.data.frame(train_x), y = analysis_y,
      case.weights = weights,
      num.trees = as.integer(trees),
      mtry = as.integer(parameters$mtry),
      min.node.size = as.integer(parameters$min_node_size),
      replace = as.logical(parameters$replace),
      sample.fraction = as.numeric(parameters$sample_fraction),
      splitrule = "variance", num.threads = threads, seed = seed,
      write.forest = TRUE
    )
    return(list(prediction = as.numeric(stats::predict(fit, data = as.data.frame(test_x), num.threads = threads)$predictions),
                fit = fit, medians = medians, best_iteration = NA_integer_))
  }
  max_rounds <- if (smoke) as.integer(context$config$runtime$smoke_xgb_rounds) else as.integer(context$config$xgb$max_rounds)
  patience <- if (smoke) as.integer(context$config$runtime$smoke_early_stopping_rounds) else as.integer(context$config$xgb$early_stopping_rounds)
  if (!is.null(xgb_rounds)) max_rounds <- as.integer(xgb_rounds)
  dtrain <- xgboost::xgb.DMatrix(train_x, label = analysis_y, weight = weights)
  dtest <- xgboost::xgb.DMatrix(test_x)
  params <- list(
    objective = "reg:squarederror", eval_metric = "rmse",
    max_depth = as.integer(parameters$max_depth), eta = as.numeric(parameters$eta),
    min_child_weight = as.numeric(parameters$min_child_weight),
    subsample = as.numeric(parameters$subsample), colsample_bytree = as.numeric(parameters$colsample_bytree),
    lambda = as.numeric(parameters$lambda), alpha = as.numeric(parameters$alpha), gamma = as.numeric(parameters$gamma),
    tree_method = context$config$runtime$xgb_tree_method, nthread = threads, seed = seed
  )
  if (is.null(xgb_rounds)) {
    dvalid <- xgboost::xgb.DMatrix(test_x, label = rep(0, nrow(test_x)))
    xgboost::setinfo(dvalid, "label", rep(0, nrow(test_x)))
    # Validation labels are installed by the caller for tuning through assessment_y.
    stop("Internal error: XGBoost tuning requires v3_fit_xgb_validation().", call. = FALSE)
  }
  fit <- xgboost::xgb.train(params = params, data = dtrain, nrounds = max_rounds, verbose = 0)
  list(prediction = as.numeric(stats::predict(fit, dtest)), fit = fit, medians = medians, best_iteration = max_rounds)
}

v3_fit_xgb_validation <- function(parameters, analysis_x, analysis_y, assessment_x, assessment_y,
                                  weights, context, seed, smoke = FALSE) {
  medians <- v3_fold_medians(analysis_x)
  train_x <- v3_apply_medians(analysis_x, medians)
  test_x <- v3_apply_medians(assessment_x, medians)
  threads <- v3_threads(context)
  max_rounds <- if (smoke) as.integer(context$config$runtime$smoke_xgb_rounds) else as.integer(context$config$xgb$max_rounds)
  patience <- if (smoke) as.integer(context$config$runtime$smoke_early_stopping_rounds) else as.integer(context$config$xgb$early_stopping_rounds)
  dtrain <- xgboost::xgb.DMatrix(train_x, label = analysis_y, weight = weights)
  dvalid <- xgboost::xgb.DMatrix(test_x, label = assessment_y)
  params <- list(
    objective = "reg:squarederror", eval_metric = "rmse",
    max_depth = as.integer(parameters$max_depth), eta = as.numeric(parameters$eta),
    min_child_weight = as.numeric(parameters$min_child_weight),
    subsample = as.numeric(parameters$subsample), colsample_bytree = as.numeric(parameters$colsample_bytree),
    lambda = as.numeric(parameters$lambda), alpha = as.numeric(parameters$alpha), gamma = as.numeric(parameters$gamma),
    tree_method = context$config$runtime$xgb_tree_method, nthread = threads, seed = seed
  )
  fit <- xgboost::xgb.train(
    params = params, data = dtrain, nrounds = max_rounds,
    evals = list(validation = dvalid), early_stopping_rounds = patience,
    maximize = FALSE, verbose = 0
  )
  attributes <- xgboost::xgb.attributes(fit)
  best <- if (!is.null(attributes$best_iteration)) as.integer(attributes$best_iteration) + 1L else max_rounds
  list(prediction = as.numeric(stats::predict(fit, dvalid, iterationrange = c(1L, best))),
       fit = fit, medians = medians, best_iteration = best)
}

v3_evaluate_candidates <- function(model, candidates, data, index, fold_id, context, stage,
                                   checkpoint_path, smoke = FALSE, seed_task = 0L) {
  predictors <- v3_predictors(context)
  x <- as.matrix(data[, ..predictors])
  y <- as.numeric(index$sr87_sr86)
  systems <- index$hydro_system_id
  weight_names <- names(context$config$weights)
  existing <- if (file.exists(checkpoint_path)) data.table::fread(checkpoint_path) else data.table::data.table()
  complete <- if (nrow(existing)) existing$candidate_id else character()
  summaries <- if (nrow(existing)) list(existing) else list()
  trees <- if (smoke) as.integer(context$config$runtime$smoke_trees) else
    if (stage == "coarse") as.integer(context$config$rf$trees_coarse) else as.integer(context$config$rf$trees_refinement)

  for (structure_row in seq_len(nrow(candidates))) {
    parameters <- as.list(candidates[structure_row])
    structure_id <- as.character(parameters$structure_id)
    pool_index <- suppressWarnings(as.integer(gsub("[^0-9]", "", structure_id)))
    for (weight_name in weight_names) {
      candidate_id <- paste(structure_id, weight_name, sep = "__")
      if (candidate_id %in% complete) next
      prediction <- rep(NA_real_, nrow(data))
      best_iterations <- integer()
      for (fold in sort(unique(fold_id))) {
        analysis <- fold_id != fold
        assessment <- fold_id == fold
        weights <- v3_case_weights(y[analysis], weight_name, context)
        seed <- v3_model_seed(model, seed_task, stage, pool_index, fold)
        if (model == "rf") {
          fitted <- v3_fit_predict(
            model, parameters, x[analysis, , drop = FALSE], y[analysis], x[assessment, , drop = FALSE],
            weights, context, stage, seed, trees = trees, smoke = smoke
          )
        } else {
          fitted <- v3_fit_xgb_validation(
            parameters, x[analysis, , drop = FALSE], y[analysis], x[assessment, , drop = FALSE], y[assessment],
            weights, context, seed, smoke = smoke
          )
          best_iterations <- c(best_iterations, fitted$best_iteration)
        }
        prediction[assessment] <- fitted$prediction
      }
      v3_assert(all(is.finite(prediction)), paste("Incomplete pooled Inner OOF for", candidate_id))
      metric <- v3_metrics(y, prediction, systems)
      metric[, `:=`(
        model = model, stage = stage, structure_id = structure_id, weight_scheme = weight_name,
        candidate_id = candidate_id,
        best_iteration_median = if (length(best_iterations)) as.integer(round(stats::median(best_iterations))) else NA_integer_,
        bias_abs = abs(bias), high_bias_abs = abs(high_median_bias)
      )]
      parameter_names <- if (model == "rf") c("mtry", "min_node_size", "replace", "sample_fraction") else
        c("max_depth", "eta", "min_child_weight", "subsample", "colsample_bytree", "lambda", "alpha", "gamma")
      parameter_table <- data.table::as.data.table(parameters[parameter_names])
      metric <- cbind(metric, parameter_table)
      summaries[[length(summaries) + 1L]] <- metric
      current <- data.table::rbindlist(summaries, fill = TRUE)
      data.table::setorderv(current, "candidate_id")
      v3_atomic_fwrite(current, checkpoint_path)
      complete <- c(complete, candidate_id)
      message(sprintf("[%s/%s] %s complete (%d/%d)", model, stage, candidate_id,
                      length(unique(complete)), nrow(candidates) * length(weight_names)))
    }
  }
  result <- data.table::rbindlist(summaries, fill = TRUE)
  result <- unique(result, by = "candidate_id")
  result <- v3_rank_candidates(result, context)
  v3_atomic_fwrite(result, checkpoint_path)
  result
}

v3_fit_locked <- function(model, parameters, data, index, analysis, assessment, context,
                          stage, weight_scheme, trees = NULL, xgb_rounds = NULL, smoke = FALSE,
                          seed_task = 0L) {
  predictors <- v3_predictors(context)
  x <- as.matrix(data[, ..predictors])
  y <- index$sr87_sr86
  weights <- v3_case_weights(y[analysis], weight_scheme, context)
  seed <- v3_model_seed(model, seed_task, stage, 1L, 0L)
  v3_fit_predict(
    model, parameters, x[analysis, , drop = FALSE], y[analysis], x[assessment, , drop = FALSE],
    weights, context, stage, seed, trees = trees, xgb_rounds = xgb_rounds, smoke = smoke
  )
}

`%||%` <- function(left, right) if (is.null(left) || !length(left)) right else left

v3_parse_args <- function(args) {
  result <- list()
  i <- 1L
  while (i <= length(args)) {
    token <- args[[i]]
    if (startsWith(token, "--")) {
      key <- sub("^--", "", token)
      if (i == length(args) || startsWith(args[[i + 1L]], "--")) {
        result[[key]] <- TRUE
        i <- i + 1L
      } else {
        result[[key]] <- args[[i + 1L]]
        i <- i + 2L
      }
    } else {
      result[[length(result) + 1L]] <- token
      i <- i + 1L
    }
  }
  result
}

v3_run_dir <- function(context, run_id) {
  v3_assert(grepl("^[A-Za-z0-9._-]+$", run_id), "run_id contains unsafe characters.")
  file.path(context$base, "runs", run_id)
}

v3_task_coordinates <- function(task) {
  task <- as.integer(task)
  v3_assert(task >= 1L && task <= 15L, "Primary task must be 1..15.")
  list(task = task, repeat_id = (task - 1L) %/% 5L + 1L, outer_fold = (task - 1L) %% 5L + 1L)
}

v3_stress_coordinates <- function(task) {
  task <- as.integer(task)
  v3_assert(task >= 1L && task <= 20L, "Stress task must be 1..20.")
  schemes <- c("spatial_500", "spatial_1000", "spatial_1500", "reference")
  list(task = task, scheme = schemes[(task - 1L) %/% 5L + 1L], fold = (task - 1L) %% 5L + 1L)
}

v3_write_run_manifest <- function(context, run_id, extra = list()) {
  run_dir <- v3_run_dir(context, run_id)
  dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)
  manifest <- c(list(
    project = "base_v3",
    run_id = run_id,
    created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    config_sha256 = v3_sha256_text(context$config_path),
    source_sha256 = v3_source_sha256(context),
    training_sha256 = v3_sha256_text(v3_path(context, context$config$input$training_csv)),
    predictors_sha256 = v3_sha256_text(v3_path(context, context$config$input$predictors)),
    r_version = R.version.string
  ), extra)
  v3_atomic_json(manifest, file.path(run_dir, "run_manifest.json"))
  manifest
}

v3_verify_fold_manifest <- function(context) {
  path <- file.path(context$base, "folds", "manifest.json")
  v3_assert(file.exists(path), "Missing Base V3 fold manifest.")
  manifest <- jsonlite::read_json(path, simplifyVector = FALSE)
  v3_assert(identical(manifest$status, "validated"), "Fold manifest is not validated.")
  expected <- manifest$input
  v3_assert(identical(expected$training_sha256, v3_sha256_text(v3_path(context, context$config$input$training_csv))),
            "Training data hash differs from the frozen fold manifest.")
  v3_assert(identical(expected$config_sha256, v3_sha256_text(context$config_path)),
            "Base V3 config hash differs from the frozen fold manifest.")
  v3_assert(identical(expected$source_sha256, v3_source_sha256(context)),
            "Base V3 source hash differs from the frozen fold manifest; rerun prepare.")
  for (name in names(manifest$outputs)) {
    output <- manifest$outputs[[name]]
    output_path <- v3_path(context, output$path)
    v3_assert(file.exists(output_path), paste("Missing frozen fold artifact:", output$path))
    v3_assert(identical(output$sha256, v3_sha256(output_path)), paste("Fold artifact hash mismatch:", output$path))
  }
  invisible(TRUE)
}
