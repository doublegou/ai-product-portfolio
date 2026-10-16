risk_rf_grid <- function(context) {
  cfg <- context$config$probability_rf
  grid <- expand.grid(
    mtry = as.integer(unlist(cfg$mtry)), min_node_size = as.integer(unlist(cfg$min_node_size)),
    sample_fraction = as.numeric(unlist(cfg$sample_fraction)), replace = as.logical(unlist(cfg$replace)),
    KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE
  )
  grid <- grid[order(grid$mtry, -grid$min_node_size, grid$sample_fraction, grid$replace), , drop = FALSE]
  grid$candidate_id <- sprintf("rf_%02d", seq_len(nrow(grid)))
  grid[c("candidate_id", "mtry", "min_node_size", "sample_fraction", "replace")]
}

risk_ranger_threads <- function(context) {
  requested <- as.integer(context$config$model$threads)
  allocated <- suppressWarnings(as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", unset = NA_character_)))
  if (is.na(allocated) || allocated < 1L) requested else max(1L, min(requested, allocated))
}

risk_fit_probability_rf <- function(x, y, params, trees, seed, context) {
  outcome <- factor(ifelse(y, "positive", "negative"), levels = c("negative", "positive"))
  risk_assert(length(unique(outcome)) == 2L, "Probability RF training fold does not contain both classes.")
  frame <- data.frame(.outcome = outcome, x, check.names = FALSE)
  ranger::ranger(
    dependent.variable.name = ".outcome", data = frame, probability = TRUE,
    num.trees = as.integer(trees), mtry = as.integer(params$mtry),
    min.node.size = as.integer(params$min_node_size), sample.fraction = as.numeric(params$sample_fraction),
    replace = as.logical(params$replace), splitrule = context$config$probability_rf$splitrule,
    case.weights = NULL, seed = as.integer(seed), num.threads = risk_ranger_threads(context),
    write.forest = TRUE, importance = "none", verbose = FALSE
  )
}

risk_predict_probability_rf <- function(model, x, context) {
  predicted <- predict(model, data = x, num.threads = risk_ranger_threads(context))$predictions
  risk_assert(is.matrix(predicted) && "positive" %in% colnames(predicted), "Probability RF did not return a positive-class probability column.")
  as.numeric(predicted[, "positive"])
}

risk_run_rf_task <- function(dat, predictors, inner_design, outer_train_ids, outer_test_ids, task, context) {
  columns <- context$config$columns
  row_id <- columns$row_id
  grid <- risk_rf_grid(context)
  risk_assert(nrow(grid) == 24L, "Probability RF grid must contain 24 candidates.")
  analysis <- dat[match(outer_train_ids, dat[[row_id]]), , drop = FALSE]
  inner_design <- inner_design[match(analysis[[row_id]], inner_design$row_id), , drop = FALSE]
  risk_assert(identical(as.character(inner_design$row_id), as.character(analysis[[row_id]])), "RF Inner design order differs from Outer training rows.")
  prediction_store <- stats::setNames(lapply(seq_len(nrow(grid)), function(i) rep(NA_real_, nrow(analysis))), grid$candidate_id)
  inner_k <- as.integer(context$config$validation$inner_folds)
  inner_trees <- as.integer(context$config$probability_rf$inner_trees)
  for (candidate_index in seq_len(nrow(grid))) {
    params <- grid[candidate_index, , drop = FALSE]
    for (inner_fold in seq_len(inner_k)) {
      assessment_index <- which(inner_design$inner_fold == inner_fold)
      training_index <- setdiff(seq_len(nrow(analysis)), assessment_index)
      x_train_raw <- risk_numeric_predictors(analysis[training_index, , drop = FALSE], predictors)
      x_assess_raw <- risk_numeric_predictors(analysis[assessment_index, , drop = FALSE], predictors)
      medians <- risk_fit_medians(x_train_raw)
      x_train <- risk_apply_medians(x_train_raw, medians)
      x_assess <- risk_apply_medians(x_assess_raw, medians)
      seed <- as.integer(context$config$model$rf_seed_base) + as.integer(task$task_id) * 100000L + candidate_index * 100L + inner_fold
      model <- risk_fit_probability_rf(x_train, analysis$.positive[training_index], params, inner_trees, seed, context)
      prediction_store[[params$candidate_id]][assessment_index] <- risk_predict_probability_rf(model, x_assess, context)
    }
  }

  summaries <- vector("list", nrow(grid))
  for (candidate_index in seq_len(nrow(grid))) {
    params <- grid[candidate_index, , drop = FALSE]
    probability <- prediction_store[[params$candidate_id]]
    risk_assert(!anyNA(probability), paste("RF Inner OOF probabilities are incomplete for", params$candidate_id))
    summaries[[candidate_index]] <- risk_candidate_metrics(
      params$candidate_id, "probability_rf", analysis$.observed, probability, analysis$.hydrological_group,
      context, list(
        mtry = params$mtry, min_node_size = params$min_node_size,
        sample_fraction = params$sample_fraction, replace = params$replace
      )
    )
  }
  summary <- risk_rank_candidates(do.call(rbind, summaries), "probability_rf")
  winner <- summary[1L, , drop = FALSE]
  inner_probability <- prediction_store[[winner$candidate_id[[1L]]]]
  inner_winner <- data.frame(
    task_id = task$task_id, model = "probability_rf", repeat_id = task$repeat_id, outer_fold = task$outer_fold,
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
  outer_seed <- as.integer(context$config$model$rf_seed_base) + as.integer(task$task_id) * 100000L + 90000L
  model <- risk_fit_probability_rf(
    x_train, outer_train$.positive, winner, as.integer(context$config$probability_rf$outer_trees), outer_seed, context
  )
  probability <- risk_predict_probability_rf(model, x_test, context)
  triggered <- probability >= winner$threshold
  outer_predictions <- data.frame(
    task_id = task$task_id, model = "probability_rf", repeat_id = task$repeat_id, outer_fold = task$outer_fold,
    row_id = outer_test[[row_id]], site_id = outer_test[[columns$site_id]],
    hydrological_group = outer_test$.hydrological_group,
    longitude = outer_test[[columns$longitude]], latitude = outer_test[[columns$latitude]],
    reference_id = outer_test[[columns$reference]], observed = outer_test$.observed,
    probability = probability, threshold = winner$threshold, triggered = triggered,
    stringsAsFactors = FALSE
  )
  metrics <- cbind(
    data.frame(
      task_id = task$task_id, model = "probability_rf", repeat_id = task$repeat_id, outer_fold = task$outer_fold,
      mtry = winner$mtry, min_node_size = winner$min_node_size, sample_fraction = winner$sample_fraction,
      replace = winner$replace, threshold = winner$threshold, inner_gate_feasible = winner$inner_gate_feasible,
      threshold_selection_mode = winner$threshold_selection_mode, stringsAsFactors = FALSE
    ),
    risk_metrics_from_triggers(outer_test$.observed, probability, triggered, outer_test$.hydrological_group, context)
  )
  selected <- list(
    task_id = as.integer(task$task_id), model = "probability_rf", repeat_id = as.integer(task$repeat_id),
    outer_fold = as.integer(task$outer_fold), candidate_id = winner$candidate_id,
    mtry = as.integer(winner$mtry), min_node_size = as.integer(winner$min_node_size),
    sample_fraction = as.numeric(winner$sample_fraction), replace = as.logical(winner$replace),
    threshold = as.numeric(winner$threshold), inner_gate_feasible = as.logical(winner$inner_gate_feasible),
    threshold_selection_mode = winner$threshold_selection_mode, fallback_reason = winner$fallback_reason,
    selection_order = context$config$selection$between_candidate_order
  )
  list(
    candidate_summary = summary, inner_winner = inner_winner, outer_predictions = outer_predictions,
    outer_metrics = metrics, selected = selected, medians = medians, outer_seed = outer_seed
  )
}
