#!/usr/bin/env Rscript

source(file.path("training", "base", "v3", "R", "common.R"))
context <- v3_context()
args <- v3_parse_args(commandArgs(trailingOnly = TRUE))
run_id <- as.character(args$`run-id` %||% "")
v3_assert(nzchar(run_id), "--run-id is required.")
run_dir <- v3_run_dir(context, run_id)
v3_verify_fold_manifest(context)
primary_decision_path <- file.path(run_dir, "reports", "primary", "algorithm_decision.json")
v3_assert(file.exists(primary_decision_path), "Primary aggregation is missing.")
primary_decision <- jsonlite::read_json(primary_decision_path, simplifyVector = TRUE)

message("Aggregating 40 fixed-recipe stress fits...")
stress_predictions <- list()
stress_fold_metrics <- list()
for (model in c("rf", "xgb")) {
  for (task in seq_len(20L)) {
    coordinates <- v3_stress_coordinates(task)
    directory <- file.path(run_dir, "validation_tasks", "stress", coordinates$scheme,
                           sprintf("fold_%02d", coordinates$fold), model)
    manifest_path <- file.path(directory, "manifest.json")
    v3_assert(file.exists(manifest_path), paste("Missing stress manifest:", manifest_path))
    manifest <- jsonlite::read_json(manifest_path, simplifyVector = TRUE)
    v3_assert(isTRUE(manifest$fixed_recipe) && !isTRUE(manifest$retuned), "Stress recipe contract failed.")
    stress_predictions[[length(stress_predictions) + 1L]] <- data.table::fread(file.path(directory, "predictions.csv"))
    stress_fold_metrics[[length(stress_fold_metrics) + 1L]] <- data.table::fread(file.path(directory, "metrics.csv"))
  }
}
stress_predictions <- data.table::rbindlist(stress_predictions, fill = TRUE)
stress_fold_metrics <- data.table::rbindlist(stress_fold_metrics, fill = TRUE)
stress_metrics <- stress_predictions[, v3_metrics(observed, predicted, hydro_system_id), by = .(model, scheme)]
stress_report_dir <- file.path(run_dir, "reports", "stress")
dir.create(stress_report_dir, recursive = TRUE, showWarnings = FALSE)
v3_atomic_fwrite(stress_predictions, file.path(stress_report_dir, "pooled_predictions.csv"))
v3_atomic_fwrite(stress_fold_metrics, file.path(stress_report_dir, "fold_metrics.csv"))
v3_atomic_fwrite(stress_metrics, file.path(stress_report_dir, "scheme_metrics.csv"))

message("Fitting final full-data RF and XGBoost sanity-check models...")
fold_dir <- file.path(context$base, "folds")
release <- readRDS(file.path(fold_dir, "training_release.rds"))
data <- data.table::as.data.table(release$data)
index <- data.table::as.data.table(release$index)
models_dir <- file.path(run_dir, "models")
dir.create(models_dir, recursive = TRUE, showWarnings = FALSE)
training_metrics <- list()
for (model in c("rf", "xgb")) {
  recipe_path <- file.path(run_dir, "deployment", model, "frozen_recipe.json")
  recipe <- jsonlite::read_json(recipe_path, simplifyVector = TRUE)
  parameters <- as.list(recipe$parameters)
  xgb_rounds <- if (model == "xgb") as.integer(recipe$best_iteration) else NULL
  trees <- as.integer(context$config$rf$trees_final)
  all_rows <- rep(TRUE, nrow(index))
  fitted <- v3_fit_locked(
    model, parameters, data, index, all_rows, all_rows, context, "final", recipe$weight_scheme,
    trees = trees, xgb_rounds = xgb_rounds, smoke = FALSE, seed_task = if (model == "rf") 1L else 2L
  )
  prediction <- fitted$prediction
  metric <- v3_metrics(index$sr87_sr86, prediction, index$hydro_system_id)
  metric[, `:=`(
    model = model,
    training_recall_075 = mean(prediction[index$sr87_sr86 >= 0.75] >= 0.75),
    training_recall_080 = mean(prediction[index$sr87_sr86 >= 0.80] >= 0.80),
    structure_id = recipe$structure_id, weight_scheme = recipe$weight_scheme,
    best_iteration = if (model == "xgb") xgb_rounds else NA_integer_
  )]
  training_metrics[[model]] <- metric
  bundle <- list(
    project = "base_v3", run_id = run_id, model_family = model,
    model = fitted$fit, predictors = v3_predictors(context), medians = fitted$medians,
    response = context$config$columns$response, recipe = recipe,
    training_sha256 = v3_sha256(v3_path(context, context$config$input$training_csv)),
    config_sha256 = v3_sha256(context$config_path),
    created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
  )
  v3_atomic_rds(bundle, file.path(models_dir, paste0(model, "_final_bundle.rds")))
  v3_atomic_fwrite(data.table::data.table(site_id = index$site_id, observed = index$sr87_sr86,
                                         predicted = prediction, error = prediction - index$sr87_sr86),
                   file.path(models_dir, paste0(model, "_training_predictions.csv")))
}
training_metrics <- data.table::rbindlist(training_metrics, fill = TRUE)
v3_atomic_fwrite(training_metrics, file.path(run_dir, "reports", "training_metrics.csv"))

final_manifest <- list(
  status = "awaiting_scientific_review",
  selected_algorithm_from_primary = primary_decision$selected_algorithm,
  stress_fits = list(rf = 20L, xgb = 20L),
  final_models = list(rf = "models/rf_final_bundle.rds", xgb = "models/xgb_final_bundle.rds"),
  release_published = FALSE,
  note = "Training metrics are fit-capacity sanity checks; Primary OOF and stress metrics are the generalization evidence."
)
v3_atomic_json(final_manifest, file.path(run_dir, "final_manifest.json"))
message("Base V3 formal run finalized and is awaiting scientific review: ", run_id)
