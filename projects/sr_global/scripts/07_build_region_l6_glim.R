#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(sf)
  library(terra)
  library(dplyr)
  library(tidyr)
  library(readr)
  library(tibble)
})

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 1) {
  stop(
    "Usage: Rscript 07_build_region_l6_glim.R <region>"
  )
}

region <- tolower(args[[1]])

valid_regions <- c(
  "af", "ar", "as", "au", "eu",
  "gr", "na", "sa", "si"
)

if (!region %in% valid_regions) {
  stop("Unknown HydroBASINS region: ", region)
}

site_dir <- Sys.getenv(
  "SR_GLOBAL_DIR",
  unset = "/home/zhangmeng/projects/sr_global"
)

n_threads <- as.integer(
  Sys.getenv("SR_NTHREADS", unset = "4")
)

terraOptions(
  tempdir = Sys.getenv("TMPDIR", unset = tempdir()),
  memfrac = 0.75,
  threads = n_threads,
  progress = 1
)

basin_file <- file.path(
  site_dir,
  "data_raw/hydrosheds/HydroBASINS_global",
  paste0("hybas_", region, "_lev06_v1c.shp")
)

glim_file <- file.path(
  site_dir,
  "data_raw/geology/GLiM",
  "GLiM_gridded_0p5deg_unzipped",
  "glim_wgs84_0point5deg.txt.asc"
)

out_dir <- file.path(
  site_dir,
  "data_processed/global/glim_l6_by_region"
)

qc_dir <- file.path(
  site_dir,
  "outputs/global/glim_l6_qc"
)

dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(qc_dir, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(basin_file)) {
  stop("Missing HydroBASINS file: ", basin_file)
}

if (!file.exists(glim_file)) {
  stop("Missing GLiM file: ", glim_file)
}

message("Region: ", region)
message("Reading L6 HydroBASINS: ", basin_file)

basins <- st_read(
  basin_file,
  quiet = TRUE
)

if (is.na(st_crs(basins))) {
  stop("HydroBASINS CRS is missing.")
}

basins <- st_transform(
  basins,
  4326
)

# Split polygons crossing the international date line.
# This is especially important for the Australia/Oceania region.
basins <- suppressWarnings(
  sf::st_wrap_dateline(
    basins,
    options = c(
      "WRAPDATELINE=YES",
      "DATELINEOFFSET=10"
    ),
    quiet = TRUE
  )
)

valid_geometry <- st_is_valid(basins)

if (any(!valid_geometry, na.rm = TRUE)) {
  message(
    "Repairing invalid basin geometries: ",
    sum(!valid_geometry, na.rm = TRUE)
  )
}

basins <- st_make_valid(basins)

# Retain polygonal components and standardise geometry type.
basins <- suppressWarnings(
  st_collection_extract(
    basins,
    "POLYGON"
  )
)

basins <- suppressWarnings(
  st_cast(
    basins,
    "MULTIPOLYGON"
  )
)

basins <- basins[
  !st_is_empty(basins),
  ,
  drop = FALSE
]

valid_after <- st_is_valid(basins)

if (any(!valid_after, na.rm = TRUE)) {
  stop(
    "Invalid basin geometries remain after repair: ",
    sum(!valid_after, na.rm = TRUE)
  )
}

basins$basin_row_id <- seq_len(nrow(basins))

required_fields <- c(
  "HYBAS_ID",
  "NEXT_DOWN",
  "MAIN_BAS",
  "SUB_AREA",
  "UP_AREA",
  "PFAF_ID",
  "basin_row_id"
)

missing_fields <- setdiff(
  required_fields,
  names(basins)
)

if (length(missing_fields) > 0) {
  stop(
    "Missing HydroBASINS fields: ",
    paste(missing_fields, collapse = ", ")
  )
}

basin_attributes <- basins %>%
  st_drop_geometry() %>%
  select(all_of(required_fields))

message("L6 basin polygons: ", nrow(basins))
message("Reading GLiM raster: ", glim_file)

