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

model_path <- "data/processed/model_table.rds"

age_path <- paste0(
  "outputs/nrcan_age_hydrobasins_l6/",
  "global_upstream/",
  "l6_nrcan_age_local_upstream_global.rds"
)

manifest_path <- paste0(
  "outputs/nrcan_age_hydrobasins_l6/",
  "global_upstream/",
  "global_age_predictor_manifest.csv"
)

output_dir <- "outputs/model_age_join"

output_model_path <- paste0(
  "data/processed/",
  "model_table_age_test.rds"
)

nearest_distance_limit_km <- 25


region_catalogue <- tribble(
  ~region, ~directory,    ~path_file,
  "af",    "af_pilot",    "hybas_af_shapefile_path.txt",
  "ar",    "ar_pilot",    "hybas_ar_shapefile_path.txt",
  "as",    "asia_pilot",  "hybas_as_shapefile_path.txt",
  "au",    "au_pilot",    "hybas_au_shapefile_path.txt",
  "eu",    "eu_pilot",    "hybas_eu_shapefile_path.txt",
  "gr",    "gr_pilot",    "hybas_gr_shapefile_path.txt",
  "na",    "na_pilot",    "hybas_na_shapefile_path.txt",
  "sa",    "sa_pilot",    "hybas_sa_shapefile_path.txt",
  "si",    "si_pilot",    "hybas_si_shapefile_path.txt"
)


required_files <- c(
  model_path,
  age_path,
  manifest_path
)

missing_files <- required_files[
  !file.exists(required_files)
]

if (length(missing_files) > 0L) {
  stop(
    "Missing required files: ",
    paste(
      missing_files,
      collapse = ", "
    )
  )
}


dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)


cat("Reading formal model table...\n")

model <- readRDS(
  model_path
)

if (inherits(model, "sf")) {
  model <- st_drop_geometry(model)
}

model <- as_tibble(
  model
)


required_model_columns <- c(
  "row_id",
  "longitude",
  "latitude",
  "sr87_sr86"
)

missing_model_columns <- setdiff(
  required_model_columns,
  names(model)
)

if (length(missing_model_columns) > 0L) {
  stop(
    "Model table lacks required columns: ",
    paste(
      missing_model_columns,
      collapse = ", "
    )
  )
}


if (
  anyDuplicated(model$row_id) > 0L ||
  any(is.na(model$row_id))
) {
  stop(
    "Missing or duplicated row_id in model table."
  )
}


model$.model_row_index <- seq_len(
  nrow(model)
)


coordinate_valid <- (
  is.finite(
    as.numeric(model$longitude)
  ) &
    is.finite(
      as.numeric(model$latitude)
    ) &
    as.numeric(model$longitude) >= -180 &
    as.numeric(model$longitude) <= 180 &
    as.numeric(model$latitude) >= -90 &
    as.numeric(model$latitude) <= 90
)

if (!all(coordinate_valid)) {
  stop(
    "Invalid sample coordinates: ",
    sum(!coordinate_valid)
  )
}


cat("Reading nine HydroBASINS L6 geometry files...\n")

basin_list <- vector(
  "list",
  nrow(region_catalogue)
)


for (
  region_index in seq_len(
    nrow(region_catalogue)
  )
) {

  region_code <- region_catalogue$region[
    region_index
  ]

  path_file <- file.path(
    "outputs/nrcan_age_hydrobasins_l6",
    region_catalogue$directory[
      region_index
    ],
    region_catalogue$path_file[
      region_index
    ]
  )

  if (!file.exists(path_file)) {
    stop(
      "Missing shapefile path record: ",
      path_file
    )
  }

  shapefile_path <- trimws(
    readLines(
      path_file,
      warn = FALSE
    )[1]
  )

  if (!file.exists(shapefile_path)) {
    stop(
      "HydroBASINS shapefile does not exist: ",
      shapefile_path
    )
  }

  region_basins <- st_read(
    shapefile_path,
    quiet = TRUE
  )

  if (!"HYBAS_ID" %in% names(region_basins)) {
    stop(
      "HYBAS_ID absent from ",
      shapefile_path
    )
  }

  region_basins <- region_basins %>%
    select(
      HYBAS_ID
    ) %>%
    mutate(
      basin_region = region_code
    )

  if (st_crs(region_basins)$epsg != 4326L) {
    region_basins <- st_transform(
      region_basins,
      4326
    )
  }

  region_basins <- st_make_valid(
    region_basins
  )

  basin_list[[
    region_index
  ]] <- region_basins

  cat(
    region_code,
    ": ",
    nrow(region_basins),
    " basins\n",
    sep = ""
  )
}


