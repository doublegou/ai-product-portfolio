#!/usr/bin/env Rscript

options(
  stringsAsFactors = FALSE,
  warn = 1
)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(sf)
  library(tibble)
})

input_dir <- paste0(
  "outputs/nrcan_age_hydrobasins_l6/",
  "asia_pilot"
)

output_dir <- paste0(
  "outputs/nrcan_age_hydrobasins_l6/",
  "asia_upstream"
)

dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

input_rds <- file.path(
  input_dir,
  "l6_nrcan_age_local_as.rds"
)

input_gpkg <- file.path(
  input_dir,
  "l6_nrcan_age_local_as.gpkg"
)

expected_rows <- 2489L


to_key <- function(values) {

  numeric_values <- suppressWarnings(
    as.numeric(values)
  )

  ifelse(
    is.na(numeric_values),
    NA_character_,
    sprintf("%.0f", numeric_values)
  )
}


if (!file.exists(input_rds)) {
  stop(
    "Missing local-age input: ",
    input_rds
  )
}


cat("Reading Asia local geological-age table...\n")

local <- readRDS(
  input_rds
)

if (inherits(local, "sf")) {
  local <- st_drop_geometry(local)
}

local <- as_tibble(
  local
)


required_columns <- c(
  "region",
  "HYBAS_ID",
  "HYBAS_KEY",
  "NEXT_DOWN",
  "SUB_AREA",
  "UP_AREA",
  "basin_geometry_area_km2",
  "local_geo_age_mapped_area_km2",
  "local_geo_age_resolved_area_km2",
  "local_geo_age_mean_ma",
  "local_geo_age_sd_ma",
  "local_geo_gt500_valid_area_km2",
  "local_geo_gt500_area_km2",
  "local_geo_gt1000_valid_area_km2",
  "local_geo_gt1000_area_km2",
  "local_geo_gt1500_valid_area_km2",
  "local_geo_gt1500_area_km2",
  "local_geo_gt2000_valid_area_km2",
  "local_geo_gt2000_area_km2"
)

missing_columns <- setdiff(
  required_columns,
  names(local)
)

if (length(missing_columns) > 0L) {
  stop(
    "Missing required columns: ",
    paste(
      missing_columns,
      collapse = ", "
    )
  )
}


if (nrow(local) != expected_rows) {
  stop(
    "Expected ",
    expected_rows,
    " Asia basins; found ",
    nrow(local)
  )
}


local$HYBAS_KEY <- to_key(
  local$HYBAS_ID
)

if (
  any(is.na(local$HYBAS_KEY)) ||
  anyDuplicated(local$HYBAS_KEY) > 0L
) {
  stop(
    "Missing or duplicated HYBAS_ID."
  )
}


numeric_zero_columns <- c(
  "SUB_AREA",
  "basin_geometry_area_km2",
  "local_geo_age_mapped_area_km2",
  "local_geo_age_resolved_area_km2",
  "local_geo_gt500_valid_area_km2",
  "local_geo_gt500_area_km2",
  "local_geo_gt1000_valid_area_km2",
  "local_geo_gt1000_area_km2",
  "local_geo_gt1500_valid_area_km2",
  "local_geo_gt1500_area_km2",
  "local_geo_gt2000_valid_area_km2",
  "local_geo_gt2000_area_km2"
)

for (column_name in numeric_zero_columns) {

  local[[column_name]] <- as.numeric(
    local[[column_name]]
  )

  local[[column_name]][
    !is.finite(local[[column_name]])
  ] <- 0
}


resolved_area <- local$
  local_geo_age_resolved_area_km2

local_age_mean <- as.numeric(
  local$local_geo_age_mean_ma
)

local_age_sd <- as.numeric(
  local$local_geo_age_sd_ma
)

local_age_sd[
  !is.finite(local_age_sd)
] <- 0


local$local_geo_age_sum_ma_km2 <- ifelse(
  resolved_area > 0 &
    is.finite(local_age_mean),
  resolved_area *
    local_age_mean,
  0
)

local$local_geo_age_second_sum_ma2_km2 <- ifelse(
  resolved_area > 0 &
    is.finite(local_age_mean),
  resolved_area *
    (
      local_age_mean^2 +
        local_age_sd^2
    ),
  0
)


cat("Constructing HYBAS_ID -> NEXT_DOWN network...\n")

next_key <- ifelse(
  is.na(local$NEXT_DOWN) |
    local$NEXT_DOWN == 0,
  NA_character_,
  to_key(local$NEXT_DOWN)
)

