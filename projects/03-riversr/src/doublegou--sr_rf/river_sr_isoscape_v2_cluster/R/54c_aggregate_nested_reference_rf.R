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

r54_dir <- file.path(
  root,
  "outputs",
  "r54_nested_reference_rf"
)

task_root <- file.path(
  r54_dir,
  "tasks"
)

out_dir <- file.path(
  r54_dir,
  "aggregate"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

manifest_file <- file.path(
  r54_dir,
  "task_manifest.csv"
)

if (!file.exists(manifest_file)) {
  stop(
    "Missing R54 task manifest: ",
    manifest_file
  )
}

manifest <- readr::read_csv(
  manifest_file,
  show_col_types = FALSE
)

if (
  nrow(manifest) != 15L ||
  !identical(
    as.integer(
      manifest$task_id
    ),
    1:15
  )
) {
  stop(
    "R54 task manifest must contain task IDs 1:15."
  )
}

required_task_files <- c(
  "run_summary.txt",
  "inner_fold_metrics.csv",
  "inner_grid_summary.csv",
  "selected_hyperparameters.csv",
  "outer_predictions.csv",
  "outer_metrics.csv",
  "outer_regime_metrics.csv",
  "outer_reference_group_metrics.csv",
  "outer_training_imputation_values.csv",
  "task_metadata.rds"
)

task_directory <- function(
  task_id,
  task_label
) {
  file.path(
    task_root,
    sprintf(
      "task_%03d__%s",
      task_id,
      task_label
    )
  )
}

# ==============================================================================
# Completion audit
# ==============================================================================

completion_audit <- lapply(
  seq_len(
    nrow(manifest)
  ),
  function(i) {
    task_id <-
      manifest$task_id[[i]]

    task_label <-
      manifest$task_label[[i]]

    task_dir <- task_directory(
      task_id,
      task_label
    )

    required_paths <- file.path(
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
        task_id,

      task_label =
        task_label,

      outer_fold =
        manifest$outer_fold[[i]],

      model_name =
        manifest$model_name[[i]],

      task_directory =
        task_dir,

      directory_exists =
        dir.exists(task_dir),

      files_present =
        sum(
          file.exists(
            required_paths
          )
        ),

      files_expected =
        length(
          required_task_files
        ),

      all_files_present =
        all(
          file.exists(
            required_paths
          )
        ),

      status_passed =
        any(
          summary_lines ==
            paste(
              "STATUS: R54 NESTED",
              "REFERENCE-GROUP RF TASK PASSED"
            )
        )
    )
  }
) |>
  dplyr::bind_rows()

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
      !all_files_present |
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
    "R54 aggregation stopped because ",
    nrow(incomplete_tasks),
    " tasks are incomplete."
  )
}

# ==============================================================================
# Read task outputs
# ==============================================================================

read_task_csv <- function(
  task_id,
  task_label,
  filename
) {
  readr::read_csv(
    file.path(
      task_directory(
        task_id,
        task_label
      ),
      filename
    ),
    show_col_types = FALSE
  )
}

metric_records <- list()
prediction_records <- list()
regime_records <- list()
reference_records <- list()
parameter_records <- list()
inner_grid_records <- list()
imputation_records <- list()

