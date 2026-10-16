#!/usr/bin/env Rscript

options(
  stringsAsFactors = FALSE,
  warn = 1
)

source("R/functions/core.R")
source("R/functions/folds.R")
source("R/functions/metrics.R")
source("R/functions/modeling.R")
source("R/functions/predictor_sets.R")

check_packages(
  c(
    "sf",
    "dplyr",
    "readr",
    "ranger",
    "Cubist",
    "tibble"
  )
)

cfg <- read_config()
ensure_dirs(cfg)


output_dir <- file.path(
  project_root(),
  "outputs/experiment_age_stop_test"
)

dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)


model_path <- file.path(
  project_root(),
  "data/processed/model_table_age_test.rds"
)

folds_path <- file.path(
  project_root(),
  "data/processed/folds_long.rds"
)

stop_missing(
  model_path,
  "Run stage 30 first."
)

stop_missing(
  folds_path,
  "Run stage 03 first."
)


dat <- readRDS(
  model_path
)

folds_all <- readRDS(
  folds_path
)


if (inherits(dat, "sf")) {
  dat <- sf::st_drop_geometry(dat)
}


required_core_columns <- c(
  "row_id",
  "sr87_sr86",
  "latitude",
  "longitude"
)

missing_core_columns <- setdiff(
  required_core_columns,
  names(dat)
)

if (length(missing_core_columns) > 0L) {
  stop(
    "Missing required model columns: ",
    paste(
      missing_core_columns,
      collapse = ", "
    )
  )
}


if (
  anyDuplicated(dat$row_id) > 0L ||
  any(is.na(dat$row_id))
) {
  stop(
    "Missing or duplicated row_id in age-test model table."
  )
}


p0_predictors <- grep(
  "^p0__",
  names(dat),
  value = TRUE
)

if (length(p0_predictors) != 28L) {
  stop(
    "Expected 28 P0 predictors; found ",
    length(p0_predictors)
  )
}


local_age_predictors <- c(
  "local_geo_age_mean_ma",
  "local_geo_age_sd_ma"
)

upstream_age_predictors <- c(
  "up_geo_age_mean_ma",
  "up_geo_age_sd_ma"
)

combined_age_predictors <- c(
  local_age_predictors,
  upstream_age_predictors,
  "local_geo_frac_midpoint_gt_1000",
  "up_geo_frac_midpoint_gt_1000",
  "local_geo_frac_midpoint_gt_2000",
  "up_geo_frac_midpoint_gt_2000"
)


predictor_sets <- list(
  P0 = p0_predictors,

  P1_local_age = c(
    p0_predictors,
    local_age_predictors
  ),

  P2_upstream_age = c(
    p0_predictors,
    upstream_age_predictors
  ),

  P3_combined_age = c(
    p0_predictors,
    combined_age_predictors
  )
)


all_required_predictors <- unique(
  unlist(
    predictor_sets,
    use.names = FALSE
  )
)

missing_predictor_columns <- setdiff(
  all_required_predictors,
  names(dat)
)

if (length(missing_predictor_columns) > 0L) {
  stop(
    "Missing predictors: ",
    paste(
      missing_predictor_columns,
      collapse = ", "
    )
  )
}


cat(
  "Locking a common complete sample across P0-P3...\n"
)

common_complete <- complete.cases(
  dat[
    ,
    unique(
      c(
        "sr87_sr86",
        all_required_predictors
      )
    ),
    drop = FALSE
  ]
)

dat_common <- dat[
  common_complete,
  ,
  drop = FALSE
]


if (nrow(dat_common) < 1L) {
  stop(
    "No common complete rows were found."
  )
}


target_scheme <- "spatial_1500km"

folds <- folds_all |>
  dplyr::filter(
    .data$scheme == target_scheme,
    .data$row_id %in% dat_common$row_id
  )


fold_duplicate_count <- folds |>
  dplyr::count(
    .data$row_id,
    name = "n"
  ) |>
  dplyr::filter(
    .data$n != 1L
  ) |>
  nrow()


if (fold_duplicate_count > 0L) {
  stop(
    "Some common-sample row_id values have zero or multiple fold assignments."
  )
}


missing_fold_ids <- setdiff(
  dat_common$row_id,
  folds$row_id
)

