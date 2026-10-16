#!/usr/bin/env Rscript

source(file.path("training", "base", "v3", "R", "common.R"))
context <- v3_context()
args <- v3_parse_args(commandArgs(trailingOnly = TRUE))
model <- as.character(args$model %||% "")
task <- as.integer(args$task %||% NA)
model_value <- model
task_value <- task
run_id <- as.character(args$`run-id` %||% "")
smoke <- isTRUE(args$smoke)
v3_assert(model %in% c("rf", "xgb"), "--model must be rf or xgb.")
v3_assert(is.finite(task), "--task is required.")
v3_assert(nzchar(run_id), "--run-id is required.")
coordinates <- v3_task_coordinates(task)

fold_dir <- file.path(context$base, "folds")
v3_assert(file.exists(file.path(fold_dir, "manifest.json")), "Run prepare before Primary tasks.")
v3_verify_fold_manifest(context)
release <- readRDS(file.path(fold_dir, "training_release.rds"))
outer <- data.table::fread(file.path(fold_dir, "outer_folds.csv"))
inner <- data.table::fread(file.path(fold_dir, "inner_folds.csv"))
coarse_pool <- data.table::fread(file.path(fold_dir, "coarse_pool.csv"))
full_pool <- data.table::fread(file.path(fold_dir, paste0(model, "_pool.csv")))
data <- data.table::as.data.table(release$data)
index <- data.table::as.data.table(release$index)
v3_assert(identical(as.character(data[[context$config$columns$id]]), index$site_id), "Release/index alignment failed.")

outer_task <- outer[repeat_id == coordinates$repeat_id]
test_ids <- outer_task[outer_fold == coordinates$outer_fold, site_id]
analysis <- !index$site_id %in% test_ids
assessment <- !analysis
inner_task <- inner[get("task") == task_value]
inner_lookup <- stats::setNames(inner_task$inner_fold, inner_task$site_id)
fold_id <- as.integer(inner_lookup[index$site_id[analysis]])
v3_assert(!anyNA(fold_id), "Inner fold lookup is incomplete.")

if (smoke) {
  set.seed(78000L + task + if (model == "xgb") 100L else 0L)
  keep_train <- unlist(lapply(sort(unique(fold_id)), function(fold) {
    rows <- which(analysis)[fold_id == fold]
    sample(rows, min(length(rows), ceiling(context$config$runtime$smoke_rows * 0.8 / 5)))
  }))
  test_rows <- which(assessment)
  keep_test <- sample(test_rows, min(length(test_rows), floor(context$config$runtime$smoke_rows * 0.2)))
  keep <- sort(unique(c(keep_train, keep_test)))
  data <- data[keep]
  index <- index[keep]
  analysis <- index$site_id %in% release$index$site_id[keep_train]
  assessment <- index$site_id %in% release$index$site_id[keep_test]
  fold_id <- as.integer(inner_lookup[index$site_id[analysis]])
}

mode_dir <- if (smoke) "smoke" else "validation_tasks"
task_dir <- file.path(v3_run_dir(context, run_id), mode_dir, "primary",
                      sprintf("repeat_%02d", coordinates$repeat_id), sprintf("fold_%02d", coordinates$outer_fold), model)
dir.create(task_dir, recursive = TRUE, showWarnings = FALSE)

coarse <- coarse_pool[get("model") == model_value & get("task") == task_value]
if (smoke) coarse <- head(coarse, as.integer(context$config$runtime$smoke_structures))
coarse_summary <- v3_evaluate_candidates(
  model, coarse, data[analysis], index[analysis], fold_id, context, "coarse",
  file.path(task_dir, "coarse_summary.csv"), smoke = smoke, seed_task = task
)

refinement_n <- if (smoke) as.integer(context$config$runtime$smoke_structures) else
  as.integer(context$config[[model]]$refinement_structures)
refinement <- v3_select_refinement(full_pool, coarse_summary, refinement_n)
v3_atomic_fwrite(refinement, file.path(task_dir, "refinement_pool.csv"))
refinement_summary <- v3_evaluate_candidates(
  model, refinement, data[analysis], index[analysis], fold_id, context, "refinement",
  file.path(task_dir, "refinement_summary.csv"), smoke = smoke, seed_task = task
)
winner <- refinement_summary[selection_rank == 1L][1L]
parameters <- as.list(full_pool[structure_id == winner$structure_id][1L])
weight_scheme <- winner$weight_scheme
xgb_rounds <- if (model == "xgb") as.integer(winner$best_iteration_median) else NULL
trees <- if (smoke) as.integer(context$config$runtime$smoke_trees) else as.integer(context$config$rf$trees_outer)

locked <- v3_fit_locked(
  model, parameters, data, index, analysis, assessment, context, "outer", weight_scheme,
  trees = trees, xgb_rounds = xgb_rounds, smoke = smoke, seed_task = task
)
prediction <- data.table::data.table(
  site_id = index$site_id[assessment], observed = index$sr87_sr86[assessment],
  predicted = locked$prediction, error = locked$prediction - index$sr87_sr86[assessment],
  hydro_system_id = index$hydro_system_id[assessment], repeat_id = coordinates$repeat_id,
  outer_fold = coordinates$outer_fold, task = task, model = model
)
metric <- v3_metrics(prediction$observed, prediction$predicted, prediction$hydro_system_id)
metric[, `:=`(model = model, task = task, repeat_id = coordinates$repeat_id, outer_fold = coordinates$outer_fold,
              structure_id = winner$structure_id, weight_scheme = weight_scheme,
              best_iteration = if (model == "xgb") xgb_rounds else NA_integer_)]

v3_atomic_fwrite(prediction, file.path(task_dir, "outer_predictions.csv"))
v3_atomic_fwrite(metric, file.path(task_dir, "outer_metrics.csv"))
v3_atomic_rds(list(model = locked$fit, medians = locked$medians, predictors = v3_predictors(context),
                   parameters = parameters, weight_scheme = weight_scheme, best_iteration = xgb_rounds),
              file.path(task_dir, "selected_outer_fit.rds"))
recipe <- list(
  model = model, task = task, repeat_id = coordinates$repeat_id, outer_fold = coordinates$outer_fold,
  structure_id = winner$structure_id, weight_scheme = weight_scheme,
  parameters = parameters, best_iteration = xgb_rounds,
  selection_rule = "global_rmse_0.5pct_shortlist_then_tail_and_error_tiebreaks",
  outer_test_used_for_selection = FALSE
)
v3_atomic_json(recipe, file.path(task_dir, "selected_recipe.json"))
files <- c("coarse_summary.csv", "refinement_pool.csv", "refinement_summary.csv", "outer_predictions.csv",
           "outer_metrics.csv", "selected_outer_fit.rds", "selected_recipe.json")
manifest <- list(
  status = "complete", model = model, task = task, repeat_id = coordinates$repeat_id,
  outer_fold = coordinates$outer_fold, smoke = smoke,
  rows = list(analysis = sum(analysis), assessment = sum(assessment)),
  candidates = list(coarse = nrow(coarse_summary), refinement = nrow(refinement_summary)),
  winner = recipe,
  outputs = stats::setNames(lapply(files, function(name) list(sha256 = v3_sha256(file.path(task_dir, name)))), files)
)
v3_atomic_json(manifest, file.path(task_dir, "manifest.json"))
message(sprintf("Base V3 %s Primary task %d complete: %s", model, task, normalizePath(task_dir, winslash = "/")))