id_lookup <- setNames(
  seq_len(nrow(local)),
  local$HYBAS_KEY
)

downstream_index <- unname(
  id_lookup[next_key]
)

external_downstream <- (
  !is.na(next_key) &
    is.na(downstream_index)
)

external_downstream_count <- sum(
  external_downstream
)

if (external_downstream_count > 0L) {
  stop(
    "NEXT_DOWN IDs outside Asia table: ",
    external_downstream_count
  )
}


additive_columns <- c(
  "SUB_AREA",
  "basin_geometry_area_km2",
  "local_geo_age_mapped_area_km2",
  "local_geo_age_resolved_area_km2",
  "local_geo_age_sum_ma_km2",
  "local_geo_age_second_sum_ma2_km2",
  "local_geo_gt500_valid_area_km2",
  "local_geo_gt500_area_km2",
  "local_geo_gt1000_valid_area_km2",
  "local_geo_gt1000_area_km2",
  "local_geo_gt1500_valid_area_km2",
  "local_geo_gt1500_area_km2",
  "local_geo_gt2000_valid_area_km2",
  "local_geo_gt2000_area_km2"
)

upstream_columns <- c(
  "upstream_SUB_AREA_sum_km2",
  "upstream_geometry_area_km2",
  "up_geo_age_mapped_area_km2",
  "up_geo_age_resolved_area_km2",
  "up_geo_age_sum_ma_km2",
  "up_geo_age_second_sum_ma2_km2",
  "up_geo_gt500_valid_area_km2",
  "up_geo_gt500_area_km2",
  "up_geo_gt1000_valid_area_km2",
  "up_geo_gt1000_area_km2",
  "up_geo_gt1500_valid_area_km2",
  "up_geo_gt1500_area_km2",
  "up_geo_gt2000_valid_area_km2",
  "up_geo_gt2000_area_km2"
)

accumulated <- as.matrix(
  local[
    ,
    additive_columns,
    drop = FALSE
  ]
)

storage.mode(
  accumulated
) <- "double"

colnames(
  accumulated
) <- upstream_columns


indegree <- tabulate(
  downstream_index[
    !is.na(downstream_index)
  ],
  nbins = nrow(local)
)

queue <- which(
  indegree == 0L
)

queue_position <- 1L

processed <- logical(
  nrow(local)
)


cat("Accumulating local geological-age components downstream...\n")

while (queue_position <= length(queue)) {

  current <- queue[
    queue_position
  ]

  queue_position <- queue_position + 1L

  processed[current] <- TRUE

  downstream <- downstream_index[
    current
  ]

  if (!is.na(downstream)) {

    accumulated[
      downstream,
    ] <- accumulated[
      downstream,
    ] + accumulated[
      current,
    ]

    indegree[downstream] <-
      indegree[downstream] - 1L

    if (indegree[downstream] == 0L) {

      queue <- c(
        queue,
        downstream
      )
    }
  }
}


unprocessed_count <- sum(
  !processed
)

if (unprocessed_count > 0L) {
  stop(
    "Network accumulation failed. ",
    "Unprocessed basins: ",
    unprocessed_count
  )
}


upstream_table <- as_tibble(
  accumulated
)


cat("Deriving upstream geological-age predictors...\n")