if (length(missing_fold_ids) > 0L) {
  stop(
    "Common-sample observations absent from spatial_1500km folds: ",
    length(missing_fold_ids)
  )
}


observed_outer_folds <- sort(
  unique(
    folds$fold
  )
)

if (!identical(
  observed_outer_folds,
  1:5
)) {
  stop(
    "Expected outer folds 1 through 5; found: ",
    paste(
      observed_outer_folds,
      collapse = ","
    )
  )
}


analysis_sample_qc <- tibble::tibble(
  metric = c(
    "original_model_rows",
    "common_complete_rows",
    "excluded_rows",
    "common_high_ge_0p720",
    "common_high_ge_0p722",
    "common_high_ge_0p750",
    "common_high_ge_0p800",
    "common_observed_maximum",
    "spatial_1500km_fold_rows",
    "spatial_1500km_unique_row_ids",
    "p0_predictor_count",
    "p1_predictor_count",
    "p2_predictor_count",
    "p3_predictor_count"
  ),

  value = c(
    nrow(dat),
    nrow(dat_common),
    nrow(dat) - nrow(dat_common),

    sum(
      dat_common$sr87_sr86 >= 0.720,
      na.rm = TRUE
    ),

    sum(
      dat_common$sr87_sr86 >= 0.722,
      na.rm = TRUE
    ),

    sum(
      dat_common$sr87_sr86 >= 0.750,
      na.rm = TRUE
    ),

    sum(
      dat_common$sr87_sr86 >= 0.800,
      na.rm = TRUE
    ),

    max(
      dat_common$sr87_sr86,
      na.rm = TRUE
    ),

    nrow(folds),

    dplyr::n_distinct(
      folds$row_id
    ),

    length(
      predictor_sets$P0
    ),

    length(
      predictor_sets$P1_local_age
    ),

    length(
      predictor_sets$P2_upstream_age
    ),

    length(
      predictor_sets$P3_combined_age
    )
  )
)


readr::write_csv(
  analysis_sample_qc,
  file.path(
    output_dir,
    "analysis_sample_qc.csv"
  )
)


predictor_manifest <- dplyr::bind_rows(
  lapply(
    names(predictor_sets),
    function(set_name) {

      tibble::tibble(
        predictor_set = set_name,
        predictor = predictor_sets[[
          set_name
        ]]
      )
    }
  )
)


readr::write_csv(
  predictor_manifest,
  file.path(
    output_dir,
    "predictor_set_manifest.csv"
  )
)


fold_balance <- folds |>
  dplyr::left_join(
    dat_common |>
      dplyr::select(
        .data$row_id,
        .data$sr87_sr86
      ),
    by = "row_id"
  ) |>
  dplyr::group_by(
    .data$scheme,
    outer_fold = .data$fold
  ) |>
  dplyr::summarise(
    n = dplyr::n(),

    high_n = sum(
      .data$sr87_sr86 >=
        cfg$selection$high_threshold,
      na.rm = TRUE
    ),

    maximum_observed = max(
      .data$sr87_sr86,
      na.rm = TRUE
    ),

    .groups = "drop"
  )


readr::write_csv(
  fold_balance,
  file.path(
    output_dir,
    "common_sample_fold_balance.csv"
  )
)


