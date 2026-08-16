rrisk_environment_predictors <- function(context) {
  predictors <- rrisk_read_lines(rrisk_path(context, context$config$input$environment_predictors))
  rrisk_assert(length(predictors) == 14L && !anyDuplicated(predictors), "Regional Environment predictor manifest must contain 14 unique variables.")
  predictors
}

rrisk_validate_input <- function(context) {
  path <- rrisk_path(context, context$config$input$table)
  dat <- rrisk_read_csv(path)
  columns <- unlist(context$config$columns, use.names = TRUE)
  predictors <- rrisk_environment_predictors(context)
  required <- unique(c(unname(columns), predictors))
  missing <- setdiff(required, names(dat))
  rrisk_assert(length(missing) == 0L, paste("Himalaya Risk V1 table lacks:", paste(missing, collapse = ", ")))
  rrisk_assert(nrow(dat) == as.integer(context$config$domain$expected_rows), "Himalaya Risk V1 must contain exactly 372 rows.")
  row_id <- trimws(as.character(dat[[columns[["row_id"]]]]))
  site_id <- trimws(as.character(dat[[columns[["site_id"]]]]))
  observed <- as.numeric(dat[[columns[["response"]]]])
  label <- as.integer(dat[[columns[["label"]]]])
  rrisk_assert(!anyNA(row_id) && all(nzchar(row_id)) && !anyDuplicated(row_id), "Regional row_id must be complete and unique.")
  rrisk_assert(!anyNA(site_id) && all(nzchar(site_id)) && !anyDuplicated(site_id), "Regional site_id must be complete and unique.")
  rrisk_assert(all(is.finite(observed)), "Regional Sr response is incomplete.")
  rrisk_assert(all(label %in% 0:1), "high_sr_label must be binary.")
  rrisk_assert(identical(label, as.integer(observed >= as.numeric(context$config$domain$positive_lower))), "Stored high_sr_label differs from the frozen Sr threshold.")
  rrisk_assert(sum(label == 1L) == as.integer(context$config$domain$expected_positive_rows), "Regional positive count changed.")
  rrisk_assert(sum(label == 0L) == as.integer(context$config$domain$expected_negative_rows), "Regional negative count changed.")
  rrisk_assert(all(as.character(dat[[columns[["terminal_component_id"]]]]) == as.character(context$config$domain$terminal_component_id)), "Regional table crosses terminal components.")
  rrisk_assert(!anyNA(dat[[columns[["l12_id"]]]]), "Regional L12 membership is incomplete.")
  numeric_required <- unique(c(predictors, columns[["regional_x"]], columns[["regional_y"]]))
  non_numeric <- numeric_required[!vapply(dat[numeric_required], is.numeric, logical(1L))]
  rrisk_assert(length(non_numeric) == 0L, paste("Regional predictors must be numeric:", paste(non_numeric, collapse = ", ")))
  nonfinite <- numeric_required[vapply(dat[numeric_required], function(x) any(!is.na(x) & !is.finite(x)), logical(1L))]
  rrisk_assert(length(nonfinite) == 0L, paste("Regional predictors contain non-finite values:", paste(nonfinite, collapse = ", ")))
  rrisk_assert(length(intersect(predictors, c(columns[["longitude"]], columns[["latitude"]], "p0__sp_x", "p0__sp_y", "p0__sp_z"))) == 0L, "Absolute/global spatial coordinates entered Environment predictors.")
  dat[[columns[["row_id"]]]] <- row_id
  dat[[columns[["site_id"]]]] <- site_id
  dat$.observed <- observed
  dat$.label <- label
  list(
    data = dat, predictors = predictors, data_signature = rrisk_text_signature(path),
    config_signature = rrisk_text_signature(context$config_path),
    predictor_signature = rrisk_text_signature(rrisk_path(context, context$config$input$environment_predictors)),
    data_pipeline_config_signature = rrisk_text_signature(rrisk_path(context, context$config$input$data_pipeline_config))
  )
}

rrisk_assert_folds_current <- function(context) {
  paths <- rrisk_fold_paths(context)
  rrisk_assert(all(file.exists(paths)), "Regional Risk V1 folds are absent. Run --stage prepare locally before cluster training.")
  validated <- rrisk_validate_input(context)
  manifest <- jsonlite::read_json(paths[["manifest"]], simplifyVector = TRUE)
  rrisk_assert(identical(as.character(manifest$input$md5), as.character(validated$data_signature$md5)), "Himalaya Risk V1 data changed after folds were frozen.")
  rrisk_assert(identical(as.character(manifest$config$md5), as.character(validated$config_signature$md5)), "Regional Risk V1 config changed after folds were frozen.")
  rrisk_assert(identical(as.character(manifest$environment_predictors$md5), as.character(validated$predictor_signature$md5)), "Environment predictor manifest changed after folds were frozen.")
  rrisk_assert(identical(as.character(manifest$implementation$sha256), as.character(rrisk_implementation_signature(context)$sha256)), "Regional Risk V1 implementation changed after folds were frozen. Rebuild locally before cluster training.")
  branches <- rrisk_read_csv(paths[["branches"]])
  labels <- rrisk_read_csv(paths[["labels"]])
  lobo <- rrisk_read_csv(paths[["lobo"]])
  tasks <- rrisk_read_csv(paths[["tasks"]])
  rrisk_assert(nrow(branches) == 372L && !anyDuplicated(branches$row_id) && setequal(branches$row_id, validated$data[[context$config$columns$row_id]]), "Frozen branch map does not cover 372 rows exactly once.")
  rrisk_assert(length(unique(branches$regional_branch_id)) == 17L, "Frozen branch map does not contain 17 branches.")
  forbidden <- intersect(names(branches), c("sr87_sr86", "observed_sr", "high_sr_label", "positive", "reference_id"))
  rrisk_assert(length(forbidden) == 0L, "Response information entered branch_map.csv.")
  rrisk_assert(nrow(labels) == 17L && sum(labels$branch_class == "mixed") == 14L && sum(labels$branch_class == "all_negative") == 3L, "Frozen label audit changed.")
  rrisk_assert(nrow(lobo) == 372L * 17L, "LOBO assignment row count changed.")
  rrisk_assert(nrow(tasks) == 85L && setequal(tasks$task_id, 1:85), "Regional Risk V1 task manifest must contain IDs 1..85.")
  invisible(list(manifest = manifest, validated = validated, branches = branches, labels = labels, lobo = lobo, tasks = tasks))
}
