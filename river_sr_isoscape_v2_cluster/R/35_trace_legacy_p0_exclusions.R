options(stringsAsFactors = FALSE, scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

setwd(
  normalizePath(
    "~/river_sr_isoscape_v2_cluster",
    mustWork = TRUE
  )
)

out_dir <- "outputs/legacy_p0_exclusion_trace"

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

legacy_root <- file.path(
  Sys.getenv("HOME"),
  "projects/sr_global/data_processed/global"
)

# ------------------------------------------------------------
# Current observations + current P0 asset
# ------------------------------------------------------------

model <- readRDS(
  "data/processed/model_table_age_test.rds"
)

pred <- readRDS(
  "data/external/predictors_at_sites.rds"
)

if (inherits(model, "sf")) {
  model <- sf::st_drop_geometry(model)
}

if (inherits(pred, "sf")) {
  pred <- sf::st_drop_geometry(pred)
}

model <- as.data.frame(model)
pred <- as.data.frame(pred)

model$row_id <- as.character(model$row_id)
pred$row_id <- as.character(pred$row_id)

model$sr87_sr86 <- suppressWarnings(
  as.numeric(
    as.character(model$sr87_sr86)
  )
)

p0 <- grep(
  "^p0__",
  names(pred),
  value = TRUE
)

finite_matrix <- vapply(
  pred[p0],
  function(x) {
    is.finite(
      suppressWarnings(
        as.numeric(
          as.character(x)
        )
      )
    )
  },
  logical(nrow(pred))
)

finite_matrix <- as.matrix(finite_matrix)

pred$p0_nonmissing_n <- rowSums(
  finite_matrix
)

fail_ids <- pred |>
  filter(
    p0_nonmissing_n == 3L
  ) |>
  pull(row_id)

fail <- model |>
  filter(
    row_id %in% fail_ids
  ) |>
  select(
    any_of(
      c(
        "row_id",
        "sr87_sr86",
        "reference_id",
        "longitude",
        "latitude"
      )
    )
  ) |>
  arrange(
    desc(sr87_sr86)
  )

fail$coord_key <- sprintf(
  "%.5f|%.5f",
  fail$longitude,
  fail$latitude
)

cat(
  "Current P0-failed rows: ",
  nrow(fail),
  "\n",
  sep = ""
)

cat(
  "Current failed rows >=0.800: ",
  sum(
    fail$sr87_sr86 >= 0.800,
    na.rm = TRUE
  ),
  "\n",
  sep = ""
)

# ------------------------------------------------------------
# Legacy stages in chronological order
# ------------------------------------------------------------

stage_files <- c(
  snapped_best =
    "global_sr_snapped_best_all.rds",

  clean_5km =
    "global_model2_df_clean_5km.rds",

  clean_10km =
    "global_model2_df_clean_10km.rds",

  primary_observations_5km =
    "global_model_primary_observations_5km.rds",

  primary_sites_5km =
    "global_model_primary_sites_5km.rds",

  main_all_sites =
    "global_model_sites_5km_main_all_sites.rds",

  l6_glim =
    "global_model_sites_5km_with_l6_glim.rds",

  l6_glim_complete =
    "global_model_sites_5km_with_l6_glim_complete.rds",

  climate_terrain =
    "global_model_sites_5km_with_geology_climate_terrain.rds",

  climate_terrain_complete =
    "global_model_sites_5km_with_geology_climate_terrain_complete.rds",

  climate_terrain_soil =
    "global_model_sites_5km_with_geology_climate_terrain_soil.rds",

  final_complete =
    "global_model_sites_5km_with_geology_climate_terrain_soil_complete.rds"
)

to_char <- function(x) {
  as.character(x)
}

first_existing <- function(candidates, nms) {
  hit <- candidates[
    candidates %in% nms
  ]

  if (length(hit) == 0L) {
    return(NA_character_)
  }

  hit[1]
}

trace_list <- list()
stage_summary_list <- list()

for (stage_name in names(stage_files)) {

  path <- file.path(
    legacy_root,
    stage_files[[stage_name]]
  )

  if (!file.exists(path)) {
    next
  }

  dat <- readRDS(path)

  if (inherits(dat, "sf")) {
    dat <- sf::st_drop_geometry(dat)
  }

  dat <- as.data.frame(dat)

  id_candidates <- names(dat)[
    grepl(
      "row_id|global_row_id|sample_id|site_id",
      names(dat),
      ignore.case = TRUE
    )
  ]

  id_match_counts <- if (
    length(id_candidates) > 0L
  ) {
    vapply(
      id_candidates,
      function(column) {
        sum(
          fail$row_id %in%
            to_char(dat[[column]])
        )
      },
      integer(1)
    )
  } else {
    integer(0)
  }

  best_id_col <- if (
    length(id_match_counts) > 0L &&
    max(id_match_counts) > 0L
  ) {
    names(
      which.max(id_match_counts)
    )
  } else {
    NA_character_
  }

  lon_col <- first_existing(
    c(
      "longitude",
      "lon",
      "LONGITUDE",
      "LONG"
    ),
    names(dat)
  )

  lat_col <- first_existing(
    c(
      "latitude",
      "lat",
      "LATITUDE",
      "LAT"
    ),
    names(dat)
  )

  has_coords <-
    !is.na(lon_col) &&
    !is.na(lat_col)

  if (has_coords) {
    dat$.__coord_key <- sprintf(
      "%.5f|%.5f",
      suppressWarnings(
        as.numeric(
          dat[[lon_col]]
        )
      ),
      suppressWarnings(
        as.numeric(
          dat[[lat_col]]
        )
      )
    )
  } else {
    dat$.__coord_key <- NA_character_
  }

  special_columns <- c(
    "region",
    "snap_dist_m",
    "snap_group",
    "predictors_complete",
    "river_HYRIV_ID",
    "river_NEXT_DOWN",
    "river_MAIN_RIV",
    "river_LENGTH_KM",
    "river_CATCH_SKM",
    "river_UPLAND_SKM",
    "river_DIS_AV_CMS",
    "river_ORD_STRA",
    "river_ORD_CLAS",
    "river_ORD_FLOW",
    "l6_assignment_method",
    "l6_assignment_distance_m",
    "HYBAS_ID",
    "l6_assignment_ok",
    "local_glim_usable",
    "upstream_glim_usable",
    "local_glim_coverage_ratio",
    "up_glim_coverage_ratio",
    "local_water_ice_frac_all",
    "up_water_ice_frac_all",
    "local_no_data_frac_all",
    "up_no_data_frac_all",
    "climate_predictors_complete",
    "minimum_local_climate_coverage",
    "minimum_upstream_climate_coverage",
    "soil_predictors_complete",
    "minimum_soil_coverage"
  )

  special_columns <- special_columns[
    special_columns %in% names(dat)
  ]

  stage_rows <- lapply(
    seq_len(nrow(fail)),
    function(i) {

      current <- fail[i, ]

      match_index <- integer(0)
      match_method <- NA_character_

      if (!is.na(best_id_col)) {

        match_index <- which(
          to_char(
            dat[[best_id_col]]
          ) == current$row_id
        )

        if (length(match_index) > 0L) {
          match_method <- paste0(
            "id:",
            best_id_col
          )
        }
      }

      if (
        length(match_index) == 0L &&
        has_coords
      ) {

        match_index <- which(
          dat$.__coord_key ==
            current$coord_key
        )

        if (length(match_index) > 0L) {
          match_method <-
            "exact_coordinate"
        }
      }

      present <- length(match_index) > 0L

      out <- data.frame(
        row_id = current$row_id,
        sr87_sr86 = current$sr87_sr86,
        reference_id =
          if ("reference_id" %in% names(current)) {
            as.character(
              current$reference_id
            )
          } else {
            NA_character_
          },
        stage = stage_name,
        stage_file =
          basename(path),
        stage_n_rows =
          nrow(dat),
        best_id_column =
          best_id_col,
        present =
          present,
        match_method =
          match_method,
        stringsAsFactors = FALSE
      )

      for (column in special_columns) {

        if (!present) {
          out[[column]] <- NA
        } else {
          out[[column]] <-
            dat[
              match_index[1],
              column
            ]
        }
      }

      out
    }
  )

  stage_trace <- bind_rows(
    stage_rows
  )

  trace_list[[stage_name]] <-
    stage_trace

  stage_summary_list[[stage_name]] <-
    data.frame(
      stage = stage_name,
      file = basename(path),
      n_rows = nrow(dat),
      best_id_column =
        best_id_col,
      fail62_present =
        sum(
          stage_trace$present
        ),
      extreme21_present =
        sum(
          stage_trace$present &
            stage_trace$sr87_sr86 >= 0.800
        ),
      stringsAsFactors = FALSE
    )
}

trace <- bind_rows(
  trace_list
)

stage_summary <- bind_rows(
  stage_summary_list
)

write_csv(
  stage_summary,
  file.path(
    out_dir,
    "stage_retention_summary.csv"
  )
)

write_csv(
  trace,
  file.path(
    out_dir,
    "failed62_stage_trace_long.csv"
  )
)

# ------------------------------------------------------------
# Extract snap information from earliest stage
# ------------------------------------------------------------

snap_audit <- trace |>
  filter(
    stage == "snapped_best"
  ) |>
  arrange(
    desc(sr87_sr86)
  )

write_csv(
  snap_audit,
  file.path(
    out_dir,
    "failed62_snap_audit.csv"
  )
)

# ------------------------------------------------------------
# Extreme-only trace
# ------------------------------------------------------------

extreme_trace <- trace |>
  filter(
    sr87_sr86 >= 0.800
  ) |>
  arrange(
    desc(sr87_sr86),
    stage
  )

write_csv(
  extreme_trace,
  file.path(
    out_dir,
    "extreme21_stage_trace_long.csv"
  )
)

cat(
  "\n===== STAGE RETENTION =====\n"
)

print(
  stage_summary,
  row.names = FALSE
)

if (
  "snap_dist_m" %in%
  names(snap_audit)
) {

  cat(
    "\n===== SNAP DISTANCE SUMMARY: 62 FAILED =====\n"
  )

  print(
    summary(
      as.numeric(
        snap_audit$snap_dist_m
      )
    )
  )

  cat(
    "\nFailed rows >5 km: ",
    sum(
      as.numeric(
        snap_audit$snap_dist_m
      ) > 5000,
      na.rm = TRUE
    ),
    "\n",
    sep = ""
  )

  cat(
    "Failed rows >10 km: ",
    sum(
      as.numeric(
        snap_audit$snap_dist_m
      ) > 10000,
      na.rm = TRUE
    ),
    "\n",
    sep = ""
  )

  extreme_snap <- snap_audit |>
    filter(
      sr87_sr86 >= 0.800
    )

  cat(
    "\n===== SNAP DISTANCE SUMMARY: 21 EXTREMES =====\n"
  )

  print(
    summary(
      as.numeric(
        extreme_snap$snap_dist_m
      )
    )
  )

  cat(
    "\nExtreme rows >5 km: ",
    sum(
      as.numeric(
        extreme_snap$snap_dist_m
      ) > 5000,
      na.rm = TRUE
    ),
    " / ",
    nrow(extreme_snap),
    "\n",
    sep = ""
  )
}

cat(
  "\nLEGACY P0 EXCLUSION TRACE COMPLETE\n"
)

cat(
  "Outputs: ",
  normalizePath(
    out_dir,
    mustWork = TRUE
  ),
  "\n",
  sep = ""
)
