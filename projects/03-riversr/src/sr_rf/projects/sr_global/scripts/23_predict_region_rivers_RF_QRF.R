#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(tibble)
  library(readr)
  library(ranger)
})

sf::sf_use_s2(TRUE)

args <- commandArgs(
  trailingOnly = TRUE
)

if (length(args) < 1) {
  stop(
    paste0(
      "Usage: Rscript ",
      "23_predict_region_rivers_RF_QRF.R ",
      "<region> [chunk_size]"
    )
  )
}

region <- tolower(
  args[[1]]
)

regions <- c(
  "af", "ar", "as",
  "au", "eu", "gr",
  "na", "sa", "si"
)

if (!region %in% regions) {
  stop(
    "Unknown region: ",
    region
  )
}

chunk_size <- if (
  length(args) >= 2
) {
  as.integer(args[[2]])
} else {
  25000L
}

if (
  is.na(chunk_size) ||
  chunk_size < 1000
) {
  stop(
    "Invalid chunk size: ",
    chunk_size
  )
}

project_dir <- Sys.getenv(
  "SR_GLOBAL_DIR",
  unset = "/home/zhangmeng/projects/sr_global"
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
  is.na(n_threads) ||
  n_threads < 1
) {
  n_threads <- 1L
}

overwrite_chunks <- identical(
  Sys.getenv(
    "SR_OVERWRITE",
    unset = "0"
  ),
  "1"
)

model_file <- file.path(
  project_dir,
  "models/global/final_RF_QRF",
  "final_upstream_clay_RF_QRF.rds"
)

l6_covariate_file <- file.path(
  project_dir,
  "data_processed/global/final_prediction",
  "global_l6_upstream_prediction_covariates.rds"
)

river_file <- file.path(
  project_dir,
  "data_raw/hydrosheds/HydroRIVERS_global",
  paste0(
    "HydroRIVERS_v10_",
    region,
    "_shp"
  ),
  paste0(
    "HydroRIVERS_v10_",
    region,
    ".shp"
  )
)

basin_file <- file.path(
  project_dir,
  "data_raw/hydrosheds/HydroBASINS_global",
  paste0(
    "hybas_",
    region,
    "_lev06_v1c.shp"
  )
)

out_root <- file.path(
  project_dir,
  "data_processed/global/final_prediction"
)

chunk_dir <- file.path(
  out_root,
  "river_prediction_chunks",
  region
)

region_dir <- file.path(
  out_root,
  "river_predictions_by_region"
)

qc_dir <- file.path(
  project_dir,
  "outputs/global/final_river_prediction_qc"
)

