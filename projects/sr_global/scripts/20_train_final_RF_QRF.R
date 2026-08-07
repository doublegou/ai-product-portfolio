#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(ranger)
  library(dplyr)
  library(readr)
  library(tibble)
})

# ============================================================
# Global river-water Sr isoscape
# Final parsimonious RF + Quantile Regression Forest
# ============================================================

project_dir <- Sys.getenv(
  "SR_GLOBAL_DIR",
  unset = path.expand("~/projects/sr_global")
)

n_threads <- suppressWarnings(
  as.integer(
    Sys.getenv(
      "SR_NTHREADS",
      unset = "8"
    )
  )
)

if (
  length(n_threads) != 1 ||
  is.na(n_threads) ||
  n_threads < 1
) {
  n_threads <- 1L
}

seed_base <- 20260623L
num_trees <- 1000L
quantile_probs <- c(
  0.10,
  0.50,
  0.90
)

final_model_name <-
  "upstream_environment_plus_upstream_clay"

out_dir <- file.path(
  project_dir,
  "outputs/global/final_RF_QRF"
)

model_dir <- file.path(
  project_dir,
  "models/global/final_RF_QRF"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

dir.create(
  model_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

pick_existing_file <- function(
  paths,
  label
) {
  paths <- unique(paths)
  paths <- paths[
    !is.na(paths) &
      nzchar(paths)
  ]

  hits <- paths[
    file.exists(paths)
  ]

  if (length(hits) == 0) {
    stop(
      "Could not find ",
      label,
      ". Checked:\n",
      paste(
        paths,
        collapse = "\n"
      )
    )
  }

  normalizePath(
    hits[[1]],
    mustWork = TRUE
  )
}

# ------------------------------------------------------------
# Input data
# ------------------------------------------------------------

data_path <- pick_existing_file(
  c(
    file.path(
      project_dir,
      paste0(
        "data_processed/global/",
        "global_model_sites_5km_with_",
        "geology_climate_terrain_soil_complete.rds"
      )
    ),
    file.path(
      project_dir,
      paste0(
        "data_processed/global/",
        "global_model_sites_5km_with_",
        "geology_climate_terrain_soil.rds"
      )
    )
  ),
  "final modeling data"
)

# ------------------------------------------------------------
# Locate the previously fitted soil-model bundle
# ------------------------------------------------------------

model_search_dir <- file.path(
  project_dir,
  "models"
)

model_search_hits <- if (
  dir.exists(model_search_dir)
) {
  list.files(
    model_search_dir,
    pattern =
      "^global_soil_RF_models\\.rds$",
    recursive = TRUE,
    full.names = TRUE
  )
} else {
  character(0)
}

source_model_path <- pick_existing_file(
  c(
    file.path(
      project_dir,
      "models/global/global_soil_RF_models.rds"
    ),
    model_search_hits
  ),
  "global soil RF model bundle"
)

cat(
  "Data file:\n",
  data_path,
  "\n\n"
)

cat(
  "Source model bundle:\n",
  source_model_path,
  "\n\n"
)

# ------------------------------------------------------------
# Extract the exact predictor list already used in model 18
# ------------------------------------------------------------

source_models <- readRDS(
  source_model_path
)

if (
  !final_model_name %in%
    names(source_models)
) {
  stop(
    "Final model not present in source bundle: ",
    final_model_name,
    "\nAvailable models:\n",
    paste(
      names(source_models),
      collapse = "\n"
    )
  )
}

predictors <- source_models[[final_model_name]]$predictors

predictors <- unique(
  as.character(predictors)
)

if (length(predictors) == 0) {
  stop(
    "The extracted predictor vector is empty."
  )
}

cat(
  "Final model:\n",
  final_model_name,
  "\n"
)

cat(
  "Number of predictors:",
  length(predictors),
  "\n"
)

cat(
  "Predictors:\n",
  paste(
    predictors,
    collapse = "\n"
  ),
  "\n\n"
)

# ------------------------------------------------------------
# Load and check modeling data
# ------------------------------------------------------------

dat <- readRDS(
  data_path
)

if (inherits(dat, "sf")) {
  if (
    !requireNamespace(
      "sf",
      quietly = TRUE
    )
  ) {
    stop(
      "Input is an sf object, but sf is unavailable."
    )
  }

  dat <- sf::st_drop_geometry(
    dat
  )
}

dat <- as.data.frame(
  dat
)

if (!"site_id" %in% names(dat)) {
  dat$site_id <- seq_len(
    nrow(dat)
  )
}

if (!"sr" %in% names(dat)) {
  stop(
    "Response column 'sr' is missing."
  )
}

required_coordinate_vars <- c(
  "longitude",
  "latitude"
)

missing_coordinate_vars <- setdiff(
  required_coordinate_vars,
  names(dat)
)

if (length(missing_coordinate_vars) > 0) {
  stop(
    "Missing coordinate variables required for spatial predictors: ",
    paste(
      missing_coordinate_vars,
      collapse = ", "
    )
  )
}

dat$longitude <- as.numeric(
  dat$longitude
)

dat$latitude <- as.numeric(
  dat$latitude
)

if (
  any(!is.finite(dat$longitude)) ||
  any(!is.finite(dat$latitude))
) {
  stop(
    "Non-finite longitude or latitude values detected."
  )
}

# Spherical spatial coordinates, matching model 18 exactly.
lon_rad <- dat$longitude * pi / 180
lat_rad <- dat$latitude * pi / 180

dat$sp_x <- cos(lat_rad) * cos(lon_rad)
dat$sp_y <- cos(lat_rad) * sin(lon_rad)
dat$sp_z <- sin(lat_rad)

missing_predictors <- setdiff(
  predictors,
  names(dat)
)

if (
  length(missing_predictors) > 0
) {
  stop(
    "Missing final predictors:\n",
    paste(
      missing_predictors,
      collapse = "\n"
    )
  )
}

dat$sr <- as.numeric(
  dat$sr
)

dat$sr_scaled <- (
  dat$sr - 0.700
) * 1000

required_columns <- c(
  "sr",
  "sr_scaled",
  predictors
)

complete_index <- complete.cases(
  dat[
    ,
    required_columns,
    drop = FALSE
  ]
) &
  is.finite(dat$sr) &
  is.finite(dat$sr_scaled)

if (!all(complete_index)) {
  stop(
    "Final modeling data contain ",
    sum(!complete_index),
    " incomplete or non-finite rows."
  )
}

cat(
  "Training sites:",
  nrow(dat),
  "\n"
)

cat(
  "Threads:",
  n_threads,
  "\n"
)

cat(
  "Trees per model:",
  num_trees,
  "\n"
)

p <- length(predictors)

mtry_value <- max(
  1L,
  min(
    p,
    floor(p / 3)
  )
)

cat(
  "mtry:",
  mtry_value,
  "\n"
)

training_frame <- dat[
  ,
  c(
    "sr_scaled",
    predictors
  ),
  drop = FALSE
]

prediction_frame <- dat[
  ,
  predictors,
  drop = FALSE
]

# ------------------------------------------------------------
# Part A: final mean RF
# ------------------------------------------------------------

cat(
  "\nTraining final mean RF...\n"
)

final_rf <- ranger(
  dependent.variable.name =
    "sr_scaled",

  data =
    training_frame,

  num.trees =
    num_trees,

  mtry =
    mtry_value,

  min.node.size =
    5,

  splitrule =
    "variance",

  importance =
    "permutation",

  seed =
    seed_base,

  num.threads =
    n_threads,

  write.forest =
    TRUE
)

cat(
  "Final mean RF completed.\n"
)

# ------------------------------------------------------------
# Part B: final quantile regression forest
# ------------------------------------------------------------

cat(
  "\nTraining final QRF...\n"
)

final_qrf <- ranger(
  dependent.variable.name =
    "sr_scaled",

  data =
    training_frame,

  num.trees =
    num_trees,

  mtry =
    mtry_value,

  min.node.size =
    5,

  splitrule =
    "variance",

  quantreg =
    TRUE,

  keep.inbag =
    TRUE,

  importance =
    "none",

  seed =
    seed_base + 1L,

  num.threads =
    n_threads,

  write.forest =
    TRUE
)

cat(
  "Final QRF completed.\n"
)

# ------------------------------------------------------------
# Training-data fitted values
# These are QC diagnostics, not validation estimates.
# ------------------------------------------------------------

rf_prediction_scaled <- predict(
  final_rf,
  data = prediction_frame,
  num.threads = n_threads
)$predictions

rf_prediction <- (
  rf_prediction_scaled / 1000
) + 0.700

qrf_prediction_scaled <- predict(
  final_qrf,
  data = prediction_frame,
  type = "quantiles",
  quantiles = quantile_probs,
  seed = seed_base + 2L,
  num.threads = n_threads
)$predictions

qrf_prediction_scaled <-
  as.matrix(
    qrf_prediction_scaled
  )

if (
  ncol(qrf_prediction_scaled) !=
    length(quantile_probs)
) {
  stop(
    "Unexpected number of QRF quantile columns: ",
    ncol(qrf_prediction_scaled)
  )
}

qrf_prediction <- (
  qrf_prediction_scaled / 1000
) + 0.700

colnames(qrf_prediction) <- c(
  "qrf_p10",
  "qrf_p50",
  "qrf_p90"
)

if (
  any(
    qrf_prediction[, "qrf_p10"] >
      qrf_prediction[, "qrf_p50"]
  ) ||
  any(
    qrf_prediction[, "qrf_p50"] >
      qrf_prediction[, "qrf_p90"]
  )
) {
  stop(
    "Non-monotonic QRF quantiles detected."
  )
}

fitted_values <- tibble(
  site_id =
    as.character(dat$site_id),

  observed_sr =
    dat$sr,

  rf_mean =
    as.numeric(rf_prediction),

  qrf_p10 =
    as.numeric(
      qrf_prediction[
        ,
        "qrf_p10"
      ]
    ),

  qrf_p50 =
    as.numeric(
      qrf_prediction[
        ,
        "qrf_p50"
      ]
    ),

  qrf_p90 =
    as.numeric(
      qrf_prediction[
        ,
        "qrf_p90"
      ]
    )
) %>%
  mutate(
    rf_residual =
      rf_mean - observed_sr,

    qrf_median_residual =
      qrf_p50 - observed_sr,

    qrf_p80_width =
      qrf_p90 - qrf_p10,

    observed_inside_p10_p90 =
      observed_sr >= qrf_p10 &
      observed_sr <= qrf_p90
  )

calculate_apparent_metrics <- function(
  observed,
  predicted,
  model
) {
  residual <- predicted - observed

  sse <- sum(
    (observed - predicted)^2
  )

  sst <- sum(
    (observed - mean(observed))^2
  )

  tibble(
    evaluation =
      "training_apparent",

    model =
      model,

    n =
      length(observed),

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

    bias =
      mean(residual),

    r2_sse =
      1 - sse / sst,

    r2_cor =
      cor(
        observed,
        predicted
      )^2
  )
}

apparent_metrics <- bind_rows(
  calculate_apparent_metrics(
    fitted_values$observed_sr,
    fitted_values$rf_mean,
    "final_RF_mean"
  ),

  calculate_apparent_metrics(
    fitted_values$observed_sr,
    fitted_values$qrf_p50,
    "final_QRF_median"
  )
)

qrf_training_summary <- tibble(
  evaluation =
    "training_apparent",

  n =
    nrow(fitted_values),

  mean_p80_width =
    mean(
      fitted_values$qrf_p80_width
    ),

  median_p80_width =
    median(
      fitted_values$qrf_p80_width
    ),

  observed_p10_p90_coverage =
    mean(
      fitted_values$
        observed_inside_p10_p90
    )
)

# ------------------------------------------------------------
# Importance and metadata
# ------------------------------------------------------------

importance_table <- enframe(
  final_rf$variable.importance,
  name = "variable",
  value = "importance"
) %>%
  arrange(
    desc(importance)
  ) %>%
  mutate(
    rank =
      row_number(),
    .before = 1
  )

model_bundle <- list(
  model_name =
    final_model_name,

  response =
    "sr_scaled",

  original_response =
    "sr",

  predictors =
    predictors,

  rf_mean =
    final_rf,

  qrf =
    final_qrf,

  quantiles =
    quantile_probs,

  sr_scaling =
    list(
      subtract = 0.700,
      multiply = 1000
    ),

  hyperparameters =
    list(
      num_trees = num_trees,
      mtry = mtry_value,
      min_node_size = 5L,
      splitrule = "variance"
    ),

  training_n =
    nrow(dat),

  seed_base =
    seed_base,

  input_data =
    data_path,

  source_model_bundle =
    source_model_path,

  package_versions =
    list(
      R =
        R.version.string,

      ranger =
        as.character(
          packageVersion(
            "ranger"
          )
        )
    )
)

# ------------------------------------------------------------
# Save outputs
# ------------------------------------------------------------

saveRDS(
  model_bundle,
  file.path(
    model_dir,
    "final_upstream_clay_RF_QRF.rds"
  )
)

saveRDS(
  dat[
    ,
    c(
      "site_id",
      "sr",
      "sr_scaled",
      predictors
    ),
    drop = FALSE
  ],
  file.path(
    model_dir,
    "final_RF_QRF_training_data.rds"
  )
)

saveRDS(
  dat[
    0,
    predictors,
    drop = FALSE
  ],
  file.path(
    model_dir,
    "final_predictor_template.rds"
  )
)

write_csv(
  fitted_values,
  file.path(
    out_dir,
    "final_RF_QRF_training_fitted_values.csv"
  )
)

write_csv(
  apparent_metrics,
  file.path(
    out_dir,
    "final_RF_QRF_training_apparent_metrics.csv"
  )
)

write_csv(
  qrf_training_summary,
  file.path(
    out_dir,
    "final_QRF_training_interval_summary.csv"
  )
)

write_csv(
  importance_table,
  file.path(
    out_dir,
    "final_RF_variable_importance.csv"
  )
)

write_lines(
  predictors,
  file.path(
    out_dir,
    "final_predictor_names.txt"
  )
)

writeLines(
  capture.output(
    sessionInfo()
  ),
  file.path(
    out_dir,
    "sessionInfo.txt"
  )
)

cat(
  "\n===== APPARENT TRAINING METRICS =====\n"
)

print(
  apparent_metrics,
  width = Inf
)

cat(
  "\n===== QRF TRAINING INTERVAL SUMMARY =====\n"
)

print(
  qrf_training_summary,
  width = Inf
)

cat(
  "\n===== TOP 20 VARIABLE IMPORTANCE =====\n"
)

print(
  head(
    importance_table,
    20
  ),
  n = 20,
  width = Inf
)

cat(
  "\nFinal model saved to:\n",
  file.path(
    model_dir,
    "final_upstream_clay_RF_QRF.rds"
  ),
  "\n"
)

cat(
  "\nFinal RF/QRF training finished.\n"
)