result <- bind_cols(
  local %>%
    select(
      -local_geo_age_sum_ma_km2,
      -local_geo_age_second_sum_ma2_km2
    ),
  upstream_table
) %>%
  mutate(
    up_geo_age_unresolved_area_km2 = pmax(
      0,
      up_geo_age_mapped_area_km2 -
        up_geo_age_resolved_area_km2
    ),

    up_geo_age_mean_ma = ifelse(
      up_geo_age_resolved_area_km2 > 0,
      up_geo_age_sum_ma_km2 /
        up_geo_age_resolved_area_km2,
      NA_real_
    ),

    up_geo_age_sd_ma = ifelse(
      up_geo_age_resolved_area_km2 > 0,
      sqrt(
        pmax(
          0,
          up_geo_age_second_sum_ma2_km2 /
            up_geo_age_resolved_area_km2 -
            up_geo_age_mean_ma^2
        )
      ),
      NA_real_
    ),

    up_geo_frac_midpoint_gt_500 = ifelse(
      up_geo_gt500_valid_area_km2 > 0,
      up_geo_gt500_area_km2 /
        up_geo_gt500_valid_area_km2,
      NA_real_
    ),

    up_geo_frac_midpoint_gt_1000 = ifelse(
      up_geo_gt1000_valid_area_km2 > 0,
      up_geo_gt1000_area_km2 /
        up_geo_gt1000_valid_area_km2,
      NA_real_
    ),

    up_geo_frac_midpoint_gt_1500 = ifelse(
      up_geo_gt1500_valid_area_km2 > 0,
      up_geo_gt1500_area_km2 /
        up_geo_gt1500_valid_area_km2,
      NA_real_
    ),

    up_geo_frac_midpoint_gt_2000 = ifelse(
      up_geo_gt2000_valid_area_km2 > 0,
      up_geo_gt2000_area_km2 /
        up_geo_gt2000_valid_area_km2,
      NA_real_
    ),

    up_geo_age_overlay_coverage = ifelse(
      upstream_geometry_area_km2 > 0,
      up_geo_age_mapped_area_km2 /
        upstream_geometry_area_km2,
      NA_real_
    ),

    up_geo_age_resolved_coverage = ifelse(
      upstream_geometry_area_km2 > 0,
      up_geo_age_resolved_area_km2 /
        upstream_geometry_area_km2,
      NA_real_
    ),

    up_geo_age_resolved_fraction_of_overlay = ifelse(
      up_geo_age_mapped_area_km2 > 0,
      up_geo_age_resolved_area_km2 /
        up_geo_age_mapped_area_km2,
      NA_real_
    ),

    up_geo_age_resolved_fraction_of_UP_AREA = ifelse(
      is.finite(UP_AREA) &
        UP_AREA > 0,
      up_geo_age_resolved_area_km2 /
        UP_AREA,
      NA_real_
    ),

    upstream_SUB_AREA_to_UP_AREA_ratio = ifelse(
      is.finite(UP_AREA) &
        UP_AREA > 0,
      upstream_SUB_AREA_sum_km2 /
        UP_AREA,
      NA_real_
    ),

    local_minus_up_geo_age_mean_ma =
      local_geo_age_mean_ma -
        up_geo_age_mean_ma,

    local_to_up_geo_age_mean_ratio = ifelse(
      is.finite(up_geo_age_mean_ma) &
        up_geo_age_mean_ma != 0,
      local_geo_age_mean_ma /
        up_geo_age_mean_ma,
      NA_real_
    )
  )


if (nrow(result) != expected_rows) {
  stop(
    "Output row count changed: ",
    nrow(result)
  )
}

if (anyDuplicated(result$HYBAS_KEY) > 0L) {
  stop(
    "Duplicated HYBAS_ID in output."
  )
}


monotonic_failure_count <- sum(
  result$up_geo_age_resolved_area_km2 +
    1e-8 <
    result$local_geo_age_resolved_area_km2,
  na.rm = TRUE
)

if (monotonic_failure_count > 0L) {
  stop(
    "Upstream resolved area is smaller than local area ",
    "for ",
    monotonic_failure_count,
    " basins."
  )
}


threshold_fields <- c(
  "up_geo_frac_midpoint_gt_500",
  "up_geo_frac_midpoint_gt_1000",
  "up_geo_frac_midpoint_gt_1500",
  "up_geo_frac_midpoint_gt_2000"
)

threshold_out_of_bounds_count <- sum(
  vapply(
    threshold_fields,
    function(field_name) {

      values <- result[[field_name]]

      sum(
        is.finite(values) &
          (
            values < -1e-10 |
              values > 1 + 1e-10
          )
      )
    },
    numeric(1)
  )
)

if (threshold_out_of_bounds_count > 0L) {
  stop(
    "Upstream threshold fractions outside [0,1]: ",
    threshold_out_of_bounds_count
  )
}


output_rds <- file.path(
  output_dir,
  "l6_nrcan_age_local_upstream_as.rds"
)

output_csv <- file.path(
  output_dir,
  "l6_nrcan_age_local_upstream_as.csv"
)

saveRDS(
  result,
  output_rds
)

write_csv(
  result,
  output_csv
)