for (i in seq_len(nrow(manifest))) {
  task_id <-
    manifest$task_id[[i]]

  task_label <-
    manifest$task_label[[i]]

  metric_records[[i]] <-
    read_task_csv(
      task_id,
      task_label,
      "outer_metrics.csv"
    )

  prediction_records[[i]] <-
    read_task_csv(
      task_id,
      task_label,
      "outer_predictions.csv"
    )

  regime_records[[i]] <-
    read_task_csv(
      task_id,
      task_label,
      "outer_regime_metrics.csv"
    )

  reference_records[[i]] <-
    read_task_csv(
      task_id,
      task_label,
      "outer_reference_group_metrics.csv"
    )

  parameter_records[[i]] <-
    read_task_csv(
      task_id,
      task_label,
      "selected_hyperparameters.csv"
    )

  inner_grid_records[[i]] <-
    read_task_csv(
      task_id,
      task_label,
      "inner_grid_summary.csv"
    ) |>
    dplyr::mutate(
      task_id =
        task_id,

      task_label =
        task_label,

      outer_fold =
        manifest$outer_fold[[i]],

      model_name =
        manifest$model_name[[i]]
    ) |>
    dplyr::relocate(
      task_id,
      task_label,
      outer_fold,
      model_name
    )

  imputation_records[[i]] <-
    read_task_csv(
      task_id,
      task_label,
      "outer_training_imputation_values.csv"
    )
}

all_outer_metrics <- dplyr::bind_rows(
  metric_records
)

all_outer_predictions <- dplyr::bind_rows(
  prediction_records
)

all_regime_metrics <- dplyr::bind_rows(
  regime_records
)

all_task_reference_metrics <- dplyr::bind_rows(
  reference_records
)

all_selected_parameters <- dplyr::bind_rows(
  parameter_records
)

all_inner_grid_summaries <- dplyr::bind_rows(
  inner_grid_records
)

all_imputation_values <- dplyr::bind_rows(
  imputation_records
)

# ==============================================================================
# Structural invariants
# ==============================================================================

if (nrow(all_outer_metrics) != 60L) {
  stop(
    "Expected 60 outer metric rows; found ",
    nrow(all_outer_metrics)
  )
}

if (
  nrow(
    all_selected_parameters
  ) !=
    15L
) {
  stop(
    "Expected 15 selected-parameter rows; found ",
    nrow(
      all_selected_parameters
    )
  )
}

expected_prediction_rows <-
  4485L *
  3L

if (
  nrow(
    all_outer_predictions
  ) !=
    expected_prediction_rows
) {
  stop(
    "Expected ",
    expected_prediction_rows,
    " prediction rows; found ",
    nrow(
      all_outer_predictions
    )
  )
}

if (
  anyNA(
    all_outer_predictions$
      predicted_sr
  ) ||
  any(
    !is.finite(
      all_outer_predictions$
        predicted_sr
    )
  )
) {
  stop(
    "Reference-CV predictions contain missing or non-finite values."
  )
}

if (
  anyNA(
    all_outer_predictions$
      reference_group
  )
) {
  stop(
    "Reference groups are missing from predictions."
  )
}

prediction_coverage <- all_outer_predictions |>
  dplyr::count(
    model_name,
    row_id,
    name = "n_predictions"
  )

invalid_prediction_coverage <-
  prediction_coverage |>
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
    "At least one row was predicted more or less than once per model."
  )
}

model_coverage <- prediction_coverage |>
  dplyr::count(
    model_name,
    name = "n_rows"
  )

if (
  nrow(model_coverage) != 3L ||
  any(
    model_coverage$n_rows !=
      4485L
  )
) {
  stop(
    "Each model must contain exactly 4485 out-of-fold predictions."
  )
}

fold_presence <- all_outer_predictions |>
  dplyr::distinct(
    model_name,
    outer_fold
  ) |>
  dplyr::count(
    model_name,
    name = "n_outer_folds"
  )

if (
  nrow(fold_presence) != 3L ||
  any(
    fold_presence$n_outer_folds !=
      5L
  )
) {
  stop(
    "Each model must contain five outer reference folds."
  )
}

reference_fold_audit <- all_outer_predictions |>
  dplyr::distinct(
    reference_group,
    outer_fold
  ) |>
  dplyr::count(
    reference_group,
    name = "n_outer_folds"
  ) |>
  dplyr::filter(
    n_outer_folds != 1L
  )

if (nrow(reference_fold_audit) > 0L) {
  stop(
    "At least one reference group crosses outer folds."
  )
}

