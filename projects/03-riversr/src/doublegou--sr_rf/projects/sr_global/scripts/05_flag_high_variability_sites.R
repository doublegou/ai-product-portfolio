#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

site_dir <- Sys.getenv(
  "SR_GLOBAL_DIR",
  unset = "/home/zhangmeng/projects/sr_global"
)

site_file <- file.path(
  site_dir,
  "data_processed/global/global_model_primary_sites_5km.rds"
)

obs_file <- file.path(
  site_dir,
  "data_processed/global/global_model_primary_observations_5km.rds"
)

out_data <- file.path(site_dir, "data_processed/global")
out_qc <- file.path(site_dir, "outputs/global/qc")

dir.create(out_data, recursive = TRUE, showWarnings = FALSE)
dir.create(out_qc, recursive = TRUE, showWarnings = FALSE)

sites <- readRDS(site_file)
obs <- readRDS(obs_file)

sites_qc <- sites %>%
  mutate(
    sr_range = sr_max - sr_min,

    site_variability_class = case_when(
      n_site_observations == 1 ~ "single_observation",
      sr_range <= 0.005        ~ "stable_le_0p005",
      sr_range <= 0.010        ~ "moderate_0p005_0p010",
      TRUE                     ~ "high_gt_0p010"
    ),

    high_variability = (
      n_site_observations > 1 &
      sr_range > 0.010
    )
  )

# 主模型：保留所有站点，以站点 Sr 中位数作为响应变量
sites_main <- sites_qc

# 严格敏感性模型：去掉站点内 Sr 极差大于 0.010 的重复站点
sites_strict <- sites_qc %>%
  filter(!high_variability)

high_ids <- sites_qc %>%
  filter(high_variability) %>%
  pull(site_id)

high_site_observations <- obs %>%
  filter(site_id %in% high_ids) %>%
  arrange(site_id, sr)

variability_summary <- sites_qc %>%
  group_by(site_variability_class) %>%
  summarise(
    n_sites = n(),
    represented_observations = sum(n_site_observations),
    median_sr_range = median(sr_range, na.rm = TRUE),
    max_sr_range = max(sr_range, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(desc(n_sites))

saveRDS(
  sites_main,
  file.path(
    out_data,
    "global_model_sites_5km_main_all_sites.rds"
  )
)

saveRDS(
  sites_strict,
  file.path(
    out_data,
    "global_model_sites_5km_sensitivity_no_high_variability.rds"
  )
)

write_csv(
  sites_qc,
  file.path(
    out_qc,
    "global_model_sites_5km_with_variability_flags.csv"
  )
)

write_csv(
  sites_qc %>%
    filter(high_variability) %>%
    arrange(desc(sr_range)),
  file.path(
    out_qc,
    "global_high_variability_sites_gt_0p010.csv"
  )
)

write_csv(
  high_site_observations,
  file.path(
    out_qc,
    "global_high_variability_site_raw_observations.csv"
  )
)

write_csv(
  variability_summary,
  file.path(
    out_qc,
    "global_site_variability_class_summary.csv"
  )
)

cat("\nSite variability classes:\n")
print(variability_summary)

cat("\nMain model sites:", nrow(sites_main), "\n")
cat("Strict sensitivity sites:", nrow(sites_strict), "\n")
cat(
  "High-variability sites excluded in strict sensitivity:",
  sum(sites_qc$high_variability),
  "\n"
)

cat("\nHigh-variability sites by region:\n")
print(
  sites_qc %>%
    filter(high_variability) %>%
    count(region, sort = TRUE)
)

cat("\nSite variability flagging finished.\n")
