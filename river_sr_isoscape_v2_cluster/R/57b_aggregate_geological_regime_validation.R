required_packages <- c(
  "dplyr",
  "readr",
  "tidyr",
  "tibble"
)

missing_packages <- required_packages[
  !vapply(
    required_packages,
    requireNamespace,
    logical(1),
    quietly = TRUE
  )
]

if (length(missing_packages) > 0L) {
  stop(
    "Missing packages: ",
    paste(
      missing_packages,
      collapse = ", "
    )
  )
}

root <- normalizePath(
  getwd(),
  mustWork = TRUE
)

prediction_file <- file.path(
  root,
  "outputs",
  "r52_nested_spatial_rf",
  "aggregate",
  "all_outer_predictions.csv"
)

out_dir <- file.path(
  root,
  "outputs",
  "r57b_geological_regime_validation"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

if (!file.exists(prediction_file)) {
  stop(
    "Missing R52 prediction file: ",
    prediction_file
  )
}

safe_r2 <- function(
  observed,
  predicted
) {
  if (length(observed) < 2L) {
    return(NA_real_)
  }

  denominator <- sum(
    (
      observed -
        mean(observed)
    )^2
  )

  if (
    !is.finite(denominator) ||
    denominator <= 0
  ) {
    return(NA_real_)
  }

  1 -
    sum(
      (
        observed -
          predicted
      )^2
    ) /
    denominator
}

safe_mean <- function(x) {
  x <- x[
    is.finite(x)
  ]

  if (length(x) == 0L) {
    return(NA_real_)
  }

  mean(x)
}

calculate_metrics <- function(
  observed,
  predicted
) {
  error <-
    predicted -
    observed

  tibble::tibble(
    n =
      length(observed),

    observed_mean =
      mean(observed),

    predicted_mean =
      mean(predicted),

    observed_sd =
      stats::sd(observed),

    rmse =
      sqrt(
        mean(
          error^2
        )
      ),

    mae =
      mean(
        abs(error)
      ),

    median_absolute_error =
      stats::median(
        abs(error)
      ),

    q90_absolute_error =
      as.numeric(
        stats::quantile(
          abs(error),
          probs = 0.90,
          names = FALSE,
          type = 8
        )
      ),

    bias =
      mean(error),

    r2 =
      safe_r2(
        observed,
        predicted
      ),

    underprediction_fraction =
      mean(
        predicted <
          observed
      ),

    n_ge_072 =
      sum(
        observed >=
          0.72
      ),

    n_ge_075 =
      sum(
        observed >=
          0.75
      ),

    n_ge_080 =
      sum(
        observed >=
          0.80
      )
  )
}

predictions <- readr::read_csv(
  prediction_file,
  show_col_types = FALSE
)

required_columns <- c(
  "validation_scheme",
  "outer_fold",
  "model_name",
  "row_id",
  "geological_regime_primary",
  "observed_sr",
  "predicted_sr"
)

missing_columns <- setdiff(
  required_columns,
  names(predictions)
)

if (length(missing_columns) > 0L) {
  stop(
    "R52 predictions are missing columns: ",
    paste(
      missing_columns,
      collapse = ", "
    )
  )
}

if (nrow(predictions) != 40365L) {
  stop(
    "Expected 40365 prediction rows; found ",
    nrow(predictions),
    "."
  )
}

if (
  anyNA(
    predictions$geological_regime_primary
  ) ||
  anyNA(
    predictions$observed_sr
  ) ||
  anyNA(
    predictions$predicted_sr
  )
) {
  stop(
    "Missing regime, observed Sr, or predicted Sr values."
  )
}

expected_models <- c(
  "M0_P0_FULL",
  "M_CORE_MECHANISTIC",
  "M_FULL_MECHANISTIC"
)

expected_schemes <- c(
  "spatial_500km",
  "spatial_1000km",
  "spatial_1500km"
)

if (
  !setequal(
    unique(
      predictions$model_name
    ),
    expected_models
  )
) {
  stop(
    "Unexpected model names in R52 predictions."
  )
}

if (
  !setequal(
    unique(
      predictions$validation_scheme
    ),
    expected_schemes
  )
) {
  stop(
    "Unexpected validation schemes in R52 predictions."
  )
}

regime_levels <- sort(
  unique(
    predictions$geological_regime_primary
  )
)

if (length(regime_levels) != 7L) {
  stop(
    "Expected seven geological regimes; found ",
    length(regime_levels),
    ": ",
    paste(
      regime_levels,
      collapse = ", "
    )
  )
}

coverage_audit <- predictions |>
  dplyr::count(
    validation_scheme,
    model_name,
    name = "n_predictions"
  ) |>
  tidyr::complete(
    validation_scheme =
      expected_schemes,

    model_name =
      expected_models
  ) |>
  dplyr::arrange(
    validation_scheme,
    model_name
  )

if (
  nrow(coverage_audit) != 9L ||
  anyNA(
    coverage_audit$n_predictions
  ) ||
  any(
    coverage_audit$n_predictions !=
      4485L
  )
) {
  stop(
    "Prediction coverage is incomplete."
  )
}

unique_observations <- predictions |>
  dplyr::distinct(
    row_id,
    geological_regime_primary,
    observed_sr
  )

if (nrow(unique_observations) != 4485L) {
  stop(
    "Expected 4485 unique observations; found ",
    nrow(unique_observations),
    "."
  )
}

regime_sample_distribution <- unique_observations |>
  dplyr::group_by(
    geological_regime_primary
  ) |>
  dplyr::summarise(
    n_sites =
      dplyr::n(),

    proportion =
      dplyr::n() /
      nrow(unique_observations),

    observed_mean =
      mean(observed_sr),

    observed_median =
      stats::median(observed_sr),

    observed_sd =
      stats::sd(observed_sr),

    observed_min =
      min(observed_sr),

    observed_max =
      max(observed_sr),

    n_ge_072 =
      sum(
        observed_sr >=
          0.72
      ),

    n_ge_075 =
      sum(
        observed_sr >=
          0.75
      ),

    n_ge_080 =
      sum(
        observed_sr >=
          0.80
      ),

    .groups = "drop"
  ) |>
  dplyr::arrange(
    dplyr::desc(
      n_sites
    )
  )

pooled_regime_metrics <- predictions |>
  dplyr::group_by(
    validation_scheme,
    model_name,
    geological_regime_primary
  ) |>
  dplyr::group_modify(
    ~ calculate_metrics(
      observed =
        .x$observed_sr,

      predicted =
        .x$predicted_sr
    )
  ) |>
  dplyr::ungroup() |>
  dplyr::group_by(
    validation_scheme,
    geological_regime_primary
  ) |>
  dplyr::mutate(
    rmse_rank =
      dplyr::min_rank(
        rmse
      ),

    best_rmse_at_scale =
      rmse_rank ==
        1L
  ) |>
  dplyr::ungroup() |>
  dplyr::mutate(
    sample_size_flag =
      dplyr::case_when(
        n < 20L ~
          "very_small_n",

        n < 50L ~
          "small_n",

        TRUE ~
          "adequate_n"
      )
  ) |>
  dplyr::arrange(
    validation_scheme,
    geological_regime_primary,
    rmse_rank,
    model_name
  )

expected_pooled_rows <-
  length(expected_schemes) *
  length(expected_models) *
  length(regime_levels)

if (
  nrow(pooled_regime_metrics) !=
    expected_pooled_rows
) {
  stop(
    "Expected ",
    expected_pooled_rows,
    " pooled metric rows; found ",
    nrow(pooled_regime_metrics),
    "."
  )
}

fold_regime_metrics <- predictions |>
  dplyr::group_by(
    validation_scheme,
    outer_fold,
    model_name,
    geological_regime_primary
  ) |>
  dplyr::group_modify(
    ~ calculate_metrics(
      observed =
        .x$observed_sr,

      predicted =
        .x$predicted_sr
    )
  ) |>
  dplyr::ungroup() |>
  dplyr::arrange(
    validation_scheme,
    outer_fold,
    geological_regime_primary,
    model_name
  )

baseline_fold_metrics <- fold_regime_metrics |>
  dplyr::filter(
    model_name ==
      "M0_P0_FULL"
  ) |>
  dplyr::select(
    validation_scheme,
    outer_fold,
    geological_regime_primary,

    baseline_n =
      n,

    baseline_rmse =
      rmse,

    baseline_mae =
      mae,

    baseline_bias =
      bias,

    baseline_r2 =
      r2,

    baseline_underprediction_fraction =
      underprediction_fraction
  )

paired_fold_deltas <- fold_regime_metrics |>
  dplyr::filter(
    model_name !=
      "M0_P0_FULL"
  ) |>
  dplyr::left_join(
    baseline_fold_metrics,
    by =
      c(
        "validation_scheme",
        "outer_fold",
        "geological_regime_primary"
      )
  ) |>
  dplyr::mutate(
    delta_rmse =
      rmse -
      baseline_rmse,

    delta_mae =
      mae -
      baseline_mae,

    delta_bias =
      bias -
      baseline_bias,

    delta_r2 =
      r2 -
      baseline_r2,

    delta_underprediction_fraction =
      underprediction_fraction -
      baseline_underprediction_fraction,

    better_rmse_than_m0 =
      delta_rmse <
      0
  ) |>
  dplyr::arrange(
    validation_scheme,
    geological_regime_primary,
    model_name,
    outer_fold
  )

if (
  anyNA(
    paired_fold_deltas$baseline_rmse
  )
) {
  stop(
    "Some mechanistic fold/regime rows could not be paired with M0."
  )
}

paired_regime_summary <- paired_fold_deltas |>
  dplyr::group_by(
    validation_scheme,
    model_name,
    geological_regime_primary
  ) |>
  dplyr::summarise(
    n_folds_available =
      dplyr::n(),

    total_test_rows =
      sum(n),

    mean_delta_rmse =
      mean(delta_rmse),

    median_delta_rmse =
      stats::median(delta_rmse),

    folds_better_rmse =
      sum(
        better_rmse_than_m0
      ),

    mean_delta_mae =
      mean(delta_mae),

    mean_delta_bias =
      mean(delta_bias),

    mean_delta_r2 =
      safe_mean(delta_r2),

    mean_delta_underprediction_fraction =
      mean(
        delta_underprediction_fraction
      ),

    .groups = "drop"
  ) |>
  dplyr::arrange(
    validation_scheme,
    geological_regime_primary,
    mean_delta_rmse,
    model_name
  )

regime_winners <- pooled_regime_metrics |>
  dplyr::filter(
    best_rmse_at_scale
  ) |>
  dplyr::select(
    validation_scheme,
    geological_regime_primary,
    winner_model =
      model_name,

    n,
    rmse,
    mae,
    bias,
    r2,
    underprediction_fraction
  ) |>
  dplyr::arrange(
    validation_scheme,
    geological_regime_primary,
    winner_model
  )

winner_counts <- regime_winners |>
  dplyr::count(
    winner_model,
    name =
      "n_regime_scale_wins"
  ) |>
  dplyr::arrange(
    dplyr::desc(
      n_regime_scale_wins
    ),
    winner_model
  )

cross_scale_regime_summary <- pooled_regime_metrics |>
  dplyr::group_by(
    model_name,
    geological_regime_primary
  ) |>
  dplyr::summarise(
    n_sites =
      dplyr::first(n),

    mean_rmse_across_scales =
      mean(rmse),

    minimum_rmse_across_scales =
      min(rmse),

    maximum_rmse_across_scales =
      max(rmse),

    mean_mae_across_scales =
      mean(mae),

    mean_bias_across_scales =
      mean(bias),

    mean_absolute_bias_across_scales =
      mean(
        abs(bias)
      ),

    mean_underprediction_fraction =
      mean(
        underprediction_fraction
      ),

    scales_ranked_first =
      sum(
        best_rmse_at_scale
      ),

    n_ge_072 =
      dplyr::first(
        n_ge_072
      ),

    n_ge_075 =
      dplyr::first(
        n_ge_075
      ),

    n_ge_080 =
      dplyr::first(
        n_ge_080
      ),

    .groups = "drop"
  ) |>
  dplyr::arrange(
    geological_regime_primary,
    mean_rmse_across_scales,
    model_name
  )

full_regime_diagnostics <- cross_scale_regime_summary |>
  dplyr::filter(
    model_name ==
      "M_FULL_MECHANISTIC"
  ) |>
  dplyr::arrange(
    dplyr::desc(
      mean_rmse_across_scales
    )
  )

core_regime_diagnostics <- cross_scale_regime_summary |>
  dplyr::filter(
    model_name ==
      "M_CORE_MECHANISTIC"
  ) |>
  dplyr::arrange(
    dplyr::desc(
      mean_rmse_across_scales
    )
  )

readr::write_csv(
  coverage_audit,
  file.path(
    out_dir,
    "prediction_coverage_audit.csv"
  )
)

readr::write_csv(
  regime_sample_distribution,
  file.path(
    out_dir,
    "regime_sample_distribution.csv"
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
  fold_regime_metrics,
  file.path(
    out_dir,
    "fold_regime_metrics.csv"
  )
)

readr::write_csv(
  paired_fold_deltas,
  file.path(
    out_dir,
    "paired_fold_deltas_vs_m0.csv"
  )
)

readr::write_csv(
  paired_regime_summary,
  file.path(
    out_dir,
    "paired_regime_summary_vs_m0.csv"
  )
)

readr::write_csv(
  regime_winners,
  file.path(
    out_dir,
    "regime_winners_by_scale.csv"
  )
)

readr::write_csv(
  winner_counts,
  file.path(
    out_dir,
    "regime_winner_counts.csv"
  )
)

readr::write_csv(
  cross_scale_regime_summary,
  file.path(
    out_dir,
    "cross_scale_regime_summary.csv"
  )
)

readr::write_csv(
  full_regime_diagnostics,
  file.path(
    out_dir,
    "full_model_regime_diagnostics.csv"
  )
)

readr::write_csv(
  core_regime_diagnostics,
  file.path(
    out_dir,
    "core_model_regime_diagnostics.csv"
  )
)

summary_lines <- c(
  "R57B GEOLOGICAL-REGIME HELD-OUT VALIDATION",
  "==========================================",
  "",
  paste0(
    "Input prediction rows: ",
    nrow(predictions)
  ),
  paste0(
    "Unique observations: ",
    nrow(unique_observations)
  ),
  paste0(
    "Validation schemes: ",
    length(expected_schemes)
  ),
  paste0(
    "Models: ",
    length(expected_models)
  ),
  paste0(
    "Geological regimes: ",
    length(regime_levels)
  ),
  paste0(
    "Pooled regime/model/scale rows: ",
    nrow(pooled_regime_metrics)
  ),
  "",
  "Winner counts across 21 regime-by-scale comparisons:",
  paste0(
    winner_counts$winner_model,
    ": ",
    winner_counts$n_regime_scale_wins
  ),
  "",
  paste(
    "Metrics are based only on spatial held-out predictions.",
    "No model was refitted."
  ),
  paste(
    "RMSE, MAE and bias are primary.",
    "Within-regime R2 is descriptive because some regimes have limited variance."
  ),
  "",
  "STATUS: R57B GEOLOGICAL-REGIME VALIDATION PASSED"
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
  "\n\n"
)

cat(
  "===== REGIME SAMPLE DISTRIBUTION =====\n"
)

print(
  regime_sample_distribution,
  n = Inf,
  width = Inf
)

cat(
  "\n===== WINNER COUNTS =====\n"
)

print(
  winner_counts,
  n = Inf,
  width = Inf
)

cat(
  "\n===== FULL MODEL REGIME DIAGNOSTICS =====\n"
)

print(
  full_regime_diagnostics,
  n = Inf,
  width = Inf
)
