source("R/functions/core.R")
source("R/functions/folds.R")
source("R/functions/metrics.R")
source("R/functions/modeling.R")
source("R/functions/predictor_sets.R")

check_packages(
  c(
    "dplyr",
    "tibble",
    "ranger"
  )
)

cfg <- read_config()
ensure_dirs(cfg)

root <- project_root()

out_dir <- file.path(
  root,
  "outputs",
  "r48_controlled_local_lithology_rf_1500"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

data_file <- file.path(
  root,
  "data",
  "processed",
  "model_table_p0_full_range_r47_hybrid_local_lithology.rds"
)

fold_file <- file.path(
  root,
  "data",
  "processed",
  "folds_long.rds"
)

module_file <- file.path(
  root,
  "outputs",
  "r47_hybrid_local_lithology",
  "r47_module_features.rds"
)

baseline_tuning_file <- file.path(
  root,
  "outputs",
  "experiment_p0_full_range_1500",
  "inner_tuning.rds"
)

baseline_prediction_file <- file.path(
  root,
  "outputs",
  "experiment_p0_full_range_1500",
  "oof_predictions.rds"
)

required_files <- c(
  data_file,
  fold_file,
  module_file,
  baseline_tuning_file,
  baseline_prediction_file
)

missing_files <- required_files[
  !file.exists(required_files)
]

if (length(missing_files) > 0L) {
  stop(
    "Missing required R48 inputs:\n",
    paste(missing_files, collapse = "\n")
  )
}

dat <- as.data.frame(
  readRDS(data_file)
)

folds_all <- as.data.frame(
  readRDS(fold_file)
)

modules <- readRDS(module_file)

baseline_tuning <- as.data.frame(
  readRDS(baseline_tuning_file)
)

baseline_predictions <- as.data.frame(
  readRDS(baseline_prediction_file)
)

outcome <- cfg$project$outcome
seed <- cfg$project$seed

# ==============================================================================
# Input and sample invariants
# ==============================================================================

if (nrow(dat) != 4485L) {
  stop(
    "R47 model table contains ",
    nrow(dat),
    " rows; expected 4485."
  )
}

if (anyDuplicated(dat$row_id)) {
  stop("R47 model table contains duplicated row_id values.")
}

if (!outcome %in% names(dat)) {
  stop("Outcome column is absent: ", outcome)
}

baseline_predictors <- grep(
  "^p0__",
  names(dat),
  value = TRUE
)

if (length(baseline_predictors) != 28L) {
  stop(
    "Expected 28 P0 predictors but found ",
    length(baseline_predictors),
    "."
  )
}

required_modules <- c(
  "M1B_LOCAL",
  "M1B_CONTRAST",
  "M1B_LOCAL_CONTRAST",
  "M1B_RADIOGENIC_COMPACT"
)

if (!all(required_modules %in% names(modules))) {
  stop(
    "R47 module object is missing: ",
    paste(
      setdiff(required_modules, names(modules)),
      collapse = ", "
    )
  )
}

feature_sets <- list(
  M0_P0_FULL =
    baseline_predictors,

  M1B_LOCAL =
    c(
      baseline_predictors,
      modules$M1B_LOCAL
    ),

  M1B_CONTRAST =
    c(
      baseline_predictors,
      modules$M1B_CONTRAST
    ),

  M1B_LOCAL_CONTRAST =
    c(
      baseline_predictors,
      modules$M1B_LOCAL_CONTRAST
    ),

  M1B_RADIOGENIC_COMPACT =
    c(
      baseline_predictors,
      modules$M1B_RADIOGENIC_COMPACT
    )
)

feature_sets <- lapply(
  feature_sets,
  unique
)

expected_feature_counts <- c(
  M0_P0_FULL = 28L,
  M1B_LOCAL = 36L,
  M1B_CONTRAST = 36L,
  M1B_LOCAL_CONTRAST = 44L,
  M1B_RADIOGENIC_COMPACT = 32L
)

if (!identical(
  unname(lengths(feature_sets)),
  unname(expected_feature_counts)
)) {
  stop(
    "Unexpected feature-set sizes:\n",
    paste(
      names(feature_sets),
      lengths(feature_sets),
      collapse = "\n"
    )
  )
}

all_model_predictors <- unique(
  unlist(
    feature_sets,
    use.names = FALSE
  )
)

missing_predictors <- setdiff(
  all_model_predictors,
  names(dat)
)

if (length(missing_predictors) > 0L) {
  stop(
    "R48 predictors absent from model table:\n",
    paste(missing_predictors, collapse = "\n")
  )
}

if (!all(
  complete.cases(
    dat[
      ,
      unique(c(outcome, all_model_predictors)),
      drop = FALSE
    ]
  )
)) {
  stop("R48 model table contains missing model values.")
}

sample_summary <- tibble::tibble(
  n = nrow(dat),
  n_ge_072 = sum(dat[[outcome]] >= 0.72),
  n_ge_075 = sum(dat[[outcome]] >= 0.75),
  n_ge_080 = sum(dat[[outcome]] >= 0.80),
  n_ge_090 = sum(dat[[outcome]] >= 0.90),
  min_sr = min(dat[[outcome]]),
  max_sr = max(dat[[outcome]])
)

if (
  sample_summary$n != 4485L ||
  sample_summary$n_ge_075 != 109L ||
  sample_summary$n_ge_080 != 20L
) {
  stop(
    "R48 sample counts do not reproduce R47 invariants."
  )
}

write_csv_safe(
  sample_summary,
  file.path(
    out_dir,
    "sample_summary.csv"
  )
)

# ==============================================================================
# Frozen 1500-km folds
# ==============================================================================

fold_set <- folds_all |>
  dplyr::filter(
    scheme == "spatial_1500km",
    row_id %in% dat$row_id
  )

if (nrow(fold_set) != 4485L) {
  stop(
    "Filtered 1500-km fold table contains ",
    nrow(fold_set),
    " rows; expected 4485."
  )
}

if (dplyr::n_distinct(fold_set$row_id) != 4485L) {
  stop("1500-km folds do not uniquely cover all 4485 sites.")
}

if (!identical(
  sort(unique(fold_set$fold)),
  1:5
)) {
  stop("Expected outer folds 1:5.")
}

fold_sizes <- fold_set |>
  dplyr::count(
    fold,
    name = "n_sites"
  ) |>
  dplyr::arrange(fold)

write_csv_safe(
  fold_sizes,
  file.path(
    out_dir,
    "outer_fold_sizes.csv"
  )
)

# ==============================================================================
# Recover and verify the original M0-selected RF parameters
# ==============================================================================

rf_grid <- expand_model_grid(
  cfg,
  "RF"
)

rf_grid$param_id <- paste0(
  "p",
  seq_len(nrow(rf_grid))
)

rf_grid <- rf_grid[
  ,
  c(
    "param_id",
    setdiff(names(rf_grid), "param_id")
  ),
  drop = FALSE
]

original_rf_predictions <- baseline_predictions |>
  dplyr::filter(
    algorithm == "RF",
    scheme == "spatial_1500km",
    predictor_set == "P0_FULL"
  )

if (nrow(original_rf_predictions) != 4485L) {
  stop(
    "Original R38 RF predictions contain ",
    nrow(original_rf_predictions),
    " rows; expected 4485."
  )
}

selected_from_oof <- original_rf_predictions |>
  dplyr::distinct(
    outer_fold,
    best_param_id
  ) |>
  dplyr::arrange(
    outer_fold
  )

if (nrow(selected_from_oof) != 5L) {
  stop(
    "Expected one original RF best_param_id per outer fold."
  )
}

guardrail_selected <- dplyr::bind_rows(
  lapply(
    1:5,
    function(current_outer_fold) {
      tune_fold <- baseline_tuning |>
        dplyr::filter(
          algorithm == "RF",
          scheme == "spatial_1500km",
          predictor_set == "P0_FULL",
          outer_fold == current_outer_fold
        )

      if (nrow(tune_fold) != 20L) {
        stop(
          "Outer fold ",
          current_outer_fold,
          " has ",
          nrow(tune_fold),
          " RF tuning rows; expected 20."
        )
      }

      selected_id <- select_params_guardrail(
        tune_fold,
        cfg$selection$rmse_tolerance_fraction
      )

      tibble::tibble(
        outer_fold = current_outer_fold,
        guardrail_param_id = selected_id
      )
    }
  )
)

frozen_parameters <- selected_from_oof |>
  dplyr::left_join(
    guardrail_selected,
    by = "outer_fold"
  ) |>
  dplyr::left_join(
    rf_grid,
    by = c(
      "best_param_id" = "param_id"
    )
  )

if (any(
  frozen_parameters$best_param_id !=
    frozen_parameters$guardrail_param_id
)) {
  stop(
    "Original OOF best_param_id does not match reconstructed ",
    "guardrail selection."
  )
}

if (anyNA(frozen_parameters$num_trees) ||
    anyNA(frozen_parameters$mtry_fraction) ||
    anyNA(frozen_parameters$min_node_size)) {
  stop("Could not map frozen RF parameter IDs to the RF grid.")
}

write_csv_safe(
  frozen_parameters,
  file.path(
    out_dir,
    "frozen_rf_parameters_by_outer_fold.csv"
  )
)

parameter_application <- dplyr::bind_rows(
  lapply(
    names(feature_sets),
    function(model_name) {
      n_predictors <- length(
        feature_sets[[model_name]]
      )

      frozen_parameters |>
        dplyr::transmute(
          predictor_set = model_name,
          outer_fold,
          best_param_id,
          num_trees,
          mtry_fraction,
          min_node_size,
          n_predictors = n_predictors,
          actual_mtry = pmax(
            1L,
            round(
              n_predictors *
                mtry_fraction
            )
          )
        )
    }
  )
)

write_csv_safe(
  parameter_application,
  file.path(
    out_dir,
    "frozen_parameter_application.csv"
  )
)

# ==============================================================================
# Feature manifest
# ==============================================================================

feature_manifest <- dplyr::bind_rows(
  lapply(
    names(feature_sets),
    function(model_name) {
      current_predictors <- feature_sets[[model_name]]

      tibble::tibble(
        predictor_set = model_name,
        feature_order = seq_along(current_predictors),
        feature = current_predictors,
        feature_role = ifelse(
          current_predictors %in% baseline_predictors,
          "P0_baseline",
          "R47_added"
        )
      )
    }
  )
)

write_csv_safe(
  feature_manifest,
  file.path(
    out_dir,
    "feature_manifest_used.csv"
  )
)

# ==============================================================================
# Controlled fixed-parameter outer CV
# ==============================================================================

all_predictions <- list()
runtime_records <- list()

for (model_name in names(feature_sets)) {
  predictors <- feature_sets[[model_name]]

  log_msg(
    "R48 starting ",
    model_name,
    " with ",
    length(predictors),
    " predictors."
  )

  model_predictions <- list()

  for (outer_fold in 1:5) {
    test_ids <- fold_set$row_id[
      fold_set$fold == outer_fold
    ]

    train <- dat[
      !dat$row_id %in% test_ids,
      ,
      drop = FALSE
    ]

    test <- dat[
      dat$row_id %in% test_ids,
      ,
      drop = FALSE
    ]

    parameter_row <- frozen_parameters |>
      dplyr::filter(
        .data$outer_fold == .env$outer_fold
      )

    if (nrow(parameter_row) != 1L) {
      stop(
        "Could not resolve frozen parameters for outer fold ",
        outer_fold,
        "."
      )
    }

    params <- list(
      num_trees =
        parameter_row$num_trees[[1L]],

      mtry_fraction =
        parameter_row$mtry_fraction[[1L]],

      min_node_size =
        parameter_row$min_node_size[[1L]]
    )

    model_seed <- seed + outer_fold

    start_time <- Sys.time()

    fit <- fit_one_model(
      train,
      predictors,
      outcome,
      "RF",
      params,
      weights = NULL,
      threads = cfg$project$threads,
      seed = model_seed
    )

    predicted <- predict(
      fit,
      test
    )

    end_time <- Sys.time()

    model_predictions[[outer_fold]] <- test |>
      dplyr::transmute(
        row_id,
        observed = .data[[outcome]],
        predicted = as.numeric(predicted),
        outer_fold = outer_fold,
        algorithm = "RF",
        predictor_set = model_name,
        best_param_id =
          parameter_row$best_param_id[[1L]],
        num_trees =
          parameter_row$num_trees[[1L]],
        mtry_fraction =
          parameter_row$mtry_fraction[[1L]],
        min_node_size =
          parameter_row$min_node_size[[1L]],
        n_predictors = length(predictors),
        actual_mtry = max(
          1L,
          round(
            length(predictors) *
              parameter_row$mtry_fraction[[1L]]
          )
        ),
        model_seed = model_seed
      )

    runtime_records[[length(runtime_records) + 1L]] <-
      tibble::tibble(
        predictor_set = model_name,
        outer_fold = outer_fold,
        n_train = nrow(train),
        n_test = nrow(test),
        n_predictors = length(predictors),
        best_param_id =
          parameter_row$best_param_id[[1L]],
        elapsed_seconds = as.numeric(
          difftime(
            end_time,
            start_time,
            units = "secs"
          )
        )
      )

    log_msg(
      "R48 completed ",
      model_name,
      " outer fold ",
      outer_fold,
      "."
    )
  }

  current_model_predictions <- dplyr::bind_rows(
    model_predictions
  )

  if (nrow(current_model_predictions) != 4485L) {
    stop(
      model_name,
      " produced ",
      nrow(current_model_predictions),
      " OOF predictions; expected 4485."
    )
  }

  # --------------------------------------------------------------------------
  # Exact M0 reproduction guardrail
  # --------------------------------------------------------------------------

  if (model_name == "M0_P0_FULL") {
    reproduction <- current_model_predictions |>
      dplyr::select(
        row_id,
        outer_fold,
        observed,
        predicted,
        best_param_id
      ) |>
      dplyr::rename(
        observed_r48 = observed,
        predicted_r48 = predicted,
        best_param_id_r48 = best_param_id
      ) |>
      dplyr::inner_join(
        original_rf_predictions |>
          dplyr::select(
            row_id,
            outer_fold,
            observed,
            predicted,
            best_param_id
          ) |>
          dplyr::rename(
            observed_r38 = observed,
            predicted_r38 = predicted,
            best_param_id_r38 = best_param_id
          ),
        by = c(
          "row_id",
          "outer_fold"
        )
      ) |>
      dplyr::mutate(
        observed_abs_difference =
          abs(observed_r48 - observed_r38),

        prediction_abs_difference =
          abs(predicted_r48 - predicted_r38),

        same_parameter =
          best_param_id_r48 ==
          best_param_id_r38
      )

    if (nrow(reproduction) != 4485L) {
      stop(
        "M0 reproduction joined ",
        nrow(reproduction),
        " rows; expected 4485."
      )
    }

    reproduction_summary <- reproduction |>
      dplyr::summarise(
        n = dplyr::n(),
        max_observed_abs_difference =
          max(observed_abs_difference),
        max_prediction_abs_difference =
          max(prediction_abs_difference),
        mean_prediction_abs_difference =
          mean(prediction_abs_difference),
        all_parameters_identical =
          all(same_parameter)
      )

    write_csv_safe(
      reproduction_summary,
      file.path(
        out_dir,
        "baseline_reproduction_audit.csv"
      )
    )

    write_atomic_rds(
      reproduction,
      file.path(
        out_dir,
        "baseline_reproduction_details.rds"
      )
    )

    if (
      reproduction_summary$
        max_observed_abs_difference > 1e-12
    ) {
      stop("M0 observed values do not reproduce R38.")
    }

    if (
      reproduction_summary$
        max_prediction_abs_difference > 1e-10
    ) {
      stop(
        "M0 predictions do not reproduce R38 within tolerance. ",
        "Maximum absolute difference = ",
        reproduction_summary$
          max_prediction_abs_difference
      )
    }

    if (!reproduction_summary$all_parameters_identical) {
      stop("M0 frozen parameter IDs do not reproduce R38.")
    }

    log_msg(
      "M0 reproduction guardrail passed; max prediction difference = ",
      reproduction_summary$
        max_prediction_abs_difference
    )
  }

  all_predictions[[model_name]] <-
    current_model_predictions

  write_atomic_rds(
    dplyr::bind_rows(all_predictions),
    file.path(
      out_dir,
      "oof_predictions_partial.rds"
    )
  )
}

predictions <- dplyr::bind_rows(
  all_predictions
)

runtime <- dplyr::bind_rows(
  runtime_records
)

if (nrow(predictions) != 4485L * 5L) {
  stop(
    "Expected 22425 total OOF rows but obtained ",
    nrow(predictions),
    "."
  )
}

write_atomic_rds(
  predictions,
  file.path(
    out_dir,
    "oof_predictions.rds"
  )
)

write_csv_safe(
  runtime,
  file.path(
    out_dir,
    "model_runtime.csv"
  )
)

# ==============================================================================
# Existing R38 metrics
# ==============================================================================

metrics_by_outer_fold <- predictions |>
  dplyr::group_by(
    predictor_set,
    algorithm,
    outer_fold
  ) |>
  dplyr::group_modify(
    ~metric_row(
      .x$observed,
      .x$predicted,
      cfg$selection$high_threshold
    )
  ) |>
  dplyr::ungroup() |>
  dplyr::mutate(
    scheme = "spatial_1500km",
    .before = 1L
  )

write_csv_safe(
  metrics_by_outer_fold,
  file.path(
    out_dir,
    "metrics_by_outer_fold.csv"
  )
)

metric_columns <- c(
  "rmse",
  "mae",
  "r2_sse",
  "bias",
  "top10_bias",
  "top05_bias",
  "high_rmse",
  "high_bias",
  "predicted_range_ratio",
  "calibration_slope",
  "max_predicted"
)

metrics_summary_mean_fold <- metrics_by_outer_fold |>
  dplyr::group_by(
    scheme,
    predictor_set,
    algorithm
  ) |>
  dplyr::summarise(
    dplyr::across(
      dplyr::all_of(metric_columns),
      ~mean(.x, na.rm = TRUE)
    ),
    .groups = "drop"
  )

write_csv_safe(
  metrics_summary_mean_fold,
  file.path(
    out_dir,
    "metrics_summary_mean_fold.csv"
  )
)

metrics_pooled_oof <- predictions |>
  dplyr::group_by(
    predictor_set,
    algorithm
  ) |>
  dplyr::group_modify(
    ~metric_row(
      .x$observed,
      .x$predicted,
      cfg$selection$high_threshold
    )
  ) |>
  dplyr::ungroup() |>
  dplyr::mutate(
    scheme = "spatial_1500km",
    .before = 1L
  )

write_csv_safe(
  metrics_pooled_oof,
  file.path(
    out_dir,
    "metrics_pooled_oof.csv"
  )
)

# ==============================================================================
# Explicit upper-tail metrics
# ==============================================================================

safe_slope <- function(y, x) {
  valid <- is.finite(y) & is.finite(x)

  y <- y[valid]
  x <- x[valid]

  if (
    length(y) < 3L ||
    stats::sd(x) == 0
  ) {
    return(NA_real_)
  }

  unname(
    stats::coef(
      stats::lm(y ~ x)
    )[[2L]]
  )
}

tail_metric_row <- function(
  observed,
  predicted,
  threshold
) {
  valid <- is.finite(observed) &
    is.finite(predicted) &
    observed >= threshold

  obs <- observed[valid]
  pred <- predicted[valid]

  n_tail <- length(obs)

  if (n_tail == 0L) {
    return(
      tibble::tibble(
        threshold = threshold,
        n = 0L,
        rmse = NA_real_,
        mae = NA_real_,
        bias = NA_real_,
        median_bias = NA_real_,
        observed_mean = NA_real_,
        predicted_mean = NA_real_,
        observed_max = NA_real_,
        predicted_max = NA_real_,
        max_gap = NA_real_,
        underprediction_fraction = NA_real_,
        predicted_on_observed_slope = NA_real_,
        observed_on_predicted_slope = NA_real_
      )
    )
  }

  residual <- pred - obs

  tibble::tibble(
    threshold = threshold,
    n = n_tail,

    rmse = sqrt(
      mean(
        residual^2
      )
    ),

    mae = mean(
      abs(residual)
    ),

    bias = mean(
      residual
    ),

    median_bias = stats::median(
      residual
    ),

    observed_mean = mean(obs),
    predicted_mean = mean(pred),
    observed_max = max(obs),
    predicted_max = max(pred),

    max_gap =
      max(pred) -
      max(obs),

    underprediction_fraction =
      mean(pred < obs),

    predicted_on_observed_slope =
      safe_slope(
        pred,
        obs
      ),

    observed_on_predicted_slope =
      safe_slope(
        obs,
        pred
      )
  )
}

tail_thresholds <- c(
  0.72,
  0.75,
  0.80
)

tail_metrics_by_outer_fold <- dplyr::bind_rows(
  lapply(
    tail_thresholds,
    function(current_threshold) {
      predictions |>
        dplyr::group_by(
          predictor_set,
          algorithm,
          outer_fold
        ) |>
        dplyr::group_modify(
          ~tail_metric_row(
            .x$observed,
            .x$predicted,
            current_threshold
          )
        ) |>
        dplyr::ungroup()
    }
  )
) |>
  dplyr::mutate(
    scheme = "spatial_1500km",
    .before = 1L
  )

write_csv_safe(
  tail_metrics_by_outer_fold,
  file.path(
    out_dir,
    "tail_metrics_by_outer_fold.csv"
  )
)

tail_metrics_pooled <- dplyr::bind_rows(
  lapply(
    tail_thresholds,
    function(current_threshold) {
      predictions |>
        dplyr::group_by(
          predictor_set,
          algorithm
        ) |>
        dplyr::group_modify(
          ~tail_metric_row(
            .x$observed,
            .x$predicted,
            current_threshold
          )
        ) |>
        dplyr::ungroup()
    }
  )
) |>
  dplyr::mutate(
    scheme = "spatial_1500km",
    .before = 1L
  )

write_csv_safe(
  tail_metrics_pooled,
  file.path(
    out_dir,
    "tail_metrics_pooled.csv"
  )
)

# ==============================================================================
# Controlled deltas against M0
# ==============================================================================

m0_fold_metrics <- metrics_by_outer_fold |>
  dplyr::filter(
    predictor_set == "M0_P0_FULL"
  ) |>
  dplyr::select(
    outer_fold,
    m0_rmse = rmse,
    m0_mae = mae,
    m0_r2_sse = r2_sse,
    m0_bias = bias,
    m0_high_rmse = high_rmse,
    m0_high_bias = high_bias,
    m0_range_ratio = predicted_range_ratio,
    m0_max_predicted = max_predicted
  )

delta_vs_m0_by_fold <- metrics_by_outer_fold |>
  dplyr::filter(
    predictor_set != "M0_P0_FULL"
  ) |>
  dplyr::left_join(
    m0_fold_metrics,
    by = "outer_fold"
  ) |>
  dplyr::mutate(
    rmse_improvement =
      m0_rmse - rmse,

    mae_improvement =
      m0_mae - mae,

    r2_change =
      r2_sse - m0_r2_sse,

    absolute_bias_improvement =
      abs(m0_bias) - abs(bias),

    high_rmse_improvement =
      m0_high_rmse - high_rmse,

    absolute_high_bias_improvement =
      abs(m0_high_bias) - abs(high_bias),

    range_ratio_change =
      predicted_range_ratio - m0_range_ratio,

    max_predicted_change =
      max_predicted - m0_max_predicted
  )

write_csv_safe(
  delta_vs_m0_by_fold,
  file.path(
    out_dir,
    "delta_vs_m0_by_fold.csv"
  )
)

delta_vs_m0_summary <- delta_vs_m0_by_fold |>
  dplyr::group_by(
    predictor_set
  ) |>
  dplyr::summarise(
    mean_rmse_improvement =
      mean(rmse_improvement),

    n_folds_rmse_better =
      sum(rmse_improvement > 0),

    mean_mae_improvement =
      mean(mae_improvement),

    n_folds_mae_better =
      sum(mae_improvement > 0),

    mean_r2_change =
      mean(r2_change),

    mean_absolute_bias_improvement =
      mean(absolute_bias_improvement),

    mean_high_rmse_improvement =
      mean(high_rmse_improvement),

    n_folds_high_rmse_better =
      sum(high_rmse_improvement > 0),

    mean_absolute_high_bias_improvement =
      mean(absolute_high_bias_improvement),

    mean_range_ratio_change =
      mean(range_ratio_change),

    mean_max_predicted_change =
      mean(max_predicted_change),

    worst_fold_rmse_improvement =
      min(rmse_improvement),

    .groups = "drop"
  )

write_csv_safe(
  delta_vs_m0_summary,
  file.path(
    out_dir,
    "delta_vs_m0_summary.csv"
  )
)

m0_tail_fold <- tail_metrics_by_outer_fold |>
  dplyr::filter(
    predictor_set == "M0_P0_FULL"
  ) |>
  dplyr::select(
    outer_fold,
    threshold,
    m0_tail_rmse = rmse,
    m0_tail_mae = mae,
    m0_tail_bias = bias,
    m0_tail_median_bias = median_bias,
    m0_tail_predicted_max = predicted_max,
    m0_underprediction_fraction =
      underprediction_fraction
  )

tail_delta_vs_m0_by_fold <- tail_metrics_by_outer_fold |>
  dplyr::filter(
    predictor_set != "M0_P0_FULL"
  ) |>
  dplyr::left_join(
    m0_tail_fold,
    by = c(
      "outer_fold",
      "threshold"
    )
  ) |>
  dplyr::mutate(
    tail_rmse_improvement =
      m0_tail_rmse - rmse,

    tail_mae_improvement =
      m0_tail_mae - mae,

    tail_absolute_bias_improvement =
      abs(m0_tail_bias) - abs(bias),

    tail_absolute_median_bias_improvement =
      abs(m0_tail_median_bias) - abs(median_bias),

    tail_predicted_max_change =
      predicted_max - m0_tail_predicted_max,

    underprediction_fraction_change =
      underprediction_fraction -
      m0_underprediction_fraction
  )

write_csv_safe(
  tail_delta_vs_m0_by_fold,
  file.path(
    out_dir,
    "tail_delta_vs_m0_by_fold.csv"
  )
)

tail_delta_vs_m0_summary <- tail_delta_vs_m0_by_fold |>
  dplyr::group_by(
    predictor_set,
    threshold
  ) |>
  dplyr::summarise(
    mean_tail_rmse_improvement =
      mean(tail_rmse_improvement, na.rm = TRUE),

    n_folds_tail_rmse_better =
      sum(tail_rmse_improvement > 0, na.rm = TRUE),

    mean_tail_mae_improvement =
      mean(tail_mae_improvement, na.rm = TRUE),

    mean_tail_absolute_bias_improvement =
      mean(
        tail_absolute_bias_improvement,
        na.rm = TRUE
      ),

    mean_tail_predicted_max_change =
      mean(
        tail_predicted_max_change,
        na.rm = TRUE
      ),

    mean_underprediction_fraction_change =
      mean(
        underprediction_fraction_change,
        na.rm = TRUE
      ),

    .groups = "drop"
  )

write_csv_safe(
  tail_delta_vs_m0_summary,
  file.path(
    out_dir,
    "tail_delta_vs_m0_summary.csv"
  )
)

# ==============================================================================
# Run summary and checksums
# ==============================================================================

reproduction_summary <- utils::read.csv(
  file.path(
    out_dir,
    "baseline_reproduction_audit.csv"
  )
)

parameter_text <- paste(
  paste0(
    "fold ",
    frozen_parameters$outer_fold,
    "=",
    frozen_parameters$best_param_id
  ),
  collapse = ", "
)

summary_lines <- c(
  "R48 CONTROLLED LOCAL-LITHOLOGY RF EXPERIMENT",
  "============================================",
  "",
  paste0("Data input: ", data_file),
  paste0("Sample n: ", nrow(dat)),
  paste0("P0 predictors: ", length(baseline_predictors)),
  paste0("Sr >= 0.75: ", sample_summary$n_ge_075),
  paste0("Sr >= 0.80: ", sample_summary$n_ge_080),
  "",
  "Outer CV: frozen spatial_1500km folds 1:5",
  "Algorithm: RF only",
  "Inner tuning: not rerun",
  "Parameter control: original M0-selected mtry_fraction frozen by outer fold",
  paste0("Frozen parameter IDs: ", parameter_text),
  paste0("RF trees: ", paste(unique(frozen_parameters$num_trees), collapse = ",")),
  paste0("Seed base: ", seed),
  "",
  paste0(
    "M0 reproduction max prediction difference: ",
    format(
      reproduction_summary$max_prediction_abs_difference,
      scientific = TRUE
    )
  ),
  "",
  paste0(
    "Models: ",
    paste(names(feature_sets), collapse = ", ")
  ),
  paste0(
    "Feature counts: ",
    paste(
      paste0(
        names(feature_sets),
        "=",
        lengths(feature_sets)
      ),
      collapse = ", "
    )
  ),
  "",
  "STATUS: ALL R48 INVARIANTS PASSED",
  "",
  "R session:",
  paste(
    capture.output(sessionInfo()),
    collapse = "\n"
  )
)

writeLines(
  summary_lines,
  file.path(
    out_dir,
    "run_summary.txt"
  )
)

checksum_files <- c(
  "sample_summary.csv",
  "outer_fold_sizes.csv",
  "frozen_rf_parameters_by_outer_fold.csv",
  "frozen_parameter_application.csv",
  "feature_manifest_used.csv",
  "baseline_reproduction_audit.csv",
  "baseline_reproduction_details.rds",
  "oof_predictions.rds",
  "model_runtime.csv",
  "metrics_by_outer_fold.csv",
  "metrics_summary_mean_fold.csv",
  "metrics_pooled_oof.csv",
  "tail_metrics_by_outer_fold.csv",
  "tail_metrics_pooled.csv",
  "delta_vs_m0_by_fold.csv",
  "delta_vs_m0_summary.csv",
  "tail_delta_vs_m0_by_fold.csv",
  "tail_delta_vs_m0_summary.csv",
  "run_summary.txt"
)

checksum_paths <- file.path(
  out_dir,
  checksum_files
)

checksum_table <- tibble::tibble(
  file = checksum_files,
  md5 = unname(
    tools::md5sum(
      checksum_paths
    )
  )
)

write_csv_safe(
  checksum_table,
  file.path(
    out_dir,
    "output_checksums.csv"
  )
)

log_msg(
  "R48 controlled local-lithology RF experiment complete."
)
