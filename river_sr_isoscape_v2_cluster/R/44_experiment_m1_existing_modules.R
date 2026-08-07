source("R/functions/core.R")
source("R/functions/folds.R")
source("R/functions/metrics.R")
source("R/functions/modeling.R")

check_packages(
  c(
    "sf",
    "dplyr",
    "ranger",
    "readr"
  )
)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

cfg <- read_config()
ensure_dirs(cfg)

# ============================================================
# 0. Paths
# ============================================================

model_file <-
  file.path(
    project_root(),
    "data/processed/model_table_m1_existing_candidates.rds"
  )

fold_file <-
  file.path(
    project_root(),
    "data/processed/folds_long.rds"
  )

out_dir <-
  file.path(
    project_root(),
    "outputs/experiment_m1_existing_modules_1500"
  )

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

stop_missing(
  model_file,
  "Run R/43_build_existing_m1_candidates.R first."
)

stop_missing(
  fold_file,
  "Missing folds_long.rds."
)

dat <- readRDS(model_file)

folds <- readRDS(fold_file) |>
  filter(
    scheme == "spatial_1500km"
  )

# ============================================================
# 1. Baseline P0
# ============================================================

p0_vars <- grep(
  "^p0__",
  names(dat),
  value = TRUE
)

if (length(p0_vars) != 28L) {
  stop(
    "Expected 28 P0 variables; found ",
    length(p0_vars)
  )
}

# ============================================================
# 2. Mechanistic modules
# ============================================================

# M1-A1
# Existing lithology fractions are already in P0.
# Entropy encodes their compositional heterogeneity.

lith_entropy <- c(
  "m1a__lith_entropy_norm"
)

# M1-A2
# Upstream geological age distribution.
# "oldest" is currently used as a low-cost upper-tail proxy.
# Later this can be replaced/tested against P90 age.

up_age_dist <- c(
  "up_geo_age_mean_ma",
  "up_geo_age_sd_ma",
  "up_geo_age_max_oldest_ma"
)

# M1-B
# Local versus whole-upstream geological contrast.
#
# Signed mean contrast:
#   whether local geology is younger/older than upstream background.
#
# Signed SD contrast:
#   whether local geology is more/less heterogeneous.
#
# Max absolute contrast:
#   whether the oldest upstream source is absent locally.

age_contrast <- c(
  "m1b__age_mean_local_minus_up",
  "m1b__age_sd_local_minus_up",
  "m1a__age_max_abs_contrast"
)

predictor_sets <- list(

  M0_P0_FULL =
    p0_vars,

  M1A_LITH_ENTROPY =
    unique(
      c(
        p0_vars,
        lith_entropy
      )
    ),

  M1A_UP_AGE_DIST =
    unique(
      c(
        p0_vars,
        up_age_dist
      )
    ),

  M1B_AGE_CONTRAST =
    unique(
      c(
        p0_vars,
        age_contrast
      )
    ),

  M1_EXISTING_COMBINED =
    unique(
      c(
        p0_vars,
        lith_entropy,
        up_age_dist,
        age_contrast
      )
    )
)

# ============================================================
# 3. Validate predictor availability
# ============================================================

all_needed <- unique(
  unlist(
    predictor_sets,
    use.names = FALSE
  )
)

missing_predictors <- setdiff(
  all_needed,
  names(dat)
)

if (length(missing_predictors) > 0L) {

  stop(
    "Missing predictors: ",
    paste(
      missing_predictors,
      collapse = ", "
    )
  )
}

# ============================================================
# 4. Force a common analysis sample
# ============================================================

response <- cfg$project$outcome

if (!response %in% names(dat)) {
  stop(
    "Outcome column missing: ",
    response
  )
}

common_index <-
  complete.cases(
    dat[
      ,
      all_needed,
      drop = FALSE
    ]
  ) &
  is.finite(
    dat[[response]]
  )

dat_common <- dat[
  common_index,
  ,
  drop = FALSE
]

fold_common <- folds |>
  filter(
    row_id %in% dat_common$row_id
  )

cat(
  "\n===== COMMON SAMPLE =====\n"
)

cat(
  "n = ",
  nrow(dat_common),
  "\n",
  sep = ""
)

