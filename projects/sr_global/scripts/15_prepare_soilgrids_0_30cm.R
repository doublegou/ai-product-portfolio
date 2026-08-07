#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(terra)
  library(dplyr)
  library(tibble)
  library(readr)
})

root_dir <- Sys.getenv(
  "SR_GLOBAL_DIR",
  unset = "/home/zhangmeng/projects/sr_global"
)

input_dir <- file.path(
  root_dir,
  "data_raw/soil/SoilGrids_5000m"
)

output_dir <- file.path(
  root_dir,
  "data_processed/global/soil_5000m"
)

qc_dir <- file.path(
  root_dir,
  "outputs/global/soil_5000m_qc"
)

temp_dir <- Sys.getenv(
  "SLURM_TMPDIR",
  unset = file.path(root_dir, "tmp/terra_soil")
)

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(qc_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(temp_dir, recursive = TRUE, showWarnings = FALSE)

terraOptions(
  tempdir = temp_dir,
  progress = 1
)

ph_files <- file.path(
  input_dir,
  "phh2o",
  c(
    "phh2o_0-5cm_mean_5000.tif",
    "phh2o_5-15cm_mean_5000.tif",
    "phh2o_15-30cm_mean_5000.tif"
  )
)

clay_files <- file.path(
  input_dir,
  "clay",
  c(
    "clay_0-5cm_mean_5000.tif",
    "clay_5-15cm_mean_5000.tif",
    "clay_15-30cm_mean_5000.tif"
  )
)

all_files <- c(ph_files, clay_files)

if (any(!file.exists(all_files))) {
  stop(
    "Missing SoilGrids files:\n",
    paste(
      all_files[!file.exists(all_files)],
      collapse = "\n"
    )
  )
}

ph <- rast(ph_files)
clay <- rast(clay_files)

names(ph) <- c(
  "ph_0_5",
  "ph_5_15",
  "ph_15_30"
)

names(clay) <- c(
  "clay_0_5",
  "clay_5_15",
  "clay_15_30"
)

if (!isTRUE(compareGeom(ph, clay, stopOnError = FALSE))) {
  stop("pH and clay raster geometries do not match.")
}

weights <- c(5, 10, 15)

cat("Calculating 0-30 cm weighted pH.\n")

# SoilGrids pH values are stored as pH × 10.
# NA propagation means all three depth layers must be valid.
ph_0_30 <- (
  ph[[1]] * weights[1] +
  ph[[2]] * weights[2] +
  ph[[3]] * weights[3]
) / sum(weights) / 10

names(ph_0_30) <- "soil_pH_0_30cm"

ph_output <- file.path(
  output_dir,
  "soil_pH_0_30cm_5000m.tif"
)

writeRaster(
  ph_0_30,
  ph_output,
  overwrite = TRUE,
  datatype = "FLT4S",
  NAflag = -9999,
  wopt = list(
    gdal = c(
      "COMPRESS=DEFLATE",
      "PREDICTOR=2",
      "TILED=YES",
      "BIGTIFF=IF_SAFER",
      "NUM_THREADS=ALL_CPUS"
    )
  )
)

cat("Calculating 0-30 cm weighted clay percentage.\n")

# SoilGrids clay is stored in g/kg.
# Dividing by 10 converts g/kg to percentage.
clay_0_30 <- (
  clay[[1]] * weights[1] +
  clay[[2]] * weights[2] +
  clay[[3]] * weights[3]
) / sum(weights) / 10

names(clay_0_30) <- "soil_clay_pct_0_30cm"

clay_output <- file.path(
  output_dir,
  "soil_clay_pct_0_30cm_5000m.tif"
)

writeRaster(
  clay_0_30,
  clay_output,
  overwrite = TRUE,
  datatype = "FLT4S",
  NAflag = -9999,
  wopt = list(
    gdal = c(
      "COMPRESS=DEFLATE",
      "PREDICTOR=2",
      "TILED=YES",
      "BIGTIFF=IF_SAFER",
      "NUM_THREADS=ALL_CPUS"
    )
  )
)

ph_final <- rast(ph_output)
clay_final <- rast(clay_output)

qc <- bind_rows(
  tibble(
    variable = "soil_pH_0_30cm",
    global(
      ph_final,
      fun = c("min", "mean", "max"),
      na.rm = TRUE
    )
  ),
  tibble(
    variable = "soil_clay_pct_0_30cm",
    global(
      clay_final,
      fun = c("min", "mean", "max"),
      na.rm = TRUE
    )
  )
)

names(qc) <- c(
  "variable",
  "minimum",
  "mean",
  "maximum"
)

if (
  qc$minimum[qc$variable == "soil_pH_0_30cm"] < 0 ||
  qc$maximum[qc$variable == "soil_pH_0_30cm"] > 14
) {
  stop("Implausible pH range after scaling.")
}

if (
  qc$minimum[qc$variable == "soil_clay_pct_0_30cm"] < 0 ||
  qc$maximum[qc$variable == "soil_clay_pct_0_30cm"] > 100
) {
  stop("Implausible clay percentage after scaling.")
}

write_csv(
  qc,
  file.path(
    qc_dir,
    "soilgrids_0_30cm_global_qc.csv"
  )
)

cat("\n===== SOIL 0-30 CM QC =====\n")
print(qc, n = Inf, width = Inf)

cat("\nOutput files:\n")
cat(ph_output, "\n")
cat(clay_output, "\n")

cat("\nSoilGrids 0-30 cm preparation finished.\n")
