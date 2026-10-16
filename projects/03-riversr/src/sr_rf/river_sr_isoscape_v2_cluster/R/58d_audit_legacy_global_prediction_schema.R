root <- normalizePath(
  getwd(),
  mustWork = TRUE
)

legacy_root <- file.path(
  "/home",
  "zhangmeng",
  "projects",
  "sr_global"
)

global_prediction_file <- file.path(
  legacy_root,
  "data_processed",
  "global",
  "final_prediction",
  "global_river_predictions_RF_QRF.rds"
)

map_attribute_file <- file.path(
  legacy_root,
  "data_processed",
  "global",
  "final_prediction",
  "global_river_prediction_map_attributes.rds"
)

region_directory <- file.path(
  legacy_root,
  "data_processed",
  "global",
  "final_prediction",
  "river_predictions_by_region"
)

full_bundle_file <- file.path(
  root,
  "outputs",
  "r56_final_models",
  "models",
  "M_FULL_MECHANISTIC_final_model_bundle.rds"
)

core_bundle_file <- file.path(
  root,
  "outputs",
  "r56_final_models",
  "models",
  "M_CORE_MECHANISTIC_final_model_bundle.rds"
)

out_dir <- file.path(
  root,
  "outputs",
  "r58d_legacy_global_schema_audit"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

required_files <- c(
  global_prediction_file,
  map_attribute_file,
  full_bundle_file,
  core_bundle_file
)

missing_files <- required_files[
  !file.exists(
    required_files
  )
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

unwrap_largest_table <- function(object) {
  if (is.data.frame(object)) {
    return(object)
  }

  if (!is.list(object)) {
    return(NULL)
  }

  table_indices <- which(
    vapply(
      object,
      is.data.frame,
      logical(1)
    )
  )

  if (length(table_indices) == 0L) {
    return(NULL)
  }

  table_rows <- vapply(
    object[table_indices],
    nrow,
    integer(1)
  )

  selected_index <- table_indices[
    which.max(
      table_rows
    )
  ]

  object[[selected_index]]
}

extract_feature_names <- function(bundle) {
  direct_candidates <- c(
    "feature_names",
    "predictor_names",
    "features",
    "predictors"
  )

  for (candidate in direct_candidates) {
    value <- bundle[[candidate]]

    if (
      !is.null(value) &&
      length(value) > 0L
    ) {
      return(
        as.character(value)
      )
    }
  }

  model_candidates <- c(
    "model",
    "final_model",
    "fit",
    "ranger_model"
  )

  for (candidate in model_candidates) {
    model <- bundle[[candidate]]

    if (
      !is.null(model) &&
      !is.null(
        model$forest$independent.variable.names
      )
    ) {
      return(
        as.character(
          model$forest$independent.variable.names
        )
      )
    }
  }

  if (
    !is.null(
      bundle$forest$independent.variable.names
    )
  ) {
    return(
      as.character(
        bundle$forest$independent.variable.names
      )
    )
  }

  stop(
    "Could not identify feature names in bundle. Bundle names: ",
    paste(
      names(bundle),
      collapse = ", "
    )
  )
}

basic_inventory <- function(
  object,
  table,
  label,
  path
) {
  data.frame(
    label =
      label,

    path =
      path,

    file_size_mb =
      file.info(path)$size /
      1024^2,

    object_class =
      paste(
        class(object),
        collapse = ";"
      ),

    list_names =
      if (is.list(object)) {
        paste(
          names(object),
          collapse = "|"
        )
      } else {
        NA_character_
      },

    table_found =
      !is.null(table),

    n_rows =
      if (!is.null(table)) {
        nrow(table)
      } else {
        NA_integer_
      },

    n_columns =
      if (!is.null(table)) {
        ncol(table)
      } else {
        NA_integer_
      },

    stringsAsFactors =
      FALSE
  )
}

audit_candidate_keys <- function(
  table,
  table_label
) {
  if (is.null(table)) {
    return(
      data.frame()
    )
  }

  candidate_names <- grep(
    "HYRIV|RIV_ID|REACH|river_id|ORD_FLOW|region",
    names(table),
    value = TRUE,
    ignore.case = TRUE
  )

  if (length(candidate_names) == 0L) {
    return(
      data.frame()
    )
  }

  rows <- lapply(
    candidate_names,
    function(column_name) {
      values <- table[[column_name]]

      nonmissing <- values[
        !is.na(values)
      ]

      data.frame(
        table =
          table_label,

        column =
          column_name,

        class =
          paste(
            class(values),
            collapse = ";"
          ),

        n_rows =
          length(values),

        n_nonmissing =
          length(nonmissing),

        any_duplicates =
          if (length(nonmissing) > 0L) {
            anyDuplicated(nonmissing) >
              0L
          } else {
            NA
          },

        example_first =
          if (length(nonmissing) > 0L) {
            as.character(
              nonmissing[[1L]]
            )
          } else {
            NA_character_
          },

        stringsAsFactors =
          FALSE
      )
    }
  )

  do.call(
    rbind,
    rows
  )
}

build_feature_coverage <- function(
  model_name,
  feature_names,
  global_columns,
  map_columns,
  region_columns
) {
  data.frame(
    model_name =
      model_name,

    feature =
      feature_names,

    in_global_prediction =
      feature_names %in%
      global_columns,

    in_map_attributes =
      feature_names %in%
      map_columns,

    in_region_tables =
      feature_names %in%
      region_columns,

    available_anywhere =
      feature_names %in%
      unique(
        c(
          global_columns,
          map_columns,
          region_columns
        )
      ),

    stringsAsFactors =
      FALSE
  )
}

cat(
  "Reading global prediction object...\n"
)

global_object <- readRDS(
  global_prediction_file
)

global_table <- unwrap_largest_table(
  global_object
)

if (is.null(global_table)) {
  stop(
    "No data-frame-like payload found in global prediction object."
  )
}

global_inventory <- basic_inventory(
  object =
    global_object,

  table =
    global_table,

  label =
    "global_river_predictions_RF_QRF",

  path =
    global_prediction_file
)

global_columns <- names(
  global_table
)

global_key_audit <- audit_candidate_keys(
  global_table,
  "global_prediction"
)

writeLines(
  global_columns,
  file.path(
    out_dir,
    "global_prediction_columns.txt"
  )
)

rm(
  global_object,
  global_table
)

invisible(
  gc()
)

cat(
  "Reading map attribute object...\n"
)

map_object <- readRDS(
  map_attribute_file
)

map_table <- unwrap_largest_table(
  map_object
)

if (is.null(map_table)) {
  stop(
    "No data-frame-like payload found in map attribute object."
  )
}

map_inventory <- basic_inventory(
  object =
    map_object,

  table =
    map_table,

  label =
    "global_river_prediction_map_attributes",

  path =
    map_attribute_file
)

map_columns <- names(
  map_table
)

map_key_audit <- audit_candidate_keys(
  map_table,
  "map_attributes"
)

writeLines(
  map_columns,
  file.path(
    out_dir,
    "map_attribute_columns.txt"
  )
)

rm(
  map_object,
  map_table
)

invisible(
  gc()
)

cat(
  "Auditing regional prediction files...\n"
)

region_files <- list.files(
  region_directory,
  pattern = "\\.[Rr][Dd][Ss]$",
  full.names = TRUE
)

region_files <- sort(
  region_files
)

if (length(region_files) == 0L) {
  stop(
    "No regional prediction RDS files found."
  )
}

region_inventory_list <- list()
region_column_sets <- list()

for (index in seq_along(region_files)) {
  region_file <- region_files[[index]]

  region_object <- readRDS(
    region_file
  )

  region_table <- unwrap_largest_table(
    region_object
  )

  if (is.null(region_table)) {
    stop(
      "No table found in regional object: ",
      region_file
    )
  }

  region_label <- sub(
    "\\.[Rr][Dd][Ss]$",
    "",
    basename(region_file)
  )

  region_inventory_list[[index]] <-
    basic_inventory(
      object =
        region_object,

      table =
        region_table,

      label =
        region_label,

      path =
        region_file
    )

  region_column_sets[[index]] <-
    names(
      region_table
    )

  rm(
    region_object,
    region_table
  )

  invisible(
    gc()
  )
}

region_inventory <- do.call(
  rbind,
  region_inventory_list
)

region_columns <- unique(
  unlist(
    region_column_sets
  )
)

all_inventory <- rbind(
  global_inventory,
  map_inventory,
  region_inventory
)

full_bundle <- readRDS(
  full_bundle_file
)

core_bundle <- readRDS(
  core_bundle_file
)

full_features <- extract_feature_names(
  full_bundle
)

core_features <- extract_feature_names(
  core_bundle
)

full_coverage <- build_feature_coverage(
  model_name =
    "M_FULL_MECHANISTIC",

  feature_names =
    full_features,

  global_columns =
    global_columns,

  map_columns =
    map_columns,

  region_columns =
    region_columns
)

core_coverage <- build_feature_coverage(
  model_name =
    "M_CORE_MECHANISTIC",

  feature_names =
    core_features,

  global_columns =
    global_columns,

  map_columns =
    map_columns,

  region_columns =
    region_columns
)

key_audit <- rbind(
  global_key_audit,
  map_key_audit
)

global_map_overlap <- data.frame(
  metric =
    c(
      "global_column_count",
      "map_attribute_column_count",
      "shared_column_count",
      "global_only_column_count",
      "map_only_column_count"
    ),

  value =
    c(
      length(
        global_columns
      ),
      length(
        map_columns
      ),
      length(
        intersect(
          global_columns,
          map_columns
        )
      ),
      length(
        setdiff(
          global_columns,
          map_columns
        )
      ),
      length(
        setdiff(
          map_columns,
          global_columns
        )
      )
    ),

  stringsAsFactors =
    FALSE
)

write.csv(
  all_inventory,
  file.path(
    out_dir,
    "legacy_global_object_inventory.csv"
  ),
  row.names = FALSE
)

write.csv(
  region_inventory,
  file.path(
    out_dir,
    "regional_prediction_inventory.csv"
  ),
  row.names = FALSE
)

write.csv(
  full_coverage,
  file.path(
    out_dir,
    "full_feature_coverage.csv"
  ),
  row.names = FALSE
)

write.csv(
  core_coverage,
  file.path(
    out_dir,
    "core_feature_coverage.csv"
  ),
  row.names = FALSE
)

write.csv(
  key_audit,
  file.path(
    out_dir,
    "candidate_join_key_audit.csv"
  ),
  row.names = FALSE
)

write.csv(
  global_map_overlap,
  file.path(
    out_dir,
    "global_map_column_overlap.csv"
  ),
  row.names = FALSE
)

writeLines(
  setdiff(
    full_features,
    unique(
      c(
        global_columns,
        map_columns,
        region_columns
      )
    )
  ),
  file.path(
    out_dir,
    "full_missing_features.txt"
  )
)

writeLines(
  setdiff(
    core_features,
    unique(
      c(
        global_columns,
        map_columns,
        region_columns
      )
    )
  ),
  file.path(
    out_dir,
    "core_missing_features.txt"
  )
)

full_available <- sum(
  full_coverage$available_anywhere
)

core_available <- sum(
  core_coverage$available_anywhere
)

regional_total_rows <- sum(
  region_inventory$n_rows
)

summary_lines <- c(
  "R58D LEGACY GLOBAL PREDICTION SCHEMA AUDIT",
  "==========================================",
  "",
  paste0(
    "Global prediction rows: ",
    global_inventory$n_rows
  ),
  paste0(
    "Global prediction columns: ",
    global_inventory$n_columns
  ),
  paste0(
    "Map attribute rows: ",
    map_inventory$n_rows
  ),
  paste0(
    "Map attribute columns: ",
    map_inventory$n_columns
  ),
  paste0(
    "Regional files: ",
    nrow(region_inventory)
  ),
  paste0(
    "Regional rows summed: ",
    regional_total_rows
  ),
  "",
  paste0(
    "FULL exact features available: ",
    full_available,
    "/",
    length(full_features)
  ),
  paste0(
    "CORE exact features available: ",
    core_available,
    "/",
    length(core_features)
  ),
  paste0(
    "FULL deployment ready by exact names: ",
    all(
      full_coverage$available_anywhere
    )
  ),
  paste0(
    "CORE deployment ready by exact names: ",
    all(
      core_coverage$available_anywhere
    )
  ),
  "",
  "STATUS: R58D LEGACY GLOBAL SCHEMA AUDIT PASSED"
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
  "===== OBJECT INVENTORY =====\n"
)

print(
  all_inventory[
    ,
    c(
      "label",
      "file_size_mb",
      "n_rows",
      "n_columns"
    )
  ],
  row.names = FALSE
)

cat(
  "\n===== FULL MISSING FEATURES =====\n"
)

print(
  full_coverage[
    !full_coverage$available_anywhere,
    c(
      "feature",
      "in_global_prediction",
      "in_map_attributes",
      "in_region_tables"
    )
  ],
  row.names = FALSE
)

cat(
  "\n===== CORE MISSING FEATURES =====\n"
)

print(
  core_coverage[
    !core_coverage$available_anywhere,
    c(
      "feature",
      "in_global_prediction",
      "in_map_attributes",
      "in_region_tables"
    )
  ],
  row.names = FALSE
)

cat(
  "\n===== CANDIDATE JOIN KEYS =====\n"
)

print(
  key_audit,
  row.names = FALSE
)
