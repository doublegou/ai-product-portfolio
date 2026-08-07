#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(ranger)
  library(sf)
  library(tibble)
})

sf::sf_use_s2(TRUE)

site_dir <- Sys.getenv(
  "SR_GLOBAL_DIR",
  unset = "/home/zhangmeng/projects/sr_global"
)

n_threads <- as.integer(
  Sys.getenv("SR_NTHREADS", unset = "4")
)

seed_base <- 20260622L

input_file <- file.path(
  site_dir,
  "data_processed/global/global_model_sites_5km_with_geology_climate_terrain_complete.rds"
)

out_dir <- file.path(
  site_dir,
  "outputs/global/climate_models"
)

model_dir <- file.path(
  site_dir,
  "models/global"
)

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)

dat <- readRDS(input_file)

hydro_vars <- c(
  "log_DIS_AV_CMS",
  "log_UPLAND_SKM",
  "log_CATCH_SKM",
  "log_LENGTH_KM",
  "log_DIST_DN_KM",
  "log_DIST_UP_KM",
  "ORD_STRA",
  "ORD_CLAS",
  "ORD_FLOW"
)

required_cols <- c(
  "site_id",
  "longitude",
  "latitude",
  "sr",
  hydro_vars
)

missing_cols <- setdiff(required_cols, names(dat))

if (length(missing_cols) > 0) {
  stop(
    "Missing required columns: ",
    paste(missing_cols, collapse = ", ")
  )
}

numeric_cols <- c(
  "longitude",
  "latitude",
  "sr",
  hydro_vars
)

for (v in numeric_cols) {
  dat[[v]] <- as.numeric(dat[[v]])
}

complete_rows <- complete.cases(dat[, numeric_cols]) &
  apply(
    dat[, numeric_cols, drop = FALSE],
    1,
    function(x) all(is.finite(x))
  )

dat <- dat[complete_rows, , drop = FALSE]

if (nrow(dat) < 100) {
  stop("Too few complete sites for modeling.")
}

# Internally rescale Sr for numerical stability.
# Predictions are converted back to 87Sr/86Sr before evaluation.
dat$sr_scaled <- (dat$sr - 0.700) * 1000

# Spherical spatial coordinates avoid the -180/180° discontinuity.
lon_rad <- dat$longitude * pi / 180
lat_rad <- dat$latitude * pi / 180

dat$sp_x <- cos(lat_rad) * cos(lon_rad)
dat$sp_y <- cos(lat_rad) * sin(lon_rad)
dat$sp_z <- sin(lat_rad)

# Equal-area global coordinates for spatial blocks.
pts_ll <- st_as_sf(
  dat,
  coords = c("longitude", "latitude"),
  crs = 4326,
  remove = FALSE
)

pts_equal_area <- st_transform(pts_ll, 6933)
xy <- st_coordinates(pts_equal_area)

dat$eq_x_m <- xy[, 1]
dat$eq_y_m <- xy[, 2]

local_geo_vars <- grep(
  "^local_geo_.*_frac$",
  names(dat),
  value = TRUE
)

up_geo_vars <- grep(
  "^up_geo_.*_frac$",
  names(dat),
  value = TRUE
)

up_temperature_vars <- c(
  "up_bio1_C",
  "up_bio4_C_sd"
)

up_precipitation_vars <- c(
  "up_bio12_mm",
  "up_bio15_cv"
)

up_water_balance_vars <- c(
  "up_ai_ratio",
  "up_et0_mm"
)

up_elevation_vars <- c(
  "up_elevation_m"
)

up_climate_terrain_vars <- c(
  up_temperature_vars,
  up_precipitation_vars,
  up_water_balance_vars,
  up_elevation_vars
)

local_climate_terrain_vars <- c(
  "local_bio1_C",
  "local_bio4_C_sd",
  "local_bio12_mm",
  "local_bio15_cv",
  "local_ai_ratio",
  "local_et0_mm",
  "local_elevation_m"
)

required_new_vars <- c(
  up_climate_terrain_vars,
  local_climate_terrain_vars
)

missing_new_vars <- setdiff(
  required_new_vars,
  names(dat)
)

if (length(missing_new_vars) > 0) {
  stop(
    "Missing climate/terrain variables: ",
    paste(missing_new_vars, collapse = ", ")
  )
}

base_space_hydro <- c(
  "sp_x",
  "sp_y",
  "sp_z",
  hydro_vars
)

