#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(terra)
  library(sf)
  library(data.table)
  library(dplyr)
  library(readr)
})

sf::sf_use_s2(TRUE)

args <- commandArgs(
  trailingOnly = TRUE
)

if (length(args) != 1) {
  stop(
    "Usage: Rscript ",
    "11_build_region_l6_climate_terrain.R <region>"
  )
}

region <- args[[1]]

valid_regions <- c(
  "af", "ar", "as", "au", "eu",
  "gr", "na", "sa", "si"
)

if (!region %in% valid_regions) {
  stop("Invalid region: ", region)
}

root_dir <- Sys.getenv(
  "SR_GLOBAL_DIR",
  unset = "/home/zhangmeng/projects/sr_global"
)

tmp_parent <- Sys.getenv(
  "TMPDIR",
  unset = "/tmp"
)

tmp_dir <- file.path(
  tmp_parent,
  paste0(
    "sr_l6_climate_",
    region,
    "_",
    Sys.getpid()
  )
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

input_dir <- file.path(
  root_dir,
  "data_processed/global/climate_terrain_2p5m"
)

out_dir <- file.path(
  root_dir,
  "data_processed/global/climate_terrain_l6_by_region"
)

qc_dir <- file.path(
  root_dir,
  "outputs/global/climate_terrain_l6_qc"
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

predictor_files <- c(
  bio1_C = file.path(
    input_dir,
    "bio1_annual_mean_temperature_C.tif"
  ),
  bio4_C_sd = file.path(
    input_dir,
    "bio4_temperature_seasonality_C_sd.tif"
  ),
  bio12_mm = file.path(
    input_dir,
    "bio12_annual_precipitation_mm.tif"
  ),
  bio15_cv = file.path(
    input_dir,
    "bio15_precipitation_seasonality_cv.tif"
  ),
  ai_ratio = file.path(
    input_dir,
    "aridity_index_ratio.tif"
  ),
  et0_mm = file.path(
    input_dir,
    "annual_et0_mm.tif"
  ),
  elevation_m = file.path(
    input_dir,
    "elevation_m.tif"
  )
)

area_file <- file.path(
  input_dir,
  "template_cell_area_km2.tif"
)

missing_files <- c(
  predictor_files,
  area_file
)

missing_files <- missing_files[
  !file.exists(missing_files)
]

if (length(missing_files) > 0) {
  stop(
    "Missing raster files:\n",
    paste(
      missing_files,
      collapse = "\n"
    )
  )
}

message(
  "Reading predictor rasters for region: ",
  region
)

predictors <- rast(
  unname(predictor_files)
)

names(predictors) <- names(
  predictor_files
)

cell_area <- rast(
  area_file
)

names(cell_area) <- "cell_area_km2"

for (i in seq_len(nlyr(predictors))) {

  if (
    !compareGeom(
      predictors[[i]],
      cell_area,
      stopOnError = FALSE
    )
  ) {
    stop(
      "Raster geometry mismatch: ",
      names(predictors)[i]
    )
  }
}

extract_stack <- c(
  predictors,
  cell_area
)

variable_names <- names(
  predictor_files
)

basin_file <- file.path(
  root_dir,
  "data_raw/hydrosheds/HydroBASINS_global",
  paste0(
    "hybas_",
    region,
    "_lev06_v1c.shp"
  )
)

if (!file.exists(basin_file)) {
  stop(
    "Missing basin file: ",
    basin_file
  )
}

message(
  "Reading L6 basins: ",
  region
)

basins <- st_read(
  basin_file,
  quiet = TRUE
) %>%
  select(
    HYBAS_ID,
    NEXT_DOWN,
    MAIN_BAS,
    SUB_AREA,
    UP_AREA,
    PFAF_ID
  )

original_n_basins <- nrow(
  basins
)

basins$basin_row_id <- seq_len(
  original_n_basins
)

basins <- st_transform(
  basins,
  4326
)

basins <- suppressWarnings(
  st_wrap_dateline(
    basins,
    options = c(
      "WRAPDATELINE=YES",
      "DATELINEOFFSET=10"
    ),
    quiet = TRUE
  )
)

basins <- suppressWarnings(
  st_make_valid(
    basins
  )
)

geometry_types <- as.character(
  st_geometry_type(
    basins
  )
)

if (
  any(
    geometry_types ==
      "GEOMETRYCOLLECTION"
  )
) {

  basins <- suppressWarnings(
    st_collection_extract(
      basins,
      "POLYGON"
    )
  )
}

basins <- basins[
  !st_is_empty(basins),
  ,
  drop = FALSE
]

if (
  anyDuplicated(
    basins$basin_row_id
  ) > 0
) {

  basins <- basins %>%
    group_by(
      basin_row_id
    ) %>%
    summarise(
      HYBAS_ID = first(HYBAS_ID),
      NEXT_DOWN = first(NEXT_DOWN),
      MAIN_BAS = first(MAIN_BAS),
      SUB_AREA = first(SUB_AREA),
      UP_AREA = first(UP_AREA),
      PFAF_ID = first(PFAF_ID),
      do_union = TRUE,
      .groups = "drop"
    )
}

basins <- basins[
  order(
    basins$basin_row_id
  ),
  ,
  drop = FALSE
]

if (
  nrow(basins) !=
    original_n_basins
) {
  stop(
    "Basin count changed after geometry repair: ",
    original_n_basins,
    " -> ",
    nrow(basins)
  )
}

basin_vect <- terra::makeValid(
  vect(
    basins
  )
)

chunk_size <- as.integer(
  Sys.getenv(
    "SR_BASIN_CHUNK_SIZE",
    unset = "100"
  )
)

basin_indices <- seq_len(
  nrow(basins)
)

chunk_ids <- split(
  basin_indices,
  ceiling(
    basin_indices /
      chunk_size
  )
)

message(
  "L6 basins: ",
  nrow(basins)
)

message(
  "Extraction chunks: ",
  length(chunk_ids)
)

summarise_chunk <- function(
    index_vector
) {

  extracted <- terra::extract(
    extract_stack,
    basin_vect[index_vector],
    exact = TRUE,
    cells = TRUE,
    ID = TRUE
  )

  base <- data.table(
    ID = seq_along(
      index_vector
    ),
    basin_row_id = index_vector
  )

  if (
    is.null(extracted) ||
      nrow(extracted) == 0
  ) {

    base[
      ,
      local_total_extracted_area_km2 :=
        0
    ]

    for (v in variable_names) {

      base[
        ,
        paste0(
          "local_",
          v,
          "_numerator"
        ) := 0
      ]

      base[
        ,
        paste0(
          "local_",
          v,
          "_valid_area_km2"
        ) := 0
      ]

      base[
        ,
        paste0(
          "local_",
          v
        ) := NA_real_
      ]

      base[
        ,
        paste0(
          "local_",
          v,
          "_coverage_ratio"
        ) := NA_real_
      ]
    }

    return(base)
  }

  extracted <- as.data.table(
    extracted
  )

  if (
    !"fraction" %in%
      names(extracted)
  ) {
    stop(
      "terra extraction did not return ",
      "a fraction column."
    )
  }

  extracted[
    ,
    overlap_area_km2 :=
      cell_area_km2 *
      fraction
  ]

  total_area <- extracted[
    is.finite(
      overlap_area_km2
    ) &
      overlap_area_km2 > 0,
    .(
      local_total_extracted_area_km2 =
        sum(
          overlap_area_km2,
          na.rm = TRUE
        )
    ),
    by = ID
  ]

  base <- merge(
    base,
    total_area,
    by = "ID",
    all.x = TRUE,
    sort = FALSE
  )

  base[
    is.na(
      local_total_extracted_area_km2
    ),
    local_total_extracted_area_km2 :=
      0
  ]

  for (v in variable_names) {

    numerator_col <- paste0(
      "local_",
      v,
      "_numerator"
    )

    area_col <- paste0(
      "local_",
      v,
      "_valid_area_km2"
    )

    mean_col <- paste0(
      "local_",
      v
    )

    coverage_col <- paste0(
      "local_",
      v,
      "_coverage_ratio"
    )

    variable_summary <- extracted[
      is.finite(
        get(v)
      ) &
        is.finite(
          overlap_area_km2
        ) &
        overlap_area_km2 > 0,
      .(
        numerator =
          sum(
            get(v) *
              overlap_area_km2,
            na.rm = TRUE
          ),
        valid_area =
          sum(
            overlap_area_km2,
            na.rm = TRUE
          )
      ),
      by = ID
    ]

    setnames(
      variable_summary,
      c(
        "numerator",
        "valid_area"
      ),
      c(
        numerator_col,
        area_col
      )
    )

    base <- merge(
      base,
      variable_summary,
      by = "ID",
      all.x = TRUE,
      sort = FALSE
    )

    set(
      base,
      which(
        is.na(
          base[[numerator_col]]
        )
      ),
      numerator_col,
      0
    )

    set(
      base,
      which(
        is.na(
          base[[area_col]]
        )
      ),
      area_col,
      0
    )

    base[
      ,
      (mean_col) :=
        fifelse(
          get(area_col) > 0,
          get(numerator_col) /
            get(area_col),
          NA_real_
        )
    ]

    base[
      ,
      (coverage_col) :=
        fifelse(
          local_total_extracted_area_km2 >
            0,
          get(area_col) /
            local_total_extracted_area_km2,
          NA_real_
        )
    ]
  }

  base
}

local_results <- vector(
  "list",
  length(chunk_ids)
)

for (
  chunk_number in
    seq_along(chunk_ids)
) {

  message(
    "Region ",
    region,
    ": chunk ",
    chunk_number,
    " of ",
    length(chunk_ids)
  )

  local_results[[chunk_number]] <-
    summarise_chunk(
      chunk_ids[[chunk_number]]
    )
}

local_table <- rbindlist(
  local_results,
  use.names = TRUE,
  fill = TRUE
)

setorder(
  local_table,
  basin_row_id
)

basin_attributes <- as.data.frame(
  st_drop_geometry(
    basins
  )
)

basin_table <- merge(
  basin_attributes,
  as.data.frame(
    local_table
  ),
  by = "basin_row_id",
  all.x = TRUE,
  sort = FALSE
)

basin_table <- basin_table[
  order(
    basin_table$basin_row_id
  ),
  ,
  drop = FALSE
]

basin_table$region <- region

basin_table$hybas_key <- sprintf(
  "%.0f",
  as.numeric(
    basin_table$HYBAS_ID
  )
)

id_keys <- sprintf(
  "%.0f",
  as.numeric(
    basin_table$HYBAS_ID
  )
)

next_keys <- sprintf(
  "%.0f",
  as.numeric(
    basin_table$NEXT_DOWN
  )
)

nonterminal <- (
  is.finite(
    basin_table$NEXT_DOWN
  ) &
    basin_table$NEXT_DOWN != 0
)

downstream_index <- match(
  next_keys,
  id_keys
)

downstream_index[
  !nonterminal
] <- NA_integer_

n_external_downstream_links <- sum(
  nonterminal &
    is.na(
      downstream_index
    )
)

if (
  n_external_downstream_links >
    0
) {
  stop(
    "External downstream links found: ",
    n_external_downstream_links
  )
}

accumulation_columns <- c(
  "local_total_extracted_area_km2"
)

for (v in variable_names) {

  accumulation_columns <- c(
    accumulation_columns,
    paste0(
      "local_",
      v,
      "_numerator"
    ),
    paste0(
      "local_",
      v,
      "_valid_area_km2"
    )
  )
}

local_matrix <- as.matrix(
  basin_table[
    ,
    accumulation_columns,
    drop = FALSE
  ]
)

local_matrix[
  !is.finite(
    local_matrix
  )
] <- 0

storage.mode(
  local_matrix
) <- "double"

accumulate_downstream <- function(
    local_values,
    downstream
) {

  n <- nrow(
    local_values
  )

  n_immediate_upstream <- tabulate(
    downstream[
      !is.na(
        downstream
      )
    ],
    nbins = n
  )

  queue <- which(
    n_immediate_upstream == 0
  )

  accumulated <- local_values

  queue_position <- 1L
  n_processed <- 0L

  while (
    queue_position <=
      length(queue)
  ) {

    current <- queue[
      queue_position
    ]

    queue_position <-
      queue_position + 1L

    n_processed <-
      n_processed + 1L

    downstream_basin <-
      downstream[
        current
      ]

    if (
      !is.na(
        downstream_basin
      )
    ) {

      accumulated[
        downstream_basin,
      ] <-
        accumulated[
          downstream_basin,
        ] +
        accumulated[
          current,
        ]

      n_immediate_upstream[
        downstream_basin
      ] <-
        n_immediate_upstream[
          downstream_basin
        ] - 1L

      if (
        n_immediate_upstream[
          downstream_basin
        ] == 0L
      ) {
        queue <- c(
          queue,
          downstream_basin
        )
      }
    }
  }

  if (
    n_processed != n
  ) {
    stop(
      "Network accumulation processed ",
      n_processed,
      " of ",
      n,
      " basins. Possible cycle."
    )
  }

  accumulated
}

message(
  "Accumulating climate and terrain ",
  "variables downstream."
)

upstream_matrix <- accumulate_downstream(
  local_matrix,
  downstream_index
)

colnames(
  upstream_matrix
) <- accumulation_columns

basin_table$up_total_extracted_area_km2 <-
  upstream_matrix[
    ,
    "local_total_extracted_area_km2"
  ]

for (v in variable_names) {

  local_numerator_col <- paste0(
    "local_",
    v,
    "_numerator"
  )

  local_area_col <- paste0(
    "local_",
    v,
    "_valid_area_km2"
  )

  up_mean_col <- paste0(
    "up_",
    v
  )

  up_area_col <- paste0(
    "up_",
    v,
    "_valid_area_km2"
  )

  up_coverage_col <- paste0(
    "up_",
    v,
    "_coverage_ratio"
  )

  upstream_numerator <-
    upstream_matrix[
      ,
      local_numerator_col
    ]

  upstream_valid_area <-
    upstream_matrix[
      ,
      local_area_col
    ]

  basin_table[[up_area_col]] <-
    upstream_valid_area

  basin_table[[up_mean_col]] <-
    ifelse(
      upstream_valid_area > 0,
      upstream_numerator /
        upstream_valid_area,
      NA_real_
    )

  basin_table[[up_coverage_col]] <-
    ifelse(
      basin_table$
        up_total_extracted_area_km2 >
        0,
      upstream_valid_area /
        basin_table$
          up_total_extracted_area_km2,
      NA_real_
    )
}

numerator_columns <- grep(
  "_numerator$",
  names(basin_table),
  value = TRUE
)

output_table <- basin_table %>%
  select(
    -all_of(
      numerator_columns
    )
  )

output_rds <- file.path(
  out_dir,
  paste0(
    "l6_climate_terrain_local_upstream_",
    region,
    ".rds"
  )
)

output_csv <- file.path(
  out_dir,
  paste0(
    "l6_climate_terrain_local_upstream_",
    region,
    ".csv"
  )
)

saveRDS(
  output_table,
  output_rds
)

write_csv(
  output_table,
  output_csv
)

variable_qc <- bind_rows(
  lapply(
    variable_names,
    function(v) {

      local_mean_col <- paste0(
        "local_",
        v
      )

      local_area_col <- paste0(
        "local_",
        v,
        "_valid_area_km2"
      )

      local_coverage_col <- paste0(
        "local_",
        v,
        "_coverage_ratio"
      )

      up_mean_col <- paste0(
        "up_",
        v
      )

      up_area_col <- paste0(
        "up_",
        v,
        "_valid_area_km2"
      )

      up_coverage_col <- paste0(
        "up_",
        v,
        "_coverage_ratio"
      )

      tibble(
        region = region,
        variable = v,
        n_l6_basins =
          nrow(output_table),
        n_local_covered =
          sum(
            output_table[[local_area_col]] > 0,
            na.rm = TRUE
          ),
        n_upstream_covered =
          sum(
            output_table[[up_area_col]] > 0,
            na.rm = TRUE
          ),
        median_local_coverage_ratio =
          median(
            output_table[[local_coverage_col]],
            na.rm = TRUE
          ),
        p05_local_coverage_ratio =
          quantile(
            output_table[[local_coverage_col]],
            0.05,
            na.rm = TRUE
          ),
        median_upstream_coverage_ratio =
          median(
            output_table[[up_coverage_col]],
            na.rm = TRUE
          ),
        p05_upstream_coverage_ratio =
          quantile(
            output_table[[up_coverage_col]],
            0.05,
            na.rm = TRUE
          ),
        local_min =
          min(
            output_table[[local_mean_col]],
            na.rm = TRUE
          ),
        local_max =
          max(
            output_table[[local_mean_col]],
            na.rm = TRUE
          ),
        upstream_min =
          min(
            output_table[[up_mean_col]],
            na.rm = TRUE
          ),
        upstream_max =
          max(
            output_table[[up_mean_col]],
            na.rm = TRUE
          )
      )
    }
  )
)

region_qc <- tibble(
  region = region,
  n_l6_basins =
    nrow(output_table),
  n_internal_downstream_links =
    sum(nonterminal),
  n_external_downstream_links =
    n_external_downstream_links,
  n_terminal_basins =
    sum(!nonterminal),
  median_extracted_to_sub_area_ratio =
    median(
      output_table$
        local_total_extracted_area_km2 /
        output_table$SUB_AREA,
      na.rm = TRUE
    )
)

write_csv(
  variable_qc,
  file.path(
    qc_dir,
    paste0(
      "l6_climate_terrain_variable_qc_",
      region,
      ".csv"
    )
  )
)

write_csv(
  region_qc,
  file.path(
    qc_dir,
    paste0(
      "l6_climate_terrain_region_qc_",
      region,
      ".csv"
    )
  )
)

cat("\nRegion QC:\n")
print(
  region_qc,
  width = Inf
)

cat("\nVariable QC:\n")
print(
  variable_qc,
  n = Inf,
  width = Inf
)

cat(
  "\nL6 climate and terrain processing finished: ",
  region,
  "\n"
)