extended_metric_row <- function(
  observed,
  predicted,
  threshold = 0.720
) {

  valid <- (
    is.finite(observed) &
      is.finite(predicted)
  )

  observed <- observed[
    valid
  ]

  predicted <- predicted[
    valid
  ]

  base <- metric_row(
    observed,
    predicted,
    threshold
  )

  residual <- predicted - observed

  high <- observed >= threshold

  high_pred_on_obs_slope <- if (
    sum(high) >= 2L &&
    length(
      unique(
        observed[
          high
        ]
      )
    ) >= 2L
  ) {

    tryCatch(
      unname(
        stats::coef(
          stats::lm(
            predicted[
              high
            ] ~ observed[
              high
            ]
          )
        )[2]
      ),
      error = function(e) NA_real_
    )

  } else {

    NA_real_
  }

  high_obs_on_pred_slope <- if (
    sum(high) >= 2L &&
    length(
      unique(
        predicted[
          high
        ]
      )
    ) >= 2L
  ) {

    tryCatch(
      unname(
        stats::coef(
          stats::lm(
            observed[
              high
            ] ~ predicted[
              high
            ]
          )
        )[2]
      ),
      error = function(e) NA_real_
    )

  } else {

    NA_real_
  }


  tibble::as_tibble(
    base
  ) |>
    dplyr::mutate(
      n = length(observed),

      high_n = sum(high),

      high_mae = if (any(high)) {
        mean(
          abs(
            residual[
              high
            ]
          )
        )
      } else {
        NA_real_
      },

      high_median_bias = if (any(high)) {
        stats::median(
          residual[
            high
          ]
        )
      } else {
        NA_real_
      },

      high_pred_on_obs_slope =
        high_pred_on_obs_slope,

      high_obs_on_pred_slope =
        high_obs_on_pred_slope,

      high_max_observed = if (any(high)) {
        max(
          observed[
            high
          ]
        )
      } else {
        NA_real_
      },

      high_max_predicted = if (any(high)) {
        max(
          predicted[
            high
          ]
        )
      } else {
        NA_real_
      },

      residual_definition =
        "predicted_minus_observed"
    )
}


algorithms <- c(
  "RF",
  "Cubist"
)

all_predictions <- list()
all_tuning <- list()
all_metrics <- list()


cat(
  "Running formal nested CV on common sample: ",
  nrow(dat_common),
  " rows.\n",
  sep = ""
)


for (set_name in names(predictor_sets)) {

  predictors <- predictor_sets[[
    set_name
  ]]

  if (
    any(
      !complete.cases(
        dat_common[
          ,
          predictors,
          drop = FALSE
        ]
      )
    )
  ) {
    stop(
      "Unexpected missing predictor values in common sample: ",
      set_name
    )
  }

  log_msg(
    target_scheme,
    " / ",
    set_name,
    ": using ",
    nrow(dat_common),
    " common rows and ",
    length(predictors),
    " predictors."
  )


  for (algorithm in algorithms) {

    result <- run_nested_cv(
      dat_common,
      folds,
      predictors,
      cfg$project$outcome,
      algorithm,
      cfg,
      seed = cfg$project$seed
    )


    predictions <- result$predictions |>
      dplyr::mutate(
        scheme = target_scheme,
        predictor_set = set_name
      )


    fold_metrics <- predictions |>
      dplyr::group_by(
        .data$scheme,
        .data$predictor_set,
        .data$algorithm,
        .data$outer_fold
      ) |>
      dplyr::group_modify(
        ~extended_metric_row(
          .x$observed,
          .x$predicted,
          cfg$selection$high_threshold
        )
      ) |>
      dplyr::ungroup()


    tuning <- result$tuning |>
      dplyr::mutate(
        scheme = target_scheme,
        predictor_set = set_name
      )


    all_predictions[[
      length(all_predictions) + 1L
    ]] <- predictions

    all_tuning[[
      length(all_tuning) + 1L
    ]] <- tuning

    all_metrics[[
      length(all_metrics) + 1L
    ]] <- fold_metrics


    write_atomic_rds(
      dplyr::bind_rows(
        all_predictions
      ),
      file.path(
        output_dir,
        "oof_predictions_partial.rds"
      )
    )
  }
}


predictions <- dplyr::bind_rows(
  all_predictions
)

tuning <- dplyr::bind_rows(
  all_tuning
)

metrics_by_outer_fold <- dplyr::bind_rows(
  all_metrics
)


write_atomic_rds(
  predictions,
  file.path(
    output_dir,
    "oof_predictions.rds"
  )
)

readr::write_csv(
  predictions,
  file.path(
    output_dir,
    "oof_predictions.csv"
  )
)

write_atomic_rds(
  tuning,
  file.path(
    output_dir,
    "inner_tuning.rds"
  )
)

readr::write_csv(
  metrics_by_outer_fold,
  file.path(
    output_dir,
    "metrics_by_outer_fold.csv"
  )
)


pooled_metrics <- predictions |>
  dplyr::group_by(
    .data$scheme,
    .data$predictor_set,
    .data$algorithm
  ) |>
  dplyr::group_modify(
    ~extended_metric_row(
      .x$observed,
      .x$predicted,
      cfg$selection$high_threshold
    )
  ) |>
  dplyr::ungroup()


