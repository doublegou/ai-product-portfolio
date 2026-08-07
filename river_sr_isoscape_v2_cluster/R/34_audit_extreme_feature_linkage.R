#!/usr/bin/env Rscript

options(
  stringsAsFactors = FALSE,
  scipen = 999
)

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

model_path <- "data/processed/model_table_age_test.rds"
out_dir <- "outputs/extreme_feature_linkage_audit"

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

model <- readRDS(model_path)

if (inherits(model, "sf")) {
  model <- sf::st_drop_geometry(model)
}

model <- as.data.frame(model)

p0_predictors <- c(
  "p0__sp_x",
  "p0__sp_y",
  "p0__sp_z",
  "p0__log_DIS_AV_CMS",
  "p0__log_UPLAND_SKM",
  "p0__log_CATCH_SKM",
  "p0__log_LENGTH_KM",
  "p0__log_DIST_DN_KM",
  "p0__log_DIST_UP_KM",
  "p0__ORD_STRA",
  "p0__ORD_CLAS",
  "p0__ORD_FLOW",
  "p0__up_geo_unconsolidated_frac",
  "p0__up_geo_siliciclastic_frac",
  "p0__up_geo_mixed_sedimentary_frac",
  "p0__up_geo_carbonate_frac",
  "p0__up_geo_metamorphic_frac",
  "p0__up_geo_plutonic_frac",
  "p0__up_geo_volcanic_frac",
  "p0__up_geo_evaporite_frac",
  "p0__up_bio1_C",
  "p0__up_bio4_C_sd",
  "p0__up_bio12_mm",
  "p0__up_bio15_cv",
  "p0__up_ai_ratio",
  "p0__up_et0_mm",
  "p0__up_elevation_m",
  "p0__up_soil_clay_pct_0_30cm"
)

missing_columns <- setdiff(
  c(
    "row_id",
    "sr87_sr86",
    "longitude",
    "latitude",
    p0_predictors
  ),
  names(model)
)

if (length(missing_columns) > 0L) {
  stop(
    "Missing required columns:\n",
    paste(
      missing_columns,
      collapse = "\n"
    )
  )
}

to_numeric <- function(x) {
  suppressWarnings(
    as.numeric(
      as.character(x)
    )
  )
}

p0_numeric <- as.data.frame(
  lapply(
    model[p0_predictors],
    to_numeric
  )
)

p0_bad <- !is.finite(
  as.matrix(p0_numeric)
)

model$p0_missing_n <- rowSums(p0_bad)
model$p0_complete <- model$p0_missing_n == 0L

model$longitude_std <- to_numeric(
  model$longitude
)

model$latitude_std <- to_numeric(
  model$latitude
)

model$sr87_sr86 <- to_numeric(
  model$sr87_sr86
)

source_col <- names(model)[
  grepl(
    "reference|citation|source|paper|study|doi",
    names(model),
    ignore.case = TRUE
  )
][1]

if (
  length(source_col) == 0L ||
  is.na(source_col)
) {
  source_col <- NA_character_
}

hybas_col <- names(model)[
  grepl(
    "^HYBAS_ID$|hybas",
    names(model),
    ignore.case = TRUE
  )
][1]

if (
  length(hybas_col) == 0L ||
  is.na(hybas_col)
) {
  hybas_col <- NA_character_
}

diagnostic_pattern <- paste(
  c(
    "^row_id$",
    "^sr87_sr86$",
    "reference",
    "citation",
    "source",
    "paper",
    "study",
    "doi",
    "^longitude$",
    "^latitude$",
    "hybas",
    "hydro",
    "river",
    "reach",
    "segment",
    "link",
    "comid",
    "join",
    "distance",
    "nearest",
    "basin",
    "catchment",
    "local_geo_age",
    "up_geo_age"
  ),
  collapse = "|"
)

diagnostic_cols <- names(model)[
  grepl(
    diagnostic_pattern,
    names(model),
    ignore.case = TRUE
  )
]

diagnostic_cols <- unique(
  c(
    diagnostic_cols,
    "p0_missing_n",
    "p0_complete"
  )
)

extreme <- model |>
  filter(
    is.finite(sr87_sr86),
    sr87_sr86 >= 0.800
  ) |>
  arrange(
    desc(sr87_sr86)
  )

complete_candidates <- model |>
  filter(
    p0_complete,
    is.finite(longitude_std),
    is.finite(latitude_std)
  )

haversine_km <- function(
  lon1,
  lat1,
  lon2,
  lat2
) {
  radius_km <- 6371.0088

  lon1 <- lon1 * pi / 180
  lat1 <- lat1 * pi / 180
  lon2 <- lon2 * pi / 180
  lat2 <- lat2 * pi / 180

  dlon <- lon2 - lon1
  dlat <- lat2 - lat1

  a <- sin(dlat / 2)^2 +
    cos(lat1) *
    cos(lat2) *
    sin(dlon / 2)^2

  2 * radius_km * asin(
    pmin(
      1,
      sqrt(a)
    )
  )
}

