v2_load_benchmark_recipe <- function(context) {
  path <- v2_path(context, context$config$input$benchmark_recipe)
  v2_assert(file.exists(path), paste("Missing frozen Base V1 benchmark recipe:", path))
  recipe <- yaml::read_yaml(path)
  required <- c("mtry", "min_node_size", "sample_fraction", "replace")
  v2_assert(all(required %in% names(recipe)), "Frozen benchmark recipe lacks required RF parameters.")
  recipe$replace <- as.logical(recipe$replace)
  recipe$recipe_md5 <- v2_recipe_md5(recipe)
  recipe
}

stage_run_benchmark_task <- function(
  context, design_id = NULL, outer_fold = NULL, task_id = NULL, force = FALSE
) {
  fold_manifest <- v2_assert_folds_current(context)
  task_manifest <- data.table::fread(
    v2_output_path(context, "validation_dir", "benchmark", "task_manifest.csv"),
    data.table = FALSE
  )
  if (!is.null(task_id)) {
    task <- task_manifest[task_manifest$task_id == as.integer(task_id), , drop = FALSE]
  } else {
    task <- task_manifest[
      task_manifest$design_id == as.character(design_id) &
        task_manifest$outer_fold == as.integer(outer_fold),
      , drop = FALSE
    ]
  }
  v2_assert(nrow(task) == 1L, "Benchmark task did not resolve to exactly one manifest row.")
  task_id <- as.integer(task$task_id[[1L]])
  design_id <- as.character(task$design_id[[1L]])
  outer_fold <- as.integer(task$outer_fold[[1L]])
  output_dir <- v2_benchmark_task_dir(context, design_id, outer_fold)
  recipe <- v2_load_benchmark_recipe(context)
  if (v2_task_complete(output_dir, "benchmark") && !force) {
    existing <- jsonlite::read_json(file.path(output_dir, "task_info.json"), simplifyVector = TRUE)
    v2_assert(identical(as.character(existing$config_md5), as.character(fold_manifest$config$md5)), "Existing benchmark task used a different V2 config.")
    v2_assert(identical(as.character(existing$recipe_md5), as.character(recipe$recipe_md5)), "Existing benchmark task used a different frozen recipe.")
    v2_log("Benchmark task already complete; skipped: ", design_id, " fold ", outer_fold, ".")
    return(invisible(existing))
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  options(river_sr.v2.log_file = file.path(output_dir, "run.log"))

  paths <- v2_fold_paths(context)
  all_design <- data.table::fread(paths[["benchmark"]], integer64 = "character", data.table = FALSE)
  design <- all_design[
    all_design$design_id == design_id & all_design$outer_fold == outer_fold,
    , drop = FALSE
  ]
  expected_rows <- as.integer(context$config$validation$expected_rows)
  v2_assert(nrow(design) == expected_rows && !anyDuplicated(design$row_id), "Benchmark task role table is incomplete.")
  dat <- v2_read_training_data(context)
  predictors <- v2_read_predictors(context)
  columns <- context$config$columns
  dat[[columns$row_id]] <- as.character(dat[[columns$row_id]])
  design <- design[match(dat[[columns$row_id]], design$row_id), , drop = FALSE]
  v2_assert(identical(as.character(design$row_id), as.character(dat[[columns$row_id]])), "Benchmark task changed training row order.")

  arms <- as.character(unlist(context$config$benchmark$arms))
  role_columns <- c(
    purged_branch = "purged_branch_role",
    naive_branch = "naive_branch_role",
    matched_terminal = "matched_terminal_role"
  )
  v2_assert(setequal(arms, names(role_columns)), "Configured benchmark arms are not implemented.")
  prediction_records <- vector("list", length(arms))
  metric_records <- vector("list", length(arms))
  median_records <- vector("list", length(arms))
  trees <- as.integer(context$config$benchmark$trees)
  threads <- v2_ranger_threads(context)

  for (arm_index in seq_along(arms)) {
    arm <- arms[[arm_index]]
    role <- design[[role_columns[[arm]]]]
    analysis_ids <- as.character(design$row_id[role == "analysis"])
    assessment_ids <- as.character(design$row_id[role == "assessment"])
    excluded_ids <- as.character(design$row_id[role %in% c("purged_downstream", "heldout_terminal_support")])
    v2_assert(length(analysis_ids) > 0L && length(assessment_ids) > 0L, paste("Benchmark arm lacks analysis or assessment rows:", arm))
    v2_assert(length(intersect(analysis_ids, assessment_ids)) == 0L, paste("Benchmark leakage in", arm))
    v2_assert(length(intersect(analysis_ids, excluded_ids)) == 0L, paste("Benchmark exclusion leakage in", arm))
    analysis <- dat[match(analysis_ids, dat[[columns$row_id]]), , drop = FALSE]
    assessment <- dat[match(assessment_ids, dat[[columns$row_id]]), , drop = FALSE]
    x_analysis_raw <- v2_numeric_predictors(analysis, predictors)
    x_assessment_raw <- v2_numeric_predictors(assessment, predictors)
    medians <- v2_fit_medians(x_analysis_raw)
    x_analysis <- v2_apply_medians(x_analysis_raw, medians)
    x_assessment <- v2_apply_medians(x_assessment_raw, medians)
    seed <- as.integer(context$config$benchmark$model_seed_base) + task_id * 100L + arm_index
    v2_log("Benchmark task ", task_id, ": ", design_id, " fold ", outer_fold, " arm ", arm, ".")
    model <- v2_fit_rf(
      x_analysis, analysis[[columns$response]], recipe, trees, seed, threads
    )
    predicted <- as.numeric(predict(model, data = x_assessment, num.threads = threads)$predictions)
    assessment_design <- design[match(assessment_ids, design$row_id), , drop = FALSE]
    predictions <- data.frame(
      task_id = task_id,
      design_id = design_id,
      scale_family = assessment_design$scale_family,
      minimum_station_support = assessment_design$minimum_station_support,
      arm = arm,
      outer_fold = outer_fold,
      row_id = assessment[[columns$row_id]],
      site_id = assessment[[columns$site_id]],
      branch_id = assessment_design$branch_id,
      terminal_component_id = assessment_design$terminal_component_id,
      longitude = assessment[[columns$longitude]],
      latitude = assessment[[columns$latitude]],
      reference_id = assessment[[columns$reference]],
      observed = assessment[[columns$response]],
      predicted = predicted,
      residual = predicted - assessment[[columns$response]],
      stringsAsFactors = FALSE
    )
    prediction_records[[arm_index]] <- predictions
    metric_records[[arm_index]] <- cbind(
      data.frame(
        task_id = task_id,
        design_id = design_id,
        scale_family = design$scale_family[[1L]],
        minimum_station_support = design$minimum_station_support[[1L]],
        arm = arm,
        outer_fold = outer_fold,
        mtry = as.integer(recipe$mtry),
        min_node_size = as.integer(recipe$min_node_size),
        sample_fraction = as.numeric(recipe$sample_fraction),
        replace = as.logical(recipe$replace),
        trees = trees,
        seed = seed,
        recipe_md5 = recipe$recipe_md5,
        n_analysis = length(analysis_ids),
        n_assessment = length(assessment_ids),
        n_excluded = length(excluded_ids),
        stringsAsFactors = FALSE
      ),
      v2_calculate_metrics(predictions$observed, predictions$predicted),
      v2_branch_macro_metrics(predictions$observed, predictions$predicted, predictions$branch_id)
    )
    median_records[[arm_index]] <- data.frame(
      arm = arm,
      feature = predictors,
      training_median = as.numeric(medians[predictors]),
      n_missing_analysis = vapply(analysis[predictors], function(x) sum(is.na(x)), integer(1L)),
      stringsAsFactors = FALSE
    )
    rm(model)
  }

  predictions <- do.call(rbind, prediction_records)
  metrics <- do.call(rbind, metric_records)
  tail <- do.call(rbind, lapply(arms, function(arm) {
    cbind(
      data.frame(task_id = task_id, design_id = design_id, arm = arm, outer_fold = outer_fold),
      v2_tail_metrics(predictions[predictions$arm == arm, , drop = FALSE], paste(design_id, arm, sep = "__"))
    )
  }))
  threshold <- do.call(rbind, lapply(arms, function(arm) {
    cbind(
      data.frame(task_id = task_id, design_id = design_id, arm = arm, outer_fold = outer_fold),
      v2_threshold_metrics(predictions[predictions$arm == arm, , drop = FALSE], paste(design_id, arm, sep = "__"))
    )
  }))
  v2_write_csv(predictions, file.path(output_dir, "outer_predictions.csv"))
  v2_write_csv(metrics, file.path(output_dir, "outer_metrics.csv"))
  v2_write_csv(tail, file.path(output_dir, "outer_tail_metrics.csv"))
  v2_write_csv(threshold, file.path(output_dir, "outer_threshold_metrics.csv"))
  v2_write_csv(do.call(rbind, median_records), file.path(output_dir, "outer_training_medians.csv"))
  info <- list(
    status = "complete",
    task_id = task_id,
    design_id = design_id,
    outer_fold = outer_fold,
    arms = arms,
    fits = length(arms),
    retuned = FALSE,
    trees_per_fit = trees,
    recipe_md5 = recipe$recipe_md5,
    config_md5 = fold_manifest$config$md5,
    completed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
  v2_write_json(info, file.path(output_dir, "task_info.json"))
  v2_log("Benchmark task ", task_id, " complete: ", design_id, " fold ", outer_fold, ".")
  invisible(info)
}

stage_run_all_benchmark <- function(context, force = FALSE) {
  manifest <- data.table::fread(
    v2_output_path(context, "validation_dir", "benchmark", "task_manifest.csv"),
    data.table = FALSE
  )
  for (i in seq_len(nrow(manifest))) {
    stage_run_benchmark_task(context, task_id = manifest$task_id[[i]], force = force)
  }
  invisible(manifest)
}