glim <- rast(glim_file)
names(glim) <- "glim_class"

cell_area <- cellSize(
  glim,
  unit = "km"
)

names(cell_area) <- "cell_area_km2"

glim_stack <- c(
  glim,
  cell_area
)

# GLiM code → grouped lithology.
# wb, ig and nd are retained for coverage QC,
# but excluded from the lithology-fraction denominator.
class_mapping <- tribble(
  ~glim_class, ~glim_code, ~lith_group,
  1L,  "su", "unconsolidated",
  2L,  "vb", "volcanic",
  3L,  "ss", "siliciclastic",
  4L,  "pb", "plutonic",
  5L,  "sm", "mixed_sedimentary",
  6L,  "sc", "carbonate",
  7L,  "va", "volcanic",
  8L,  "mt", "metamorphic",
  9L,  "pa", "plutonic",
  10L, "vi", "volcanic",
  11L, "wb", "water_ice",
  12L, "py", "volcanic",
  13L, "pi", "plutonic",
  14L, "ev", "evaporite",
  15L, "nd", "no_data",
  16L, "ig", "water_ice"
)

if (region == "af") {
  write_csv(
    class_mapping,
    file.path(
      qc_dir,
      "GLiM_grouped_class_mapping.csv"
    )
  )
}

message(
  "Extracting exact area-weighted GLiM intersections..."
)

basins_vect <- terra::vect(basins)
basins_vect <- terra::makeValid(basins_vect)

extracted <- terra::extract(
  glim_stack,
  basins_vect,
  exact = TRUE,
  cells = TRUE,
  ID = TRUE
)

extracted <- as_tibble(extracted)

coverage_column <- intersect(
  c("fraction", "weight"),
  names(extracted)
)

if (length(coverage_column) == 0) {
  stop(
    "terra::extract did not return a coverage fraction column. ",
    "Columns were: ",
    paste(names(extracted), collapse = ", ")
  )
}

coverage_column <- coverage_column[[1]]

extracted <- extracted %>%
  filter(
    !is.na(glim_class),
    is.finite(cell_area_km2),
    is.finite(.data[[coverage_column]])
  ) %>%
  mutate(
    glim_class = as.integer(round(glim_class)),
    covered_area_km2 =
      cell_area_km2 * .data[[coverage_column]]
  ) %>%
  left_join(
    class_mapping,
    by = "glim_class"
  )

if (any(is.na(extracted$lith_group))) {
  unknown_codes <- sort(
    unique(
      extracted$glim_class[
        is.na(extracted$lith_group)
      ]
    )
  )

  stop(
    "Unmapped GLiM classes: ",
    paste(unknown_codes, collapse = ", ")
  )
}

message(
  "Extracted raster-polygon intersections: ",
  nrow(extracted)
)

local_long <- extracted %>%
  group_by(
    ID,
    lith_group
  ) %>%
  summarise(
    covered_area_km2 = sum(
      covered_area_km2,
      na.rm = TRUE
    ),
    .groups = "drop"
  )

local_wide <- local_long %>%
  pivot_wider(
    names_from = lith_group,
    values_from = covered_area_km2,
    names_prefix = "local_area_",
    values_fill = 0
  )

group_levels <- c(
  "unconsolidated",
  "siliciclastic",
  "mixed_sedimentary",
  "carbonate",
  "metamorphic",
  "plutonic",
  "volcanic",
  "evaporite",
  "water_ice",
  "no_data"
)

local_area_columns <- paste0(
  "local_area_",
  group_levels
)

basin_table <- basin_attributes %>%
  left_join(
    local_wide,
    by = c("basin_row_id" = "ID")
  )

for (v in local_area_columns) {
  if (!v %in% names(basin_table)) {
    basin_table[[v]] <- 0
  }

  basin_table[[v]][
    is.na(basin_table[[v]])
  ] <- 0
}

lith_groups <- c(
  "unconsolidated",
  "siliciclastic",
  "mixed_sedimentary",
  "carbonate",
  "metamorphic",
  "plutonic",
  "volcanic",
  "evaporite"
)

