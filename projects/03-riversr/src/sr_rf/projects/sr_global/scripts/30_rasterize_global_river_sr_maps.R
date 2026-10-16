suppressPackageStartupMessages({
  library(sf)
  library(terra)
  library(dplyr)
})

out_dir <- "outputs/global/final_rasters"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

message("Reading ORD_FLOW <= 5 river geometry...")

river_file <- paste0(
  "data_processed/global/final_prediction/",
  "map_geometry_ordflow5/global_major_rivers_ordflow5.rds"
)

if (!file.exists(river_file)) {
  stop("Missing river geometry file: ", river_file)
}

rivers <- readRDS(river_file)

message("River object class:")
print(class(rivers))

message("Columns:")
print(names(rivers))

# ------------------------------------------------------------
# Detect prediction columns robustly
# ------------------------------------------------------------

find_col <- function(patterns, nms) {
  hit <- unlist(
    lapply(
      patterns,
      function(p) grep(p, nms, value = TRUE, ignore.case = TRUE)
    )
  )
  hit <- unique(hit)
  if (length(hit) == 0) return(NA_character_)
  hit[1]
}

nms <- names(rivers)

rf_col <- find_col(
  c("^rf_mean$", "rf.*mean", "pred.*rf", "mean.*pred"),
  nms
)

p10_col <- find_col(
  c("p10", "qrf.*10"),
  nms
)

p50_col <- find_col(
  c("p50", "qrf.*50", "median"),
  nms
)

p90_col <- find_col(
  c("p90", "qrf.*90"),
  nms
)

width_col <- find_col(
  c("p80.*width", "width", "p90.*p10"),
  nms
)

message("Detected columns:")
print(
  data.frame(
    field = c("rf_mean", "p10", "p50", "p90", "p80_width"),
    column = c(rf_col, p10_col, p50_col, p90_col, width_col)
  )
)

if (is.na(rf_col)) {
  stop("Could not find RF mean prediction column.")
}

if (is.na(width_col)) {
  if (!is.na(p10_col) && !is.na(p90_col)) {
    rivers$qrf_p80_width_tmp <- rivers[[p90_col]] - rivers[[p10_col]]
    width_col <- "qrf_p80_width_tmp"
  } else {
    warning("Could not find p80 width or p10/p90 columns.")
  }
}

# ------------------------------------------------------------
# Prepare data
# ------------------------------------------------------------

if (!inherits(rivers, "sf")) {
  stop("River geometry is not an sf object.")
}

rivers <- st_make_valid(rivers)

if (is.na(st_crs(rivers))) {
  stop("River geometry has no CRS.")
}

rivers <- st_transform(rivers, 4326)

# Keep only needed columns to reduce memory
keep_cols <- unique(
  na.omit(
    c(rf_col, p10_col, p50_col, p90_col, width_col)
  )
)

rivers_small <- rivers[, keep_cols, drop = FALSE]

message("Converting to terra vector...")
rivers_v <- vect(rivers_small)

# ------------------------------------------------------------
# Raster template
# ------------------------------------------------------------
# 0.05 degrees = about 5 km at the equator.
# This is a georeferenced WGS84 raster. Cells without selected river
# reaches remain NA.

res_deg <- 0.05

template <- rast(
  xmin = -180,
  xmax = 180,
  ymin = -90,
  ymax = 90,
  resolution = res_deg,
  crs = "EPSG:4326"
)

message("Template raster:")
print(template)

# ------------------------------------------------------------
# Rasterize helper
# ------------------------------------------------------------

write_rasterized <- function(field, out_name) {

  if (is.na(field) || !(field %in% names(rivers_v))) {
    message("Skipping missing field: ", out_name)
    return(invisible(NULL))
  }

  message("Rasterizing: ", field)

  r <- rasterize(
    rivers_v,
    template,
    field = field,
    fun = "mean",
    touches = TRUE,
    background = NA
  )

  out_file <- file.path(out_dir, out_name)

  writeRaster(
    r,
    out_file,
    overwrite = TRUE,
    gdal = c(
      "COMPRESS=LZW",
      "TILED=YES",
      "BIGTIFF=IF_SAFER"
    )
  )

  message("Saved: ", out_file)
  message("Non-NA cells: ", global(!is.na(r), "sum", na.rm = TRUE)[1, 1])
  message("Min/max:")
  print(global(r, c("min", "max"), na.rm = TRUE))

  invisible(out_file)
}

write_rasterized(
  rf_col,
  "global_river_Sr_RF_mean_ordflow5_0p05deg.tif"
)

write_rasterized(
  p10_col,
  "global_river_Sr_QRF_p10_ordflow5_0p05deg.tif"
)

write_rasterized(
  p50_col,
  "global_river_Sr_QRF_p50_ordflow5_0p05deg.tif"
)

write_rasterized(
  p90_col,
  "global_river_Sr_QRF_p90_ordflow5_0p05deg.tif"
)

write_rasterized(
  width_col,
  "global_river_Sr_QRF_p80_width_ordflow5_0p05deg.tif"
)

# ------------------------------------------------------------
# Save metadata
# ------------------------------------------------------------

metadata <- data.frame(
  item = c(
    "input_geometry",
    "river_selection",
    "raster_resolution_degree",
    "crs",
    "rasterization_function",
    "rf_mean_column",
    "qrf_p10_column",
    "qrf_p50_column",
    "qrf_p90_column",
    "qrf_p80_width_column",
    "interpretation"
  ),
  value = c(
    river_file,
    "ORD_FLOW <= 5",
    res_deg,
    "EPSG:4326",
    "terra::rasterize, fun = mean, touches = TRUE",
    rf_col,
    p10_col,
    p50_col,
    p90_col,
    width_col,
    "River-reach raster only. Non-river cells are NA. This is not a continuous land-surface Sr map."
  )
)

write.csv(
  metadata,
  file.path(out_dir, "global_river_Sr_raster_metadata_ordflow5_0p05deg.csv"),
  row.names = FALSE
)

message("Rasterization completed.")
message("Output directory:")
message(normalizePath(out_dir))
