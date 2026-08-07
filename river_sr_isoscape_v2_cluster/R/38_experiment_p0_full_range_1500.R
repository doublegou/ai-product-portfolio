source("R/functions/core.R")
source("R/functions/folds.R")
source("R/functions/metrics.R")
source("R/functions/modeling.R")
source("R/functions/predictor_sets.R")

check_packages(
  c(
    "sf",
    "dplyr",
    "ranger",
    "Cubist"
  )
)

cfg <- read_config()
ensure_dirs(cfg)

dat <- readRDS(
  file.path(
    project_root(),
    "data/processed/model_table_p0_full_range.rds"
  )
)

folds_all <- readRDS(
  file.path(
    project_root(),
    "data/processed/folds_long.rds"
  )
)

fold <- folds_all |>
  dplyr::filter(
    scheme == "spatial_1500km"
  )

predictors <- grep(
  "^p0__",
  names(dat),
  value = TRUE
)

stopifnot(
  length(predictors) == 28L
)

complete_index <- stats::complete.cases(
  dat[, predictors, drop = FALSE]
)

dat_set <- dat[
  complete_index,
  ,
  drop = FALSE
]

fold_set <- fold |>
  dplyr::filter(
    row_id %in% dat_set$row_id
  )

if (nrow(dat_set) != 4485L) {
  stop(
    "Expected 4485 complete P0 rows; got ",
    nrow(dat_set)
  )
}

if (
  dplyr::n_distinct(
    fold_set$row_id
  ) != 4485L
) {
  stop(
    "Fold table does not cover all 4485 sites."
  )
}

if (
  !identical(
    sort(unique(fold_set$fold)),
    1:5
  )
) {
  stop(
    "Expected outer folds 1:5."
  )
}

out_dir <- file.path(
  project_root(),
  "outputs/experiment_p0_full_range_1500"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

sample_summary <- dat_set |>
  dplyr::summarise(
    n = dplyr::n(),
    n_ge_0720 =
      sum(sr87_sr86 >= 0.720),
    n_ge_0750 =
      sum(sr87_sr86 >= 0.750),
    n_ge_0800 =
      sum(sr87_sr86 >= 0.800),
    n_ge_0900 =
      sum(sr87_sr86 >= 0.900),
    max_sr =
      max(sr87_sr86)
  )

write_csv_safe(
  sample_summary,
  file.path(
    out_dir,
    "sample_summary.csv"
  )
)

log_msg(
  "P0-F spatial_1500km: ",
  nrow(dat_set),
  " complete rows; ",
  length(predictors),
  " predictors."
)

algorithms <- c(
  "RF",
  "Cubist"
)

all_pred <- list()
all_tune <- list()
all_metrics <- list()

for (alg in algorithms) {

  log_msg(
    "Starting P0-F / spatial_1500km / ",
    alg
  )

  res <- run_nested_cv(
    dat_set,
    fold_set,
    predictors,
    cfg$project$outcome,
    alg,
    cfg,
    seed = cfg$project$seed
  )

  pred <- res$predictions |>
    dplyr::mutate(
      scheme = "spatial_1500km",
      predictor_set = "P0_FULL"
    )

  met <- pred |>
    dplyr::group_by(
      scheme,
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
    dplyr::ungroup()

  all_pred[[length(all_pred) + 1L]] <-
    pred

  all_tune[[length(all_tune) + 1L]] <-
    res$tuning |>
    dplyr::mutate(
      scheme = "spatial_1500km",
      predictor_set = "P0_FULL"
    )

  all_metrics[[length(all_metrics) + 1L]] <-
    met

  write_atomic_rds(
    dplyr::bind_rows(all_pred),
    file.path(
      out_dir,
      "oof_predictions_partial.rds"
    )
  )
}

pred <- dplyr::bind_rows(
  all_pred
)

tune <- dplyr::bind_rows(
  all_tune
)

metrics <- dplyr::bind_rows(
  all_metrics
)

write_atomic_rds(
  pred,
  file.path(
    out_dir,
    "oof_predictions.rds"
  )
)

write_atomic_rds(
  tune,
  file.path(
    out_dir,
    "inner_tuning.rds"
  )
)

write_csv_safe(
  metrics,
  file.path(
    out_dir,
    "metrics_by_outer_fold.csv"
  )
)

summary <- metrics |>
  dplyr::group_by(
    scheme,
    predictor_set,
    algorithm
  ) |>
  dplyr::summarise(
    dplyr::across(
      c(
        rmse,
        mae,
        r2_sse,
        bias,
        top10_bias,
        top05_bias,
        high_rmse,
        high_bias,
        predicted_range_ratio,
        calibration_slope,
        max_predicted
      ),
      ~mean(.x, na.rm = TRUE)
    ),
    .groups = "drop"
  )

write_csv_safe(
  summary,
  file.path(
    out_dir,
    "metrics_summary.csv"
  )
)

log_msg(
  "P0-F spatial_1500km complete."
)
