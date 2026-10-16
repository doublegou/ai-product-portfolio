suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

# ============================================================
# 0. Paths
# ============================================================

project_dir <- normalizePath(
  ".",
  mustWork = TRUE
)

legacy_root <-
  "/home/zhangmeng/projects/sr_global"

glim_dir <- file.path(
  legacy_root,
  "data_processed/global/glim_l6_by_region"
)

terrain_dir <- file.path(
  legacy_root,
  "data_processed/global/climate_terrain_l6_by_region"
)

model_file <- file.path(
  project_dir,
  "data/processed/model_table_p0_full_range.rds"
)

site_predictor_file <- file.path(
  project_dir,
  "data/external/predictors_at_sites_full_range.rds"
)

out_dir <- file.path(
  project_dir,
  "outputs/r46_full_range_local_lithology_compatibility"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

# ============================================================
# 1. Required inputs
# ============================================================

required_paths <- c(
  glim_dir,
  model_file,
  site_predictor_file
)

missing_paths <- required_paths[
  !file.exists(required_paths) &
    !dir.exists(required_paths)
]

if (length(missing_paths) > 0L) {
  stop(
    "Missing required paths:\n",
    paste(
      missing_paths,
      collapse = "\n"
    )
  )
}

# ============================================================
# 2. Discover regional assets
# ============================================================

glim_files <- list.files(
  glim_dir,
  pattern =
    "^l6_glim_local_upstream_[a-z]{2}\\.rds$",
  full.names = TRUE
)

terrain_files <- if (
  dir.exists(terrain_dir)
) {
  list.files(
    terrain_dir,
    pattern =
      "^l6_climate_terrain_local_upstream_[a-z]{2}\\.rds$",
    full.names = TRUE
  )
} else {
  character(0)
}

if (length(glim_files) == 0L) {
  stop(
    "No regional GLiM local/upstream RDS files found."
  )
}

cat(
  "\n===== REGIONAL ASSETS =====\n"
)

cat(
  "GLiM files: ",
  length(glim_files),
  "\n",
  sep = ""
)

cat(
  "Climate/terrain files: ",
  length(terrain_files),
  "\n",
  sep = ""
)

# ============================================================
# 3. Helpers
# ============================================================

find_key <- function(dat) {

  exact_candidates <- c(
    "HYBAS_ID",
    "hybas_id",
    "HYBAS_KEY",
    "hybas_key"
  )

  hit <- intersect(
    exact_candidates,
    names(dat)
  )

  if (length(hit) > 0L) {
    return(hit[1])
  }

  regex_hit <- grep(
    "hybas",
    names(dat),
    ignore.case = TRUE,
    value = TRUE
  )

  if (length(regex_hit) > 0L) {
    return(regex_hit[1])
  }

  NA_character_
}

standardize_key <- function(x) {

  if (is.factor(x)) {
    x <- as.character(x)
  }

  if (is.numeric(x)) {
    return(
      format(
        x,
        scientific = FALSE,
        trim = TRUE
      )
    )
  }

  as.character(x)
}

safe_numeric <- function(x) {

  if (is.numeric(x)) {
    return(x)
  }

  suppressWarnings(
    as.numeric(
      as.character(x)
    )
  )
}

field_catalogue <- function(
  dat,
  file,
  region,
  key
) {

  data.frame(
    file =
      file,

    region =
      region,

    key_field =
      key,

    field =
      names(dat),

    field_class =
      vapply(
        dat,
        function(x) {
          paste(
            class(x),
            collapse = ";"
          )
        },
        character(1)
      ),

    stringsAsFactors =
      FALSE
  )
}

# ============================================================
# 4. Inspect and combine GLiM regional files
# ============================================================

glim_summary_list <- list()
glim_fields_list <- list()
glim_data_list <- list()

for (
  i in seq_along(glim_files)
) {

  file_i <- glim_files[i]

  region_i <- sub(
    "^.*l6_glim_local_upstream_([a-z]{2})\\.rds$",
    "\\1",
    file_i
  )

  x <- readRDS(
    file_i
  )

  if (!is.data.frame(x)) {
    stop(
      "GLiM asset is not a data frame: ",
      file_i
    )
  }

  key_i <- find_key(x)

  if (is.na(key_i)) {
    stop(
      "No HYBAS key found in: ",
      file_i
    )
  }

  local_fields_i <- grep(
    "^local_geo_.*_frac$",
    names(x),
    value = TRUE
  )

  upstream_fields_i <- grep(
    "^(up_geo_|upstream_geo_).*_frac$",
    names(x),
    value = TRUE
  )

  area_fields_i <- grep(
    "^(local|up)_area_",
    names(x),
    value = TRUE
  )

  glim_summary_list[[i]] <- data.frame(

    region =
      region_i,

    file =
      file_i,

    n_rows =
      nrow(x),

    n_cols =
      ncol(x),

    key_field =
      key_i,

    missing_key =
      sum(
        is.na(
          x[[key_i]]
        )
      ),

    duplicated_key =
      sum(
        duplicated(
          standardize_key(
            x[[key_i]]
          )
        )
      ),

    n_local_frac_fields =
      length(local_fields_i),

    n_upstream_frac_fields =
      length(upstream_fields_i),

    n_area_fields =
      length(area_fields_i),

    stringsAsFactors =
      FALSE
  )

  glim_fields_list[[i]] <-
    field_catalogue(
      x,
      file_i,
      region_i,
      key_i
    )

  keep_fields <- unique(
    c(
      key_i,
      local_fields_i,
      upstream_fields_i,
      area_fields_i,
      grep(
        "lith.*area|total.*area",
        names(x),
        ignore.case = TRUE,
        value = TRUE
      )
    )
  )

  y <- x[
    ,
    keep_fields,
    drop = FALSE
  ]

  names(y)[
    names(y) ==
      key_i
  ] <- "HYBAS_JOIN_KEY"

  y$HYBAS_JOIN_KEY <-
    standardize_key(
      y$HYBAS_JOIN_KEY
    )

  y$asset_region <-
    region_i

  glim_data_list[[i]] <-
    y
}

glim_summary <- bind_rows(
  glim_summary_list
)

glim_fields <- bind_rows(
  glim_fields_list
)

write_csv(
  glim_summary,
  file.path(
    out_dir,
    "glim_regional_asset_summary.csv"
  )
)

write_csv(
  glim_fields,
  file.path(
    out_dir,
    "glim_field_catalogue.csv"
  )
)

glim_all <- bind_rows(
  glim_data_list
)

# Check global key uniqueness.

global_duplicate_keys <- glim_all |>
  count(
    HYBAS_JOIN_KEY,
    name = "n"
  ) |>
  filter(
    n > 1L
  )

write_csv(
  global_duplicate_keys,
  file.path(
    out_dir,
    "glim_global_duplicate_keys.csv"
  )
)

if (nrow(global_duplicate_keys) > 0L) {

  cat(
    "\nWARNING: duplicate HYBAS keys across regional GLiM files: ",
    nrow(global_duplicate_keys),
    "\n",
    sep = ""
  )
}

# Keep the first row only for audit joins.
# Duplicates remain separately documented.

glim_unique <- glim_all |>
  arrange(
    HYBAS_JOIN_KEY,
    asset_region
  ) |>
  distinct(
    HYBAS_JOIN_KEY,
    .keep_all = TRUE
  )

# ============================================================
# 5. Audit climate/terrain regional assets
# ============================================================

terrain_summary_list <- list()
terrain_fields_list <- list()

if (length(terrain_files) > 0L) {

  for (
    i in seq_along(terrain_files)
  ) {

    file_i <- terrain_files[i]

    region_i <- sub(
      "^.*l6_climate_terrain_local_upstream_([a-z]{2})\\.rds$",
      "\\1",
      file_i
    )

    x <- readRDS(
      file_i
    )

    key_i <- find_key(x)

    terrain_candidate_fields <- grep(
      "elev|slope|relief|rugged|terrain",
      names(x),
      ignore.case = TRUE,
      value = TRUE
    )

    terrain_summary_list[[i]] <- data.frame(

      region =
        region_i,

      file =
        file_i,

      n_rows =
        nrow(x),

      n_cols =
        ncol(x),

      key_field =
        key_i,

      n_terrain_candidate_fields =
        length(
          terrain_candidate_fields
        ),

      terrain_candidate_fields =
        paste(
          terrain_candidate_fields,
          collapse = ";"
        ),

      stringsAsFactors =
        FALSE
    )

    terrain_fields_list[[i]] <-
      field_catalogue(
        x,
        file_i,
        region_i,
        key_i
      )
  }
}

terrain_summary <- bind_rows(
  terrain_summary_list
)

terrain_fields <- bind_rows(
  terrain_fields_list
)

write_csv(
  terrain_summary,
  file.path(
    out_dir,
    "terrain_regional_asset_summary.csv"
  )
)

write_csv(
  terrain_fields,
  file.path(
    out_dir,
    "terrain_field_catalogue.csv"
  )
)

# ============================================================
# 6. Read current full-range model tables
# ============================================================

model <- readRDS(
  model_file
)

site_predictors <- readRDS(
  site_predictor_file
)

if (!is.data.frame(model)) {
  stop(
    "Full-range model object is not a data frame."
  )
}

if (!is.data.frame(site_predictors)) {
  stop(
    "Full-range site predictor object is not a data frame."
  )
}

if (!"row_id" %in% names(model)) {
  stop(
    "row_id missing from full-range model table."
  )
}

if (!"row_id" %in% names(site_predictors)) {
  stop(
    "row_id missing from full-range site predictor table."
  )
}

if (anyDuplicated(model$row_id)) {
  stop(
    "Duplicated row_id in full-range model table."
  )
}

if (anyDuplicated(site_predictors$row_id)) {
  stop(
    "Duplicated row_id in full-range site predictor table."
  )
}

model_key_candidates <- grep(
  "hybas",
  names(model),
  ignore.case = TRUE,
  value = TRUE
)

site_key_candidates <- grep(
  "hybas",
  names(site_predictors),
  ignore.case = TRUE,
  value = TRUE
)

make_key_inventory <- function(
  source_name,
  fields
) {

  if (length(fields) == 0L) {

    return(
      data.frame(
        source =
          character(0),

        field =
          character(0),

        stringsAsFactors =
          FALSE
      )
    )
  }

  data.frame(
    source =
      rep(
        source_name,
        length(fields)
      ),

    field =
      fields,

    stringsAsFactors =
      FALSE
  )
}

key_inventory <- bind_rows(

  make_key_inventory(
    "model_table_p0_full_range",
    model_key_candidates
  ),

  make_key_inventory(
    "predictors_at_sites_full_range",
    site_key_candidates
  )
)

write_csv(
  key_inventory,
  file.path(
    out_dir,
    "full_range_hybas_key_inventory.csv"
  )
)

cat(
  "\n===== FULL-RANGE HYBAS KEY CANDIDATES =====\n"
)

if (nrow(key_inventory) > 0L) {

  print(
    key_inventory,
    row.names = FALSE
  )

} else {

  cat(
    "No HYBAS field stored directly in either full-range table.\n"
  )
}

# ============================================================
# 7. Resolve a site-to-basin key
# ============================================================

preferred_keys <- c(
  "HYBAS_ID",
  "hybas_id",
  "HYBAS_KEY",
  "hybas_key",
  "current_HYBAS_ID",
  "current_hybas_key",
  "legacy_HYBAS_ID",
  "legacy_hybas_key"
)

choose_preferred_key <- function(
  dat
) {

  exact_hit <- intersect(
    preferred_keys,
    names(dat)
  )

  if (length(exact_hit) > 0L) {
    return(exact_hit[1])
  }

  regex_hit <- grep(
    "hybas",
    names(dat),
    ignore.case = TRUE,
    value = TRUE
  )

  if (length(regex_hit) > 0L) {
    return(regex_hit[1])
  }

  NA_character_
}

model_key <- choose_preferred_key(
  model
)

site_key <- choose_preferred_key(
  site_predictors
)

mapping_schema_list <- list()
mapping_data <- NULL
mapping_source <- NA_character_
mapping_key <- NA_character_

# ------------------------------------------------------------
# 7A. First preference: key stored directly in model table
# ------------------------------------------------------------

if (!is.na(model_key)) {

  site_map <- model |>
    transmute(
      row_id =
        row_id,

      HYBAS_JOIN_KEY =
        standardize_key(
          .data[[model_key]]
        ),

      join_key_source =
        paste0(
          "model:",
          model_key
        )
    )

  mapping_source <- paste0(
    "model:",
    model_key
  )

  mapping_key <- model_key

# ------------------------------------------------------------
# 7B. Second preference: key stored in site predictor table
# ------------------------------------------------------------

} else if (!is.na(site_key)) {

  site_key_table <- site_predictors |>
    transmute(
      row_id =
        row_id,

      HYBAS_JOIN_KEY =
        standardize_key(
          .data[[site_key]]
        )
    )

  site_map <- model |>
    select(
      row_id
    ) |>
    left_join(
      site_key_table,
      by = "row_id"
    ) |>
    mutate(
      join_key_source =
        paste0(
          "site_predictors:",
          site_key
        )
    )

  mapping_source <- paste0(
    "site_predictors:",
    site_key
  )

  mapping_key <- site_key

# ------------------------------------------------------------
# 7C. Fallback: discover an existing site-HydroBASINS assignment
# ------------------------------------------------------------

} else {

  explicit_mapping_candidates <- c(

    "outputs/model_age_join/sample_hydrobasins_l6_assignment.csv",

    "outputs/model_age_join/sample_hydrobasins_l6_assignment.rds",

    "outputs/full_range_p0_recovery/sample_hydrobasins_l6_assignment.csv",

    "outputs/full_range_p0_recovery/sample_hydrobasins_l6_assignment.rds"
  )

  discovered_mapping_candidates <- unique(
    c(

      list.files(
        "outputs",
        recursive = TRUE,
        full.names = TRUE,
        pattern =
          "(hybas.*assign|assign.*hybas|sample_hydrobasins).*\\.(csv|rds)$",
        ignore.case = TRUE
      ),

      list.files(
        "data",
        recursive = TRUE,
        full.names = TRUE,
        pattern =
          "(hybas.*assign|assign.*hybas|sample_hydrobasins).*\\.(csv|rds)$",
        ignore.case = TRUE
      )
    )
  )

  mapping_candidates <- unique(
    c(
      explicit_mapping_candidates,
      discovered_mapping_candidates
    )
  )

  mapping_candidates <- mapping_candidates[
    file.exists(
      mapping_candidates
    )
  ]

  read_mapping_candidate <- function(
    mapping_path
  ) {

    extension <- tolower(
      tools::file_ext(
        mapping_path
      )
    )

    if (extension == "rds") {

      obj <- tryCatch(
        readRDS(
          mapping_path
        ),
        error = function(e) e
      )

    } else {

      obj <- tryCatch(
        read_csv(
          mapping_path,
          show_col_types = FALSE,
          progress = FALSE
        ),
        error = function(e) e
      )
    }

    obj
  }

  for (
    candidate_path in mapping_candidates
  ) {

    candidate_object <- read_mapping_candidate(
      candidate_path
    )

    if (
      inherits(
        candidate_object,
        "error"
      )
    ) {

      mapping_schema_list[[
        length(mapping_schema_list) + 1L
      ]] <- data.frame(

        path =
          candidate_path,

        status =
          "READ_ERROR",

        n_rows =
          NA_real_,

        n_cols =
          NA_real_,

        row_id_field =
          NA_character_,

        hybas_field =
          NA_character_,

        fields =
          NA_character_,

        notes =
          conditionMessage(
            candidate_object
          ),

        stringsAsFactors =
          FALSE
      )

      next
    }

    if (!is.data.frame(candidate_object)) {

      mapping_schema_list[[
        length(mapping_schema_list) + 1L
      ]] <- data.frame(

        path =
          candidate_path,

        status =
          "NOT_DATA_FRAME",

        n_rows =
          NA_real_,

        n_cols =
          NA_real_,

        row_id_field =
          NA_character_,

        hybas_field =
          NA_character_,

        fields =
          NA_character_,

        notes =
          paste(
            class(candidate_object),
            collapse = ";"
          ),

        stringsAsFactors =
          FALSE
      )

      next
    }

    row_field_candidates <- intersect(
      c(
        "row_id",
        "site_row_id",
        "model_row_id"
      ),
      names(candidate_object)
    )

    row_field <- if (
      length(row_field_candidates) > 0L
    ) {
      row_field_candidates[1]
    } else {
      NA_character_
    }

    hybas_field <- choose_preferred_key(
      candidate_object
    )

    usable <- !is.na(row_field) &&
      !is.na(hybas_field)

    mapping_schema_list[[
      length(mapping_schema_list) + 1L
    ]] <- data.frame(

      path =
        candidate_path,

      status =
        if (usable) {
          "USABLE"
        } else {
          "MISSING_REQUIRED_FIELDS"
        },

      n_rows =
        nrow(candidate_object),

      n_cols =
        ncol(candidate_object),

      row_id_field =
        row_field,

      hybas_field =
        hybas_field,

      fields =
        paste(
          names(candidate_object),
          collapse = ";"
        ),

      notes =
        NA_character_,

      stringsAsFactors =
        FALSE
    )

    if (
      usable &&
      is.null(mapping_data)
    ) {

      mapping_data <- candidate_object

      mapping_source <- candidate_path

      mapping_key <- hybas_field

      mapping_row_field <- row_field
    }
  }

  mapping_schema <- if (
    length(mapping_schema_list) > 0L
  ) {
    bind_rows(
      mapping_schema_list
    )
  } else {
    data.frame(
      path =
        character(0),

      status =
        character(0),

      n_rows =
        numeric(0),

      n_cols =
        numeric(0),

      row_id_field =
        character(0),

      hybas_field =
        character(0),

      fields =
        character(0),

      notes =
        character(0),

      stringsAsFactors =
        FALSE
    )
  }

  write_csv(
    mapping_schema,
    file.path(
      out_dir,
      "site_hybas_mapping_candidate_schema.csv"
    )
  )

  cat(
    "\n===== SITE-HYBAS MAPPING CANDIDATES =====\n"
  )

  print(
    mapping_schema,
    row.names = FALSE
  )

  if (is.null(mapping_data)) {

    stop(
      paste0(
        "No usable site-to-HydroBASINS mapping was found. ",
        "Inspect site_hybas_mapping_candidate_schema.csv."
      )
    )
  }

  selected_mapping <- mapping_data |>
    transmute(
      row_id =
        .data[[mapping_row_field]],

      HYBAS_JOIN_KEY =
        standardize_key(
          .data[[mapping_key]]
        )
    )

  if (anyDuplicated(selected_mapping$row_id)) {

    duplicated_mapping_ids <- selected_mapping |>
      count(
        row_id,
        name = "n"
      ) |>
      filter(
        n > 1L
      )

    write_csv(
      duplicated_mapping_ids,
      file.path(
        out_dir,
        "duplicated_site_hybas_mapping_row_ids.csv"
      )
    )

    stop(
      paste0(
        "Selected site-HYBAS mapping contains duplicated row_id values: ",
        nrow(duplicated_mapping_ids)
      )
    )
  }

  site_map <- model |>
    select(
      row_id
    ) |>
    left_join(
      selected_mapping,
      by = "row_id"
    ) |>
    mutate(
      join_key_source =
        paste0(
          "mapping_file:",
          mapping_source,
          ":",
          mapping_key
        )
    )
}

if (anyDuplicated(site_map$row_id)) {
  stop(
    "Duplicated row_id in final site-to-basin map."
  )
}

selected_mapping_summary <- data.frame(

  mapping_source =
    mapping_source,

  mapping_key =
    mapping_key,

  n_model_rows =
    nrow(model),

  n_mapping_rows =
    nrow(site_map),

  n_nonmissing_hybas =
    sum(
      !is.na(
        site_map$HYBAS_JOIN_KEY
      ) &
        nzchar(
          site_map$HYBAS_JOIN_KEY
        )
    ),

  n_missing_hybas =
    sum(
      is.na(
        site_map$HYBAS_JOIN_KEY
      ) |
        !nzchar(
          site_map$HYBAS_JOIN_KEY
        )
    ),

  stringsAsFactors =
    FALSE
)

write_csv(
  selected_mapping_summary,
  file.path(
    out_dir,
    "selected_site_hybas_mapping_summary.csv"
  )
)

cat(
  "\n===== SELECTED SITE-HYBAS MAPPING =====\n"
)

print(
  selected_mapping_summary,
  row.names = FALSE
)

# ============================================================
# 8. Join GLiM information to full-range sites
# ============================================================

site_glim <- site_map |>
  left_join(
    glim_unique,
    by = "HYBAS_JOIN_KEY"
  ) |>
  left_join(
    model |>
      select(
        row_id,
        any_of(
          c(
            "sr87_sr86",
            grep(
              "^p0__up_geo_.*_frac$",
              names(model),
              value = TRUE
            )
          )
        )
      ),
    by = "row_id"
  )

local_frac_fields <- grep(
  "^local_geo_.*_frac$",
  names(site_glim),
  value = TRUE
)

asset_up_frac_fields <- grep(
  "^(up_geo_|upstream_geo_).*_frac$",
  names(site_glim),
  value = TRUE
)

# Exclude p0 fields from the asset-field list.

asset_up_frac_fields <- asset_up_frac_fields[
  !grepl(
    "^p0__",
    asset_up_frac_fields
  )
]

matched_any_local <- if (
  length(local_frac_fields) > 0L
) {
  rowSums(
    !is.na(
      site_glim[
        ,
        local_frac_fields,
        drop = FALSE
      ]
    )
  ) > 0L
} else {
  rep(
    FALSE,
    nrow(site_glim)
  )
}

matched_any_asset_up <- if (
  length(asset_up_frac_fields) > 0L
) {
  rowSums(
    !is.na(
      site_glim[
        ,
        asset_up_frac_fields,
        drop = FALSE
      ]
    )
  ) > 0L
} else {
  rep(
    FALSE,
    nrow(site_glim)
  )
}

site_glim$matched_glim_key <-
  !is.na(
    site_glim$asset_region
  )

site_glim$matched_any_local_lith <-
  matched_any_local

site_glim$matched_any_asset_up_lith <-
  matched_any_asset_up

# ============================================================
# 9. Identify the full-range analysis sample
# ============================================================

p0_vars <- grep(
  "^p0__",
  names(model),
  value = TRUE
)

complete_p0_index <- complete.cases(
  model[
    ,
    p0_vars,
    drop = FALSE
  ]
)

complete_p0_ids <- model$row_id[
  complete_p0_index
]

site_glim$is_complete_p0 <-
  site_glim$row_id %in%
  complete_p0_ids

site_glim$is_ge_075 <-
  if (
    "sr87_sr86" %in% names(site_glim)
  ) {
    site_glim$sr87_sr86 >=
      0.750
  } else {
    FALSE
  }

site_glim$is_ge_080 <-
  if (
    "sr87_sr86" %in% names(site_glim)
  ) {
    site_glim$sr87_sr86 >=
      0.800
  } else {
    FALSE
  }

match_summary <- data.frame(

  subset = c(
    "all_4527",
    "complete_p0_4485",
    "complete_p0_ge_075",
    "complete_p0_ge_080"
  ),

  n = c(
    nrow(site_glim),

    sum(
      site_glim$is_complete_p0,
      na.rm = TRUE
    ),

    sum(
      site_glim$is_complete_p0 &
        site_glim$is_ge_075,
      na.rm = TRUE
    ),

    sum(
      site_glim$is_complete_p0 &
        site_glim$is_ge_080,
      na.rm = TRUE
    )
  ),

  n_key_matched = c(

    sum(
      site_glim$matched_glim_key,
      na.rm = TRUE
    ),

    sum(
      site_glim$is_complete_p0 &
        site_glim$matched_glim_key,
      na.rm = TRUE
    ),

    sum(
      site_glim$is_complete_p0 &
        site_glim$is_ge_075 &
        site_glim$matched_glim_key,
      na.rm = TRUE
    ),

    sum(
      site_glim$is_complete_p0 &
        site_glim$is_ge_080 &
        site_glim$matched_glim_key,
      na.rm = TRUE
    )
  ),

  n_local_lith_available = c(

    sum(
      site_glim$matched_any_local_lith,
      na.rm = TRUE
    ),

    sum(
      site_glim$is_complete_p0 &
        site_glim$matched_any_local_lith,
      na.rm = TRUE
    ),

    sum(
      site_glim$is_complete_p0 &
        site_glim$is_ge_075 &
        site_glim$matched_any_local_lith,
      na.rm = TRUE
    ),

    sum(
      site_glim$is_complete_p0 &
        site_glim$is_ge_080 &
        site_glim$matched_any_local_lith,
      na.rm = TRUE
    )
  ),

  n_asset_up_lith_available = c(

    sum(
      site_glim$matched_any_asset_up_lith,
      na.rm = TRUE
    ),

    sum(
      site_glim$is_complete_p0 &
        site_glim$matched_any_asset_up_lith,
      na.rm = TRUE
    ),

    sum(
      site_glim$is_complete_p0 &
        site_glim$is_ge_075 &
        site_glim$matched_any_asset_up_lith,
      na.rm = TRUE
    ),

    sum(
      site_glim$is_complete_p0 &
        site_glim$is_ge_080 &
        site_glim$matched_any_asset_up_lith,
      na.rm = TRUE
    )
  )
)

write_csv(
  match_summary,
  file.path(
    out_dir,
    "full_range_glim_match_summary.csv"
  )
)

# ============================================================
# 10. Compare asset upstream fractions with frozen P0
# ============================================================

lith_types <- c(
  "unconsolidated",
  "siliciclastic",
  "mixed_sedimentary",
  "carbonate",
  "metamorphic",
  "plutonic",
  "volcanic",
  "evaporite"
)

comparison_list <- list()

for (
  lith in lith_types
) {

  p0_name <- paste0(
    "p0__up_geo_",
    lith,
    "_frac"
  )

  asset_candidates <- c(
    paste0(
      "up_geo_",
      lith,
      "_frac"
    ),
    paste0(
      "upstream_geo_",
      lith,
      "_frac"
    )
  )

  asset_name <- intersect(
    asset_candidates,
    names(site_glim)
  )

  if (
    !p0_name %in%
    names(site_glim) ||
    length(asset_name) == 0L
  ) {
    next
  }

  asset_name <- asset_name[1]

  a <- safe_numeric(
    site_glim[[p0_name]]
  )

  b <- safe_numeric(
    site_glim[[asset_name]]
  )

  use <- is.finite(a) &
    is.finite(b) &
    site_glim$is_complete_p0

  difference <- b[
    use
  ] -
    a[
      use
    ]

  comparison_list[[
    length(comparison_list) + 1L
  ]] <- data.frame(

    lithology =
      lith,

    p0_field =
      p0_name,

    asset_field =
      asset_name,

    n_compared =
      sum(use),

    n_exact_equal =
      sum(
        abs(difference) <
          1e-12
      ),

    n_different =
      sum(
        abs(difference) >=
          1e-12
      ),

    max_abs_difference =
      if (
        length(difference) > 0L
      ) {
        max(
          abs(difference)
        )
      } else {
        NA_real_
      },

    mean_abs_difference =
      if (
        length(difference) > 0L
      ) {
        mean(
          abs(difference)
        )
      } else {
        NA_real_
      }
  )
}

upstream_validation <- if (
  length(comparison_list) > 0L
) {
  bind_rows(
    comparison_list
  )
} else {
  data.frame(
    lithology =
      character(0),

    p0_field =
      character(0),

    asset_field =
      character(0),

    n_compared =
      integer(0),

    n_exact_equal =
      integer(0),

    n_different =
      integer(0),

    max_abs_difference =
      numeric(0),

    mean_abs_difference =
      numeric(0),

    stringsAsFactors =
      FALSE
  )
}

write_csv(
  upstream_validation,
  file.path(
    out_dir,
    "asset_upstream_vs_frozen_p0_validation.csv"
  )
)

# Site-level mismatch details.

mismatch_rows <- list()

for (
  lith in lith_types
) {

  p0_name <- paste0(
    "p0__up_geo_",
    lith,
    "_frac"
  )

  asset_candidates <- c(
    paste0(
      "up_geo_",
      lith,
      "_frac"
    ),
    paste0(
      "upstream_geo_",
      lith,
      "_frac"
    )
  )

  asset_name <- intersect(
    asset_candidates,
    names(site_glim)
  )

  if (
    !p0_name %in%
    names(site_glim) ||
    length(asset_name) == 0L
  ) {
    next
  }

  asset_name <- asset_name[1]

  a <- safe_numeric(
    site_glim[[p0_name]]
  )

  b <- safe_numeric(
    site_glim[[asset_name]]
  )

  bad <- is.finite(a) &
    is.finite(b) &
    site_glim$is_complete_p0 &
    abs(
      a -
        b
    ) >=
    1e-12

  if (any(bad)) {

    mismatch_rows[[
      length(mismatch_rows) + 1L
    ]] <- data.frame(

      row_id =
        site_glim$row_id[
          bad
        ],

      HYBAS_JOIN_KEY =
        site_glim$HYBAS_JOIN_KEY[
          bad
        ],

      asset_region =
        site_glim$asset_region[
          bad
        ],

      lithology =
        lith,

      p0_value =
        a[
          bad
        ],

      asset_value =
        b[
          bad
        ],

      difference =
        b[
          bad
        ] -
        a[
          bad
        ]
    )
  }
}

mismatch_details <- if (
  length(mismatch_rows) > 0L
) {
  bind_rows(
    mismatch_rows
  )
} else {
  data.frame(
    row_id =
      integer(0),

    HYBAS_JOIN_KEY =
      character(0),

    asset_region =
      character(0),

    lithology =
      character(0),

    p0_value =
      numeric(0),

    asset_value =
      numeric(0),

    difference =
      numeric(0),

    stringsAsFactors =
      FALSE
  )
}

write_csv(
  mismatch_details,
  file.path(
    out_dir,
    "asset_upstream_vs_frozen_p0_mismatch_details.csv"
  )
)

# ============================================================
# 11. Save compact site-level candidate table
# ============================================================

candidate_keep <- unique(
  c(
    "row_id",
    "HYBAS_JOIN_KEY",
    "asset_region",
    "join_key_source",
    "matched_glim_key",
    "matched_any_local_lith",
    "matched_any_asset_up_lith",
    "is_complete_p0",
    "is_ge_075",
    "is_ge_080",
    "sr87_sr86",
    local_frac_fields,
    asset_up_frac_fields
  )
)

candidate_keep <- intersect(
  candidate_keep,
  names(site_glim)
)

site_candidate <- site_glim[
  ,
  candidate_keep,
  drop = FALSE
]

saveRDS(
  site_candidate,
  file.path(
    out_dir,
    "full_range_local_upstream_lithology_candidate.rds"
  )
)

write_csv(
  site_candidate,
  file.path(
    out_dir,
    "full_range_local_upstream_lithology_candidate.csv"
  )
)

# ============================================================
# 12. Existing P1-reuse outputs
# ============================================================

existing_p1_files <- unique(
  c(
    list.files(
      "data",
      recursive = TRUE,
      full.names = TRUE,
      pattern =
        "p1r|p1_reuse|reuse_predictor",
      ignore.case = TRUE
    ),

    list.files(
      "outputs",
      recursive = TRUE,
      full.names = TRUE,
      pattern =
        "p1r|p1_reuse|reuse_predictor",
      ignore.case = TRUE
    )
  )
)

existing_p1_inventory <- data.frame(

  path =
    existing_p1_files,

  size_mb =
    if (
      length(existing_p1_files) > 0L
    ) {
      file.info(
        existing_p1_files
      )$size /
        1024^2
    } else {
      numeric(0)
    },

  stringsAsFactors =
    FALSE
)

write_csv(
  existing_p1_inventory,
  file.path(
    out_dir,
    "existing_p1_reuse_file_inventory.csv"
  )
)

# ============================================================
# 13. Terminal report
# ============================================================

cat(
  "\n========================================\n"
)

cat(
  "R46 FULL-RANGE LOCAL LITHOLOGY AUDIT\n"
)

cat(
  "========================================\n"
)

cat(
  "\n===== GLiM REGIONAL SUMMARY =====\n"
)

print(
  glim_summary,
  row.names = FALSE
)

cat(
  "\n===== LOCAL FRACTION FIELDS =====\n"
)

print(
  local_frac_fields
)

cat(
  "\n===== ASSET UPSTREAM FRACTION FIELDS =====\n"
)

print(
  asset_up_frac_fields
)

cat(
  "\n===== FULL-RANGE MATCH SUMMARY =====\n"
)

print(
  match_summary,
  row.names = FALSE
)

cat(
  "\n===== ASSET UPSTREAM VS FROZEN P0 =====\n"
)

print(
  upstream_validation,
  row.names = FALSE
)

cat(
  "\nNumber of site/lithology mismatch rows: ",
  nrow(mismatch_details),
  "\n",
  sep = ""
)

cat(
  "\n===== TERRAIN ASSET SUMMARY =====\n"
)

print(
  terrain_summary,
  row.names = FALSE
)

cat(
  "\n===== EXISTING P1-REUSE FILES =====\n"
)

print(
  existing_p1_inventory,
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
