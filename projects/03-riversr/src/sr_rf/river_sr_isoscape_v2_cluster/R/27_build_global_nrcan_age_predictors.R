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

output_dir <- paste0(
  "outputs/nrcan_age_hydrobasins_l6/",
  "global_upstream"
)

dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)


region_catalogue <- tribble(
  ~region, ~directory,     ~expected_rows,
  "af",    "af_pilot",              3597L,
  "ar",    "ar_pilot",               849L,
  "as",    "asia_pilot",            2489L,
  "au",    "au_pilot",              1425L,
  "eu",    "eu_pilot",              2240L,
  "gr",    "gr_pilot",               302L,
  "na",    "na_pilot",              2043L,
  "sa",    "sa_pilot",              1946L,
  "si",    "si_pilot",              1506L
)

expected_global_rows <- sum(
  region_catalogue$expected_rows
)


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


safe_quantile <- function(
  values,
  probability
) {

  values <- values[
    is.finite(values)
  ]

  if (length(values) == 0L) {
    return(NA_real_)
  }

  as.numeric(
    quantile(
      values,
      probs = probability,
      names = FALSE,
      na.rm = TRUE
    )
  )
}


combine_max_na <- function(
  first,
  second
) {

  if (!is.finite(first)) {
    return(second)
  }

  if (!is.finite(second)) {
    return(first)
  }

  max(
    first,
    second
  )
}


combine_min_na <- function(
  first,
  second
) {

  if (!is.finite(first)) {
    return(second)
  }

  if (!is.finite(second)) {
    return(first)
  }

  min(
    first,
    second
  )
}


cat("Reading nine regional local-age tables...\n")

regional_tables <- vector(
  "list",
  nrow(region_catalogue)
)

for (
  catalogue_index in seq_len(
    nrow(region_catalogue)
  )
) {

  region_code <- region_catalogue$region[
    catalogue_index
  ]

  region_directory <- region_catalogue$directory[
    catalogue_index
  ]

  expected_rows <- region_catalogue$expected_rows[
    catalogue_index
  ]

  input_path <- file.path(
    "outputs/nrcan_age_hydrobasins_l6",
    region_directory,
    paste0(
      "l6_nrcan_age_local_",
      region_code,
      ".rds"
    )
  )

  if (!file.exists(input_path)) {
    stop(
      "Missing regional table: ",
      input_path
    )
  }

  region_table <- readRDS(
    input_path
  )

  if (inherits(region_table, "sf")) {
    region_table <- st_drop_geometry(
      region_table
    )
  }

  region_table <- as_tibble(
    region_table
  )

  if (nrow(region_table) != expected_rows) {
    stop(
      "Unexpected row count for region ",
      region_code,
      ": expected ",
      expected_rows,
      "; found ",
      nrow(region_table)
    )
  }

  if (!"region" %in% names(region_table)) {

    region_table$region <- region_code

  } else {

    observed_regions <- unique(
      as.character(
        region_table$region
      )
    )

    observed_regions <- observed_regions[
      !is.na(observed_regions)
    ]

    if (
      length(observed_regions) != 1L ||
      observed_regions != region_code
    ) {
      stop(
        "Region field mismatch for ",
        region_code
      )
    }
  }

  regional_tables[[
    catalogue_index
  ]] <- region_table

  cat(
    region_code,
    ": ",
    nrow(region_table),
    " basins\n",
    sep = ""
  )
}


cat("Combining global local-age table...\n")

global_local <- bind_rows(
  regional_tables
)