dir.create(
  chunk_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

dir.create(
  region_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

dir.create(
  qc_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

required_files <- c(
  model_file,
  l6_covariate_file,
  river_file,
  basin_file
)

missing_files <- required_files[
  !file.exists(required_files)
]

if (length(missing_files) > 0) {
  stop(
    "Missing required files:\n",
    paste(
      missing_files,
      collapse = "\n"
    )
  )
}

cat(
  "Region:",
  region,
  "\n"
)

cat(
  "Chunk size:",
  chunk_size,
  "\n"
)

cat(
  "Threads:",
  n_threads,
  "\n"
)

# ------------------------------------------------------------
# Model and predictor definitions
# ------------------------------------------------------------

model_bundle <- readRDS(
  model_file
)

predictors <- model_bundle$predictors

space_vars <- c(
  "sp_x",
  "sp_y",
  "sp_z"
)

hydro_log_map <- c(
  log_DIS_AV_CMS = "DIS_AV_CMS",
  log_UPLAND_SKM = "UPLAND_SKM",
  log_CATCH_SKM = "CATCH_SKM",
  log_LENGTH_KM = "LENGTH_KM",
  log_DIST_DN_KM = "DIST_DN_KM",
  log_DIST_UP_KM = "DIST_UP_KM"
)

hydro_order_vars <- c(
  "ORD_STRA",
  "ORD_CLAS",
  "ORD_FLOW"
)

hydro_predictors <- c(
  names(hydro_log_map),
  hydro_order_vars
)

l6_predictors <- setdiff(
  predictors,
  c(
    space_vars,
    hydro_predictors
  )
)

if (length(predictors) != 28) {
  stop(
    "Expected 28 final predictors, found ",
    length(predictors)
  )
}

if (length(l6_predictors) != 16) {
  stop(
    "Expected 16 L6 predictors, found ",
    length(l6_predictors)
  )
}

# ------------------------------------------------------------
# L6 covariates
# ------------------------------------------------------------

l6_covariates <- readRDS(
  l6_covariate_file
) %>%
  filter(
    region == !!region
  )

if (nrow(l6_covariates) == 0) {
  stop(
    "No L6 covariates for region ",
    region
  )
}

if (
  anyDuplicated(
    l6_covariates$hybas_key
  )
) {
  stop(
    "Duplicate L6 covariate keys in region ",
    region
  )
}

l6_join <- l6_covariates %>%
  select(
    region,
    hybas_key,
    l6_predictors_complete,
    all_of(l6_predictors)
  )

# ------------------------------------------------------------
# L6 basin geometry
# ------------------------------------------------------------

cat(
  "Reading L6 basins...\n"
)

basins <- st_read(
  basin_file,
  quiet = TRUE
) %>%
  st_transform(4326)

basins <- suppressWarnings(
  st_wrap_dateline(
    basins,
    options = c(
      "WRAPDATELINE=YES",
      "DATELINEOFFSET=10"
    ),
    quiet = TRUE
  )
)

basins <- st_make_valid(
  basins
)

basins <- basins[
  !st_is_empty(basins),
  ,
  drop = FALSE
]

basins$hybas_key <- sprintf(
  "%.0f",
  as.numeric(
    basins$HYBAS_ID
  )
)

if (
  anyDuplicated(
    basins$hybas_key
  )
) {
  stop(
    "Duplicate basin geometry keys in region ",
    region
  )
}

basin_attributes <- basins %>%
  st_drop_geometry() %>%
  transmute(
    hybas_key,
    HYBAS_ID
  )

# ------------------------------------------------------------
# River inventory
# ------------------------------------------------------------

layers <- st_layers(
  river_file
)

layer_name <- layers$name[[1]]
n_river_segments <- as.integer(
  layers$features[[1]]
)

if (
  is.na(n_river_segments) ||
  n_river_segments < 1
) {
  stop(
    "Could not determine river feature count."
  )
}

chunk_starts <- seq.int(
  from = 0L,
  to = n_river_segments - 1L,
  by = chunk_size
)

cat(
  "River segments:",
  n_river_segments,
  "\n"
)

cat(
  "Chunks:",
  length(chunk_starts),
  "\n"
)

as_numeric_safe <- function(x) {
  suppressWarnings(
    as.numeric(
      as.character(x)
    )
  )
}

safe_log1p <- function(x) {

  x <- as_numeric_safe(x)

  x[
    !is.finite(x) |
      x < 0
  ] <- NA_real_

  log1p(x)
}

# ------------------------------------------------------------
# Chunk loop
# ------------------------------------------------------------

for (
  chunk_id in seq_along(
    chunk_starts
  )
) {

  offset <- chunk_starts[[chunk_id]]

  chunk_file <- file.path(
    chunk_dir,
    sprintf(
      "river_predictions_%s_chunk_%05d.rds",
      region,
      chunk_id
    )
  )

  if (
    file.exists(chunk_file) &&
    !overwrite_chunks
  ) {
    cat(
      "Skipping existing chunk:",
      chunk_id,
      "\n"
    )
    next
  }

  cat(
    "\nChunk ",
    chunk_id,
    " of ",
    length(chunk_starts),
    " | offset ",
    offset,
    "\n",
    sep = ""
  )

  query_text <- sprintf(
    paste0(
      'SELECT * FROM "%s" ',
      "LIMIT %d OFFSET %d"
    ),
    layer_name,
    chunk_size,
    offset
  )

  rivers <- st_read(
    river_file,
    query = query_text,
    quiet = TRUE
  )

  if (nrow(rivers) == 0) {
    cat(
      "No rows returned for chunk ",
      chunk_id,
      "\n"
    )
    next
  }

  required_river_fields <- c(
    "HYRIV_ID",
    unname(hydro_log_map),
    hydro_order_vars
  )

  missing_river_fields <- setdiff(
    required_river_fields,
    names(rivers)
  )

  if (
    length(missing_river_fields) > 0
  ) {
    stop(
      "Missing HydroRIVERS fields:\n",
      paste(
        missing_river_fields,
        collapse = "\n"
      )
    )
  }

  if (
    any(
      st_is_empty(rivers)
    )
  ) {
    stop(
      "Empty river geometries detected in chunk ",
      chunk_id
    )
  }

  # A representative point located on each reach.
  rivers_projected <- st_transform(
    rivers,
    6933
  )

  reach_points <- suppressWarnings(
    st_point_on_surface(
      rivers_projected
    )
  ) %>%
    st_transform(4326)

  coordinates <- st_coordinates(
    reach_points
  )

  if (
    nrow(coordinates) !=
      nrow(rivers)
  ) {
    stop(
      "Representative-point row mismatch in chunk ",
      chunk_id
    )
  }

  longitude <- coordinates[, 1]
  latitude <- coordinates[, 2]

  # Match reach points to L6 basin polygons.
  intersections <- st_intersects(
    reach_points,
    basins
  )

  n_intersections <- lengths(
    intersections
  )

  basin_index <- vapply(
    intersections,
    function(z) {
      if (length(z) == 0) {
        NA_integer_
      } else {
        z[[1]]
      }
    },
    integer(1)
  )

  assignment_method <- ifelse(
    is.na(basin_index),
    "nearest_l6",
    "within_l6"
  )

  assignment_distance_m <- rep(
    0,
    nrow(rivers)
  )

  unmatched <- which(
    is.na(basin_index)
  )

  if (length(unmatched) > 0) {

    nearest_index <- st_nearest_feature(
      reach_points[
        unmatched,
        ,
        drop = FALSE
      ],
      basins
    )

    nearest_distance <- as.numeric(
      st_distance(
        reach_points[
          unmatched,
          ,
          drop = FALSE
        ],
        basins[
          nearest_index,
          ,
          drop = FALSE
        ],
        by_element = TRUE
      )
    )

    basin_index[
      unmatched
    ] <- nearest_index

    assignment_distance_m[
      unmatched
    ] <- nearest_distance
  }

  assigned_basins <- basin_attributes[
    basin_index,
    ,
    drop = FALSE
  ]

  river_data <- st_drop_geometry(
    rivers
  )

  prediction_data <- tibble(
    source_row_index =
      offset +
      seq_len(nrow(rivers)),

    region =
      region,

    HYRIV_ID =
      as_numeric_safe(
        river_data$HYRIV_ID
      ),

    hyriv_key =
      sprintf(
        "%.0f",
        as_numeric_safe(
          river_data$HYRIV_ID
        )
      ),

    longitude =
      longitude,

    latitude =
      latitude,

    hybas_key =
      assigned_basins$hybas_key,

    HYBAS_ID =
      assigned_basins$HYBAS_ID,

    n_l6_intersections =
      n_intersections,

    l6_assignment_method =
      assignment_method,

    l6_assignment_distance_m =
      assignment_distance_m
  )

  prediction_data$l6_assignment_ok <-
    is.finite(
      prediction_data$
        l6_assignment_distance_m
    ) &
    prediction_data$
      l6_assignment_distance_m <= 10000

  # Spherical spatial coordinates.
  lon_rad <- longitude * pi / 180
  lat_rad <- latitude * pi / 180

  prediction_data$sp_x <-
    cos(lat_rad) * cos(lon_rad)

  prediction_data$sp_y <-
    cos(lat_rad) * sin(lon_rad)

  prediction_data$sp_z <-
    sin(lat_rad)

  # HydroRIVERS log1p transformations.
  for (
    log_name in names(
      hydro_log_map
    )
  ) {

    raw_name <- hydro_log_map[[log_name]]

    prediction_data[[log_name]] <- safe_log1p(
      river_data[[raw_name]]
    )
  }

  for (
    order_name in hydro_order_vars
  ) {

    values <- as_numeric_safe(
      river_data[[order_name]]
    )

    values[
      !is.finite(values) |
        values < 0
    ] <- NA_real_

    prediction_data[[order_name]] <- values
  }

  prediction_data <- prediction_data %>%
    left_join(
      l6_join,
      by = c(
        "region",
        "hybas_key"
      )
    )

  river_predictors_complete <-
    complete.cases(
      prediction_data[
        ,
        c(
          space_vars,
          hydro_predictors
        ),
        drop = FALSE
      ]
    )

  l6_complete <-
    !is.na(
      prediction_data$
        l6_predictors_complete
    ) &
    prediction_data$
      l6_predictors_complete

  model_frame <- prediction_data[
    ,
    predictors,
    drop = FALSE
  ]

  for (v in predictors) {
    model_frame[[v]] <-
      as_numeric_safe(
        model_frame[[v]]
      )
  }

  prediction_complete <-
    complete.cases(
      model_frame
    ) &
    apply(
      model_frame,
      1,
      function(z) {
        all(is.finite(z))
      }
    ) &
    prediction_data$
      l6_assignment_ok

  prediction_status <- rep(
    "predicted",
    nrow(prediction_data)
  )

  prediction_status[
    !prediction_data$
      l6_assignment_ok
  ] <- "l6_assignment_over_10km"

  prediction_status[
    prediction_data$
      l6_assignment_ok &
      !l6_complete
  ] <- "incomplete_l6_covariates"

  prediction_status[
    prediction_data$
      l6_assignment_ok &
      l6_complete &
      !river_predictors_complete
  ] <- "incomplete_river_predictors"

  prediction_status[
    !prediction_complete &
      prediction_status ==
        "predicted"
  ] <- "incomplete_final_predictors"

  rf_mean <- rep(
    NA_real_,
    nrow(prediction_data)
  )

  qrf_p10 <- rep(
    NA_real_,
    nrow(prediction_data)
  )

  qrf_p50 <- rep(
    NA_real_,
    nrow(prediction_data)
  )

  qrf_p90 <- rep(
    NA_real_,
    nrow(prediction_data)
  )

  prediction_rows <- which(
    prediction_complete
  )

  if (
    length(prediction_rows) > 0
  ) {

    newdata <- model_frame[
      prediction_rows,
      ,
      drop = FALSE
    ]

    rf_scaled <- predict(
      model_bundle$rf_mean,
      data = newdata,
      num.threads = n_threads
    )$predictions

    qrf_scaled <- predict(
      model_bundle$qrf,
      data = newdata,
      type = "quantiles",
      quantiles =
        model_bundle$quantiles,
      seed =
        model_bundle$seed_base +
        chunk_id,
      num.threads =
        n_threads
    )$predictions

    qrf_scaled <- as.matrix(
      qrf_scaled
    )

    if (ncol(qrf_scaled) != 3) {
      stop(
        "Unexpected QRF output columns in chunk ",
        chunk_id
      )
    }

    rf_mean[
      prediction_rows
    ] <- rf_scaled / 1000 + 0.700

    qrf_p10[
      prediction_rows
    ] <- qrf_scaled[, 1] / 1000 + 0.700

    qrf_p50[
      prediction_rows
    ] <- qrf_scaled[, 2] / 1000 + 0.700

    qrf_p90[
      prediction_rows
    ] <- qrf_scaled[, 3] / 1000 + 0.700
  }

  output_chunk <- prediction_data %>%
    transmute(
      source_row_index,
      region,
      HYRIV_ID,
      hyriv_key,
      longitude,
      latitude,
      HYBAS_ID,
      hybas_key,
      n_l6_intersections,
      l6_assignment_method,
      l6_assignment_distance_m,
      l6_assignment_ok,
      l6_predictors_complete =
        l6_complete,
      river_predictors_complete,
      prediction_status,
      rf_mean,
      qrf_p10,
      qrf_p50,
      qrf_p90,
      qrf_p80_width =
        qrf_p90 - qrf_p10,
      ORD_STRA,
      ORD_CLAS,
      ORD_FLOW,
      log_DIS_AV_CMS,
      log_UPLAND_SKM,
      log_CATCH_SKM,
      log_LENGTH_KM,
      log_DIST_DN_KM,
      log_DIST_UP_KM
    )

  saveRDS(
    output_chunk,
    chunk_file
  )

  cat(
    "Rows:",
    nrow(output_chunk),
    "| predicted:",
    sum(
      output_chunk$
        prediction_status ==
        "predicted"
    ),
    "\n"
  )

  rm(
    rivers,
    rivers_projected,
    reach_points,
    prediction_data,
    model_frame,
    output_chunk
  )

  invisible(
    gc()
  )
}

# ------------------------------------------------------------
# Combine regional chunks
# ------------------------------------------------------------

chunk_files <- list.files(
  chunk_dir,
  pattern = paste0(
    "^river_predictions_",
    region,
    "_chunk_[0-9]+\\.rds$"
  ),
  full.names = TRUE
)

if (
  length(chunk_files) !=
    length(chunk_starts)
) {
  stop(
    "Expected ",
    length(chunk_starts),
    " chunk files but found ",
    length(chunk_files)
  )
}

chunk_files <- sort(
  chunk_files
)

cat(
  "\nCombining ",
  length(chunk_files),
  " regional chunks...\n",
  sep = ""
)

region_predictions <- bind_rows(
  lapply(
    chunk_files,
    readRDS
  )
) %>%
  arrange(
    source_row_index
  )

if (
  nrow(region_predictions) !=
    n_river_segments
) {
  stop(
    "Regional row count mismatch: ",
    nrow(region_predictions),
    " versus ",
    n_river_segments
  )
}

if (
  anyDuplicated(
    region_predictions$source_row_index
  )
) {
  stop(
    "Duplicate source row indices detected."
  )
}

region_output_file <- file.path(
  region_dir,
  paste0(
    "river_predictions_",
    region,
    ".rds"
  )
)

saveRDS(
  region_predictions,
  region_output_file
)

status_summary <- region_predictions %>%
  count(
    prediction_status,
    name = "n_segments"
  ) %>%
  mutate(
    region = region,
    pct_segments =
      100 * n_segments /
      sum(n_segments),
    .before = 1
  )

overall_summary <- tibble(
  region = region,
  n_total_segments =
    nrow(region_predictions),
  n_predicted =
    sum(
      region_predictions$
        prediction_status ==
        "predicted"
    ),
  pct_predicted =
    100 * n_predicted /
    n_total_segments,
  n_nearest_l6 =
    sum(
      region_predictions$
        l6_assignment_method ==
        "nearest_l6"
    ),
  n_multiple_l6_intersections =
    sum(
      region_predictions$
        n_l6_intersections > 1
    ),
  rf_min =
    min(
      region_predictions$rf_mean,
      na.rm = TRUE
    ),
  rf_median =
    median(
      region_predictions$rf_mean,
      na.rm = TRUE
    ),
  rf_max =
    max(
      region_predictions$rf_mean,
      na.rm = TRUE
    ),
  median_p80_width =
    median(
      region_predictions$qrf_p80_width,
      na.rm = TRUE
    )
)

write_csv(
  status_summary,
  file.path(
    qc_dir,
    paste0(
      "river_prediction_status_",
      region,
      ".csv"
    )
  )
)

write_csv(
  overall_summary,
  file.path(
    qc_dir,
    paste0(
      "river_prediction_summary_",
      region,
      ".csv"
    )
  )
)

cat(
  "\n===== REGIONAL STATUS SUMMARY =====\n"
)

print(
  status_summary,
  n = Inf,
  width = Inf
)

cat(
  "\n===== REGIONAL OVERALL SUMMARY =====\n"
)

print(
  overall_summary,
  width = Inf
)

cat(
  "\nRegional prediction saved to:\n",
  region_output_file,
  "\n"
)

cat(
  "\nREGIONAL RIVER PREDICTION FINISHED\n"
)
