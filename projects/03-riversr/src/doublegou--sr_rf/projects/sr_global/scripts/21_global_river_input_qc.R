#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(tibble)
  library(readr)
})

regions <- c(
  "af", "ar", "as",
  "au", "eu", "gr",
  "na", "sa", "si"
)

river_required <- c(
  "HYRIV_ID",
  "NEXT_DOWN",
  "MAIN_RIV",
  "LENGTH_KM",
  "DIST_DN_KM",
  "DIST_UP_KM",
  "CATCH_SKM",
  "UPLAND_SKM",
  "DIS_AV_CMS",
  "ORD_STRA",
  "ORD_CLAS",
  "ORD_FLOW"
)

river_qc <- list()
l6_qc <- list()

for (r in regions) {

  cat(
    "\n========================================\n",
    "REGION: ", toupper(r), "\n",
    sep = ""
  )

  river_file <- file.path(
    "data_raw/hydrosheds/HydroRIVERS_global",
    paste0("HydroRIVERS_v10_", r, "_shp"),
    paste0("HydroRIVERS_v10_", r, ".shp")
  )

  if (!file.exists(river_file)) {
    stop("Missing HydroRIVERS file: ", river_file)
  }

  layers <- st_layers(river_file)
  layer_name <- layers$name[[1]]

  river_one <- st_read(
    river_file,
    query = sprintf(
      'SELECT * FROM "%s" LIMIT 1',
      layer_name
    ),
    quiet = TRUE
  )

  missing_river_vars <- setdiff(
    river_required,
    names(river_one)
  )

  cat(
    "HydroRIVERS features:",
    layers$features[[1]],
    "\n"
  )

  cat(
    "Geometry:",
    paste(
      unique(
        as.character(
          st_geometry_type(river_one)
        )
      ),
      collapse = ", "
    ),
    "\n"
  )

  cat(
    "CRS EPSG:",
    st_crs(river_one)$epsg,
    "\n"
  )

  cat(
    "Missing required fields:",
    length(missing_river_vars),
    "\n"
  )

  if (length(missing_river_vars) > 0) {
    print(missing_river_vars)
  }

  river_qc[[r]] <- tibble(
    region = r,
    n_river_segments =
      as.numeric(layers$features[[1]]),
    geometry_type =
      paste(
        unique(
          as.character(
            st_geometry_type(river_one)
          )
        ),
        collapse = ";"
      ),
    epsg = st_crs(river_one)$epsg,
    n_missing_required_fields =
      length(missing_river_vars),
    missing_required_fields =
      paste(
        missing_river_vars,
        collapse = ";"
      )
  )

  geo <- readRDS(
    file.path(
      "data_processed/global/glim_l6_by_region",
      paste0(
        "l6_glim_local_upstream_",
        r,
        ".rds"
      )
    )
  )

  climate <- readRDS(
    file.path(
      paste0(
        "data_processed/global/",
        "climate_terrain_l6_by_region"
      ),
      paste0(
        "l6_climate_terrain_local_upstream_",
        r,
        ".rds"
      )
    )
  )

  soil <- readRDS(
    file.path(
      "data_processed/global/soil_l6_by_region",
      paste0(
        "l6_soil_local_upstream_",
        r,
        ".rds"
      )
    )
  )

  make_key <- function(x) {
    sprintf(
      "%.0f",
      as.numeric(x)
    )
  }

  geo$hybas_key <- make_key(geo$HYBAS_ID)
  climate$hybas_key <- make_key(climate$HYBAS_ID)
  soil$hybas_key <- make_key(soil$HYBAS_ID)

  geo_dup <- sum(
    duplicated(geo$hybas_key)
  )

  climate_dup <- sum(
    duplicated(climate$hybas_key)
  )

  soil_dup <- sum(
    duplicated(soil$hybas_key)
  )

  geo_keys <- geo$hybas_key
  climate_keys <- climate$hybas_key
  soil_keys <- soil$hybas_key

  cat(
    "L6 rows geology/climate/soil:",
    nrow(geo),
    nrow(climate),
    nrow(soil),
    "\n"
  )

  cat(
    "Duplicate keys geology/climate/soil:",
    geo_dup,
    climate_dup,
    soil_dup,
    "\n"
  )

  cat(
    "Climate keys absent from geology:",
    length(
      setdiff(
        climate_keys,
        geo_keys
      )
    ),
    "\n"
  )

  cat(
    "Soil keys absent from geology:",
    length(
      setdiff(
        soil_keys,
        geo_keys
      )
    ),
    "\n"
  )

  l6_qc[[r]] <- tibble(
    region = r,
    n_geo = nrow(geo),
    n_climate = nrow(climate),
    n_soil = nrow(soil),
    geo_duplicate_keys = geo_dup,
    climate_duplicate_keys = climate_dup,
    soil_duplicate_keys = soil_dup,
    climate_keys_absent_from_geo =
      length(
        setdiff(
          climate_keys,
          geo_keys
        )
      ),
    soil_keys_absent_from_geo =
      length(
        setdiff(
          soil_keys,
          geo_keys
        )
      )
  )
}

river_qc <- bind_rows(river_qc)
l6_qc <- bind_rows(l6_qc)

cat("\n===== HYDRORIVERS QC SUMMARY =====\n")
print(
  river_qc,
  n = Inf,
  width = Inf
)

cat("\n===== L6 TABLE QC SUMMARY =====\n")
print(
  l6_qc,
  n = Inf,
  width = Inf
)

out_dir <- paste0(
  "outputs/global/",
  "final_river_prediction_qc"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

write_csv(
  river_qc,
  file.path(
    out_dir,
    "hydrorivers_region_inventory.csv"
  )
)

write_csv(
  l6_qc,
  file.path(
    out_dir,
    "l6_covariate_table_inventory.csv"
  )
)

stopifnot(
  all(
    river_qc$
      n_missing_required_fields == 0
  ),
  all(
    l6_qc$geo_duplicate_keys == 0
  ),
  all(
    l6_qc$climate_duplicate_keys == 0
  ),
  all(
    l6_qc$soil_duplicate_keys == 0
  )
)

cat(
  "\nGLOBAL RIVER INPUT QC PASSED\n"
)
