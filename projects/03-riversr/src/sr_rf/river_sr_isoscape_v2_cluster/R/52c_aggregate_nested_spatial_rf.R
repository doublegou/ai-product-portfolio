source("R/functions/core.R")

check_packages(
  c(
    "dplyr",
    "readr",
    "tibble",
    "tidyr"
  )
)

root <- project_root()

r52_dir <- file.path(
  root,
  "outputs",
  "r52_nested_spatial_rf"
)

task_root <- file.path(
  r52_dir,
  "tasks"
)

out_dir <- file.path(
  r52_dir,
  "aggregate"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

manifest_file <- file.path(
  r52_dir,
  "task_manifest.csv"
)

if (!file.exists(manifest_file)) {
  stop(
    "Missing task manifest: ",
    manifest_file
  )
}

manifest <- readr::read_csv(
  manifest_file,
  show_col_types = FALSE
)

if (
  nrow(manifest) != 45L ||
  !identical(
    as.integer(manifest$task_id),
    1:45
  )
) {
  stop(
    "Task manifest must contain task IDs 1:45."
  )
}

required_task_files <- c(
  "run_summary.txt",
  "outer_metrics.csv",
  "outer_predictions.csv",
  "outer_regime_metrics.csv",
  "selected_hyperparameters.csv",
  "inner_grid_summary.csv",
  "outer_training_imputation_values.csv",
  "feature_importance.csv",
  "task_metadata.rds"
)

task_directories <- file.path(
  task_root,
  sprintf(
    "task_%03d__%s",
    manifest$task_id,
    manifest$task_label
  )
)

audit_records <- lapply(
  seq_len(nrow(manifest)),
  function(i) {
    task_dir <- task_directories[[i]]

    expected_paths <- file.path(
      task_dir,
      required_task_files
    )

    summary_file <- file.path(
      task_dir,
      "run_summary.txt"
    )

    summary_lines <- if (
      file.exists(summary_file)
    ) {
      readLines(
        summary_file,
        warn = FALSE
      )
    } else {
      character()
    }

    tibble::tibble(
      task_id =
        manifest$task_id[[i]],

      task_label =
        manifest$task_label[[i]],

      validation_scheme =
        manifest$validation_scheme[[i]],

      outer_fold =
        manifest$outer_fold[[i]],

      model_name =
        manifest$model_name[[i]],

      task_directory =
        task_dir,

      directory_exists =
        dir.exists(task_dir),

      n_required_files_present =
        sum(
          file.exists(
            expected_paths
          )
        ),

      n_required_files_expected =
        length(
          required_task_files
        ),

      all_required_files_present =
        all(
          file.exists(
            expected_paths
          )
        ),

      status_passed =
        any(
          grepl(
            "^STATUS: R52 NESTED SPATIAL RF TASK PASSED$",
            summary_lines
          )
        )
    )
  }
)

completion_audit <- dplyr::bind_rows(
  audit_records
)

readr::write_csv(
  completion_audit,
  file.path(
    out_dir,
    "task_completion_audit.csv"
  )
)

incomplete_tasks <- completion_audit |>
  dplyr::filter(
    !directory_exists |
      !all_required_files_present |
      !status_passed
  )

if (nrow(incomplete_tasks) > 0L) {
  readr::write_csv(
    incomplete_tasks,
    file.path(
      out_dir,
      "incomplete_tasks.csv"
    )
  )

  stop(
    "R52 aggregation stopped: ",
    nrow(incomplete_tasks),
    " of 45 tasks are incomplete. ",
    "Inspect aggregate/incomplete_tasks.csv."
  )
}

read_task_outputs <- function(
  task_id,
  task_label
) {
  task_dir <- file.path(
    task_root,
    sprintf(
      "task_%03d__%s",
      task_id,
      task_label
    )
  )

  list(
    metrics =
      readr::read_csv(
        file.path(
          task_dir,
          "outer_metrics.csv"
        ),
        show_col_types = FALSE
      ),

    predictions =
      readr::read_csv(
        file.path(
          task_dir,
          "outer_predictions.csv"
        ),
        show_col_types = FALSE
      ),

    regime_metrics =
      readr::read_csv(
        file.path(
          task_dir,
          "outer_regime_metrics.csv"
        ),
        show_col_types = FALSE
      ),

    selected =
      readr::read_csv(
        file.path(
          task_dir,
          "selected_hyperparameters.csv"
        ),
        show_col_types = FALSE
      ),

    inner_grid =
      readr::read_csv(
        file.path(
          task_dir,
          "inner_grid_summary.csv"
        ),
        show_col_types = FALSE
      ),

    imputation =
      readr::read_csv(
        file.path(
          task_dir,
          "outer_training_imputation_values.csv"
        ),
        show_col_types = FALSE
      ),

    importance =
      readr::read_csv(
        file.path(
          task_dir,
          "feature_importance.csv"
        ),
        show_col_types = FALSE
      )
  )
}

task_outputs <- lapply(
  seq_len(nrow(manifest)),
  function(i) {
    read_task_outputs(
      task_id =
        manifest$task_id[[i]],

      task_label =
        manifest$task_label[[i]]
    )
  }
)

all_outer_metrics <- dplyr::bind_rows(
  lapply(
    task_outputs,
    function(x) {
      x$metrics
    }
  )
)

all_outer_predictions <- dplyr::bind_rows(
  lapply(
    task_outputs,
    function(x) {
      x$predictions
    }
  )
)

all_regime_metrics <- dplyr::bind_rows(
  lapply(
    task_outputs,
    function(x) {
      x$regime_metrics
    }
  )
)

all_selected_hyperparameters <- dplyr::bind_rows(
  lapply(
    task_outputs,
    function(x) {
      x$selected
    }
  )
)

all_inner_grid_summaries <- dplyr::bind_rows(
  lapply(
    task_outputs,
    function(x) {
      x$inner_grid
    }
  )
)

all_imputation_values <- dplyr::bind_rows(
  lapply(
    task_outputs,
    function(x) {
      x$imputation
    }
  )
)

all_existing_importance <- dplyr::bind_rows(
  lapply(
    task_outputs,
    function(x) {
      x$importance
    }
  )
)

# ==============================================================================
# Structural output invariants
# ==============================================================================

if (nrow(all_outer_metrics) != 45L * 4L) {
  stop(
    "Expected 180 outer metric rows; found ",
    nrow(all_outer_metrics)
  )
}

if (nrow(all_selected_hyperparameters) != 45L) {
  stop(
    "Expected 45 selected-hyperparameter rows; found ",
    nrow(all_selected_hyperparameters)
  )
}

if (
  !setequal(
    unique(
      all_selected_hyperparameters$task_id
    ),
    1:45
  )
) {
  stop(
    "Selected hyperparameters do not cover task IDs 1:45."
  )
}

expected_prediction_rows <-
  4485L *
  3L *
  3L

if (
  nrow(all_outer_predictions) !=
    expected_prediction_rows
) {
  stop(
    "Expected ",
    expected_prediction_rows,
    " outer predictions; found ",
    nrow(all_outer_predictions)
  )
}

if (
  anyNA(
    all_outer_predictions$predicted_sr
  ) ||
  any(
    !is.finite(
      all_outer_predictions$predicted_sr
    )
  )
) {
  stop(
    "Outer predictions contain missing or non-finite values."
  )
}

prediction_coverage <- all_outer_predictions |>
  dplyr::count(
    validation_scheme,
    model_name,
    row_id,
    name = "n_predictions"
  )

invalid_prediction_coverage <- prediction_coverage |>
  dplyr::filter(
    n_predictions != 1L
  )

if (
  nrow(
    invalid_prediction_coverage
  ) > 0L
) {
  readr::write_csv(
    invalid_prediction_coverage,
    file.path(
      out_dir,
      "invalid_prediction_coverage.csv"
    )
  )

  stop(
    "At least one row was predicted more or less than once ",
    "within a validation-scheme/model combination."
  )
}

coverage_summary <- prediction_coverage |>
  dplyr::count(
    validation_scheme,
    model_name,
    name = "n_rows"
  )

if (
  nrow(coverage_summary) != 9L ||
  any(
    coverage_summary$n_rows !=
      4485L
  )
) {
  stop(
    "Each of the nine scheme/model combinations must cover 4485 rows."
  )
}

task_prediction_counts <- all_outer_predictions |>
  dplyr::count(
    task_id,
    name = "n_predictions"
  )

task_metric_counts <- all_outer_metrics |>
  dplyr::filter(
    evaluation_subset ==
      "all"
  ) |>
  dplyr::select(
    task_id,
    expected_n =
      n
  )

task_prediction_audit <- task_prediction_counts |>
  dplyr::left_join(
    task_metric_counts,
    by = "task_id"
  ) |>
  dplyr::mutate(
    counts_match =
      n_predictions ==
      expected_n
  )

readr::write_csv(
  task_prediction_audit,
  file.path(
    out_dir,
    "task_prediction_count_audit.csv"
  )
)

if (
  any(
    !task_prediction_audit$
      counts_match
  )
) {
  stop(
    "Prediction-row counts disagree with outer metric sample sizes."
  )
}

# ==============================================================================
# Metric functions for pooled out-of-fold predictions
# ==============================================================================

calculate_metrics <- function(
  observed,
  predicted
) {
  observed <- as.numeric(
    observed
  )

  predicted <- as.numeric(
    predicted
  )

  valid <-
    is.finite(observed) &
    is.finite(predicted)

  observed <- observed[
    valid
  ]

  predicted <- predicted[
    valid
  ]

  n <- length(observed)

  if (n == 0L) {
    return(
      tibble::tibble(
        n = 0L,
        rmse = NA_real_,
        mae = NA_real_,
        r2 = NA_real_,
        bias = NA_real_,
        calibration_intercept = NA_real_,
        calibration_slope = NA_real_,
        observed_mean = NA_real_,
        predicted_mean = NA_real_,
        predicted_min = NA_real_,
        predicted_max = NA_real_,
        predicted_range = NA_real_,
        underprediction_fraction = NA_real_
      )
    )
  }

  residual <-
    predicted -
    observed

  denominator <- sum(
    (
      observed -
        mean(observed)
    )^2
  )

  r2 <- if (
    denominator <= 0
  ) {
    NA_real_
  } else {
    1 -
      sum(
        residual^2
      ) /
      denominator
  }

  calibration <- if (
    n >= 3L &&
    dplyr::n_distinct(
      predicted
    ) >= 2L
  ) {
    stats::coef(
      stats::lm(
        observed ~
          predicted
      )
    )
  } else {
    c(
      `(Intercept)` =
        NA_real_,

      predicted =
        NA_real_
    )
  }

  tibble::tibble(
    n = n,

    rmse =
      sqrt(
        mean(
          residual^2
        )
      ),

    mae =
      mean(
        abs(residual)
      ),

    r2 =
      r2,

    bias =
      mean(residual),

    calibration_intercept =
      unname(
        calibration[[1]]
      ),

    calibration_slope =
      unname(
        calibration[[2]]
      ),

    observed_mean =
      mean(observed),

    predicted_mean =
      mean(predicted),

    predicted_min =
      min(predicted),

    predicted_max =
      max(predicted),

    predicted_range =
      max(predicted) -
      min(predicted),

    underprediction_fraction =
      mean(
        predicted <
          observed
      )
  )
}

calculate_threshold_metrics <- function(
  observed,
  predicted
) {
  threshold_table <- tibble::tribble(
    ~evaluation_subset,
    ~threshold,

    "all",
    -Inf,

    "ge_072",
    0.72,

    "ge_075",
    0.75,

    "ge_080",
    0.80
  )

  dplyr::bind_rows(
    lapply(
      seq_len(
        nrow(
          threshold_table
        )
      ),
      function(i) {
        threshold <-
          threshold_table$
            threshold[[i]]

        keep <- if (
          is.infinite(
            threshold
          )
        ) {
          rep(
            TRUE,
            length(observed)
          )
        } else {
          observed >=
            threshold
        }

        dplyr::bind_cols(
          threshold_table[
            i,
            ,
            drop = FALSE
          ],

          calculate_metrics(
            observed[
              keep
            ],
            predicted[
              keep
            ]
          )
        )
      }
    )
  )
}

pooled_outer_metrics <- all_outer_predictions |>
  dplyr::group_by(
    validation_scheme,
    model_name
  ) |>
  dplyr::group_modify(
    function(
      .x,
      .y
    ) {
      calculate_threshold_metrics(
        .x$observed_sr,
        .x$predicted_sr
      )
    }
  ) |>
  dplyr::ungroup()

fold_metric_summary <- all_outer_metrics |>
  dplyr::group_by(
    validation_scheme,
    model_name,
    evaluation_subset,
    threshold
  ) |>
  dplyr::summarise(
    n_folds =
      dplyr::n(),

    mean_n =
      mean(n),

    mean_rmse =
      mean(
        rmse,
        na.rm = TRUE
      ),

    sd_rmse =
      stats::sd(
        rmse,
        na.rm = TRUE
      ),

    mean_mae =
      mean(
        mae,
        na.rm = TRUE
      ),

    sd_mae =
      stats::sd(
        mae,
        na.rm = TRUE
      ),

    mean_r2 =
      mean(
        r2,
        na.rm = TRUE
      ),

    sd_r2 =
      stats::sd(
        r2,
        na.rm = TRUE
      ),

    mean_bias =
      mean(
        bias,
        na.rm = TRUE
      ),

    mean_calibration_slope =
      mean(
        calibration_slope,
        na.rm = TRUE
      ),

    mean_underprediction_fraction =
      mean(
        underprediction_fraction,
        na.rm = TRUE
      ),

    .groups = "drop"
  )

# ==============================================================================
# Paired model comparison using identical outer folds
# ==============================================================================

baseline_fold_metrics <- all_outer_metrics |>
  dplyr::filter(
    evaluation_subset ==
      "all",

    model_name ==
      "M0_P0_FULL"
  ) |>
  dplyr::select(
    validation_scheme,
    outer_fold,

    baseline_rmse =
      rmse,

    baseline_mae =
      mae,

    baseline_r2 =
      r2,

    baseline_bias =
      bias
  )

paired_model_deltas <- all_outer_metrics |>
  dplyr::filter(
    evaluation_subset ==
      "all"
  ) |>
  dplyr::left_join(
    baseline_fold_metrics,
    by = c(
      "validation_scheme",
      "outer_fold"
    )
  ) |>
  dplyr::mutate(
    delta_rmse_vs_m0 =
      rmse -
      baseline_rmse,

    delta_mae_vs_m0 =
      mae -
      baseline_mae,

    delta_r2_vs_m0 =
      r2 -
      baseline_r2,

    delta_bias_vs_m0 =
      bias -
      baseline_bias,

    better_rmse_than_m0 =
      delta_rmse_vs_m0 <
      0
  )

paired_delta_summary <- paired_model_deltas |>
  dplyr::group_by(
    validation_scheme,
    model_name
  ) |>
  dplyr::summarise(
    n_folds =
      dplyr::n(),

    mean_delta_rmse =
      mean(
        delta_rmse_vs_m0
      ),

    median_delta_rmse =
      stats::median(
        delta_rmse_vs_m0
      ),

    folds_better_rmse =
      sum(
        better_rmse_than_m0
      ),

    mean_delta_mae =
      mean(
        delta_mae_vs_m0
      ),

    mean_delta_r2 =
      mean(
        delta_r2_vs_m0
      ),

    mean_delta_bias =
      mean(
        delta_bias_vs_m0
      ),

    .groups = "drop"
  )

# ==============================================================================
# Pooled geological-regime performance
# ==============================================================================

pooled_regime_metrics <- all_outer_predictions |>
  dplyr::group_by(
    validation_scheme,
    model_name,
    geological_regime_primary
  ) |>
  dplyr::group_modify(
    function(
      .x,
      .y
    ) {
      calculate_metrics(
        .x$observed_sr,
        .x$predicted_sr
      )
    }
  ) |>
  dplyr::ungroup()

# ==============================================================================
# Hyperparameter and imputation summaries
# ==============================================================================

hyperparameter_frequency <- all_selected_hyperparameters |>
  dplyr::count(
    validation_scheme,
    model_name,
    mtry,
    min_node_size,
    sample_fraction,
    name = "n_outer_folds"
  ) |>
  dplyr::arrange(
    validation_scheme,
    model_name,
    dplyr::desc(
      n_outer_folds
    )
  )

imputation_summary <- all_imputation_values |>
  dplyr::group_by(
    validation_scheme,
    model_name,
    feature
  ) |>
  dplyr::summarise(
    n_outer_folds =
      dplyr::n_distinct(
        outer_fold
      ),

    folds_with_missing =
      sum(
        n_missing_outer_train >
          0
      ),

    maximum_missing_outer_train =
      max(
        n_missing_outer_train
      ),

    minimum_training_median =
      min(
        training_median
      ),

    maximum_training_median =
      max(
        training_median
      ),

    .groups = "drop"
  )

# ==============================================================================
# Audit existing ranger OOB importance
# ==============================================================================

feature_importance_audit <- all_existing_importance |>
  dplyr::group_by(
    task_id,
    task_label,
    validation_scheme,
    outer_fold,
    model_name
  ) |>
  dplyr::summarise(
    n_features =
      dplyr::n(),

    n_finite_importance =
      sum(
        is.finite(
          permutation_importance
        )
      ),

    n_missing_importance =
      sum(
        is.na(
          permutation_importance
        )
      ),

    .groups = "drop"
  ) |>
  dplyr::left_join(
    all_selected_hyperparameters |>
      dplyr::select(
        task_id,
        selected_sample_fraction =
          sample_fraction
      ),
    by = "task_id"
  ) |>
  dplyr::mutate(
    suitable_for_cross_fold_interpretation =
      FALSE,

    exclusion_reason =
      paste(
        "Existing ranger permutation importance uses OOB observations;",
        "it is undefined when replace=FALSE and sample_fraction=1",
        "and is not comparable across varying sample fractions.",
        "Use held-out outer-fold permutation importance instead."
      )
  )

# ==============================================================================
# Save aggregated outputs
# ==============================================================================

readr::write_csv(
  all_outer_metrics,
  file.path(
    out_dir,
    "all_outer_fold_metrics.csv"
  )
)

readr::write_csv(
  all_outer_predictions,
  file.path(
    out_dir,
    "all_outer_predictions.csv"
  )
)

readr::write_csv(
  all_regime_metrics,
  file.path(
    out_dir,
    "all_outer_fold_regime_metrics.csv"
  )
)

readr::write_csv(
  all_selected_hyperparameters,
  file.path(
    out_dir,
    "all_selected_hyperparameters.csv"
  )
)

readr::write_csv(
  all_inner_grid_summaries,
  file.path(
    out_dir,
    "all_inner_grid_summaries.csv"
  )
)

readr::write_csv(
  pooled_outer_metrics,
  file.path(
    out_dir,
    "pooled_outer_metrics.csv"
  )
)

readr::write_csv(
  fold_metric_summary,
  file.path(
    out_dir,
    "fold_metric_summary.csv"
  )
)

readr::write_csv(
  paired_model_deltas,
  file.path(
    out_dir,
    "paired_model_deltas.csv"
  )
)

readr::write_csv(
  paired_delta_summary,
  file.path(
    out_dir,
    "paired_delta_summary.csv"
  )
)

readr::write_csv(
  pooled_regime_metrics,
  file.path(
    out_dir,
    "pooled_regime_metrics.csv"
  )
)

readr::write_csv(
  hyperparameter_frequency,
  file.path(
    out_dir,
    "hyperparameter_frequency.csv"
  )
)

readr::write_csv(
  imputation_summary,
  file.path(
    out_dir,
    "imputation_summary.csv"
  )
)

readr::write_csv(
  feature_importance_audit,
  file.path(
    out_dir,
    "feature_importance_audit.csv"
  )
)

aggregate_results <- list(
  completion_audit =
    completion_audit,

  outer_fold_metrics =
    all_outer_metrics,

  outer_predictions =
    all_outer_predictions,

  pooled_outer_metrics =
    pooled_outer_metrics,

  fold_metric_summary =
    fold_metric_summary,

  paired_model_deltas =
    paired_model_deltas,

  paired_delta_summary =
    paired_delta_summary,

  pooled_regime_metrics =
    pooled_regime_metrics,

  selected_hyperparameters =
    all_selected_hyperparameters,

  hyperparameter_frequency =
    hyperparameter_frequency,

  imputation_summary =
    imputation_summary,

  feature_importance_audit =
    feature_importance_audit
)

saveRDS(
  aggregate_results,
  file.path(
    out_dir,
    "aggregate_results.rds"
  ),
  version = 3
)

summary_lines <- c(
  "R52 NESTED SPATIAL RF AGGREGATION",
  "=================================",
  "",
  paste0(
    "Completed tasks: ",
    sum(
      completion_audit$status_passed
    ),
    " / 45"
  ),
  paste0(
    "Outer prediction rows: ",
    nrow(
      all_outer_predictions
    )
  ),
  paste0(
    "Scheme/model combinations with complete coverage: ",
    nrow(
      coverage_summary
    ),
    " / 9"
  ),
  "",
  "MODEL COMPARISON:",
  paste(
    "M0, CORE and FULL were evaluated on identical",
    "outer folds at 500, 1000 and 1500 km."
  ),
  paste(
    "Paired RMSE deltas are negative when a mechanistic",
    "model improves on M0."
  ),
  "",
  "FEATURE IMPORTANCE:",
  paste(
    "Original ranger OOB permutation importance is excluded",
    "from interpretation."
  ),
  paste(
    "Held-out outer-fold permutation importance",
    "will be calculated separately."
  ),
  "",
  "STATUS: ALL R52 AGGREGATION INVARIANTS PASSED"
)

writeLines(
  summary_lines,
  file.path(
    out_dir,
    "run_summary.txt"
  )
)

cat(
  paste(
    summary_lines,
    collapse = "\n"
  ),
  "\n"
)