basins <- do.call(
  rbind,
  basin_list
)


if (nrow(basins) != 16397L) {
  stop(
    "Expected 16397 global basins; found ",
    nrow(basins)
  )
}


if (anyDuplicated(basins$HYBAS_ID) > 0L) {
  stop(
    "Duplicated HYBAS_ID in combined geometry."
  )
}


cat("Creating sample point geometry...\n")

points <- st_as_sf(
  model,
  coords = c(
    "longitude",
    "latitude"
  ),
  crs = 4326,
  remove = FALSE
)


cat("Calculating basin areas for deterministic tie-breaking...\n")

basins_equal <- st_transform(
  basins,
  6933
)

basin_area_km2 <- as.numeric(
  st_area(basins_equal)
) / 1e6


choose_smallest_basin <- function(
  candidate_indices
) {

  if (length(candidate_indices) == 0L) {
    return(NA_integer_)
  }

  candidate_indices[
    which.min(
      basin_area_km2[
        candidate_indices
      ]
    )
  ]
}


assigned_basin_index <- rep(
  NA_integer_,
  nrow(points)
)

assignment_method <- rep(
  "unmatched",
  nrow(points)
)

nearest_distance_km <- rep(
  NA_real_,
  nrow(points)
)


cat("Assigning samples using point-within-polygon...\n")

within_candidates <- st_within(
  points,
  basins,
  sparse = TRUE
)

for (sample_index in seq_len(nrow(points))) {

  candidates <- within_candidates[[
    sample_index
  ]]

  if (length(candidates) == 1L) {

    assigned_basin_index[
      sample_index
    ] <- candidates

    assignment_method[
      sample_index
    ] <- "within"

  } else if (length(candidates) > 1L) {

    assigned_basin_index[
      sample_index
    ] <- choose_smallest_basin(
      candidates
    )

    assignment_method[
      sample_index
    ] <- "within_multiple_smallest"
  }
}


cat("Resolving boundary points using st_intersects...\n")

unmatched_index <- which(
  is.na(assigned_basin_index)
)

if (length(unmatched_index) > 0L) {

  intersection_candidates <- st_intersects(
    points[
      unmatched_index,
    ],
    basins,
    sparse = TRUE
  )

  for (
    local_index in seq_along(
      unmatched_index
    )
  ) {

    sample_index <- unmatched_index[
      local_index
    ]

    candidates <- intersection_candidates[[
      local_index
    ]]

    if (length(candidates) == 1L) {

      assigned_basin_index[
        sample_index
      ] <- candidates

      assignment_method[
        sample_index
      ] <- "boundary_intersects"

    } else if (length(candidates) > 1L) {

      assigned_basin_index[
        sample_index
      ] <- choose_smallest_basin(
        candidates
      )

      assignment_method[
        sample_index
      ] <- "boundary_multiple_smallest"
    }
  }
}


cat("Applying limited nearest-basin fallback...\n")

still_unmatched <- which(
  is.na(assigned_basin_index)
)

if (length(still_unmatched) > 0L) {

  unmatched_points_equal <- st_transform(
    points[
      still_unmatched,
    ],
    6933
  )

  nearest_index <- st_nearest_feature(
    unmatched_points_equal,
    basins_equal
  )

  nearest_distance <- as.numeric(
    st_distance(
      unmatched_points_equal,
      basins_equal[
        nearest_index,
      ],
      by_element = TRUE
    )
  ) / 1000

  accepted <- (
    is.finite(nearest_distance) &
      nearest_distance <=
        nearest_distance_limit_km
  )

  accepted_sample_indices <- still_unmatched[
    accepted
  ]

  assigned_basin_index[
    accepted_sample_indices
  ] <- nearest_index[
    accepted
  ]

  assignment_method[
    accepted_sample_indices
  ] <- "nearest_within_25km"

  nearest_distance_km[
    accepted_sample_indices
  ] <- nearest_distance[
    accepted
  ]

  nearest_distance_km[
    still_unmatched[
      !accepted
    ]
  ] <- nearest_distance[
    !accepted
  ]
}