local_lith_area_columns <- paste0(
  "local_area_",
  lith_groups
)

basin_table$local_total_extracted_area_km2 <-
  rowSums(
    basin_table[
      ,
      local_area_columns,
      drop = FALSE
    ],
    na.rm = TRUE
  )

basin_table$local_lith_area_km2 <-
  rowSums(
    basin_table[
      ,
      local_lith_area_columns,
      drop = FALSE
    ],
    na.rm = TRUE
  )

basin_table$local_glim_coverage_ratio <-
  ifelse(
    basin_table$SUB_AREA > 0,
    basin_table$local_total_extracted_area_km2 /
      basin_table$SUB_AREA,
    NA_real_
  )

for (g in lith_groups) {
  area_name <- paste0(
    "local_area_",
    g
  )

  frac_name <- paste0(
    "local_geo_",
    g,
    "_frac"
  )

  basin_table[[frac_name]] <- ifelse(
    basin_table$local_lith_area_km2 > 0,
    basin_table[[area_name]] /
      basin_table$local_lith_area_km2,
    NA_real_
  )
}

basin_table$local_water_ice_frac_all <- ifelse(
  basin_table$local_total_extracted_area_km2 > 0,
  basin_table$local_area_water_ice /
    basin_table$local_total_extracted_area_km2,
  NA_real_
)

basin_table$local_no_data_frac_all <- ifelse(
  basin_table$local_total_extracted_area_km2 > 0,
  basin_table$local_area_no_data /
    basin_table$local_total_extracted_area_km2,
  NA_real_
)

# ------------------------------------------------------------
# Upstream accumulation using HYBAS_ID → NEXT_DOWN
# ------------------------------------------------------------

message(
  "Accumulating L6 lithology areas downstream..."
)

id_character <- sprintf(
  "%.0f",
  as.numeric(basin_table$HYBAS_ID)
)

next_character <- ifelse(
  is.na(basin_table$NEXT_DOWN) |
    basin_table$NEXT_DOWN == 0,
  NA_character_,
  sprintf(
    "%.0f",
    as.numeric(basin_table$NEXT_DOWN)
  )
)

id_lookup <- setNames(
  seq_len(nrow(basin_table)),
  id_character
)

downstream_index <- unname(
  id_lookup[next_character]
)

external_next <- (
  !is.na(next_character) &
    is.na(downstream_index)
)

if (any(external_next)) {
  warning(
    "NEXT_DOWN IDs outside this regional L6 file: ",
    sum(external_next)
  )
}

indegree <- tabulate(
  downstream_index[
    !is.na(downstream_index)
  ],
  nbins = nrow(basin_table)
)

queue <- which(indegree == 0L)
queue_position <- 1L

accumulated_area <- as.matrix(
  basin_table[
    ,
    local_area_columns,
    drop = FALSE
  ]
)

storage.mode(accumulated_area) <- "double"

processed <- logical(
  nrow(basin_table)
)

while (queue_position <= length(queue)) {

  current <- queue[[queue_position]]
  queue_position <- queue_position + 1L

  processed[[current]] <- TRUE

  downstream <- downstream_index[[current]]

  if (!is.na(downstream)) {

    accumulated_area[
      downstream,
    ] <- accumulated_area[
      downstream,
    ] + accumulated_area[
      current,
    ]

    indegree[[downstream]] <-
      indegree[[downstream]] - 1L

    if (indegree[[downstream]] == 0L) {
      queue <- c(
        queue,
        downstream
      )
    }
  }
}

if (sum(processed) != nrow(basin_table)) {
  stop(
    "HydroBASINS network accumulation failed. ",
    "Unprocessed basins: ",
    nrow(basin_table) - sum(processed)
  )
}

upstream_area_columns <- sub(
  "^local_area_",
  "up_area_",
  local_area_columns
)

