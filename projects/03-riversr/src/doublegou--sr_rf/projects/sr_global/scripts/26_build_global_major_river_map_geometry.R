#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(readr)
  library(tibble)
})

sf::sf_use_s2(TRUE)

project_dir <- Sys.getenv(
  "SR_GLOBAL_DIR",
  unset = "/home/zhangmeng/projects/sr_global"
)

max_ord_flow <- as.integer(
  Sys.getenv(
    "SR_MAP_MAX_ORD_FLOW",
    unset = "5"
  )
)

regions <- c(
  "af", "ar", "as",
  "au", "eu", "gr",
  "na", "sa", "si"
)

attribute_file <- file.path(
  project_dir,
  "data_processed/global/final_prediction",
  "global_river_prediction_map_attributes.rds"
)

inventory_file <- file.path(
  project_dir,
  "outputs/global/final_river_prediction_qc",
  "map_ORD_FLOW_threshold_inventory_by_region.csv"
)

out_dir <- file.path(
  project_dir,
  "data_processed/global/final_prediction",
  paste0(
    "map_geometry_ordflow",
    max_ord_flow
  )
)

qc_dir <- file.path(
  project_dir,
  "outputs/global/final_river_prediction_qc"
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

if (!file.exists(attribute_file)) {
  stop(
    "Missing map attribute file: ",
    attribute_file
  )
}

if (!file.exists(inventory_file)) {
  stop(
    "Missing map threshold inventory: ",
    inventory_file
  )
}

cat(
  "Maximum ORD_FLOW:",
  max_ord_flow,
  "\n"
)

attributes <- readRDS(
  attribute_file
) %>%
  filter(
    prediction_status == "predicted",
    is.finite(ORD_FLOW),
    ORD_FLOW <= max_ord_flow
  ) %>%
  mutate(
    region = as.character(region),
    hyriv_key = sprintf(
      "%.0f",
      as.numeric(HYRIV_ID)
    )
  ) %>%
  select(
    region,
    source_row_index,
    HYRIV_ID,
    hyriv_key,
    HYBAS_ID,
    rf_mean,
    qrf_p10,
    qrf_p50,
    qrf_p90,
    qrf_p80_width,
    ORD_STRA,
    ORD_CLAS,
    ORD_FLOW,
    log_DIS_AV_CMS
  )

inventory <- read_csv(
  inventory_file,
  show_col_types = FALSE
) %>%
  filter(
    max_ORD_FLOW == max_ord_flow
  )

if (nrow(inventory) != length(regions)) {
  stop(
    "Threshold inventory does not contain all nine regions."
  )
}

expected_global <- sum(
  inventory$n_segments
)

cat(
  "Expected global map segments:",
  expected_global,
  "\n\n"
)

region_objects <- vector(
  "list",
  length(regions)
)

names(region_objects) <- regions

qc_list <- vector(
  "list",
  length(regions)
)

names(qc_list) <- regions

for (r in regions) {

  cat(
    "========================================\n"
  )

  cat(
    "REGION:",
    toupper(r),
    "\n"
  )

  river_file <- file.path(
    project_dir,
    "data_raw/hydrosheds/HydroRIVERS_global",
    paste0(
      "HydroRIVERS_v10_",
      r,
      "_shp"
    ),
    paste0(
      "HydroRIVERS_v10_",
      r,
      ".shp"
    )
  )

  if (!file.exists(river_file)) {
    stop(
      "Missing HydroRIVERS file: ",
      river_file
    )
  }

  attrs_r <- attributes %>%
    filter(
      region == r
    )

  expected_r <- inventory$n_segments[
    match(
      r,
      inventory$region
    )
  ]

  if (nrow(attrs_r) != expected_r) {
    stop(
      "Attribute count mismatch for region ",
      r,
      ": ",
      nrow(attrs_r),
      " versus ",
      expected_r
    )
  }

  layers <- st_layers(
    river_file
  )

  layer_name <- layers$name[1]

  query_text <- sprintf(
    paste0(
      'SELECT HYRIV_ID, ORD_FLOW ',
      'FROM "%s" ',
      'WHERE ORD_FLOW <= %d'
    ),
    layer_name,
    max_ord_flow
  )

  cat(
    "Reading selected river geometry...\n"
  )

  rivers <- st_read(
    river_file,
    query = query_text,
    quiet = TRUE
  )

  if (is.na(st_crs(rivers))) {
    stop(
      "Missing CRS for region ",
      r
    )
  }

  rivers <- st_transform(
    rivers,
    4326
  )

  rivers <- rivers[
    !st_is_empty(rivers),
    ,
    drop = FALSE
  ]

  rivers <- rivers %>%
    transmute(
      hyriv_key = sprintf(
        "%.0f",
        as.numeric(HYRIV_ID)
      )
    )

  if (
    anyDuplicated(
      rivers$hyriv_key
    )
  ) {
    stop(
      "Duplicate HYRIV_ID geometry keys in region ",
      r
    )
  }

  rivers_joined <- rivers %>%
    inner_join(
      attrs_r,
      by = "hyriv_key"
    )

  if (nrow(rivers_joined) != expected_r) {
    stop(
      "Joined geometry count mismatch for region ",
      r,
      ": ",
      nrow(rivers_joined),
      " versus ",
      expected_r
    )
  }

  rivers_joined <- suppressWarnings(
    st_wrap_dateline(
      rivers_joined,
      options = c(
        "WRAPDATELINE=YES",
        "DATELINEOFFSET=10"
      ),
      quiet = TRUE
    )
  )

  regional_file <- file.path(
    out_dir,
    paste0(
      "major_rivers_ordflow",
      max_ord_flow,
      "_",
      r,
      ".rds"
    )
  )

  saveRDS(
    rivers_joined,
    regional_file,
    compress = "gzip"
  )

  region_objects[[r]] <- rivers_joined

  qc_list[[r]] <- tibble(
    region = r,
    max_ORD_FLOW = max_ord_flow,
    n_expected = expected_r,
    n_geometry_query = nrow(rivers),
    n_joined_predicted = nrow(rivers_joined),
    n_missing_rf_mean = sum(
      !is.finite(
        rivers_joined$rf_mean
      )
    ),
    n_missing_uncertainty = sum(
      !is.finite(
        rivers_joined$qrf_p80_width
      )
    )
  )

  cat(
    "Expected:",
    expected_r,
    "| queried:",
    nrow(rivers),
    "| joined:",
    nrow(rivers_joined),
    "\n\n"
  )

  rm(
    rivers,
    rivers_joined
  )

  invisible(
    gc()
  )
}

cat(
  "Combining nine map geometry tables...\n"
)

global_rivers <- do.call(
  rbind,
  region_objects
)

rm(
  region_objects
)

invisible(
  gc()
)

if (nrow(global_rivers) != expected_global) {
  stop(
    "Global map geometry row mismatch: ",
    nrow(global_rivers),
    " versus ",
    expected_global
  )
}

if (
  anyDuplicated(
    paste(
      global_rivers$region,
      global_rivers$HYRIV_ID,
      sep = "_"
    )
  )
) {
  stop(
    "Duplicate region + HYRIV_ID in global map geometry."
  )
}

global_file <- file.path(
  out_dir,
  paste0(
    "global_major_rivers_ordflow",
    max_ord_flow,
    ".rds"
  )
)

cat(
  "Saving global map geometry...\n"
)

saveRDS(
  global_rivers,
  global_file,
  compress = "gzip"
)

qc <- bind_rows(
  qc_list
)

write_csv(
  qc,
  file.path(
    qc_dir,
    paste0(
      "global_map_geometry_ordflow",
      max_ord_flow,
      "_qc.csv"
    )
  )
)

cat(
  "\n===== MAP GEOMETRY QC =====\n"
)

print(
  qc,
  n = Inf,
  width = Inf
)

cat(
  "\nGlobal map segments:",
  nrow(global_rivers),
  "\n"
)

cat(
  "Geometry types:\n"
)

print(
  table(
    as.character(
      st_geometry_type(
        global_rivers
      )
    )
  )
)

cat(
  "\nGlobal map geometry saved to:\n",
  global_file,
  "\n"
)

cat(
  "\nGLOBAL MAJOR RIVER MAP GEOMETRY BUILT\n"
)
