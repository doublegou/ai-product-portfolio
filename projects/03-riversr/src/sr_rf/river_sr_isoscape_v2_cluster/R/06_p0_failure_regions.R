source("R/functions/core.R")

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

input_file <- file.path(
  project_root(),
  "outputs/p0_residual_diagnostics/p0_oof_residuals_all.rds"
)

stop_missing(
  input_file,
  "Run P0 residual diagnostics first."
)

out_dir <- file.path(
  project_root(),
  "outputs/p0_failure_regions"
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

residuals <- readRDS(input_file)

required_columns <- c(
  "row_id",
  "scheme",
  "algorithm",
  "outer_fold",
  "longitude",
  "latitude",
  "observed",
  "predicted",
  "residual",
  "absolute_error",
  "high_sr"
)

missing_columns <- setdiff(
  required_columns,
  names(residuals)
)

if (length(missing_columns) > 0L) {
  stop(
    "Missing columns: ",
    paste(
      missing_columns,
      collapse = ", "
    )
  )
}

# The three clearest P0 failure folds.
target_folds <- tribble(
  ~scheme,          ~outer_fold,
  "spatial_1500km", 2L,
  "spatial_1000km", 3L,
  "spatial_500km",  4L
)

rf <- residuals |>
  filter(
    algorithm == "RF",
    predictor_set == "P0"
  )

target <- rf |>
  inner_join(
    target_folds,
    by = c(
      "scheme",
      "outer_fold"
    )
  )

if (nrow(target) == 0L) {
  stop("No observations matched the target folds.")
}

# ------------------------------------------------------------
# 1. Overall target-fold summaries
# ------------------------------------------------------------

target_fold_summary <- target |>
  group_by(
    scheme,
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
        residual^2,
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

    high_rmse = sqrt(
      mean(
        residual[high_sr]^2,
        na.rm = TRUE
      )
    ),

    high_bias = mean(
      residual[high_sr],
      na.rm = TRUE
    ),

    top05_bias = mean(
      residual[
        observed >= quantile(
          observed,
          0.95,
          na.rm = TRUE
        )
      ],
      na.rm = TRUE
    ),

    observed_min = min(
      observed,
      na.rm = TRUE
    ),

    observed_max = max(
      observed,
      na.rm = TRUE
    ),

    predicted_min = min(
      predicted,
      na.rm = TRUE
    ),

    predicted_max = max(
      predicted,
      na.rm = TRUE
    ),

    .groups = "drop"
  )

write_csv(
  target_fold_summary,
  file.path(
    out_dir,
    "target_fold_summary.csv"
  )
)

# ------------------------------------------------------------
# 2. Equal-area 500 km hotspot grid
# ------------------------------------------------------------

target_sf <- st_as_sf(
  target,
  coords = c(
    "longitude",
    "latitude"
  ),
  crs = 4326,
  remove = FALSE
)

target_equal_area <- st_transform(
  target_sf,
  8857
)

xy <- st_coordinates(
  target_equal_area
)

grid_size_m <- 500000

target_grid_input <- target |>
  mutate(
    equal_area_x = xy[, 1],
    equal_area_y = xy[, 2],

    grid_x = floor(
      equal_area_x / grid_size_m
    ),

    grid_y = floor(
      equal_area_y / grid_size_m
    ),

    grid_id = paste(
      grid_x,
      grid_y,
      sep = "_"
    )
  )

grid_summary <- target_grid_input |>
  group_by(
    scheme,
    outer_fold,
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

    mean_observed = mean(
      observed,
      na.rm = TRUE
    ),

    mean_predicted = mean(
      predicted,
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
        residual^2,
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

    high_rmse = if (
      any(high_sr)
    ) {
      sqrt(
        mean(
          residual[high_sr]^2,
          na.rm = TRUE
        )
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

grid_sf <- st_as_sf(
  grid_summary,
  coords = c(
    "center_x",
    "center_y"
  ),
  crs = 8857,
  remove = FALSE
) |>
  st_transform(4326)

grid_coordinates <- st_coordinates(
  grid_sf
)

grid_summary <- grid_summary |>
  mutate(
    center_longitude =
      grid_coordinates[, 1],

    center_latitude =
      grid_coordinates[, 2]
  )

grid_hotspots <- grid_summary |>
  filter(
    n >= 5L
  ) |>
  group_by(
    scheme,
    outer_fold
  ) |>
  arrange(
    mean_residual,
    desc(n_high),
    desc(n)
  ) |>
  slice_head(n = 30L) |>
  ungroup()

write_csv(
  grid_summary,
  file.path(
    out_dir,
    "target_fold_grid500_all.csv"
  )
)

write_csv(
  grid_hotspots,
  file.path(
    out_dir,
    "target_fold_grid500_underprediction_hotspots.csv"
  )
)

# ------------------------------------------------------------
# 3. Most underpredicted individual sites
# ------------------------------------------------------------

site_metadata_candidates <- c(
  "row_id",
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
  "sample_id",
  "scheme",
  "outer_fold",
  "longitude",
  "latitude",
  "observed",
  "predicted",
  "residual",
  "absolute_error",
  "high_sr"
)

site_columns <- intersect(
  site_metadata_candidates,
  names(target)
)

worst_sites <- target |>
  group_by(
    scheme,
    outer_fold
  ) |>
  arrange(
    residual
  ) |>
  slice_head(n = 100L) |>
  ungroup() |>
  select(
    all_of(site_columns)
  )

worst_high_sites <- target |>
  filter(high_sr) |>
  group_by(
    scheme,
    outer_fold
  ) |>
  arrange(
    residual
  ) |>
  slice_head(n = 100L) |>
  ungroup() |>
  select(
    all_of(site_columns)
  )

write_csv(
  worst_sites,
  file.path(
    out_dir,
    "target_fold_top_underpredicted_sites.csv"
  )
)

write_csv(
  worst_high_sites,
  file.path(
    out_dir,
    "target_fold_high_sr_underpredicted_sites.csv"
  )
)

# ------------------------------------------------------------
# 4. Reference-level summaries
# ------------------------------------------------------------

reference_candidates <- c(
  "reference_id",
  "short_references",
  "reference"
)

reference_column <- reference_candidates[
  reference_candidates %in% names(target)
][1]

if (
  length(reference_column) == 1L &&
  !is.na(reference_column)
) {
  reference_summary <- target |>
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
      outer_fold,
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
          residual^2,
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

      longitude_mean = mean(
        longitude,
        na.rm = TRUE
      ),

      latitude_mean = mean(
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
    filter(
      n >= 3L
    ) |>
    arrange(
      scheme,
      outer_fold,
      bias
    )

  write_csv(
    reference_summary,
    file.path(
      out_dir,
      "target_fold_reference_summary.csv"
    )
  )
}

# ------------------------------------------------------------
# 5. Country-level summaries, when available
# ------------------------------------------------------------

if ("country" %in% names(target)) {
  country_summary <- target |>
    filter(
      !is.na(country),
      nzchar(as.character(country))
    ) |>
    group_by(
      scheme,
      outer_fold,
      country
    ) |>
    summarise(
      n = n(),

      n_high = sum(
        high_sr,
        na.rm = TRUE
      ),

      rmse = sqrt(
        mean(
          residual^2,
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
    filter(n >= 3L) |>
    arrange(
      scheme,
      outer_fold,
      bias
    )

  write_csv(
    country_summary,
    file.path(
      out_dir,
      "target_fold_country_summary.csv"
    )
  )
}

# ------------------------------------------------------------
# 6. GeoPackage
# ------------------------------------------------------------

gpkg_path <- file.path(
  out_dir,
  "p0_failure_regions.gpkg"
)

if (file.exists(gpkg_path)) {
  unlink(gpkg_path)
}

st_write(
  target_sf,
  dsn = gpkg_path,
  layer = "target_fold_sites",
  quiet = TRUE
)

high_target_sf <- target_sf |>
  filter(high_sr)

st_write(
  high_target_sf,
  dsn = gpkg_path,
  layer = "high_sr_sites",
  append = TRUE,
  quiet = TRUE
)

st_write(
  grid_sf,
  dsn = gpkg_path,
  layer = "grid500_centers",
  append = TRUE,
  quiet = TRUE
)

# ------------------------------------------------------------
# 7. Maps
# ------------------------------------------------------------

world <- NULL

if (
  requireNamespace(
    "maps",
    quietly = TRUE
  )
) {
  world <- ggplot2::map_data(
    "world"
  )
}

for (i in seq_len(nrow(target_folds))) {
  scheme_i <- target_folds$scheme[i]
  fold_i <- target_folds$outer_fold[i]

  map_data <- target |>
    filter(
      scheme == scheme_i,
      outer_fold == fold_i
    )

  plot_object <- ggplot()

  if (!is.null(world)) {
    plot_object <- plot_object +
      geom_polygon(
        data = world,
        aes(
          x = long,
          y = lat,
          group = group
        ),
        fill = "grey95",
        colour = "grey75",
        linewidth = 0.15
      )
  }

  plot_object <- plot_object +
    geom_point(
      data = map_data,
      aes(
        x = longitude,
        y = latitude,
        colour = residual,
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
      title = paste0(
        scheme_i,
        " / outer fold ",
        fold_i
      ),
      subtitle =
        "P0 Random Forest out-of-fold residuals",
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
        scheme_i,
        "_fold_",
        fold_i,
        "_residuals.png"
      )
    ),
    plot = plot_object,
    width = 11,
    height = 5.8,
    dpi = 220
  )

  high_map_data <- map_data |>
    filter(high_sr)

  high_plot <- ggplot()

  if (!is.null(world)) {
    high_plot <- high_plot +
      geom_polygon(
        data = world,
        aes(
          x = long,
          y = lat,
          group = group
        ),
        fill = "grey95",
        colour = "grey75",
        linewidth = 0.15
      )
  }

  high_plot <- high_plot +
    geom_point(
      data = high_map_data,
      aes(
        x = longitude,
        y = latitude,
        colour = residual,
        size = absolute_error
      ),
      alpha = 0.85
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
      title = paste0(
        "High-Sr sites: ",
        scheme_i,
        " / fold ",
        fold_i
      ),
      subtitle =
        "Observed ratio >= 0.720",
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
        scheme_i,
        "_fold_",
        fold_i,
        "_high_sr.png"
      )
    ),
    plot = high_plot,
    width = 11,
    height = 5.8,
    dpi = 220
  )
}

cat("\nTarget-fold summary:\n")

print(
  target_fold_summary,
  n = Inf,
  width = Inf
)

cat("\nStrongest 500-km underprediction hotspots:\n")

print(
  grid_hotspots |>
    select(
      scheme,
      outer_fold,
      grid_id,
      n,
      n_high,
      mean_residual,
      high_bias,
      rmse,
      center_longitude,
      center_latitude,
      observed_max,
      predicted_max
    ) |>
    group_by(
      scheme,
      outer_fold
    ) |>
    slice_head(n = 10L) |>
    ungroup(),
  n = Inf,
  width = Inf
)

log_msg(
  "P0 failure-region extraction complete: ",
  out_dir
)