cat(
  "n >= 0.720 = ",
  sum(
    dat_common[[response]] >= 0.720
  ),
  "\n",
  sep = ""
)

cat(
  "n >= 0.750 = ",
  sum(
    dat_common[[response]] >= 0.750
  ),
  "\n",
  sep = ""
)

cat(
  "n >= 0.800 = ",
  sum(
    dat_common[[response]] >= 0.800
  ),
  "\n",
  sep = ""
)

cat(
  "max Sr = ",
  max(
    dat_common[[response]]
  ),
  "\n",
  sep = ""
)

if (nrow(dat_common) != 4485L) {

  stop(
    "Expected common sample n=4485; got ",
    nrow(dat_common)
  )
}

if (
  sum(
    dat_common[[response]] >= 0.800
  ) != 20L
) {

  stop(
    "Expected 20 observations >= 0.800."
  )
}

# Each common row should have one spatial_1500km fold assignment.

fold_check <- fold_common |>
  count(
    row_id
  )

if (
  any(
    fold_check$n != 1L
  )
) {
  stop(
    "Some row_id values do not have exactly one 1500-km fold assignment."
  )
}

outer_folds <- sort(
  unique(
    fold_common$fold
  )
)

if (
  !identical(
    outer_folds,
    1:5
  )
) {

  stop(
    "Expected outer folds 1:5; found ",
    paste(
      outer_folds,
      collapse = ","
    )
  )
}

# ============================================================
# 5. Predictor-set manifest
# ============================================================

manifest <- bind_rows(
  lapply(
    names(predictor_sets),
    function(set_name) {

      data.frame(
        predictor_set =
          set_name,

        predictor =
          predictor_sets[[set_name]],

        stringsAsFactors =
          FALSE
      )
    }
  )
)

write_csv(
  manifest,
  file.path(
    out_dir,
    "predictor_set_manifest.csv"
  )
)

set_summary <- data.frame(
  predictor_set =
    names(predictor_sets),

  predictor_n =
    vapply(
      predictor_sets,
      length,
      integer(1)
    ),

  stringsAsFactors =
    FALSE
)

cat(
  "\n===== PREDICTOR SETS =====\n"
)

print(
  set_summary,
  row.names = FALSE
)

write_csv(
  set_summary,
  file.path(
    out_dir,
    "predictor_set_summary.csv"
  )
)

# ============================================================
# 6. Run nested spatial CV
# ============================================================

all_pred <- list()
all_tune <- list()
all_metrics <- list()

alg <- "RF"

for (
  set_name in names(predictor_sets)
) {

  predictors <-
    predictor_sets[[set_name]]

  cat(
    "\n========================================\n"
  )

  cat(
    "RUNNING: ",
    set_name,
    "\n",
    sep = ""
  )

  cat(
    "Predictor n: ",
    length(predictors),
    "\n",
    sep = ""
  )

  cat(
    "========================================\n"
  )

  res <- run_nested_cv(
    dat_common,
    fold_common,
    predictors,
    response,
    alg,
    cfg,
    seed = cfg$project$seed
  )

  pred <- res$predictions |>
    mutate(
      scheme =
        "spatial_1500km",

      predictor_set =
        set_name,

      predictor_n =
        length(predictors)
    )

  met <- pred |>
    group_by(
      scheme,
      predictor_set,
      algorithm,
      outer_fold
    ) |>
    group_modify(
      ~metric_row(
        .x$observed,
        .x$predicted,
        cfg$selection$high_threshold
      )
    ) |>
    ungroup() |>
    mutate(
      predictor_n =
        length(predictors)
    )

  tuning <- res$tuning |>
    mutate(
      scheme =
        "spatial_1500km",

      predictor_set =
        set_name,

      predictor_n =
        length(predictors)
    )

  all_pred[[
    length(all_pred) + 1L
  ]] <- pred

  all_tune[[
    length(all_tune) + 1L
  ]] <- tuning

  all_metrics[[
    length(all_metrics) + 1L
  ]] <- met

  # Save progress after every predictor set.

  write_atomic_rds(
    bind_rows(all_pred),
    file.path(
      out_dir,
      "oof_predictions_partial.rds"
    )
  )

  write_csv_safe(
    bind_rows(all_metrics),
    file.path(
      out_dir,
      "metrics_by_outer_fold_partial.csv"
    )
  )

  cat(
    "Finished: ",
    set_name,
    "\n",
    sep = ""
  )
}

