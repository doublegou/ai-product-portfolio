#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

site_dir <- Sys.getenv(
  "SR_GLOBAL_DIR",
  unset = "/home/zhangmeng/projects/sr_global"
)

obs_file <- file.path(
  site_dir,
  "data_processed/global/global_model_primary_observations_5km.rds"
)

out_data <- file.path(site_dir, "data_processed/global")
out_qc  <- file.path(site_dir, "outputs/global/qc")

dir.create(out_data, recursive = TRUE, showWarnings = FALSE)
dir.create(out_qc, recursive = TRUE, showWarnings = FALSE)

obs <- readRDS(obs_file)

# 注意：先使用不同名称，避免覆盖原始 sr
site_sr_summary <- obs %>%
  group_by(site_id) %>%
  summarise(
    n_site_observations = n(),
    sr_median = median(sr, na.rm = TRUE),
    sr_mean = mean(sr, na.rm = TRUE),
    sr_min = min(sr, na.rm = TRUE),
    sr_max = max(sr, na.rm = TRUE),
    sr_sd = ifelse(n() > 1, sd(sr, na.rm = TRUE), NA_real_),
    sr_range = sr_max - sr_min,
    .groups = "drop"
  ) %>%
  rename(sr = sr_median)

# 每个 site 保留一条空间与河网属性
site_attributes <- obs %>%
  arrange(global_row_id) %>%
  distinct(site_id, .keep_all = TRUE) %>%
  select(
    -sr,
    -source_sample_id,
    -global_row_id,
    -n_observations_at_site,
    -any_of(c(
      "n_site_observations",
      "sr_mean",
      "sr_min",
      "sr_max",
      "sr_sd",
      "sr_range"
    ))
  )

site_primary_5km <- site_attributes %>%
  left_join(site_sr_summary, by = "site_id") %>%
  relocate(
    site_id,
    n_site_observations,
    longitude,
    latitude,
    sr,
    sr_mean,
    sr_min,
    sr_max,
    sr_sd,
    sr_range
  )

saveRDS(
  site_primary_5km,
  file.path(
    out_data,
    "global_model_primary_sites_5km.rds"
  )
)

write_csv(
  site_primary_5km,
  file.path(
    out_qc,
    "global_model_primary_sites_5km.csv"
  )
)

cat("\nRebuilt unique sites:", nrow(site_primary_5km), "\n")

cat("\nWithin-site Sr range summary:\n")
print(
  quantile(
    site_primary_5km$sr_range[
      site_primary_5km$n_site_observations > 1
    ],
    probs = c(0, 0.25, 0.5, 0.75, 0.9, 0.95, 0.99, 1),
    na.rm = TRUE
  ),
  digits = 8
)

cat("\nLargest site ranges:\n")
print(
  site_primary_5km %>%
    filter(n_site_observations > 1) %>%
    arrange(desc(sr_range)) %>%
    select(
      site_id,
      n_site_observations,
      sr_min,
      sr,
      sr_max,
      sr_range,
      region
    ) %>%
    head(20),
  n = 20,
  digits = 8
)

cat("\nSite-level dataset rebuilt successfully.\n")
