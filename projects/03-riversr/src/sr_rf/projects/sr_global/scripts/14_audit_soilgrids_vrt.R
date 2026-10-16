#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(terra)
  library(dplyr)
  library(tibble)
})

root_dir <- Sys.getenv(
  "SR_GLOBAL_DIR",
  unset = "/home/zhangmeng/projects/sr_global"
)

soil_dir <- file.path(
  root_dir,
  "data_raw/soil/SoilGrids_VRT"
)

layer_names <- c(
  "phh2o_0_5",
  "phh2o_5_15",
  "phh2o_15_30",
  "clay_0_5",
  "clay_5_15",
  "clay_15_30"
)

file_names <- c(
  "phh2o_0-5cm_mean_patched.vrt",
  "phh2o_5-15cm_mean_patched.vrt",
  "phh2o_15-30cm_mean_patched.vrt",
  "clay_0-5cm_mean_patched.vrt",
  "clay_5-15cm_mean_patched.vrt",
  "clay_15-30cm_mean_patched.vrt"
)

paths <- file.path(
  soil_dir,
  file_names
)

if (any(!file.exists(paths))) {
  stop(
    "Missing files:\n",
    paste(
      paths[!file.exists(paths)],
      collapse = "\n"
    )
  )
}

soil <- rast(paths)

names(soil) <- layer_names

cat("\n===== RASTER METADATA =====\n")

metadata <- bind_rows(
  lapply(
    seq_len(nlyr(soil)),
    function(i) {

      r <- soil[[i]]

      tibble(
        layer = names(soil)[i],
        nrow = nrow(r),
        ncol = ncol(r),
        resolution_x = res(r)[1],
        resolution_y = res(r)[2],
        xmin = xmin(r),
        xmax = xmax(r),
        ymin = ymin(r),
        ymax = ymax(r),
        datatype = datatype(r)
      )
    }
  )
)

print(
  metadata,
  n = Inf,
  width = Inf
)

cat("\n===== GEOMETRY COMPARISON =====\n")

geometry_check <- tibble(
  layer = names(soil),
  same_geometry = vapply(
    seq_len(nlyr(soil)),
    function(i) {
      isTRUE(
        compareGeom(
          soil[[1]],
          soil[[i]],
          stopOnError = FALSE
        )
      )
    },
    logical(1)
  )
)

print(
  geometry_check,
  n = Inf,
  width = Inf
)

test_points <- tribble(
  ~location,       ~lon,    ~lat,
  "Beijing",       116.40,   39.90,
  "Delhi",          77.20,   28.60,
  "Paris",           2.35,   48.86,
  "Nairobi",        36.82,   -1.29,
  "Sao_Paulo",     -46.63,  -23.55,
  "Sydney",        151.21,  -33.87,
  "New_York",      -74.01,   40.71,
  "Cairo",          31.24,   30.04,
  "Lima",          -77.04,  -12.05,
  "Moscow",         37.62,   55.75,
  "Mexico_City",   -99.13,   19.43,
  "Cape_Town",      18.42,  -33.93
)

points_vect <- vect(
  test_points,
  geom = c("lon", "lat"),
  crs = "EPSG:4326"
)

extracted <- extract(
  soil,
  points_vect,
  ID = FALSE
)

sample_values <- bind_cols(
  test_points,
  as_tibble(extracted)
)

cat("\n===== TEST-POINT RAW VALUES =====\n")

print(
  sample_values,
  n = Inf,
  width = Inf
)

cat("\n===== SAMPLE VALUE SUMMARY =====\n")

sample_summary <- bind_rows(
  lapply(
    layer_names,
    function(nm) {

      x <- sample_values[[nm]]
      finite_x <- x[is.finite(x)]

      tibble(
        layer = nm,
        n_finite = length(finite_x),
        minimum = ifelse(
          length(finite_x) > 0,
          min(finite_x),
          NA_real_
        ),
        median = ifelse(
          length(finite_x) > 0,
          median(finite_x),
          NA_real_
        ),
        maximum = ifelse(
          length(finite_x) > 0,
          max(finite_x),
          NA_real_
        )
      )
    }
  )
)

print(
  sample_summary,
  n = Inf,
  width = Inf
)

cat("\nSoilGrids VRT audit finished.\n")