# ============================================================
# 7. Combine outputs
# ============================================================

predictions <- bind_rows(
  all_pred
)

tuning <- bind_rows(
  all_tune
)

metrics_by_fold <- bind_rows(
  all_metrics
)

write_atomic_rds(
  predictions,
  file.path(
    out_dir,
    "oof_predictions.rds"
  )
)

write_csv_safe(
  predictions,
  file.path(
    out_dir,
    "oof_predictions.csv"
  )
)

write_atomic_rds(
  tuning,
  file.path(
    out_dir,
    "inner_tuning.rds"
  )
)

write_csv_safe(
  metrics_by_fold,
  file.path(
    out_dir,
    "metrics_by_outer_fold.csv"
  )
)

# ============================================================
# 8. Mean metrics across outer folds
# ============================================================

metric_columns <- intersect(
  c(
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
  ),
  names(metrics_by_fold)
)

mean_metrics <- metrics_by_fold |>
  group_by(
    scheme,
    predictor_set,
    algorithm,
    predictor_n
  ) |>
  summarise(
    across(
      all_of(metric_columns),
      ~mean(
        .x,
        na.rm = TRUE
      )
    ),
    .groups = "drop"
  )

write_csv(
  mean_metrics,
  file.path(
    out_dir,
    "mean_metrics_across_outer_folds.csv"
  )
)

# ============================================================
# 9. Pooled OOF threshold metrics
# ============================================================

thresholds <- c(
  0.720,
  0.730,
  0.740,
  0.750,
  0.775,
  0.800,
  0.900
)

tail_results <- list()
counter <- 1L

for (
  set_name in unique(
    predictions$predictor_set
  )
) {

  d <- predictions |>
    filter(
      predictor_set ==
        set_name
    )

  for (
    thr in thresholds
  ) {

    z <- d |>
      filter(
        observed >= thr
      )

    if (
      nrow(z) == 0L
    ) {
      next
    }

    tail_results[[
      counter
    ]] <- data.frame(

      predictor_set =
        set_name,

      threshold =
        thr,

      n =
        nrow(z),

      observed_mean =
        mean(
          z$observed
        ),

      predicted_mean =
        mean(
          z$predicted
        ),

      rmse =
        sqrt(
          mean(
            (
              z$predicted -
              z$observed
            )^2
          )
        ),

      mae =
        mean(
          abs(
            z$predicted -
            z$observed
          )
        ),

      bias =
        mean(
          z$predicted -
          z$observed
        ),

      median_bias =
        median(
          z$predicted -
          z$observed
        ),

      observed_max =
        max(
          z$observed
        ),

      predicted_max =
        max(
          z$predicted
        )
    )

    counter <-
      counter + 1L
  }
}

tail_metrics <- bind_rows(
  tail_results
)

write_csv(
  tail_metrics,
  file.path(
    out_dir,
    "cumulative_tail_metrics.csv"
  )
)

# ============================================================
# 10. Fixed Sr-bin profile
# ============================================================

breaks <- c(
  0.700,
  0.710,
  0.720,
  0.730,
  0.740,
  0.750,
  0.775,
  0.800,
  0.900,
  Inf
)

labels <- c(
  "0.700-0.710",
  "0.710-0.720",
  "0.720-0.730",
  "0.730-0.740",
  "0.740-0.750",
  "0.750-0.775",
  "0.775-0.800",
  "0.800-0.900",
  ">=0.900"
)

