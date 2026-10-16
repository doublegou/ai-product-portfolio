#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

site_dir <- Sys.getenv(
  "SR_GLOBAL_DIR",
  unset = "/home/zhangmeng/projects/sr_global"
)

in_rds <- file.path(
  site_dir,
  "data_processed/global/world_river_water_sr_solute_global.rds"
)

out_dir <- file.path(site_dir, "data_processed/global")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

d <- readRDS(in_rds)

d_qc <- d %>%
  group_by(longitude, latitude) %>%
  mutate(
    coordinate_replicates = n()
  ) %>%
  ungroup() %>%
  mutate(
    primary_analysis = sr > 0.700 & sr < 0.800,

    sr_qc_group = case_when(
      sr <= 0.700 ~ "low_le_0p700",
      sr >= 0.800 ~ "high_ge_0p800",
      TRUE        ~ "primary_0p700_0p800"
    )
  )

d_primary <- d_qc %>%
  filter(primary_analysis)

d_extreme <- d_qc %>%
  filter(!primary_analysis)

saveRDS(
  d_qc,
  file.path(out_dir, "world_river_water_sr_solute_global_flagged.rds")
)

write_csv(
  d_qc,
  file.path(out_dir, "world_river_water_sr_solute_global_flagged.csv")
)

saveRDS(
  d_primary,
  file.path(out_dir, "world_river_water_sr_solute_global_primary_6258.rds")
)

write_csv(
  d_primary,
  file.path(out_dir, "world_river_water_sr_solute_global_primary_6258.csv")
)

write_csv(
  d_extreme,
  file.path(out_dir, "world_river_water_sr_solute_global_extreme_25.csv")
)

cat("\nQC groups:\n")
print(d_qc %>% count(sr_qc_group))

cat("\nPrimary analysis rows:", nrow(d_primary), "\n")
cat("Full sensitivity rows:", nrow(d_qc), "\n")

cat("\nCoordinate replication among extreme samples:\n")
print(
  d_extreme %>%
    count(longitude, latitude, name = "n_extreme") %>%
    arrange(desc(n_extreme)),
  n = Inf
)

cat("\nGlobal Sr QC finished.\n")
