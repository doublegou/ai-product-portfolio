rrisk11_environment_predictors <- function(context) {
  predictors <- rrisk11_read_lines(rrisk11_path(context, context$config$input$environment_predictors))
  rrisk11_assert(length(predictors) == 14L && !anyDuplicated(predictors), "Regional Risk V1.1 requires the 14 frozen V1 Environment predictors.")
  predictors
}

rrisk11_input_signatures <- function(context) {
  keys <- c("table", "v1_branch_map", "v1_fold_manifest", "v1_config", "environment_predictors")
  signatures <- stats::setNames(lapply(keys, function(key) rrisk11_text_signature(rrisk11_path(context, context$config$input[[key]]))), keys)
  expected <- unlist(context$config$input$expected_md5, use.names = TRUE)
  for (key in keys) {
    rrisk11_assert(
      identical(as.character(signatures[[key]]$md5), as.character(expected[[key]])),
      paste("Frozen upstream signature changed:", key)
    )
  }
  signatures
}

rrisk11_validate_input <- function(context) {
  signatures <- rrisk11_input_signatures(context)
  dat <- rrisk11_read_csv(rrisk11_path(context, context$config$input$table))
  branches <- rrisk11_read_csv(rrisk11_path(context, context$config$input$v1_branch_map))
  columns <- context$config$columns
  predictors <- rrisk11_environment_predictors(context)
  required <- unique(c(unlist(columns, use.names = FALSE), predictors, unlist(context$config$gam$smooth_predictors), unlist(context$config$gam$linear_predictors)))
  missing <- setdiff(required, names(dat))
  rrisk11_assert(length(missing) == 0L, paste("Himalaya Risk V1 table lacks:", paste(missing, collapse = ", ")))
  rrisk11_assert(nrow(dat) == as.integer(context$config$domain$expected_rows), "Regional Risk V1.1 must use exactly 372 frozen stations.")

  row_id <- trimws(as.character(dat[[columns$row_id]]))
  site_id <- trimws(as.character(dat[[columns$site_id]]))
  observed <- as.numeric(dat[[columns$response]])
  label <- as.integer(dat[[columns$label]])
  rrisk11_assert(!anyNA(row_id) && all(nzchar(row_id)) && !anyDuplicated(row_id), "row_id must be complete and unique.")
  rrisk11_assert(!anyNA(site_id) && all(nzchar(site_id)) && !anyDuplicated(site_id), "site_id must be complete and unique.")
  rrisk11_assert(all(is.finite(observed)), "Sr response contains non-finite values.")
  rrisk11_assert(all(label %in% 0:1), "high_sr_label must be binary.")
  rrisk11_assert(identical(label, as.integer(observed >= as.numeric(context$config$domain$positive_lower))), "Stored high_sr_label differs from Sr >= 0.75.")

  numeric_required <- unique(c(predictors, columns$regional_x, columns$regional_y))
  non_numeric <- numeric_required[!vapply(dat[numeric_required], is.numeric, logical(1L))]
  rrisk11_assert(length(non_numeric) == 0L, paste("GAM predictors must be numeric:", paste(non_numeric, collapse = ", ")))
  nonfinite <- numeric_required[vapply(dat[numeric_required], function(x) any(!is.na(x) & !is.finite(x)), logical(1L))]
  rrisk11_assert(length(nonfinite) == 0L, paste("GAM predictors contain non-finite values:", paste(nonfinite, collapse = ", ")))

  required_branch_columns <- c("row_id", "site_id", "regional_branch_id", "branch_order", "branch_size")
  rrisk11_assert(length(setdiff(required_branch_columns, names(branches))) == 0L, "Frozen V1 branch_map.csv lacks required columns.")
  forbidden <- intersect(names(branches), c("sr87_sr86", "observed_sr", "high_sr_label", "positive", "reference_id"))
  rrisk11_assert(length(forbidden) == 0L, "Response information entered the frozen V1 branch map.")
  rrisk11_assert(nrow(branches) == nrow(dat) && !anyDuplicated(branches$row_id) && setequal(branches$row_id, row_id), "Frozen V1 branch map must cover the 372 rows exactly once.")
  branches <- branches[match(row_id, branches$row_id), , drop = FALSE]
  rrisk11_assert(!anyNA(branches$row_id), "Branch-map join is incomplete.")
  rrisk11_assert(length(unique(branches$regional_branch_id)) == as.integer(context$config$domain$expected_branches), "Frozen V1 branch count changed.")
  rrisk11_assert(setequal(as.integer(unique(branches$branch_order)), seq_len(as.integer(context$config$domain$expected_branches))), "Frozen V1 branch order must be 1..17.")
  observed_sizes <- table(branches$regional_branch_id)
  rrisk11_assert(all(as.integer(observed_sizes[branches$regional_branch_id]) == as.integer(branches$branch_size)), "Frozen branch_size differs from branch membership.")

  background <- observed < as.numeric(context$config$domain$background_upper)
  positive <- observed >= as.numeric(context$config$domain$positive_lower)
  gray <- !background & !positive
  extreme <- observed >= as.numeric(context$config$domain$extreme_lower)
  expected_counts <- c(
    background = context$config$domain$expected_background_rows,
    gray = context$config$domain$expected_gray_rows,
    positive = context$config$domain$expected_positive_rows,
    extreme = context$config$domain$expected_extreme_rows
  )
  actual_counts <- c(background = sum(background), gray = sum(gray), positive = sum(positive), extreme = sum(extreme))
  rrisk11_assert(identical(as.integer(actual_counts), as.integer(expected_counts)), "Frozen Sr category counts changed.")
  positive_branches <- unique(branches$regional_branch_id[positive])
  extreme_branches <- unique(branches$regional_branch_id[extreme])
  rrisk11_assert(length(positive_branches) == as.integer(context$config$domain$expected_positive_branches), "Positive-branch count changed.")
  rrisk11_assert(length(extreme_branches) == as.integer(context$config$domain$expected_extreme_branches), "Extreme-branch count changed.")

  dat[[columns$row_id]] <- row_id
  dat[[columns$site_id]] <- site_id
  dat$.observed <- observed
  dat$.label <- label
  dat$.regional_branch_id <- as.character(branches$regional_branch_id)
  dat$.branch_order <- as.integer(branches$branch_order)
  raw_eval_weight <- 1 / sqrt(as.numeric(branches$branch_size))
  dat$.eval_weight <- raw_eval_weight / mean(raw_eval_weight)
  rrisk11_assert(abs(mean(dat$.eval_weight) - 1) < 1e-12, "Full-domain evaluation weights are not normalized to mean one.")

  list(
    data = dat, branches = branches, predictors = predictors, signatures = signatures,
    audit = list(
      rows = nrow(dat), branches = length(unique(dat$.regional_branch_id)),
      background = sum(background), gray = sum(gray), positive = sum(positive), extreme = sum(extreme),
      positive_branches = length(positive_branches), extreme_branches = length(extreme_branches)
    )
  )
}

