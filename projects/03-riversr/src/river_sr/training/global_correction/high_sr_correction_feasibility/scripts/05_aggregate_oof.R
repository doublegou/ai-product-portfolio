stage_corr_aggregate_oof <- function(context, run_id, force = FALSE) {
  frozen <- corr_assert_frozen_current(context)
  corr_begin_run(context, run_id, commandArgs(trailingOnly = TRUE))
  options(river_sr.correction.log_file = corr_run_dir(context, run_id, "logs", "run.log"))
  incomplete_base <- vapply(seq_len(nrow(frozen$base_tasks)), function(i) {
    path <- corr_base_task_dir(context, frozen$base_tasks$repeat_id[[i]], frozen$base_tasks$outer_fold[[i]])
    if (!corr_base_task_complete(path)) return(TRUE)
    info <- jsonlite::read_json(file.path(path, "task_info.json"), simplifyVector = TRUE)
    !identical(as.character(info$config_md5), as.character(frozen$manifest$config$md5)) ||
      !identical(as.character(info$implementation_md5), as.character(frozen$manifest$implementation$md5))
  }, logical(1L))
  corr_assert(!any(incomplete_base), paste("Incomplete Base task IDs:", paste(frozen$base_tasks$task_id[incomplete_base], collapse = ", ")))
  incomplete_model <- vapply(seq_len(nrow(frozen$correction_tasks)), function(i) {
    x <- frozen$correction_tasks[i, ]; path <- corr_model_task_dir(context, x$model, x$repeat_id, x$outer_fold)
    if (!corr_model_task_complete(path)) return(TRUE)
    info <- jsonlite::read_json(file.path(path, "task_info.json"), simplifyVector = TRUE)
    !identical(as.character(info$config_md5), as.character(frozen$manifest$config$md5)) ||
      !identical(as.character(info$implementation_md5), as.character(frozen$manifest$implementation$md5))
  }, logical(1L))
  corr_assert(!any(incomplete_model), paste("Incomplete correction task IDs:", paste(frozen$correction_tasks$correction_task_id[incomplete_model], collapse = ", ")))

  expected_rows <- as.character(frozen$validated$data[[context$config$columns$row_id]])
  repeats <- as.integer(context$config$validation$repeats); outer_k <- as.integer(context$config$validation$outer_folds)
  feature_sets <- c("basepred", "env47", "full50"); models <- c("elastic_net", "residual_rf")
  repeat_records <- list(); tail_records <- list(); group_records <- list(); selected_records <- list()
  for (model in models) {
    for (repeat_id in seq_len(repeats)) {
      fold_predictions <- lapply(seq_len(outer_k), function(outer_fold) {
        corr_read_table(file.path(corr_model_task_dir(context, model, repeat_id, outer_fold), "outer_predictions.csv"))
      })
      all <- as.data.frame(data.table::rbindlist(fold_predictions, use.names = TRUE, fill = TRUE))
      all$oracle_elevated <- as.logical(all$oracle_elevated)
      for (feature_set in feature_sets) {
        x <- all[all$feature_set == feature_set, , drop = FALSE]
        corr_assert(nrow(x) == length(expected_rows) && !anyDuplicated(x$row_id) && setequal(x$row_id, expected_rows), paste("Incomplete Outer OOF:", model, feature_set, repeat_id))
        x <- x[match(expected_rows, x$row_id), , drop = FALSE]
        corr_assert(sum(x$oracle_elevated) == as.integer(context$config$validation$expected_elevated_rows), "Oracle Outer OOF count changed.")
        corr_assert(length(unique(x$hydrological_group[x$oracle_elevated])) == as.integer(context$config$validation$expected_elevated_groups), "Oracle Outer OOF group count changed.")
        corr_assert(all(x$correction >= 0) && all(x$final_prediction >= x$base_prediction), "Aggregated correction invariant failed.")
        candidate <- corr_prediction_metrics(x, "final_prediction", context)
        raw_frame <- x; raw_frame$correction <- 0
        raw <- corr_prediction_metrics(raw_frame, "base_prediction", context)
        oracle <- x[x$oracle_elevated, , drop = FALSE]
        groups_candidate <- corr_group_metrics(oracle$observed, oracle$final_prediction, oracle$hydrological_group)
        groups_raw <- corr_group_metrics(oracle$observed, oracle$base_prediction, oracle$hydrological_group)
        groups_candidate$raw_base_mae <- groups_raw$mae[match(groups_candidate$hydrological_group, groups_raw$hydrological_group)]
        groups_candidate$mae_delta_vs_raw <- groups_candidate$mae - groups_candidate$raw_base_mae
        repeat_records[[length(repeat_records) + 1L]] <- data.frame(
          model = model, feature_set = feature_set, repeat_id = repeat_id,
          n = candidate$n, n_groups = candidate$n_groups,
          group_macro_mae = candidate$group_macro_mae, station_mae = candidate$station_mae,
          rmse = candidate$rmse, bias = candidate$bias,
          raw_base_group_macro_mae = raw$group_macro_mae, raw_base_station_mae = raw$station_mae,
          raw_base_rmse = raw$rmse, raw_base_bias = raw$bias,
          correction_trigger_rate = candidate$correction_trigger_rate, correction_mean = candidate$correction_mean,
          correction_p90 = candidate$correction_p90, correction_max = candidate$correction_max,
          n_final_gt_1 = candidate$n_final_gt_1, max_final_prediction = candidate$max_final_prediction,
          n_above_outer_training_observed_max = candidate$n_above_outer_training_observed_max,
          improved_groups_vs_raw = sum(groups_candidate$mae_delta_vs_raw < -as.numeric(context$config$selection$numerical_epsilon)),
          degraded_groups_vs_raw = sum(groups_candidate$mae_delta_vs_raw > as.numeric(context$config$selection$numerical_epsilon)),
          tied_groups_vs_raw = sum(abs(groups_candidate$mae_delta_vs_raw) <= as.numeric(context$config$selection$numerical_epsilon)),
          stringsAsFactors = FALSE
        )
        tail <- corr_tail_metrics(x, "final_prediction", context)
        raw_tail <- corr_tail_metrics(raw_frame, "base_prediction", context)
        tail$raw_base_group_macro_mae <- raw_tail$group_macro_mae[match(tail$tail_bin, raw_tail$tail_bin)]
        tail$raw_base_station_mae <- raw_tail$station_mae[match(tail$tail_bin, raw_tail$tail_bin)]
        tail$raw_base_bias <- raw_tail$bias[match(tail$tail_bin, raw_tail$tail_bin)]
        tail$group_macro_improvement_vs_raw <- (tail$raw_base_group_macro_mae - tail$group_macro_mae) / tail$raw_base_group_macro_mae
        tail$station_improvement_vs_raw <- (tail$raw_base_station_mae - tail$station_mae) / tail$raw_base_station_mae
        tail$model <- model; tail$feature_set <- feature_set; tail$repeat_id <- repeat_id
        tail_records[[length(tail_records) + 1L]] <- tail
        groups_candidate$model <- model; groups_candidate$feature_set <- feature_set; groups_candidate$repeat_id <- repeat_id
        group_records[[length(group_records) + 1L]] <- groups_candidate
      }
      repeat_dir <- corr_output_path(context, "validation_dir", model, sprintf("repeat_%02d", repeat_id))
      corr_write_csv(all, file.path(repeat_dir, "oof_predictions.csv"))
    }
  }
  repeat_metrics <- do.call(rbind, repeat_records)
  eps <- as.numeric(context$config$selection$numerical_epsilon)
  threshold <- as.numeric(context$config$selection$signal_repeat_improvement)
  repeat_metrics$basepred_group_macro_mae <- NA_real_
  repeat_metrics$signal_improvement <- NA_real_
  repeat_metrics$signal_repeat_pass <- FALSE
  repeat_metrics$raw_base_improvement <- (repeat_metrics$raw_base_group_macro_mae - repeat_metrics$group_macro_mae) / repeat_metrics$raw_base_group_macro_mae
  repeat_metrics$raw_base_safety_repeat_pass <- repeat_metrics$group_macro_mae <= repeat_metrics$raw_base_group_macro_mae + eps
  for (model in models) for (repeat_id in seq_len(repeats)) {
    baseline <- repeat_metrics$group_macro_mae[repeat_metrics$model == model & repeat_metrics$repeat_id == repeat_id & repeat_metrics$feature_set == "basepred"]
    corr_assert(length(baseline) == 1L, "BasePred-only repeat baseline is ambiguous.")
    index <- repeat_metrics$model == model & repeat_metrics$repeat_id == repeat_id
    repeat_metrics$basepred_group_macro_mae[index] <- baseline
    candidate <- index & repeat_metrics$feature_set %in% c("env47", "full50")
    repeat_metrics$signal_improvement[candidate] <- (baseline - repeat_metrics$group_macro_mae[candidate]) / baseline
    repeat_metrics$signal_repeat_pass[candidate] <- repeat_metrics$signal_improvement[candidate] >= threshold - eps
  }
  candidate_summary <- corr_candidate_summary(repeat_metrics, context)
  selected <- lapply(seq_len(nrow(frozen$correction_tasks)), function(i) {
    x <- frozen$correction_tasks[i, ]; corr_read_table(file.path(corr_model_task_dir(context, x$model, x$repeat_id, x$outer_fold), "selected_params.csv"))
  })
  selected_tasks <- as.data.frame(data.table::rbindlist(selected, use.names = TRUE, fill = TRUE))
  tail_metrics <- as.data.frame(data.table::rbindlist(tail_records, use.names = TRUE, fill = TRUE))
  group_metrics <- as.data.frame(data.table::rbindlist(group_records, use.names = TRUE, fill = TRUE))
  validation_dir <- corr_output_path(context, "validation_dir")
  corr_write_csv(repeat_metrics, file.path(validation_dir, "repeat_metrics.csv"))
  corr_write_csv(candidate_summary, file.path(validation_dir, "candidate_summary.csv"))
  corr_write_csv(tail_metrics, file.path(validation_dir, "tail_metrics.csv"))
  corr_write_csv(group_metrics, file.path(validation_dir, "group_metrics.csv"))
  corr_write_csv(selected_tasks, file.path(validation_dir, "selected_tasks.csv"))
  manifest <- list(
    status = "complete", run_id = run_id, aggregated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    base_tasks = nrow(frozen$base_tasks), correction_tasks = nrow(frozen$correction_tasks),
    models = models, feature_sets = feature_sets, repeats = repeats,
    rows_per_feature_repeat = length(expected_rows), oracle_rows_per_feature_repeat = as.integer(context$config$validation$expected_elevated_rows),
    prediction_averaging_across_repeats = FALSE, final_model_fitted = FALSE,
    config_md5 = frozen$manifest$config$md5, implementation_md5 = frozen$manifest$implementation$md5,
    fold_manifest_md5 = corr_text_signature(corr_fold_paths(context)[["manifest"]])$md5
  )
  corr_write_json(manifest, file.path(validation_dir, "oof_manifest.json"))
  reports <- corr_run_dir(context, run_id, "reports")
  for (name in c("repeat_metrics.csv", "candidate_summary.csv", "tail_metrics.csv", "group_metrics.csv", "selected_tasks.csv")) {
    source <- file.path(validation_dir, name)
    corr_write_csv(corr_read_table(source), file.path(reports, name))
  }
  corr_write_json(manifest, file.path(reports, "oof_manifest.json"))
  corr_log("Aggregated complete repeated Outer OOF evidence; no predictions were averaged across repeats.")
  invisible(list(repeat_metrics = repeat_metrics, candidate_summary = candidate_summary))
}