model_specs <- list(
  reference_upstream_geology = c(
    base_space_hydro,
    up_geo_vars
  ),

  upstream_geo_plus_temperature = c(
    base_space_hydro,
    up_geo_vars,
    up_temperature_vars
  ),

  upstream_geo_plus_precipitation = c(
    base_space_hydro,
    up_geo_vars,
    up_precipitation_vars
  ),

  upstream_geo_plus_water_balance = c(
    base_space_hydro,
    up_geo_vars,
    up_water_balance_vars
  ),

  upstream_geo_plus_elevation = c(
    base_space_hydro,
    up_geo_vars,
    up_elevation_vars
  ),

  upstream_geo_plus_all_upstream_environment = c(
    base_space_hydro,
    up_geo_vars,
    up_climate_terrain_vars
  ),

  upstream_geo_plus_local_and_upstream_environment = c(
    base_space_hydro,
    up_geo_vars,
    local_climate_terrain_vars,
    up_climate_terrain_vars
  ),

  both_geo_plus_local_and_upstream_environment = c(
    base_space_hydro,
    local_geo_vars,
    up_geo_vars,
    local_climate_terrain_vars,
    up_climate_terrain_vars
  )
)

fit_rf_predict <- function(
  train_data,
  test_data,
  predictors,
  seed,
  num_trees = 500
) {
  p <- length(predictors)

  mtry_value <- max(
    1L,
    min(
      p,
      floor(p / 3)
    )
  )

  fit <- ranger(
    dependent.variable.name = "sr_scaled",
    data = train_data[
      ,
      c("sr_scaled", predictors),
      drop = FALSE
    ],
    num.trees = num_trees,
    mtry = mtry_value,
    min.node.size = 5,
    splitrule = "variance",
    seed = seed,
    num.threads = n_threads,
    write.forest = TRUE
  )

  pred_scaled <- predict(
    fit,
    data = test_data[
      ,
      predictors,
      drop = FALSE
    ]
  )$predictions

  pred_scaled / 1000 + 0.700
}

calculate_metrics <- function(
  prediction_data,
  validation,
  run_id,
  model_name
) {
  obs <- prediction_data$observed
  pred <- prediction_data$predicted

  residual <- pred - obs

  sse <- sum((obs - pred)^2)
  sst <- sum((obs - mean(obs))^2)

  tibble(
    validation = validation,
    run_id = as.character(run_id),
    model = model_name,
    n = length(obs),
    rmse = sqrt(mean(residual^2)),
    mae = mean(abs(residual)),
    bias = mean(residual),
    r2_sse = 1 - sse / sst,
    r2_cor = ifelse(
      sd(obs) > 0 && sd(pred) > 0,
      cor(obs, pred)^2,
      NA_real_
    )
  )
}

cat("Input sites:", nrow(dat), "\n")
cat("Threads:", n_threads, "\n")

# ------------------------------------------------------------
# Part A: repeated random 5-fold CV
# ------------------------------------------------------------

k_folds <- 5L
n_random_repeats <- 5L

random_predictions_list <- list()
random_metrics_list <- list()

prediction_counter <- 1L
metric_counter <- 1L

for (repeat_id in seq_len(n_random_repeats)) {

  set.seed(seed_base + repeat_id)

  fold_id <- sample(
    rep(
      seq_len(k_folds),
      length.out = nrow(dat)
    )
  )

  for (model_name in names(model_specs)) {

    predictors <- model_specs[[model_name]]
    fold_prediction_list <- list()

    for (fold in seq_len(k_folds)) {

      test_index <- which(fold_id == fold)
      train_index <- which(fold_id != fold)

      predicted <- fit_rf_predict(
        train_data = dat[train_index, , drop = FALSE],
        test_data = dat[test_index, , drop = FALSE],
        predictors = predictors,
        seed = seed_base +
          repeat_id * 100L +
          fold * 10L +
          match(model_name, names(model_specs))
      )

      fold_prediction_list[[fold]] <- tibble(
        site_id = dat$site_id[test_index],
        validation = "random_cv",
        run_id = paste0("repeat_", repeat_id),
        fold = fold,
        model = model_name,
        observed = dat$sr[test_index],
        predicted = predicted,
        residual = predicted - dat$sr[test_index]
      )
    }

    model_predictions <- bind_rows(
      fold_prediction_list
    )

    random_predictions_list[[prediction_counter]] <-
      model_predictions

    random_metrics_list[[metric_counter]] <-
      calculate_metrics(
        model_predictions,
        validation = "random_cv",
        run_id = paste0("repeat_", repeat_id),
        model_name = model_name
      )

    prediction_counter <- prediction_counter + 1L
    metric_counter <- metric_counter + 1L
  }

  cat(
    "Random CV repeat completed:",
    repeat_id,
    "of",
    n_random_repeats,
    "\n"
  )
}

random_predictions <- bind_rows(
  random_predictions_list
)

random_metrics <- bind_rows(
  random_metrics_list
)

write_csv(
  random_predictions,
  file.path(out_dir, "random_cv_predictions.csv")
)

write_csv(
  random_metrics,
  file.path(out_dir, "random_cv_metrics_by_repeat.csv")
)

