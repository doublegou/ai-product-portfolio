#!/usr/bin/env Rscript

options(
  stringsAsFactors = FALSE,
  warn = 1
)

suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(readr)
  library(tibble)
})

output_dir <- paste0(
  "outputs/nrcan_age_hydrobasins_l6/",
  "ar_pilot"
)

dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

path_file <- file.path(
  output_dir,
  "hybas_ar_shapefile_path.txt"
)

age_gpkg <- paste0(
  "outputs/nrcan_of5529/final_age_crosswalk/",
  "roxworld_age_wgs84.gpkg"
)

network_rds <- paste0(
  "/home/zhangmeng/projects/sr_global/",
  "data_processed/global/glim_l6_by_region/",
  "l6_glim_local_upstream_ar.rds"
)

expected_basin_count <- 849L


to_key <- function(values) {

  numeric_values <- suppressWarnings(
    as.numeric(values)
  )

  result <- ifelse(
    is.na(numeric_values),
    NA_character_,
    sprintf("%.0f", numeric_values)
  )

  result
}


safe_min <- function(values) {

  values <- values[
    is.finite(values)
  ]

  if (length(values) == 0L) {
    return(NA_real_)
  }

  min(values)
}


safe_max <- function(values) {

  values <- values[
    is.finite(values)
  ]

  if (length(values) == 0L) {
    return(NA_real_)
  }

  max(values)
}


equal_with_na <- function(first, second) {

  (
    is.na(first) &
      is.na(second)
  ) |
    (
      !is.na(first) &
        !is.na(second) &
        first == second
    )
}


required_files <- c(
  path_file,
  age_gpkg,
  network_rds
)

missing_files <- required_files[
  !file.exists(required_files)
]

if (length(missing_files) > 0L) {
  stop(
    "Missing required files: ",
    paste(missing_files, collapse = "; ")
  )
}


hybas_shp <- trimws(
  readLines(
    path_file,
    warn = FALSE
  )[1]
)

if (!file.exists(hybas_shp)) {
  stop(
    "HydroBASINS shapefile does not exist: ",
    hybas_shp
  )
}


cat("Reading HydroBASINS AR L6 geometry...\n")

basins <- st_read(
  hybas_shp,
  quiet = TRUE,
  stringsAsFactors = FALSE
)

required_basin_fields <- c(
  "HYBAS_ID",
  "NEXT_DOWN",
  "SUB_AREA",
  "UP_AREA"
)

missing_basin_fields <- setdiff(
  required_basin_fields,
  names(basins)
)

if (length(missing_basin_fields) > 0L) {
  stop(
    "Missing HydroBASINS fields: ",
    paste(missing_basin_fields, collapse = ", ")
  )
}

if (nrow(basins) != expected_basin_count) {
  stop(
    "Expected ",
    expected_basin_count,
    " Asia L6 basins; found ",
    nrow(basins)
  )
}

basins$HYBAS_KEY <- to_key(
  basins$HYBAS_ID
)

if (
  any(is.na(basins$HYBAS_KEY)) ||
  anyDuplicated(basins$HYBAS_KEY) > 0L
) {
  stop(
    "Missing or duplicated HYBAS_ID in shapefile."
  )
}


cat("Reading verified HydroBASINS network table...\n")

network <- readRDS(
  network_rds
)

if (inherits(network, "sf")) {
  network <- st_drop_geometry(network)
}

network <- as_tibble(
  network
)

missing_network_fields <- setdiff(
  required_basin_fields,
  names(network)
)

if (length(missing_network_fields) > 0L) {
  stop(
    "Missing network fields: ",
    paste(missing_network_fields, collapse = ", ")
  )
}

if (nrow(network) != expected_basin_count) {
  stop(
    "Expected ",
    expected_basin_count,
    " network rows; found ",
    nrow(network)
  )
}

network$HYBAS_KEY <- to_key(
  network$HYBAS_ID
)

if (
  any(is.na(network$HYBAS_KEY)) ||
  anyDuplicated(network$HYBAS_KEY) > 0L
) {
  stop(
    "Missing or duplicated HYBAS_ID in network RDS."
  )
}

if (
  !setequal(
    basins$HYBAS_KEY,
    network$HYBAS_KEY
  )
) {
  stop(
    "Shapefile and network HYBAS_ID sets differ."
  )
}