for (i in seq_along(upstream_area_columns)) {
  basin_table[[upstream_area_columns[[i]]]] <-
    accumulated_area[, i]
}

upstream_lith_area_columns <- paste0(
  "up_area_",
  lith_groups
)

basin_table$up_total_extracted_area_km2 <-
  rowSums(
    basin_table[
      ,
      upstream_area_columns,
      drop = FALSE
    ],
    na.rm = TRUE
  )

basin_table$up_lith_area_km2 <-
  rowSums(
    basin_table[
      ,
      upstream_lith_area_columns,
      drop = FALSE
    ],
    na.rm = TRUE
  )

basin_table$up_glim_coverage_ratio <-
  ifelse(
    basin_table$UP_AREA > 0,
    basin_table$up_total_extracted_area_km2 /
      basin_table$UP_AREA,
    NA_real_
  )

for (g in lith_groups) {
  area_name <- paste0(
    "up_area_",
    g
  )

  frac_name <- paste0(
    "up_geo_",
    g,
    "_frac"
  )

  basin_table[[frac_name]] <- ifelse(
    basin_table$up_lith_area_km2 > 0,
    basin_table[[area_name]] /
      basin_table$up_lith_area_km2,
    NA_real_
  )
}

basin_table$up_water_ice_frac_all <- ifelse(
  basin_table$up_total_extracted_area_km2 > 0,
  basin_table$up_area_water_ice /
    basin_table$up_total_extracted_area_km2,
  NA_real_
)

basin_table$up_no_data_frac_all <- ifelse(
  basin_table$up_total_extracted_area_km2 > 0,
  basin_table$up_area_no_data /
    basin_table$up_total_extracted_area_km2,
  NA_real_
)

basin_table$region <- region

out_rds <- file.path(
  out_dir,
  paste0(
    "l6_glim_local_upstream_",
    region,
    ".rds"
  )
)

out_csv <- file.path(
  out_dir,
  paste0(
    "l6_glim_local_upstream_",
    region,
    ".csv"
  )
)

saveRDS(
  basin_table,
  out_rds
)

write_csv(
  basin_table,
  out_csv
)

finite_local_coverage <-
  basin_table$local_glim_coverage_ratio[
    is.finite(
      basin_table$local_glim_coverage_ratio
    )
  ]

finite_up_coverage <-
  basin_table$up_glim_coverage_ratio[
    is.finite(
      basin_table$up_glim_coverage_ratio
    )
  ]

qc_summary <- tibble(
  region = region,
  n_l6_basins = nrow(basin_table),
  n_internal_downstream_links =
    sum(!is.na(downstream_index)),
  n_external_downstream_links =
    sum(external_next),
  n_terminal_basins =
    sum(is.na(next_character)),
  n_local_lithology_covered =
    sum(basin_table$local_lith_area_km2 > 0),
  n_upstream_lithology_covered =
    sum(basin_table$up_lith_area_km2 > 0),
  median_local_coverage_ratio =
    median(
      finite_local_coverage,
      na.rm = TRUE
    ),
  median_upstream_coverage_ratio =
    median(
      finite_up_coverage,
      na.rm = TRUE
    )
)

write_csv(
  qc_summary,
  file.path(
    qc_dir,
    paste0(
      "l6_glim_qc_",
      region,
      ".csv"
    )
  )
)

cat("\nRegion QC summary:\n")
print(qc_summary)

cat("\nLocal lithology fraction sums:\n")
print(
  summary(
    rowSums(
      basin_table[
        ,
        paste0(
          "local_geo_",
          lith_groups,
          "_frac"
        ),
        drop = FALSE
      ],
      na.rm = FALSE
    )
  )
)

cat("\nUpstream lithology fraction sums:\n")
print(
  summary(
    rowSums(
      basin_table[
        ,
        paste0(
          "up_geo_",
          lith_groups,
          "_frac"
        ),
        drop = FALSE
      ],
      na.rm = FALSE
    )
  )
)

cat(
  "\nRegional L6 GLiM processing finished:",
  region,
  "\n"
)
