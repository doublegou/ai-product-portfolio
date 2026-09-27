file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) stop("Run this file with Rscript.", call. = FALSE)
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
source(file.path(dirname(script_path), "common.R"), local = TRUE)
context <- river_sr_context(script_path)

assignment_path <- river_sr_path(context, context$config$output$basin_assignment)
scope_path <- river_sr_path(context, context$config$output$basin_scope)
output_path <- river_sr_path(context, context$config$output$soil)
soil_root <- river_sr_path(context, "data/raw/features/soil/soilgrids_v2")
depths <- c("0-5", "5-15", "15-30")
paths <- c(
  setNames(file.path(soil_root, "clay", paste0("clay_", depths, "cm_mean.vrt")), paste0("clay_", depths)),
  setNames(file.path(soil_root, "phh2o", paste0("phh2o_", depths, "cm_mean.vrt")), paste0("ph_", depths))
)
river_sr_assert(file.exists(assignment_path), paste("Run step 02 first; missing:", assignment_path))
river_sr_assert(file.exists(scope_path), paste("Run step 02 first; missing:", scope_path))
missing <- paths[!file.exists(paths) | !file.exists(paste0(paths, ".ovr"))]
river_sr_assert(length(missing) == 0L, paste("Missing SoilGrids VRT/overview inputs:", paste(missing, collapse = ", ")))

suppressPackageStartupMessages({
  library(sf)
  library(terra)
})
terra::terraOptions(memfrac = 0.70, progress = 1)

# Only the official VRT files and their compact overviews are stored in raw/.
# GDAL materializes the 5 km working rasters directly from those overviews, so
# the multi-gigabyte 250 m tile collections are not downloaded.
to_5km <- function(path, name) {
  output <- tempfile(paste0(name, "_5km_"), fileext = ".tif")
  sf::gdal_utils(
    util = "translate",
    source = path,
    destination = output,
    options = c(
      "-ovr", "AUTO", "-tr", "5000", "5000", "-r", "average",
      "-ot", "Float32", "-co", "COMPRESS=DEFLATE", "-co", "TILED=YES"
    ),
    quiet = FALSE
  )
  x <- terra::rast(output)
  names(x) <- name
  x
}

clay <- terra::rast(lapply(seq_along(depths), function(i) to_5km(paths[[paste0("clay_", depths[[i]])]], paste0("clay_", i))))
ph <- terra::rast(lapply(seq_along(depths), function(i) to_5km(paths[[paste0("ph_", depths[[i]])]], paste0("ph_", i))))
river_sr_assert(terra::compareGeom(clay, ph, stopOnError = FALSE), "Clay and pH 5 km geometries differ.")
weights <- c(5, 10, 15)
soil_clay <- (clay[[1L]] * weights[[1L]] + clay[[2L]] * weights[[2L]] + clay[[3L]] * weights[[3L]]) / sum(weights) / 10
soil_ph <- (ph[[1L]] * weights[[1L]] + ph[[2L]] * weights[[2L]] + ph[[3L]] * weights[[3L]]) / sum(weights) / 10
names(soil_clay) <- "soil_clay_pct_0_30cm"
names(soil_ph) <- "soil_pH_0_30cm"
predictors <- c(soil_clay, soil_ph)
area <- terra::cellSize(soil_clay, unit = "km", mask = FALSE)
names(area) <- "cell_area_km2"
stack <- c(predictors, area)
variables <- names(predictors)
scope <- data.table::as.data.table(readRDS(scope_path))

parts <- lapply(river_sr_region_codes(), function(region) {
  message("Soil region: ", region)
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
  p0__up_soil_clay_pct_0_30cm = "up_soil_clay_pct_0_30cm",
  p1r__local_soil_clay_pct_0_30cm = "local_soil_clay_pct_0_30cm",
  p1r__local_soil_pH_0_30cm = "local_soil_pH_0_30cm",
  p1r__up_soil_pH_0_30cm = "up_soil_pH_0_30cm"
)
for (output_name in names(mapping)) {
  result[, (output_name) := basin_values[[mapping[[output_name]]]][current]]
}
data.table::setorder(result, site_id)
river_sr_save_rds(result, output_path)
message(sprintf("06 complete: SoilGrids 0-30 cm predictors built for %d sites: %s", nrow(result), output_path))