readr::write_csv(
  pooled_metrics,
  file.path(
    output_dir,
    "pooled_metrics.csv"
  )
)


fold_mean_metrics <- metrics_by_outer_fold |>
  dplyr::group_by(
    .data$scheme,
    .data$predictor_set,
    .data$algorithm
  ) |>
  dplyr::summarise(
    dplyr::across(
      where(is.numeric),
      ~mean(
        .x,
        na.rm = TRUE
      )
    ),

    .groups = "drop"
  )


readr::write_csv(
  fold_mean_metrics,
  file.path(
    output_dir,
    "mean_metrics_across_outer_folds.csv"
  )
)


best_parameters <- predictions |>
  dplyr::distinct(
    .data$scheme,
    .data$predictor_set,
    .data$algorithm,
    .data$outer_fold,
    .data$best_param_id
  ) |>
  dplyr::arrange(
    .data$algorithm,
    .data$predictor_set,
    .data$outer_fold
  )


readr::write_csv(
  best_parameters,
  file.path(
    output_dir,
    "best_parameters_by_outer_fold.csv"
  )
)


comparison_columns <- c(
  "rmse",
  "mae",
  "bias",
  "high_rmse",
  "high_mae",
  "high_bias",
  "high_median_bias",
  "top10_bias",
  "top05_bias",
  "max_predicted",
  "high_max_predicted",
  "high_pred_on_obs_slope"
)


p0_fold_reference <- metrics_by_outer_fold |>
  dplyr::filter(
    .data$predictor_set == "P0"
  ) |>
  dplyr::select(
    .data$algorithm,
    .data$outer_fold,
    dplyr::all_of(
      comparison_columns
    )
  ) |>
  dplyr::rename_with(
    ~paste0(
      "p0_",
      .x
    ),
    dplyr::all_of(
      comparison_columns
    )
  )


comparison_by_outer_fold <- metrics_by_outer_fold |>
  dplyr::filter(
    .data$predictor_set != "P0"
  ) |>
  dplyr::left_join(
    p0_fold_reference,
    by = c(
      "algorithm",
      "outer_fold"
    )
  ) |>
  dplyr::mutate(
    delta_rmse_improvement =
      .data$p0_rmse -
        .data$rmse,

    delta_mae_improvement =
      .data$p0_mae -
        .data$mae,

    delta_high_rmse_improvement =
      .data$p0_high_rmse -
        .data$high_rmse,

    delta_high_mae_improvement =
      .data$p0_high_mae -
        .data$high_mae,

    delta_abs_high_bias_improvement =
      abs(
        .data$p0_high_bias
      ) -
        abs(
          .data$high_bias
        ),

    delta_abs_high_median_bias_improvement =
      abs(
        .data$p0_high_median_bias
      ) -
        abs(
          .data$high_median_bias
        ),

    relative_high_rmse_improvement =
      ifelse(
        is.finite(
          .data$p0_high_rmse
        ) &
          .data$p0_high_rmse != 0,
        (
          .data$p0_high_rmse -
            .data$high_rmse
        ) /
          .data$p0_high_rmse,
        NA_real_
      ),

    relative_global_rmse_change =
      ifelse(
        is.finite(
          .data$p0_rmse
        ) &
          .data$p0_rmse != 0,
        (
          .data$rmse -
            .data$p0_rmse
        ) /
          .data$p0_rmse,
        NA_real_
      )
  )


readr::write_csv(
  comparison_by_outer_fold,
  file.path(
    output_dir,
    "comparison_vs_p0_by_outer_fold.csv"
  )
)


