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
  "data_processed/global/global_model_sites_5km_with_geology_climate_terrain_complete.rds"
)

soil_dir <- file.path(
  root_dir,
  "data_processed/global/soil_l6_by_region"
)

out_dir <- file.path(
  root_dir,
  "data_processed/global"
)

qc_dir <- file.path(
  root_dir,
  "outputs/global/soil_site_qc"
)

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(qc_dir, recursive = TRUE, showWarnings = FALSE)

regions <- c(
  "af", "ar", "as", "au", "eu",
  "gr", "na", "sa", "si"
)

soil_files <- file.path(
  soil_dir,
  paste0(
    "l6_soil_local_upstream_",
    regions,
    ".rds"
  )
)

missing_files <- soil_files[
  !file.exists(soil_files)
]

if (length(missing_files) > 0) {
  stop(
    "Missing regional soil files:\n",
    paste(missing_files, collapse = "\n")
  )
}

soil_predictors <- c(
  "local_soil_pH_0_30cm",
  "local_soil_clay_pct_0_30cm",
  "up_soil_pH_0_30cm",
  "up_soil_clay_pct_0_30cm"
)

soil_coverage_columns <- c(
  "local_soil_pH_0_30cm_coverage_ratio",
  "local_soil_clay_pct_0_30cm_coverage_ratio",
  "up_soil_pH_0_30cm_coverage_ratio",
  "up_soil_clay_pct_0_30cm_coverage_ratio"
)

soil <- bind_rows(
  lapply(
    soil_files,
    readRDS
  )
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
  soil_predictors,
  soil_coverage_columns
)

missing_columns <- setdiff(
  required_columns,
  names(soil)
)

if (length(missing_columns) > 0) {
  stop(
    "Missing soil columns: ",
    paste(missing_columns, collapse = ", ")
  )
}

duplicate_keys <- soil %>%
  count(region, hybas_key) %>%
  filter(n > 1)

if (nrow(duplicate_keys) > 0) {
  stop("Duplicate region + HYBAS_ID keys found.")
}

soil_join <- soil %>%
  select(
    region,
    hybas_key,
    all_of(soil_predictors),
    all_of(soil_coverage_columns)
  )

sites <- readRDS(site_file) %>%
  mutate(
    region = as.character(region),
    hybas_key = as.character(hybas_key)
  )

n_before <- nrow(sites)

sites_soil <- sites %>%
  left_join(
    soil_join,
    by = c(
      "region",
      "hybas_key"
    )
  )

if (nrow(sites_soil) != n_before) {
  stop(
    "Row count changed after join: ",
    n_before,
    " to ",
    nrow(sites_soil)
  )
}

minimum_finite <- function(data) {

  x <- as.matrix(data)

  apply(
    x,
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

sites_soil$soil_predictors_complete <-
  complete.cases(
    sites_soil[
      ,
      soil_predictors,
      drop = FALSE
    ]
  )

sites_soil$minimum_soil_coverage <-
  minimum_finite(
    sites_soil[
      ,
      soil_coverage_columns,
      drop = FALSE
    ]
  )

sites_soil$soil_coverage_ge_0p5 <-
  sites_soil$soil_predictors_complete &
  sites_soil$minimum_soil_coverage >= 0.5

sites_soil$soil_coverage_ge_0p8 <-
  sites_soil$soil_predictors_complete &
  sites_soil$minimum_soil_coverage >= 0.8

sites_soil$soil_coverage_ge_0p9 <-
  sites_soil$soil_predictors_complete &
  sites_soil$minimum_soil_coverage >= 0.9

saveRDS(
  sites_soil,
  file.path(
    out_dir,
    "global_model_sites_5km_with_geology_climate_terrain_soil.rds"
  )
)

complete_sites <- sites_soil %>%
  filter(
    soil_predictors_complete
  )

saveRDS(
  complete_sites,
  file.path(
    out_dir,
    "global_model_sites_5km_with_geology_climate_terrain_soil_complete.rds"
  )
)

summary_table <- tibble(
  metric = c(
    "all_sites",
    "soil_predictors_complete",
    "soil_coverage_ge_0p5",
    "soil_coverage_ge_0p8",
    "soil_coverage_ge_0p9"
  ),
  value = c(
    nrow(sites_soil),
    sum(
      sites_soil$soil_predictors_complete,
      na.rm = TRUE
    ),
    sum(
      sites_soil$soil_coverage_ge_0p5,
      na.rm = TRUE
    ),
    sum(
      sites_soil$soil_coverage_ge_0p8,
      na.rm = TRUE
    ),
    sum(
      sites_soil$soil_coverage_ge_0p9,
      na.rm = TRUE
    )
  )
)

missing_by_variable <- bind_rows(
  lapply(
    soil_predictors,
    function(v) {

      tibble(
        variable = v,
        n_missing = sum(
          !is.finite(
            sites_soil[[v]]
          )
        )
      )
    }
  )
)

regional_summary <- sites_soil %>%
  group_by(region) %>%
  summarise(
    n_sites = n(),

    n_complete =
      sum(
        soil_predictors_complete,
        na.rm = TRUE
      ),

    n_coverage_ge_0p5 =
      sum(
        soil_coverage_ge_0p5,
        na.rm = TRUE
      ),

    n_coverage_ge_0p8 =
      sum(
        soil_coverage_ge_0p8,
        na.rm = TRUE
      ),

    n_coverage_ge_0p9 =
      sum(
        soil_coverage_ge_0p9,
        na.rm = TRUE
      ),

    minimum_soil_coverage =
      min(
        minimum_soil_coverage,
        na.rm = TRUE
      ),

    .groups = "drop"
  ) %>%
  arrange(region)

write_csv(
  summary_table,
  file.path(
    qc_dir,
    "global_site_soil_summary.csv"
  )
)

write_csv(
  missing_by_variable,
  file.path(
    qc_dir,
    "global_site_soil_missing_by_variable.csv"
  )
)

write_csv(
  regional_summary,
  file.path(
    qc_dir,
    "global_site_soil_summary_by_region.csv"
  )
)

write_csv(
  sites_soil %>%
    filter(
      !soil_predictors_complete |
        minimum_soil_coverage < 0.8
    ) %>%
    select(
      any_of(
        c(
          "site_id",
          "longitude",
          "latitude",
          "region",
          "sr",
          "HYBAS_ID"
        )
      ),
      all_of(soil_predictors),
      minimum_soil_coverage,
      soil_predictors_complete,
      soil_coverage_ge_0p8
    ),
  file.path(
    qc_dir,
    "global_sites_with_missing_or_low_soil_coverage.csv"
  )
)

cat("\n===== SITE SOIL SUMMARY =====\n")
print(
  summary_table,
  n = Inf
)

cat("\n===== MISSING BY VARIABLE =====\n")
print(
  missing_by_variable,
  n = Inf
)

cat("\n===== REGIONAL SOIL SUMMARY =====\n")
print(
  regional_summary,
  n = Inf,
  width = Inf
)

cat(
  "\nSoil variables attached to sites.\n"
)
