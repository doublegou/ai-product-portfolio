root <- normalizePath(
  getwd(),
  mustWork = TRUE
)

legacy_global <- file.path(
  "/home",
  "zhangmeng",
  "projects",
  "sr_global",
  "data_processed",
  "global"
)

out_dir <- file.path(
  root,
  "outputs",
  "r58j_strict_deployment_join_audit"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

regions <- c(
  "af",
  "ar",
  "as",
  "au",
  "eu",
  "gr",
  "na",
  "sa",
  "si"
)

climate_variables <- c(
  "local_elevation_m",
  "up_elevation_m",
  "up_bio1_C",
  "up_bio4_C_sd",
  "up_bio12_mm",
  "up_bio15_cv",
  "up_ai_ratio",
  "up_et0_mm"
)

age_file <- file.path(
  root,
  "outputs",
  "nrcan_age_hydrobasins_l6",
  "global_upstream",
  "l6_nrcan_age_local_upstream_global.rds"
)

global_fallback_file <- file.path(
  legacy_global,
  "final_prediction",
  "global_l6_upstream_prediction_covariates.rds"
)

training_file <- file.path(
  root,
  "outputs",
  "r50b_feature_architecture",
  "integrated_model_table.rds"
)

read_largest_table <- function(path) {
  if (!file.exists(path)) {
    stop(
      "Required file not found: ",
      path
    )
  }

  object <- readRDS(path)

  if (is.data.frame(object)) {
    return(object)
  }

  if (!is.list(object)) {
    stop(
      "No data-frame payload in: ",
      path
    )
  }

  table_indices <- which(
    vapply(
      object,
      is.data.frame,
      logical(1)
    )
  )

  if (length(table_indices) == 0L) {
    stop(
      "No data-frame payload in: ",
      path
    )
  }

  table_rows <- vapply(
    object[table_indices],
    nrow,
    integer(1)
  )

  selected_index <- table_indices[
    which.max(table_rows)
  ]

  object[[selected_index]]
}

find_key_column <- function(table) {
  candidates <- c(
    "HYBAS_ID",
    "hybas_id",
    "HYBAS_KEY",
    "hybas_key"
  )

  matched <- candidates[
    candidates %in%
      names(table)
  ]

  if (length(matched) == 0L) {
    stop(
      "No HYBAS key found. Columns include: ",
      paste(
        head(
          names(table),
          30L
        ),
        collapse = ", "
      )
    )
  }

  matched[[1L]]
}

find_column <- function(table, candidates) {
  matched <- candidates[
    candidates %in%
      names(table)
  ]

  if (length(matched) == 0L) {
    return(NA_character_)
  }

  matched[[1L]]
}

normalise_key <- function(values) {
  output <- as.character(values)

  output[
    is.na(values)
  ] <- NA_character_

  output
}

is_finite_value <- function(values) {
  if (is.numeric(values)) {
    return(
      is.finite(values)
    )
  }

  !is.na(values)
}

safe_metrics <- function(observed, predicted) {
  keep <- is.finite(observed) &
    is.finite(predicted)

  if (!any(keep)) {
    return(
      c(
        n_complete = 0,
        rmse = NA_real_,
        mae = NA_real_,
        max_abs_difference = NA_real_,
        correlation = NA_real_
      )
    )
  }

  observed <- observed[keep]
  predicted <- predicted[keep]

  difference <- predicted -
    observed

  correlation <- NA_real_

  if (
    length(observed) >= 3L &&
    stats::sd(observed) > 0 &&
    stats::sd(predicted) > 0
  ) {
    correlation <- stats::cor(
      observed,
      predicted
    )
  }

  c(
    n_complete = length(observed),
    rmse = sqrt(
      mean(
        difference^2
      )
    ),
    mae = mean(
      abs(difference)
    ),
    max_abs_difference = max(
      abs(difference)
    ),
    correlation = correlation
  )
}

age_table <- read_largest_table(
  age_file
)

age_key_column <- find_key_column(
  age_table
)

age_keys <- normalise_key(
  age_table[[age_key_column]]
)

age_key_unique <-
  !anyDuplicated(
    age_keys[
      !is.na(age_keys)
    ]
  )

regional_audit_rows <- list()
missing_rows <- list()
climate_tables <- list()

regional_index <- 0L
missing_index <- 0L

for (region in regions) {
  climate_path <- file.path(
    legacy_global,
    "climate_terrain_l6_by_region",
    paste0(
      "l6_climate_terrain_local_upstream_",
      region,
      ".rds"
    )
  )

  geology_path <- file.path(
    legacy_global,
    "glim_l6_by_region",
    paste0(
      "l6_glim_local_upstream_",
      region,
      ".rds"
    )
  )

  soil_path <- file.path(
    legacy_global,
    "soil_l6_by_region",
    paste0(
      "l6_soil_local_upstream_",
      region,
      ".rds"
    )
  )

  reach_path <- file.path(
    legacy_global,
    "final_prediction",
    "river_predictions_by_region",
    paste0(
      "river_predictions_",
      region,
      ".rds"
    )
  )

  climate <- read_largest_table(
    climate_path
  )

  geology <- read_largest_table(
    geology_path
  )

  soil <- read_largest_table(
    soil_path
  )

  reach <- read_largest_table(
    reach_path
  )

  climate_key_column <- find_key_column(
    climate
  )

  geology_key_column <- find_key_column(
    geology
  )

  soil_key_column <- find_key_column(
    soil
  )

  reach_key_column <- find_key_column(
    reach
  )

  climate_keys <- normalise_key(
    climate[[climate_key_column]]
  )

  geology_keys <- normalise_key(
    geology[[geology_key_column]]
  )

  soil_keys <- normalise_key(
    soil[[soil_key_column]]
  )

  reach_keys <- normalise_key(
    reach[[reach_key_column]]
  )

  missing_climate_variables <- setdiff(
    climate_variables,
    names(climate)
  )

  if (length(missing_climate_variables) > 0L) {
    stop(
      "Climate variables absent in region ",
      region,
      ": ",
      paste(
        missing_climate_variables,
        collapse = ", "
      )
    )
  }

  regional_index <- regional_index + 1L

  regional_audit_rows[[regional_index]] <- data.frame(
    region = region,

    n_climate_l6 =
      nrow(climate),

    n_geology_l6 =
      nrow(geology),

    n_soil_l6 =
      nrow(soil),

    n_reaches =
      nrow(reach),

    climate_key_duplicates =
      sum(
        duplicated(
          climate_keys[
            !is.na(climate_keys)
          ]
        )
      ),

    geology_key_duplicates =
      sum(
        duplicated(
          geology_keys[
            !is.na(geology_keys)
          ]
        )
      ),

    soil_key_duplicates =
      sum(
        duplicated(
          soil_keys[
            !is.na(soil_keys)
          ]
        )
      ),

    climate_equals_geology_keys =
      setequal(
        climate_keys,
        geology_keys
      ),

    climate_equals_soil_keys =
      setequal(
        climate_keys,
        soil_keys
      ),

    climate_keys_in_age =
      all(
        climate_keys %in%
          age_keys
      ),

    reach_rows_unmatched_climate =
      sum(
        !reach_keys %in%
          climate_keys
      ),

    reach_rows_unmatched_geology =
      sum(
        !reach_keys %in%
          geology_keys
      ),

    reach_rows_unmatched_soil =
      sum(
        !reach_keys %in%
          soil_keys
      ),

    reach_rows_unmatched_age =
      sum(
        !reach_keys %in%
          age_keys
      ),

    stringsAsFactors = FALSE
  )

  climate_selected <- climate[
    ,
    c(
      climate_key_column,
      climate_variables
    ),
    drop = FALSE
  ]

  names(climate_selected)[
    names(climate_selected) ==
      climate_key_column
  ] <- "HYBAS_ID"

  climate_selected$HYBAS_ID <- normalise_key(
    climate_selected$HYBAS_ID
  )

  climate_selected$region <- region

  climate_tables[[region]] <- climate_selected

  for (variable in climate_variables) {
    finite <- is_finite_value(
      climate[[variable]]
    )

    missing_indices <- which(
      !finite
    )

    if (length(missing_indices) == 0L) {
      next
    }

    missing_index <- missing_index + 1L

    missing_rows[[missing_index]] <- data.frame(
      region = region,
      HYBAS_ID =
        climate_keys[
          missing_indices
        ],
      variable = variable,
      regional_value =
        as.character(
          climate[
            missing_indices,
            variable
          ]
        ),
      stringsAsFactors = FALSE
    )
  }

  rm(
    climate,
    geology,
    soil,
    reach
  )

  invisible(gc())
}

regional_audit <- do.call(
  rbind,
  regional_audit_rows
)

climate_all <- do.call(
  rbind,
  climate_tables
)

rownames(climate_all) <- NULL

if (length(missing_rows) > 0L) {
  climate_missing_records <- do.call(
    rbind,
    missing_rows
  )
} else {
  climate_missing_records <- data.frame(
    region = character(),
    HYBAS_ID = character(),
    variable = character(),
    regional_value = character(),
    stringsAsFactors = FALSE
  )
}

climate_union_keys <- climate_all$HYBAS_ID

climate_union_duplicate_count <- sum(
  duplicated(
    climate_union_keys[
      !is.na(climate_union_keys)
    ]
  )
)

global_fallback <- read_largest_table(
  global_fallback_file
)

global_key_column <- find_key_column(
  global_fallback
)

global_keys <- normalise_key(
  global_fallback[[global_key_column]]
)

global_match <- match(
  climate_all$HYBAS_ID,
  global_keys
)

common_fallback_variables <- intersect(
  climate_variables,
  names(global_fallback)
)

fallback_rows <- list()
fallback_index <- 0L

for (variable in climate_variables) {
  regional_values <- climate_all[[variable]]
  regional_finite <- is_finite_value(
    regional_values
  )

  variable_in_global <-
    variable %in%
    names(global_fallback)

  if (variable_in_global) {
    global_values <- global_fallback[
      global_match,
      variable
    ]

    global_finite <- is_finite_value(
      global_values
    )

    numeric_comparison <-
      is.numeric(regional_values) &&
      is.numeric(global_values)

    if (numeric_comparison) {
      metrics <- safe_metrics(
        regional_values,
        global_values
      )
    } else {
      metrics <- c(
        n_complete = sum(
          regional_finite &
            global_finite
        ),
        rmse = NA_real_,
        mae = NA_real_,
        max_abs_difference = NA_real_,
        correlation = NA_real_
      )
    }

    missing_recoverable <- sum(
      !regional_finite &
        global_finite
    )
  } else {
    metrics <- c(
      n_complete = 0,
      rmse = NA_real_,
      mae = NA_real_,
      max_abs_difference = NA_real_,
      correlation = NA_real_
    )

    missing_recoverable <- 0L
  }

  fallback_index <- fallback_index + 1L

  fallback_rows[[fallback_index]] <- data.frame(
    variable = variable,
    present_in_global_fallback =
      variable_in_global,

    regional_missing_count =
      sum(
        !regional_finite
      ),

    missing_values_recoverable =
      missing_recoverable,

    n_common_finite =
      metrics[["n_complete"]],

    rmse =
      metrics[["rmse"]],

    mae =
      metrics[["mae"]],

    max_abs_difference =
      metrics[["max_abs_difference"]],

    correlation =
      metrics[["correlation"]],

    stringsAsFactors = FALSE
  )
}

fallback_comparison <- do.call(
  rbind,
  fallback_rows
)

if (nrow(climate_missing_records) > 0L) {
  climate_missing_records$global_fallback_present <-
    climate_missing_records$variable %in%
      names(global_fallback)

  climate_missing_records$global_fallback_value <-
    NA_real_

  for (
    row_index in
      seq_len(
        nrow(climate_missing_records)
      )
  ) {
    variable <- climate_missing_records$variable[
      row_index
    ]

    if (!variable %in% names(global_fallback)) {
      next
    }

    matched_index <- match(
      climate_missing_records$HYBAS_ID[
        row_index
      ],
      global_keys
    )

    value <- global_fallback[
      matched_index,
      variable
    ]

    climate_missing_records$global_fallback_value[
      row_index
    ] <- suppressWarnings(
      as.numeric(value)
    )
  }

  climate_missing_records$global_fallback_finite <-
    is.finite(
      climate_missing_records$global_fallback_value
    )
}

training <- read_largest_table(
  training_file
)

longitude_column <- find_column(
  training,
  c(
    "longitude",
    "lon",
    "LONGITUDE",
    "Longitude"
  )
)

latitude_column <- find_column(
  training,
  c(
    "latitude",
    "lat",
    "LATITUDE",
    "Latitude"
  )
)

if (
  is.na(longitude_column) ||
  is.na(latitude_column)
) {
  stop(
    "Training longitude or latitude column not found."
  )
}

required_spatial_features <- c(
  "p0__sp_x",
  "p0__sp_y",
  "p0__sp_z"
)

missing_spatial_features <- setdiff(
  required_spatial_features,
  names(training)
)

if (length(missing_spatial_features) > 0L) {
  stop(
    "Spatial model features absent: ",
    paste(
      missing_spatial_features,
      collapse = ", "
    )
  )
}

longitude_radians <-
  training[[longitude_column]] *
  pi /
  180

latitude_radians <-
  training[[latitude_column]] *
  pi /
  180

spatial_candidates <- list(
  p0__sp_x =
    cos(latitude_radians) *
    cos(longitude_radians),

  p0__sp_y =
    cos(latitude_radians) *
    sin(longitude_radians),

  p0__sp_z =
    sin(latitude_radians)
)

spatial_rows <- lapply(
  required_spatial_features,
  function(feature) {
    metrics <- safe_metrics(
      training[[feature]],
      spatial_candidates[[feature]]
    )

    data.frame(
      feature = feature,
      formula = switch(
        feature,
        p0__sp_x =
          "cos(latitude_rad) * cos(longitude_rad)",
        p0__sp_y =
          "cos(latitude_rad) * sin(longitude_rad)",
        p0__sp_z =
          "sin(latitude_rad)"
      ),
      n_complete =
        metrics[["n_complete"]],
      rmse =
        metrics[["rmse"]],
      mae =
        metrics[["mae"]],
      max_abs_difference =
        metrics[["max_abs_difference"]],
      correlation =
        metrics[["correlation"]],
      stringsAsFactors = FALSE
    )
  }
)

spatial_formula_diagnostics <- do.call(
  rbind,
  spatial_rows
)

spatial_formula_exact <- all(
  is.finite(
    spatial_formula_diagnostics$
      max_abs_difference
  ) &
  spatial_formula_diagnostics$
    max_abs_difference <
    1e-12
)

all_regional_keys_congruent <- all(
  regional_audit$
    climate_key_duplicates ==
    0L &
  regional_audit$
    geology_key_duplicates ==
    0L &
  regional_audit$
    soil_key_duplicates ==
    0L &
  regional_audit$
    climate_equals_geology_keys &
  regional_audit$
    climate_equals_soil_keys &
  regional_audit$
    climate_keys_in_age
)

all_reach_joins_complete <- all(
  regional_audit$
    reach_rows_unmatched_climate ==
    0L &
  regional_audit$
    reach_rows_unmatched_geology ==
    0L &
  regional_audit$
    reach_rows_unmatched_soil ==
    0L &
  regional_audit$
    reach_rows_unmatched_age ==
    0L
)

climate_partition_exact <-
  nrow(climate_all) ==
    16397L &&
  length(
    unique(
      climate_union_keys
    )
  ) ==
    16397L &&
  climate_union_duplicate_count ==
    0L

climate_missing_cells <-
  nrow(
    climate_missing_records
  )

fallback_recoverable_cells <-
  if (
    nrow(climate_missing_records) >
      0L
  ) {
    sum(
      climate_missing_records$
        global_fallback_finite
    )
  } else {
    0L
  }

pilot_join_ready <-
  age_key_unique &&
  climate_partition_exact &&
  all_regional_keys_congruent &&
  all_reach_joins_complete &&
  spatial_formula_exact

write.csv(
  regional_audit,
  file.path(
    out_dir,
    "regional_key_join_audit.csv"
  ),
  row.names = FALSE
)

write.csv(
  climate_missing_records,
  file.path(
    out_dir,
    "climate_missing_records.csv"
  ),
  row.names = FALSE
)

write.csv(
  fallback_comparison,
  file.path(
    out_dir,
    "global_fallback_comparison.csv"
  ),
  row.names = FALSE
)

write.csv(
  spatial_formula_diagnostics,
  file.path(
    out_dir,
    "spatial_formula_diagnostics.csv"
  ),
  row.names = FALSE
)

summary_lines <- c(
  "R58J STRICT DEPLOYMENT JOIN AUDIT",
  "=================================",
  "",
  paste0(
    "Regional climate rows: ",
    nrow(climate_all)
  ),
  paste0(
    "Unique regional climate HYBAS_IDs: ",
    length(
      unique(
        climate_union_keys
      )
    )
  ),
  paste0(
    "Cross-region climate key duplicates: ",
    climate_union_duplicate_count
  ),
  paste0(
    "Age table HYBAS_ID unique: ",
    age_key_unique
  ),
  paste0(
    "Climate partition exactly 16,397 L6 basins: ",
    climate_partition_exact
  ),
  paste0(
    "All regional basin-source keys congruent: ",
    all_regional_keys_congruent
  ),
  paste0(
    "All reach-to-basin joins complete: ",
    all_reach_joins_complete
  ),
  paste0(
    "Climate missing cells: ",
    climate_missing_cells
  ),
  paste0(
    "Missing cells recoverable from global fallback: ",
    fallback_recoverable_cells
  ),
  paste0(
    "Spatial unit-sphere formula exact: ",
    spatial_formula_exact
  ),
  paste0(
    "Pilot asset join ready: ",
    pilot_join_ready
  ),
  "",
  "STATUS: R58J STRICT DEPLOYMENT JOIN AUDIT PASSED"
)

writeLines(
  summary_lines,
  file.path(
    out_dir,
    "run_summary.txt"
  )
)

cat(
  paste(
    summary_lines,
    collapse = "\n"
  ),
  "\n\n"
)

cat(
  "===== REGIONAL KEY/JOIN AUDIT =====\n"
)

print(
  regional_audit,
  row.names = FALSE
)

cat(
  "\n===== GLOBAL FALLBACK COMPARISON =====\n"
)

print(
  fallback_comparison,
  row.names = FALSE
)

cat(
  "\n===== SPATIAL FORMULA DIAGNOSTICS =====\n"
)

print(
  spatial_formula_diagnostics,
  row.names = FALSE
)

cat(
  "\n===== CLIMATE MISSING RECORDS =====\n"
)

print(
  climate_missing_records,
  row.names = FALSE
)
