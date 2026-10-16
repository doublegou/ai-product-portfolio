#!/usr/bin/env Rscript

source(file.path("training", "base", "v3", "R", "common.R"))
context <- v3_context()
args <- v3_parse_args(commandArgs(trailingOnly = TRUE))
run_id <- as.character(args$`run-id` %||% "")
v3_assert(nzchar(run_id), "--run-id is required.")
run_dir <- v3_run_dir(context, run_id)
v3_verify_fold_manifest(context)
report_dir <- file.path(run_dir, "reports", "primary")
dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)
index <- data.table::fread(file.path(context$base, "folds", "training_index.csv"))

all_predictions <- list()
all_recipes <- list()
for (model in c("rf", "xgb")) {
  for (task in seq_len(15L)) {
    coordinates <- v3_task_coordinates(task)
    directory <- file.path(run_dir, "validation_tasks", "primary",
                           sprintf("repeat_%02d", coordinates$repeat_id), sprintf("fold_%02d", coordinates$outer_fold), model)
    manifest_path <- file.path(directory, "manifest.json")
    v3_assert(file.exists(manifest_path), paste("Missing Primary task manifest:", manifest_path))
    manifest <- jsonlite::read_json(manifest_path, simplifyVector = TRUE)
    v3_assert(identical(manifest$status, "complete"), paste("Incomplete Primary task", model, task))
    all_predictions[[length(all_predictions) + 1L]] <- data.table::fread(file.path(directory, "outer_predictions.csv"))
    recipe <- jsonlite::read_json(file.path(directory, "selected_recipe.json"), simplifyVector = TRUE)
    all_recipes[[length(all_recipes) + 1L]] <- data.table::data.table(
      model = model, task = task, repeat_id = coordinates$repeat_id, outer_fold = coordinates$outer_fold,
      structure_id = recipe$structure_id, weight_scheme = recipe$weight_scheme,
      best_iteration = recipe$best_iteration %||% NA_integer_
    )
  }
}
predictions <- data.table::rbindlist(all_predictions, fill = TRUE)
recipes <- data.table::rbindlist(all_recipes, fill = TRUE)
v3_assert(nrow(predictions) == nrow(index) * 3L * 2L, "Pooled Primary prediction count failed.")
coverage <- predictions[, .N, by = .(model, repeat_id, site_id)]
v3_assert(all(coverage$N == 1L), "Each model/repeat/site must have one strict Outer prediction.")

overall <- predictions[, v3_metrics(observed, predicted, hydro_system_id), by = model]
repeat_metrics <- predictions[, v3_metrics(observed, predicted, hydro_system_id), by = .(model, repeat_id)]
overall[, bias_abs := abs(bias)]
data.table::setorderv(overall, c("rmse", "mae", "bias_abs"), c(1L, 1L, 1L))
winner <- overall[1L, model]

site_oof <- predictions[, .(
  observed = observed[1L], hydro_system_id = hydro_system_id[1L],
  pred_repeat1 = predicted[repeat_id == 1L], pred_repeat2 = predicted[repeat_id == 2L], pred_repeat3 = predicted[repeat_id == 3L]
), by = .(model, site_id)]
site_oof[, `:=`(
  pred_mean = rowMeans(.SD),
  pred_sd = apply(.SD, 1L, stats::sd)
), .SDcols = c("pred_repeat1", "pred_repeat2", "pred_repeat3")]
site_oof[, `:=`(
  error_repeat1 = pred_repeat1 - observed,
  error_repeat2 = pred_repeat2 - observed,
  error_repeat3 = pred_repeat3 - observed
)]

v3_atomic_fwrite(predictions, file.path(report_dir, "pooled_outer_predictions.csv"))
v3_atomic_fwrite(site_oof, file.path(report_dir, "site_oof_predictions.csv"))
v3_atomic_fwrite(overall, file.path(report_dir, "overall_metrics.csv"))
v3_atomic_fwrite(repeat_metrics, file.path(report_dir, "repeat_metrics.csv"))
v3_atomic_fwrite(recipes, file.path(report_dir, "outer_selected_recipes.csv"))
decision <- list(
  status = "primary_complete", selected_algorithm = winner,
  rule = "minimum pooled strict Outer-OOF RMSE; MAE then absolute bias as deterministic tie-breakers",
  pooled_rows_per_model = nrow(index) * 3L,
  note = "Deployment parameters are selected in a separate grouped tuning pass; this decision does not pick a structure."
)
v3_atomic_json(decision, file.path(report_dir, "algorithm_decision.json"))
message("Primary aggregation complete. Selected algorithm: ", winner)
