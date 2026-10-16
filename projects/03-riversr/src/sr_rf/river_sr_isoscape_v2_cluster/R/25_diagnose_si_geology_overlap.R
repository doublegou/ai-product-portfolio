#!/usr/bin/env Rscript

options(
  stringsAsFactors = FALSE,
  warn = 1
)

suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(readr)
  library(tibble)
})

output_dir <- paste0(
  "outputs/nrcan_age_hydrobasins_l6/",
  "repair_checks"
)

dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

basin_path_file <- paste0(
  "outputs/nrcan_age_hydrobasins_l6/",
  "si_pilot/hybas_si_shapefile_path.txt"
)

age_gpkg <- paste0(
  "outputs/nrcan_of5529/final_age_crosswalk/",
  "roxworld_age_wgs84.gpkg"
)

target_ids <- c(
  3060451380,
  3060451260
)

if (!file.exists(basin_path_file)) {
  stop(
    "Missing SI shapefile path file: ",
    basin_path_file
  )
}

if (!file.exists(age_gpkg)) {
  stop(
    "Missing geology GeoPackage: ",
    age_gpkg
  )
}

basin_shp <- trimws(
  readLines(
    basin_path_file,
    warn = FALSE
  )[1]
)

cat("Reading two SI diagnostic basins...\n")

basins <- st_read(
  basin_shp,
  quiet = TRUE
) %>%
  filter(
    HYBAS_ID %in% target_ids
  ) %>%
  select(
    HYBAS_ID,
    SUB_AREA,
    UP_AREA
  )

if (nrow(basins) != 2L) {
  stop(
    "Expected two SI basins; found ",
    nrow(basins)
  )
}

cat("Reading NRCan age polygons...\n")

age <- st_read(
  age_gpkg,
  layer = "roxworld_age",
  quiet = TRUE
)

required_fields <- c(
  "RUNO",
  "resolved",
  "weighted_mean_midpoint_ma",
  "weighted_sd_midpoint_ma"
)

missing_fields <- setdiff(
  required_fields,
  names(age)
)

if (length(missing_fields) > 0L) {
  stop(
    "Missing age fields: ",
    paste(
      missing_fields,
      collapse = ", "
    )
  )
}

if (st_crs(age)$epsg != 4326L) {
  age <- st_transform(
    age,
    4326
  )
}

if (st_crs(basins)$epsg != 4326L) {
  basins <- st_transform(
    basins,
    4326
  )
}

age_si <- st_filter(
  age,
  basins,
  .predicate = st_intersects
)

cat(
  "Candidate geology polygons: ",
  nrow(age_si),
  "\n",
  sep = ""
)

basins_equal <- basins %>%
  st_make_valid() %>%
  st_transform(6933)

age_equal <- age_si %>%
  st_make_valid() %>%
  st_transform(6933)

basins_equal <- suppressWarnings(
  st_buffer(
    basins_equal,
    0
  )
)

age_equal <- suppressWarnings(
  st_buffer(
    age_equal,
    0
  )
)

age_equal$source_polygon_id <- seq_len(
  nrow(age_equal)
)

cat("Creating basin-geology intersection pieces...\n")

pieces <- suppressWarnings(
  st_intersection(
    basins_equal %>%
      select(
        HYBAS_ID
      ),
    age_equal %>%
      select(
        source_polygon_id,
        RUNO,
        resolved,
        weighted_mean_midpoint_ma,
        weighted_sd_midpoint_ma
      )
  )
)

pieces$piece_area_km2 <- as.numeric(
  st_area(pieces)
) / 1e6

pieces <- pieces %>%
  filter(
    is.finite(piece_area_km2),
    piece_area_km2 > 0
  )

piece_table <- pieces %>%
  st_drop_geometry() %>%
  arrange(
    HYBAS_ID,
    desc(piece_area_km2)
  )

write_csv(
  piece_table,
  file.path(
    output_dir,
    "si_target_basin_geology_pieces.csv"
  )
)


cat("Calculating pairwise overlap among geology pieces...\n")

pair_results <- list()
result_index <- 0L

