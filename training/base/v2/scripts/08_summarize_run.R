v2_read_task_outputs <- function(context, kind = c("primary", "stress")) {
  kind <- match.arg(kind)
  manifest <- data.table::fread(
    v2_output_path(context, "validation_dir", kind, "task_manifest.csv"), data.table = FALSE
  )
  metrics <- vector("list", nrow(manifest))
  predictions <- vector("list", nrow(manifest))
  for (i in seq_len(nrow(manifest))) {
    task_dir <- if (kind == "primary") {
      v2_primary_task_dir(context, manifest$repeat_id[[i]], manifest$outer_fold[[i]])
    } else {
      v2_stress_task_dir(context, manifest$scheme[[i]], manifest$outer_fold[[i]])
    }
    v2_assert(v2_task_complete(task_dir, kind), paste("Incomplete", kind, "task:", task_dir))
    metrics[[i]] <- data.table::fread(file.path(task_dir, "outer_metrics.csv"), data.table = FALSE)
    predictions[[i]] <- data.table::fread(file.path(task_dir, "outer_predictions.csv"), integer64 = "character", data.table = FALSE)
  }
  list(manifest = manifest, metrics = do.call(rbind, metrics), predictions = do.call(rbind, predictions))
}

v2_read_benchmark_outputs <- function(context) {
  manifest <- data.table::fread(
    v2_output_path(context, "validation_dir", "benchmark", "task_manifest.csv"),
    data.table = FALSE
  )
  metrics <- vector("list", nrow(manifest))
  predictions <- vector("list", nrow(manifest))
  for (i in seq_len(nrow(manifest))) {
    task_dir <- v2_benchmark_task_dir(
      context, manifest$design_id[[i]], manifest$outer_fold[[i]]
    )
    v2_assert(v2_task_complete(task_dir, "benchmark"), paste("Incomplete benchmark task:", task_dir))
    metrics[[i]] <- data.table::fread(file.path(task_dir, "outer_metrics.csv"), data.table = FALSE)
    predictions[[i]] <- data.table::fread(
      file.path(task_dir, "outer_predictions.csv"), integer64 = "character", data.table = FALSE
    )
  }
  list(
    manifest = manifest,
    metrics = do.call(rbind, metrics),
    predictions = do.call(rbind, predictions)
  )
}