if (file.exists(input_gpkg)) {

  cat("Writing upstream predictor GeoPackage...\n")

  basin_geometry <- st_read(
    input_gpkg,
    quiet = TRUE
  )

  basin_geometry$HYBAS_KEY <- to_key(
    basin_geometry$HYBAS_ID
  )

  upstream_join <- result %>%
    select(
      HYBAS_KEY,
      upstream_SUB_AREA_sum_km2,
      upstream_geometry_area_km2,
      up_geo_age_mapped_area_km2,
      up_geo_age_resolved_area_km2,
      up_geo_age_unresolved_area_km2,
      up_geo_age_mean_ma,
      up_geo_age_sd_ma,
      up_geo_frac_midpoint_gt_500,
      up_geo_frac_midpoint_gt_1000,
      up_geo_frac_midpoint_gt_1500,
      up_geo_frac_midpoint_gt_2000,
      up_geo_age_overlay_coverage,
      up_geo_age_resolved_coverage,
      up_geo_age_resolved_fraction_of_overlay,
      up_geo_age_resolved_fraction_of_UP_AREA,
      upstream_SUB_AREA_to_UP_AREA_ratio,
      local_minus_up_geo_age_mean_ma,
      local_to_up_geo_age_mean_ratio
    )

  basin_output <- basin_geometry %>%
    left_join(
      upstream_join,
      by = "HYBAS_KEY"
    )

  output_gpkg <- file.path(
    output_dir,
    "l6_nrcan_age_local_upstream_as.gpkg"
  )

  if (file.exists(output_gpkg)) {
    file.remove(output_gpkg)
  }

  st_write(
    basin_output,
    output_gpkg,
    layer = "l6_nrcan_age_local_upstream_as",
    quiet = TRUE
  )
}


coverage_quantiles <- quantile(
  result$up_geo_age_resolved_coverage,
  probs = c(
    0,
    0.01,
    0.05,
    0.50,
    0.95,
    0.99,
    1
  ),
  na.rm = TRUE,
  names = FALSE
)

area_ratio_difference <- abs(
  result$
    upstream_SUB_AREA_to_UP_AREA_ratio -
    1
)


qc <- tibble(
  metric = c(
    "asia_basin_count",
    "processed_basin_count",
    "unprocessed_basin_count",
    "external_NEXT_DOWN_count",
    "basins_with_local_resolved_age",
    "basins_with_upstream_resolved_age",
    "up_resolved_coverage_minimum",
    "up_resolved_coverage_p01",
    "up_resolved_coverage_p05",
    "up_resolved_coverage_median",
    "up_resolved_coverage_p95",
    "up_resolved_coverage_p99",
    "up_resolved_coverage_maximum",
    "maximum_SUB_AREA_to_UP_AREA_absolute_difference",
    "median_SUB_AREA_to_UP_AREA_absolute_difference",
    "upstream_area_smaller_than_local_count",
    "threshold_fraction_out_of_bounds_count",
    "nonfinite_upstream_mean_count",
    "negative_upstream_sd_count"
  ),
  value = c(
    nrow(result),
    sum(processed),
    unprocessed_count,
    external_downstream_count,
    sum(
      result$
        local_geo_age_resolved_area_km2 > 0
    ),
    sum(
      result$
        up_geo_age_resolved_area_km2 > 0
    ),
    coverage_quantiles[1],
    coverage_quantiles[2],
    coverage_quantiles[3],
    coverage_quantiles[4],
    coverage_quantiles[5],
    coverage_quantiles[6],
    coverage_quantiles[7],
    max(
      area_ratio_difference,
      na.rm = TRUE
    ),
    median(
      area_ratio_difference,
      na.rm = TRUE
    ),
    monotonic_failure_count,
    threshold_out_of_bounds_count,
    sum(
      result$up_geo_age_resolved_area_km2 > 0 &
        !is.finite(
          result$up_geo_age_mean_ma
        )
    ),
    sum(
      is.finite(result$up_geo_age_sd_ma) &
        result$up_geo_age_sd_ma < 0
    )
  )
)

write_csv(
  qc,
  file.path(
    output_dir,
    "asia_upstream_age_qc.csv"
  )
)


focal_result <- result %>%
  filter(
    HYBAS_KEY == "4060840120"
  ) %>%
  select(
    region,
    HYBAS_ID,
    NEXT_DOWN,
    SUB_AREA,
    UP_AREA,
    local_geo_age_mean_ma,
    local_geo_age_sd_ma,
    up_geo_age_mean_ma,
    up_geo_age_sd_ma,
    local_minus_up_geo_age_mean_ma,
    local_geo_frac_midpoint_gt_1000,
    up_geo_frac_midpoint_gt_1000,
    local_geo_frac_midpoint_gt_2000,
    up_geo_frac_midpoint_gt_2000,
    local_geo_age_resolved_coverage,
    up_geo_age_resolved_coverage
  )

write_csv(
  focal_result,
  file.path(
    output_dir,
    "himalaya_focal_basin_upstream_age.csv"
  )
)


cat("\n========================================\n")
cat("ASIA UPSTREAM AGE ACCUMULATION COMPLETE\n")
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