nearest_results <- lapply(
  seq_len(nrow(extreme)),
  function(index) {
    current <- extreme[index, ]

    valid_point <- is.finite(
      current$longitude_std
    ) &&
      is.finite(
        current$latitude_std
      )

    if (
      !valid_point ||
      nrow(complete_candidates) == 0L
    ) {
      return(
        data.frame(
          row_id = current$row_id,
          nearest_complete_row_id = NA_character_,
          nearest_complete_distance_km = NA_real_,
          nearest_complete_observed = NA_real_,
          same_hybas_complete_n = NA_integer_,
          nearest_same_hybas_distance_km = NA_real_
        )
      )
    }

    distances <- haversine_km(
      current$longitude_std,
      current$latitude_std,
      complete_candidates$longitude_std,
      complete_candidates$latitude_std
    )

    nearest_index <- which.min(
      distances
    )

    same_hybas_n <- NA_integer_
    nearest_same_hybas <- NA_real_

    if (
      !is.na(hybas_col) &&
      !is.na(current[[hybas_col]]) &&
      nzchar(
        as.character(
          current[[hybas_col]]
        )
      )
    ) {
      same_hybas <- complete_candidates |>
        filter(
          as.character(
            .data[[hybas_col]]
          ) ==
            as.character(
              current[[hybas_col]]
            )
        )

      same_hybas_n <- nrow(
        same_hybas
      )

      if (same_hybas_n > 0L) {
        nearest_same_hybas <- min(
          haversine_km(
            current$longitude_std,
            current$latitude_std,
            same_hybas$longitude_std,
            same_hybas$latitude_std
          ),
          na.rm = TRUE
        )
      }
    }

    data.frame(
      row_id = current$row_id,

      nearest_complete_row_id =
        complete_candidates$row_id[
          nearest_index
        ],

      nearest_complete_distance_km =
        distances[
          nearest_index
        ],

      nearest_complete_observed =
        complete_candidates$sr87_sr86[
          nearest_index
        ],

      same_hybas_complete_n =
        same_hybas_n,

      nearest_same_hybas_distance_km =
        nearest_same_hybas
    )
  }
) |>
  bind_rows()

extreme_audit <- extreme |>
  select(
    any_of(
      diagnostic_cols
    )
  ) |>
  left_join(
    nearest_results,
    by = "row_id"
  )

write_csv(
  extreme_audit,
  file.path(
    out_dir,
    "extreme_feature_linkage_audit.csv"
  )
)

column_availability <- data.frame(
  column = names(model),
  nonmissing_all_rows = vapply(
    model,
    function(x) {
      sum(
        !is.na(x) &
          !(is.character(x) & x == "")
      )
    },
    numeric(1)
  ),
  nonmissing_extreme_rows = vapply(
    extreme,
    function(x) {
      sum(
        !is.na(x) &
          !(is.character(x) & x == "")
      )
    },
    numeric(1)
  )
) |>
  arrange(
    nonmissing_extreme_rows,
    column
  )

write_csv(
  column_availability,
  file.path(
    out_dir,
    "column_availability_extreme_vs_all.csv"
  )
)

if (!is.na(source_col)) {
  source_summary <- model |>
    mutate(
      source_label = as.character(
        .data[[source_col]]
      )
    ) |>
    group_by(
      source_label
    ) |>
    summarise(
      n_total = n(),

      n_p0_complete = sum(
        p0_complete
      ),

      proportion_p0_complete = mean(
        p0_complete
      ),

      n_ge_0p750 = sum(
        sr87_sr86 >= 0.750,
        na.rm = TRUE
      ),

      n_ge_0p800 = sum(
        sr87_sr86 >= 0.800,
        na.rm = TRUE
      ),

      maximum_sr = max(
        sr87_sr86,
        na.rm = TRUE
      ),

      .groups = "drop"
    ) |>
    arrange(
      desc(n_ge_0p800),
      desc(maximum_sr)
    )

  write_csv(
    source_summary,
    file.path(
      out_dir,
      "feature_completeness_by_source.csv"
    )
  )
}

if (!is.na(hybas_col)) {
  hybas_summary <- model |>
    mutate(
      hybas_label = as.character(
        .data[[hybas_col]]
      )
    ) |>
    group_by(
      hybas_label
    ) |>
    summarise(
      n_total = n(),

      n_p0_complete = sum(
        p0_complete
      ),

      n_ge_0p800 = sum(
        sr87_sr86 >= 0.800,
        na.rm = TRUE
      ),

      max_sr = max(
        sr87_sr86,
        na.rm = TRUE
      ),

      .groups = "drop"
    ) |>
    filter(
      n_ge_0p800 > 0L
    ) |>
    arrange(
      desc(max_sr)
    )

  write_csv(
    hybas_summary,
    file.path(
      out_dir,
      "extreme_hybas_feature_support.csv"
    )
  )
}

cat(
  "Extreme rows: ",
  nrow(extreme),
  "\n",
  sep = ""
)

cat(
  "P0-complete extreme rows: ",
  sum(extreme$p0_complete),
  "\n",
  sep = ""
)

cat(
  "Detected source column: ",
  ifelse(
    is.na(source_col),
    "NONE",
    source_col
  ),
  "\n",
  sep = ""
)

cat(
  "Detected HYBAS column: ",
  ifelse(
    is.na(hybas_col),
    "NONE",
    hybas_col
  ),
  "\n",
  sep = ""
)

cat(
  "EXTREME FEATURE LINKAGE AUDIT COMPLETE\n"
)

cat(
  "Outputs written to: ",
  normalizePath(
    out_dir,
    mustWork = TRUE
  ),
  "\n",
  sep = ""
)