# Reorder geometry to exactly match the verified network table.
basin_order <- match(
  network$HYBAS_KEY,
  basins$HYBAS_KEY
)

basins <- basins[
  basin_order,
]

if (
  !identical(
    basins$HYBAS_KEY,
    network$HYBAS_KEY
  )
) {
  stop(
    "Failed to align basin geometry to network order."
  )
}


shape_next <- to_key(
  basins$NEXT_DOWN
)

network_next <- to_key(
  network$NEXT_DOWN
)

next_down_disagreements <- sum(
  !equal_with_na(
    shape_next,
    network_next
  ),
  na.rm = TRUE
)

if (next_down_disagreements > 0L) {
  stop(
    "NEXT_DOWN disagreement count: ",
    next_down_disagreements
  )
}


sub_area_difference <- abs(
  as.numeric(basins$SUB_AREA) -
    as.numeric(network$SUB_AREA)
)

up_area_difference <- abs(
  as.numeric(basins$UP_AREA) -
    as.numeric(network$UP_AREA)
)


cat("Validating basin geometries...\n")

basins <- st_make_valid(
  basins
)

invalid_basin_count <- sum(
  !st_is_valid(basins),
  na.rm = TRUE
)

empty_basin_count <- sum(
  st_is_empty(basins),
  na.rm = TRUE
)

if (
  invalid_basin_count > 0L ||
  empty_basin_count > 0L
) {
  stop(
    "Invalid basins: ",
    invalid_basin_count,
    "; empty basins: ",
    empty_basin_count
  )
}


cat("Reading NRCan geological-age polygons...\n")

age <- st_read(
  age_gpkg,
  layer = "roxworld_age",
  quiet = TRUE
)

required_age_fields <- c(
  "RUNO",
  "resolved",
  "weighted_mean_midpoint_ma",
  "weighted_sd_midpoint_ma",
  "maximum_oldest_ma",
  "minimum_youngest_ma",
  "fraction_midpoint_gt_500",
  "fraction_midpoint_gt_1000",
  "fraction_midpoint_gt_1500",
  "fraction_midpoint_gt_2000"
)

missing_age_fields <- setdiff(
  required_age_fields,
  names(age)
)

if (length(missing_age_fields) > 0L) {
  stop(
    "Missing geological-age fields: ",
    paste(missing_age_fields, collapse = ", ")
  )
}

if (st_crs(age)$epsg != 4326L) {
  age <- st_transform(
    age,
    4326
  )
}

if (st_crs(basins)$epsg != 4326L) {
  basins <- st_transform(
    basins,
    4326
  )
}


resolved_text <- tolower(
  as.character(age$resolved)
)

age$resolved_flag <- resolved_text %in% c(
  "true",
  "1",
  "t"
)

age <- age %>%
  select(
    RUNO,
    resolved_flag,
    weighted_mean_midpoint_ma,
    weighted_sd_midpoint_ma,
    maximum_oldest_ma,
    minimum_youngest_ma,
    fraction_midpoint_gt_500,
    fraction_midpoint_gt_1000,
    fraction_midpoint_gt_1500,
    fraction_midpoint_gt_2000
  )


cat("Spatially filtering geological polygons to AR...\n")

age_asia <- st_filter(
  age,
  basins,
  .predicate = st_intersects
)

if (nrow(age_asia) == 0L) {
  stop(
    "No geological-age polygons intersect Asia basins."
  )
}

cat(
  "AR geological polygons retained: ",
  nrow(age_asia),
  "\n",
  sep = ""
)


