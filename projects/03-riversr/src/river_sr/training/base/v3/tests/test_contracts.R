#!/usr/bin/env Rscript

source(file.path("training", "base", "v3", "R", "common.R"))
context <- v3_context()
data <- v3_read_training(context)
predictors <- v3_predictors(context)
rf <- v3_rf_pool(context)
xgb <- v3_xgb_pool(context)
training_path <- v3_path(context, context$config$input$training_csv)
stopifnot(
  nrow(data) == 5600L,
  length(predictors) == 50L,
  nrow(rf) == 378L,
  nrow(xgb) == 1728L,
  nrow(v3_maximin(rf, 48L, 1L)) == 48L,
  nrow(v3_maximin(xgb, 48L, 1L)) == 48L,
  length(unique(v3_maximin(rf, 48L, 1L)$structure_id)) == 48L,
  length(unique(v3_maximin(xgb, 48L, 1L)$structure_id)) == 48L,
  v3_sha256_text(training_path) == context$config$contract$training_sha256_lf
)

lf_file <- tempfile(fileext = ".txt")
crlf_file <- tempfile(fileext = ".txt")
writeBin(charToRaw("alpha\nbeta\n"), lf_file)
writeBin(charToRaw("alpha\r\nbeta\r\n"), crlf_file)
stopifnot(v3_sha256_text(lf_file) == v3_sha256_text(crlf_file))
unlink(c(lf_file, crlf_file))

synthetic <- data.table::data.table(
  candidate_id = c("a", "b", "c"), structure_id = c("a", "b", "c"),
  rmse = c(1, 1.004, 1.02), mae = c(1, .9, .5), bias = c(0, .01, 0), bias_abs = c(0, .01, 0),
  hit_080_system_count = c(0, 1, 100), hit_075_system_count = c(0, 1, 100),
  hit_080_rate = c(0, .1, 1), hit_075_080_rate = c(0, .1, 1), hit_072_075_rate = c(0, .1, 1),
  false_high_low_rate = c(0, 0, 0), high_bias_abs = c(.1, .05, 0)
)
ranked <- v3_rank_candidates(synthetic, context)
stopifnot(ranked[selection_rank == 1L, candidate_id] == "b", !ranked[candidate_id == "c", rmse_eligible])

deployment_evidence <- data.table::data.table(
  task = seq_len(7L),
  structure_id = c(rep("odd_group", 3L), rep("even_group", 4L)),
  selection_rank = as.integer(c(1L, 2L, 3L, 1L, 2L, 3L, 4L))
)
for (fixture in list(deployment_evidence, deployment_evidence[.N:1L])) {
  deployment_ranking <- v3_summarise_deployment_evidence(fixture)
  stopifnot(
    identical(typeof(deployment_ranking$tasks_evaluated), "integer"),
    identical(typeof(deployment_ranking$winner_count), "integer"),
    identical(typeof(deployment_ranking$median_rank), "double"),
    identical(typeof(deployment_ranking$mean_rank_fraction), "double"),
    deployment_ranking[structure_id == "odd_group", median_rank] == 2,
    deployment_ranking[structure_id == "even_group", median_rank] == 2.5
  )
}

fold_manifest <- file.path(context$base, "folds", "manifest.json")
if (file.exists(fold_manifest)) {
  v3_verify_fold_manifest(context)
  index <- data.table::fread(file.path(context$base, "folds", "training_index.csv"))
  outer <- data.table::fread(file.path(context$base, "folds", "outer_folds.csv"))
  inner <- data.table::fread(file.path(context$base, "folds", "inner_folds.csv"))
  stress <- data.table::fread(file.path(context$base, "folds", "stress_folds.csv"))
  stopifnot(
    nrow(index) == 5600L,
    nrow(outer) == 16800L,
    nrow(inner) > 0L,
    nrow(stress) == 22400L,
    data.table::uniqueN(index$hydro_system_id) == 364L
  )
  stopifnot(all(outer[, .N, by = .(site_id, repeat_id)]$N == 1L))
  outer_group <- unique(outer[, .(hydro_system_id, repeat_id, outer_fold)])
  stopifnot(all(outer_group[, .N, by = .(hydro_system_id, repeat_id)]$N == 1L))
  outer_sizes <- outer[, .N, by = .(repeat_id, outer_fold)]
  stopifnot(max(outer_sizes$N) - min(outer_sizes$N) < 50L)
  outer_wide <- data.table::dcast(outer_group, hydro_system_id ~ repeat_id, value.var = "outer_fold")
  stopifnot(mean(outer_wide[["1"]] == outer_wide[["2"]]) < 0.5)
  for (task_id in seq_len(15L)) {
    coordinates <- v3_task_coordinates(task_id)
    held_groups <- outer[repeat_id == coordinates$repeat_id & outer_fold == coordinates$outer_fold, unique(hydro_system_id)]
    current_inner <- inner[get("task") == task_id]
    stopifnot(
      !length(intersect(held_groups, current_inner$hydro_system_id)),
      nrow(current_inner) == nrow(index) - outer[repeat_id == coordinates$repeat_id & outer_fold == coordinates$outer_fold, .N],
      !anyDuplicated(current_inner$site_id),
      data.table::uniqueN(current_inner$inner_fold) == 5L,
      all(unique(current_inner[, .(hydro_system_id, inner_fold)])[, .N, by = hydro_system_id]$N == 1L)
    )
  }
  stopifnot(all(stress[, .N, by = .(scheme, site_id)]$N == 1L))
  stopifnot(all(unique(stress[, .(scheme, stress_group, fold)])[, .N, by = .(scheme, stress_group)]$N == 1L))
}
message("Base V3 contract tests passed.")
