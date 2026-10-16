v1_read_task_outputs <- function(context, kind = c("primary", "stress")) {
  kind <- match.arg(kind)
  manifest <- data.table::fread(
    v1_output_path(context, "validation_dir", kind, "task_manifest.csv"), data.table = FALSE
  )
  metrics <- vector("list", nrow(manifest))
  predictions <- vector("list", nrow(manifest))
  for (i in seq_len(nrow(manifest))) {
    task_dir <- if (kind == "primary") {
      v1_primary_task_dir(context, manifest$repeat_id[[i]], manifest$outer_fold[[i]])
    } else {
      v1_stress_task_dir(context, manifest$scheme[[i]], manifest$outer_fold[[i]])
    }
    v1_assert(v1_task_complete(task_dir, kind), paste("Incomplete", kind, "task:", task_dir))
    metrics[[i]] <- data.table::fread(file.path(task_dir, "outer_metrics.csv"), data.table = FALSE)
    predictions[[i]] <- data.table::fread(file.path(task_dir, "outer_predictions.csv"), integer64 = "character", data.table = FALSE)
  }
  list(manifest = manifest, metrics = do.call(rbind, metrics), predictions = do.call(rbind, predictions))
}

v1_primary_station_summary <- function(predictions, context) {
  expected_rows <- as.integer(context$config$validation$expected_rows)
  repeats <- as.integer(context$config$validation$repeats)
  v1_assert(nrow(predictions) == expected_rows * repeats, "Primary OOF prediction count is not 4,485 x 3.")
  key <- paste(predictions$row_id, predictions$repeat_id, sep = "__")
  v1_assert(!anyDuplicated(key), "A station has more than one Primary OOF prediction in a repeat.")
  per_row <- stats::aggregate(
    predicted ~ row_id + site_id + hydrological_group + longitude + latitude + reference_id + observed,
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
  v1_assert(nrow(result) == expected_rows, "Primary station summary does not contain 4,485 rows.")
  v1_assert(all(result$n_oof_predictions == repeats), "A station does not have exactly three Primary OOF predictions.")
  result$residual <- result$predicted - result$observed
  result
}

stage_summarize_run <- function(context, run_id) {
  v1_log("Aggregating 15 Primary and 20 fixed-recipe stress tasks.")
  primary <- v1_read_task_outputs(context, "primary")
  stress <- v1_read_task_outputs(context, "stress")
  station <- v1_primary_station_summary(primary$predictions, context)
  repeats <- sort(unique(primary$predictions$repeat_id))
  repeat_metrics <- do.call(rbind, lapply(repeats, function(repeat_id) {
    current <- primary$predictions[primary$predictions$repeat_id == repeat_id, , drop = FALSE]
    cbind(data.frame(evaluation = "primary_repeat", repeat_id = repeat_id), v1_calculate_metrics(current$observed, current$predicted))
  }))
  pooled_repeated <- cbind(
    data.frame(evaluation = "primary_all_repeated_oof", repeat_id = NA_integer_),
    v1_calculate_metrics(primary$predictions$observed, primary$predictions$predicted)
  )
  station_metrics <- cbind(
    data.frame(evaluation = "primary_station_mean_oof", repeat_id = NA_integer_),
    v1_calculate_metrics(station$observed, station$predicted)
  )
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
  v1_assert(nrow(stress$predictions) == as.integer(context$config$validation$expected_rows) * length(stress_schemes), "Stress prediction count is invalid.")
  stress_summary <- do.call(rbind, lapply(stress_schemes, function(scheme) {
    current <- stress$predictions[stress$predictions$scheme == scheme, , drop = FALSE]
    v1_assert(!anyDuplicated(current$row_id), paste("Duplicate stress OOF row for", scheme))
    cbind(data.frame(evaluation = scheme), v1_calculate_metrics(current$observed, current$predicted))
  }))
  selected <- yaml::read_yaml(v1_run_dir(context, run_id, "models", "selected_params.yml"))
  selected_recipe_md5 <- v1_recipe_md5(selected)
  v1_assert(
    length(unique(stress$metrics$recipe_md5)) == 1L && identical(as.character(unique(stress$metrics$recipe_md5)), selected_recipe_md5),
    "Stress tasks do not all use the deployment-selected recipe."
  )
  validation_summary <- rbind(
    data.frame(
      scheme = "hydrological",
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
        stringsAsFactors = FALSE
      )
    }))
  )

  reports_dir <- v1_run_dir(context, run_id, "reports")
  dir.create(reports_dir, recursive = TRUE, showWarnings = FALSE)
  v1_write_csv(primary$metrics, file.path(reports_dir, "primary_outer_fold_metrics.csv"))
  v1_write_csv(primary$predictions, file.path(reports_dir, "primary_repeated_oof_predictions.csv"))
  v1_write_csv(station, file.path(reports_dir, "primary_station_oof_summary.csv"))
  v1_write_csv(primary_summary, file.path(reports_dir, "primary_metrics.csv"))
  v1_write_csv(repeat_variation, file.path(reports_dir, "primary_repeat_variation.csv"))
  v1_write_csv(v1_tail_metrics(station, "primary_station_mean_oof"), file.path(reports_dir, "primary_tail_metrics.csv"))
  v1_write_csv(v1_threshold_metrics(station, "primary_station_mean_oof"), file.path(reports_dir, "primary_threshold_metrics.csv"))
  v1_write_csv(stress$metrics, file.path(reports_dir, "stress_outer_fold_metrics.csv"))
  v1_write_csv(stress$predictions, file.path(reports_dir, "stress_oof_predictions.csv"))
  v1_write_csv(stress_summary, file.path(reports_dir, "stress_metrics.csv"))
  stress_tail <- do.call(rbind, lapply(stress_schemes, function(scheme) {
    v1_tail_metrics(stress$predictions[stress$predictions$scheme == scheme, , drop = FALSE], scheme)
  }))
  stress_threshold <- do.call(rbind, lapply(stress_schemes, function(scheme) {
    v1_threshold_metrics(stress$predictions[stress$predictions$scheme == scheme, , drop = FALSE], scheme)
  }))
  v1_write_csv(stress_tail, file.path(reports_dir, "stress_tail_metrics.csv"))
  v1_write_csv(stress_threshold, file.path(reports_dir, "stress_threshold_metrics.csv"))
  v1_write_csv(validation_summary, file.path(reports_dir, "validation_summary.csv"))

  primary_headline <- validation_summary[validation_summary$scheme == "hydrological", , drop = FALSE]
  lines <- c(
    "# Base Model V1 run summary",
    "",
    paste0("- Run: `", run_id, "`"),
    "- Model: Full50 unweighted ranger Random Forest",
    "- Primary: 355 MAIN_BAS groups; 3 repeats x 5 Outer; 5 grouped Inner folds",
    paste0("- Primary station-mean OOF RMSE: ", signif(primary_headline$rmse, 7)),
    paste0("- Primary station-mean OOF MAE: ", signif(primary_headline$mae, 7)),
    paste0("- Primary station-mean OOF R²: ", signif(primary_headline$r2, 7)),
    paste0("- Primary station-mean OOF Bias: ", signif(primary_headline$bias, 7)),
    paste0("- Final recipe: mtry=", selected$mtry, ", min.node.size=", selected$min_node_size,
           ", sample.fraction=", selected$sample_fraction, ", replace=", selected$replace),
    paste0("- Recipe fingerprint: `", selected$recipe_md5, "`"),
    "- Deployment CV selected the recipe and is not reported as an unbiased benchmark.",
    "- Stress tests used this frozen recipe without retuning.",
    "",
    "Final-model in-sample metrics are sanity checks only; predictive performance comes from OOF results."
  )
  writeLines(lines, file.path(reports_dir, "run_summary.md"), useBytes = TRUE)
  v1_log("V1 reports written: ", reports_dir)
  invisible(validation_summary)
}