bin_metrics <- predictions |>
  mutate(
    sr_bin =
      cut(
        observed,
        breaks = breaks,
        labels = labels,
        right = FALSE,
        include.lowest = TRUE
      )
  ) |>
  filter(
    !is.na(sr_bin)
  ) |>
  group_by(
    predictor_set,
    algorithm,
    sr_bin
  ) |>
  summarise(

    n =
      n(),

    observed_mean =
      mean(
        observed
      ),

    predicted_mean =
      mean(
        predicted
      ),

    rmse =
      sqrt(
        mean(
          (
            predicted -
            observed
          )^2
        )
      ),

    mae =
      mean(
        abs(
          predicted -
            observed
        )
      ),

    bias =
      mean(
        predicted -
          observed
      ),

    median_bias =
      median(
        predicted -
          observed
      ),

    .groups = "drop"
  )

write_csv(
  bin_metrics,
  file.path(
    out_dir,
    "sr_bin_metrics.csv"
  )
)

# ============================================================
# 11. Paired comparison with M0 by outer fold
# ============================================================

m0_metrics <- metrics_by_fold |>
  filter(
    predictor_set ==
      "M0_P0_FULL"
  ) |>
  select(
    outer_fold,
    all_of(
      metric_columns
    )
  )

names(m0_metrics)[
  names(m0_metrics) !=
    "outer_fold"
] <- paste0(
  names(m0_metrics)[
    names(m0_metrics) !=
      "outer_fold"
  ],
  "_m0"
)

comparison <- metrics_by_fold |>
  filter(
    predictor_set !=
      "M0_P0_FULL"
  ) |>
  left_join(
    m0_metrics,
    by = "outer_fold"
  )

for (
  metric in metric_columns
) {

  m0_name <-
    paste0(
      metric,
      "_m0"
    )

  delta_name <-
    paste0(
      "delta_",
      metric
    )

  comparison[[
    delta_name
  ]] <-
    comparison[[
      metric
    ]] -
    comparison[[
      m0_name
    ]]
}

write_csv(
  comparison,
  file.path(
    out_dir,
    "comparison_vs_m0_by_outer_fold.csv"
  )
)

# ============================================================
# 12. Simple fold-stability screen
#
# Negative delta RMSE = improvement.
# Negative delta MAE  = improvement.
#
# For high_bias, because baseline is negative,
# we evaluate improvement using absolute bias.
# ============================================================

comparison <- comparison |>
  mutate(
    rmse_improved =
      rmse <
      rmse_m0,

    mae_improved =
      mae <
      mae_m0,

    high_rmse_improved =
      if (
        "high_rmse" %in%
        names(comparison)
      )
        high_rmse <
        high_rmse_m0
      else
        NA,

    high_bias_abs_improved =
      if (
        "high_bias" %in%
        names(comparison)
      )
        abs(high_bias) <
        abs(high_bias_m0)
      else
        NA
  )

stability_summary <- comparison |>
  group_by(
    predictor_set
  ) |>
  summarise(

    folds_rmse_improved =
      sum(
        rmse_improved,
        na.rm = TRUE
      ),

    folds_mae_improved =
      sum(
        mae_improved,
        na.rm = TRUE
      ),

    folds_high_rmse_improved =
      sum(
        high_rmse_improved,
        na.rm = TRUE
      ),

    folds_high_bias_improved =
      sum(
        high_bias_abs_improved,
        na.rm = TRUE
      ),

    mean_delta_rmse =
      mean(
        delta_rmse,
        na.rm = TRUE
      ),

    mean_delta_mae =
      mean(
        delta_mae,
        na.rm = TRUE
      ),

    .groups = "drop"
  )

write_csv(
  stability_summary,
  file.path(
    out_dir,
    "fold_stability_summary.csv"
  )
)

# ============================================================
# 13. Terminal report
# ============================================================

cat(
  "\n===== MEAN OUTER-FOLD METRICS =====\n"
)

print(
  as.data.frame(
    mean_metrics
  ),
  row.names = FALSE
)

cat(
  "\n===== FOLD STABILITY VS M0 =====\n"
)

print(
  as.data.frame(
    stability_summary
  ),
  row.names = FALSE
)

cat(
  "\n===== TAIL METRICS: >= 0.750 =====\n"
)

print(
  as.data.frame(
    tail_metrics |>
      filter(
        threshold >= 0.750
      )
  ),
  row.names = FALSE
)

cat(
  "\n===== DONE =====\n"
)

cat(
  "Output directory: ",
  out_dir,
  "\n",
  sep = ""
)
