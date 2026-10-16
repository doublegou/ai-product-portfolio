v2_collect_primary_winners <- function(context) {
  manifest <- data.table::fread(
    v2_output_path(context, "validation_dir", "primary", "task_manifest.csv"), data.table = FALSE
  )
  records <- vector("list", nrow(manifest))
  for (i in seq_len(nrow(manifest))) {
    task_dir <- v2_primary_task_dir(context, manifest$repeat_id[[i]], manifest$outer_fold[[i]])
    v2_assert(v2_task_complete(task_dir, "primary"), paste("Incomplete Primary task:", task_dir))
    task_info <- jsonlite::read_json(file.path(task_dir, "task_info.json"), simplifyVector = TRUE)
    fold_manifest <- jsonlite::read_json(v2_fold_paths(context)[["manifest"]], simplifyVector = TRUE)
    v2_assert(identical(as.character(task_info$config_md5), as.character(fold_manifest$config$md5)), paste("Primary task used a different config:", task_dir))
    v2_assert(identical(as.integer(task_info$branch_leakage), 0L), paste("Primary task did not pass its branch leakage audit:", task_dir))
    v2_assert(identical(as.integer(task_info$downstream_purge_leakage), 0L), paste("Primary task did not pass its downstream-purge audit:", task_dir))
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
  v2_assert(nrow(result) == 15L, paste("Expected 15 Primary winners; found", nrow(result)))
  result
}

stage_deployment_tuning <- function(context, run_id, force = FALSE) {
  fold_manifest <- v2_assert_folds_current(context)
  v2_begin_run(context, run_id, commandArgs(trailingOnly = TRUE))
  models_dir <- v2_run_dir(context, run_id, "models")
  deployment_dir <- v2_run_dir(context, run_id, "deployment")
  selected_path <- file.path(models_dir, "selected_params.yml")
  if (file.exists(selected_path) && !force) {
    selected <- yaml::read_yaml(selected_path)
    v2_log("Deployment tuning already complete; selected recipe ", selected$recipe_md5, ".")
    return(invisible(selected))
  }
  winners <- v2_collect_primary_winners(context)

  dat <- v2_read_training_data(context)
  predictors <- v2_read_predictors(context)
  candidates <- v2_coarse_grid(length(predictors), context)
  names(candidates)[names(candidates) == "grid_id"] <- "candidate_id"
  columns <- context$config$columns
  dat[[columns$row_id]] <- as.character(dat[[columns$row_id]])
  deployment_design <- data.table::fread(v2_fold_paths(context)[["deployment"]], data.table = FALSE)
  names(deployment_design)[names(deployment_design) == "deployment_fold"] <- "selection_fold"
  v2_log("Deployment tuning: evaluating all ", nrow(candidates), " frozen ordinary-RF recipes on independent Purged-Branch 5-fold CV.")
  tuning <- v2_evaluate_candidates(
    dat = dat,
    predictors = predictors,
    role_design = deployment_design,
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
  recipe$recipe_md5 <- v2_recipe_md5(recipe)
  selected <- c(recipe, list(
    deployment_candidate_id = as.integer(winner$candidate_id),
    deployment_pooled_rmse = as.numeric(winner$pooled_rmse),
    deployment_branch_macro_rmse = as.numeric(winner$branch_macro_rmse),
    deployment_pooled_mae = as.numeric(winner$pooled_mae),
    deployment_pooled_r2 = as.numeric(winner$pooled_r2),
    deployment_pooled_bias = as.numeric(winner$pooled_bias),
    source_outer_winners = 15L,
    deployment_candidates = nrow(candidates),
    selection_role = "full-data recipe selection only; not an unbiased performance estimate",
    selection_order = context$config$search$selection_order,
    fold_input_md5 = fold_manifest$input$md5
  ))
  dir.create(deployment_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(models_dir, recursive = TRUE, showWarnings = FALSE)
  v2_write_csv(winners, file.path(deployment_dir, "primary_outer_winners.csv"))
  v2_write_csv(candidates, file.path(deployment_dir, "deployment_candidates.csv"))
  v2_write_csv(tuning$fold_metrics, file.path(deployment_dir, "deployment_fold_metrics.csv"))
  v2_write_csv(tuning$summary, file.path(deployment_dir, "deployment_summary.csv"))
  v2_write_yaml(selected, selected_path)
  v2_log(
    "Deployment recipe selected: mtry=", selected$mtry,
    ", min.node.size=", selected$min_node_size,
    ", sample.fraction=", selected$sample_fraction,
    ", replace=", selected$replace,
    ", recipe=", selected$recipe_md5, "."
  )
  invisible(selected)
}

stage_run_deployment_tuning <- stage_deployment_tuning
