#!/usr/bin/env Rscript

options(stringsAsFactors = FALSE)

suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(readr)
})

input_gpkg <- paste0(
  "outputs/nrcan_of5529/final_age_crosswalk/",
  "roxworld_age_wgs84.gpkg"
)

output_dir <- "outputs/nrcan_of5529/target_region_qc"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

cat("Reading final geological-age polygons...\n")

x <- st_read(
  input_gpkg,
  layer = "roxworld_age",
  quiet = TRUE
)

x <- x %>%
  mutate(
    resolved_flag = resolved %in% c(
      TRUE, 1, "1", "TRUE", "true"
    ),
    polygon_row = row_number()
  )

if (nrow(x) != 13920L) {
  stop("Expected 13,920 polygons; found ", nrow(x))
}

if (!identical(st_crs(x)$epsg, 4326L)) {
  stop("Expected EPSG:4326.")
}

x_equal <- suppressWarnings(st_transform(x, 6933))

x$polygon_area_km2 <- as.numeric(
  st_area(x_equal)
) / 1e6

unresolved <- x %>%
  filter(!resolved_flag)

cat("Defining diagnostic target regions...\n")

# These are diagnostic windows, not formal biogeographic boundaries.
himalaya_box <- st_as_sfc(
  st_bbox(
    c(
      xmin = 65,
      ymin = 20,
      xmax = 100,
      ymax = 40
    ),
    crs = st_crs(4326)
  )
)

south_asia_box <- st_as_sfc(
  st_bbox(
    c(
      xmin = 60,
      ymin = 5,
      xmax = 110,
      ymax = 40
    ),
    crs = st_crs(4326)
  )
)

focal_point <- st_sfc(
  st_point(c(80.8, 29.9)),
  crs = 4326
)

region_objects <- list(
  himalaya_diagnostic_box = himalaya_box,
  south_asia_diagnostic_box = south_asia_box
)

summarise_region <- function(region_name, region_geometry) {

  intersects_all <- lengths(
    st_intersects(x, region_geometry)
  ) > 0

  intersects_unresolved <- lengths(
    st_intersects(unresolved, region_geometry)
  ) > 0

  all_region <- x[intersects_all, ]
  unresolved_region <- unresolved[
    intersects_unresolved,
  ]

  tibble(
    region = region_name,
    xmin = st_bbox(region_geometry)[["xmin"]],
    ymin = st_bbox(region_geometry)[["ymin"]],
    xmax = st_bbox(region_geometry)[["xmax"]],
    ymax = st_bbox(region_geometry)[["ymax"]],
    intersecting_polygon_rows = nrow(all_region),
    intersecting_unique_runo = n_distinct(
      all_region$RUNO,
      na.rm = TRUE
    ),
    unresolved_intersecting_polygon_rows =
      nrow(unresolved_region),
    unresolved_intersecting_unique_runo =
      n_distinct(
        unresolved_region$RUNO,
        na.rm = TRUE
      ),
    unresolved_full_polygon_area_km2 = sum(
      unresolved_region$polygon_area_km2,
      na.rm = TRUE
    )
  )
}

region_summary <- bind_rows(
  lapply(
    names(region_objects),
    function(region_name) {
      summarise_region(
        region_name,
        region_objects[[region_name]]
      )
    }
  )
)

region_unresolved_details <- bind_rows(
  lapply(
    names(region_objects),
    function(region_name) {

      region_geometry <- region_objects[[region_name]]

      keep <- lengths(
        st_intersects(
          unresolved,
          region_geometry
        )
      ) > 0

      unresolved[keep, ] %>%
        st_drop_geometry() %>%
        transmute(
          region = region_name,
          polygon_row,
          RUNO,
          GROUP,
          resolution_method,
          confidence_tier,
          polygon_area_km2,
          n_entities,
          n_default_entities,
          n_complete_default,
          percent_weight_sum
        )
    }
  )
) %>%
  arrange(
    region,
    desc(polygon_area_km2),
    RUNO
  )

cat("Checking focal point geology...\n")

focal_sf <- st_sf(
  diagnostic_location = "high_Sr_residual_focus",
  longitude = 80.8,
  latitude = 29.9,
  geometry = focal_point
)

focal_match <- st_join(
  focal_sf,
  x %>%
    select(
      RUNO,
      GROUP,
      resolved_flag,
      resolution_method,
      confidence_tier,
      weighted_mean_midpoint_ma,
      weighted_sd_midpoint_ma,
      maximum_oldest_ma,
      minimum_youngest_ma,
      fraction_midpoint_gt_500,
      fraction_midpoint_gt_1000,
      fraction_midpoint_gt_1500,
      fraction_midpoint_gt_2000
    ),
  join = st_intersects,
  left = TRUE
)

focal_match_table <- focal_match %>%
  st_drop_geometry()

cat("Calculating distance to unresolved polygons...\n")

distance_matrix <- st_distance(
  focal_point,
  unresolved
)

distance_km <- as.numeric(
  distance_matrix[1, ]
) / 1000

nearest_order <- order(distance_km)

nearest_n <- min(
  20L,
  length(nearest_order)
)