required_columns <- c(
  "region",
  "HYBAS_ID",
  "NEXT_DOWN",
  "SUB_AREA",
  "UP_AREA",
  "basin_geometry_area_km2",
  "local_geo_age_mapped_area_km2",
  "local_geo_age_resolved_area_km2",
  "local_geo_age_unresolved_area_km2",
  "local_geo_age_overlay_coverage",
  "local_geo_age_resolved_coverage",
  "local_geo_age_mean_ma",
  "local_geo_age_sd_ma",
  "local_geo_age_max_oldest_ma",
  "local_geo_age_min_youngest_ma",
  "local_geo_frac_midpoint_gt_500",
  "local_geo_frac_midpoint_gt_1000",
  "local_geo_frac_midpoint_gt_1500",
  "local_geo_frac_midpoint_gt_2000",
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
  names(global_local)
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


if (nrow(global_local) != expected_global_rows) {
  stop(
    "Expected ",
    expected_global_rows,
    " global basins; found ",
    nrow(global_local)
  )
}


global_local$HYBAS_KEY <- to_key(
  global_local$HYBAS_ID
)

global_local$NEXT_DOWN_KEY <- ifelse(
  is.na(global_local$NEXT_DOWN) |
    global_local$NEXT_DOWN == 0,
  NA_character_,
  to_key(global_local$NEXT_DOWN)
)


missing_hybas_id_count <- sum(
  is.na(global_local$HYBAS_KEY)
)

duplicated_hybas_id_count <- sum(
  duplicated(global_local$HYBAS_KEY)
)

if (
  missing_hybas_id_count > 0L ||
  duplicated_hybas_id_count > 0L
) {
  stop(
    "Global HYBAS_ID problem. Missing: ",
    missing_hybas_id_count,
    "; duplicated: ",
    duplicated_hybas_id_count
  )
}


global_local <- global_local %>%
  arrange(
    region,
    HYBAS_ID
  )


write_csv(
  global_local,
  file.path(
    output_dir,
    "l6_nrcan_age_local_global.csv"
  )
)

saveRDS(
  global_local,
  file.path(
    output_dir,
    "l6_nrcan_age_local_global.rds"
  )
)


cat("Constructing complete global HydroBASINS network...\n")

id_lookup <- setNames(
  seq_len(nrow(global_local)),
  global_local$HYBAS_KEY
)

downstream_index <- unname(
  id_lookup[
    global_local$NEXT_DOWN_KEY
  ]
)

external_next_down <- (
  !is.na(global_local$NEXT_DOWN_KEY) &
    is.na(downstream_index)
)

external_next_down_count <- sum(
  external_next_down
)

if (external_next_down_count > 0L) {

  external_table <- global_local[
    external_next_down,
    c(
      "region",
      "HYBAS_ID",
      "NEXT_DOWN",
      "SUB_AREA",
      "UP_AREA"
    )
  ]

  write_csv(
    external_table,
    file.path(
      output_dir,
      "external_next_down_ids.csv"
    )
  )

  stop(
    "Global NEXT_DOWN IDs absent from combined table: ",
    external_next_down_count
  )
}


self_loop_count <- sum(
  !is.na(downstream_index) &
    downstream_index == seq_len(
      nrow(global_local)
    )
)

if (self_loop_count > 0L) {
  stop(
    "Self-referencing NEXT_DOWN links: ",
    self_loop_count
  )
}


valid_downstream <- !is.na(
  downstream_index
)

cross_region_link_count <- sum(
  global_local$region[
    valid_downstream
  ] !=
    global_local$region[
      downstream_index[
        valid_downstream
      ]
    ]
)


cat(
  "Cross-region downstream links: ",
  cross_region_link_count,
  "\n",
  sep = ""
)


numeric_zero_columns <- c(
  "SUB_AREA",
  "basin_geometry_area_km2",
  "local_geo_age_mapped_area_km2",
  "local_geo_age_resolved_area_km2",
  "local_geo_age_unresolved_area_km2",
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

  global_local[[column_name]] <- as.numeric(
    global_local[[column_name]]
  )

  global_local[[column_name]][
    !is.finite(
      global_local[[column_name]]
    )
  ] <- 0
}


resolved_area <- global_local[[
  "local_geo_age_resolved_area_km2"
]]

local_age_mean <- as.numeric(
  global_local[[
    "local_geo_age_mean_ma"
  ]]
)

local_age_sd <- as.numeric(
  global_local[[
    "local_geo_age_sd_ma"
  ]]
)

local_age_sd[
  !is.finite(local_age_sd)
] <- 0


global_local$local_geo_age_sum_ma_km2 <- ifelse(
  resolved_area > 0 &
    is.finite(local_age_mean),
  resolved_area *
    local_age_mean,
  0
)

global_local$local_geo_age_second_sum_ma2_km2 <- ifelse(
  resolved_area > 0 &
    is.finite(local_age_mean),
  resolved_area *
    (
      local_age_mean^2 +
        local_age_sd^2
    ),
  0
)


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
  global_local[
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


upstream_max_oldest_ma <- as.numeric(
  global_local[[
    "local_geo_age_max_oldest_ma"
  ]]
)

upstream_min_youngest_ma <- as.numeric(
  global_local[[
    "local_geo_age_min_youngest_ma"
  ]]
)

upstream_max_oldest_ma[
  !is.finite(upstream_max_oldest_ma)
] <- NA_real_

upstream_min_youngest_ma[
  !is.finite(upstream_min_youngest_ma)
] <- NA_real_


indegree <- tabulate(
  downstream_index[
    !is.na(downstream_index)
  ],
  nbins = nrow(global_local)
)

queue <- which(
  indegree == 0L
)

queue_position <- 1L

processed <- logical(
  nrow(global_local)
)


cat("Accumulating geological-age components downstream globally...\n")

while (queue_position <= length(queue)) {

  current <- queue[
    queue_position
  ]

  queue_position <- queue_position + 1L

  processed[
    current
  ] <- TRUE

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

    upstream_max_oldest_ma[
      downstream
    ] <- combine_max_na(
      upstream_max_oldest_ma[
        downstream
      ],
      upstream_max_oldest_ma[
        current
      ]
    )

    upstream_min_youngest_ma[
      downstream
    ] <- combine_min_na(
      upstream_min_youngest_ma[
        downstream
      ],
      upstream_min_youngest_ma[
        current
      ]
    )

    indegree[
      downstream
    ] <- indegree[
      downstream
    ] - 1L

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

  unprocessed_table <- global_local[
    !processed,
    c(
      "region",
      "HYBAS_ID",
      "NEXT_DOWN",
      "SUB_AREA",
      "UP_AREA"
    )
  ]

  write_csv(
    unprocessed_table,
    file.path(
      output_dir,
      "unprocessed_global_network_basins.csv"
    )
  )

  stop(
    "Global accumulation left ",
    unprocessed_count,
    " unprocessed basins."
  )
}


upstream_table <- as_tibble(
  accumulated
)


cat("Deriving global upstream age predictors...\n")

global_result <- bind_cols(
  global_local %>%
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

    up_geo_age_max_oldest_ma =
      upstream_max_oldest_ma,

    up_geo_age_min_youngest_ma =
      upstream_min_youngest_ma,

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
    ),

    up_geo_age_quality_tier = case_when(
      !is.finite(
        up_geo_age_resolved_coverage
      ) ~ "none",

      up_geo_age_resolved_coverage >= 0.95 ~
        "high",

      up_geo_age_resolved_coverage >= 0.80 ~
        "medium",

      up_geo_age_resolved_coverage > 0 ~
        "low",

      TRUE ~
        "none"
    )
  )


if (nrow(global_result) != expected_global_rows) {
  stop(
    "Global output row count changed: ",
    nrow(global_result)
  )
}


monotonic_failure_count <- sum(
  global_result$up_geo_age_resolved_area_km2 +
    1e-8 <
    global_result$local_geo_age_resolved_area_km2,
  na.rm = TRUE
)


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

      values <- global_result[[
        field_name
      ]]

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


if (monotonic_failure_count > 0L) {
  stop(
    "Upstream resolved area smaller than local area: ",
    monotonic_failure_count
  )
}


if (threshold_out_of_bounds_count > 0L) {
  stop(
    "Threshold fractions outside [0,1]: ",
    threshold_out_of_bounds_count
  )
}


saveRDS(
  global_result,
  file.path(
    output_dir,
    "l6_nrcan_age_local_upstream_global.rds"
  )
)

write_csv(
  global_result,
  file.path(
    output_dir,
    "l6_nrcan_age_local_upstream_global.csv"
  )
)


regional_summary <- global_result %>%
  group_by(region) %>%
  summarise(
    basin_count = n(),

    local_resolved_count = sum(
      local_geo_age_resolved_area_km2 > 0
    ),

    upstream_resolved_count = sum(
      up_geo_age_resolved_area_km2 > 0
    ),

    local_resolved_coverage_p05 =
      safe_quantile(
        local_geo_age_resolved_coverage,
        0.05
      ),

    local_resolved_coverage_median =
      safe_quantile(
        local_geo_age_resolved_coverage,
        0.50
      ),

    upstream_resolved_coverage_p05 =
      safe_quantile(
        up_geo_age_resolved_coverage,
        0.05
      ),

    upstream_resolved_coverage_median =
      safe_quantile(
        up_geo_age_resolved_coverage,
        0.50
      ),

    upstream_mean_age_median =
      safe_quantile(
        up_geo_age_mean_ma,
        0.50
      ),

    upstream_frac_gt_1000_median =
      safe_quantile(
        up_geo_frac_midpoint_gt_1000,
        0.50
      ),

    upstream_frac_gt_2000_median =
      safe_quantile(
        up_geo_frac_midpoint_gt_2000,
        0.50
      ),

    .groups = "drop"
  )


write_csv(
  regional_summary,
  file.path(
    output_dir,
    "global_age_regional_summary.csv"
  )
)


area_ratio_difference <- abs(
  global_result$upstream_SUB_AREA_to_UP_AREA_ratio -
    1
)


qc <- tibble(
  metric = c(
    "global_basin_count",
    "expected_global_basin_count",
    "unique_HYBAS_ID_count",
    "duplicated_HYBAS_ID_count",
    "processed_basin_count",
    "unprocessed_basin_count",
    "outlet_or_terminal_basin_count",
    "external_NEXT_DOWN_count",
    "cross_region_NEXT_DOWN_count",
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
    "negative_upstream_sd_count",
    "high_quality_upstream_age_count",
    "medium_quality_upstream_age_count",
    "low_quality_upstream_age_count",
    "no_upstream_age_count"
  ),

  value = c(
    nrow(global_result),
    expected_global_rows,
    length(
      unique(
        global_result$HYBAS_KEY
      )
    ),
    sum(
      duplicated(
        global_result$HYBAS_KEY
      )
    ),
    sum(processed),
    unprocessed_count,
    sum(
      is.na(downstream_index)
    ),
    external_next_down_count,
    cross_region_link_count,
    sum(
      global_result$local_geo_age_resolved_area_km2 > 0
    ),
    sum(
      global_result$up_geo_age_resolved_area_km2 > 0
    ),
    safe_quantile(
      global_result$up_geo_age_resolved_coverage,
      0
    ),
    safe_quantile(
      global_result$up_geo_age_resolved_coverage,
      0.01
    ),
    safe_quantile(
      global_result$up_geo_age_resolved_coverage,
      0.05
    ),
    safe_quantile(
      global_result$up_geo_age_resolved_coverage,
      0.50
    ),
    safe_quantile(
      global_result$up_geo_age_resolved_coverage,
      0.95
    ),
    safe_quantile(
      global_result$up_geo_age_resolved_coverage,
      0.99
    ),
    safe_quantile(
      global_result$up_geo_age_resolved_coverage,
      1
    ),
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
      global_result$up_geo_age_resolved_area_km2 > 0 &
        !is.finite(
          global_result$up_geo_age_mean_ma
        )
    ),
    sum(
      is.finite(
        global_result$up_geo_age_sd_ma
      ) &
        global_result$up_geo_age_sd_ma < 0
    ),
    sum(
      global_result$up_geo_age_quality_tier == "high"
    ),
    sum(
      global_result$up_geo_age_quality_tier == "medium"
    ),
    sum(
      global_result$up_geo_age_quality_tier == "low"
    ),
    sum(
      global_result$up_geo_age_quality_tier == "none"
    )
  )
)


