stage_risk_run_task <- function(context, task_id, force = FALSE) {
  frozen <- risk_assert_folds_current(context)
  task_id <- as.integer(task_id)
  manifest <- data.table::fread(risk_fold_paths(context)[["tasks"]], data.table = FALSE)
  task <- manifest[manifest$task_id == task_id, , drop = FALSE]
  risk_assert(nrow(task) == 1L, paste("Task ID must resolve to exactly one row in 1-", nrow(manifest), "."))
  output_dir <- risk_task_dir(context, task$model[[1L]], task$repeat_id[[1L]], task$outer_fold[[1L]])
  if (risk_task_complete(output_dir) && !force) {
    info <- jsonlite::read_json(file.path(output_dir, "task_info.json"), simplifyVector = TRUE)
    risk_assert(identical(as.character(info$config_md5), as.character(frozen$manifest$config$md5)), "Existing task used a different Risk V1 config.")
    risk_assert(identical(as.character(info$fold_manifest_md5), as.character(risk_text_signature(risk_fold_paths(context)[["manifest"]])$md5)), "Existing task used different frozen folds.")
    risk_log("Risk task already complete; skipped: ", task_id, ".")
    return(invisible(info))
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  options(river_sr.risk_v1.log_file = file.path(output_dir, "run.log"))
  validated <- frozen$validated
  dat <- validated$data
  columns <- context$config$columns
  repeat_id <- as.integer(task$repeat_id[[1L]])
  outer_fold <- as.integer(task$outer_fold[[1L]])
  model_name <- as.character(task$model[[1L]])
  repeat_outer <- validated$outer[validated$outer$repeat_id == repeat_id, , drop = FALSE]
  outer_test_ids <- as.character(repeat_outer$row_id[repeat_outer$outer_fold == outer_fold])
  outer_train_ids <- setdiff(as.character(dat[[columns$row_id]]), outer_test_ids)
  inner_all <- data.table::fread(risk_fold_paths(context)[["inner"]], integer64 = "character", data.table = FALSE)
  inner_all$row_id <- as.character(inner_all$row_id)
  inner_design <- inner_all[inner_all$repeat_id == repeat_id & inner_all$outer_fold == outer_fold, , drop = FALSE]
  risk_assert(setequal(inner_design$row_id, outer_train_ids), "Risk Inner rows differ from the selected Outer training rows.")
  train_groups <- unique(dat$.hydrological_group[dat[[columns$row_id]] %in% outer_train_ids])
  test_groups <- unique(dat$.hydrological_group[dat[[columns$row_id]] %in% outer_test_ids])
  risk_assert(length(intersect(train_groups, test_groups)) == 0L, "A hydrological system crosses the Risk Outer boundary.")
  risk_log("Starting Risk V1 task ", task_id, ": ", model_name, " repeat ", repeat_id, " fold ", outer_fold, ".")

  result <- if (identical(model_name, "elastic_net")) {
    risk_run_elastic_task(dat, validated$predictors, inner_design, outer_train_ids, outer_test_ids, task[1L, ], context)
  } else if (identical(model_name, "probability_rf")) {
    risk_run_rf_task(dat, validated$predictors, inner_design, outer_train_ids, outer_test_ids, task[1L, ], context)
  } else {
    stop("Unsupported Risk V1 model: ", model_name, call. = FALSE)
  }
  risk_write_csv(result$candidate_summary, file.path(output_dir, "candidate_summary.csv"))
  risk_write_yaml(result$selected, file.path(output_dir, "selected_params.yml"))
  risk_write_csv(result$inner_winner, file.path(output_dir, "inner_winner_oof.csv"))
  risk_write_csv(result$outer_predictions, file.path(output_dir, "outer_predictions.csv"))
  risk_write_csv(result$outer_metrics, file.path(output_dir, "outer_metrics.csv"))
  outer_train <- dat[match(outer_train_ids, dat[[columns$row_id]]), , drop = FALSE]
  medians_table <- data.frame(
    feature = validated$predictors, training_median = as.numeric(result$medians[validated$predictors]),
    n_missing_outer_train = vapply(outer_train[validated$predictors], function(x) sum(is.na(x)), integer(1L)),
    stringsAsFactors = FALSE
  )
  risk_write_csv(medians_table, file.path(output_dir, "outer_training_medians.csv"))
  if (!is.null(result$path_diagnostics)) risk_write_csv(result$path_diagnostics, file.path(output_dir, "elastic_path_diagnostics.csv"))
  fold_manifest_signature <- risk_text_signature(risk_fold_paths(context)[["manifest"]])
  info <- list(
    status = "complete", task_id = task_id, model = model_name, repeat_id = repeat_id, outer_fold = outer_fold,
    n_outer_train = length(outer_train_ids), n_outer_test = length(outer_test_ids),
    n_train_groups = length(train_groups), n_test_groups = length(test_groups), group_leakage = 0L,
    candidates = nrow(result$candidate_summary), inner_folds = as.integer(context$config$validation$inner_folds),
    config_md5 = frozen$manifest$config$md5, fold_manifest_md5 = fold_manifest_signature$md5,
    completed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), runtime = risk_runtime_info()
  )
  risk_write_json(info, file.path(output_dir, "task_info.json"))
  risk_log("Risk V1 task ", task_id, " complete; Inner winner feasible=", result$selected$inner_gate_feasible, ".")
  invisible(info)
}
