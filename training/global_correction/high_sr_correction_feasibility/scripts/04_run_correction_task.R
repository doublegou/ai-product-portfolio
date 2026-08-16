corr_feature_sets <- function(validated) list(basepred = character(0L), env47 = validated$env47, full50 = validated$full50)

stage_corr_run_correction_task <- function(context, correction_task_id, force = FALSE) {
  frozen <- corr_assert_frozen_current(context)
  task <- frozen$correction_tasks[frozen$correction_tasks$correction_task_id == as.integer(correction_task_id), , drop = FALSE]
  corr_assert(nrow(task) == 1L, "Correction task ID must resolve to exactly one task in 1..30.")
  model <- as.character(task$model); task_id <- as.integer(task$base_task_id)
  repeat_id <- as.integer(task$repeat_id); outer_fold <- as.integer(task$outer_fold)
  output_dir <- corr_model_task_dir(context, model, repeat_id, outer_fold)
  if (corr_model_task_complete(output_dir) && !force) {
    info <- jsonlite::read_json(file.path(output_dir, "task_info.json"), simplifyVector = TRUE)
    corr_assert(identical(as.character(info$config_md5), as.character(frozen$manifest$config$md5)), "Existing correction task used another config.")
    corr_assert(identical(as.character(info$implementation_md5), as.character(frozen$manifest$implementation$md5)), "Existing correction task used another implementation.")
    corr_log("Correction task already complete; skipped: ", correction_task_id, ".")
    return(invisible(info))
  }
  base_dir <- corr_base_task_dir(context, repeat_id, outer_fold)
  corr_assert(corr_base_task_complete(base_dir), paste("Required Base task is incomplete:", task_id))
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  options(river_sr.correction.log_file = file.path(output_dir, "run.log"))
  dat <- frozen$validated$data; columns <- context$config$columns
  meta <- corr_read_table(file.path(base_dir, "correction_inner_meta_features.csv"))
  standard <- corr_read_table(file.path(base_dir, "outer_train_base_oof.csv"))
  outer <- corr_read_table(file.path(base_dir, "outer_test_base_predictions.csv"))
  meta$oracle_elevated <- as.logical(meta$oracle_elevated); standard$oracle_elevated <- as.logical(standard$oracle_elevated); outer$oracle_elevated <- as.logical(outer$oracle_elevated)
  features <- corr_feature_sets(frozen$validated)
  feature_ids <- c(basepred = 1L, env47 = 2L, full50 = 3L)
  candidate_records <- list(); selected_records <- list(); inner_records <- list(); outer_records <- list(); metric_records <- list(); diagnostic_records <- list(); preprocessing_records <- list()
  for (feature_set in names(features)) {
    predictors <- features[[feature_set]]
    corr_log("Correction task ", correction_task_id, ": ", model, " / ", feature_set, ".")
    tuned <- if (model == "elastic_net") {
      corr_tune_elastic(meta, dat, predictors, context)
    } else {
      corr_tune_residual_rf(meta, dat, predictors, context, task_id, feature_ids[[feature_set]])
    }
    selected <- tuned$selected
    train <- standard[standard$oracle_elevated, , drop = FALSE]
    assessment <- outer
    train <- cbind(train, dat[match(train$row_id, dat[[columns$row_id]]), predictors, drop = FALSE])
    assessment <- cbind(assessment, dat[match(assessment$row_id, dat[[columns$row_id]]), predictors, drop = FALSE])
    fitted <- if (model == "elastic_net") {
      corr_fit_final_elastic(train, assessment, predictors, selected, context)
    } else {
      corr_fit_final_residual_rf(train, assessment, predictors, selected, context, task_id, feature_ids[[feature_set]])
    }
    prediction <- data.frame(
      correction_task_id = as.integer(correction_task_id), task_id = task_id, repeat_id = repeat_id, outer_fold = outer_fold,
      model = model, feature_set = feature_set, row_id = outer$row_id, site_id = outer$site_id,
      hydrological_group = outer$hydrological_group, longitude = outer$longitude, latitude = outer$latitude,
      reference_id = outer$reference_id, observed = outer$observed, oracle_elevated = outer$oracle_elevated,
      base_prediction = outer$base_prediction, residual_observed = outer$residual_observed,
      predicted_residual = fitted$predicted_residual, correction = fitted$correction,
      final_prediction = outer$base_prediction + fitted$correction,
      outer_training_observed_max = max(standard$observed),
      prediction_error = outer$base_prediction + fitted$correction - outer$observed, stringsAsFactors = FALSE
    )
    corr_assert(all(prediction$correction >= 0) && all(prediction$final_prediction >= prediction$base_prediction), "Non-negative correction invariant failed.")
    context_columns <- list(correction_task_id = as.integer(correction_task_id), base_task_id = task_id, repeat_id = repeat_id, outer_fold = outer_fold)
    candidates <- tuned$summary
    for (name in names(context_columns)) candidates[[name]] <- context_columns[[name]]
    candidates$model <- model; candidates$feature_set <- feature_set
    for (name in names(context_columns)) selected[[name]] <- context_columns[[name]]
    selected$model <- model; selected$feature_set <- feature_set
    if (model == "elastic_net") {
      selected$outer_lambda_max <- fitted$lambda_max; selected$outer_lambda <- fitted$lambda
    } else {
      selected$outer_seed <- fitted$seed
    }
    winner_oof <- tuned$winner_oof
    for (name in names(context_columns)) winner_oof[[name]] <- context_columns[[name]]
    winner_oof$model <- model; winner_oof$feature_set <- feature_set
    metrics <- corr_prediction_metrics(prediction, "final_prediction", context); metrics$model <- model; metrics$feature_set <- feature_set
    candidate_records[[feature_set]] <- candidates; selected_records[[feature_set]] <- selected
    inner_records[[feature_set]] <- winner_oof; outer_records[[feature_set]] <- prediction; metric_records[[feature_set]] <- metrics
    if (model == "elastic_net") {
      diag <- tuned$lambda_diagnostics; diag$model <- model; diag$feature_set <- feature_set
      diagnostic_records[[feature_set]] <- diag
    }
    model_predictors <- c("base_prediction", predictors)
    preprocessing_records[[feature_set]] <- data.frame(
      correction_task_id = as.integer(correction_task_id), base_task_id = task_id, repeat_id = repeat_id, outer_fold = outer_fold,
      model = model, feature_set = feature_set, feature = model_predictors,
      training_median = as.numeric(fitted$medians[model_predictors]),
      training_center = if (is.null(fitted$scaler)) NA_real_ else as.numeric(fitted$scaler$center[model_predictors]),
      training_scale = if (is.null(fitted$scaler)) NA_real_ else as.numeric(fitted$scaler$scale[model_predictors]),
      stringsAsFactors = FALSE
    )
  }
  outer_all <- as.data.frame(data.table::rbindlist(outer_records, use.names = TRUE, fill = TRUE))
  for (row_id in unique(outer_all$row_id)) {
    values <- outer_all$base_prediction[outer_all$row_id == row_id]
    corr_assert(length(unique(values)) == 1L, "Feature sets did not reuse an identical Outer Base prediction.")
  }
  corr_write_csv(as.data.frame(data.table::rbindlist(candidate_records, use.names = TRUE, fill = TRUE)), file.path(output_dir, "candidate_summary.csv"))
  corr_write_csv(as.data.frame(data.table::rbindlist(selected_records, use.names = TRUE, fill = TRUE)), file.path(output_dir, "selected_params.csv"))
  corr_write_csv(as.data.frame(data.table::rbindlist(inner_records, use.names = TRUE, fill = TRUE)), file.path(output_dir, "inner_winner_oof.csv"))
  corr_write_csv(outer_all, file.path(output_dir, "outer_predictions.csv"))
  corr_write_csv(as.data.frame(data.table::rbindlist(metric_records, use.names = TRUE, fill = TRUE)), file.path(output_dir, "outer_metrics.csv"))
  corr_write_csv(as.data.frame(data.table::rbindlist(preprocessing_records, use.names = TRUE, fill = TRUE)), file.path(output_dir, "outer_preprocessing.csv"))
  if (length(diagnostic_records)) corr_write_csv(as.data.frame(data.table::rbindlist(diagnostic_records, use.names = TRUE, fill = TRUE)), file.path(output_dir, "elastic_lambda_diagnostics.csv"))
  base_info <- jsonlite::read_json(file.path(base_dir, "task_info.json"), simplifyVector = TRUE)
  info <- list(
    status = "complete", correction_task_id = as.integer(correction_task_id), base_task_id = task_id,
    model = model, repeat_id = repeat_id, outer_fold = outer_fold, feature_sets = names(features),
    n_outer_test = nrow(outer), n_oracle_outer_test = sum(outer$oracle_elevated),
    base_task_config_md5 = base_info$config_md5, config_md5 = frozen$manifest$config$md5,
    implementation_md5 = frozen$manifest$implementation$md5,
    base_artifacts = list(
      outer_train_oof = corr_text_signature(file.path(base_dir, "outer_train_base_oof.csv")),
      outer_test = corr_text_signature(file.path(base_dir, "outer_test_base_predictions.csv")),
      nested_meta = corr_text_signature(file.path(base_dir, "correction_inner_meta_features.csv"))
    ),
    completed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), runtime = corr_runtime_info()
  )
  corr_write_json(info, file.path(output_dir, "task_info.json"))
  corr_log("Correction task ", correction_task_id, " complete.")
  invisible(info)
}
