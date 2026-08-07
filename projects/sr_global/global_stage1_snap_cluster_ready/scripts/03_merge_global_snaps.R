#!/usr/bin/env Rscript
source(file.path(Sys.getenv("SR_GLOBAL_DIR", "/home/zhangmeng/projects/sr_global"),
                 "scripts", "00_global_helpers.R"))

snap_dir <- file.path(site_dir, "data_processed", "global", "snap_by_region")
files <- file.path(snap_dir, paste0("global_snap_", region_codes, ".rds"))
missing <- files[!file.exists(files)]
if (length(missing) > 0) stop("Missing regional snap outputs:\n", paste(missing, collapse = "\n"))

all_candidates <- bind_rows(lapply(files, readRDS))
if (nrow(all_candidates) == 0) stop("No snap candidates were produced.")

best <- all_candidates %>% filter(is.finite(snap_dist_m)) %>%
  arrange(global_row_id, snap_dist_m) %>% group_by(global_row_id) %>% slice(1) %>% ungroup()

samples <- readRDS(file.path(site_dir, "data_processed", "global", "world_river_water_sr_solute_global.rds"))
all_best <- samples %>% left_join(best %>% select(-source_sample_id, -longitude, -latitude, -sr), by = "global_row_id")

needed <- c("DIS_AV_CMS", "UPLAND_SKM", "CATCH_SKM", "LENGTH_KM", "DIST_DN_KM", "DIST_UP_KM", "ORD_STRA", "ORD_CLAS", "ORD_FLOW")
for (v in needed) {
  rv <- paste0("river_", v)
  if (!rv %in% names(all_best)) all_best[[rv]] <- NA_real_
  all_best[[rv]] <- safe_numeric(all_best[[rv]])
}

all_best <- all_best %>% mutate(
  log_DIS_AV_CMS = log1p(river_DIS_AV_CMS),
  log_UPLAND_SKM = log1p(river_UPLAND_SKM),
  log_CATCH_SKM = log1p(river_CATCH_SKM),
  log_LENGTH_KM = log1p(river_LENGTH_KM),
  log_DIST_DN_KM = log1p(river_DIST_DN_KM),
  log_DIST_UP_KM = log1p(river_DIST_UP_KM),
  ORD_STRA = river_ORD_STRA, ORD_CLAS = river_ORD_CLAS, ORD_FLOW = river_ORD_FLOW
)

predictor_cols <- c("longitude", "latitude", "log_DIS_AV_CMS", "log_UPLAND_SKM", "log_CATCH_SKM",
                    "log_LENGTH_KM", "log_DIST_DN_KM", "log_DIST_UP_KM", "ORD_STRA", "ORD_CLAS", "ORD_FLOW")
clean_5km <- all_best %>% filter(is.finite(snap_dist_m), snap_dist_m <= 5000,
                                 if_all(all_of(predictor_cols), is.finite))
clean_10km <- all_best %>% filter(is.finite(snap_dist_m), snap_dist_m <= 10000,
                                  if_all(all_of(predictor_cols), is.finite))

out_dir <- dir_create(site_dir, "data_processed", "global")
output_dir <- dir_create(site_dir, "outputs", "global")
saveRDS(all_candidates, file.path(out_dir, "global_snap_all_region_candidates.rds"))
saveRDS(all_best, file.path(out_dir, "global_sr_snapped_best_all.rds"))
saveRDS(clean_5km, file.path(out_dir, "global_model2_df_clean_5km.rds"))
saveRDS(clean_10km, file.path(out_dir, "global_model2_df_clean_10km.rds"))
write_csv(all_best, file.path(output_dir, "global_sr_snapped_best_all.csv"))
write_csv(clean_5km, file.path(output_dir, "global_model2_df_clean_5km.csv"))

coverage <- data.frame(
  total_global_solute = nrow(samples),
  matched_any_region = sum(is.finite(all_best$snap_dist_m)),
  within_5km_complete = nrow(clean_5km),
  within_10km_complete = nrow(clean_10km),
  median_snap_m = median(all_best$snap_dist_m, na.rm = TRUE),
  p95_snap_m = as.numeric(quantile(all_best$snap_dist_m, 0.95, na.rm = TRUE))
)
write_csv(coverage, file.path(output_dir, "global_snap_coverage_summary.csv"))
write_csv(all_best %>% count(region, name = "n_best_matches") %>% arrange(desc(n_best_matches)),
          file.path(output_dir, "global_snap_best_region_counts.csv"))
message("Global solute samples: ", nrow(samples))
message("Matched to at least one region: ", sum(is.finite(all_best$snap_dist_m)))
message("Clean within 5 km: ", nrow(clean_5km))
message("Clean within 10 km: ", nrow(clean_10km))
message("Global merge finished.")
