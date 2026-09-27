suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

# ============================================================
# 0. Paths
# ============================================================

mismatch_file <- paste0(
  "outputs/r46_full_range_local_lithology_compatibility/",
  "asset_upstream_vs_frozen_p0_mismatch_details.csv"
)

model_file <-
  "data/processed/model_table_p0_full_range.rds"

current_assignment_file <- paste0(
  "outputs/model_age_join/",
  "sample_hydrobasins_l6_assignment.csv"
)

known_validation_candidates <- c(
  paste0(
    "outputs/full_range_p0_recovery/",
    "hybas_validation_legacy_vs_current.csv"
  ),
  paste0(
    "outputs/full_range_p0_recovery/",
    "hybas_7_mismatches.csv"
  )
)

out_dir <-
  "outputs/r46b_local_lithology_mismatch_diagnosis"

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

required_files <- c(
  mismatch_file,
  model_file,
  current_assignment_file
)

missing_files <- required_files[
  !file.exists(required_files)
]

if (length(missing_files) > 0L) {
  stop(
    "Missing required files:\n",
    paste(
      missing_files,
      collapse = "\n"
    )
  )
}

# ============================================================
# 1. Read mismatch and model data
# ============================================================

mismatch <- read_csv(
  mismatch_file,
  show_col_types = FALSE,
  progress = FALSE
)

model <- readRDS(
  model_file
)

current_assignment <- read_csv(
  current_assignment_file,
  show_col_types = FALSE,
  progress = FALSE
)

if (!is.data.frame(model)) {
  stop(
    "Model object is not a data frame."
  )
}

required_mismatch_fields <- c(
  "row_id",
  "HYBAS_JOIN_KEY",
  "asset_region",
  "lithology",
  "p0_value",
  "asset_value",
  "difference"
)

missing_mismatch_fields <- setdiff(
  required_mismatch_fields,
  names(mismatch)
)

if (length(missing_mismatch_fields) > 0L) {
  stop(
    "Missing mismatch fields: ",
    paste(
      missing_mismatch_fields,
      collapse = ", "
    )
  )
}

if (!"row_id" %in% names(model)) {
  stop(
    "row_id missing from model table."
  )
}

if (!all(
  c(
    "row_id",
    "HYBAS_ID"
  ) %in%
  names(current_assignment)
)) {
  stop(
    "Current assignment must contain row_id and HYBAS_ID."
  )
}

# ============================================================
# 2. Basic mismatch summaries
# ============================================================

mismatch <- mismatch |>
  mutate(
    row_id =
      trimws(as.character(row_id)),

    abs_difference =
      abs(
        difference
      )
  )

mismatch_by_lithology <- mismatch |>
  group_by(
    lithology
  ) |>
  summarise(
    n_mismatch_rows =
      n(),

    n_unique_sites =
      n_distinct(
        row_id
      ),

    max_abs_difference =
      max(
        abs_difference,
        na.rm = TRUE
      ),

    mean_abs_difference =
      mean(
        abs_difference,
        na.rm = TRUE
      ),

    .groups =
      "drop"
  ) |>
  arrange(
    desc(
      n_mismatch_rows
    ),
    desc(
      max_abs_difference
    )
  )

mismatch_by_site <- mismatch |>
  group_by(
    row_id
  ) |>
  summarise(
    mismatch_hybas_key =
      first(
        HYBAS_JOIN_KEY
      ),

    asset_region =
      first(
        asset_region
      ),

    n_lithology_mismatches =
      n(),

    mismatched_lithologies =
      paste(
        sort(
          unique(
            lithology
          )
        ),
        collapse = ";"
      ),

    max_abs_difference =
      max(
        abs_difference,
        na.rm = TRUE
      ),

    sum_abs_difference =
      sum(
        abs_difference,
        na.rm = TRUE
      ),

    .groups =
      "drop"
  )

# ============================================================
# 3. Attach target and location information
# ============================================================

model_fields <- intersect(
  c(
    "row_id",
    "sr87_sr86",
    "longitude",
    "latitude",
    "site_id",
    "reference_group",
    "source_reference"
  ),
  names(model)
)

model_compact <- model |>
  select(
    all_of(
      model_fields
    )
  ) |>
  mutate(
    row_id =
      trimws(
        as.character(
          row_id
        )
      )
  )

mismatch_by_site <- mismatch_by_site |>
  mutate(
    row_id =
      trimws(
        as.character(
          row_id
        )
      )
  ) |>
  left_join(
    model_compact,
    by = "row_id"
  )

