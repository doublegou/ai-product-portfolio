#!/usr/bin/env Rscript

source(file.path("training", "base", "v3", "R", "common.R"))
context <- v3_context()
args <- v3_parse_args(commandArgs(trailingOnly = TRUE))
run_id <- as.character(args$`run-id` %||% "")
model <- as.character(args$model %||% "")
v3_assert(nzchar(run_id), "--run-id is required.")
v3_assert(model %in% c("rf", "xgb"), "--model must be rf or xgb.")
run_dir <- v3_run_dir(context, run_id)
v3_verify_fold_manifest(context)
v3_assert(file.exists(file.path(run_dir, "reports", "primary", "algorithm_decision.json")),
          "Aggregate Primary results before deployment tuning.")

fold_dir <- file.path(context$base, "folds")
release <- readRDS(file.path(fold_dir, "training_release.rds"))
data <- data.table::as.data.table(release$data)
index <- data.table::as.data.table(release$index)
pool <- data.table::fread(file.path(fold_dir, paste0(model, "_pool.csv")))
evidence <- list()
for (task in seq_len(15L)) {
  coordinates <- v3_task_coordinates(task)
  path <- file.path(run_dir, "validation_tasks", "primary",
                    sprintf("repeat_%02d", coordinates$repeat_id), sprintf("fold_%02d", coordinates$outer_fold),
                    model, "refinement_summary.csv")
  v3_assert(file.exists(path), paste("Missing refinement evidence:", path))
  table <- data.table::fread(path)
  table[, task := task]
  evidence[[task]] <- table
}
evidence <- data.table::rbindlist(evidence, fill = TRUE)
structure_evidence <- evidence[order(selection_rank), .SD[1L], by = .(task, structure_id)]
ranking <- structure_evidence[, .(
  tasks_evaluated = .N,
  winner_count = sum(selection_rank == 1L),
  median_rank = stats::median(selection_rank),
  mean_rank_fraction = mean(selection_rank / max(selection_rank))
), by = structure_id]
data.table::setorderv(ranking, c("winner_count", "tasks_evaluated", "mean_rank_fraction", "median_rank", "structure_id"),
                     c(-1L, -1L, 1L, 1L, 1L))
shortlist_ids <- head(ranking$structure_id, 16L)
shortlist <- pool[match(shortlist_ids, structure_id)]
v3_assert(nrow(shortlist) > 0L, "Deployment shortlist is empty.")

system_summary <- v3_group_summary(index, "hydro_system_id")
group_fold <- v3_balance_groups(system_summary, "hydro_system_id", 5L,
                                as.integer(context$config$validation$deployment_seed) + if (model == "xgb") 1L else 0L)
site_fold <- merge(index[, .(site_id, hydro_system_id)], group_fold, by = "hydro_system_id", sort = FALSE)
fold_lookup <- stats::setNames(site_fold$fold, site_fold$site_id)
deployment_fold <- as.integer(fold_lookup[index$site_id])
v3_assert(!anyNA(deployment_fold), "Deployment fold lookup failed.")

directory <- file.path(run_dir, "deployment", model)
dir.create(directory, recursive = TRUE, showWarnings = FALSE)
v3_atomic_fwrite(ranking, file.path(directory, "primary_structure_evidence.csv"))
v3_atomic_fwrite(shortlist, file.path(directory, "shortlist.csv"))
v3_atomic_fwrite(site_fold[, .(site_id, hydro_system_id, deployment_fold = fold)], file.path(directory, "folds.csv"))
summary <- v3_evaluate_candidates(
  model, shortlist, data, index, deployment_fold, context, "deployment",
  file.path(directory, "tuning_summary.csv"), smoke = FALSE, seed_task = 90L + if (model == "xgb") 1L else 0L
)
winner <- summary[selection_rank == 1L][1L]
parameters <- as.list(pool[structure_id == winner$structure_id][1L])
recipe <- list(
  status = "frozen", model = model, structure_id = winner$structure_id,
  weight_scheme = winner$weight_scheme, parameters = parameters,
  best_iteration = if (model == "xgb") as.integer(winner$best_iteration_median) else NULL,
  primary_evidence_tasks = 15L, deployment_tuning_folds = 5L,
  deployment_tuning_is_performance_estimate = FALSE,
  stress_may_retune = FALSE,
  selection_rule = "global_rmse_0.5pct_shortlist_then_tail_and_error_tiebreaks"
)
v3_atomic_json(recipe, file.path(directory, "frozen_recipe.json"))
manifest <- list(
  status = "complete", model = model, shortlisted_structures = nrow(shortlist),
  evaluated_candidates = nrow(summary), recipe = recipe,
  outputs = list(
    shortlist_sha256 = v3_sha256(file.path(directory, "shortlist.csv")),
    tuning_summary_sha256 = v3_sha256(file.path(directory, "tuning_summary.csv")),
    frozen_recipe_sha256 = v3_sha256(file.path(directory, "frozen_recipe.json"))
  )
)
v3_atomic_json(manifest, file.path(directory, "manifest.json"))
message("Frozen Base V3 deployment recipe for ", model, ": ", winner$structure_id, " + ", winner$weight_scheme)