rrisk11_task_manifest <- function(context) {
  arms <- data.frame(
    model_type = c("gam", "gam"), feature_set = c("environment", "combined"),
    model_id = c("gam_environment", "gam_combined"), stringsAsFactors = FALSE
  )
  tasks <- do.call(rbind, lapply(seq_len(nrow(arms)), function(i) cbind(
    arms[rep(i, as.integer(context$config$validation$outer_folds)), , drop = FALSE],
    outer_fold = seq_len(as.integer(context$config$validation$outer_folds)), stringsAsFactors = FALSE
  )))
  tasks$task_id <- seq_len(nrow(tasks))
  tasks[, c("task_id", "model_type", "feature_set", "model_id", "outer_fold")]
}

rrisk11_outer_assignments <- function(branches) {
  records <- lapply(sort(unique(branches$branch_order)), function(fold) {
    heldout <- unique(branches$regional_branch_id[branches$branch_order == fold])
    data.frame(
      outer_fold = as.integer(fold), heldout_branch = heldout, row_id = branches$row_id,
      regional_branch_id = branches$regional_branch_id,
      role = ifelse(branches$branch_order == fold, "assessment", "analysis"), stringsAsFactors = FALSE
    )
  })
  do.call(rbind, records)
}

rrisk11_assert_folds_current <- function(context) {
  paths <- rrisk11_fold_paths(context)
  rrisk11_assert(all(file.exists(paths)), "Regional Risk V1.1 folds are absent. Run --stage prepare locally before cluster training.")
  validated <- rrisk11_validate_input(context)
  manifest <- jsonlite::read_json(paths[["manifest"]], simplifyVector = TRUE)
  rrisk11_assert(identical(as.character(manifest$config$md5), as.character(rrisk11_text_signature(context$config_path)$md5)), "Regional Risk V1.1 config changed after prepare.")
  rrisk11_assert(identical(as.character(manifest$implementation$sha256), as.character(rrisk11_implementation_signature(context)$sha256)), "Regional Risk V1.1 implementation changed after prepare; rerun prepare locally.")
  for (key in names(validated$signatures)) {
    rrisk11_assert(identical(as.character(manifest$upstream[[key]]$md5), as.character(validated$signatures[[key]]$md5)), paste("Upstream changed after prepare:", key))
  }
  branches <- rrisk11_read_csv(paths[["branches"]])
  outer <- rrisk11_read_csv(paths[["outer"]])
  tasks <- rrisk11_read_csv(paths[["tasks"]])
  rrisk11_assert(nrow(branches) == 372L && !anyDuplicated(branches$row_id) && setequal(branches$row_id, validated$data[[context$config$columns$row_id]]), "Prepared branch snapshot is incomplete.")
  rrisk11_assert(nrow(outer) == 372L * 17L, "Outer assignment row count must be 6,324.")
  rrisk11_assert(nrow(tasks) == as.integer(context$config$validation$expected_tasks) && setequal(tasks$task_id, 1:34), "Task manifest must contain IDs 1..34.")
  rrisk11_assert(setequal(unique(tasks$model_id), c("gam_environment", "gam_combined")), "Only the two frozen V1 GAM candidates are allowed.")
  invisible(list(manifest = manifest, validated = validated, branches = branches, outer = outer, tasks = tasks))
}