assignment <- tibble(
  .model_row_index =
    model$.model_row_index,

  row_id =
    as.character(model$row_id),

  HYBAS_ID = ifelse(
    is.na(assigned_basin_index),
    NA_real_,
    basins$HYBAS_ID[
      assigned_basin_index
    ]
  ),

  basin_region = ifelse(
    is.na(assigned_basin_index),
    NA_character_,
    basins$basin_region[
      assigned_basin_index
    ]
  ),

  basin_assignment_method =
    assignment_method,

  nearest_basin_distance_km =
    nearest_distance_km
)


write_csv(
  assignment,
  file.path(
    output_dir,
    "sample_hydrobasins_l6_assignment.csv"
  )
)


cat("Reading global age predictor table...\n")

age <- readRDS(
  age_path
)

if (inherits(age, "sf")) {
  age <- st_drop_geometry(age)
}

age <- as_tibble(
  age
)


manifest <- read_csv(
  manifest_path,
  show_col_types = FALSE
)


age_predictors <- unique(
  manifest$predictor
)

missing_age_predictors <- setdiff(
  age_predictors,
  names(age)
)

if (length(missing_age_predictors) > 0L) {
  stop(
    "Manifest predictors missing from age table: ",
    paste(
      missing_age_predictors,
      collapse = ", "
    )
  )
}


age_join_table <- age %>%
  select(
    HYBAS_ID,
    any_of(
      c(
        age_predictors,
        "up_geo_age_quality_tier"
      )
    )
  )


if (anyDuplicated(age_join_table$HYBAS_ID) > 0L) {
  stop(
    "Duplicated HYBAS_ID in age join table."
  )
}


cat("Joining HydroBASINS assignment and age predictors...\n")

model_age <- model %>%
  left_join(
    assignment %>%
      select(
        -row_id
      ),
    by = ".model_row_index"
  ) %>%
  left_join(
    age_join_table,
    by = "HYBAS_ID"
  ) %>%
  arrange(
    .model_row_index
  )


if (nrow(model_age) != nrow(model)) {
  stop(
    "Model row count changed during join."
  )
}


if (
  any(
    model_age$row_id != model$row_id
  )
) {
  stop(
    "Model row order changed during join."
  )
}


model_age <- model_age %>%
  select(
    -.model_row_index
  )


saveRDS(
  model_age,
  output_model_path
)


write_csv(
  model_age,
  file.path(
    output_dir,
    "model_table_age_test.csv"
  )
)


cat("Writing unmatched and low-coverage diagnostics...\n")

unmatched <- model_age %>%
  filter(
    is.na(HYBAS_ID)
  ) %>%
  select(
    any_of(
      c(
        "row_id",
        "sr87_sr86",
        "longitude",
        "latitude",
        "short_references",
        "original_sample_id",
        "sample_type",
        "water_provenance",
        "basin_assignment_method",
        "nearest_basin_distance_km"
      )
    )
  )

write_csv(
  unmatched,
  file.path(
    output_dir,
    "unmatched_model_samples.csv"
  )
)


low_age_coverage <- model_age %>%
  filter(
    !is.na(HYBAS_ID),
    (
      !is.finite(
        up_geo_age_resolved_coverage
      ) |
        up_geo_age_resolved_coverage < 0.80
    )
  ) %>%
  select(
    any_of(
      c(
        "row_id",
        "sr87_sr86",
        "longitude",
        "latitude",
        "HYBAS_ID",
        "basin_region",
        "basin_assignment_method",
        "local_geo_age_resolved_coverage",
        "up_geo_age_resolved_coverage",
        "short_references",
        "original_sample_id"
      )
    )
  )

write_csv(
  low_age_coverage,
  file.path(
    output_dir,
    "low_age_coverage_model_samples.csv"
  )
)


cat("Auditing extreme observed Sr values...\n")

metadata_pattern <- paste0(
  "row_id|sr87|latitude|longitude|",
  "reference|sample|site|location|",
  "country|water|provenance|HYBAS|",
  "basin_region|assignment"
)

