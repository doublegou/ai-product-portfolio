############################################################
# Step 1: Clean global river-water Sr table and extract
# Pearl River / South China pilot points
############################################################

rm(list = ls())
gc()

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(stringr)
  library(tibble)
  library(sf)
  library(ggplot2)
  library(viridis)
})

site_dir <- Sys.getenv("SR_SITE_DIR", unset = path.expand("~/projects/sr_global"))
water_file <- Sys.getenv(
  "SR_WATER_FILE",
  unset = file.path(site_dir, "data_raw", "water", "world_river_water_sr.csv")
)

# Pearl River / South China pilot bbox
bbox_pr <- sf::st_bbox(
  c(xmin = 96.5, xmax = 116.5, ymin = 20.0, ymax = 27.8),
  crs = sf::st_crs(4326)
)
bbox_pr_sf <- sf::st_as_sfc(bbox_pr)

dir.create(file.path(site_dir, "data_processed"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(site_dir, "outputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(site_dir, "outputs", "figures"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(site_dir, "outputs", "maps"), recursive = TRUE, showWarnings = FALSE)

message("site_dir: ", site_dir)
message("water_file: ", water_file)
stopifnot(file.exists(water_file))

# Helper: pick a likely column name if the table changes slightly
guess_col <- function(nms, patterns) {
  for (p in patterns) {
    hit <- grep(p, nms, value = TRUE, ignore.case = TRUE)
    if (length(hit) > 0) return(hit[1])
  }
  NA_character_
}

sr <- readr::read_csv(
  water_file,
  na = c("NA", "", "NaN"),
  show_col_types = FALSE
)

message("Input columns:")
print(names(sr))

sample_type_col <- Sys.getenv("SR_SAMPLE_TYPE_COL", unset = "sample_type")
lon_col <- Sys.getenv("SR_LON_COL", unset = guess_col(names(sr), c("^longitude$", "^lon$", "decimal.*long", "long", "^x$")))
lat_col <- Sys.getenv("SR_LAT_COL", unset = guess_col(names(sr), c("^latitude$", "^lat$", "decimal.*lat", "lat", "^y$")))
sr_col <- Sys.getenv("SR_RATIO_COL", unset = guess_col(names(sr), c("^sr87_sr86$", "87.*sr.*86", "sr.*87.*86", "sr_ratio", "Sr_ratio", "X87Sr", "Sr87")))

message("Detected sample_type_col: ", sample_type_col)
message("Detected lon_col: ", lon_col)
message("Detected lat_col: ", lat_col)
message("Detected sr_col: ", sr_col)

if (!(sample_type_col %in% names(sr))) stop("sample_type column not found: ", sample_type_col)
if (is.na(lon_col) || !(lon_col %in% names(sr))) stop("Longitude column not found. Set SR_LON_COL.")
if (is.na(lat_col) || !(lat_col %in% names(sr))) stop("Latitude column not found. Set SR_LAT_COL.")
if (is.na(sr_col) || !(sr_col %in% names(sr))) stop("Sr ratio column not found. Set SR_RATIO_COL.")

sample_type_summary <- sr %>%
  count(.data[[sample_type_col]], sort = TRUE)

write.csv(
  sample_type_summary,
  file.path(site_dir, "outputs", "01_sample_type_distribution.csv"),
  row.names = FALSE
)

sr_solute <- sr %>%
  mutate(sample_type_clean = stringr::str_to_lower(stringr::str_trim(.data[[sample_type_col]]))) %>%
  filter(sample_type_clean == "solute") %>%
  select(-sample_type_clean) %>%
  mutate(
    longitude = as.numeric(.data[[lon_col]]),
    latitude = as.numeric(.data[[lat_col]]),
    sr87_sr86 = as.numeric(.data[[sr_col]])
  ) %>%
  filter(
    !is.na(longitude), !is.na(latitude), !is.na(sr87_sr86),
    sr87_sr86 > 0.700, sr87_sr86 < 0.800
  )

message("Solute rows retained: ", nrow(sr_solute))

readr::write_csv(
  sr_solute,
  file.path(site_dir, "data_processed", "world_river_water_sr_solute.csv"),
  na = "NA"
)
saveRDS(
  sr_solute,
  file.path(site_dir, "data_processed", "world_river_water_sr_solute.rds")
)

summary_table <- tibble::tibble(
  item = c("Source file", "Filter", "Rows retained", "Purpose"),
  value = c(
    basename(water_file),
    paste0(sample_type_col, " == solute; 0.700 < Sr < 0.800"),
    as.character(nrow(sr_solute)),
    "Strict dissolved river/stream water dataset for Sr isoscape modelling"
  )
)
write.csv(
  summary_table,
  file.path(site_dir, "outputs", "01_solute_filter_summary.csv"),
  row.names = FALSE
)

sr_sf <- sf::st_as_sf(
  sr_solute,
  coords = c("longitude", "latitude"),
  crs = 4326,
  remove = FALSE
)

sr_pr <- suppressWarnings(sf::st_crop(sr_sf, bbox_pr))
message("Pilot points retained: ", nrow(sr_pr))

saveRDS(
  sr_pr,
  file.path(site_dir, "data_processed", "sr_solute_pearl_southchina.rds")
)

out_gpkg <- file.path(site_dir, "data_processed", "sr_solute_pearl_southchina.gpkg")
if (file.exists(out_gpkg)) unlink(out_gpkg)
sf::st_write(
  sr_pr,
  dsn = out_gpkg,
  layer = "sr_solute_pearl_southchina",
  driver = "GPKG",
  quiet = TRUE
)

p_points <- ggplot() +
  geom_sf(data = bbox_pr_sf, fill = NA, linewidth = 0.6) +
  geom_sf(data = sr_pr, aes(color = sr87_sr86), size = 1.8, alpha = 0.8) +
  coord_sf(xlim = c(96.5, 116.5), ylim = c(20.0, 27.8), expand = FALSE) +
  scale_color_viridis_c(name = expression(""^87*"Sr/"^86*"Sr")) +
  labs(
    title = "Pilot region: Pearl River and South China",
    subtitle = paste0("Solute river/stream Sr samples: n = ", nrow(sr_pr)),
    x = "Longitude",
    y = "Latitude"
  ) +
  theme_bw()

ggsave(
  filename = file.path(site_dir, "outputs", "maps", "sr_solute_pearl_southchina_points.png"),
  plot = p_points,
  width = 8,
  height = 5,
  dpi = 300
)

message("Step 1 finished.")
