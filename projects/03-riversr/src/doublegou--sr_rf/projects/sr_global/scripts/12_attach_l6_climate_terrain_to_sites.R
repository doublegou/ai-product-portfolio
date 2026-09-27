#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
})

root_dir <- Sys.getenv(
  "SR_GLOBAL_DIR",
  unset = "/home/zhangmeng/projects/sr_global"
)

site_file <- file.path(
  root_dir,
  "data_processed/global/global_model_sites_5km_with_l6_glim_complete.rds"
)

climate_dir <- file.path(
  root_dir,
  "data_processed/global/climate_terrain_l6_by_region"
)

out_dir <- file.path(
  root_dir,
  "data_processed/global"
)

qc_dir <- file.path(
  root_dir,
  "outputs/global/climate_terrain_site_qc"
)

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(qc_dir, recursive = TRUE, showWarnings = FALSE)

regions <- c(
  "af", "ar", "as", "au", "eu",
  "gr", "na", "sa", "si"
)

files <- file.path(
  climate_dir,
  paste0(
    "l6_climate_terrain_local_upstream_",
    regions,
    ".rds"
  )
)

missing_files <- files[
  !file.exists(files)
]

if (length(missing_files) > 0) {
  stop(
    "Missing regional files:\n",
    paste(missing_files, collapse = "\n")
  )
}

variable_names <- c(
  "bio1_C",
  "bio4_C_sd",
  "bio12_mm",
  "bio15_cv",
  "ai_ratio",
  "et0_mm",
  "elevation_m"
)

local_predictors <- paste0(
  "local_",
  variable_names
)

upstream_predictors <- paste0(
  "up_",
  variable_names
)

predictor_columns <- c(
  local_predictors,
  upstream_predictors
)

local_coverage_columns <- paste0(
  local_predictors,
  "_coverage_ratio"
)

upstream_coverage_columns <- paste0(
  upstream_predictors,
  "_coverage_ratio"
)

coverage_columns <- c(
  local_coverage_columns,
  upstream_coverage_columns
)

climate <- bind_rows(
  lapply(files, readRDS)
) %>%
  mutate(
    region = as.character(region),
    hybas_key = sprintf(
      "%.0f",
      as.numeric(HYBAS_ID)
    )
  )

required_columns <- c(
  "region",
  "hybas_key",
  predictor_columns,
  coverage_columns
)

missing_columns <- setdiff(
  required_columns,
  names(climate)
)

if (length(missing_columns) > 0) {
  stop(
    "Missing climate columns: ",
    paste(missing_columns, collapse = ", ")
  )
}

duplicate_keys <- climate %>%
  count(region, hybas_key) %>%
  filter(n > 1)

if (nrow(duplicate_keys) > 0) {
  stop("Duplicate region + HYBAS_ID keys found.")
}

climate_join <- climate %>%
  select(
    region,
    hybas_key,
    all_of(predictor_columns),
    all_of(coverage_columns)
  )

sites <- readRDS(site_file) %>%
  mutate(
    region = as.character(region),
    hybas_key = as.character(hybas_key)
  )

n_before <- nrow(sites)

sites_climate <- sites %>%
  left_join(
    climate_join,
    by = c(
      "region",
      "hybas_key"
    )
  )

if (nrow(sites_climate) != n_before) {
  stop(
    "Row count changed after join: ",
    n_before,
    " to ",
    nrow(sites_climate)
  )
}

minimum_finite <- function(data) {

  matrix_data <- as.matrix(data)

  apply(
    matrix_data,
    1,
    function(z) {

      z <- z[is.finite(z)]

      if (length(z) == 0) {
        NA_real_
      } else {
        min(z)
      }
    }
  )
}

sites_climate$climate_predictors_complete <-
  complete.cases(
    sites_climate[
      ,
      predictor_columns,
      drop = FALSE
    ]
  )

sites_climate$minimum_local_climate_coverage <-
  minimum_finite(
    sites_climate[
      ,
      local_coverage_columns,
      drop = FALSE
    ]
  )

