#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(terra)
  library(readr)
  library(tibble)
  library(dplyr)
})

root_dir <- Sys.getenv(
  "SR_GLOBAL_DIR",
  unset = "/home/zhangmeng/projects/sr_global"
)

out_dir <- file.path(
  root_dir,
  "data_processed/global/climate_terrain_2p5m"
)

qc_dir <- file.path(
  root_dir,
  "outputs/global/climate_terrain_qc"
)

tmp_parent <- Sys.getenv(
  "TMPDIR",
  unset = "/tmp"
)

tmp_dir <- file.path(
  tmp_parent,
  paste0(
    "sr_climate_prepare_",
    Sys.getpid()
  )
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

dir.create(
  qc_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

dir.create(
  tmp_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

on.exit(
  unlink(
    tmp_dir,
    recursive = TRUE,
    force = TRUE
  ),
  add = TRUE
)

terraOptions(
  tempdir = tmp_dir,
  memfrac = 0.70,
  progress = 1
)

Sys.setenv(
  GDAL_NUM_THREADS = Sys.getenv(
    "SLURM_CPUS_PER_TASK",
    unset = "4"
  )
)

paths <- c(
  bio1 = file.path(
    root_dir,
    "data_raw/climate/WorldClim_v2_1/climate/wc2.1_2.5m/wc2.1_2.5m_bio_1.tif"
  ),
  bio4 = file.path(
    root_dir,
    "data_raw/climate/WorldClim_v2_1/climate/wc2.1_2.5m/wc2.1_2.5m_bio_4.tif"
  ),
  bio12 = file.path(
    root_dir,
    "data_raw/climate/WorldClim_v2_1/climate/wc2.1_2.5m/wc2.1_2.5m_bio_12.tif"
  ),
  bio15 = file.path(
    root_dir,
    "data_raw/climate/WorldClim_v2_1/climate/wc2.1_2.5m/wc2.1_2.5m_bio_15.tif"
  ),
  ai = file.path(
    root_dir,
    "data_raw/climate/Global_AI_PET/unzipped/Global-AI_ET0__annual_v3_1/ai_v31_yr.tif"
  ),
  et0 = file.path(
    root_dir,
    "data_raw/climate/Global_AI_PET/unzipped/Global-AI_ET0__annual_v3_1/et0_v31_yr.tif"
  ),
  elevation = file.path(
    root_dir,
    "data_raw/terrain/WorldClim_elevation/unzipped/wc2.1_2.5m_elev.tif"
  )
)

missing_files <- paths[
  !file.exists(paths)
]

if (length(missing_files) > 0) {
  stop(
    "Missing input files:\n",
    paste(
      missing_files,
      collapse = "\n"
    )
  )
}

wopt <- list(
  datatype = "FLT4S",
  gdal = c(
    "COMPRESS=DEFLATE",
    "PREDICTOR=3",
    "TILED=YES",
    "BIGTIFF=YES"
  )
)

write_layer <- function(
    x,
    filename,
    layer_name
) {

  names(x) <- layer_name

  writeRaster(
    x,
    filename,
    overwrite = TRUE,
    wopt = wopt
  )

  rast(filename)
}

message("Reading 2.5 arc-minute template.")

template <- rast(
  paths[["bio1"]]
)

if (nlyr(template) != 1) {
  stop("BIO1 template has more than one layer.")
}

output_files <- c(
  bio1_C = file.path(
    out_dir,
    "bio1_annual_mean_temperature_C.tif"
  ),
  bio4_C_sd = file.path(
    out_dir,
    "bio4_temperature_seasonality_C_sd.tif"
  ),
  bio12_mm = file.path(
    out_dir,
    "bio12_annual_precipitation_mm.tif"
  ),
  bio15_cv = file.path(
    out_dir,
    "bio15_precipitation_seasonality_cv.tif"
  ),
  ai_ratio = file.path(
    out_dir,
    "aridity_index_ratio.tif"
  ),
  et0_mm = file.path(
    out_dir,
    "annual_et0_mm.tif"
  ),
  elevation_m = file.path(
    out_dir,
    "elevation_m.tif"
  ),
  cell_area_km2 = file.path(
    out_dir,
    "template_cell_area_km2.tif"
  )
)

message("Writing WorldClim variables.")

bio1 <- write_layer(
  rast(paths[["bio1"]]),
  output_files[["bio1_C"]],
  "bio1_C"
)

bio4 <- rast(
  paths[["bio4"]]
) * 0.01

bio4 <- write_layer(
  bio4,
  output_files[["bio4_C_sd"]],
  "bio4_C_sd"
)

bio12 <- write_layer(
  rast(paths[["bio12"]]),
  output_files[["bio12_mm"]],
  "bio12_mm"
)

bio15 <- write_layer(
  rast(paths[["bio15"]]),
  output_files[["bio15_cv"]],
  "bio15_cv"
)

elevation <- write_layer(
  rast(paths[["elevation"]]),
  output_files[["elevation_m"]],
  "elevation_m"
)

message("Reading 30 arc-second AI and ET0.")

ai_raw <- rast(
  paths[["ai"]]
)

et0_raw <- rast(
  paths[["et0"]]
)

if (
  !compareGeom(
    ai_raw,
    et0_raw,
    stopOnError = FALSE
  )
) {
  stop("AI and ET0 geometries do not match.")
}

aggregation_factor <- round(
  res(template)[1] /
    res(ai_raw)[1]
)

if (aggregation_factor != 5) {
  stop(
    "Expected aggregation factor 5, found ",
    aggregation_factor
  )
}

message(
  "Cleaning AI and ET0 at native resolution."
)

valid_ai <- (
  is.finite(ai_raw) &
    ai_raw >= 0 &
    ai_raw < 65535 &
    is.finite(et0_raw) &
    et0_raw > 0
)

ai_clean <- ifel(
  valid_ai,
  ai_raw * 0.0001,
  NA
)

et0_clean <- ifel(
  is.finite(et0_raw) &
    et0_raw > 0,
  et0_raw,
  NA
)

message(
  "Aggregating AI to 2.5 arc-minute."
)

ai_aggregated <- aggregate(
  ai_clean,
  fact = aggregation_factor,
  fun = "mean",
  na.rm = TRUE,
  filename = file.path(
    tmp_dir,
    "ai_aggregated_2p5m.tif"
  ),
  overwrite = TRUE,
  wopt = wopt
)

message(
  "Aggregating ET0 to 2.5 arc-minute."
)

et0_aggregated <- aggregate(
  et0_clean,
  fact = aggregation_factor,
  fun = "mean",
  na.rm = TRUE,
  filename = file.path(
    tmp_dir,
    "et0_aggregated_2p5m.tif"
  ),
  overwrite = TRUE,
  wopt = wopt
)

message(
  "Aligning AI and ET0 with WorldClim template."
)

ai_aligned_temp <- resample(
  ai_aggregated,
  template,
  method = "bilinear",
  filename = file.path(
    tmp_dir,
    "ai_aligned_temp.tif"
  ),
  overwrite = TRUE,
  wopt = wopt
)

et0_aligned_temp <- resample(
  et0_aggregated,
  template,
  method = "bilinear",
  filename = file.path(
    tmp_dir,
    "et0_aligned_temp.tif"
  ),
  overwrite = TRUE,
  wopt = wopt
)

latitude_raster <- init(
  et0_aligned_temp,
  "y"
)

polar_et0_artifact <- (
  latitude_raster > 60 &
    et0_aligned_temp > 4000
)

n_polar_et0_artifact <- global(
  polar_et0_artifact,
  fun = "sum",
  na.rm = TRUE
)[[1, 1]]

message(
  "Masking ",
  n_polar_et0_artifact,
  " implausible high-Arctic ET0 cells."
)

et0_aligned <- ifel(
  is.finite(et0_aligned_temp) &
    et0_aligned_temp > 0 &
    !polar_et0_artifact,
  et0_aligned_temp,
  NA
)

ai_aligned <- ifel(
  is.finite(ai_aligned_temp) &
    ai_aligned_temp >= 0 &
    ai_aligned_temp <= 6.5535 &
    is.finite(et0_aligned) &
    et0_aligned > 0 &
    !polar_et0_artifact,
  ai_aligned_temp,
  NA
)

ai_aligned <- write_layer(
  ai_aligned,
  output_files[["ai_ratio"]],
  "ai_ratio"
)

et0_aligned <- write_layer(
  et0_aligned,
  output_files[["et0_mm"]],
  "et0_mm"
)

message("Creating cell-area raster.")

cell_area <- cellSize(
  template,
  unit = "km",
  mask = FALSE
)

cell_area <- write_layer(
  cell_area,
  output_files[["cell_area_km2"]],
  "cell_area_km2"
)

predictor_files <- output_files[
  names(output_files) !=
    "cell_area_km2"
]

geometry_check <- bind_rows(
  lapply(
    names(predictor_files),
    function(nm) {

      r <- rast(
        predictor_files[[nm]]
      )

      tibble(
        variable = nm,
        geometry_matches_template =
          compareGeom(
            r,
            template,
            stopOnError = FALSE
          ),
        nrow = nrow(r),
        ncol = ncol(r),
        resolution_x = res(r)[1],
        resolution_y = res(r)[2],
        xmin = xmin(r),
        xmax = xmax(r),
        ymin = ymin(r),
        ymax = ymax(r)
      )
    }
  )
)

if (
  !all(
    geometry_check$geometry_matches_template
  )
) {
  stop(
    "At least one predictor does not match the template."
  )
}

stats <- bind_rows(
  lapply(
    names(predictor_files),
    function(nm) {

      r <- rast(
        predictor_files[[nm]]
      )

      x <- global(
        r,
        fun = c(
          "min",
          "max",
          "mean",
          "sd"
        ),
        na.rm = TRUE
      )

      tibble(
        variable = nm,
        file = predictor_files[[nm]],
        min = x[[1, "min"]],
        max = x[[1, "max"]],
        mean = x[[1, "mean"]],
        sd = x[[1, "sd"]]
      )
    }
  )
)

metadata <- tribble(
  ~variable, ~description, ~units, ~transformation,
  "bio1_C",
  "Annual mean temperature",
  "degrees C",
  "original WorldClim BIO1 values",
  "bio4_C_sd",
  "Temperature seasonality",
  "degrees C standard deviation",
  "WorldClim BIO4 divided by 100",
  "bio12_mm",
  "Annual precipitation",
  "mm per year",
  "original WorldClim BIO12 values",
  "bio15_cv",
  "Precipitation seasonality",
  "coefficient of variation",
  "original WorldClim BIO15 values",
  "ai_ratio",
  "Global aridity index",
  "precipitation divided by ET0",
  "raw AI multiplied by 0.0001; 65535 and non-land cells removed",
  "et0_mm",
  "Annual reference evapotranspiration",
  "mm per year",
  "positive ET0 values; 5 by 5 mean aggregation",
  "elevation_m",
  "Elevation",
  "m",
  "original WorldClim elevation values"
)

write_csv(
  geometry_check,
  file.path(
    qc_dir,
    "global_climate_terrain_geometry_check.csv"
  )
)

write_csv(
  stats,
  file.path(
    qc_dir,
    "global_climate_terrain_summary_statistics.csv"
  )
)

write_csv(
  metadata,
  file.path(
    qc_dir,
    "global_climate_terrain_variable_metadata.csv"
  )
)

cat("\nGeometry check:\n")
print(
  geometry_check,
  n = Inf,
  width = Inf
)

cat("\nSummary statistics:\n")
print(
  stats,
  n = Inf,
  width = Inf
)

cat(
  "\nGlobal climate and terrain preparation finished.\n"
)