v2_summarize_benchmark <- function(context, benchmark) {
  designs <- data.table::fread(
    v2_fold_paths(context)[["benchmark_designs"]], data.table = FALSE
  )
  arms <- as.character(unlist(context$config$benchmark$arms))
  expected_recipe <- v2_load_benchmark_recipe(context)$recipe_md5
  v2_assert(
    nrow(benchmark$manifest) == 45L && nrow(benchmark$metrics) == 135L,
    "Benchmark does not contain 45 tasks and 135 arm-level fits."
  )
  v2_assert(
    length(unique(benchmark$metrics$recipe_md5)) == 1L &&
      identical(as.character(unique(benchmark$metrics$recipe_md5)), as.character(expected_recipe)),
    "Benchmark tasks do not all use the frozen Base V1 recipe."
  )

  summary_rows <- list()
  tail_rows <- list()
  threshold_rows <- list()
  index <- 0L
  for (design_id in designs$design_id) for (arm in arms) {
    current <- benchmark$predictions[
      benchmark$predictions$design_id == design_id & benchmark$predictions$arm == arm,
      , drop = FALSE
    ]
    expected_rows <- as.integer(designs$n_eligible_rows[designs$design_id == design_id])
    v2_assert(nrow(current) == expected_rows, paste("Benchmark OOF row count is invalid for", design_id, arm))
    v2_assert(!anyDuplicated(current$row_id), paste("Duplicate benchmark OOF row for", design_id, arm))
    index <- index + 1L
    summary_rows[[index]] <- cbind(
      data.frame(
        design_id = design_id,
        scale_family = designs$scale_family[designs$design_id == design_id],
        minimum_station_support = designs$minimum_station_support[designs$design_id == design_id],
        arm = arm,
        n_outer_folds = as.integer(context$config$benchmark$folds),
        stringsAsFactors = FALSE
      ),
      v2_calculate_metrics(current$observed, current$predicted),
      v2_branch_macro_metrics(current$observed, current$predicted, current$branch_id)
    )
    tail_rows[[index]] <- cbind(
      data.frame(design_id = design_id, arm = arm),
      v2_tail_metrics(current, paste(design_id, arm, sep = "__"))
    )
    threshold_rows[[index]] <- cbind(
      data.frame(design_id = design_id, arm = arm),
      v2_threshold_metrics(current, paste(design_id, arm, sep = "__"))
    )
  }
  summary <- do.call(rbind, summary_rows)
  tail <- do.call(rbind, tail_rows)
  threshold <- do.call(rbind, threshold_rows)

  population_keys <- stats::aggregate(
    row_id ~ design_id + arm, benchmark$predictions,
    function(x) digest::digest(sort(as.character(x)), algo = "md5", serialize = FALSE)
  )
  for (design_id in designs$design_id) {
    current <- population_keys[population_keys$design_id == design_id, , drop = FALSE]
    v2_assert(length(unique(current$row_id)) == 1L, paste("Benchmark arms use different OOF populations for", design_id))
  }

  comparisons <- list()
  comparison_index <- 0L
  for (design_id in designs$design_id) for (comparator in c("naive_branch", "matched_terminal")) {
    purged <- summary[summary$design_id == design_id & summary$arm == "purged_branch", , drop = FALSE]
    other <- summary[summary$design_id == design_id & summary$arm == comparator, , drop = FALSE]
    purged_075 <- threshold[
      threshold$design_id == design_id & threshold$arm == "purged_branch" & threshold$threshold == 0.75,
      , drop = FALSE
    ]
    other_075 <- threshold[
      threshold$design_id == design_id & threshold$arm == comparator & threshold$threshold == 0.75,
      , drop = FALSE
    ]
    v2_assert(nrow(purged) == 1L && nrow(other) == 1L && nrow(purged_075) == 1L && nrow(other_075) == 1L, "Benchmark comparison row is missing.")
    comparison_index <- comparison_index + 1L
    comparisons[[comparison_index]] <- data.frame(
      design_id = design_id,
      scale_family = purged$scale_family,
      minimum_station_support = purged$minimum_station_support,
      comparator = comparator,
      purged_rmse = purged$rmse,
      comparator_rmse = other$rmse,
      rmse_improvement = other$rmse - purged$rmse,
      relative_rmse_improvement = (other$rmse - purged$rmse) / other$rmse,
      purged_mae = purged$mae,
      comparator_mae = other$mae,
      mae_improvement = other$mae - purged$mae,
      purged_abs_bias = abs(purged$bias),
      comparator_abs_bias = abs(other$bias),
      absolute_bias_improvement = abs(other$bias) - abs(purged$bias),
      purged_branch_macro_rmse = purged$branch_macro_rmse,
      comparator_branch_macro_rmse = other$branch_macro_rmse,
      branch_macro_rmse_improvement = other$branch_macro_rmse - purged$branch_macro_rmse,
      purged_abs_bias_ge_0_75 = abs(purged_075$bias),
      comparator_abs_bias_ge_0_75 = abs(other_075$bias),
      absolute_bias_ge_0_75_improvement = abs(other_075$bias) - abs(purged_075$bias),
      stringsAsFactors = FALSE
    )
  }
  list(
    designs = designs,
    metrics = summary,
    tail = tail,
    threshold = threshold,
    comparisons = do.call(rbind, comparisons)
  )
}

v2_primary_station_summary <- function(predictions, context) {
  fold_manifest <- v2_assert_folds_current(context)
  expected_rows <- as.integer(fold_manifest$topology$n_primary_eligible_rows)
  repeats <- as.integer(context$config$validation$repeats)
  v2_assert(nrow(predictions) == expected_rows * repeats, "Primary OOF prediction count is not eligible rows x repeats.")
  key <- paste(predictions$row_id, predictions$repeat_id, sep = "__")
  v2_assert(!anyDuplicated(key), "A station has more than one Primary OOF prediction in a repeat.")
  per_row <- stats::aggregate(
    predicted ~ row_id + site_id + branch_id + terminal_component_id + longitude + latitude + reference_id + observed,
    predictions,
    function(x) c(mean = mean(x), sd = stats::sd(x), n = length(x), min = min(x), max = max(x))
  )
  values <- if (is.matrix(per_row$predicted)) per_row$predicted else do.call(rbind, per_row$predicted)
  per_row$predicted <- NULL
  result <- cbind(per_row, data.frame(
    predicted = values[, "mean"],
    prediction_sd = values[, "sd"],
    n_oof_predictions = as.integer(values[, "n"]),
    prediction_min = values[, "min"],
    prediction_max = values[, "max"]
  ))
  v2_assert(nrow(result) == expected_rows, "Primary station summary does not contain every branch-eligible row.")
  v2_assert(all(result$n_oof_predictions == repeats), "A station does not have exactly three Primary OOF predictions.")
  result$residual <- result$predicted - result$observed
  result
}

