source("R/functions/core.R")

check_packages(
  c(
    "dplyr",
    "readr",
    "tibble"
  )
)

root <- project_root()

out_dir <- file.path(
  root,
  "outputs",
  "r55_model_selection"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

spatial_metrics_file <- file.path(
  root,
  "outputs",
  "r52_nested_spatial_rf",
  "aggregate",
  "pooled_outer_metrics.csv"
)

spatial_delta_file <- file.path(
  root,
  "outputs",
  "r52_nested_spatial_rf",
  "aggregate",
  "paired_delta_summary.csv"
)

reference_metrics_file <- file.path(
  root,
  "outputs",
  "r54_nested_reference_rf",
  "aggregate",
  "pooled_outer_metrics.csv"
)

reference_fold_file <- file.path(
  root,
  "outputs",
  "r54_nested_reference_rf",
  "aggregate",
  "paired_fold_summary.csv"
)

reference_pair_file <- file.path(
  root,
  "outputs",
  "r54_nested_reference_rf",
  "aggregate",
  "paired_reference_summary.csv"
)

reference_macro_file <- file.path(
  root,
  "outputs",
  "r54_nested_reference_rf",
  "aggregate",
  "reference_macro_summary.csv"
)

feature_sets_file <- file.path(
  root,
  "outputs",
  "r50b_feature_architecture",
  "model_feature_sets.rds"
)

required_files <- c(
  spatial_metrics_file,
  spatial_delta_file,
  reference_metrics_file,
  reference_fold_file,
  reference_pair_file,
  reference_macro_file,
  feature_sets_file
)

missing_files <- required_files[
  !file.exists(
    required_files
  )
]

if (length(missing_files) > 0L) {
  stop(
    "Missing R55 input files: ",
    paste(
      missing_files,
      collapse = ", "
    )
  )
}

require_columns <- function(
  x,
  required,
  object_name
) {
  missing_columns <- setdiff(
    required,
    names(x)
  )

  if (length(missing_columns) > 0L) {
    stop(
      object_name,
      " is missing columns: ",
      paste(
        missing_columns,
        collapse = ", "
      )
    )
  }

  invisible(TRUE)
}

spatial_metrics <- readr::read_csv(
  spatial_metrics_file,
  show_col_types = FALSE
)

spatial_deltas <- readr::read_csv(
  spatial_delta_file,
  show_col_types = FALSE
)

reference_metrics <- readr::read_csv(
  reference_metrics_file,
  show_col_types = FALSE
)

reference_folds <- readr::read_csv(
  reference_fold_file,
  show_col_types = FALSE
)

reference_pairs <- readr::read_csv(
  reference_pair_file,
  show_col_types = FALSE
)

reference_macro <- readr::read_csv(
  reference_macro_file,
  show_col_types = FALSE
)

feature_sets <- readRDS(
  feature_sets_file
)

model_names <- c(
  "M0_P0_FULL",
  "M_CORE_MECHANISTIC",
  "M_FULL_MECHANISTIC"
)

mechanistic_models <- c(
  "M_CORE_MECHANISTIC",
  "M_FULL_MECHANISTIC"
)

require_columns(
  spatial_metrics,
  c(
    "validation_scheme",
    "model_name",
    "evaluation_subset",
    "n",
    "rmse",
    "mae",
    "r2",
    "bias",
    "calibration_slope",
    "underprediction_fraction"
  ),
  "R52 pooled metrics"
)

require_columns(
  spatial_deltas,
  c(
    "validation_scheme",
    "model_name",
    "n_folds",
    "mean_delta_rmse",
    "median_delta_rmse",
    "folds_better_rmse",
    "mean_delta_mae",
    "mean_delta_r2",
    "mean_delta_bias"
  ),
  "R52 paired delta summary"
)

require_columns(
  reference_metrics,
  c(
    "model_name",
    "evaluation_subset",
    "n",
    "rmse",
    "mae",
    "r2",
    "bias",
    "calibration_slope",
    "underprediction_fraction"
  ),
  "R54 pooled metrics"
)

require_columns(
  reference_folds,
  c(
    "model_name",
    "evaluation_subset",
    "n_outer_folds",
    "mean_delta_rmse",
    "median_delta_rmse",
    "folds_better_rmse"
  ),
  "R54 paired fold summary"
)

require_columns(
  reference_pairs,
  c(
    "model_name",
    "n_reference_groups",
    "references_better_rmse",
    "proportion_references_better_rmse",
    "mean_delta_rmse",
    "median_delta_rmse",
    "weighted_mean_delta_rmse",
    "references_n_ge_5_better_rmse",
    "n_references_n_ge_5"
  ),
  "R54 paired reference summary"
)

require_columns(
  reference_macro,
  c(
    "model_name",
    "mean_reference_rmse",
    "median_reference_rmse",
    "weighted_mean_reference_rmse",
    "mean_reference_mae",
    "median_reference_mae",
    "mean_absolute_reference_bias"
  ),
  "R54 reference macro summary"
)

missing_model_sets <- setdiff(
  model_names,
  names(feature_sets)
)

if (length(missing_model_sets) > 0L) {
  stop(
    "Feature-set object is missing models: ",
    paste(
      missing_model_sets,
      collapse = ", "
    )
  )
}

feature_counts <- tibble::tibble(
  model_name =
    model_names,

  n_features =
    vapply(
      model_names,
      function(model_name) {
        length(
          feature_sets[[model_name]]
        )
      },
      integer(1)
    )
)

spatial_overall <- spatial_metrics |>
  dplyr::filter(
    evaluation_subset ==
      "all",
    model_name %in%
      model_names
  )

if (nrow(spatial_overall) != 9L) {
  stop(
    "Expected nine spatial scheme/model rows; found ",
    nrow(spatial_overall),
    "."
  )
}

spatial_scale_scorecard <- spatial_overall |>
  dplyr::group_by(
    validation_scheme
  ) |>
  dplyr::mutate(
    rmse_rank =
      rank(
        rmse,
        ties.method = "min"
      ),

    best_at_scale =
      rmse_rank ==
        1L
  ) |>
  dplyr::ungroup() |>
  dplyr::arrange(
    validation_scheme,
    rmse_rank,
    model_name
  )

spatial_summary <- spatial_scale_scorecard |>
  dplyr::group_by(
    model_name
  ) |>
  dplyr::summarise(
    n_spatial_scales =
      dplyr::n_distinct(
        validation_scheme
      ),

    mean_spatial_rmse =
      mean(rmse),

    median_spatial_rmse =
      stats::median(rmse),

    minimum_spatial_rmse =
      min(rmse),

    maximum_spatial_rmse =
      max(rmse),

    mean_spatial_mae =
      mean(mae),

    mean_spatial_r2 =
      mean(r2),

    mean_spatial_bias =
      mean(bias),

    spatial_scales_ranked_first =
      sum(best_at_scale),

    .groups = "drop"
  )

spatial_delta_overall <- spatial_deltas |>
  dplyr::filter(
    model_name %in%
      model_names
  ) |>
  dplyr::group_by(
    model_name
  ) |>
  dplyr::summarise(
    spatial_folds_evaluated =
      sum(n_folds),

    spatial_folds_better_than_m0 =
      sum(
        folds_better_rmse
      ),

    mean_spatial_delta_rmse_vs_m0 =
      mean(
        mean_delta_rmse
      ),

    median_spatial_delta_rmse_vs_m0 =
      stats::median(
        median_delta_rmse
      ),

    mean_spatial_delta_mae_vs_m0 =
      mean(
        mean_delta_mae
      ),

    .groups = "drop"
  )

reference_overall <- reference_metrics |>
  dplyr::filter(
    evaluation_subset ==
      "all",
    model_name %in%
      model_names
  ) |>
  dplyr::transmute(
    model_name,

    reference_rmse =
      rmse,

    reference_mae =
      mae,

    reference_r2 =
      r2,

    reference_bias =
      bias,

    reference_calibration_slope =
      calibration_slope,

    reference_underprediction_fraction =
      underprediction_fraction
  )

if (nrow(reference_overall) != 3L) {
  stop(
    "Expected three pooled reference-validation rows; found ",
    nrow(reference_overall),
    "."
  )
}

reference_fold_overall <- reference_folds |>
  dplyr::filter(
    evaluation_subset ==
      "all",
    model_name %in%
      model_names
  ) |>
  dplyr::transmute(
    model_name,

    reference_outer_folds =
      n_outer_folds,

    reference_folds_better_than_m0 =
      folds_better_rmse,

    mean_reference_fold_delta_rmse_vs_m0 =
      mean_delta_rmse,

    median_reference_fold_delta_rmse_vs_m0 =
      median_delta_rmse
  )

reference_pair_summary <- reference_pairs |>
  dplyr::filter(
    model_name %in%
      mechanistic_models
  )

reference_macro_summary <- reference_macro |>
  dplyr::filter(
    model_name %in%
      model_names
  )

scorecard <- feature_counts |>
  dplyr::left_join(
    spatial_summary,
    by = "model_name"
  ) |>
  dplyr::left_join(
    spatial_delta_overall,
    by = "model_name"
  ) |>
  dplyr::left_join(
    reference_overall,
    by = "model_name"
  ) |>
  dplyr::left_join(
    reference_fold_overall,
    by = "model_name"
  ) |>
  dplyr::left_join(
    reference_macro_summary,
    by = "model_name"
  ) |>
  dplyr::left_join(
    reference_pair_summary |>
      dplyr::select(
        model_name,
        n_reference_groups,
        references_better_rmse,
        proportion_references_better_rmse,
        weighted_mean_delta_rmse,
        references_n_ge_5_better_rmse,
        n_references_n_ge_5
      ),
    by = "model_name"
  )

if (
  nrow(scorecard) !=
    3L ||
  anyNA(
    scorecard$
      mean_spatial_rmse
  ) ||
  anyNA(
    scorecard$
      reference_rmse
  )
) {
  stop(
    "R55 model-selection scorecard is incomplete."
  )
}

m0_spatial_rmse <- scorecard |>
  dplyr::filter(
    model_name ==
      "M0_P0_FULL"
  ) |>
  dplyr::pull(
    mean_spatial_rmse
  )

m0_reference_rmse <- scorecard |>
  dplyr::filter(
    model_name ==
      "M0_P0_FULL"
  ) |>
  dplyr::pull(
    reference_rmse
  )

scorecard <- scorecard |>
  dplyr::mutate(
    mean_spatial_rmse_improvement_vs_m0_pct =
      100 *
      (
        m0_spatial_rmse -
          mean_spatial_rmse
      ) /
      m0_spatial_rmse,

    reference_rmse_improvement_vs_m0_pct =
      100 *
      (
        m0_reference_rmse -
          reference_rmse
      ) /
      m0_reference_rmse
  )

mechanistic_ranking <- scorecard |>
  dplyr::filter(
    model_name %in%
      mechanistic_models
  ) |>
  dplyr::arrange(
    reference_rmse,
    mean_spatial_rmse,
    n_features
  ) |>
  dplyr::mutate(
    selection_rank =
      dplyr::row_number()
  )

primary_model <-
  mechanistic_ranking$
    model_name[[1]]

sensitivity_model <-
  mechanistic_ranking$
    model_name[[2]]

scorecard <- scorecard |>
  dplyr::mutate(
    deployment_role =
      dplyr::case_when(
        model_name ==
          primary_model ~
          "primary_final_isoscape",

        model_name ==
          sensitivity_model ~
          "mandatory_sensitivity_isoscape",

        TRUE ~
          "baseline_comparator"
      ),

    selection_status =
      dplyr::case_when(
        model_name ==
          primary_model ~
          "SELECTED_PRIMARY",

        model_name ==
          sensitivity_model ~
          "SELECTED_SENSITIVITY",

        TRUE ~
          "BASELINE"
      )
  ) |>
  dplyr::arrange(
    match(
      model_name,
      model_names
    )
  )

reference_tail_scorecard <- reference_metrics |>
  dplyr::filter(
    evaluation_subset %in%
      c(
        "ge_075",
        "ge_080"
      ),
    model_name %in%
      model_names
  ) |>
  dplyr::arrange(
    evaluation_subset,
    rmse,
    model_name
  )

readr::write_csv(
  scorecard,
  file.path(
    out_dir,
    "model_selection_scorecard.csv"
  )
)

readr::write_csv(
  spatial_scale_scorecard,
  file.path(
    out_dir,
    "spatial_scale_scorecard.csv"
  )
)

readr::write_csv(
  spatial_deltas,
  file.path(
    out_dir,
    "spatial_paired_delta_summary.csv"
  )
)

readr::write_csv(
  reference_tail_scorecard,
  file.path(
    out_dir,
    "high_tail_validation_scorecard.csv"
  )
)

readr::write_csv(
  reference_pairs,
  file.path(
    out_dir,
    "reference_group_comparison.csv"
  )
)

model_decision <- list(
  primary_model =
    primary_model,

  sensitivity_model =
    sensitivity_model,

  baseline_model =
    "M0_P0_FULL",

  primary_feature_set =
    feature_sets[[primary_model]],

  sensitivity_feature_set =
    feature_sets[[sensitivity_model]],

  selection_rule =
    paste(
      "Among the two mechanistic models, the primary model",
      "has the lowest outcome-blind pooled reference-group RMSE;",
      "mean outcome-blind spatial RMSE is the secondary criterion."
    ),

  validation_basis =
    c(
      "R52 outcome-blind nested spatial validation",
      "R54 outcome-blind nested reference-group validation"
    ),

  permutation_importance_status =
    paste(
      "R53 was intentionally skipped after a partial run",
      "and was not used for model selection."
    ),

  scorecard =
    scorecard,

  spatial_scale_scorecard =
    spatial_scale_scorecard,

  high_tail_scorecard =
    reference_tail_scorecard,

  created_at =
    as.character(
      Sys.time()
    )
)

saveRDS(
  model_decision,
  file.path(
    out_dir,
    "model_decision.rds"
  ),
  version = 3
)

primary_row <- scorecard |>
  dplyr::filter(
    model_name ==
      primary_model
  )

sensitivity_row <- scorecard |>
  dplyr::filter(
    model_name ==
      sensitivity_model
  )

summary_lines <- c(
  "R55 OUTCOME-BLIND MODEL SELECTION",
  "=================================",
  "",
  paste0(
    "Primary final model: ",
    primary_model
  ),
  paste0(
    "Mandatory sensitivity model: ",
    sensitivity_model
  ),
  "Baseline model: M0_P0_FULL",
  "",
  paste0(
    "Primary feature count: ",
    primary_row$n_features[[1]]
  ),
  paste0(
    "Primary mean spatial RMSE: ",
    primary_row$mean_spatial_rmse[[1]]
  ),
  paste0(
    "Sensitivity mean spatial RMSE: ",
    sensitivity_row$mean_spatial_rmse[[1]]
  ),
  paste0(
    "Primary reference-group RMSE: ",
    primary_row$reference_rmse[[1]]
  ),
  paste0(
    "Sensitivity reference-group RMSE: ",
    sensitivity_row$reference_rmse[[1]]
  ),
  paste0(
    "Primary spatial scales ranked first: ",
    primary_row$
      spatial_scales_ranked_first[[1]],
    " / 3"
  ),
  paste0(
    "Sensitivity spatial scales ranked first: ",
    sensitivity_row$
      spatial_scales_ranked_first[[1]],
    " / 3"
  ),
  "",
  paste(
    "R53 held-out permutation importance was skipped",
    "and was not used for model selection."
  ),
  paste(
    "High-Sr tail performance remains a separately",
    "reported limitation."
  ),
  "",
  "STATUS: R55 OUTCOME-BLIND MODEL SELECTION PASSED"
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
