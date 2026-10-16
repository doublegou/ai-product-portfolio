stage_corr_build_tasks <- function(context, validated, force = FALSE) {
  paths <- corr_fold_paths(context)
  if (all(file.exists(paths)) && !force) {
    existing <- corr_assert_frozen_current(context)
    corr_log("Frozen correction task manifests already exist and remain current.")
    return(invisible(existing$manifest))
  }
  repeats <- as.integer(context$config$validation$repeats); outer_k <- as.integer(context$config$validation$outer_folds)
  base_tasks <- do.call(rbind, lapply(seq_len(repeats), function(repeat_id) data.frame(
    task_id = (repeat_id - 1L) * outer_k + seq_len(outer_k), repeat_id = repeat_id,
    outer_fold = seq_len(outer_k), expected_unique_base_fits = as.integer(context$config$validation$expected_unique_base_fits_per_outer),
    stringsAsFactors = FALSE
  )))
  correction_tasks <- do.call(rbind, lapply(c("elastic_net", "residual_rf"), function(model) {
    offset <- if (model == "elastic_net") 0L else nrow(base_tasks)
    data.frame(correction_task_id = offset + base_tasks$task_id, base_task_id = base_tasks$task_id,
      model = model, repeat_id = base_tasks$repeat_id, outer_fold = base_tasks$outer_fold, feature_sets = "basepred+env47+full50",
      stringsAsFactors = FALSE)
  }))
  fit_plan <- do.call(rbind, lapply(seq_len(nrow(base_tasks)), function(i) {
    task_id <- base_tasks$task_id[[i]]; repeat_id <- base_tasks$repeat_id[[i]]; outer_fold <- base_tasks$outer_fold[[i]]
    single <- data.frame(
      task_id = task_id, repeat_id = repeat_id, outer_fold = outer_fold, fit_type = "single_exclusion",
      fit_key = sprintf("single_%02d", seq_len(5L)), excluded_fold_low = seq_len(5L), excluded_fold_high = NA_integer_,
      seed = vapply(seq_len(5L), function(fold) corr_single_seed(context, task_id, fold), integer(1L)), stringsAsFactors = FALSE
    )
    pairs <- t(utils::combn(seq_len(5L), 2L))
    pair <- data.frame(
      task_id = task_id, repeat_id = repeat_id, outer_fold = outer_fold, fit_type = "pair_exclusion",
      fit_key = sprintf("pair_%02d_%02d", pairs[, 1L], pairs[, 2L]), excluded_fold_low = pairs[, 1L], excluded_fold_high = pairs[, 2L],
      seed = mapply(function(low, high) corr_pair_seed(context, task_id, low, high), pairs[, 1L], pairs[, 2L]), stringsAsFactors = FALSE
    )
    full <- data.frame(
      task_id = task_id, repeat_id = repeat_id, outer_fold = outer_fold, fit_type = "outer_full", fit_key = "outer_full",
      excluded_fold_low = NA_integer_, excluded_fold_high = NA_integer_, seed = corr_full_seed(context, task_id), stringsAsFactors = FALSE
    )
    rbind(single, pair, full)
  }))
  corr_write_csv(base_tasks, paths[["base_tasks"]])
  corr_write_csv(correction_tasks, paths[["correction_tasks"]])
  corr_write_csv(fit_plan, paths[["base_fit_plan"]])
  manifest <- list(
    status = "frozen", prepared_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    design = "three repeated grouped five-fold Outer evaluations with strict nested correction selection",
    base_tasks = nrow(base_tasks), correction_tasks = nrow(correction_tasks),
    unique_base_fits_per_outer = as.integer(context$config$validation$expected_unique_base_fits_per_outer),
    config = corr_text_signature(context$config_path), implementation = corr_implementation_signature(context), inputs = corr_signature_bundle(context),
    task_manifests = list(
      base = corr_text_signature(paths[["base_tasks"]]),
      correction = corr_text_signature(paths[["correction_tasks"]]),
      base_fit_plan = corr_text_signature(paths[["base_fit_plan"]])
    )
  )
  corr_write_json(manifest, paths[["manifest"]])
  corr_log("Frozen 15 Base tasks and 30 correction tasks; no model was fitted.")
  invisible(manifest)
}
