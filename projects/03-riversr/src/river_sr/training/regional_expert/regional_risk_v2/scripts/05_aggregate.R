stage_rrisk2_aggregate <- function(context, run_id) {
  frozen <- rrisk2_assert_folds_current(context); rrisk2_begin_run(context, run_id, commandArgs(trailingOnly = TRUE))
  tasks <- frozen$tasks; incomplete <- vapply(seq_len(nrow(tasks)), function(i) !rrisk2_task_complete(rrisk2_task_dir(context, tasks$model_id[i], tasks$outer_fold[i])), logical(1L))
  rrisk2_assert(!any(incomplete), paste("Cannot aggregate; incomplete task IDs:", paste(tasks$task_id[incomplete], collapse = ", ")))
  predictions <- thresholds <- diagnostics <- importance <- vector("list", nrow(tasks))
  for (i in seq_len(nrow(tasks))) {
    path <- rrisk2_task_dir(context, tasks$model_id[i], tasks$outer_fold[i])
    predictions[[i]] <- rrisk2_read_csv(file.path(path, "outer_predictions.csv")); thresholds[[i]] <- rrisk2_read_csv(file.path(path, "threshold.csv"))
    diagnostics[[i]] <- rrisk2_read_csv(file.path(path, "fit_diagnostics.csv")); importance[[i]] <- rrisk2_read_csv(file.path(path, "variable_importance.csv"))
  }
  oof <- as.data.frame(data.table::rbindlist(predictions)); selected <- as.data.frame(data.table::rbindlist(thresholds)); fits <- as.data.frame(data.table::rbindlist(diagnostics)); vi <- as.data.frame(data.table::rbindlist(importance))
  expected_rows <- frozen$validated$data[[context$config$columns$row_id]]; candidates <- rrisk2_candidate_manifest()$model_id
  for (model in candidates) { x <- oof[oof$model_id == model, ]; rrisk2_assert(nrow(x) == 372L && !anyDuplicated(x$row_id) && setequal(x$row_id, expected_rows), paste("Incomplete outer OOF:", model)) }
  rrisk2_assert(nrow(oof) == 1488L && nrow(selected) == 68L && nrow(fits) == 1156L, "Aggregate counts differ from the frozen plan.")
  rrisk2_assert(all(is.finite(oof$probability)) && all(oof$probability >= 0 & oof$probability <= 1), "Aggregated probabilities are invalid.")
  oof <- oof[order(match(oof$model_id, candidates), oof$outer_fold, oof$row_id), ]
  gate_records <- ranking_records <- branch_records <- vector("list", length(candidates))
  for (i in seq_along(candidates)) {
    model <- candidates[i]; x <- oof[oof$model_id == model, ]
    gate_records[[i]] <- cbind(data.frame(model_id = model, stringsAsFactors = FALSE), rrisk2_apply_gate(rrisk2_gate_metrics(x, context), context))
    ranking_records[[i]] <- cbind(data.frame(model_id = model, stringsAsFactors = FALSE), rrisk2_probability_metrics(x, context))
    branch_records[[i]] <- cbind(data.frame(model_id = model, stringsAsFactors = FALSE), rrisk2_branch_metrics(x, context))
  }
  gate <- as.data.frame(data.table::rbindlist(gate_records)); ranking <- as.data.frame(data.table::rbindlist(ranking_records)); branch <- as.data.frame(data.table::rbindlist(branch_records))
  extreme <- oof[oof$observed_sr >= as.numeric(context$config$domain$extreme_lower), c("model_id", "outer_fold", "regional_branch_id", "row_id", "site_id", "observed_sr", "probability", "threshold", "trigger")]
  outputs <- list(oof_predictions = oof, gate_metrics = gate, ranking_metrics = ranking, branch_metrics = branch, extreme_audit = extreme,
                  selected_thresholds = selected, fit_diagnostics = fits, variable_importance = vi)
  validation_dir <- rrisk2_output_path(context, "validation_dir"); for (name in names(outputs)) rrisk2_write_csv(outputs[[name]], file.path(validation_dir, paste0(name, ".csv")))
  manifest <- list(status = "complete", run_id = run_id, aggregated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), tasks = 68L, candidates = 4L,
    outer_folds = 17L, inner_folds_per_task = 16L, model_fits = nrow(fits), thresholds = nrow(selected), outer_oof_rows = nrow(oof), calibration = "none",
    data_md5 = frozen$manifest$inputs$table$md5, config_md5 = frozen$manifest$config$md5, fold_manifest_md5 = rrisk2_text_signature(rrisk2_fold_paths(context)[["manifest"]])$md5,
    branch_sqrt_weighted_gate_metrics = TRUE, station_equal_ranking_metrics = TRUE, full_data_model_fitted = FALSE, release_created = FALSE)
  rrisk2_write_json(manifest, file.path(validation_dir, "oof_manifest.json")); reports <- rrisk2_run_dir(context, run_id, "reports")
  for (name in c("gate_metrics", "ranking_metrics", "branch_metrics", "extreme_audit", "selected_thresholds")) rrisk2_write_csv(outputs[[name]], file.path(reports, paste0(name, ".csv")))
  rrisk2_write_json(manifest, file.path(reports, "oof_manifest.json")); rrisk2_write_yaml(manifest, file.path(reports, "run_manifest.yml"))
  rrisk2_log("Aggregated 68 tasks into 1,488 strict outer OOF predictions."); invisible(list(gate = gate, ranking = ranking))
}
