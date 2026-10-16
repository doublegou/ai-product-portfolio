rrisk2_input_signatures <- function(context) {
  keys <- c("table", "v1_branch_map", "full50_predictors", "process14_predictors", "process14_formula_dictionary")
  signatures <- stats::setNames(lapply(keys, function(key) rrisk2_text_signature(rrisk2_path(context, context$config$input[[key]]))), keys)
  expected <- unlist(context$config$input$expected_md5, use.names = TRUE)
  for (key in keys) rrisk2_assert(identical(as.character(signatures[[key]]$md5), as.character(expected[[key]])), paste("Frozen input signature changed:", key))
  signatures
}

rrisk2_validate_input <- function(context) {
  signatures <- rrisk2_input_signatures(context)
  dat <- rrisk2_read_csv(rrisk2_path(context, context$config$input$table))
  branches <- rrisk2_read_csv(rrisk2_path(context, context$config$input$v1_branch_map))
  columns <- context$config$columns
  full50 <- rrisk2_predictors(context, "full50"); full64 <- rrisk2_predictors(context, "full50_process")
  required <- unique(c(unlist(columns, use.names = FALSE), full64))
  rrisk2_assert(!length(setdiff(required, names(dat))), paste("V2 table lacks:", paste(setdiff(required, names(dat)), collapse = ", ")))
  rrisk2_assert(nrow(dat) == as.integer(context$config$domain$expected_rows), "V2 requires exactly 372 stations.")
  row_id <- trimws(as.character(dat[[columns$row_id]])); site_id <- trimws(as.character(dat[[columns$site_id]]))
  observed <- as.numeric(dat[[columns$response]]); label <- as.integer(dat[[columns$label]])
  rrisk2_assert(!anyNA(row_id) && all(nzchar(row_id)) && !anyDuplicated(row_id), "row_id must be complete and unique.")
  rrisk2_assert(!anyNA(site_id) && all(nzchar(site_id)) && !anyDuplicated(site_id), "site_id must be complete and unique.")
  rrisk2_assert(all(is.finite(observed)) && all(label %in% 0:1), "Response or label is invalid.")
  rrisk2_assert(identical(label, as.integer(observed >= as.numeric(context$config$domain$positive_lower))), "Stored label differs from Sr >= 0.75.")
  rrisk2_assert(all(vapply(dat[full64], is.numeric, logical(1L))) && !anyNA(dat[full64]), "All 64 predictors must be numeric and complete.")
  rrisk2_assert(all(vapply(dat[full64], function(x) all(is.finite(x)), logical(1L))), "Predictors contain non-finite values.")

  required_branch <- c("row_id", "site_id", "regional_branch_id", "branch_order", "branch_size")
  rrisk2_assert(!length(setdiff(required_branch, names(branches))), "V1 branch map lacks required columns.")
  rrisk2_assert(!length(intersect(names(branches), c("sr87_sr86", "observed_sr", "high_sr_label", "positive"))), "Response entered the branch map.")
  rrisk2_assert(nrow(branches) == nrow(dat) && !anyDuplicated(branches$row_id) && setequal(branches$row_id, row_id), "Branch map must cover all rows exactly once.")
  branches <- branches[match(row_id, branches$row_id), , drop = FALSE]
  rrisk2_assert(length(unique(branches$regional_branch_id)) == 17L && setequal(as.integer(unique(branches$branch_order)), 1:17), "Branch map must contain the 17 frozen branches.")
  sizes <- table(branches$regional_branch_id)
  rrisk2_assert(all(as.integer(sizes[branches$regional_branch_id]) == as.integer(branches$branch_size)), "Frozen branch sizes changed.")

  background <- observed < as.numeric(context$config$domain$background_upper)
  positive <- observed >= as.numeric(context$config$domain$positive_lower)
  gray <- !background & !positive; extreme <- observed >= as.numeric(context$config$domain$extreme_lower)
  actual <- c(sum(background), sum(gray), sum(positive), sum(extreme))
  expected <- as.integer(unlist(context$config$domain[c("expected_background_rows", "expected_gray_rows", "expected_positive_rows", "expected_extreme_rows")]))
  rrisk2_assert(identical(as.integer(actual), expected), "Frozen Sr stratum counts changed.")
  rrisk2_assert(length(unique(branches$regional_branch_id[positive])) == 14L, "Positive-branch count changed.")
  rrisk2_assert(length(unique(branches$regional_branch_id[extreme])) == 4L, "Extreme-system count changed.")

  dat[[columns$row_id]] <- row_id; dat[[columns$site_id]] <- site_id
  dat$.observed <- observed; dat$.label <- label; dat$.regional_branch_id <- as.character(branches$regional_branch_id); dat$.branch_order <- as.integer(branches$branch_order)
  raw_weight <- 1 / sqrt(as.numeric(branches$branch_size)); dat$.eval_weight <- raw_weight / mean(raw_weight)
  list(data = dat, branches = branches, signatures = signatures,
       audit = list(rows = nrow(dat), branches = 17L, background = sum(background), gray = sum(gray), positive = sum(positive), extreme = sum(extreme), positive_branches = 14L, extreme_branches = 4L))
}

