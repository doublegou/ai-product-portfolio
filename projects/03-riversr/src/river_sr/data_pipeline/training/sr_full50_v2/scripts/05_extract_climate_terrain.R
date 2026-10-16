file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) stop("Run this file with Rscript.", call. = FALSE)
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
source(file.path(dirname(script_path), "common.R"), local = TRUE)
context <- river_sr_context(script_path)

assignment_path <- river_sr_path(context, context$config$output$basin_assignment)
scope_path <- river_sr_path(context, context$config$output$basin_scope)
output_path <- river_sr_path(context, context$config$output$climate_terrain)
raw_root <- river_sr_path(context, "data/raw/features")
paths <- c(
  bio1_C = file.path(raw_root, "climate/worldclim_v2_1/bio_2p5m/wc2.1_2.5m_bio_1.tif"),
  bio4_C_sd = file.path(raw_root, "climate/worldclim_v2_1/bio_2p5m/wc2.1_2.5m_bio_4.tif"),
  bio12_mm = file.path(raw_root, "climate/worldclim_v2_1/bio_2p5m/wc2.1_2.5m_bio_12.tif"),
  bio15_cv = file.path(raw_root, "climate/worldclim_v2_1/bio_2p5m/wc2.1_2.5m_bio_15.tif"),
  ai_ratio = file.path(raw_root, "climate/global_ai_et0_v3_1/annual/Global-AI_ET0__annual_v3_1/ai_v31_yr.tif"),
  et0_mm = file.path(raw_root, "climate/global_ai_et0_v3_1/annual/Global-AI_ET0__annual_v3_1/et0_v31_yr.tif"),
  elevation_m = file.path(raw_root, "terrain/worldclim_v2_1/elevation_2p5m/wc2.1_2.5m_elev.tif")
)
river_sr_assert(file.exists(assignment_path), paste("Run step 02 first; missing:", assignment_path))
river_sr_assert(file.exists(scope_path), paste("Run step 02 first; missing:", scope_path))
missing <- paths[!file.exists(paths)]
river_sr_assert(length(missing) == 0L, paste("Missing climate/terrain inputs:", paste(missing, collapse = ", ")))

suppressPackageStartupMessages(library(terra))
terra::terraOptions(memfrac = 0.70, progress = 1)
wopt <- list(datatype = "FLT4S", gdal = c("COMPRESS=DEFLATE", "PREDICTOR=3", "TILED=YES"))
write_temp <- function(x, name) {
  path <- tempfile(paste0(name, "_"), fileext = ".tif")
  terra::writeRaster(x, path, overwrite = TRUE, wopt = wopt)
  y <- terra::rast(path)
  names(y) <- name
  y
}

template <- terra::rast(paths[["bio1_C"]])
bio1 <- write_temp(template, "bio1_C")
bio4 <- write_temp(terra::rast(paths[["bio4_C_sd"]]) * 0.01, "bio4_C_sd")
bio12 <- write_temp(terra::rast(paths[["bio12_mm"]]), "bio12_mm")
bio15 <- write_temp(terra::rast(paths[["bio15_cv"]]), "bio15_cv")
elevation <- write_temp(terra::rast(paths[["elevation_m"]]), "elevation_m")

ai_raw <- terra::rast(paths[["ai_ratio"]])
et0_raw <- terra::rast(paths[["et0_mm"]])
river_sr_assert(terra::compareGeom(ai_raw, et0_raw, stopOnError = FALSE), "AI and ET0 geometries differ.")
factor <- round(terra::res(template)[1L] / terra::res(ai_raw)[1L])
river_sr_assert(factor == 5L, paste("Expected AI/ET0 aggregation factor 5; found", factor))
valid_et0 <- is.finite(et0_raw) & et0_raw > 0
ai_clean <- terra::ifel(is.finite(ai_raw) & ai_raw >= 0 & ai_raw < 65535 & valid_et0, ai_raw * 0.0001, NA)
et0_clean <- terra::ifel(valid_et0, et0_raw, NA)
ai_2p5m <- terra::aggregate(ai_clean, fact = factor, fun = "mean", na.rm = TRUE)
et0_2p5m <- terra::aggregate(et0_clean, fact = factor, fun = "mean", na.rm = TRUE)
ai_aligned <- terra::resample(ai_2p5m, template, method = "bilinear")
et0_aligned <- terra::resample(et0_2p5m, template, method = "bilinear")
latitude <- terra::init(template, "y")
polar_artifact <- latitude > 60 & et0_aligned > 4000
et0 <- write_temp(terra::ifel(is.finite(et0_aligned) & et0_aligned > 0 & !polar_artifact, et0_aligned, NA), "et0_mm")
ai <- write_temp(terra::ifel(is.finite(ai_aligned) & ai_aligned >= 0 & ai_aligned <= 6.5535 & !polar_artifact, ai_aligned, NA), "ai_ratio")

predictors <- c(bio1, bio4, bio12, bio15, ai, et0, elevation)
area <- terra::cellSize(template, unit = "km", mask = FALSE)
names(area) <- "cell_area_km2"
stack <- c(predictors, area)
variables <- names(predictors)
scope <- data.table::as.data.table(readRDS(scope_path))
parts <- lapply(river_sr_region_codes(), function(region) {
  message("Climate/terrain region: ", region)
  river_sr_summarise_rasters_by_l6(
    context, region, stack, variables,
    basin_ids = scope[basin_region == region, hybas_id]
  )
})
basin_values <- data.table::rbindlist(parts, use.names = TRUE)
basin_values[, hybas_id := sprintf("%.0f", as.numeric(HYBAS_ID))]

assignment <- data.table::as.data.table(readRDS(assignment_path))
current <- match(assignment$current_hybas_id, basin_values$hybas_id)
result <- assignment[, .(site_id)]
mapping <- c(
  p0__up_bio1_C = "up_bio1_C",
  p0__up_bio4_C_sd = "up_bio4_C_sd",
  p0__up_bio12_mm = "up_bio12_mm",
  p0__up_bio15_cv = "up_bio15_cv",
  p0__up_ai_ratio = "up_ai_ratio",
  p0__up_et0_mm = "up_et0_mm",
  p0__up_elevation_m = "up_elevation_m",
  p1r__local_ai_ratio = "local_ai_ratio",
  p1r__local_elevation_m = "local_elevation_m"
)
for (output_name in names(mapping)) {
  result[, (output_name) := basin_values[[mapping[[output_name]]]][current]]
}
data.table::setorder(result, site_id)
river_sr_save_rds(result, output_path)
message(sprintf("05 complete: climate and terrain built for %d sites: %s", nrow(result), output_path))