sites_climate$minimum_upstream_climate_coverage <-
  minimum_finite(
    sites_climate[
      ,
      upstream_coverage_columns,
      drop = FALSE
    ]
  )

sites_climate$all_climate_coverage_ge_0p8 <-
  sites_climate$climate_predictors_complete &
  sites_climate$minimum_local_climate_coverage >= 0.8 &
  sites_climate$minimum_upstream_climate_coverage >= 0.8

sites_climate$all_climate_coverage_ge_0p9 <-
  sites_climate$climate_predictors_complete &
  sites_climate$minimum_local_climate_coverage >= 0.9 &
  sites_climate$minimum_upstream_climate_coverage >= 0.9

saveRDS(
  sites_climate,
  file.path(
    out_dir,
    "global_model_sites_5km_with_geology_climate_terrain.rds"
  )
)

complete_sites <- sites_climate %>%
  filter(
    climate_predictors_complete
  )

saveRDS(
  complete_sites,
  file.path(
    out_dir,
    "global_model_sites_5km_with_geology_climate_terrain_complete.rds"
  )
)

summary_table <- tibble(
  metric = c(
    "all_sites",
    "climate_predictors_complete",
    "all_climate_coverage_ge_0p8",
    "all_climate_coverage_ge_0p9"
  ),
  value = c(
    nrow(sites_climate),
    sum(
      sites_climate$climate_predictors_complete,
      na.rm = TRUE
    ),
    sum(
      sites_climate$all_climate_coverage_ge_0p8,
      na.rm = TRUE
    ),
    sum(
      sites_climate$all_climate_coverage_ge_0p9,
      na.rm = TRUE
    )
  )
)

missing_by_variable <- bind_rows(
  lapply(
    predictor_columns,
    function(v) {
      tibble(
        variable = v,
        n_missing = sum(
          !is.finite(sites_climate[[v]])
        )
      )
    }
  )
)

regional_summary <- sites_climate %>%
  group_by(region) %>%
  summarise(
    n_sites = n(),

    n_complete =
      sum(
        climate_predictors_complete,
        na.rm = TRUE
      ),

    n_coverage_ge_0p8 =
      sum(
        all_climate_coverage_ge_0p8,
        na.rm = TRUE
      ),

    n_coverage_ge_0p9 =
      sum(
        all_climate_coverage_ge_0p9,
        na.rm = TRUE
      ),

    minimum_local_coverage =
      min(
        minimum_local_climate_coverage,
        na.rm = TRUE
      ),

    minimum_upstream_coverage =
      min(
        minimum_upstream_climate_coverage,
        na.rm = TRUE
      ),

    .groups = "drop"
  ) %>%
  arrange(region)

write_csv(
  summary_table,
  file.path(
    qc_dir,
    "global_site_climate_terrain_summary.csv"
  )
)

write_csv(
  missing_by_variable,
  file.path(
    qc_dir,
    "global_site_climate_terrain_missing_by_variable.csv"
  )
)

write_csv(
  regional_summary,
  file.path(
    qc_dir,
    "global_site_climate_terrain_summary_by_region.csv"
  )
)

write_csv(
  sites_climate %>%
    filter(
      !climate_predictors_complete |
        !all_climate_coverage_ge_0p8
    ) %>%
    select(
      site_id,
      longitude,
      latitude,
      region,
      sr,
      HYBAS_ID,
      all_of(predictor_columns),
      minimum_local_climate_coverage,
      minimum_upstream_climate_coverage,
      climate_predictors_complete,
      all_climate_coverage_ge_0p8
    ),
  file.path(
    qc_dir,
    "global_sites_with_missing_or_low_climate_coverage.csv"
  )
)

cat("\n===== SITE SUMMARY =====\n")
print(summary_table, n = Inf)

cat("\n===== MISSING BY VARIABLE =====\n")
print(missing_by_variable, n = Inf)

cat("\n===== REGIONAL SUMMARY =====\n")
print(regional_summary, n = Inf, width = Inf)

cat(
  "\nClimate and terrain variables attached to sites.\n"
)
