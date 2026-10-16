#!/usr/bin/env Rscript

options(
  stringsAsFactors = FALSE,
  scipen = 999
)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
})

setwd(
  normalizePath(
    "~/river_sr_isoscape_v2_cluster",
    mustWork = TRUE
  )
)

model_path <- "data/processed/model_table_age_test.rds"
oof_path <- "outputs/experiment_age_stop_test/oof_predictions.rds"
out_dir <- "outputs/extreme_value_exclusion_audit"

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

oof <- readRDS(oof_path)

if (!is.data.frame(oof)) {
  oof <- bind_rows(oof)
}

required_model_columns <- c(
  "row_id",
  "sr87_sr86"
)

missing_required <- setdiff(
  required_model_columns,
  names(model)
)

if (length(missing_required) > 0L) {
  stop(
    "Missing model columns: ",
    paste(
      missing_required,
      collapse = ", "
    )
  )
}

if (
  !"row_id" %in% names(oof) ||
  !"predictor_set" %in% names(oof)
) {
  stop(
    "OOF table must contain row_id and predictor_set."
  )
}

model$row_id <- as.character(
  model$row_id
)

oof$row_id <- as.character(
  oof$row_id
)

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

missing_predictor_columns <- setdiff(
  p0_predictors,
  names(model)
)

if (length(missing_predictor_columns) > 0L) {
  stop(
    "Missing P0 predictor columns:\n",
    paste(
      missing_predictor_columns,
      collapse = "\n"
    )
  )
}

p0_oof_ids <- oof |>
  filter(
    predictor_set == "P0"
  ) |>
  distinct(
    row_id
  ) |>
  pull(
    row_id
  )

predictor_numeric <- as.data.frame(
  lapply(
    model[p0_predictors],
    function(x) {
      suppressWarnings(
        as.numeric(
          as.character(x)
        )
      )
    }
  )
)

bad_matrix <- !is.finite(
  as.matrix(
    predictor_numeric
  )
)

model$p0_missing_n <- rowSums(
  bad_matrix
)

model$p0_missing_variables <- apply(
  bad_matrix,
  1,
  function(is_bad) {
    paste(
      p0_predictors[is_bad],
      collapse = ";"
    )
  }
)

model$in_formal_common_sample <-
  model$row_id %in% p0_oof_ids

threshold_summary <- bind_rows(
  lapply(
    c(
      0.720,
      0.750,
      0.800,
      0.900
    ),
    function(threshold) {
      subset_rows <- model |>
        filter(
          is.finite(sr87_sr86),
          sr87_sr86 >= threshold
        )

      tibble(
        threshold = threshold,
        original_n = nrow(subset_rows),

        retained_in_formal_common = sum(
          subset_rows$in_formal_common_sample
        ),

        excluded_from_formal_common = sum(
          !subset_rows$in_formal_common_sample
        ),

        retained_max_observed = if (
          any(
            subset_rows$in_formal_common_sample
          )
        ) {
          max(
            subset_rows$sr87_sr86[
              subset_rows$in_formal_common_sample
            ],
            na.rm = TRUE
          )
        } else {
          NA_real_
        },

        excluded_max_observed = if (
          any(
            !subset_rows$in_formal_common_sample
          )
        ) {
          max(
            subset_rows$sr87_sr86[
              !subset_rows$in_formal_common_sample
            ],
            na.rm = TRUE
          )
        } else {
          NA_real_
        }
      )
    }
  )
)

metadata_candidates <- c(
  "row_id",
  "sr87_sr86",
  "reference_id",
  "longitude",
  "latitude",
  "HYBAS_ID",
  "join_method",
  "join_distance_km",
  "local_geo_age_mean_ma",
  "up_geo_age_mean_ma",
  "p0_missing_n",
  "p0_missing_variables",
  "in_formal_common_sample"
)

extreme_rows <- model |>
  filter(
    is.finite(sr87_sr86),
    sr87_sr86 >= 0.800
  ) |>
  select(
    any_of(
      metadata_candidates
    )
  ) |>
  arrange(
    desc(sr87_sr86)
  )

excluded_extreme_rows <- extreme_rows |>
  filter(
    !in_formal_common_sample
  )

missingness_summary <- excluded_extreme_rows |>
  select(
    row_id,
    p0_missing_variables
  ) |>
  separate_rows(
    p0_missing_variables,
    sep = ";"
  ) |>
  filter(
    !is.na(p0_missing_variables),
    nzchar(p0_missing_variables)
  ) |>
  count(
    p0_missing_variables,
    name = "excluded_extreme_rows_missing",
    sort = TRUE
  )

all_excluded <- model |>
  filter(
    !in_formal_common_sample
  ) |>
  select(
    any_of(
      metadata_candidates
    )
  ) |>
  arrange(
    desc(sr87_sr86)
  )

write_csv(
  threshold_summary,
  file.path(
    out_dir,
    "threshold_retention_summary.csv"
  )
)

write_csv(
  extreme_rows,
  file.path(
    out_dir,
    "all_original_extreme_rows_ge_0p800.csv"
  )
)

write_csv(
  excluded_extreme_rows,
  file.path(
    out_dir,
    "excluded_extreme_rows_ge_0p800.csv"
  )
)

write_csv(
  missingness_summary,
  file.path(
    out_dir,
    "excluded_extreme_missingness_by_variable.csv"
  )
)

write_csv(
  all_excluded,
  file.path(
    out_dir,
    "all_rows_excluded_from_formal_common_sample.csv"
  )
)

cat(
  "\n===== SAMPLE RETENTION BY THRESHOLD =====\n"
)

print(
  threshold_summary,
  n = Inf,
  width = Inf
)

cat(
  "\n===== EXCLUDED EXTREME ROWS =====\n"
)

print(
  excluded_extreme_rows,
  n = Inf,
  width = Inf
)

cat(
  "\n===== MISSING VARIABLES AMONG EXCLUDED EXTREMES =====\n"
)

print(
  missingness_summary,
  n = Inf,
  width = Inf
)

cat(
  "\nOriginal model rows: ",
  nrow(model),
  "\n",
  sep = ""
)

cat(
  "Formal common sample rows: ",
  length(unique(p0_oof_ids)),
  "\n",
  sep = ""
)

cat(
  "Original maximum observed value: ",
  max(
    model$sr87_sr86,
    na.rm = TRUE
  ),
  "\n",
  sep = ""
)

cat(
  "Formal common-sample maximum observed value: ",
  max(
    model$sr87_sr86[
      model$in_formal_common_sample
    ],
    na.rm = TRUE
  ),
  "\n",
  sep = ""
)

cat(
  "\nEXTREME EXCLUSION AUDIT COMPLETE\n"
)
