#!/usr/bin/env Rscript
source(file.path(Sys.getenv("SR_GLOBAL_DIR", "/home/zhangmeng/projects/sr_global"),
                 "scripts", "00_global_helpers.R"))

water_file <- find_first_existing(c(
  file.path(site_dir, "data_raw", "water", "world_river_water_sr.csv"),
  file.path(site_dir, "data_raw", "world_river_water_sr_solute.csv")
), "global river-water Sr CSV")

message("water_file: ", water_file)
raw <- readr::read_csv(water_file, show_col_types = FALSE, progress = FALSE)

sample_type_col <- pick_col(raw, c("sample_type", "sample.type"), required = FALSE)
lon_col <- pick_col(raw, c("longitude", "lon", "long", "x"), label = "longitude")
lat_col <- pick_col(raw, c("latitude", "lat", "y"), label = "latitude")
sr_col <- pick_col(raw, c("sr87_sr86", "87sr_86sr", "sr_ratio", "sr"), label = "87Sr/86Sr")
sample_id_col <- pick_col(raw, c("sample_id", "sampleid", "material_id", "id"), required = FALSE)

if (!is.na(sample_type_col)) {
  raw <- raw %>% filter(tolower(trimws(as.character(.data[[sample_type_col]]))) == "solute")
}

global <- raw %>%
  mutate(
    longitude = safe_numeric(.data[[lon_col]]),
    latitude = safe_numeric(.data[[lat_col]]),
    sr = safe_numeric(.data[[sr_col]]),
    source_sample_id = if (!is.na(sample_id_col)) as.character(.data[[sample_id_col]]) else NA_character_
  ) %>%
  filter(is.finite(longitude), is.finite(latitude), is.finite(sr),
         longitude >= -180, longitude <= 180, latitude >= -90, latitude <= 90) %>%
  mutate(global_row_id = row_number()) %>%
  relocate(global_row_id, source_sample_id, longitude, latitude, sr)

out_dir <- dir_create(site_dir, "data_processed", "global")
write_csv(global, file.path(out_dir, "world_river_water_sr_solute_global.csv"))
saveRDS(global, file.path(out_dir, "world_river_water_sr_solute_global.rds"))

manifest <- data.frame(
  region = region_codes,
  hydrorivers_shp = vapply(region_codes, hydrorivers_path, character(1)),
  exists = vapply(region_codes, function(x) file.exists(hydrorivers_path(x)), logical(1))
)
write_csv(manifest, file.path(out_dir, "hydrorivers_region_manifest.csv"))

message("Global solute rows retained: ", nrow(global))
message("Longitude range: ", paste(range(global$longitude), collapse = " to "))
message("Latitude range: ", paste(range(global$latitude), collapse = " to "))
message("HydroRIVERS regions present: ", sum(manifest$exists), "/", nrow(manifest))
if (!all(manifest$exists)) stop("Missing HydroRIVERS region files:\n", paste(manifest$hydrorivers_shp[!manifest$exists], collapse = "\n"))
message("Step 1 global sample preparation finished.")