v2_primary_metric_row <- function(predictions, evaluation, repeat_id = NA_integer_) {
  cbind(
    data.frame(evaluation = evaluation, repeat_id = repeat_id),
    v2_calculate_metrics(predictions$observed, predictions$predicted),
    v2_branch_macro_metrics(predictions$observed, predictions$predicted, predictions$branch_id)
  )
}

stage_summarize_run <- function(context, run_id) {
  v2_log("Aggregating 45 branch-methodology benchmark, 15 Primary and 25 fixed-recipe stress tasks.")
  benchmark <- v2_read_benchmark_outputs(context)
  benchmark_summary <- v2_summarize_benchmark(context, benchmark)
  primary <- v2_read_task_outputs(context, "primary")
  stress <- v2_read_task_outputs(context, "stress")
  station <- v2_primary_station_summary(primary$predictions, context)
  repeats <- sort(unique(primary$predictions$repeat_id))
  repeat_metrics <- do.call(rbind, lapply(repeats, function(repeat_id) {
    current <- primary$predictions[primary$predictions$repeat_id == repeat_id, , drop = FALSE]
    v2_primary_metric_row(current, "primary_repeat", repeat_id)
  }))
  pooled_repeated <- v2_primary_metric_row(primary$predictions, "primary_all_repeated_oof")
  station_metrics <- v2_primary_metric_row(station, "primary_station_mean_oof")
  primary_summary <- rbind(repeat_metrics, pooled_repeated, station_metrics)
  repeat_variation <- data.frame(
    metric = c("rmse", "mae", "r2", "bias", "calibration_slope"),
    repeat_mean = c(
      mean(repeat_metrics$rmse), mean(repeat_metrics$mae), mean(repeat_metrics$r2),
      mean(repeat_metrics$bias), mean(repeat_metrics$calibration_slope)
    ),
    repeat_sd = c(
      stats::sd(repeat_metrics$rmse), stats::sd(repeat_metrics$mae), stats::sd(repeat_metrics$r2),
      stats::sd(repeat_metrics$bias), stats::sd(repeat_metrics$calibration_slope)
    )
  )

  stress_schemes <- unique(stress$manifest$scheme)
  v2_assert(nrow(stress$predictions) == as.integer(context$config$validation$expected_rows) * length(stress_schemes), "Stress prediction count is invalid.")
  stress_summary <- do.call(rbind, lapply(stress_schemes, function(scheme) {
    current <- stress$predictions[stress$predictions$scheme == scheme, , drop = FALSE]
    v2_assert(!anyDuplicated(current$row_id), paste("Duplicate stress OOF row for", scheme))
    cbind(data.frame(evaluation = scheme), v2_calculate_metrics(current$observed, current$predicted))
  }))
  selected <- yaml::read_yaml(v2_run_dir(context, run_id, "models", "selected_params.yml"))
  selected_recipe_md5 <- v2_recipe_md5(selected)
  v2_assert(
    length(unique(stress$metrics$recipe_md5)) == 1L && identical(as.character(unique(stress$metrics$recipe_md5)), selected_recipe_md5),
    "Stress tasks do not all use the deployment-selected recipe."
  )
  validation_summary <- rbind(
    data.frame(
      scheme = "purged_branch_primary",
      role = "primary",
      prediction_definition = "mean of 3 strict OOF predictions per station",
      station_metrics,
      stringsAsFactors = FALSE
    )[c("scheme", "role", "prediction_definition", names(station_metrics)[!names(station_metrics) %in% c("evaluation", "repeat_id")])],
    do.call(rbind, lapply(seq_len(nrow(stress_summary)), function(i) {
      data.frame(
        scheme = stress_summary$evaluation[[i]], role = "stress",
        prediction_definition = "one fixed-recipe OOF prediction per station",
        stress_summary[i, setdiff(names(stress_summary), "evaluation"), drop = FALSE],
        n_branches = NA_integer_, branch_macro_rmse = NA_real_, branch_macro_mae = NA_real_,
        stringsAsFactors = FALSE
      )
    }))
  )

  reports_dir <- v2_run_dir(context, run_id, "reports")
  dir.create(reports_dir, recursive = TRUE, showWarnings = FALSE)
  v2_write_csv(benchmark$metrics, file.path(reports_dir, "benchmark_outer_fold_metrics.csv"))
  v2_write_csv(benchmark$predictions, file.path(reports_dir, "benchmark_oof_predictions.csv"))
  v2_write_csv(benchmark_summary$designs, file.path(reports_dir, "benchmark_designs.csv"))
  v2_write_csv(benchmark_summary$metrics, file.path(reports_dir, "benchmark_design_metrics.csv"))
  v2_write_csv(benchmark_summary$tail, file.path(reports_dir, "benchmark_tail_metrics.csv"))
  v2_write_csv(benchmark_summary$threshold, file.path(reports_dir, "benchmark_threshold_metrics.csv"))
  v2_write_csv(benchmark_summary$comparisons, file.path(reports_dir, "benchmark_pairwise_comparison.csv"))
  v2_write_csv(primary$metrics, file.path(reports_dir, "primary_outer_fold_metrics.csv"))
  v2_write_csv(primary$predictions, file.path(reports_dir, "primary_repeated_oof_predictions.csv"))
  v2_write_csv(station, file.path(reports_dir, "primary_station_oof_summary.csv"))
  v2_write_csv(primary_summary, file.path(reports_dir, "primary_metrics.csv"))
  v2_write_csv(repeat_variation, file.path(reports_dir, "primary_repeat_variation.csv"))
  v2_write_csv(v2_tail_metrics(station, "primary_station_mean_oof"), file.path(reports_dir, "primary_tail_metrics.csv"))
  v2_write_csv(v2_threshold_metrics(station, "primary_station_mean_oof"), file.path(reports_dir, "primary_threshold_metrics.csv"))
  v2_write_csv(stress$metrics, file.path(reports_dir, "stress_outer_fold_metrics.csv"))
  v2_write_csv(stress$predictions, file.path(reports_dir, "stress_oof_predictions.csv"))
  v2_write_csv(stress_summary, file.path(reports_dir, "stress_metrics.csv"))
  stress_tail <- do.call(rbind, lapply(stress_schemes, function(scheme) {
    v2_tail_metrics(stress$predictions[stress$predictions$scheme == scheme, , drop = FALSE], scheme)
  }))
  stress_threshold <- do.call(rbind, lapply(stress_schemes, function(scheme) {
    v2_threshold_metrics(stress$predictions[stress$predictions$scheme == scheme, , drop = FALSE], scheme)
  }))
  v2_write_csv(stress_tail, file.path(reports_dir, "stress_tail_metrics.csv"))
  v2_write_csv(stress_threshold, file.path(reports_dir, "stress_threshold_metrics.csv"))
  v2_write_csv(validation_summary, file.path(reports_dir, "validation_summary.csv"))

  primary_headline <- validation_summary[validation_summary$scheme == "purged_branch_primary", , drop = FALSE]
  matched <- benchmark_summary$comparisons[
    benchmark_summary$comparisons$comparator == "matched_terminal", , drop = FALSE
  ]
  naive <- benchmark_summary$comparisons[
    benchmark_summary$comparisons$comparator == "naive_branch", , drop = FALSE
  ]
  lines <- c(
    "# Base Model V2 run summary",
    "",
    paste0("- Run: `", run_id, "`"),
    "- Model: Full50 unweighted ranger Random Forest",
    paste0("- Primary: ", v2_assert_folds_current(context)$topology$n_primary_branches,
           " forward-reconstructed branches; 3 repeats x 5 Outer; 5 nested Purged-Branch Inner folds"),
    paste0("- Primary assessment population: ", nrow(station), " branch-eligible stations"),
    paste0("- Primary station-mean OOF RMSE: ", signif(primary_headline$rmse, 7)),
    paste0("- Primary station-mean OOF MAE: ", signif(primary_headline$mae, 7)),
    paste0("- Primary station-mean OOF R²: ", signif(primary_headline$r2, 7)),
    paste0("- Primary station-mean OOF Bias: ", signif(primary_headline$bias, 7)),
    paste0("- Primary branch-macro RMSE: ", signif(primary_headline$branch_macro_rmse, 7)),
    paste0("- Methodology benchmark: 9 designs x 5 folds x 3 fixed-recipe arms (135 fits; no retuning)."),
    paste0("- Purged better than matched terminal: RMSE ", sum(matched$rmse_improvement > 0), "/9; MAE ",
           sum(matched$mae_improvement > 0), "/9; |bias| at Sr >= 0.75 ",
           sum(matched$absolute_bias_ge_0_75_improvement > 0), "/9; branch-macro RMSE ",
           sum(matched$branch_macro_rmse_improvement > 0), "/9."),
    paste0("- Purged better than naive branch: RMSE ", sum(naive$rmse_improvement > 0), "/9; MAE ",
           sum(naive$mae_improvement > 0), "/9; |bias| at Sr >= 0.75 ",
           sum(naive$absolute_bias_ge_0_75_improvement > 0), "/9; branch-macro RMSE ",
           sum(naive$branch_macro_rmse_improvement > 0), "/9."),
    paste0("- Final recipe: mtry=", selected$mtry, ", min.node.size=", selected$min_node_size,
           ", sample.fraction=", selected$sample_fraction, ", replace=", selected$replace),
    paste0("- Recipe fingerprint: `", selected$recipe_md5, "`"),
    "- Deployment CV selected the recipe and is not reported as an unbiased benchmark.",
    "- The branch-methodology benchmark used the frozen Base V1 recipe and did not participate in V2 parameter selection.",
    "- Stress tests used this frozen recipe without retuning.",
    "",
    "Final-model in-sample metrics are sanity checks only; predictive performance comes from OOF results."
  )
  writeLines(lines, file.path(reports_dir, "run_summary.md"), useBytes = TRUE)
  v2_log("V2 reports written: ", reports_dir)
  invisible(validation_summary)
}

