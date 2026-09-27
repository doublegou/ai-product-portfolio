risk_assign_inner_groups <- function(units, k, seed) {
  required <- c("validation_unit", "n_rows", "n_positive", "n_extreme")
  risk_assert(all(required %in% names(units)), "Inner units lack required balancing columns.")
  k <- as.integer(k)
  set.seed(as.integer(seed))
  units$.tie <- stats::runif(nrow(units))
  units$fold <- NA_integer_
  fold_rows <- rep(0L, k)
  fold_units <- rep(0L, k)
  fold_positive_rows <- rep(0L, k)
  fold_positive_groups <- rep(0L, k)

  positive_index <- which(units$n_positive > 0L)
  positive_index <- positive_index[order(
    -units$n_positive[positive_index], -units$n_extreme[positive_index],
    -units$n_rows[positive_index], units$.tie[positive_index]
  )]
  for (index in positive_index) {
    candidates <- which(fold_positive_groups == min(fold_positive_groups))
    candidates <- candidates[fold_positive_rows[candidates] == min(fold_positive_rows[candidates])]
    candidates <- candidates[fold_rows[candidates] == min(fold_rows[candidates])]
    chosen <- if (length(candidates) == 1L) candidates else sample(candidates, 1L)
    units$fold[[index]] <- chosen
    fold_rows[[chosen]] <- fold_rows[[chosen]] + units$n_rows[[index]]
    fold_units[[chosen]] <- fold_units[[chosen]] + 1L
    fold_positive_rows[[chosen]] <- fold_positive_rows[[chosen]] + units$n_positive[[index]]
    fold_positive_groups[[chosen]] <- fold_positive_groups[[chosen]] + 1L
  }

  background_index <- which(units$n_positive == 0L)
  background_index <- background_index[order(-units$n_rows[background_index], units$.tie[background_index])]
  for (index in background_index) {
    candidates <- which(fold_rows == min(fold_rows))
    candidates <- candidates[fold_units[candidates] == min(fold_units[candidates])]
    chosen <- if (length(candidates) == 1L) candidates else sample(candidates, 1L)
    units$fold[[index]] <- chosen
    fold_rows[[chosen]] <- fold_rows[[chosen]] + units$n_rows[[index]]
    fold_units[[chosen]] <- fold_units[[chosen]] + 1L
  }
  units$.tie <- NULL
  risk_assert(!anyNA(units$fold), "One or more hydrological systems were not assigned to an Inner fold.")
  units
}

risk_build_inner_folds <- function(validated, context) {
  dat <- validated$data
  outer <- validated$outer
  repeats <- as.integer(context$config$validation$repeats)
  outer_k <- as.integer(context$config$validation$outer_folds)
  inner_k <- as.integer(context$config$validation$inner_folds)
  records <- list()
  diagnostics <- list()
  index <- 0L
  diagnostic_index <- 0L
  for (repeat_id in seq_len(repeats)) {
    repeat_outer <- outer[outer$repeat_id == repeat_id, , drop = FALSE]
    for (outer_fold in seq_len(outer_k)) {
      outer_test_ids <- repeat_outer$row_id[repeat_outer$outer_fold == outer_fold]
      training <- dat[!dat[[context$config$columns$row_id]] %in% outer_test_ids, , drop = FALSE]
      units <- stats::aggregate(
        cbind(n_rows = rep(1L, nrow(training)), n_positive = as.integer(training$.positive), n_extreme = as.integer(training$.extreme)) ~ .hydrological_group,
        training, sum
      )
      names(units)[[1L]] <- "validation_unit"
      seed <- as.integer(context$config$validation$inner_seed_base) + repeat_id * 100L + outer_fold
      assigned <- risk_assign_inner_groups(units, inner_k, seed)
      inner <- merge(
        training[c(context$config$columns$row_id, ".hydrological_group")], assigned[c("validation_unit", "fold")],
        by.x = ".hydrological_group", by.y = "validation_unit", sort = FALSE
      )
      names(inner)[names(inner) == context$config$columns$row_id] <- "row_id"
      inner <- inner[match(training[[context$config$columns$row_id]], inner$row_id), , drop = FALSE]
      index <- index + 1L
      records[[index]] <- data.frame(
        row_id = inner$row_id, repeat_id = repeat_id, outer_fold = outer_fold,
        inner_fold = inner$fold, validation_unit = inner$.hydrological_group, stringsAsFactors = FALSE
      )
      for (inner_fold in seq_len(inner_k)) {
        assessment <- training[inner$fold == inner_fold, , drop = FALSE]
        diagnostic_index <- diagnostic_index + 1L
        diagnostics[[diagnostic_index]] <- data.frame(
          repeat_id = repeat_id, outer_fold = outer_fold, inner_fold = inner_fold,
          n_analysis = nrow(training) - nrow(assessment), n_assessment = nrow(assessment),
          n_assessment_groups = length(unique(assessment$.hydrological_group)),
          n_positive_rows = sum(assessment$.positive),
          n_positive_groups = length(unique(assessment$.hydrological_group[assessment$.positive])),
          n_extreme_rows = sum(assessment$.extreme),
          n_extreme_groups = length(unique(assessment$.hydrological_group[assessment$.extreme])),
          seed = seed, stringsAsFactors = FALSE
        )
      }
    }
  }
  list(inner = do.call(rbind, records), diagnostics = do.call(rbind, diagnostics))
}

risk_task_manifest <- function(context) {
  tasks <- expand.grid(
    outer_fold = seq_len(as.integer(context$config$validation$outer_folds)),
    repeat_id = seq_len(as.integer(context$config$validation$repeats)),
    model = c("elastic_net", "probability_rf"), KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE
  )
  tasks <- tasks[order(match(tasks$model, c("elastic_net", "probability_rf")), tasks$repeat_id, tasks$outer_fold), ]
  tasks$task_id <- seq_len(nrow(tasks))
  tasks[c("task_id", "model", "repeat_id", "outer_fold")]
}
