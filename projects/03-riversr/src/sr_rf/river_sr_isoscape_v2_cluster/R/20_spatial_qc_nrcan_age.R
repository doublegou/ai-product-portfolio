#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(readr)
  library(ggplot2)
})

input_gpkg <- paste0(
  "outputs/nrcan_of5529/final_age_crosswalk/",
  "roxworld_age_wgs84.gpkg"
)

output_dir <- "outputs/nrcan_of5529/spatial_qc"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

cat("Reading final NRCan age GeoPackage...\n")

x <- st_read(
  input_gpkg,
  layer = "roxworld_age",
  quiet = TRUE
)

required_fields <- c(
  "RUNO",
  "GROUP",
  "resolution_method",
  "resolved",
  "confidence_tier",
  "weighted_mean_midpoint_ma",
  "weighted_sd_midpoint_ma",
  "maximum_oldest_ma",
  "minimum_youngest_ma",
  "fraction_midpoint_gt_500",
  "fraction_midpoint_gt_1000",
  "fraction_midpoint_gt_1500",
  "fraction_midpoint_gt_2000"
)

missing_fields <- setdiff(required_fields, names(x))

if (length(missing_fields) > 0L) {
  stop(
    "Missing required fields: ",
    paste(missing_fields, collapse = ", ")
  )
}

if (nrow(x) != 13920L) {
  stop("Expected 13,920 polygons; found ", nrow(x))
}

if (!identical(st_crs(x)$epsg, 4326L)) {
  stop("Expected EPSG:4326; found ", st_crs(x)$epsg)
}

resolved_flag <- x$resolved %in% c(
  TRUE, 1, "1", "TRUE", "true"
)

x <- x %>%
  mutate(
    resolved_flag = resolved_flag,
    age_duration_ma = if_else(
      resolved_flag,
      maximum_oldest_ma - minimum_youngest_ma,
      NA_real_
    )
  )

invalid_geometry <- !st_is_valid(x)
empty_geometry <- st_is_empty(x)

n_invalid <- sum(invalid_geometry, na.rm = TRUE)
n_empty <- sum(empty_geometry, na.rm = TRUE)

if (n_invalid > 0L) {
  stop("Input GeoPackage contains ", n_invalid, " invalid geometries.")
}

if (n_empty > 0L) {
  stop("Input GeoPackage contains ", n_empty, " empty geometries.")
}

cat("Calculating equal-area polygon areas...\n")

x_equal <- suppressWarnings(st_transform(x, 6933))

polygon_area_km2 <- as.numeric(st_area(x_equal)) / 1e6

surface_points <- suppressWarnings(
  st_point_on_surface(x_equal)
)

surface_points <- st_transform(surface_points, 4326)
surface_coordinates <- st_coordinates(surface_points)

x <- x %>%
  mutate(
    polygon_row = row_number(),
    polygon_area_km2 = polygon_area_km2,
    surface_lon = surface_coordinates[, 1],
    surface_lat = surface_coordinates[, 2]
  )

resolved_rows <- sum(x$resolved_flag, na.rm = TRUE)
unresolved_rows <- sum(!x$resolved_flag, na.rm = TRUE)

if (resolved_rows != 13307L) {
  stop("Expected 13,307 resolved polygons; found ", resolved_rows)
}

if (unresolved_rows != 613L) {
  stop("Expected 613 unresolved polygons; found ", unresolved_rows)
}

total_area_km2 <- sum(x$polygon_area_km2, na.rm = TRUE)

resolved_area_km2 <- sum(
  x$polygon_area_km2[x$resolved_flag],
  na.rm = TRUE
)

resolved_area_fraction <- resolved_area_km2 / total_area_km2

cat("Preparing QC summaries...\n")

overall_qc <- tibble(
  metric = c(
    "feature_count",
    "resolved_polygon_rows",
    "unresolved_polygon_rows",
    "resolved_polygon_fraction",
    "total_polygon_area_km2",
    "resolved_polygon_area_km2",
    "unresolved_polygon_area_km2",
    "resolved_area_fraction",
    "invalid_geometry_count",
    "empty_geometry_count",
    "output_crs_epsg"
  ),
  value = c(
    nrow(x),
    resolved_rows,
    unresolved_rows,
    resolved_rows / nrow(x),
    total_area_km2,
    resolved_area_km2,
    total_area_km2 - resolved_area_km2,
    resolved_area_fraction,
    n_invalid,
    n_empty,
    st_crs(x)$epsg
  )
)