if (
  "sr87_sr86" %in%
  names(mismatch_by_site)
) {

  mismatch_by_site <- mismatch_by_site |>
    mutate(
      is_ge_072 =
        !is.na(sr87_sr86) &
        sr87_sr86 >= 0.720,

      is_ge_075 =
        !is.na(sr87_sr86) &
        sr87_sr86 >= 0.750,

      is_ge_080 =
        !is.na(sr87_sr86) &
        sr87_sr86 >= 0.800
    )

} else {

  mismatch_by_site <- mismatch_by_site |>
    mutate(
      is_ge_072 =
        NA,

      is_ge_075 =
        NA,

      is_ge_080 =
        NA
    )
}

# ============================================================
# 4. Attach current assignment
# ============================================================

current_compact <- current_assignment |>
  transmute(
    row_id =
      trimws(as.character(row_id)),

    current_HYBAS_ID =
      as.character(
        HYBAS_ID
      ),

    current_basin_region =
      if (
        "basin_region" %in%
        names(current_assignment)
      ) {
        as.character(
          basin_region
        )
      } else {
        NA_character_
      },

    current_assignment_method =
      if (
        "basin_assignment_method" %in%
        names(current_assignment)
      ) {
        as.character(
          basin_assignment_method
        )
      } else {
        NA_character_
      },

    current_nearest_distance_km =
      if (
        "nearest_basin_distance_km" %in%
        names(current_assignment)
      ) {
        as.numeric(
          nearest_basin_distance_km
        )
      } else {
        NA_real_
      }
  )

mismatch_by_site <- mismatch_by_site |>
  left_join(
    current_compact,
    by = "row_id"
  )

# ============================================================
# 5. Inspect known legacy/current mismatch assets
# ============================================================

find_row_field <- function(dat) {

  hit <- intersect(
    c(
      "row_id",
      "site_row_id",
      "model_row_id",
      ".model_row_index"
    ),
    names(dat)
  )

  if (length(hit) > 0L) {
    return(
      hit[1]
    )
  }

  NA_character_
}

find_field <- function(
  dat,
  candidates
) {

  hit <- intersect(
    candidates,
    names(dat)
  )

  if (length(hit) > 0L) {
    return(
      hit[1]
    )
  }

  NA_character_
}

known_schema_list <- list()
known_row_tables <- list()

for (
  path_i in known_validation_candidates
) {

  if (!file.exists(path_i)) {
    next
  }

  x <- read_csv(
    path_i,
    show_col_types = FALSE,
    progress = FALSE
  )

  row_field <- find_row_field(
    x
  )

  current_field <- find_field(
    x,
    c(
      "current_HYBAS_ID",
      "current_hybas_key",
      "HYBAS_ID"
    )
  )

  legacy_field <- find_field(
    x,
    c(
      "legacy_HYBAS_ID",
      "legacy_hybas_key"
    )
  )

  same_field <- find_field(
    x,
    c(
      "same_hybas",
      "same_HYBAS_ID"
    )
  )

  known_schema_list[[
    length(known_schema_list) + 1L
  ]] <- data.frame(
    path =
      path_i,

    n_rows =
      nrow(x),

    n_cols =
      ncol(x),

    row_field =
      row_field,

    current_field =
      current_field,

    legacy_field =
      legacy_field,

    same_field =
      same_field,

    all_fields =
      paste(
        names(x),
        collapse = ";"
      ),

    stringsAsFactors =
      FALSE
  )

  if (!is.na(row_field)) {

    compact <- data.frame(
      row_id =
        trimws(as.character(x[[row_field]])),

      known_source =
        path_i,

      known_current_HYBAS_ID =
        if (
          !is.na(current_field)
        ) {
          as.character(
            x[[current_field]]
          )
        } else {
          NA_character_
        },

      known_legacy_HYBAS_ID =
        if (
          !is.na(legacy_field)
        ) {
          as.character(
            x[[legacy_field]]
          )
        } else {
          NA_character_
        },

      known_same_hybas =
        if (
          !is.na(same_field)
        ) {
          as.logical(
            x[[same_field]]
          )
        } else {
          NA
        },

      stringsAsFactors =
        FALSE
    )

    known_row_tables[[
      length(known_row_tables) + 1L
    ]] <- compact
  }
}

