#!/usr/bin/env Rscript
source(file.path(Sys.getenv("SR_GLOBAL_DIR", "/home/zhangmeng/projects/sr_global"),
                 "scripts", "00_global_helpers.R"))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1) stop("Usage: Rscript 02_snap_region_hydrorivers.R <region code>")
region <- tolower(args[[1]])
if (!region %in% region_codes) stop("Unknown region: ", region)

sf::sf_use_s2(TRUE)
sample_file <- file.path(site_dir, "data_processed", "global", "world_river_water_sr_solute_global.rds")
if (!file.exists(sample_file)) stop("Missing sample file: ", sample_file)
river_file <- hydrorivers_path(region)
if (!file.exists(river_file)) stop("Missing HydroRIVERS file: ", river_file)

samples <- readRDS(sample_file)
message("Region: ", region)
message("Reading HydroRIVERS: ", river_file)
rivers <- st_read(river_file, quiet = TRUE)
if (is.na(st_crs(rivers))) stop("HydroRIVERS CRS is missing for region ", region)
rivers <- st_transform(rivers, 4326)

keep_river_vars <- intersect(c(
  "HYRIV_ID", "NEXT_DOWN", "MAIN_RIV", "LENGTH_KM", "DIST_DN_KM", "DIST_UP_KM",
  "CATCH_SKM", "UPLAND_SKM", "DIS_AV_CMS", "ORD_STRA", "ORD_CLAS", "ORD_FLOW"
), names(rivers))
rivers <- rivers[, keep_river_vars, drop = FALSE]

bb <- st_bbox(rivers)
buffer_deg <- 2
candidate <- samples %>% filter(
  longitude >= as.numeric(bb["xmin"]) - buffer_deg,
  longitude <= as.numeric(bb["xmax"]) + buffer_deg,
  latitude >= max(-90, as.numeric(bb["ymin"]) - buffer_deg),
  latitude <= min(90, as.numeric(bb["ymax"]) + buffer_deg)
)

message("HydroRIVERS segments: ", nrow(rivers))
message("Candidate samples in expanded region bbox: ", nrow(candidate))
out_dir <- dir_create(site_dir, "data_processed", "global", "snap_by_region")
out_file <- file.path(out_dir, paste0("global_snap_", region, ".rds"))
out_csv <- file.path(out_dir, paste0("global_snap_", region, ".csv"))

if (nrow(candidate) == 0) {
  empty <- candidate %>% mutate(region = region, snap_dist_m = numeric(0))
  saveRDS(empty, out_file); write_csv(empty, out_csv)
  message("No candidate samples; wrote empty output.")
  quit(save = "no", status = 0)
}

pts <- st_as_sf(candidate, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)
message("Finding nearest HydroRIVERS reach...")
nearest_idx <- st_nearest_feature(pts, rivers)
message("Calculating geodesic point-to-reach distance...")
snap_dist_m <- as.numeric(st_distance(pts, rivers[nearest_idx, ], by_element = TRUE))

river_attr <- rivers[nearest_idx, , drop = FALSE] %>%
  st_drop_geometry() %>% rename_with(~ paste0("river_", .x))
result <- bind_cols(candidate,
                    data.frame(region = region, region_river_index = nearest_idx, snap_dist_m = snap_dist_m),
                    river_attr)
saveRDS(result, out_file)
write_csv(result, out_csv)
message("Snapped candidates written: ", nrow(result))
print(summary(result$snap_dist_m))
message("Region snap finished: ", region)
