#!/usr/bin/env Rscript

source(file.path("training", "base", "v3", "R", "common.R"))
context <- v3_context()
args <- v3_parse_args(commandArgs(trailingOnly = TRUE))
run_id <- as.character(args$`run-id` %||% "")
model <- as.character(args$model %||% "")
task <- as.integer(args$task %||% NA)
v3_assert(nzchar(run_id), "--run-id is required.")
v3_assert(model %in% c("rf", "xgb"), "--model must be rf or xgb.")
v3_assert(is.finite(task), "--task is required.")
coordinates <- v3_stress_coordinates(task)
run_dir <- v3_run_dir(context, run_id)
v3_verify_fold_manifest(context)
recipe_path <- file.path(run_dir, "deployment", model, "frozen_recipe.json")
v3_assert(file.exists(recipe_path), "Freeze the deployment recipe before stress testing.")
recipe <- jsonlite::read_json(recipe_path, simplifyVector = TRUE)
v3_assert(identical(recipe$status, "frozen") && identical(recipe$model, model), "Invalid frozen recipe.")

fold_dir <- file.path(context$base, "folds")
release <- readRDS(file.path(fold_dir, "training_release.rds"))
data <- data.table::as.data.table(release$data)
index <- data.table::as.data.table(release$index)
stress <- data.table::fread(file.path(fold_dir, "stress_folds.csv"))
assignment <- stress[get("scheme") == coordinates$scheme]
test_ids <- assignment[fold == coordinates$fold, site_id]
analysis <- !index$site_id %in% test_ids
assessment <- !analysis
v3_assert(any(analysis) && any(assessment), "Stress split is empty.")
held_groups <- assignment[fold == coordinates$fold, stress_group]
train_groups <- assignment[fold != coordinates$fold, stress_group]
v3_assert(!length(intersect(held_groups, train_groups)), "Stress-group leakage detected.")

parameters <- as.list(recipe$parameters)
xgb_rounds <- if (model == "xgb") as.integer(recipe$best_iteration) else NULL
trees <- as.integer(context$config$rf$trees_stress)
locked <- v3_fit_locked(
  model, parameters, data, index, analysis, assessment, context, "stress", recipe$weight_scheme,
  trees = trees, xgb_rounds = xgb_rounds, smoke = FALSE, seed_task = task
)
prediction <- data.table::data.table(
  site_id = index$site_id[assessment], observed = index$sr87_sr86[assessment],
  predicted = locked$prediction, error = locked$prediction - index$sr87_sr86[assessment],
  hydro_system_id = index$hydro_system_id[assessment], model = model,
  scheme = coordinates$scheme, fold = coordinates$fold, task = task
)
metric <- v3_metrics(prediction$observed, prediction$predicted, prediction$hydro_system_id)
metric[, `:=`(model = model, scheme = coordinates$scheme, fold = coordinates$fold, task = task,
              structure_id = recipe$structure_id, weight_scheme = recipe$weight_scheme,
              best_iteration = if (model == "xgb") xgb_rounds else NA_integer_)]

directory <- file.path(run_dir, "validation_tasks", "stress", coordinates$scheme,
                       sprintf("fold_%02d", coordinates$fold), model)
dir.create(directory, recursive = TRUE, showWarnings = FALSE)
v3_atomic_fwrite(prediction, file.path(directory, "predictions.csv"))
v3_atomic_fwrite(metric, file.path(directory, "metrics.csv"))
v3_atomic_json(list(
  status = "complete", fixed_recipe = TRUE, retuned = FALSE, model = model,
  task = task, scheme = coordinates$scheme, fold = coordinates$fold,
  analysis_rows = sum(analysis), assessment_rows = sum(assessment),
  structure_id = recipe$structure_id, weight_scheme = recipe$weight_scheme,
  best_iteration = xgb_rounds,
  predictions_sha256 = v3_sha256(file.path(directory, "predictions.csv")),
  metrics_sha256 = v3_sha256(file.path(directory, "metrics.csv"))
), file.path(directory, "manifest.json"))
message(sprintf("Base V3 %s stress %s fold %d complete.", model, coordinates$scheme, coordinates$fold))