cat("Transforming to EPSG:6933 for area calculations...
")

basins_equal <- st_transform(
  basins,
  6933
)

age_equal <- st_transform(
  age_asia,
  6933
)

cat("Repairing projected geometries before intersection...
")

basins_equal <- suppressWarnings(
  st_buffer(
    st_make_valid(
      basins_equal
    ),
    dist = 0
  )
)

age_equal <- suppressWarnings(
  st_buffer(
    st_make_valid(
      age_equal
    ),
    dist = 0
  )
)

empty_basin_count_projected <- sum(
  st_is_empty(
    basins_equal
  )
)

if (empty_basin_count_projected > 0L) {
  stop(
    "Projected geometry repair produced ",
    empty_basin_count_projected,
    " empty basin geometries."
  )
}

empty_age_geometry <- st_is_empty(
  age_equal
)

if (any(empty_age_geometry)) {

  cat(
    "Dropping ",
    sum(empty_age_geometry),
    " empty geological geometries after repair.
",
    sep = ""
  )

  age_equal <- age_equal[
    !empty_age_geometry,
  ]
}

invalid_basin_count_projected <- sum(
  !st_is_valid(
    basins_equal
  )
)

invalid_age_count_projected <- sum(
  !st_is_valid(
    age_equal
  )
)

if (
  invalid_basin_count_projected > 0L ||
  invalid_age_count_projected > 0L
) {
  stop(
    "Invalid projected geometries remain. ",
    "Basins: ",
    invalid_basin_count_projected,
    "; geology: ",
    invalid_age_count_projected
  )
}

basin_area <- tibble(
  HYBAS_KEY = basins_equal$HYBAS_KEY,
  basin_geometry_area_km2 =
    as.numeric(
      st_area(basins_equal)
    ) / 1e6
)


cat("Intersecting geological polygons with Asia L6 basins...\n")

basin_overlay_geometry <- basins_equal %>%
  select(HYBAS_KEY)

overlay <- suppressWarnings(
  st_intersection(
    basin_overlay_geometry,
    age_equal
  )
)

if (nrow(overlay) == 0L) {
  stop(
    "The basin-geology intersection produced zero rows."
  )
}

overlay$intersection_area_km2 <-
  as.numeric(
    st_area(overlay)
  ) / 1e6

overlay <- overlay %>%
  filter(
    is.finite(intersection_area_km2),
    intersection_area_km2 > 0
  )

overlay_table <- st_drop_geometry(
  overlay
)


cat("Preparing area-weighted geological-age components...\n")

overlay_table <- overlay_table %>%
  mutate(
    age_value_valid =
      resolved_flag &
      is.finite(
        weighted_mean_midpoint_ma
      ),

    within_age_sd = ifelse(
      is.finite(
        weighted_sd_midpoint_ma
      ),
      weighted_sd_midpoint_ma,
      0
    ),

    age_valid_area_km2 = ifelse(
      age_value_valid,
      intersection_area_km2,
      0
    ),

    age_mean_area = ifelse(
      age_value_valid,
      intersection_area_km2 *
        weighted_mean_midpoint_ma,
      0
    ),

    age_second_moment_area = ifelse(
      age_value_valid,
      intersection_area_km2 *
        (
          weighted_mean_midpoint_ma^2 +
            within_age_sd^2
        ),
      0
    ),

    gt500_valid_area_km2 = ifelse(
      age_value_valid &
        is.finite(
          fraction_midpoint_gt_500
        ),
      intersection_area_km2,
      0
    ),

    gt500_area = ifelse(
      age_value_valid &
        is.finite(
          fraction_midpoint_gt_500
        ),
      intersection_area_km2 *
        fraction_midpoint_gt_500,
      0
    ),

    gt1000_valid_area_km2 = ifelse(
      age_value_valid &
        is.finite(
          fraction_midpoint_gt_1000
        ),
      intersection_area_km2,
      0
    ),

    gt1000_area = ifelse(
      age_value_valid &
        is.finite(
          fraction_midpoint_gt_1000
        ),
      intersection_area_km2 *
        fraction_midpoint_gt_1000,
      0
    ),

    gt1500_valid_area_km2 = ifelse(
      age_value_valid &
        is.finite(
          fraction_midpoint_gt_1500
        ),
      intersection_area_km2,
      0
    ),

    gt1500_area = ifelse(
      age_value_valid &
        is.finite(
          fraction_midpoint_gt_1500
        ),
      intersection_area_km2 *
        fraction_midpoint_gt_1500,
      0
    ),

    gt2000_valid_area_km2 = ifelse(
      age_value_valid &
        is.finite(
          fraction_midpoint_gt_2000
        ),
      intersection_area_km2,
      0
    ),

    gt2000_area = ifelse(
      age_value_valid &
        is.finite(
          fraction_midpoint_gt_2000
        ),
      intersection_area_km2 *
        fraction_midpoint_gt_2000,
      0
    )
  )


cat("Aggregating local geological-age predictors by HYBAS_ID...\n")

local_age_summary <- overlay_table %>%
  group_by(HYBAS_KEY) %>%
  summarise(
    local_geo_age_intersection_count = n(),

    local_geo_age_mapped_area_km2 = sum(
      intersection_area_km2,
      na.rm = TRUE
    ),

    local_geo_age_resolved_area_km2 = sum(
      age_valid_area_km2,
      na.rm = TRUE
    ),

    local_geo_age_mean_numerator = sum(
      age_mean_area,
      na.rm = TRUE
    ),

    local_geo_age_second_numerator = sum(
      age_second_moment_area,
      na.rm = TRUE
    ),

    local_geo_gt500_valid_area_km2 = sum(
      gt500_valid_area_km2,
      na.rm = TRUE
    ),

    local_geo_gt500_area_km2 = sum(
      gt500_area,
      na.rm = TRUE
    ),

    local_geo_gt1000_valid_area_km2 = sum(
      gt1000_valid_area_km2,
      na.rm = TRUE
    ),

    local_geo_gt1000_area_km2 = sum(
      gt1000_area,
      na.rm = TRUE
    ),

    local_geo_gt1500_valid_area_km2 = sum(
      gt1500_valid_area_km2,
      na.rm = TRUE
    ),

    local_geo_gt1500_area_km2 = sum(
      gt1500_area,
      na.rm = TRUE
    ),

    local_geo_gt2000_valid_area_km2 = sum(
      gt2000_valid_area_km2,
      na.rm = TRUE
    ),

    local_geo_gt2000_area_km2 = sum(
      gt2000_area,
      na.rm = TRUE
    ),

    local_geo_age_max_oldest_ma = safe_max(
      ifelse(
        age_value_valid,
        maximum_oldest_ma,
        NA_real_
      )
    ),

    local_geo_age_min_youngest_ma = safe_min(
      ifelse(
        age_value_valid,
        minimum_youngest_ma,
        NA_real_
      )
    ),

    .groups = "drop"
  )


network_output <- network %>%
  transmute(
    region = "ar",
    HYBAS_ID,
    HYBAS_KEY,
    NEXT_DOWN,
    SUB_AREA,
    UP_AREA
  ) %>%
  left_join(
    basin_area,
    by = "HYBAS_KEY"
  ) %>%
  left_join(
    local_age_summary,
    by = "HYBAS_KEY"
  ) %>%
  mutate(
    across(
      c(
        local_geo_age_intersection_count,
        local_geo_age_mapped_area_km2,
        local_geo_age_resolved_area_km2,
        local_geo_age_mean_numerator,
        local_geo_age_second_numerator,
        local_geo_gt500_valid_area_km2,
        local_geo_gt500_area_km2,
        local_geo_gt1000_valid_area_km2,
        local_geo_gt1000_area_km2,
        local_geo_gt1500_valid_area_km2,
        local_geo_gt1500_area_km2,
        local_geo_gt2000_valid_area_km2,
        local_geo_gt2000_area_km2
      ),
      ~ coalesce(.x, 0)
    ),

    local_geo_age_unresolved_area_km2 = pmax(
      0,
      local_geo_age_mapped_area_km2 -
        local_geo_age_resolved_area_km2
    ),

    local_geo_age_mean_ma = ifelse(
      local_geo_age_resolved_area_km2 > 0,
      local_geo_age_mean_numerator /
        local_geo_age_resolved_area_km2,
      NA_real_
    ),

    local_geo_age_sd_ma = ifelse(
      local_geo_age_resolved_area_km2 > 0,
      sqrt(
        pmax(
          0,
          local_geo_age_second_numerator /
            local_geo_age_resolved_area_km2 -
            local_geo_age_mean_ma^2
        )
      ),
      NA_real_
    ),

    local_geo_frac_midpoint_gt_500 = ifelse(
      local_geo_gt500_valid_area_km2 > 0,
      local_geo_gt500_area_km2 /
        local_geo_gt500_valid_area_km2,
      NA_real_
    ),

    local_geo_frac_midpoint_gt_1000 = ifelse(
      local_geo_gt1000_valid_area_km2 > 0,
      local_geo_gt1000_area_km2 /
        local_geo_gt1000_valid_area_km2,
      NA_real_
    ),

    local_geo_frac_midpoint_gt_1500 = ifelse(
      local_geo_gt1500_valid_area_km2 > 0,
      local_geo_gt1500_area_km2 /
        local_geo_gt1500_valid_area_km2,
      NA_real_
    ),

    local_geo_frac_midpoint_gt_2000 = ifelse(
      local_geo_gt2000_valid_area_km2 > 0,
      local_geo_gt2000_area_km2 /
        local_geo_gt2000_valid_area_km2,
      NA_real_
    ),

    local_geo_age_overlay_coverage = ifelse(
      basin_geometry_area_km2 > 0,
      local_geo_age_mapped_area_km2 /
        basin_geometry_area_km2,
      NA_real_
    ),

    local_geo_age_resolved_coverage = ifelse(
      basin_geometry_area_km2 > 0,
      local_geo_age_resolved_area_km2 /
        basin_geometry_area_km2,
      NA_real_
    ),

    local_geo_age_resolved_fraction_of_overlay = ifelse(
      local_geo_age_mapped_area_km2 > 0,
      local_geo_age_resolved_area_km2 /
        local_geo_age_mapped_area_km2,
      NA_real_
    ),

    geometry_to_SUB_AREA_ratio = ifelse(
      is.finite(SUB_AREA) &
        SUB_AREA > 0,
      basin_geometry_area_km2 /
        SUB_AREA,
      NA_real_
    )
  ) %>%
  select(
    region,
    HYBAS_ID,
    HYBAS_KEY,
    NEXT_DOWN,
    SUB_AREA,
    UP_AREA,
    basin_geometry_area_km2,
    geometry_to_SUB_AREA_ratio,
    local_geo_age_intersection_count,
    local_geo_age_mapped_area_km2,
    local_geo_age_resolved_area_km2,
    local_geo_age_unresolved_area_km2,
    local_geo_age_overlay_coverage,
    local_geo_age_resolved_coverage,
    local_geo_age_resolved_fraction_of_overlay,
    local_geo_age_mean_ma,
    local_geo_age_sd_ma,
    local_geo_age_max_oldest_ma,
    local_geo_age_min_youngest_ma,
    local_geo_frac_midpoint_gt_500,
    local_geo_frac_midpoint_gt_1000,
    local_geo_frac_midpoint_gt_1500,
    local_geo_frac_midpoint_gt_2000,
    local_geo_gt500_valid_area_km2,
    local_geo_gt500_area_km2,
    local_geo_gt1000_valid_area_km2,
    local_geo_gt1000_area_km2,
    local_geo_gt1500_valid_area_km2,
    local_geo_gt1500_area_km2,
    local_geo_gt2000_valid_area_km2,
    local_geo_gt2000_area_km2
  )


if (nrow(network_output) != expected_basin_count) {
  stop(
    "Output row count changed: ",
    nrow(network_output)
  )
}

if (anyDuplicated(network_output$HYBAS_KEY) > 0L) {
  stop(
    "Duplicated HYBAS_ID in final local-age table."
  )
}


maximum_overlay_coverage <- max(
  network_output$local_geo_age_overlay_coverage,
  na.rm = TRUE
)

if (maximum_overlay_coverage > 1.10) {
  stop(
    "Severe overlay area inflation detected. ",
    "Maximum coverage ratio: ",
    maximum_overlay_coverage
  )
}


cat("Writing AR local geological-age tables...\n")

output_rds <- file.path(
  output_dir,
  "l6_nrcan_age_local_ar.rds"
)

output_csv <- file.path(
  output_dir,
  "l6_nrcan_age_local_ar.csv"
)

saveRDS(
  network_output,
  output_rds
)

write_csv(
  network_output,
  output_csv
)


basins_output <- basins %>%
  select(
    HYBAS_ID,
    NEXT_DOWN,
    SUB_AREA,
    UP_AREA,
    HYBAS_KEY
  ) %>%
  left_join(
    network_output %>%
      select(
        -HYBAS_ID,
        -NEXT_DOWN,
        -SUB_AREA,
        -UP_AREA
      ),
    by = "HYBAS_KEY"
  )

output_gpkg <- file.path(
  output_dir,
  "l6_nrcan_age_local_ar.gpkg"
)

if (file.exists(output_gpkg)) {
  file.remove(output_gpkg)
}

st_write(
  basins_output,
  output_gpkg,
  layer = "l6_nrcan_age_local_ar",
  quiet = TRUE
)


cat("Checking focal Himalayan location...\n")

focal_point <- st_as_sf(
  tibble(
    diagnostic_location =
      "high_Sr_residual_focus",
    longitude = 80.8,
    latitude = 29.9
  ),
  coords = c(
    "longitude",
    "latitude"
  ),
  crs = 4326
)

focal_result <- st_join(
  focal_point,
  basins_output %>%
    select(
      HYBAS_ID,
      NEXT_DOWN,
      SUB_AREA,
      UP_AREA,
      local_geo_age_mean_ma,
      local_geo_age_sd_ma,
      local_geo_frac_midpoint_gt_1000,
      local_geo_frac_midpoint_gt_2000,
      local_geo_age_overlay_coverage,
      local_geo_age_resolved_coverage
    ),
  join = st_intersects,
  left = TRUE
) %>%
  st_drop_geometry()

write_csv(
  focal_result,
  file.path(
    output_dir,
    "himalaya_focal_basin_local_age.csv"
  )
)


low_coverage <- network_output %>%
  arrange(
    local_geo_age_resolved_coverage
  ) %>%
  slice_head(
    n = 100
  )

write_csv(
  low_coverage,
  file.path(
    output_dir,
    "lowest_resolved_coverage_basins.csv"
  )
)


coverage_quantiles <- quantile(
  network_output$local_geo_age_resolved_coverage,
  probs = c(
    0,
    0.01,
    0.05,
    0.25,
    0.50,
    0.75,
    0.95,
    0.99,
    1
  ),
  na.rm = TRUE
)

qc <- tibble(
  metric = c(
    "region_basin_count",
    "region_age_polygon_count",
    "intersection_piece_count",
    "basins_with_any_overlay",
    "basins_with_resolved_age",
    "basins_resolved_coverage_ge_0p80",
    "basins_resolved_coverage_ge_0p90",
    "basins_resolved_coverage_ge_0p95",
    "resolved_coverage_minimum",
    "resolved_coverage_p01",
    "resolved_coverage_p05",
    "resolved_coverage_median",
    "resolved_coverage_p95",
    "resolved_coverage_p99",
    "resolved_coverage_maximum",
    "maximum_overlay_coverage",
    "overlay_coverage_gt_1p02_count",
    "NEXT_DOWN_disagreement_count",
    "maximum_SUB_AREA_difference",
    "maximum_UP_AREA_difference",
    "invalid_basin_geometry_count",
    "empty_basin_geometry_count"
  ),
  value = c(
    nrow(network_output),
    nrow(age_asia),
    nrow(overlay_table),
    sum(
      network_output$
        local_geo_age_mapped_area_km2 > 0
    ),
    sum(
      network_output$
        local_geo_age_resolved_area_km2 > 0
    ),
    sum(
      network_output$
        local_geo_age_resolved_coverage >= 0.80,
      na.rm = TRUE
    ),
    sum(
      network_output$
        local_geo_age_resolved_coverage >= 0.90,
      na.rm = TRUE
    ),
    sum(
      network_output$
        local_geo_age_resolved_coverage >= 0.95,
      na.rm = TRUE
    ),
    coverage_quantiles[1],
    coverage_quantiles[2],
    coverage_quantiles[3],
    coverage_quantiles[5],
    coverage_quantiles[7],
    coverage_quantiles[8],
    coverage_quantiles[9],
    maximum_overlay_coverage,
    sum(
      network_output$
        local_geo_age_overlay_coverage > 1.02,
      na.rm = TRUE
    ),
    next_down_disagreements,
    max(
      sub_area_difference,
      na.rm = TRUE
    ),
    max(
      up_area_difference,
      na.rm = TRUE
    ),
    invalid_basin_count,
    empty_basin_count
  )
)

write_csv(
  qc,
  file.path(
    output_dir,
    "ar_overlay_qc.csv"
  )
)


cat("\n========================================\n")
cat("AR NRCan AGE OVERLAY COMPLETE\n")
cat("========================================\n")

cat("\nQC summary:\n")
print(
  qc,
  n = Inf
)

cat("\nHimalaya focal basin:\n")
print(
  focal_result,
  n = Inf,
  width = Inf
)

cat("\nOutputs saved to:\n")
cat(output_dir, "\n")