stage_release_run <- function(context, run_id, force = FALSE) {
  source_dir <- v2_run_dir(context, run_id)
  required <- c(
    model = file.path(source_dir, "models", "full50_rf_model.rds"),
    parameters = file.path(source_dir, "models", "selected_params.yml"),
    medians = file.path(source_dir, "models", "training_medians.csv"),
    summary = file.path(source_dir, "reports", "validation_summary.csv"),
    primary = file.path(source_dir, "reports", "primary_metrics.csv"),
    benchmark = file.path(source_dir, "reports", "benchmark_pairwise_comparison.csv"),
    config = file.path(source_dir, "config_used.yml"),
    folds = v2_fold_paths(context)[["manifest"]],
    predictors = v2_path(context, context$config$input$predictors)
  )
  v2_assert(all(file.exists(required)), paste("Run is not release-ready; missing:", paste(required[!file.exists(required)], collapse = ", ")))
  release_dir <- v2_output_path(context, "release_dir")
  targets <- file.path(release_dir, c(
    "model_bundle.rds", "selected_params.yml", "training_medians.csv", "validation_summary.csv", "primary_metrics.csv",
    "benchmark_pairwise_comparison.csv",
    "config_used.yml", "fold_manifest.json", "full50_predictors.txt", "training_rows.csv", "release_info.json", "README.md"
  ))
  existing <- targets[file.exists(targets)]
  v2_assert(length(existing) == 0L || force, "A frozen V2 release exists. Refusing to overwrite without --force.")
  dir.create(release_dir, recursive = TRUE, showWarnings = FALSE)
  destinations <- file.path(release_dir, c(
    "model_bundle.rds", "selected_params.yml", "training_medians.csv", "validation_summary.csv", "primary_metrics.csv",
    "benchmark_pairwise_comparison.csv",
    "config_used.yml", "fold_manifest.json", "full50_predictors.txt"
  ))
  copied <- file.copy(unname(required), destinations, overwrite = force)
  v2_assert(all(copied), "Failed to copy one or more V2 release artifacts.")
  dat <- v2_read_training_data(context)
  columns <- context$config$columns
  v2_write_csv(dat[c(columns$row_id, columns$site_id)], file.path(release_dir, "training_rows.csv"))
  release_files <- setdiff(list.files(release_dir, full.names = TRUE), file.path(release_dir, c("release_info.json", "README.md")))
  v2_write_json(list(
    status = "frozen", source_run = run_id,
    released_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    artifacts = lapply(release_files, v2_file_signature, relative_to = context$repo_root)
  ), file.path(release_dir, "release_info.json"))
  writeLines(c(
    "# Base V2 frozen release", "",
    paste0("Source run: `", run_id, "`"), "",
    "Full50 ordinary RF selected by independent Primary Purged-Branch deployment CV.",
    "Primary performance is defined only on the frozen branch-eligible OOF population."
  ), file.path(release_dir, "README.md"), useBytes = TRUE)
  v2_log("Frozen V2 release created directly in: ", release_dir)
  invisible(release_dir)
}