rrisk2_candidate_manifest <- function() data.frame(
  algorithm = rep(c("probability_rf", "shallow_boosting"), each = 2L),
  feature_set = rep(c("full50", "full50_process"), 2L),
  model_id = c("probability_rf__full50", "probability_rf__full50_process", "shallow_boosting__full50", "shallow_boosting__full50_process"),
  stringsAsFactors = FALSE
)

rrisk2_task_manifest <- function(context) {
  arms <- rrisk2_candidate_manifest(); folds <- seq_len(as.integer(context$config$validation$outer_folds))
  tasks <- do.call(rbind, lapply(seq_len(nrow(arms)), function(i) cbind(arms[rep(i, length(folds)), , drop = FALSE], outer_fold = folds)))
  tasks$task_id <- seq_len(nrow(tasks)); tasks[, c("task_id", "algorithm", "feature_set", "model_id", "outer_fold")]
}

rrisk2_outer_assignments <- function(branches) do.call(rbind, lapply(1:17, function(fold) {
  heldout <- unique(branches$regional_branch_id[branches$branch_order == fold])
  data.frame(outer_fold = fold, heldout_branch = heldout, row_id = branches$row_id, regional_branch_id = branches$regional_branch_id,
             role = ifelse(branches$branch_order == fold, "assessment", "analysis"), stringsAsFactors = FALSE)
}))

rrisk2_fit_plan <- function(tasks) data.frame(task_id = tasks$task_id, model_id = tasks$model_id, outer_fold = tasks$outer_fold,
  inner_fits = 16L, outer_fits = 1L, total_fits = 17L, threshold_fits = 1L, calibration_fits = 0L, stringsAsFactors = FALSE)

rrisk2_assert_folds_current <- function(context) {
  paths <- rrisk2_fold_paths(context); rrisk2_assert(all(file.exists(paths)), "V2 folds are absent. Run --stage prepare locally.")
  validated <- rrisk2_validate_input(context); manifest <- jsonlite::read_json(paths[["manifest"]], simplifyVector = TRUE)
  rrisk2_assert(identical(as.character(manifest$config$md5), as.character(rrisk2_text_signature(context$config_path)$md5)), "V2 config changed after prepare.")
  rrisk2_assert(identical(as.character(manifest$implementation$sha256), as.character(rrisk2_implementation_signature(context)$sha256)), "V2 implementation changed after prepare; rerun prepare.")
  for (key in names(validated$signatures)) rrisk2_assert(identical(as.character(manifest$inputs[[key]]$md5), as.character(validated$signatures[[key]]$md5)), paste("Input changed after prepare:", key))
  branches <- rrisk2_read_csv(paths[["branches"]]); outer <- rrisk2_read_csv(paths[["outer"]]); tasks <- rrisk2_read_csv(paths[["tasks"]]); fits <- rrisk2_read_csv(paths[["fits"]])
  rrisk2_assert(nrow(branches) == 372L && nrow(outer) == 6324L && nrow(tasks) == 68L && nrow(fits) == 68L, "Prepared artifact counts are invalid.")
  rrisk2_assert(setequal(tasks$task_id, 1:68) && setequal(unique(tasks$model_id), rrisk2_candidate_manifest()$model_id), "Task manifest changed.")
  rrisk2_assert(sum(fits$total_fits) == 1156L && sum(fits$calibration_fits) == 0L, "Expected fit plan changed.")
  invisible(list(manifest = manifest, validated = validated, branches = branches, outer = outer, tasks = tasks, fits = fits))
}