random_summary <- random_metrics %>%
  group_by(model) %>%
  summarise(
    n_runs = n(),
    rmse_mean = mean(rmse),
    rmse_sd = sd(rmse),
    mae_mean = mean(mae),
    mae_sd = sd(mae),
    bias_mean = mean(bias),
    r2_sse_mean = mean(r2_sse),
    r2_sse_sd = sd(r2_sse),
    r2_cor_mean = mean(r2_cor),
    r2_cor_sd = sd(r2_cor),
    .groups = "drop"
  ) %>%
  mutate(validation = "random_cv") %>%
  relocate(validation)

write_csv(
  random_summary,
  file.path(out_dir, "random_cv_metrics_summary.csv")
)

# ------------------------------------------------------------
# Part B: global spatial block CV
# ------------------------------------------------------------

block_size_m <- 1000000
buffer_m <- 200000

shift_schemes <- tibble(
  scheme = c(
    "shift_00",
    "shift_x",
    "shift_y",
    "shift_xy"
  ),
  shift_x = c(
    0,
    block_size_m / 2,
    0,
    block_size_m / 2
  ),
  shift_y = c(
    0,
    0,
    block_size_m / 2,
    block_size_m / 2
  )
)

spatial_predictions_list <- list()
spatial_metrics_list <- list()
spatial_fold_summary_list <- list()
spatial_assignment_list <- list()

prediction_counter <- 1L
metric_counter <- 1L
fold_summary_counter <- 1L
assignment_counter <- 1L

for (scheme_index in seq_len(nrow(shift_schemes))) {

  scheme_name <- shift_schemes$scheme[scheme_index]
  shift_x <- shift_schemes$shift_x[scheme_index]
  shift_y <- shift_schemes$shift_y[scheme_index]

  block_x <- floor(
    (dat$eq_x_m + shift_x) / block_size_m
  )

  block_y <- floor(
    (dat$eq_y_m + shift_y) / block_size_m
  )

  block_id <- paste(
    block_x,
    block_y,
    sep = "_"
  )

  # Checkerboard-like assignment distributes test blocks globally.
  spatial_fold <- (
    (block_x + 2 * block_y) %% k_folds
  ) + 1L

  spatial_assignment_list[[assignment_counter]] <-
    tibble(
      site_id = dat$site_id,
      scheme = scheme_name,
      block_x = block_x,
      block_y = block_y,
      block_id = block_id,
      fold = spatial_fold
    )

  assignment_counter <- assignment_counter + 1L

  scheme_predictions_by_model <- list()

  for (model_name in names(model_specs)) {

    predictors <- model_specs[[model_name]]
    fold_prediction_list <- list()

    for (fold in seq_len(k_folds)) {

      test_index <- which(spatial_fold == fold)
      train_index_initial <- which(spatial_fold != fold)

      if (length(test_index) == 0) {
        stop(
          "Spatial fold has no test sites: ",
          scheme_name,
          ", fold ",
          fold
        )
      }

      # Remove training sites located within 200 km of test sites.
      near_test <- st_is_within_distance(
        pts_ll[train_index_initial, ],
        pts_ll[test_index, ],
        dist = buffer_m
      )

      keep_train <- lengths(near_test) == 0

      train_index <- train_index_initial[
        keep_train
      ]

      if (length(train_index) < 500) {
        stop(
          "Too few buffered training sites: ",
          scheme_name,
          ", fold ",
          fold,
          ", n = ",
          length(train_index)
        )
      }

      predicted <- fit_rf_predict(
        train_data = dat[train_index, , drop = FALSE],
        test_data = dat[test_index, , drop = FALSE],
        predictors = predictors,
        seed = seed_base +
          scheme_index * 1000L +
          fold * 10L +
          match(model_name, names(model_specs))
      )

      fold_prediction_list[[fold]] <- tibble(
        site_id = dat$site_id[test_index],
        validation = "spatial_block_cv",
        run_id = scheme_name,
        fold = fold,
        model = model_name,
        block_size_km = block_size_m / 1000,
        buffer_km = buffer_m / 1000,
        observed = dat$sr[test_index],
        predicted = predicted,
        residual = predicted - dat$sr[test_index]
      )

      if (model_name == names(model_specs)[1]) {
        spatial_fold_summary_list[[fold_summary_counter]] <-
          tibble(
            scheme = scheme_name,
            fold = fold,
            n_test = length(test_index),
            n_train_before_buffer =
              length(train_index_initial),
            n_train_after_buffer =
              length(train_index),
            n_train_removed_by_buffer =
              length(train_index_initial) -
              length(train_index),
            n_test_blocks =
              length(unique(block_id[test_index]))
          )

        fold_summary_counter <-
          fold_summary_counter + 1L
      }
    }

    model_predictions <- bind_rows(
      fold_prediction_list
    )

    spatial_predictions_list[[prediction_counter]] <-
      model_predictions

    spatial_metrics_list[[metric_counter]] <-
      calculate_metrics(
        model_predictions,
        validation = "spatial_block_cv",
        run_id = scheme_name,
        model_name = model_name
      )

    prediction_counter <- prediction_counter + 1L
    metric_counter <- metric_counter + 1L
  }

  cat(
    "Spatial scheme completed:",
    scheme_name,
    "\n"
  )
}

