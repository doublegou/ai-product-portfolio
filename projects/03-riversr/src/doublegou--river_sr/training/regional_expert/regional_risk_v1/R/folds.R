rrisk_branch_diagnostics <- function(branch_map) {
  do.call(rbind, lapply(split(branch_map, branch_map$regional_branch_id), function(x) data.frame(
    regional_branch_id = x$regional_branch_id[[1L]], branch_order = x$branch_order[[1L]],
    branch_outlet_l12_id = x$branch_outlet_l12_id[[1L]], n_stations = nrow(x),
    n_station_l12 = length(unique(x$station_l12_id)), stringsAsFactors = FALSE
  )))
}

rrisk_label_audit <- function(dat, branch_map, context) {
  labels <- dat[[context$config$columns$label]][match(branch_map$row_id, dat[[context$config$columns$row_id]])]
  rrisk_assert(!anyNA(labels), "Label audit join is incomplete.")
  audit <- do.call(rbind, lapply(split(seq_len(nrow(branch_map)), branch_map$regional_branch_id), function(index) {
    y <- as.integer(labels[index]); data.frame(
      regional_branch_id = branch_map$regional_branch_id[index[[1L]]], branch_order = branch_map$branch_order[index[[1L]]],
      n_stations = length(index), n_positive = sum(y == 1L), n_negative = sum(y == 0L),
      branch_class = if (all(y == 0L)) "all_negative" else if (all(y == 1L)) "all_positive" else "mixed",
      stringsAsFactors = FALSE
    )
  }))
  audit <- audit[order(audit$branch_order), , drop = FALSE]
  rrisk_assert(sum(audit$branch_class == "mixed") == as.integer(context$config$branches$expected_mixed_branches), "Mixed-branch count changed.")
  rrisk_assert(sum(audit$branch_class == "all_negative") == as.integer(context$config$branches$expected_all_negative_branches), "All-negative branch count changed.")
  rrisk_assert(sum(audit$branch_class == "all_positive") == as.integer(context$config$branches$expected_all_positive_branches), "All-positive branch count changed.")
  audit
}

rrisk_build_lobo_assignments <- function(branch_map) {
  records <- lapply(sort(unique(branch_map$branch_order)), function(fold) data.frame(
    outer_fold = as.integer(fold), heldout_branch = unique(branch_map$regional_branch_id[branch_map$branch_order == fold]),
    row_id = branch_map$row_id, regional_branch_id = branch_map$regional_branch_id,
    role = ifelse(branch_map$branch_order == fold, "assessment", "analysis"), stringsAsFactors = FALSE
  ))
  do.call(rbind, records)
}

rrisk_task_manifest <- function(context) {
  arms <- data.frame(
    model_type = c("gam", "gam", "gam", "elastic_net", "elastic_net"),
    feature_set = c("spatial_only", "environment", "combined", "environment", "combined"),
    model_id = c("gam_spatial_only", "gam_environment", "gam_combined", "elastic_environment", "elastic_combined"),
    stringsAsFactors = FALSE
  )
  tasks <- do.call(rbind, lapply(seq_len(nrow(arms)), function(i) cbind(
    arms[rep(i, as.integer(context$config$validation$expected_outer_folds)), , drop = FALSE],
    outer_fold = seq_len(as.integer(context$config$validation$expected_outer_folds)), stringsAsFactors = FALSE
  )))
  tasks$task_id <- seq_len(nrow(tasks))
  tasks[, c("task_id", "model_type", "feature_set", "model_id", "outer_fold")]
}

rrisk_build_inner_folds <- function(outer_train, outer_branch, context) {
  stats <- do.call(rbind, lapply(split(seq_len(nrow(outer_train)), outer_train$.regional_branch_id), function(index) data.frame(
    regional_branch_id = outer_train$.regional_branch_id[index[[1L]]], n_positive = sum(outer_train$.label[index] == 1L),
    n_negative = sum(outer_train$.label[index] == 0L), n_rows = length(index), stringsAsFactors = FALSE
  )))
  preferred <- c(as.integer(context$config$elastic_net$preferred_inner_folds), as.integer(context$config$elastic_net$fallback_inner_folds))
  base_seed <- as.integer(context$config$elastic_net$inner_seed_base) + sum(utf8ToInt(as.character(outer_branch)))
  for (k in preferred) {
    if (nrow(stats) < k) next
    for (attempt in 0:999) {
      set.seed(base_seed + k * 10000L + attempt)
      work <- stats; work$tie <- stats::runif(nrow(work))
      work <- work[order(-work$n_positive, -work$n_negative, -work$n_rows, work$tie), , drop = FALSE]
      fold_positive <- fold_negative <- fold_rows <- integer(k); assigned <- integer(nrow(work))
      for (i in seq_len(nrow(work))) {
        score <- data.frame(fold = seq_len(k), positive = fold_positive, negative = fold_negative, rows = fold_rows)
        candidates <- score$fold[order(score$positive, score$negative, score$rows)]
        chosen <- candidates[[1L]]; assigned[[i]] <- chosen
        fold_positive[[chosen]] <- fold_positive[[chosen]] + work$n_positive[[i]]
        fold_negative[[chosen]] <- fold_negative[[chosen]] + work$n_negative[[i]]
        fold_rows[[chosen]] <- fold_rows[[chosen]] + work$n_rows[[i]]
      }
      work$inner_fold <- assigned
      if (all(fold_positive > 0L) && all(fold_negative > 0L)) {
        branch_fold <- stats::setNames(work$inner_fold, work$regional_branch_id)
        result <- data.frame(
          row_id = outer_train[[context$config$columns$row_id]], regional_branch_id = outer_train$.regional_branch_id,
          inner_fold = as.integer(branch_fold[outer_train$.regional_branch_id]), stringsAsFactors = FALSE
        )
        rrisk_assert(!anyNA(result$inner_fold), "Elastic Inner assignments are incomplete.")
        return(list(assignments = result, k = k, seed = base_seed + k * 10000L + attempt, attempts = attempt + 1L))
      }
    }
  }
  stop("Could not construct grouped Elastic Inner folds with both classes in every assessment fold.", call. = FALSE)
}
