#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

site_dir <- Sys.getenv(
  "SR_GLOBAL_DIR",
  unset = "/home/zhangmeng/projects/sr_global"
)

in_file <- file.path(
  site_dir,
  "data_processed/global/global_sr_snapped_best_all.rds"
)

out_data <- file.path(site_dir, "data_processed/global")
out_qc   <- file.path(site_dir, "outputs/global/qc")

dir.create(out_data, recursive = TRUE, showWarnings = FALSE)
dir.create(out_qc, recursive = TRUE, showWarnings = FALSE)

d <- readRDS(in_file)

predictor_cols <- c(
  "longitude",
  "latitude",
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

d_qc <- d %>%
  mutate(
    primary_analysis = sr > 0.700 & sr < 0.800,

    sr_qc_group = case_when(
      sr <= 0.700 ~ "low_le_0p700",
      sr >= 0.800 ~ "high_ge_0p800",
      TRUE        ~ "primary_0p700_0p800"
    ),

    snap_group = case_when(
      is.na(region) | !is.finite(snap_dist_m) ~ "unmatched",
      snap_dist_m <= 5000                    ~ "within_5km",
      snap_dist_m <= 10000                   ~ "5_to_10km",
      TRUE                                   ~ "over_10km"
    ),

    predictors_complete = if_all(
      all_of(predictor_cols),
      is.finite
    ),

    site_id = paste0(
      sprintf("%.5f", longitude),
      "_",
      sprintf("%.5f", latitude)
    )
  ) %>%
  group_by(site_id) %>%
  mutate(n_observations_at_site = n()) %>%
  ungroup()

# 主分析：0.700–0.800、5 km 内、HydroRIVERS predictors 完整
obs_primary_5km <- d_qc %>%
  filter(
    primary_analysis,
    snap_group == "within_5km",
    predictors_complete
  )

# 10 km sensitivity
obs_primary_10km <- d_qc %>%
  filter(
    primary_analysis,
    snap_group %in% c("within_5km", "5_to_10km"),
    predictors_complete
  )

# Site-level Sr summaries
site_sr_summary <- obs_primary_5km %>%
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

# 保留每个 site 第一条记录的河网和空间属性
site_attributes <- obs_primary_5km %>%
  arrange(global_row_id) %>%
  group_by(site_id) %>%
  slice(1) %>%
  ungroup() %>%
  select(
    -sr,
    -source_sample_id,
    -global_row_id,
    -n_observations_at_site
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
    sr_sd
  )

# 保存完整 QC、observation-level 和 site-level 数据
saveRDS(
  d_qc,
  file.path(out_data, "global_sr_snapped_qc_all.rds")
)

saveRDS(
  obs_primary_5km,
  file.path(out_data, "global_model_primary_observations_5km.rds")
)

saveRDS(
  obs_primary_10km,
  file.path(out_data, "global_model_primary_observations_10km.rds")
)

saveRDS(
  site_primary_5km,
  file.path(out_data, "global_model_primary_sites_5km.rds")
)

write_csv(
  obs_primary_5km,
  file.path(out_qc, "global_model_primary_observations_5km.csv")
)

write_csv(
  site_primary_5km,
  file.path(out_qc, "global_model_primary_sites_5km.csv")
)

# 未匹配样点
write_csv(
  d_qc %>%
    filter(snap_group == "unmatched") %>%
    select(
      global_row_id,
      source_sample_id,
      longitude,
      latitude,
      sr,
      sr_qc_group
    ),
  file.path(out_qc, "global_unmatched_samples.csv")
)

# 超过 5 km 的样点
write_csv(
  d_qc %>%
    filter(snap_group != "within_5km") %>%
    select(
      global_row_id,
      source_sample_id,
      longitude,
      latitude,
      sr,
      sr_qc_group,
      region,
      snap_dist_m,
      snap_group
    ) %>%
    arrange(desc(snap_dist_m)),
  file.path(out_qc, "global_samples_outside_5km.csv")
)

# 重复站点
duplicate_sites <- obs_primary_5km %>%
  count(site_id, longitude, latitude, name = "n_observations") %>%
  filter(n_observations > 1) %>%
  arrange(desc(n_observations))

write_csv(
  duplicate_sites,
  file.path(out_qc, "global_duplicate_coordinate_sites.csv")
)

# Predictor missingness
missing_predictors <- data.frame(
  variable = predictor_cols,
  n_missing = vapply(
    predictor_cols,
    function(v) sum(!is.finite(d_qc[[v]])),
    numeric(1)
  )
)

write_csv(
  missing_predictors,
  file.path(out_qc, "global_predictor_missingness.csv")
)

# 总结
summary_table <- data.frame(
  metric = c(
    "all_solute_rows",
    "primary_sr_rows",
    "matched_any_region",
    "primary_5km_complete_observations",
    "primary_10km_complete_observations",
    "primary_5km_unique_sites",
    "duplicate_coordinate_sites",
    "extreme_sr_rows"
  ),
  value = c(
    nrow(d_qc),
    sum(d_qc$primary_analysis),
    sum(d_qc$snap_group != "unmatched"),
    nrow(obs_primary_5km),
    nrow(obs_primary_10km),
    nrow(site_primary_5km),
    nrow(duplicate_sites),
    sum(!d_qc$primary_analysis)
  )
)

write_csv(
  summary_table,
  file.path(out_qc, "global_modeling_qc_summary.csv")
)

cat("\nGlobal modeling QC summary:\n")
print(summary_table)

cat("\nSnap groups:\n")
print(d_qc %>% count(snap_group))

cat("\nRegional distribution of primary 5 km observations:\n")
print(
  obs_primary_5km %>%
    count(region, sort = TRUE)
)

cat("\nGlobal modeling dataset preparation finished.\n")
