#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
})

project_dir <- Sys.getenv(
  "SR_GLOBAL_DIR",
  unset = "/home/zhangmeng/projects/sr_global"
)

regions <- c(
  "af", "ar", "as",
  "au", "eu", "gr",
  "na", "sa", "si"
)

model_path <- file.path(
  project_dir,
  "models/global/final_RF_QRF",
  "final_upstream_clay_RF_QRF.rds"
)

out_dir <- file.path(
  project_dir,
  "data_processed/global/final_prediction"
)

qc_dir <- file.path(
  project_dir,
  "outputs/global/final_river_prediction_qc"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

dir.create(
  qc_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

model_bundle <- readRDS(
  model_path
)

final_predictors <- model_bundle$predictors

space_vars <- c(
  "sp_x",
  "sp_y",
  "sp_z"
)

hydro_vars <- c(
  "log_DIS_AV_CMS",
  "log_UPLAND_SKM",
  "log_CATCH_SKM",
  "log_LENGTH_KM",
  "log_DIST_DN_KM",
  "log_DIST_UP_KM",
  "ORD_STRA",
  "ORD_CLAS",
  "ORD_FLOW"
)

l6_predictors <- setdiff(
  final_predictors,
  c(
    space_vars,
    hydro_vars
  )
)

cat(
  "Final predictor count:",
  length(final_predictors),
  "\n"
)

cat(
  "L6 predictor count:",
  length(l6_predictors),
  "\n"
)

cat(
  "L6 predictors:\n",
  paste(
    l6_predictors,
    collapse = "\n"
  ),
  "\n\n"
)

if (length(l6_predictors) != 16) {
  stop(
    "Expected 16 L6 predictors, found ",
    length(l6_predictors)
  )
}

make_key <- function(x) {
  sprintf(
    "%.0f",
    as.numeric(x)
  )
}

region_tables <- list()
region_qc <- list()

for (r in regions) {

  cat(
    "\nBuilding L6 table for region: ",
    r,
    "\n",
    sep = ""
  )

  geo_file <- file.path(
    project_dir,
    "data_processed/global/glim_l6_by_region",
    paste0(
      "l6_glim_local_upstream_",
      r,
      ".rds"
    )
  )

  climate_file <- file.path(
    project_dir,
    paste0(
      "data_processed/global/",
      "climate_terrain_l6_by_region"
    ),
    paste0(
      "l6_climate_terrain_local_upstream_",
      r,
      ".rds"
    )
  )

  soil_file <- file.path(
    project_dir,
    "data_processed/global/soil_l6_by_region",
    paste0(
      "l6_soil_local_upstream_",
      r,
      ".rds"
    )
  )

  geo <- readRDS(geo_file) %>%
    mutate(
      region = r,
      hybas_key = make_key(HYBAS_ID)
    )

  climate <- readRDS(climate_file) %>%
    mutate(
      region = r,
      hybas_key = make_key(HYBAS_ID)
    )

  soil <- readRDS(soil_file) %>%
    mutate(
      region = r,
      hybas_key = make_key(HYBAS_ID)
    )

  if (
    anyDuplicated(geo$hybas_key) ||
    anyDuplicated(climate$hybas_key) ||
    anyDuplicated(soil$hybas_key)
  ) {
    stop(
      "Duplicate L6 keys detected in region ",
      r
    )
  }

  geo_predictors <- intersect(
    l6_predictors,
    names(geo)
  )

  climate_predictors <- intersect(
    l6_predictors,
    names(climate)
  )

  soil_predictors <- intersect(
    l6_predictors,
    names(soil)
  )

  geo_keep <- geo %>%
    select(
      region,
      hybas_key,
      HYBAS_ID,
      NEXT_DOWN,
      MAIN_BAS,
      SUB_AREA,
      UP_AREA,
      PFAF_ID,
      all_of(geo_predictors),
      any_of(
        c(
          "up_glim_coverage_ratio",
          "up_lith_area_km2",
          "up_water_ice_frac_all",
          "up_no_data_frac_all"
        )
      )
    )

  climate_keep <- climate %>%
    select(
      region,
      hybas_key,
      all_of(climate_predictors),
      any_of(
        c(
          "up_bio1_C_coverage_ratio",
          "up_bio4_C_sd_coverage_ratio",
          "up_bio12_mm_coverage_ratio",
          "up_bio15_cv_coverage_ratio",
          "up_ai_ratio_coverage_ratio",
          "up_et0_mm_coverage_ratio",
          "up_elevation_m_coverage_ratio"
        )
      )
    )

  soil_keep <- soil %>%
    select(
      region,
      hybas_key,
      all_of(soil_predictors),
      any_of(
        c(
          "up_soil_clay_pct_0_30cm_coverage_ratio"
        )
      )
    )

  joined <- geo_keep %>%
    left_join(
      climate_keep,
      by = c(
        "region",
        "hybas_key"
      )
    ) %>%
    left_join(
      soil_keep,
      by = c(
        "region",
        "hybas_key"
      )
    )

  if (nrow(joined) != nrow(geo)) {
    stop(
      "L6 row count changed after joins in region ",
      r,
      ": ",
      nrow(geo),
      " -> ",
      nrow(joined)
    )
  }

  missing_predictor_columns <- setdiff(
    l6_predictors,
    names(joined)
  )

  if (length(missing_predictor_columns) > 0) {
    stop(
      "Missing L6 predictor columns in region ",
      r,
      ": ",
      paste(
        missing_predictor_columns,
        collapse = ", "
      )
    )
  }

  numeric_predictors <- joined[
    ,
    l6_predictors,
    drop = FALSE
  ]

  complete_l6 <- complete.cases(
    numeric_predictors
  ) &
    apply(
      numeric_predictors,
      1,
      function(z) {
        all(is.finite(z))
      }
    )

  joined$l6_predictors_complete <-
    complete_l6

  region_tables[[r]] <- joined

  region_qc[[r]] <- tibble(
    region = r,
    n_l6 = nrow(joined),
    n_complete_l6_predictors =
      sum(complete_l6),
    pct_complete_l6_predictors =
      100 * mean(complete_l6)
  )

  cat(
    "L6 basins:",
    nrow(joined),
    "\n"
  )

  cat(
    "Complete model covariates:",
    sum(complete_l6),
    "\n"
  )
}

global_l6 <- bind_rows(
  region_tables
)

global_qc <- bind_rows(
  region_qc
)

if (
  anyDuplicated(
    paste(
      global_l6$region,
      global_l6$hybas_key,
      sep = "_"
    )
  )
) {
  stop(
    "Duplicate global region + hybas_key combinations."
  )
}

missing_summary <- tibble(
  variable = l6_predictors,
  n_missing_or_nonfinite = vapply(
    l6_predictors,
    function(v) {
      sum(
        !is.finite(
          as.numeric(
            global_l6[[v]]
          )
        )
      )
    },
    integer(1)
  )
) %>%
  arrange(
    desc(n_missing_or_nonfinite)
  )

cat(
  "\n===== GLOBAL L6 QC =====\n"
)

print(
  global_qc,
  n = Inf,
  width = Inf
)

cat(
  "\n===== L6 VARIABLE MISSINGNESS =====\n"
)

print(
  missing_summary,
  n = Inf,
  width = Inf
)

cat(
  "\nGlobal L6 rows:",
  nrow(global_l6),
  "\n"
)

cat(
  "Complete L6 rows:",
  sum(
    global_l6$l6_predictors_complete
  ),
  "\n"
)

saveRDS(
  global_l6,
  file.path(
    out_dir,
    "global_l6_upstream_prediction_covariates.rds"
  )
)

write_csv(
  global_l6,
  file.path(
    out_dir,
    "global_l6_upstream_prediction_covariates.csv"
  )
)

write_csv(
  global_qc,
  file.path(
    qc_dir,
    "global_l6_prediction_covariate_coverage_by_region.csv"
  )
)

write_csv(
  missing_summary,
  file.path(
    qc_dir,
    "global_l6_prediction_covariate_missingness.csv"
  )
)

cat(
  "\nGLOBAL L6 PREDICTION TABLE BUILT\n"
)
