rrisk2_fit_predict <- function(analysis, assessment, predictors, algorithm, seed, context) {
  analysis <- rrisk2_add_fit_weights(analysis)
  train <- rrisk2_numeric_matrix(analysis, predictors); test <- rrisk2_numeric_matrix(assessment, predictors, train$medians)
  model <- rrisk2_fit_model(algorithm, train$x, analysis$.label, analysis$.fit_weight, seed, context)
  list(probability = rrisk2_predict_model(model, test$x), medians = train$medians, model = model)
}

stage_rrisk2_run_task <- function(context, task_id, force = FALSE) {
  frozen <- rrisk2_assert_folds_current(context); task_id <- as.integer(task_id)
  task <- frozen$tasks[frozen$tasks$task_id == task_id, , drop = FALSE]
  rrisk2_assert(nrow(task) == 1L, "task_id must resolve to one V2 task in 1..68.")
  output_dir <- rrisk2_task_dir(context, task$model_id[1], task$outer_fold[1]); fold_md5 <- rrisk2_text_signature(rrisk2_fold_paths(context)[["manifest"]])$md5
  if (rrisk2_task_complete(output_dir) && !force) {
    info <- jsonlite::read_json(file.path(output_dir, "task_info.json"), simplifyVector = TRUE)
    rrisk2_assert(identical(as.character(info$fold_manifest_md5), as.character(fold_md5)), "Existing task used another fold manifest.")
    rrisk2_log("V2 task already complete; skipped: ", task_id); return(invisible(info))
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE); options(river_sr.regional_risk_v2.log_file = file.path(output_dir, "run.log"))
  dat <- frozen$validated$data; outer_fold <- as.integer(task$outer_fold[1]); heldout <- unique(dat$.regional_branch_id[dat$.branch_order == outer_fold])
  outer_test <- dat[dat$.regional_branch_id == heldout, , drop = FALSE]; outer_train <- dat[dat$.regional_branch_id != heldout, , drop = FALSE]
  rrisk2_assert(length(heldout) == 1L && length(unique(outer_train$.regional_branch_id)) == 16L && !heldout %in% outer_train$.regional_branch_id, "Outer leakage detected.")
  predictors <- rrisk2_predictors(context, task$feature_set[1]); rrisk2_log("Starting task ", task_id, ": ", task$model_id[1], ", held out ", heldout, ".")

  inner_branches <- unique(outer_train[, c(".regional_branch_id", ".branch_order")]); inner_branches <- inner_branches[order(inner_branches$.branch_order), ]
  records <- vector("list", 16L); diagnostics <- vector("list", 17L)
  for (i in 1:16) {
    inner_heldout <- inner_branches$.regional_branch_id[i]; assessment <- outer_train[outer_train$.regional_branch_id == inner_heldout, ]; analysis <- outer_train[outer_train$.regional_branch_id != inner_heldout, ]
    rrisk2_assert(length(unique(analysis$.regional_branch_id)) == 15L && !heldout %in% c(analysis$.regional_branch_id, assessment$.regional_branch_id), "Inner leakage detected.")
    fitted <- rrisk2_fit_predict(analysis, assessment, predictors, task$algorithm[1], rrisk2_seed(context, task_id, i), context)
    records[[i]] <- data.frame(task_id = task_id, model_id = task$model_id[1], algorithm = task$algorithm[1], feature_set = task$feature_set[1], outer_fold = outer_fold,
      outer_heldout_branch = heldout, inner_fold = i, inner_heldout_branch = inner_heldout, row_id = assessment[[context$config$columns$row_id]], site_id = assessment[[context$config$columns$site_id]],
      regional_branch_id = assessment$.regional_branch_id, observed_sr = assessment$.observed, high_sr_label = assessment$.label, branch_sqrt_weight = assessment$.eval_weight,
      probability = fitted$probability, stringsAsFactors = FALSE)
    diagnostics[[i]] <- data.frame(task_id = task_id, fit_role = "inner", fit_index = i, heldout_branch = inner_heldout, n_analysis = nrow(analysis), n_assessment = nrow(assessment),
      positive_analysis = sum(analysis$.label), predictor_n = length(predictors), seed = rrisk2_seed(context, task_id, i), stringsAsFactors = FALSE)
  }
  inner_oof <- as.data.frame(data.table::rbindlist(records)); rrisk2_assert(nrow(inner_oof) == nrow(outer_train) && !anyDuplicated(inner_oof$row_id), "Inner OOF must cover outer training exactly once.")
  threshold <- rrisk2_select_threshold(inner_oof, context); selected <- threshold$selected
  fitted <- rrisk2_fit_predict(outer_train, outer_test, predictors, task$algorithm[1], rrisk2_seed(context, task_id, 17L), context)
  diagnostics[[17L]] <- data.frame(task_id = task_id, fit_role = "outer", fit_index = 17L, heldout_branch = heldout, n_analysis = nrow(outer_train), n_assessment = nrow(outer_test),
    positive_analysis = sum(outer_train$.label), predictor_n = length(predictors), seed = rrisk2_seed(context, task_id, 17L), stringsAsFactors = FALSE)
  probability <- fitted$probability; predictions <- data.frame(task_id = task_id, model_id = task$model_id[1], algorithm = task$algorithm[1], feature_set = task$feature_set[1], outer_fold = outer_fold,
    heldout_branch = heldout, row_id = outer_test[[context$config$columns$row_id]], site_id = outer_test[[context$config$columns$site_id]], regional_branch_id = outer_test$.regional_branch_id,
    observed_sr = outer_test$.observed, high_sr_label = outer_test$.label, branch_sqrt_weight = outer_test$.eval_weight, probability = probability,
    threshold = selected$threshold[1], trigger = probability >= selected$threshold[1], stringsAsFactors = FALSE)
  selected$task_id <- task_id; selected$model_id <- task$model_id[1]; selected$outer_fold <- outer_fold
  threshold$curve$task_id <- task_id; threshold$curve$model_id <- task$model_id[1]; threshold$curve$outer_fold <- outer_fold
  importance <- rrisk2_importance_model(fitted$model, predictors); importance$task_id <- task_id; importance$model_id <- task$model_id[1]; importance$outer_fold <- outer_fold
  medians <- data.frame(feature = names(fitted$medians), training_median = as.numeric(fitted$medians), stringsAsFactors = FALSE)
  rrisk2_write_csv(inner_oof, file.path(output_dir, "inner_oof.csv")); rrisk2_write_csv(predictions, file.path(output_dir, "outer_predictions.csv"))
  rrisk2_write_csv(selected, file.path(output_dir, "threshold.csv")); rrisk2_write_csv(threshold$curve, file.path(output_dir, "threshold_curve.csv"))
  rrisk2_write_csv(as.data.frame(data.table::rbindlist(diagnostics)), file.path(output_dir, "fit_diagnostics.csv")); rrisk2_write_csv(importance, file.path(output_dir, "variable_importance.csv")); rrisk2_write_csv(medians, file.path(output_dir, "outer_training_medians.csv"))
  info <- list(status = "complete", task_id = task_id, model_id = task$model_id[1], algorithm = task$algorithm[1], feature_set = task$feature_set[1], outer_fold = outer_fold, heldout_branch = heldout,
    n_outer_train = nrow(outer_train), n_outer_test = nrow(outer_test), inner_folds = 16L, model_fits = 17L, calibration = "none", thresholds = 1L,
    outer_branch_in_inner_oof = FALSE, threshold_selection_mode = selected$selection_mode[1], data_md5 = frozen$manifest$inputs$table$md5,
    config_md5 = frozen$manifest$config$md5, fold_manifest_md5 = fold_md5, completed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), runtime = rrisk2_runtime_info())
  rrisk2_write_json(info, file.path(output_dir, "task_info.json")); rrisk2_log("Task ", task_id, " complete: 16 inner fits, one nested threshold and one outer fit.")
  invisible(info)
}