spatial_predictions <- bind_rows(
  spatial_predictions_list
)

spatial_metrics <- bind_rows(
  spatial_metrics_list
)

spatial_fold_summary <- bind_rows(
  spatial_fold_summary_list
)

spatial_assignments <- bind_rows(
  spatial_assignment_list
)

write_csv(
  spatial_predictions,
  file.path(out_dir, "spatial_block_cv_predictions.csv")
)

write_csv(
  spatial_metrics,
  file.path(out_dir, "spatial_block_cv_metrics_by_scheme.csv")
)

write_csv(
  spatial_fold_summary,
  file.path(out_dir, "spatial_block_cv_fold_counts.csv")
)

write_csv(
  spatial_assignments,
  file.path(out_dir, "spatial_block_assignments.csv")
)

spatial_summary <- spatial_metrics %>%
  group_by(model) %>%
  summarise(
    n_runs = n(),
    rmse_mean = mean(rmse),
    rmse_sd = sd(rmse),
    mae_mean = mean(mae),
    mae_sd = sd(mae),
    bias_mean = mean(bias),
    r2_sse_mean = mean(r2_sse),
    r2_sse_sd = sd(r2_sse),
    r2_cor_mean = mean(r2_cor),
    r2_cor_sd = sd(r2_cor),
    .groups = "drop"
  ) %>%
  mutate(validation = "spatial_block_cv") %>%
  relocate(validation)

write_csv(
  spatial_summary,
  file.path(out_dir, "spatial_block_cv_metrics_summary.csv")
)

# ------------------------------------------------------------
# Part C: combined comparison
# ------------------------------------------------------------

comparison <- bind_rows(
  random_summary,
  spatial_summary
)

write_csv(
  comparison,
  file.path(out_dir, "global_climate_model_comparison.csv")
)

validation_gap <- random_summary %>%
  select(
    model,
    random_rmse = rmse_mean,
    random_r2 = r2_sse_mean
  ) %>%
  left_join(
    spatial_summary %>%
      select(
        model,
        spatial_rmse = rmse_mean,
        spatial_r2 = r2_sse_mean
      ),
    by = "model"
  ) %>%
  mutate(
    rmse_increase_spatial =
      spatial_rmse - random_rmse,
    r2_drop_random_to_spatial =
      random_r2 - spatial_r2
  )

write_csv(
  validation_gap,
  file.path(out_dir, "random_vs_spatial_validation_gap.csv")
)

# ------------------------------------------------------------
# Part D: fit final full-data baseline models
# ------------------------------------------------------------

final_models <- list()
importance_list <- list()

for (model_name in names(model_specs)) {

  predictors <- model_specs[[model_name]]
  p <- length(predictors)

  final_fit <- ranger(
    dependent.variable.name = "sr_scaled",
    data = dat[
      ,
      c("sr_scaled", predictors),
      drop = FALSE
    ],
    num.trees = 1000,
    mtry = max(
      1L,
      min(p, floor(p / 3))
    ),
    min.node.size = 5,
    splitrule = "variance",
    importance = "permutation",
    seed = seed_base +
      10000L +
      match(model_name, names(model_specs)),
    num.threads = n_threads,
    write.forest = TRUE
  )

  final_models[[model_name]] <- list(
    model = final_fit,
    predictors = predictors,
    sr_scaling = list(
      subtract = 0.700,
      multiply = 1000
    )
  )

  importance_list[[model_name]] <- tibble(
    model = model_name,
    variable = names(
      final_fit$variable.importance
    ),
    importance = as.numeric(
      final_fit$variable.importance
    )
  ) %>%
    arrange(desc(importance))
}

saveRDS(
  final_models,
  file.path(
    model_dir,
    "global_climate_RF_models.rds"
  )
)

write_csv(
  bind_rows(importance_list),
  file.path(
    out_dir,
    "global_climate_variable_importance.csv"
  )
)

saveRDS(
  dat,
  file.path(
    model_dir,
    "global_climate_modeling_data.rds"
  )
)

cat("\nRandom CV summary:\n")
print(random_summary)

cat("\nSpatial block CV summary:\n")
print(spatial_summary)

cat("\nRandom versus spatial validation gap:\n")
print(validation_gap)

cat("\nGlobal climate-terrain modeling finished.\n")
