stage_rrisk11_run_task <- function(context, task_id, force = FALSE) {
  frozen <- rrisk11_assert_folds_current(context)
  task_id <- as.integer(task_id)
  task <- frozen$tasks[frozen$tasks$task_id == task_id, , drop = FALSE]
  rrisk11_assert(nrow(task) == 1L, "task_id must resolve to exactly one Regional Risk V1.1 task in 1..34.")
  output_dir <- rrisk11_task_dir(context, task$model_id[[1L]], task$outer_fold[[1L]])
  fold_manifest_md5 <- rrisk11_text_signature(rrisk11_fold_paths(context)[["manifest"]])$md5
  if (rrisk11_task_complete(output_dir) && !force) {
    info <- jsonlite::read_json(file.path(output_dir, "task_info.json"), simplifyVector = TRUE)
    rrisk11_assert(identical(as.character(info$fold_manifest_md5), as.character(fold_manifest_md5)), "Existing task used a different V1.1 fold manifest.")
    rrisk11_log("Regional Risk V1.1 task already complete; skipped: ", task_id, ".")
    return(invisible(info))
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  options(river_sr.regional_risk_v1_1.log_file = file.path(output_dir, "run.log"))
  dat <- frozen$validated$data
  outer_fold <- as.integer(task$outer_fold[[1L]])
  heldout <- unique(dat$.regional_branch_id[dat$.branch_order == outer_fold])
  rrisk11_assert(length(heldout) == 1L, "Outer fold does not identify exactly one branch.")
  outer_test <- dat[dat$.regional_branch_id == heldout, , drop = FALSE]
  outer_train <- dat[dat$.regional_branch_id != heldout, , drop = FALSE]
  rrisk11_assert(length(unique(outer_train$.regional_branch_id)) == 16L && !heldout %in% outer_train$.regional_branch_id, "Outer branch leakage detected.")
  rrisk11_log("Starting task ", task_id, ": ", task$model_id[[1L]], ", held out ", heldout, ".")

  inner_branches <- unique(outer_train[, c(".regional_branch_id", ".branch_order")])
  inner_branches <- inner_branches[order(inner_branches$.branch_order), , drop = FALSE]
  inner_records <- vector("list", nrow(inner_branches)); diagnostics <- vector("list", nrow(inner_branches) + 1L)
  for (i in seq_len(nrow(inner_branches))) {
    inner_heldout <- inner_branches$.regional_branch_id[[i]]
    inner_assessment <- outer_train[outer_train$.regional_branch_id == inner_heldout, , drop = FALSE]
    inner_analysis <- outer_train[outer_train$.regional_branch_id != inner_heldout, , drop = FALSE]
    rrisk11_assert(length(unique(inner_analysis$.regional_branch_id)) == 15L, "Inner analysis must contain 15 branches.")
    rrisk11_assert(!heldout %in% c(inner_analysis$.regional_branch_id, inner_assessment$.regional_branch_id), "Outer branch entered an Inner fit.")
    fitted <- rrisk11_fit_gam(inner_analysis, inner_assessment, task$feature_set[[1L]], context, outer_fold, inner_fold = i)
    inner_records[[i]] <- data.frame(
      task_id = task_id, model_id = task$model_id[[1L]], feature_set = task$feature_set[[1L]], outer_fold = outer_fold,
      outer_heldout_branch = heldout, inner_fold = i, inner_heldout_branch = inner_heldout,
      row_id = inner_assessment[[context$config$columns$row_id]], site_id = inner_assessment[[context$config$columns$site_id]],
      regional_branch_id = inner_assessment$.regional_branch_id, observed_sr = inner_assessment$.observed,
      high_sr_label = inner_assessment$.label, branch_sqrt_weight = inner_assessment$.eval_weight,
      raw_probability = fitted$probability, stringsAsFactors = FALSE
    )
    fitted$diagnostics$model_id <- task$model_id[[1L]]
    fitted$diagnostics$heldout_branch <- inner_heldout
    diagnostics[[i]] <- fitted$diagnostics
  }
  inner_oof <- as.data.frame(data.table::rbindlist(inner_records, use.names = TRUE, fill = TRUE))
  rrisk11_assert(nrow(inner_oof) == nrow(outer_train) && !anyDuplicated(inner_oof$row_id) && setequal(inner_oof$row_id, outer_train[[context$config$columns$row_id]]), "Inner OOF does not cover Outer training rows exactly once.")
  rrisk11_assert(!heldout %in% inner_oof$regional_branch_id, "Outer branch entered Inner OOF.")

  calibrator <- rrisk11_fit_platt(inner_oof, context)
  inner_oof$calibrated_probability <- rrisk11_apply_platt(inner_oof$raw_probability, calibrator, context)
  thresholds <- rrisk11_select_operating_points(inner_oof, context)
  threshold_summary <- thresholds$selected
  threshold_summary$task_id <- task_id; threshold_summary$model_id <- task$model_id[[1L]]; threshold_summary$outer_fold <- outer_fold
  threshold_curve <- thresholds$curve
  threshold_curve$task_id <- task_id; threshold_curve$model_id <- task$model_id[[1L]]; threshold_curve$outer_fold <- outer_fold

  outer_fitted <- rrisk11_fit_gam(outer_train, outer_test, task$feature_set[[1L]], context, outer_fold)
  outer_fitted$diagnostics$model_id <- task$model_id[[1L]]
  outer_fitted$diagnostics$heldout_branch <- heldout
  diagnostics[[length(diagnostics)]] <- outer_fitted$diagnostics
  calibrated_outer <- rrisk11_apply_platt(outer_fitted$probability, calibrator, context)
  primary_threshold <- threshold_summary$threshold[threshold_summary$operating_point == "primary"]
  strict_threshold <- threshold_summary$threshold[threshold_summary$operating_point == "strict"]
  rrisk11_assert(length(primary_threshold) == 1L && length(strict_threshold) == 1L, "Each task must select Primary and Strict thresholds.")
  predictions <- data.frame(
    task_id = task_id, model_id = task$model_id[[1L]], feature_set = task$feature_set[[1L]], outer_fold = outer_fold,
    heldout_branch = heldout, row_id = outer_test[[context$config$columns$row_id]], site_id = outer_test[[context$config$columns$site_id]],
    regional_branch_id = outer_test$.regional_branch_id, observed_sr = outer_test$.observed, high_sr_label = outer_test$.label,
    branch_sqrt_weight = outer_test$.eval_weight, raw_probability = outer_fitted$probability,
    calibrated_probability = calibrated_outer, primary_threshold = primary_threshold, strict_threshold = strict_threshold,
    trigger_primary = calibrated_outer >= primary_threshold, trigger_strict = calibrated_outer >= strict_threshold,
    stringsAsFactors = FALSE
  )
  calibrator_summary <- calibrator$summary
  calibrator_summary$task_id <- task_id; calibrator_summary$model_id <- task$model_id[[1L]]; calibrator_summary$outer_fold <- outer_fold
  medians <- data.frame(
    feature = names(outer_fitted$medians), training_median = as.numeric(outer_fitted$medians),
    n_missing_outer_train = vapply(outer_train[names(outer_fitted$medians)], function(x) sum(is.na(x)), integer(1L)), stringsAsFactors = FALSE
  )
  diagnostics_table <- as.data.frame(data.table::rbindlist(diagnostics, use.names = TRUE, fill = TRUE))
  rrisk11_assert(nrow(diagnostics_table) == 17L, "Each task must record 16 Inner and one Outer GAM fit.")

  rrisk11_write_csv(inner_oof, file.path(output_dir, "inner_oof.csv"))
  rrisk11_write_csv(predictions, file.path(output_dir, "outer_predictions.csv"))
  rrisk11_write_csv(calibrator_summary, file.path(output_dir, "calibrator.csv"))
  rrisk11_write_csv(threshold_summary, file.path(output_dir, "thresholds.csv"))
  rrisk11_write_csv(threshold_curve, file.path(output_dir, "threshold_curve.csv"))
  rrisk11_write_csv(diagnostics_table, file.path(output_dir, "gam_diagnostics.csv"))
  rrisk11_write_csv(medians, file.path(output_dir, "outer_training_medians.csv"))
  info <- list(
    status = "complete", task_id = task_id, model_id = task$model_id[[1L]], feature_set = task$feature_set[[1L]],
    outer_fold = outer_fold, heldout_branch = heldout, n_outer_train = nrow(outer_train), n_outer_test = nrow(outer_test),
    inner_folds = 16L, gam_fits = 17L, calibrators = 1L, thresholds = 2L,
    outer_branch_in_inner_oof = FALSE, calibration_slope = calibrator$slope,
    primary_selection_mode = threshold_summary$selection_mode[threshold_summary$operating_point == "primary"],
    strict_selection_mode = threshold_summary$selection_mode[threshold_summary$operating_point == "strict"],
    threshold_candidate_rule_status = context$config$threshold$candidate_rule_status,
    data_md5 = frozen$manifest$upstream$table$md5, config_md5 = frozen$manifest$config$md5,
    fold_manifest_md5 = fold_manifest_md5, completed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), runtime = rrisk11_runtime_info()
  )
  rrisk11_write_json(info, file.path(output_dir, "task_info.json"))
  rrisk11_log("Task ", task_id, " complete: 16 Inner GAMs, one Platt calibrator, two thresholds and one Outer GAM.")
  invisible(info)
}
