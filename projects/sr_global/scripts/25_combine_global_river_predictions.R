#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
})

options(
  dplyr.summarise.inform = FALSE
)

project_dir <- Sys.getenv(
  "SR_GLOBAL_DIR",
  unset = "/home/zhangmeng/projects/sr_global"
)

regions <- c(
  "af", "ar", "as",
  "au", "eu", "gr",
  "na", "sa", "si"
)

expected_counts <- c(
  af = 1527551L,
  ar = 324078L,
  as = 1428959L,
  au = 836472L,
  eu = 938544L,
  gr = 137088L,
  na = 986463L,
  sa = 1620963L,
  si = 677765L
)

expected_global_n <- sum(
  expected_counts
)

input_dir <- file.path(
  project_dir,
  "data_processed/global/final_prediction",
  "river_predictions_by_region"
)

output_dir <- file.path(
  project_dir,
  "data_processed/global/final_prediction"
)

qc_dir <- file.path(
  project_dir,
  "outputs/global/final_river_prediction_qc"
)

dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

dir.create(
  qc_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

required_cols <- c(
  "source_row_index",
  "region",
  "HYRIV_ID",
  "hyriv_key",
  "longitude",
  "latitude",
  "HYBAS_ID",
  "hybas_key",
  "n_l6_intersections",
  "l6_assignment_method",
  "l6_assignment_distance_m",
  "l6_assignment_ok",
  "l6_predictors_complete",
  "river_predictors_complete",
  "prediction_status",
  "rf_mean",
  "qrf_p10",
  "qrf_p50",
  "qrf_p90",
  "qrf_p80_width",
  "ORD_STRA",
  "ORD_CLAS",
  "ORD_FLOW"
)

region_objects <- vector(
  "list",
  length(regions)
)

names(region_objects) <- regions

regional_qc <- vector(
  "list",
  length(regions)
)

names(regional_qc) <- regions

cat(
  "Expected global river segments:",
  expected_global_n,
  "\n\n"
)

for (r in regions) {

  file_r <- file.path(
    input_dir,
    paste0(
      "river_predictions_",
      r,
      ".rds"
    )
  )

  if (!file.exists(file_r)) {
    stop(
      "Missing regional prediction file: ",
      file_r
    )
  }

  cat(
    "Reading region:",
    r,
    "\n"
  )

  x <- readRDS(
    file_r
  )

  missing_cols <- setdiff(
    required_cols,
    names(x)
  )

  if (length(missing_cols) > 0) {
    stop(
      "Missing columns in region ",
      r,
      ": ",
      paste(
        missing_cols,
        collapse = ", "
      )
    )
  }

  if (nrow(x) != expected_counts[[r]]) {
    stop(
      "Unexpected row count for region ",
      r,
      ": ",
      nrow(x),
      " versus ",
      expected_counts[[r]]
    )
  }

  if (
    any(
      is.na(x$region)
    ) ||
    any(
      x$region != r
    )
  ) {
    stop(
      "Region label mismatch in ",
      r
    )
  }

  if (
    anyDuplicated(
      x$source_row_index
    )
  ) {
    stop(
      "Duplicate source_row_index in region ",
      r
    )
  }

  if (
    anyDuplicated(
      x$HYRIV_ID
    )
  ) {
    stop(
      "Duplicate HYRIV_ID in region ",
      r
    )
  }

  predicted_index <- which(
    x$prediction_status == "predicted"
  )

  if (length(predicted_index) > 0) {

    prediction_matrix <- as.matrix(
      x[
        predicted_index,
        c(
          "rf_mean",
          "qrf_p10",
          "qrf_p50",
          "qrf_p90",
          "qrf_p80_width"
        ),
        drop = FALSE
      ]
    )

    if (
      any(
        !is.finite(
          prediction_matrix
        )
      )
    ) {
      stop(
        "Non-finite predictions in region ",
        r
      )
    }

    bad_quantile_order <- sum(
      x$qrf_p10[predicted_index] >
        x$qrf_p50[predicted_index] |
      x$qrf_p50[predicted_index] >
        x$qrf_p90[predicted_index]
    )

  } else {

    bad_quantile_order <- 0L
  }

  if (bad_quantile_order > 0) {
    stop(
      "Non-monotonic QRF quantiles in region ",
      r,
      ": ",
      bad_quantile_order
    )
  }

  regional_qc[[r]] <- tibble(
    region = r,
    n_total_segments = nrow(x),
    n_predicted = sum(
      x$prediction_status == "predicted"
    ),
    pct_predicted = 100 * n_predicted /
      n_total_segments,
    n_incomplete_l6 = sum(
      x$prediction_status ==
        "incomplete_l6_covariates"
    ),
    n_incomplete_river = sum(
      x$prediction_status ==
        "incomplete_river_predictors"
    ),
    n_assignment_over_10km = sum(
      x$prediction_status ==
        "l6_assignment_over_10km"
    ),
    n_nearest_l6 = sum(
      x$l6_assignment_method ==
        "nearest_l6"
    ),
    n_multiple_l6_intersections = sum(
      x$n_l6_intersections > 1
    ),
    rf_min = min(
      x$rf_mean,
      na.rm = TRUE
    ),
    rf_median = median(
      x$rf_mean,
      na.rm = TRUE
    ),
    rf_mean_value = mean(
      x$rf_mean,
      na.rm = TRUE
    ),
    rf_max = max(
      x$rf_mean,
      na.rm = TRUE
    ),
    median_p80_width = median(
      x$qrf_p80_width,
      na.rm = TRUE
    ),
    max_p80_width = max(
      x$qrf_p80_width,
      na.rm = TRUE
    )
  )

  region_objects[[r]] <- x

  cat(
    "Rows:",
    nrow(x),
    "| predicted:",
    sum(
      x$prediction_status == "predicted"
    ),
    "\n\n"
  )
}

cat(
  "Combining nine regional tables...\n"
)

global_predictions <- bind_rows(
  region_objects
)

rm(
  region_objects
)

invisible(
  gc()
)

cat(
  "Combined rows:",
  nrow(global_predictions),
  "\n"
)

if (
  nrow(global_predictions) !=
    expected_global_n
) {
  stop(
    "Global row count mismatch: ",
    nrow(global_predictions),
    " versus ",
    expected_global_n
  )
}

global_key <- paste(
  global_predictions$region,
  global_predictions$source_row_index,
  sep = "_"
)

if (
  anyDuplicated(global_key)
) {
  stop(
    "Duplicate region + source_row_index keys."
  )
}

region_hyriv_key <- paste(
  global_predictions$region,
  global_predictions$HYRIV_ID,
  sep = "_"
)

if (
  anyDuplicated(region_hyriv_key)
) {
  stop(
    "Duplicate region + HYRIV_ID keys."
  )
}

predicted_rows <- global_predictions %>%
  filter(
    prediction_status == "predicted"
  )

bad_quantiles <- predicted_rows %>%
  filter(
    qrf_p10 > qrf_p50 |
      qrf_p50 > qrf_p90
  )

if (nrow(bad_quantiles) > 0) {
  stop(
    "Global non-monotonic quantile rows: ",
    nrow(bad_quantiles)
  )
}

regional_summary <- bind_rows(
  regional_qc
)

status_summary <- global_predictions %>%
  count(
    region,
    prediction_status,
    name = "n_segments"
  ) %>%
  group_by(
    region
  ) %>%
  mutate(
    pct_segments =
      100 * n_segments /
      sum(n_segments)
  ) %>%
  ungroup()

global_status_summary <- global_predictions %>%
  count(
    prediction_status,
    name = "n_segments"
  ) %>%
  mutate(
    pct_segments =
      100 * n_segments /
      sum(n_segments)
  )

global_summary <- tibble(
  n_total_segments =
    nrow(global_predictions),

  n_predicted =
    nrow(predicted_rows),

  pct_predicted =
    100 * n_predicted /
    n_total_segments,

  n_regions =
    n_distinct(
      global_predictions$region
    ),

  n_unique_region_hyriv =
    length(
      unique(
        region_hyriv_key
      )
    ),

  n_duplicate_bare_HYRIV_ID =
    sum(
      duplicated(
        global_predictions$HYRIV_ID
      )
    ),

  n_nearest_l6 =
    sum(
      global_predictions$
        l6_assignment_method ==
        "nearest_l6"
    ),

  n_assignment_over_10km =
    sum(
      global_predictions$
        l6_assignment_distance_m >
        10000,
      na.rm = TRUE
    ),

  n_multiple_l6_intersections =
    sum(
      global_predictions$
        n_l6_intersections > 1
    ),

  rf_min =
    min(
      predicted_rows$rf_mean
    ),

  rf_q025 =
    quantile(
      predicted_rows$rf_mean,
      0.025,
      names = FALSE
    ),

  rf_median =
    median(
      predicted_rows$rf_mean
    ),

  rf_mean_value =
    mean(
      predicted_rows$rf_mean
    ),

  rf_q975 =
    quantile(
      predicted_rows$rf_mean,
      0.975,
      names = FALSE
    ),

  rf_max =
    max(
      predicted_rows$rf_mean
    ),

  p80_width_median =
    median(
      predicted_rows$qrf_p80_width
    ),

  p80_width_q90 =
    quantile(
      predicted_rows$qrf_p80_width,
      0.90,
      names = FALSE
    ),

  p80_width_q95 =
    quantile(
      predicted_rows$qrf_p80_width,
      0.95,
      names = FALSE
    ),

  p80_width_max =
    max(
      predicted_rows$qrf_p80_width
    ),

  n_nonmonotonic_quantiles =
    nrow(
      bad_quantiles
    )
)

full_output_file <- file.path(
  output_dir,
  "global_river_predictions_RF_QRF.rds"
)

compact_output_file <- file.path(
  output_dir,
  "global_river_prediction_map_attributes.rds"
)

cat(
  "\nSaving full global prediction table...\n"
)

saveRDS(
  global_predictions,
  full_output_file,
  compress = "gzip"
)

map_attributes <- global_predictions %>%
  select(
    region,
    source_row_index,
    HYRIV_ID,
    longitude,
    latitude,
    HYBAS_ID,
    prediction_status,
    rf_mean,
    qrf_p10,
    qrf_p50,
    qrf_p90,
    qrf_p80_width,
    ORD_STRA,
    ORD_CLAS,
    ORD_FLOW,
    log_DIS_AV_CMS
  )

cat(
  "Saving compact map attribute table...\n"
)

saveRDS(
  map_attributes,
  compact_output_file,
  compress = "gzip"
)

write_csv(
  regional_summary,
  file.path(
    qc_dir,
    "global_river_prediction_summary_by_region.csv"
  )
)

write_csv(
  status_summary,
  file.path(
    qc_dir,
    "global_river_prediction_status_by_region.csv"
  )
)

write_csv(
  global_status_summary,
  file.path(
    qc_dir,
    "global_river_prediction_status_global.csv"
  )
)

write_csv(
  global_summary,
  file.path(
    qc_dir,
    "global_river_prediction_summary_global.csv"
  )
)

cat(
  "\n===== REGIONAL SUMMARY =====\n"
)

print(
  regional_summary,
  n = Inf,
  width = Inf
)

cat(
  "\n===== GLOBAL STATUS SUMMARY =====\n"
)

print(
  global_status_summary,
  n = Inf,
  width = Inf
)

cat(
  "\n===== GLOBAL SUMMARY =====\n"
)

print(
  global_summary,
  width = Inf
)

cat(
  "\nFull table:\n",
  full_output_file,
  "\n"
)

cat(
  "\nCompact map attributes:\n",
  compact_output_file,
  "\n"
)

cat(
  "\nGLOBAL RIVER PREDICTION QC PASSED\n"
)
