v1_collect_primary_winners <- function(context) {
  manifest <- data.table::fread(
    v1_output_path(context, "validation_dir", "primary", "task_manifest.csv"), data.table = FALSE
  )
  records <- vector("list", nrow(manifest))
  for (i in seq_len(nrow(manifest))) {
    task_dir <- v1_primary_task_dir(context, manifest$repeat_id[[i]], manifest$outer_fold[[i]])
    v1_assert(v1_task_complete(task_dir, "primary"), paste("Incomplete Primary task:", task_dir))
    task_info <- jsonlite::read_json(file.path(task_dir, "task_info.json"), simplifyVector = TRUE)
    fold_manifest <- jsonlite::read_json(v1_fold_paths(context)[["manifest"]], simplifyVector = TRUE)
    v1_assert(identical(as.character(task_info$config_md5), as.character(fold_manifest$config$md5)), paste("Primary task used a different config:", task_dir))
    v1_assert(identical(as.integer(task_info$group_leakage), 0L), paste("Primary task did not pass its group leakage audit:", task_dir))
    selected <- yaml::read_yaml(file.path(task_dir, "selected_params.yml"))
    records[[i]] <- data.frame(
      task_id = as.integer(selected$task_id),
      repeat_id = as.integer(selected$repeat_id),
      outer_fold = as.integer(selected$outer_fold),
      source_grid_id = as.integer(selected$source_grid_id),
      mtry = as.integer(selected$mtry),
      min_node_size = as.integer(selected$min_node_size),
      sample_fraction = as.numeric(selected$sample_fraction),
      replace = as.logical(selected$replace),
      inner_pooled_rmse = as.numeric(selected$inner_pooled_rmse),
      stringsAsFactors = FALSE
    )
  }
  result <- do.call(rbind, records)
  v1_assert(nrow(result) == 15L, paste("Expected 15 Primary winners; found", nrow(result)))
  result
}

stage_run_deployment_tuning <- function(context, run_id, force = FALSE) {
  fold_manifest <- v1_assert_folds_current(context)
  v1_begin_run(context, run_id, commandArgs(trailingOnly = TRUE))
  models_dir <- v1_run_dir(context, run_id, "models")
  deployment_dir <- v1_run_dir(context, run_id, "deployment")
  selected_path <- file.path(models_dir, "selected_params.yml")
  if (file.exists(selected_path) && !force) {
    selected <- yaml::read_yaml(selected_path)
    v1_log("Deployment tuning already complete; selected recipe ", selected$recipe_md5, ".")
    return(invisible(selected))
  }
  winners <- v1_collect_primary_winners(context)
  keys <- vapply(seq_len(nrow(winners)), function(i) v1_parameter_key(winners[i, ]), character(1L))
  unique_indices <- !duplicated(keys)
  candidates <- winners[unique_indices, c("mtry", "min_node_size", "sample_fraction", "replace"), drop = FALSE]
  candidates$candidate_id <- seq_len(nrow(candidates))
  candidates <- candidates[c("candidate_id", "mtry", "min_node_size", "sample_fraction", "replace")]
  v1_assert(nrow(candidates) >= 1L && nrow(candidates) <= 15L, "Deployment candidate count is invalid.")

  dat <- v1_read_training_data(context)
  predictors <- v1_read_predictors(context)
  columns <- context$config$columns
  dat[[columns$row_id]] <- as.character(dat[[columns$row_id]])
  deployment_design <- data.table::fread(v1_fold_paths(context)[["deployment"]], data.table = FALSE)
  names(deployment_design)[names(deployment_design) == "deployment_fold"] <- "selection_fold"
  v1_log("Deployment tuning: evaluating ", nrow(candidates), " unique Primary winners on independent grouped 5-fold CV.")
  tuning <- v1_evaluate_candidates(
    dat = dat,
    predictors = predictors,
    analysis_ids = dat[[columns$row_id]],
    fold_design = deployment_design,
    candidates = candidates,
    fold_column = "selection_fold",
    trees = as.integer(context$config$model$deployment_trees),
    context = context,
    seed_base = as.integer(context$config$model$deployment_seed_base),
    task_id = 0L,
    stage = "deployment"
  )
  winner <- tuning$summary[1L, , drop = FALSE]
  recipe <- list(
    mtry = as.integer(winner$mtry),
    min_node_size = as.integer(winner$min_node_size),
    sample_fraction = as.numeric(winner$sample_fraction),
    replace = as.logical(winner$replace)
  )
  recipe$recipe_md5 <- v1_recipe_md5(recipe)
  selected <- c(recipe, list(
    deployment_candidate_id = as.integer(winner$candidate_id),
    deployment_pooled_rmse = as.numeric(winner$pooled_rmse),
    deployment_pooled_mae = as.numeric(winner$pooled_mae),
    deployment_pooled_r2 = as.numeric(winner$pooled_r2),
    deployment_pooled_bias = as.numeric(winner$pooled_bias),
    source_outer_winners = 15L,
    unique_deployment_candidates = nrow(candidates),
    selection_role = "full-data recipe selection only; not an unbiased performance estimate",
    selection_order = context$config$search$selection_order,
    fold_input_md5 = fold_manifest$input$md5
  ))
  dir.create(deployment_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(models_dir, recursive = TRUE, showWarnings = FALSE)
  v1_write_csv(winners, file.path(deployment_dir, "primary_outer_winners.csv"))
  v1_write_csv(candidates, file.path(deployment_dir, "deployment_candidates.csv"))
  v1_write_csv(tuning$fold_metrics, file.path(deployment_dir, "deployment_fold_metrics.csv"))
  v1_write_csv(tuning$summary, file.path(deployment_dir, "deployment_summary.csv"))
  v1_write_yaml(selected, selected_path)
  v1_log(
    "Deployment recipe selected: mtry=", selected$mtry,
    ", min.node.size=", selected$min_node_size,
    ", sample.fraction=", selected$sample_fraction,
    ", replace=", selected$replace,
    ", recipe=", selected$recipe_md5, "."
  )
  invisible(selected)
}