known_schema <- if (
  length(known_schema_list) > 0L
) {
  bind_rows(
    known_schema_list
  )
} else {
  data.frame(
    path =
      character(0),

    n_rows =
      integer(0),

    n_cols =
      integer(0),

    row_field =
      character(0),

    current_field =
      character(0),

    legacy_field =
      character(0),

    same_field =
      character(0),

    all_fields =
      character(0),

    stringsAsFactors =
      FALSE
  )
}

known_rows <- if (
  length(known_row_tables) > 0L
) {
  bind_rows(
    known_row_tables
  ) |>
    distinct(
      row_id,
      .keep_all = TRUE
    )
} else {
  data.frame(
    row_id = character(0),

    known_source =
      character(0),

    known_current_HYBAS_ID =
      character(0),

    known_legacy_HYBAS_ID =
      character(0),

    known_same_hybas =
      logical(0),

    stringsAsFactors =
      FALSE
  )
}

mismatch_by_site <- mismatch_by_site |>
  left_join(
    known_rows,
    by = "row_id"
  ) |>
  mutate(
    found_in_known_validation =
      !is.na(
        known_source
      ),

    mismatch_key_equals_current =
      as.character(
        mismatch_hybas_key
      ) ==
      as.character(
        current_HYBAS_ID
      ),

    mismatch_key_equals_known_legacy =
      as.character(
        mismatch_hybas_key
      ) ==
      as.character(
        known_legacy_HYBAS_ID
      )
  ) |>
  arrange(
    desc(
      is_ge_080
    ),
    desc(
      is_ge_075
    ),
    desc(
      max_abs_difference
    )
  )

# ============================================================
# 6. Compact overall summary
# ============================================================

overall_summary <- data.frame(
  statistic = c(
    "mismatch_site_lithology_rows",
    "unique_mismatch_sites",
    "sites_in_known_validation",
    "sites_not_in_known_validation",
    "mismatch_sites_ge_072",
    "mismatch_sites_ge_075",
    "mismatch_sites_ge_080",
    "max_site_abs_difference"
  ),

  value = c(
    nrow(
      mismatch
    ),

    n_distinct(
      mismatch$row_id
    ),

    sum(
      mismatch_by_site$found_in_known_validation,
      na.rm = TRUE
    ),

    sum(
      !mismatch_by_site$found_in_known_validation,
      na.rm = TRUE
    ),

    sum(
      mismatch_by_site$is_ge_072,
      na.rm = TRUE
    ),

    sum(
      mismatch_by_site$is_ge_075,
      na.rm = TRUE
    ),

    sum(
      mismatch_by_site$is_ge_080,
      na.rm = TRUE
    ),

    max(
      mismatch_by_site$max_abs_difference,
      na.rm = TRUE
    )
  ),

  stringsAsFactors =
    FALSE
)

# ============================================================
# 7. Save outputs
# ============================================================

write_csv(
  overall_summary,
  file.path(
    out_dir,
    "overall_mismatch_summary.csv"
  )
)

write_csv(
  mismatch_by_lithology,
  file.path(
    out_dir,
    "mismatch_summary_by_lithology.csv"
  )
)

write_csv(
  mismatch_by_site,
  file.path(
    out_dir,
    "mismatch_summary_by_site.csv"
  )
)

write_csv(
  mismatch,
  file.path(
    out_dir,
    "mismatch_details_with_abs_difference.csv"
  )
)

write_csv(
  known_schema,
  file.path(
    out_dir,
    "known_hybas_validation_schema.csv"
  )
)

# ============================================================
# 8. Terminal report
# ============================================================

cat(
  "\n========================================\n"
)

cat(
  "R46B LOCAL LITHOLOGY MISMATCH DIAGNOSIS\n"
)

cat(
  "========================================\n"
)

cat(
  "\n===== OVERALL SUMMARY =====\n"
)

print(
  overall_summary,
  row.names = FALSE
)

cat(
  "\n===== SUMMARY BY LITHOLOGY =====\n"
)

print(
  mismatch_by_lithology,
  row.names = FALSE
)

cat(
  "\n===== AFFECTED SITES =====\n"
)

print(
  mismatch_by_site,
  row.names = FALSE
)

cat(
  "\n===== KNOWN HYBAS FILE SCHEMAS =====\n"
)

print(
  known_schema,
  row.names = FALSE
)

cat(
  "\n===== OUTPUT FILES =====\n"
)

print(
  list.files(
    out_dir,
    full.names = FALSE
  )
)

cat(
  "\n===== DONE =====\n"
)