resolution_area_summary <- x %>%
  st_drop_geometry() %>%
  group_by(
    resolution_method,
    resolved_flag,
    confidence_tier
  ) %>%
  summarise(
    n_polygon_rows = n(),
    n_unique_runo = n_distinct(RUNO, na.rm = TRUE),
    area_km2 = sum(polygon_area_km2, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    polygon_fraction = n_polygon_rows / nrow(x),
    area_fraction = area_km2 / total_area_km2
  ) %>%
  arrange(desc(resolved_flag), desc(area_km2))

group_area_summary <- x %>%
  st_drop_geometry() %>%
  group_by(GROUP, resolved_flag) %>%
  summarise(
    n_polygon_rows = n(),
    n_unique_runo = n_distinct(RUNO, na.rm = TRUE),
    area_km2 = sum(polygon_area_km2, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  group_by(GROUP) %>%
  mutate(
    group_total_area_km2 = sum(area_km2),
    area_fraction_within_group = area_km2 / group_total_area_km2
  ) %>%
  ungroup() %>%
  arrange(GROUP, desc(resolved_flag))

unresolved_features <- x %>%
  filter(!resolved_flag) %>%
  st_drop_geometry() %>%
  select(
    polygon_row,
    RUNO,
    GROUP,
    resolution_method,
    confidence_tier,
    polygon_area_km2,
    surface_lon,
    surface_lat,
    n_entities,
    n_default_entities,
    n_complete_default,
    percent_weight_sum
  ) %>%
  arrange(
    resolution_method,
    desc(polygon_area_km2),
    RUNO
  )

special_runo_summary <- x %>%
  filter(
    RUNO %in% c(0, 6410, 6411) |
      !resolved_flag
  ) %>%
  st_drop_geometry() %>%
  group_by(
    RUNO,
    GROUP,
    resolution_method
  ) %>%
  summarise(
    n_polygon_rows = n(),
    area_km2 = sum(polygon_area_km2, na.rm = TRUE),
    minimum_lon = min(surface_lon, na.rm = TRUE),
    maximum_lon = max(surface_lon, na.rm = TRUE),
    minimum_lat = min(surface_lat, na.rm = TRUE),
    maximum_lat = max(surface_lat, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(RUNO, GROUP)

age_distribution_summary <- bind_rows(
  tibble(
    variable = "weighted_mean_midpoint_ma",
    values = list(x$weighted_mean_midpoint_ma[x$resolved_flag])
  ),
  tibble(
    variable = "weighted_sd_midpoint_ma",
    values = list(x$weighted_sd_midpoint_ma[x$resolved_flag])
  ),
  tibble(
    variable = "age_duration_ma",
    values = list(x$age_duration_ma[x$resolved_flag])
  )
) %>%
  rowwise() %>%
  transmute(
    variable,
    n_nonmissing = sum(is.finite(values)),
    minimum = min(values, na.rm = TRUE),
    p05 = unname(quantile(values, 0.05, na.rm = TRUE)),
    p25 = unname(quantile(values, 0.25, na.rm = TRUE)),
    median = unname(quantile(values, 0.50, na.rm = TRUE)),
    mean = mean(values, na.rm = TRUE),
    p75 = unname(quantile(values, 0.75, na.rm = TRUE)),
    p95 = unname(quantile(values, 0.95, na.rm = TRUE)),
    maximum = max(values, na.rm = TRUE)
  ) %>%
  ungroup()

write_csv(
  overall_qc,
  file.path(output_dir, "spatial_qc_summary.csv")
)

write_csv(
  resolution_area_summary,
  file.path(output_dir, "resolution_area_summary.csv")
)

write_csv(
  group_area_summary,
  file.path(output_dir, "group_area_summary.csv")
)

write_csv(
  unresolved_features,
  file.path(output_dir, "unresolved_feature_locations.csv")
)

write_csv(
  special_runo_summary,
  file.path(output_dir, "special_runo_spatial_summary.csv")
)

write_csv(
  age_distribution_summary,
  file.path(output_dir, "age_distribution_summary.csv")
)

cat("Writing unresolved spatial layers...\n")

qc_gpkg <- file.path(
  output_dir,
  "nrcan_age_spatial_qc_layers.gpkg"
)

if (file.exists(qc_gpkg)) {
  file.remove(qc_gpkg)
}

write_layer <- function(object, layer_name) {
  if (nrow(object) == 0L) {
    warning("Skipping empty layer: ", layer_name)
    return(invisible(NULL))
  }

  st_write(
    object,
    qc_gpkg,
    layer = layer_name,
    append = file.exists(qc_gpkg),
    quiet = TRUE
  )
}

write_layer(
  filter(x, !resolved_flag),
  "unresolved_all"
)

write_layer(
  filter(x, RUNO == 0),
  "runo_0"
)

write_layer(
  filter(
    x,
    resolution_method == "unresolved_no_entity"
  ),
  "unresolved_no_entity"
)

write_layer(
  filter(
    x,
    resolution_method == "unresolved_no_age"
  ),
  "unresolved_no_age"
)

write_layer(
  filter(
    x,
    resolution_method ==
      "unresolved_multiple_without_weights"
  ),
  "unresolved_multiple_no_weights"
)

base_theme <- theme_void() +
  theme(
    legend.position = "bottom",
    legend.title = element_text(size = 9),
    legend.text = element_text(size = 8),
    plot.title = element_text(size = 13, face = "bold"),
    plot.subtitle = element_text(size = 9)
  )

save_discrete_map <- function(
  background,
  overlay,
  fill_field,
  title,
  subtitle,
  filename
) {
  plot_object <- ggplot() +
    geom_sf(
      data = background,
      fill = "grey94",
      colour = NA
    ) +
    geom_sf(
      data = overlay,
      aes(fill = .data[[fill_field]]),
      colour = NA
    ) +
    scale_fill_viridis_d(
      na.value = "grey70"
    ) +
    coord_sf(
      xlim = c(-180, 180),
      ylim = c(-85, 85),
      expand = FALSE
    ) +
    labs(
      title = title,
      subtitle = subtitle,
      fill = fill_field
    ) +
    base_theme

  ggsave(
    file.path(output_dir, filename),
    plot_object,
    width = 14,
    height = 7,
    dpi = 220
  )
}

save_continuous_map <- function(
  data,
  fill_field,
  title,
  subtitle,
  filename
) {
  plot_object <- ggplot(data) +
    geom_sf(
      aes(fill = .data[[fill_field]]),
      colour = NA
    ) +
    scale_fill_viridis_c(
      na.value = "grey90"
    ) +
    coord_sf(
      xlim = c(-180, 180),
      ylim = c(-85, 85),
      expand = FALSE
    ) +
    labs(
      title = title,
      subtitle = subtitle,
      fill = fill_field
    ) +
    base_theme

  ggsave(
    file.path(output_dir, filename),
    plot_object,
    width = 14,
    height = 7,
    dpi = 220
  )
}

cat("Creating spatial QC maps...\n")

save_discrete_map(
  x,
  filter(x, !resolved_flag),
  "resolution_method",
  "Unresolved NRCan geological-age polygons",
  paste0(
    unresolved_rows,
    " of ",
    nrow(x),
    " polygons; ",
    sprintf("%.3f", 100 * (1 - resolved_area_fraction)),
    "% of mapped area"
  ),
  "01_unresolved_world.png"
)

save_discrete_map(
  x,
  filter(x, RUNO == 0),
  "GROUP",
  "Spatial distribution of RUNO 0",
  "Database-free background or unassigned polygons",
  "02_runo0_world.png"
)

save_discrete_map(
  x,
  filter(
    x,
    resolution_method == "unresolved_no_age"
  ),
  "GROUP",
  "Polygons with no recoverable geological age",
  "Fourteen RUNO units retained as unresolved",
  "03_unresolved_no_age_world.png"
)

save_discrete_map(
  x,
  filter(
    x,
    resolution_method ==
      "unresolved_multiple_without_weights"
  ),
  "GROUP",
  "Multiple-age entities without reliable weights",
  "Strict main analysis retains these units as unresolved",
  "04_unresolved_multiple_world.png"
)

save_discrete_map(
  x,
  filter(x, resolved_flag),
  "confidence_tier",
  "NRCan geological-age resolution confidence",
  "Confidence reflects database matching and entity resolution",
  "05_confidence_tier_world.png"
)

save_continuous_map(
  x,
  "weighted_mean_midpoint_ma",
  "Geological-age midpoint",
  "Weighted midpoint in Ma; unresolved polygons shown in grey",
  "06_geological_midpoint_world.png"
)

save_continuous_map(
  x,
  "age_duration_ma",
  "Geological-age interval duration",
  "Maximum oldest age minus minimum youngest age, in Ma",
  "07_age_duration_world.png"
)

cat("\n========================================\n")
cat("NRCan spatial QC complete\n")
cat("========================================\n")

print(overall_qc, n = Inf)

cat("\nResolution and area summary:\n")
print(resolution_area_summary, n = Inf)

cat("\nAge distributions:\n")
print(age_distribution_summary, n = Inf)

cat("\nOutputs saved to:\n")
cat(output_dir, "\n")
