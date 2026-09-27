fa_validate_inputs <- function(context) {
  keys <- c("table", "branch_map", "full50_predictors", "process14_predictors", "outer_oof", "gate_metrics", "oof_manifest")
  signatures <- stats::setNames(lapply(keys, function(key) fa_signature(fa_path(context, context$config$input[[key]]))), keys)
  for (key in keys) signatures[[key]]$path <- context$config$input[[key]]
  expected <- unlist(context$config$input$expected_md5, use.names = TRUE)
  for (key in keys) fa_assert(identical(as.character(signatures[[key]]$md5), as.character(expected[[key]])), paste("Frozen input signature changed:", key))

  dat <- fa_read_csv(fa_path(context, context$config$input$table)); branches <- fa_read_csv(fa_path(context, context$config$input$branch_map)); oof <- fa_read_csv(fa_path(context, context$config$input$outer_oof))
  gate <- fa_read_csv(fa_path(context, context$config$input$gate_metrics)); oof_manifest <- jsonlite::read_json(fa_path(context, context$config$input$oof_manifest), simplifyVector = TRUE)
  fa_assert(identical(as.character(oof_manifest$run_id), as.character(context$config$input$expected_run_id)), "Outer OOF run ID is not the corrected frozen V2 run.")
  fa_assert(identical(as.character(oof_manifest$status), "complete") && identical(as.integer(oof_manifest$outer_oof_rows), 1488L), "Outer OOF manifest is incomplete.")
  fa_assert(!isTRUE(oof_manifest$full_data_model_fitted) && !isTRUE(oof_manifest$release_created), "Failure Audit requires a non-released V2 Gate experiment.")
  fa_assert(nrow(gate) == 4L && all(!as.logical(gate$gate_pass)), "Failure Audit requires four candidates with no complete Regional Gate pass.")
  full50 <- fa_read_lines(fa_path(context, context$config$input$full50_predictors)); process14 <- fa_read_lines(fa_path(context, context$config$input$process14_predictors)); full64 <- c(full50, process14)
  columns <- context$config$columns; required <- unique(c(unlist(columns, use.names = FALSE), full64))
  fa_assert(nrow(dat) == 372L && !length(setdiff(required, names(dat))), "Frozen V2 table shape or columns changed.")
  fa_assert(length(full50) == 50L && length(process14) == 14L && !anyDuplicated(full64), "Feature manifests must define 50 + 14 unique predictors.")
  fa_assert(all(vapply(dat[full64], is.numeric, logical(1L))) && !anyNA(dat[full64]) && all(vapply(dat[full64], function(x) all(is.finite(x)), logical(1L))), "Full64 predictors must be finite and complete.")

  fa_assert(nrow(branches) == 372L && !anyDuplicated(branches$row_id) && setequal(branches$row_id, dat[[columns$row_id]]), "Branch map does not cover the frozen table.")
  branches <- branches[match(dat[[columns$row_id]], branches$row_id), , drop = FALSE]
  dat$.regional_branch_id <- as.character(branches$regional_branch_id); dat$.branch_size <- as.integer(branches$branch_size)
  dat$.observed <- as.numeric(dat[[columns$response]]); dat$.label <- as.integer(dat[[columns$label]])
  fa_assert(sum(dat$.observed < as.numeric(context$config$domain$background_upper)) == 100L && sum(dat$.label == 1L) == 80L, "Frozen response strata changed.")
  dat$.branch_sqrt_weight <- (1 / sqrt(dat$.branch_size)) / mean(1 / sqrt(dat$.branch_size))

  primary <- context$config$failure_set$primary_candidate; primary_oof <- oof[oof$model_id == primary, , drop = FALSE]
  fa_assert(nrow(primary_oof) == 372L && !anyDuplicated(primary_oof$row_id) && setequal(primary_oof$row_id, dat[[columns$row_id]]), "Primary candidate Outer OOF is incomplete.")
  branch_positive <- tapply(primary_oof$high_sr_label == 1L, primary_oof$regional_branch_id, sum)
  branch_hits <- tapply(primary_oof$high_sr_label == 1L & as.logical(primary_oof$trigger), primary_oof$regional_branch_id, sum)
  missed_branches <- names(branch_positive)[branch_positive > 0 & branch_hits == 0]
  missed_ids <- primary_oof$row_id[primary_oof$regional_branch_id %in% missed_branches & primary_oof$high_sr_label == 1L]
  fa_assert(length(missed_branches) == as.integer(context$config$failure_set$expected_missed_branches), "Completely missed branch count changed.")
  fa_assert(length(missed_ids) == as.integer(context$config$failure_set$expected_missed_high_sr_sites), "Missed high-Sr site count changed.")
  dat$.failure_role <- ifelse(dat[[columns$row_id]] %in% missed_ids, "missed_high_sr", ifelse(dat$.observed < as.numeric(context$config$domain$background_upper), "background", "other"))
  list(data = dat, branches = branches, oof = oof, primary_oof = primary_oof, full50 = full50, process14 = process14, full64 = full64,
       missed_branches = missed_branches, missed_ids = missed_ids, signatures = signatures)
}