extreme_columns <- names(model_age)[
  grepl(
    metadata_pattern,
    names(model_age),
    ignore.case = TRUE
  )
]

extreme_rows <- model_age %>%
  filter(
    sr87_sr86 >= 0.80
  ) %>%
  select(
    all_of(
      extreme_columns
    )
  ) %>%
  arrange(
    desc(sr87_sr86)
  )

write_csv(
  extreme_rows,
  file.path(
    output_dir,
    "observed_sr_ge_0p80_audit.csv"
  )
)


tail_summary <- tibble(
  metric = c(
    "model_row_count",
    "observed_ge_0p720_count",
    "observed_ge_0p722_count",
    "observed_ge_0p750_count",
    "observed_ge_0p800_count",
    "observed_ge_0p900_count",
    "observed_maximum"
  ),

  value = c(
    nrow(model_age),

    sum(
      model_age$sr87_sr86 >= 0.720,
      na.rm = TRUE
    ),

    sum(
      model_age$sr87_sr86 >= 0.722,
      na.rm = TRUE
    ),

    sum(
      model_age$sr87_sr86 >= 0.750,
      na.rm = TRUE
    ),

    sum(
      model_age$sr87_sr86 >= 0.800,
      na.rm = TRUE
    ),

    sum(
      model_age$sr87_sr86 >= 0.900,
      na.rm = TRUE
    ),

    max(
      model_age$sr87_sr86,
      na.rm = TRUE
    )
  )
)

write_csv(
  tail_summary,
  file.path(
    output_dir,
    "observed_sr_tail_summary.csv"
  )
)


join_qc <- tibble(
  metric = c(
    "model_row_count",
    "assigned_HYBAS_ID_count",
    "unmatched_sample_count",
    "within_assignment_count",
    "within_multiple_assignment_count",
    "boundary_assignment_count",
    "boundary_multiple_assignment_count",
    "nearest_within_25km_count",
    "age_mean_available_count",
    "upstream_age_mean_available_count",
    "upstream_age_coverage_ge_0p95_count",
    "upstream_age_coverage_ge_0p80_count",
    "upstream_age_coverage_lt_0p80_count",
    "age_predictor_count"
  ),

  value = c(
    nrow(model_age),

    sum(
      !is.na(model_age$HYBAS_ID)
    ),

    sum(
      is.na(model_age$HYBAS_ID)
    ),

    sum(
      model_age$basin_assignment_method ==
        "within"
    ),

    sum(
      model_age$basin_assignment_method ==
        "within_multiple_smallest"
    ),

    sum(
      model_age$basin_assignment_method ==
        "boundary_intersects"
    ),

    sum(
      model_age$basin_assignment_method ==
        "boundary_multiple_smallest"
    ),

    sum(
      model_age$basin_assignment_method ==
        "nearest_within_25km"
    ),

    sum(
      is.finite(
        model_age$local_geo_age_mean_ma
      )
    ),

    sum(
      is.finite(
        model_age$up_geo_age_mean_ma
      )
    ),

    sum(
      model_age$up_geo_age_resolved_coverage >=
        0.95,
      na.rm = TRUE
    ),

    sum(
      model_age$up_geo_age_resolved_coverage >=
        0.80,
      na.rm = TRUE
    ),

    sum(
      !is.na(
        model_age$up_geo_age_resolved_coverage
      ) &
        model_age$up_geo_age_resolved_coverage <
          0.80
    ),

    length(age_predictors)
  )
)


write_csv(
  join_qc,
  file.path(
    output_dir,
    "sample_age_join_qc.csv"
  )
)


cat("\n========================================\n")
cat("MODEL–AGE SPATIAL JOIN COMPLETE\n")
cat("========================================\n")

cat("\nJoin QC:\n")

print(
  join_qc,
  n = Inf,
  width = Inf
)

cat("\nObserved Sr tail summary:\n")

print(
  tail_summary,
  n = Inf,
  width = Inf
)

cat("\nObserved Sr >= 0.80 records:\n")

if (nrow(extreme_rows) == 0L) {

  cat("None\n")

} else {

  print(
    extreme_rows,
    n = Inf,
    width = Inf
  )
}

cat("\nOutput model table:\n")
cat(output_model_path, "\n")