for (basin_id in target_ids) {

  basin_pieces <- pieces[
    pieces$HYBAS_ID == basin_id,
  ]

  n_piece <- nrow(
    basin_pieces
  )

  if (n_piece < 2L) {
    next
  }

  combinations <- combn(
    seq_len(n_piece),
    2
  )

  for (pair_index in seq_len(ncol(combinations))) {

    first_index <- combinations[
      1,
      pair_index
    ]

    second_index <- combinations[
      2,
      pair_index
    ]

    first_piece <- basin_pieces[
      first_index,
    ]

    second_piece <- basin_pieces[
      second_index,
    ]

    overlap <- suppressWarnings(
      st_intersection(
        st_geometry(first_piece),
        st_geometry(second_piece)
      )
    )

    if (length(overlap) == 0L) {
      next
    }

    overlap_area_km2 <- sum(
      as.numeric(
        st_area(overlap)
      ) / 1e6,
      na.rm = TRUE
    )

    if (
      !is.finite(overlap_area_km2) ||
      overlap_area_km2 <= 1e-6
    ) {
      next
    }

    result_index <- result_index + 1L

    pair_results[[result_index]] <- tibble(
      HYBAS_ID = basin_id,

      polygon_id_1 =
        first_piece$source_polygon_id,

      RUNO_1 =
        first_piece$RUNO,

      resolved_1 =
        first_piece$resolved,

      age_mean_1 =
        first_piece$weighted_mean_midpoint_ma,

      polygon_id_2 =
        second_piece$source_polygon_id,

      RUNO_2 =
        second_piece$RUNO,

      resolved_2 =
        second_piece$resolved,

      age_mean_2 =
        second_piece$weighted_mean_midpoint_ma,

      overlap_area_km2 =
        overlap_area_km2
    )
  }
}

if (length(pair_results) == 0L) {

  overlap_table <- tibble(
    HYBAS_ID = numeric(),
    polygon_id_1 = integer(),
    RUNO_1 = numeric(),
    resolved_1 = logical(),
    age_mean_1 = numeric(),
    polygon_id_2 = integer(),
    RUNO_2 = numeric(),
    resolved_2 = logical(),
    age_mean_2 = numeric(),
    overlap_area_km2 = numeric()
  )

} else {

  overlap_table <- bind_rows(
    pair_results
  ) %>%
    arrange(
      HYBAS_ID,
      desc(overlap_area_km2)
    )
}

write_csv(
  overlap_table,
  file.path(
    output_dir,
    "si_target_basin_pairwise_geology_overlap.csv"
  )
)


basin_summary <- basins_equal %>%
  mutate(
    basin_geometry_area_km2 =
      as.numeric(
        st_area(geometry)
      ) / 1e6
  ) %>%
  st_drop_geometry() %>%
  left_join(
    piece_table %>%
      group_by(HYBAS_ID) %>%
      summarise(
        sum_piece_area_km2 = sum(
          piece_area_km2
        ),
        n_intersection_pieces = n(),
        .groups = "drop"
      ),
    by = "HYBAS_ID"
  ) %>%
  left_join(
    overlap_table %>%
      group_by(HYBAS_ID) %>%
      summarise(
        sum_pairwise_overlap_km2 = sum(
          overlap_area_km2
        ),
        largest_pairwise_overlap_km2 = max(
          overlap_area_km2
        ),
        n_overlapping_pairs = n(),
        .groups = "drop"
      ),
    by = "HYBAS_ID"
  ) %>%
  mutate(
    across(
      c(
        sum_pairwise_overlap_km2,
        largest_pairwise_overlap_km2,
        n_overlapping_pairs
      ),
      ~ coalesce(.x, 0)
    ),

    excess_piece_area_km2 =
      sum_piece_area_km2 -
        basin_geometry_area_km2,

    piece_area_to_basin_ratio =
      sum_piece_area_km2 /
        basin_geometry_area_km2
  )

write_csv(
  basin_summary,
  file.path(
    output_dir,
    "si_target_basin_overlap_summary.csv"
  )
)


cat("\n===== SI TARGET BASIN SUMMARY =====\n")

print(
  basin_summary,
  n = Inf,
  width = Inf
)

cat("\n===== PAIRWISE GEOLOGY OVERLAPS =====\n")

if (nrow(overlap_table) == 0L) {

  cat("No positive-area pairwise overlaps detected.\n")

} else {

  print(
    overlap_table,
    n = Inf,
    width = Inf
  )
}

cat(
  "\nOutputs written to: ",
  output_dir,
  "\n",
  sep = ""
)