write_csv(
  qc,
  file.path(
    output_dir,
    "global_upstream_age_qc.csv"
  )
)


predictor_manifest <- tribble(
  ~predictor, ~group, ~priority, ~role,

  "local_geo_age_mean_ma",
  "local_age",
  1L,
  "Mean geological age in the local L6 basin",

  "up_geo_age_mean_ma",
  "upstream_age",
  1L,
  "Area-weighted mean age across the upstream catchment",

  "local_geo_age_sd_ma",
  "local_age",
  2L,
  "Within-basin geological-age heterogeneity",

  "up_geo_age_sd_ma",
  "upstream_age",
  2L,
  "Upstream geological-age heterogeneity",

  "local_geo_frac_midpoint_gt_1000",
  "ancient_fraction",
  1L,
  "Local fraction with midpoint age above 1000 Ma",

  "up_geo_frac_midpoint_gt_1000",
  "ancient_fraction",
  1L,
  "Upstream fraction with midpoint age above 1000 Ma",

  "local_geo_frac_midpoint_gt_2000",
  "ancient_fraction",
  1L,
  "Local fraction with midpoint age above 2000 Ma",

  "up_geo_frac_midpoint_gt_2000",
  "ancient_fraction",
  1L,
  "Upstream fraction with midpoint age above 2000 Ma",

  "local_geo_age_max_oldest_ma",
  "extreme_age",
  2L,
  "Oldest possible local geological component",

  "up_geo_age_max_oldest_ma",
  "extreme_age",
  2L,
  "Oldest possible upstream geological component",

  "local_minus_up_geo_age_mean_ma",
  "local_upstream_contrast",
  3L,
  "Difference between local and upstream mean age",

  "local_geo_age_resolved_coverage",
  "quality_control",
  0L,
  "Local resolved-age coverage; retain for QC",

  "up_geo_age_resolved_coverage",
  "quality_control",
  0L,
  "Upstream resolved-age coverage; retain for QC"
)


write_csv(
  predictor_manifest,
  file.path(
    output_dir,
    "global_age_predictor_manifest.csv"
  )
)


cat("\n========================================\n")
cat("GLOBAL NRCan AGE PREDICTORS COMPLETE\n")
cat("========================================\n")

cat("\nGlobal QC:\n")

print(
  qc,
  n = Inf,
  width = Inf
)

cat("\nRegional summary:\n")

print(
  regional_summary,
  n = Inf,
  width = Inf
)

cat("\nOutputs saved to:\n")
cat(output_dir, "\n")