stage_release_run <- function(context, run_id, force = FALSE) {
  source_dir <- v1_run_dir(context, run_id)
  required <- c(
    model = file.path(source_dir, "models", "full50_rf_model.rds"),
    parameters = file.path(source_dir, "models", "selected_params.yml"),
    summary = file.path(source_dir, "reports", "validation_summary.csv"),
    primary = file.path(source_dir, "reports", "primary_metrics.csv"),
    config = file.path(source_dir, "config_used.yml")
  )
  v1_assert(all(file.exists(required)), paste("Run is not release-ready; missing:", paste(required[!file.exists(required)], collapse = ", ")))
  release_dir <- v1_output_path(context, "release_dir")
  targets <- file.path(release_dir, c(
    "model_bundle.rds", "selected_params.yml", "validation_summary.csv", "primary_metrics.csv",
    "config_used.yml", "release_info.json"
  ))
  existing <- targets[file.exists(targets)]
  v1_assert(length(existing) == 0L || force, "A frozen V1 release exists. Refusing to overwrite without --force.")
  dir.create(release_dir, recursive = TRUE, showWarnings = FALSE)
  destinations <- file.path(release_dir, c(
    "model_bundle.rds", "selected_params.yml", "validation_summary.csv", "primary_metrics.csv", "config_used.yml"
  ))
  copied <- file.copy(unname(required), destinations, overwrite = force)
  v1_assert(all(copied), "Failed to copy one or more V1 release artifacts.")
  v1_write_json(
    list(
      status = "frozen",
      source_run = run_id,
      released_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      model_md5 = unname(tools::md5sum(file.path(release_dir, "model_bundle.rds")))
    ),
    file.path(release_dir, "release_info.json")
  )
  v1_log("Frozen V1 release created directly in: ", release_dir)
  invisible(release_dir)
}