# ==============================================================================
# Metric helpers
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
        observed_sd = NA_real_,
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
    n =
      n,

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

    observed_sd =
      if (
        n >= 2L
      ) {
        stats::sd(observed)
      } else {
        NA_real_
      },

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

weighted_mean_safe <- function(
  values,
  weights
) {
  valid <-
    is.finite(values) &
    is.finite(weights) &
    weights >
      0

  if (!any(valid)) {
    return(
      NA_real_
    )
  }

  stats::weighted.mean(
    values[
      valid
    ],
    weights[
      valid
    ]
  )
}

# ==============================================================================
# Pooled out-of-fold model performance
# ==============================================================================

pooled_outer_metrics <- all_outer_predictions |>
  dplyr::group_by(
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
  dplyr::ungroup() |>
  dplyr::mutate(
    validation_scheme =
      "reference_grouped_5fold"
  ) |>
  dplyr::relocate(
    validation_scheme,
    model_name
  )

fold_metric_summary <- all_outer_metrics |>
  dplyr::group_by(
    model_name,
    evaluation_subset,
    threshold
  ) |>
  dplyr::summarise(
    n_outer_folds =
      dplyr::n_distinct(
        outer_fold
      ),

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
# Paired fold comparisons against M0
# ==============================================================================

baseline_fold_metrics <- all_outer_metrics |>
  dplyr::filter(
    model_name ==
      "M0_P0_FULL"
  ) |>
  dplyr::select(
    outer_fold,
    evaluation_subset,

    baseline_n =
      n,

    baseline_rmse =
      rmse,

    baseline_mae =
      mae,

    baseline_r2 =
      r2,

    baseline_bias =
      bias,

    baseline_underprediction =
      underprediction_fraction
  )

paired_fold_deltas <- all_outer_metrics |>
  dplyr::left_join(
    baseline_fold_metrics,
    by = c(
      "outer_fold",
      "evaluation_subset"
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

    delta_underprediction_vs_m0 =
      underprediction_fraction -
      baseline_underprediction,

    better_rmse_than_m0 =
      delta_rmse_vs_m0 <
        0
  )

paired_fold_summary <- paired_fold_deltas |>
  dplyr::group_by(
    model_name,
    evaluation_subset
  ) |>
  dplyr::summarise(
    n_outer_folds =
      dplyr::n_distinct(
        outer_fold
      ),

    mean_delta_rmse =
      mean(
        delta_rmse_vs_m0,
        na.rm = TRUE
      ),

    median_delta_rmse =
      stats::median(
        delta_rmse_vs_m0,
        na.rm = TRUE
      ),

    folds_better_rmse =
      sum(
        better_rmse_than_m0,
        na.rm = TRUE
      ),

    mean_delta_mae =
      mean(
        delta_mae_vs_m0,
        na.rm = TRUE
      ),

    mean_delta_r2 =
      mean(
        delta_r2_vs_m0,
        na.rm = TRUE
      ),

    mean_delta_bias =
      mean(
        delta_bias_vs_m0,
        na.rm = TRUE
      ),

    mean_delta_underprediction =
      mean(
        delta_underprediction_vs_m0,
        na.rm = TRUE
      ),

    .groups = "drop"
  )

# ==============================================================================
# Per-reference performance
# ==============================================================================

reference_sizes <- all_outer_predictions |>
  dplyr::distinct(
    row_id,
    reference_group
  ) |>
  dplyr::count(
    reference_group,
    name = "reference_size"
  ) |>
  dplyr::mutate(
    reference_size_class =
      dplyr::case_when(
        reference_size == 1L ~
          "1",

        reference_size <= 4L ~
          "2-4",

        reference_size <= 9L ~
          "5-9",

        reference_size <= 24L ~
          "10-24",

        reference_size <= 49L ~
          "25-49",

        TRUE ~
          "50+"
      ),

    reference_size_class =
      factor(
        reference_size_class,
        levels = c(
          "1",
          "2-4",
          "5-9",
          "10-24",
          "25-49",
          "50+"
        ),
        ordered = TRUE
      )
  )

predictions_with_reference_size <-
  all_outer_predictions |>
  dplyr::left_join(
    reference_sizes,
    by = "reference_group"
  )

pooled_reference_group_metrics <-
  predictions_with_reference_size |>
  dplyr::group_by(
    model_name,
    reference_group,
    reference_size,
    reference_size_class
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

if (
  dplyr::n_distinct(
    pooled_reference_group_metrics$
      reference_group
  ) !=
    227L
) {
  stop(
    "Expected 227 reference groups in pooled group metrics."
  )
}

reference_macro_summary <-
  pooled_reference_group_metrics |>
  dplyr::group_by(
    model_name
  ) |>
  dplyr::summarise(
    n_reference_groups =
      dplyr::n_distinct(
        reference_group
      ),

    total_rows =
      sum(
        reference_size
      ),

    mean_reference_rmse =
      mean(
        rmse
      ),

    median_reference_rmse =
      stats::median(
        rmse
      ),

    weighted_mean_reference_rmse =
      weighted_mean_safe(
        rmse,
        reference_size
      ),

    mean_reference_mae =
      mean(
        mae
      ),

    median_reference_mae =
      stats::median(
        mae
      ),

    median_reference_bias =
      stats::median(
        bias
      ),

    mean_absolute_reference_bias =
      mean(
        abs(bias)
      ),

    references_with_positive_r2 =
      sum(
        is.finite(r2) &
          r2 >
            0
      ),

    references_with_n_ge_5 =
      sum(
        reference_size >=
          5L
      ),

    median_r2_references_n_ge_5 =
      stats::median(
        r2[
          reference_size >=
            5L &
          is.finite(r2)
        ],
        na.rm = TRUE
      ),

    .groups = "drop"
  )

reference_size_class_metrics <-
  predictions_with_reference_size |>
  dplyr::group_by(
    model_name,
    reference_size_class
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
  dplyr::ungroup() |>
  dplyr::left_join(
    reference_sizes |>
      dplyr::count(
        reference_size_class,
        name =
          "n_reference_groups"
      ),
    by =
      "reference_size_class"
  )

# ==============================================================================
# Paired per-reference comparisons
# ==============================================================================

paired_reference_metrics <-
  pooled_reference_group_metrics |>
  dplyr::select(
    model_name,
    reference_group,
    reference_size,
    reference_size_class,
    rmse,
    mae,
    bias,
    underprediction_fraction
  ) |>
  tidyr::pivot_wider(
    names_from =
      model_name,

    values_from =
      c(
        rmse,
        mae,
        bias,
        underprediction_fraction
      )
  ) |>
  dplyr::mutate(
    delta_rmse_core_vs_m0 =
      rmse_M_CORE_MECHANISTIC -
      rmse_M0_P0_FULL,

    delta_rmse_full_vs_m0 =
      rmse_M_FULL_MECHANISTIC -
      rmse_M0_P0_FULL,

    delta_mae_core_vs_m0 =
      mae_M_CORE_MECHANISTIC -
      mae_M0_P0_FULL,

    delta_mae_full_vs_m0 =
      mae_M_FULL_MECHANISTIC -
      mae_M0_P0_FULL,

    core_better_rmse =
      delta_rmse_core_vs_m0 <
        0,

    full_better_rmse =
      delta_rmse_full_vs_m0 <
        0
  )

paired_reference_summary <-
  dplyr::bind_rows(
    paired_reference_metrics |>
      dplyr::transmute(
        model_name =
          "M_CORE_MECHANISTIC",

        reference_group,
        reference_size,

        delta_rmse =
          delta_rmse_core_vs_m0,

        delta_mae =
          delta_mae_core_vs_m0,

        better_rmse =
          core_better_rmse
      ),

    paired_reference_metrics |>
      dplyr::transmute(
        model_name =
          "M_FULL_MECHANISTIC",

        reference_group,
        reference_size,

        delta_rmse =
          delta_rmse_full_vs_m0,

        delta_mae =
          delta_mae_full_vs_m0,

        better_rmse =
          full_better_rmse
      )
  ) |>
  dplyr::group_by(
    model_name
  ) |>
  dplyr::summarise(
    n_reference_groups =
      dplyr::n(),

    references_better_rmse =
      sum(
        better_rmse
      ),

    proportion_references_better_rmse =
      mean(
        better_rmse
      ),

    mean_delta_rmse =
      mean(
        delta_rmse
      ),

    median_delta_rmse =
      stats::median(
        delta_rmse
      ),

    weighted_mean_delta_rmse =
      weighted_mean_safe(
        delta_rmse,
        reference_size
      ),

    mean_delta_mae =
      mean(
        delta_mae
      ),

    references_n_ge_5_better_rmse =
      sum(
        better_rmse &
          reference_size >=
            5L
      ),

    n_references_n_ge_5 =
      sum(
        reference_size >=
          5L
      ),

    .groups = "drop"
  )

# ==============================================================================
# Geological-regime performance
# ==============================================================================

pooled_regime_metrics <- all_outer_predictions |>
  dplyr::group_by(
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

hyperparameter_frequency <-
  all_selected_parameters |>
  dplyr::count(
    model_name,
    mtry,
    min_node_size,
    sample_fraction,
    name = "n_outer_folds"
  ) |>
  dplyr::arrange(
    model_name,
    dplyr::desc(
      n_outer_folds
    ),
    mtry,
    min_node_size,
    sample_fraction
  )

imputation_summary <- all_imputation_values |>
  dplyr::group_by(
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
# Optional comparison with spatial validation
# ==============================================================================

spatial_metrics_file <- file.path(
  root,
  "outputs",
  "r52_nested_spatial_rf",
  "aggregate",
  "pooled_outer_metrics.csv"
)

validation_family_comparison <- if (
  file.exists(
    spatial_metrics_file
  )
) {
  spatial_metrics <-
    readr::read_csv(
      spatial_metrics_file,
      show_col_types = FALSE
    ) |>
    dplyr::mutate(
      validation_family =
        "spatial_blocked"
    )

  reference_metrics <-
    pooled_outer_metrics |>
    dplyr::mutate(
      validation_family =
        "reference_grouped"
    )

  dplyr::bind_rows(
    spatial_metrics,
    reference_metrics
  ) |>
    dplyr::select(
      validation_family,
      validation_scheme,
      model_name,
      evaluation_subset,
      threshold,
      n,
      rmse,
      mae,
      r2,
      bias,
      calibration_intercept,
      calibration_slope,
      observed_mean,
      predicted_mean,
      predicted_min,
      predicted_max,
      predicted_range,
      underprediction_fraction
    )
} else {
  tibble::tibble()
}

# ==============================================================================
# Save outputs
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
    "all_task_regime_metrics.csv"
  )
)

readr::write_csv(
  all_task_reference_metrics,
  file.path(
    out_dir,
    "all_task_reference_group_metrics.csv"
  )
)

readr::write_csv(
  all_selected_parameters,
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
  paired_fold_deltas,
  file.path(
    out_dir,
    "paired_fold_deltas.csv"
  )
)

readr::write_csv(
  paired_fold_summary,
  file.path(
    out_dir,
    "paired_fold_summary.csv"
  )
)

readr::write_csv(
  pooled_reference_group_metrics,
  file.path(
    out_dir,
    "pooled_reference_group_metrics.csv"
  )
)

readr::write_csv(
  reference_macro_summary,
  file.path(
    out_dir,
    "reference_macro_summary.csv"
  )
)

readr::write_csv(
  reference_size_class_metrics,
  file.path(
    out_dir,
    "reference_size_class_metrics.csv"
  )
)

readr::write_csv(
  paired_reference_metrics,
  file.path(
    out_dir,
    "paired_reference_metrics.csv"
  )
)

readr::write_csv(
  paired_reference_summary,
  file.path(
    out_dir,
    "paired_reference_summary.csv"
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

if (
  nrow(
    validation_family_comparison
  ) > 0L
) {
  readr::write_csv(
    validation_family_comparison,
    file.path(
      out_dir,
      "spatial_vs_reference_validation.csv"
    )
  )
}

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

  paired_fold_deltas =
    paired_fold_deltas,

  paired_fold_summary =
    paired_fold_summary,

  pooled_reference_group_metrics =
    pooled_reference_group_metrics,

  reference_macro_summary =
    reference_macro_summary,

  reference_size_class_metrics =
    reference_size_class_metrics,

  paired_reference_metrics =
    paired_reference_metrics,

  paired_reference_summary =
    paired_reference_summary,

  pooled_regime_metrics =
    pooled_regime_metrics,

  selected_hyperparameters =
    all_selected_parameters,

  hyperparameter_frequency =
    hyperparameter_frequency,

  imputation_summary =
    imputation_summary,

  validation_family_comparison =
    validation_family_comparison
)

saveRDS(
  aggregate_results,
  file.path(
    out_dir,
    "aggregate_results.rds"
  ),
  version = 3
)

overall_results <- pooled_outer_metrics |>
  dplyr::filter(
    evaluation_subset ==
      "all"
  ) |>
  dplyr::arrange(
    rmse,
    mae,
    dplyr::desc(r2)
  )

best_model <-
  overall_results$
    model_name[[1]]

best_rmse <-
  overall_results$
    rmse[[1]]

mechanistic_delta_lines <-
  paired_fold_summary |>
  dplyr::filter(
    evaluation_subset ==
      "all",
    model_name !=
      "M0_P0_FULL"
  ) |>
  dplyr::mutate(
    line =
      paste0(
        model_name,
        ": mean delta RMSE = ",
        mean_delta_rmse,
        "; folds better than M0 = ",
        folds_better_rmse,
        "/",
        n_outer_folds
      )
  ) |>
  dplyr::pull(
    line
  )

reference_delta_lines <-
  paired_reference_summary |>
  dplyr::mutate(
    line =
      paste0(
        model_name,
        ": references better than M0 = ",
        references_better_rmse,
        "/",
        n_reference_groups,
        "; median delta RMSE = ",
        median_delta_rmse
      )
  ) |>
  dplyr::pull(
    line
  )

summary_lines <- c(
  "R54 NESTED REFERENCE-GROUP RF AGGREGATION",
  "==========================================",
  "",
  paste0(
    "Completed tasks: ",
    sum(
      completion_audit$
        status_passed
    ),
    " / 15"
  ),
  paste0(
    "Prediction rows: ",
    nrow(
      all_outer_predictions
    )
  ),
  paste0(
    "Models with complete 4485-row coverage: ",
    nrow(
      model_coverage
    ),
    " / 3"
  ),
  paste0(
    "Reference groups represented: ",
    dplyr::n_distinct(
      all_outer_predictions$
        reference_group
    )
  ),
  "",
  paste0(
    "Best pooled overall model: ",
    best_model
  ),
  paste0(
    "Best pooled overall RMSE: ",
    best_rmse
  ),
  "",
  "PAIRED OUTER-FOLD COMPARISON:",
  mechanistic_delta_lines,
  "",
  "PAIRED REFERENCE-GROUP COMPARISON:",
  reference_delta_lines,
  "",
  paste(
    "Reference groups were held out intact;",
    "no source crossed training and test boundaries."
  ),
  paste(
    "Reference-group R2 values for small or low-variance",
    "sources should be interpreted cautiously."
  ),
  "",
  "STATUS: ALL R54 AGGREGATION INVARIANTS PASSED"
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
