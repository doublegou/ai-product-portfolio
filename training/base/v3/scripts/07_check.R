#!/usr/bin/env Rscript

source(file.path("training", "base", "v3", "R", "common.R"))
context <- v3_context()
args <- v3_parse_args(commandArgs(trailingOnly = TRUE))
run_id <- as.character(args$`run-id` %||% "")
v3_assert(nzchar(run_id), "--run-id is required.")
run_dir <- v3_run_dir(context, run_id)
v3_verify_fold_manifest(context)
manifest_path <- file.path(run_dir, "final_manifest.json")
v3_assert(file.exists(manifest_path), "Finalize the run before checking it.")
primary <- data.table::fread(file.path(run_dir, "reports", "primary", "overall_metrics.csv"))
stress <- data.table::fread(file.path(run_dir, "reports", "stress", "scheme_metrics.csv"))
training <- data.table::fread(file.path(run_dir, "reports", "training_metrics.csv"))
recipes <- data.table::rbindlist(lapply(c("rf", "xgb"), function(model) {
  recipe <- jsonlite::read_json(file.path(run_dir, "deployment", model, "frozen_recipe.json"), simplifyVector = TRUE)
  data.table::data.table(model = model, structure_id = recipe$structure_id, weight_scheme = recipe$weight_scheme,
                         best_iteration = recipe$best_iteration %||% NA_integer_)
}))

checks <- data.table::data.table(
  check = c("primary_has_two_models", "stress_has_eight_model_schemes", "training_has_two_models",
            "primary_predictions_complete", "all_primary_metrics_finite", "all_stress_metrics_finite",
            "release_not_auto_published"),
  passed = c(
    data.table::uniqueN(primary$model) == 2L,
    nrow(stress) == 8L,
    data.table::uniqueN(training$model) == 2L,
    all(primary$n == 16800L),
    all(is.finite(primary$rmse)) && all(is.finite(primary$mae)) && all(is.finite(primary$bias)),
    all(is.finite(stress$rmse)) && all(is.finite(stress$mae)),
    !isTRUE(jsonlite::read_json(manifest_path, simplifyVector = TRUE)$release_published)
  )
)
v3_assert(all(checks$passed), paste("Base V3 result checks failed:", paste(checks[passed == FALSE, check], collapse = ", ")))

report_dir <- file.path(run_dir, "reports")
v3_atomic_fwrite(checks, file.path(report_dir, "integrity_checks.csv"))
lines <- c(
  paste0("# Base V3 result review — ", run_id), "",
  "Status: engineering checks passed; scientific approval is intentionally manual.", "",
  "## Frozen deployment recipes", "",
  "| model | structure | weight | best iteration |", "|---|---:|---:|---:|",
  vapply(seq_len(nrow(recipes)), function(i) sprintf("| %s | %s | %s | %s |", recipes$model[i], recipes$structure_id[i],
                                                   recipes$weight_scheme[i], ifelse(is.na(recipes$best_iteration[i]), "—", recipes$best_iteration[i])), character(1)),
  "", "## Strict Primary pooled OOF", "",
  "| model | RMSE | MAE | bias | prediction max | >=0.80 hits | >=0.80 systems |", "|---|---:|---:|---:|---:|---:|---:|",
  vapply(seq_len(nrow(primary)), function(i) sprintf("| %s | %.6f | %.6f | %.6f | %.4f | %d | %d |",
      primary$model[i], primary$rmse[i], primary$mae[i], primary$bias[i], primary$prediction_max[i],
      primary$hit_080_count[i], primary$hit_080_system_count[i]), character(1)),
  "", "## Interpretation guardrail", "",
  "Training metrics are not generalization evidence. Compare Primary OOF first, then use the four frozen-recipe stress schemes to characterize deployment risk."
)
report_path <- file.path(report_dir, "RESULTS_DRAFT.md")
temporary <- paste0(report_path, ".tmp-", Sys.getpid())
writeLines(lines, temporary, useBytes = TRUE)
if (file.exists(report_path)) file.remove(report_path)
v3_assert(file.rename(temporary, report_path), "Could not publish result draft.")
message("Base V3 result checks passed. Review: ", normalizePath(report_path, winslash = "/"))