nearest_unresolved <- unresolved[
  nearest_order[seq_len(nearest_n)],
] %>%
  st_drop_geometry() %>%
  mutate(
    distance_to_focal_km =
      distance_km[
        nearest_order[seq_len(nearest_n)]
      ]
  ) %>%
  select(
    polygon_row,
    RUNO,
    GROUP,
    resolution_method,
    polygon_area_km2,
    distance_to_focal_km,
    n_entities,
    n_default_entities,
    n_complete_default,
    percent_weight_sum
  ) %>%
  arrange(distance_to_focal_km)

cat("Summarising RUNO 0 polygon sizes...\n")

runo0 <- x %>%
  filter(RUNO == 0)

runo0_area_quantiles <- tibble(
  statistic = c(
    "n_polygons",
    "total_area_km2",
    "minimum_area_km2",
    "p05_area_km2",
    "p25_area_km2",
    "median_area_km2",
    "mean_area_km2",
    "p75_area_km2",
    "p95_area_km2",
    "maximum_area_km2",
    "n_lt_1_km2",
    "n_lt_10_km2",
    "n_lt_100_km2",
    "n_lt_1000_km2",
    "n_ge_10000_km2"
  ),
  value = c(
    nrow(runo0),
    sum(runo0$polygon_area_km2),
    min(runo0$polygon_area_km2),
    unname(quantile(
      runo0$polygon_area_km2,
      0.05
    )),
    unname(quantile(
      runo0$polygon_area_km2,
      0.25
    )),
    median(runo0$polygon_area_km2),
    mean(runo0$polygon_area_km2),
    unname(quantile(
      runo0$polygon_area_km2,
      0.75
    )),
    unname(quantile(
      runo0$polygon_area_km2,
      0.95
    )),
    max(runo0$polygon_area_km2),
    sum(runo0$polygon_area_km2 < 1),
    sum(runo0$polygon_area_km2 < 10),
    sum(runo0$polygon_area_km2 < 100),
    sum(runo0$polygon_area_km2 < 1000),
    sum(runo0$polygon_area_km2 >= 10000)
  )
)

largest_runo0 <- runo0 %>%
  arrange(desc(polygon_area_km2)) %>%
  slice_head(n = 50) %>%
  st_drop_geometry() %>%
  select(
    polygon_row,
    RUNO,
    GROUP,
    polygon_area_km2,
    AREA,
    PERIMETER
  )

largest_unresolved <- unresolved %>%
  arrange(desc(polygon_area_km2)) %>%
  slice_head(n = 75) %>%
  st_drop_geometry() %>%
  select(
    polygon_row,
    RUNO,
    GROUP,
    resolution_method,
    polygon_area_km2,
    n_entities,
    n_default_entities,
    n_complete_default,
    percent_weight_sum
  )

write_csv(
  region_summary,
  file.path(
    output_dir,
    "target_region_summary.csv"
  )
)

write_csv(
  region_unresolved_details,
  file.path(
    output_dir,
    "target_region_unresolved_details.csv"
  )
)

write_csv(
  focal_match_table,
  file.path(
    output_dir,
    "focal_point_geology.csv"
  )
)

write_csv(
  nearest_unresolved,
  file.path(
    output_dir,
    "nearest_unresolved_to_focal.csv"
  )
)

write_csv(
  runo0_area_quantiles,
  file.path(
    output_dir,
    "runo0_area_distribution.csv"
  )
)

write_csv(
  largest_runo0,
  file.path(
    output_dir,
    "largest_runo0_polygons.csv"
  )
)

write_csv(
  largest_unresolved,
  file.path(
    output_dir,
    "largest_unresolved_polygons.csv"
  )
)

target_gpkg <- file.path(
  output_dir,
  "target_region_qc_layers.gpkg"
)

if (file.exists(target_gpkg)) {
  file.remove(target_gpkg)
}

st_write(
  unresolved,
  target_gpkg,
  layer = "unresolved_all",
  quiet = TRUE
)

st_write(
  focal_sf,
  target_gpkg,
  layer = "focal_point",
  append = TRUE,
  quiet = TRUE
)

st_write(
  st_sf(
    region = "himalaya_diagnostic_box",
    geometry = himalaya_box
  ),
  target_gpkg,
  layer = "himalaya_box",
  append = TRUE,
  quiet = TRUE
)

st_write(
  st_sf(
    region = "south_asia_diagnostic_box",
    geometry = south_asia_box
  ),
  target_gpkg,
  layer = "south_asia_box",
  append = TRUE,
  quiet = TRUE
)

cat("\n========================================\n")
cat("TARGET-REGION QC COMPLETE\n")
cat("========================================\n")

cat("\nRegion summary:\n")
print(region_summary, n = Inf, width = Inf)

cat("\nFocal-point geological match:\n")
print(focal_match_table, n = Inf, width = Inf)

cat("\nNearest unresolved polygons:\n")
print(
  nearest_unresolved,
  n = min(20L, nrow(nearest_unresolved)),
  width = Inf
)

cat("\nRUNO 0 area distribution:\n")
print(runo0_area_quantiles, n = Inf)

cat("\nOutputs saved to:\n")
cat(output_dir, "\n")