directional_screen <- comparison_by_outer_fold |>
  dplyr::group_by(
    .data$predictor_set,
    .data$algorithm
  ) |>
  dplyr::summarise(
    mean_high_rmse_improvement =
      mean(
        .data$delta_high_rmse_improvement,
        na.rm = TRUE
      ),

    median_high_rmse_improvement =
      stats::median(
        .data$delta_high_rmse_improvement,
        na.rm = TRUE
      ),

    mean_relative_high_rmse_improvement =
      mean(
        .data$relative_high_rmse_improvement,
        na.rm = TRUE
      ),

    high_rmse_improved_fold_count =
      sum(
        .data$delta_high_rmse_improvement > 0,
        na.rm = TRUE
      ),

    high_mae_improved_fold_count =
      sum(
        .data$delta_high_mae_improvement > 0,
        na.rm = TRUE
      ),

    high_bias_improved_fold_count =
      sum(
        .data$delta_abs_high_bias_improvement > 0,
        na.rm = TRUE
      ),

    mean_abs_high_bias_improvement =
      mean(
        .data$delta_abs_high_bias_improvement,
        na.rm = TRUE
      ),

    mean_global_rmse_change =
      mean(
        .data$relative_global_rmse_change,
        na.rm = TRUE
      ),

    directional_screen_pass =
      mean_high_rmse_improvement > 0 &
        high_rmse_improved_fold_count >= 3L &
        high_bias_improved_fold_count >= 3L &
        mean_global_rmse_change <= 0.02,

    .groups = "drop"
  )


readr::write_csv(
  directional_screen,
  file.path(
    output_dir,
    "directional_stop_screen.csv"
  )
)


prediction_metadata <- dat_common |>
  dplyr::select(
    dplyr::any_of(
      c(
        "row_id",
        "basin_assignment_method",
        "up_geo_age_resolved_coverage"
      )
    )
  )


predictions_with_metadata <- predictions |>
  dplyr::left_join(
    prediction_metadata,
    by = "row_id"
  ) |>
  dplyr::mutate(
    strict_within_cov80 =
      .data$basin_assignment_method == "within" &
        is.finite(
          .data$up_geo_age_resolved_coverage
        ) &
        .data$up_geo_age_resolved_coverage >= 0.80
  )


sensitivity_predictions <- dplyr::bind_rows(
  predictions_with_metadata |>
    dplyr::mutate(
      evaluation_subset = "all_common"
    ),

  predictions_with_metadata |>
    dplyr::filter(
      .data$strict_within_cov80
    ) |>
    dplyr::mutate(
      evaluation_subset =
        "within_polygon_and_upstream_coverage_ge_0p80"
    )
)


sensitivity_metrics <- sensitivity_predictions |>
  dplyr::group_by(
    .data$evaluation_subset,
    .data$predictor_set,
    .data$algorithm
  ) |>
  dplyr::group_modify(
    ~extended_metric_row(
      .x$observed,
      .x$predicted,
      cfg$selection$high_threshold
    )
  ) |>
  dplyr::ungroup()


readr::write_csv(
  sensitivity_metrics,
  file.path(
    output_dir,
    "spatial_join_sensitivity_metrics.csv"
  )
)


tail_thresholds <- c(
  0.720,
  0.722,
  0.725,
  0.730
)


threshold_sensitivity <- dplyr::bind_rows(
  lapply(
    tail_thresholds,
    function(threshold_value) {

      predictions |>
        dplyr::group_by(
          .data$predictor_set,
          .data$algorithm
        ) |>
        dplyr::group_modify(
          ~extended_metric_row(
            .x$observed,
            .x$predicted,
            threshold_value
          )
        ) |>
        dplyr::ungroup() |>
        dplyr::mutate(
          high_threshold =
            threshold_value
        )
    }
  )
)


readr::write_csv(
  threshold_sensitivity,
  file.path(
    output_dir,
    "tail_threshold_sensitivity_metrics.csv"
  )
)


cat("\n========================================\n")
cat("AGE STOP TEST COMPLETE\n")
cat("========================================\n")

cat("\nAnalysis sample QC:\n")

print(
  analysis_sample_qc,
  n = Inf,
  width = Inf
)

cat("\nPooled metrics:\n")

print(
  pooled_metrics |>
    dplyr::select(
      .data$predictor_set,
      .data$algorithm,
      .data$rmse,
      .data$mae,
      .data$high_rmse,
      .data$high_mae,
      .data$high_bias,
      .data$high_median_bias,
      .data$high_pred_on_obs_slope,
      .data$high_max_predicted
    ),
  n = Inf,
  width = Inf
)

cat("\nDirectional stop screen:\n")

print(
  directional_screen,
  n = Inf,
  width = Inf
)

cat("\nOutputs written to:\n")
cat(output_dir, "\n")
