source("R/functions/core.R")
source("R/functions/metrics.R")

check_packages(
  c(
    "dplyr",
    "readr",
    "tibble",
    "sf",
    "ggplot2"
  )
)

library(dplyr)
library(readr)
library(tibble)
library(sf)
library(ggplot2)

cfg <- read_config()

out_dir <- file.path(
  project_root(),
  "outputs/p0_residual_diagnostics"
)

map_dir <- file.path(
  out_dir,
  "maps"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

dir.create(
  map_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

model_path <- file.path(
  project_root(),
  "data/processed/model_table.rds"
)

prediction_path <- file.path(
  project_root(),
  "outputs/experiment_A_p0/oof_predictions.rds"
)

fold_metrics_path <- file.path(
  project_root(),
  "outputs/experiment_A_p0/metrics_by_outer_fold.csv"
)

stop_missing(
  model_path,
  "Missing model table."
)

stop_missing(
  prediction_path,
  "Missing P0 OOF predictions."
)

stop_missing(
  fold_metrics_path,
  "Missing P0 outer-fold metrics."
)

dat <- readRDS(model_path)
pred <- readRDS(prediction_path)

required_prediction_columns <- c(
  "row_id",
  "observed",
  "predicted",
  "algorithm",
  "outer_fold",
  "scheme",
  "predictor_set"
)

missing_prediction_columns <- setdiff(
  required_prediction_columns,
  names(pred)
)

if (length(missing_prediction_columns) > 0L) {
  stop(
    "Missing prediction columns: ",
    paste(
      missing_prediction_columns,
      collapse = ", "
    )
  )
}

required_model_columns <- c(
  "row_id",
  "longitude",
  "latitude"
)

missing_model_columns <- setdiff(
  required_model_columns,
  names(dat)
)

if (length(missing_model_columns) > 0L) {
  stop(
    "Missing model-table columns: ",
    paste(
      missing_model_columns,
      collapse = ", "
    )
  )
}

optional_metadata <- c(
  "site_id",
  "legacy_site_id",
  "reference_id",
  "short_references",
  "reference",
  "river_name",
  "site_name",
  "country",
  "continent",
  "basin_name",
  "sample_id"
)

metadata_columns <- unique(
  c(
    required_model_columns,
    intersect(
      optional_metadata,
      names(dat)
    )
  )
)

metadata <- dat |>
  select(
    all_of(metadata_columns)
  ) |>
  distinct(row_id, .keep_all = TRUE)

joined <- pred |>
  filter(
    predictor_set == "P0"
  ) |>
  left_join(
    metadata,
    by = "row_id"
  ) |>
  mutate(
    residual = predicted - observed,
    absolute_error = abs(residual),
    squared_error = residual^2,
    high_sr = observed >=
      cfg$selection$high_threshold,

    top10 = observed >=
      quantile(
        observed,
        probs = 0.90,
        na.rm = TRUE
      ),

    top05 = observed >=
      quantile(
        observed,
        probs = 0.95,
        na.rm = TRUE
      ),

    residual_direction = case_when(
      residual < -0.005 ~
        "underprediction_gt_0.005",

      residual > 0.005 ~
        "overprediction_gt_0.005",

      TRUE ~
        "within_0.005"
    )
  )

if (
  anyNA(joined$longitude) ||
  anyNA(joined$latitude)
) {
  stop(
    "Missing coordinates after joining predictions to model table."
  )
}

prediction_counts <- joined |>
  count(
    scheme,
    algorithm,
    predictor_set,
    name = "n_predictions"
  ) |>
  arrange(
    scheme,
    algorithm
  )

write_csv(
  prediction_counts,
  file.path(
    out_dir,
    "prediction_counts.csv"
  )
)

write_atomic_rds(
  joined,
  file.path(
    out_dir,
    "p0_oof_residuals_all.rds"
  )
)

write_csv(
  joined,
  file.path(
    out_dir,
    "p0_oof_residuals_all.csv"
  )
)

# ------------------------------------------------------------
# 1. Pooled OOF metrics
# ------------------------------------------------------------

pooled_metrics <- joined |>
  group_by(
    scheme,
    predictor_set,
    algorithm
  ) |>
  group_modify(
    ~ metric_row(
      .x$observed,
      .x$predicted,
      cfg$selection$high_threshold
    )
  ) |>
  ungroup() |>
  arrange(
    scheme,
    rmse
  )

write_csv(
  pooled_metrics,
  file.path(
    out_dir,
    "pooled_oof_metrics.csv"
  )
)

# ------------------------------------------------------------
# 2. Fold variability
# ------------------------------------------------------------

fold_metrics <- read_csv(
  fold_metrics_path,
  show_col_types = FALSE
)

fold_variability <- fold_metrics |>
  group_by(
    scheme,
    predictor_set,
    algorithm
  ) |>
  summarise(
    across(
      c(
        rmse,
        mae,
        r2_sse,
        bias,
        high_rmse,
        high_bias,
        predicted_range_ratio,
        calibration_slope,
        max_predicted
      ),
      list(
        mean = ~ mean(
          .x,
          na.rm = TRUE
        ),

        sd = ~ stats::sd(
          .x,
          na.rm = TRUE
        ),

        min = ~ min(
          .x,
          na.rm = TRUE
        ),

        max = ~ max(
          .x,
          na.rm = TRUE
        )
      )
    ),
    .groups = "drop"
  )

write_csv(
  fold_variability,
  file.path(
    out_dir,
    "fold_metric_variability.csv"
  )
)

# ------------------------------------------------------------
# 3. Fold-level geographic summaries
# ------------------------------------------------------------

fold_geography <- joined |>
  group_by(
    scheme,
    predictor_set,
    algorithm,
    outer_fold
  ) |>
  summarise(
    n = n(),

    n_high = sum(
      high_sr,
      na.rm = TRUE
    ),

    rmse = sqrt(
      mean(
        squared_error,
        na.rm = TRUE
      )
    ),

    mae = mean(
      absolute_error,
      na.rm = TRUE
    ),

    bias = mean(
      residual,
      na.rm = TRUE
    ),

    high_rmse = if (
      any(high_sr)
    ) {
      sqrt(
        mean(
          squared_error[high_sr],
          na.rm = TRUE
        )
      )
    } else {
      NA_real_
    },

    high_bias = if (
      any(high_sr)
    ) {
      mean(
        residual[high_sr],
        na.rm = TRUE
      )
    } else {
      NA_real_
    },

    longitude_mean = mean(
      longitude,
      na.rm = TRUE
    ),

    latitude_mean = mean(
      latitude,
      na.rm = TRUE
    ),

    longitude_min = min(
      longitude,
      na.rm = TRUE
    ),

    longitude_max = max(
      longitude,
      na.rm = TRUE
    ),

    latitude_min = min(
      latitude,
      na.rm = TRUE
    ),

    latitude_max = max(
      latitude,
      na.rm = TRUE
    ),

    observed_max = max(
      observed,
      na.rm = TRUE
    ),

    predicted_max = max(
      predicted,
      na.rm = TRUE
    ),

    .groups = "drop"
  ) |>
  arrange(
    desc(rmse)
  )

write_csv(
  fold_geography,
  file.path(
    out_dir,
    "fold_geographic_diagnostics.csv"
  )
)

# ------------------------------------------------------------
# 4. RF point-level extremes
# ------------------------------------------------------------

rf <- joined |>
  filter(
    algorithm == "RF"
  )

rf_underpredicted <- rf |>
  group_by(scheme) |>
  slice_min(
    order_by = residual,
    n = 100,
    with_ties = FALSE
  ) |>
  ungroup() |>
  arrange(
    scheme,
    residual
  )

rf_overpredicted <- rf |>
  group_by(scheme) |>
  slice_max(
    order_by = residual,
    n = 100,
    with_ties = FALSE
  ) |>
  ungroup() |>
  arrange(
    scheme,
    desc(residual)
  )

rf_high_underpredicted <- rf |>
  filter(high_sr) |>
  group_by(scheme) |>
  slice_min(
    order_by = residual,
    n = 100,
    with_ties = FALSE
  ) |>
  ungroup() |>
  arrange(
    scheme,
    residual
  )

write_csv(
  rf_underpredicted,
  file.path(
    out_dir,
    "rf_top_underpredicted_sites.csv"
  )
)

write_csv(
  rf_overpredicted,
  file.path(
    out_dir,
    "rf_top_overpredicted_sites.csv"
  )
)

write_csv(
  rf_high_underpredicted,
  file.path(
    out_dir,
    "rf_high_sr_underpredicted_sites.csv"
  )
)

# ------------------------------------------------------------
# 5. Reference-level residual summaries
# ------------------------------------------------------------

reference_candidates <- c(
  "reference_id",
  "short_references",
  "reference"
)

reference_column <- reference_candidates[
  reference_candidates %in% names(rf)
][1]

if (
  length(reference_column) == 1L &&
  !is.na(reference_column)
) {
  reference_summary <- rf |>
    mutate(
      reference_group =
        as.character(
          .data[[reference_column]]
        )
    ) |>
    filter(
      !is.na(reference_group),
      nzchar(reference_group)
    ) |>
    group_by(
      scheme,
      reference_group
    ) |>
    summarise(
      n = n(),

      n_high = sum(
        high_sr,
        na.rm = TRUE
      ),

      rmse = sqrt(
        mean(
          squared_error,
          na.rm = TRUE
        )
      ),

      bias = mean(
        residual,
        na.rm = TRUE
      ),

      high_bias = if (
        any(high_sr)
      ) {
        mean(
          residual[high_sr],
          na.rm = TRUE
        )
      } else {
        NA_real_
      },

      observed_max = max(
        observed,
        na.rm = TRUE
      ),

      predicted_max = max(
        predicted,
        na.rm = TRUE
      ),

      .groups = "drop"
    ) |>
    filter(n >= 5L) |>
    arrange(
      scheme,
      desc(rmse)
    )

  write_csv(
    reference_summary,
    file.path(
      out_dir,
      "rf_reference_residual_summary.csv"
    )
  )
}

# ------------------------------------------------------------
# 6. Equal-area 500 km residual hotspot summaries
# ------------------------------------------------------------

rf_sf_wgs84 <- st_as_sf(
  rf,
  coords = c(
    "longitude",
    "latitude"
  ),
  crs = 4326,
  remove = FALSE
)

rf_sf_equal_area <- st_transform(
  rf_sf_wgs84,
  8857
)

xy <- st_coordinates(
  rf_sf_equal_area
)

grid_size_m <- 500000

rf_grid <- rf |>
  mutate(
    grid_x = floor(
      xy[, 1] / grid_size_m
    ),

    grid_y = floor(
      xy[, 2] / grid_size_m
    ),

    grid_id = paste(
      grid_x,
      grid_y,
      sep = "_"
    )
  )

grid_summary <- rf_grid |>
  group_by(
    scheme,
    grid_id,
    grid_x,
    grid_y
  ) |>
  summarise(
    n = n(),

    n_high = sum(
      high_sr,
      na.rm = TRUE
    ),

    mean_residual = mean(
      residual,
      na.rm = TRUE
    ),

    median_residual = median(
      residual,
      na.rm = TRUE
    ),

    rmse = sqrt(
      mean(
        squared_error,
        na.rm = TRUE
      )
    ),

    high_bias = if (
      any(high_sr)
    ) {
      mean(
        residual[high_sr],
        na.rm = TRUE
      )
    } else {
      NA_real_
    },

    observed_max = max(
      observed,
      na.rm = TRUE
    ),

    predicted_max = max(
      predicted,
      na.rm = TRUE
    ),

    center_x = (
      first(grid_x) + 0.5
    ) * grid_size_m,

    center_y = (
      first(grid_y) + 0.5
    ) * grid_size_m,

    .groups = "drop"
  )

grid_centers <- st_as_sf(
  grid_summary,
  coords = c(
    "center_x",
    "center_y"
  ),
  crs = 8857,
  remove = FALSE
) |>
  st_transform(4326)

grid_lonlat <- st_coordinates(
  grid_centers
)

grid_summary <- grid_summary |>
  mutate(
    center_longitude =
      grid_lonlat[, 1],

    center_latitude =
      grid_lonlat[, 2]
  ) |>
  arrange(
    scheme,
    mean_residual
  )

write_csv(
  grid_summary,
  file.path(
    out_dir,
    "rf_grid500_residual_summary.csv"
  )
)

write_csv(
  grid_summary |>
    filter(n >= 10L) |>
    group_by(scheme) |>
    slice_min(
      order_by = mean_residual,
      n = 20,
      with_ties = FALSE
    ) |>
    ungroup(),
  file.path(
    out_dir,
    "rf_grid500_underprediction_hotspots.csv"
  )
)

write_csv(
  grid_summary |>
    filter(n >= 10L) |>
    group_by(scheme) |>
    slice_max(
      order_by = mean_residual,
      n = 20,
      with_ties = FALSE
    ) |>
    ungroup(),
  file.path(
    out_dir,
    "rf_grid500_overprediction_hotspots.csv"
  )
)

# ------------------------------------------------------------
# 7. GeoPackage for QGIS
# ------------------------------------------------------------

gpkg_path <- file.path(
  out_dir,
  "p0_rf_oof_residuals.gpkg"
)

if (file.exists(gpkg_path)) {
  unlink(gpkg_path)
}

st_write(
  rf_sf_wgs84,
  dsn = gpkg_path,
  layer = "rf_oof_residuals",
  quiet = TRUE
)

# ------------------------------------------------------------
# 8. Residual and fold maps
# ------------------------------------------------------------

residual_limits <- quantile(
  rf$residual,
  probs = c(
    0.02,
    0.98
  ),
  na.rm = TRUE
)

make_world_background <- function(plot_object) {
  if (
    requireNamespace(
      "maps",
      quietly = TRUE
    )
  ) {
    world <- ggplot2::map_data(
      "world"
    )

    plot_object +
      geom_polygon(
        data = world,
        aes(
          x = long,
          y = lat,
          group = group
        ),
        inherit.aes = FALSE,
        fill = "grey95",
        colour = "grey75",
        linewidth = 0.15
      )
  } else {
    plot_object
  }
}

for (
  scheme_name in unique(
    rf$scheme
  )
) {
  map_dat <- rf |>
    filter(
      scheme == scheme_name
    ) |>
    mutate(
      residual_plot = pmax(
        residual_limits[1],
        pmin(
          residual,
          residual_limits[2]
        )
      )
    )

  residual_plot <- ggplot()

  residual_plot <-
    make_world_background(
      residual_plot
    )

  residual_plot <-
    residual_plot +
    geom_point(
      data = map_dat,
      aes(
        x = longitude,
        y = latitude,
        colour = residual_plot
      ),
      size = 0.75,
      alpha = 0.75
    ) +
    scale_colour_gradient2(
      midpoint = 0,
      name = "Predicted - observed"
    ) +
    coord_quickmap(
      xlim = c(-180, 180),
      ylim = c(-60, 85),
      expand = FALSE
    ) +
    labs(
      title = paste(
        "P0 RF OOF residuals:",
        scheme_name
      ),
      subtitle =
        "Negative values indicate underprediction",
      x = "Longitude",
      y = "Latitude"
    ) +
    theme_minimal(
      base_size = 11
    )

  ggsave(
    filename = file.path(
      map_dir,
      paste0(
        "rf_residual_",
        scheme_name,
        ".png"
      )
    ),
    plot = residual_plot,
    width = 11,
    height = 5.8,
    dpi = 220
  )

  fold_plot <- ggplot()

  fold_plot <-
    make_world_background(
      fold_plot
    )

  fold_plot <-
    fold_plot +
    geom_point(
      data = map_dat,
      aes(
        x = longitude,
        y = latitude,
        colour = factor(
          outer_fold
        )
      ),
      size = 0.75,
      alpha = 0.8
    ) +
    coord_quickmap(
      xlim = c(-180, 180),
      ylim = c(-60, 85),
      expand = FALSE
    ) +
    labs(
      title = paste(
        "Outer-fold geography:",
        scheme_name
      ),
      colour = "Outer fold",
      x = "Longitude",
      y = "Latitude"
    ) +
    theme_minimal(
      base_size = 11
    )

  ggsave(
    filename = file.path(
      map_dir,
      paste0(
        "outer_folds_",
        scheme_name,
        ".png"
      )
    ),
    plot = fold_plot,
    width = 11,
    height = 5.8,
    dpi = 220
  )

  high_plot_dat <- map_dat |>
    filter(high_sr)

  high_plot <- ggplot()

  high_plot <-
    make_world_background(
      high_plot
    )

  high_plot <-
    high_plot +
    geom_point(
      data = high_plot_dat,
      aes(
        x = longitude,
        y = latitude,
        colour = residual_plot,
        size = absolute_error
      ),
      alpha = 0.8
    ) +
    scale_colour_gradient2(
      midpoint = 0,
      name = "Predicted - observed"
    ) +
    scale_size_continuous(
      name = "Absolute error"
    ) +
    coord_quickmap(
      xlim = c(-180, 180),
      ylim = c(-60, 85),
      expand = FALSE
    ) +
    labs(
      title = paste(
        "High-Sr residuals:",
        scheme_name
      ),
      subtitle = paste0(
        "Observed Sr >= ",
        cfg$selection$high_threshold
      ),
      x = "Longitude",
      y = "Latitude"
    ) +
    theme_minimal(
      base_size = 11
    )

  ggsave(
    filename = file.path(
      map_dir,
      paste0(
        "high_sr_residual_",
        scheme_name,
        ".png"
      )
    ),
    plot = high_plot,
    width = 11,
    height = 5.8,
    dpi = 220
  )
}

log_msg(
  "P0 residual diagnostics complete: ",
  out_dir
)

print(
  pooled_metrics,
  n = Inf,
  width = Inf
)

cat(
  "\nWorst RF outer folds:\n"
)

print(
  fold_geography |>
    filter(
      algorithm == "RF"
    ) |>
    select(
      scheme,
      outer_fold,
      n,
      n_high,
      rmse,
      high_rmse,
      high_bias,
      longitude_mean,
      latitude_mean,
      observed_max,
      predicted_max
    ) |>
    slice_head(n = 12),
  n = Inf,
  width = Inf
)
