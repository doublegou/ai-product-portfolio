root <- normalizePath(
  getwd(),
  mustWork = TRUE
)

training_file <- file.path(
  root,
  "outputs",
  "r50b_feature_architecture",
  "integrated_model_table.rds"
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

age_file <- file.path(
  root,
  "outputs",
  "nrcan_age_hydrobasins_l6",
  "global_upstream",
  "l6_nrcan_age_local_upstream_global.rds"
)

legacy_reach_dir <- file.path(
  "/home",
  "zhangmeng",
  "projects",
  "sr_global",
  "data_processed",
  "global",
  "final_prediction",
  "river_predictions_by_region"
)

out_dir <- file.path(
  root,
  "outputs",
  "r58l_training_replay_key_audit"
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

  indices <- which(
    vapply(
      object,
      is.data.frame,
      logical(1)
    )
  )

  if (length(indices) == 0L) {
    stop(
      "No data-frame payload in: ",
      path
    )
  }

  row_counts <- vapply(
    object[indices],
    nrow,
    integer(1)
  )

  object[[indices[[which.max(row_counts)]]]]
}

extract_feature_names <- function(bundle) {
  direct_fields <- c(
    "feature_names",
    "predictor_names",
    "features",
    "predictors"
  )

  for (field in direct_fields) {
    value <- bundle[[field]]

    if (
      !is.null(value) &&
      length(value) > 0L
    ) {
      return(
        as.character(value)
      )
    }
  }

  model_fields <- c(
    "model",
    "final_model",
    "fit",
    "ranger_model"
  )

  for (field in model_fields) {
    model <- bundle[[field]]

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
    "Could not extract feature names."
  )
}

normalise_id <- function(values) {
  if (is.numeric(values)) {
    output <- format(
      values,
      scientific = FALSE,
      trim = TRUE
    )
  } else {
    output <- trimws(
      as.character(values)
    )
  }

  output[
    is.na(values) |
    output == ""
  ] <- NA_character_

  output
}

training <- read_largest_table(
  training_file
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

union_features <- unique(
  c(
    full_features,
    core_features
  )
)

missing_model_features <- setdiff(
  union_features,
  names(training)
)

feature_rows <- lapply(
  union_features,
  function(feature) {
    if (!feature %in% names(training)) {
      return(
        data.frame(
          feature = feature,
          in_full = feature %in% full_features,
          in_core = feature %in% core_features,
          present_in_training = FALSE,
          numeric = FALSE,
          n_finite = 0L,
          n_missing = nrow(training),
          stringsAsFactors = FALSE
        )
      )
    }

    values <- training[[feature]]
    numeric_feature <- is.numeric(values)

    finite <- if (numeric_feature) {
      is.finite(values)
    } else {
      !is.na(values)
    }

    data.frame(
      feature = feature,
      in_full = feature %in% full_features,
      in_core = feature %in% core_features,
      present_in_training = TRUE,
      numeric = numeric_feature,
      n_finite = sum(finite),
      n_missing = sum(!finite),
      stringsAsFactors = FALSE
    )
  }
)

feature_completeness <- do.call(
  rbind,
  feature_rows
)

reach_universe <- character()
reach_inventory_rows <- list()
reach_inventory_index <- 0L

for (region in regions) {
  path <- file.path(
    legacy_reach_dir,
    paste0(
      "river_predictions_",
      region,
      ".rds"
    )
  )

  table <- read_largest_table(
    path
  )

  key_columns <- grep(
    "hyriv|hydroriver|reach[_]?id",
    names(table),
    value = TRUE,
    ignore.case = TRUE
  )

  if (length(key_columns) == 0L) {
    stop(
      "No reach key columns found in ",
      path
    )
  }

  for (column in key_columns) {
    values <- normalise_id(
      table[[column]]
    )

    reach_universe <- c(
      reach_universe,
      values[
        !is.na(values)
      ]
    )

    reach_inventory_index <-
      reach_inventory_index + 1L

    reach_inventory_rows[[reach_inventory_index]] <- data.frame(
      region = region,
      path = path,
      key_column = column,
      n_rows = nrow(table),
      n_nonmissing = sum(
        !is.na(values)
      ),
      n_unique = length(
        unique(
          values[
            !is.na(values)
          ]
        )
      ),
      stringsAsFactors = FALSE
    )
  }

  rm(table)
  invisible(gc())
}

reach_universe <- unique(
  reach_universe
)

age_table <- read_largest_table(
  age_file
)

basin_key_columns <- grep(
  "hybas|hydrobasin",
  names(age_table),
  value = TRUE,
  ignore.case = TRUE
)

if (length(basin_key_columns) == 0L) {
  stop(
    "No basin key columns found in age table."
  )
}

basin_universe <- unique(
  unlist(
    lapply(
      basin_key_columns,
      function(column) {
        values <- normalise_id(
          age_table[[column]]
        )

        values[
          !is.na(values)
        ]
      }
    ),
    use.names = FALSE
  )
)

training_reach_candidates <- grep(
  "hyriv|hydroriver|reach[_]?id",
  names(training),
  value = TRUE,
  ignore.case = TRUE
)

training_basin_candidates <- grep(
  "hybas|hydrobasin",
  names(training),
  value = TRUE,
  ignore.case = TRUE
)

audit_key <- function(column, key_type, universe) {
  values <- normalise_id(
    training[[column]]
  )

  nonmissing <- !is.na(values)
  matched <- nonmissing &
    values %in%
    universe

  data.frame(
    key_type = key_type,
    training_column = column,
    n_training_rows = nrow(training),
    n_nonmissing = sum(nonmissing),
    n_missing = sum(!nonmissing),
    n_unique = length(
      unique(
        values[
          nonmissing
        ]
      )
    ),
    duplicate_training_rows =
      sum(nonmissing) -
      length(
        unique(
          values[
            nonmissing
          ]
        )
      ),
    n_matched = sum(matched),
    n_unmatched_nonmissing =
      sum(
        nonmissing &
        !matched
      ),
    match_fraction = if (
      sum(nonmissing) > 0L
    ) {
      sum(matched) /
        sum(nonmissing)
    } else {
      NA_real_
    },
    exact_complete_match =
      sum(!nonmissing) == 0L &&
      sum(
        nonmissing &
        !matched
      ) == 0L,
    stringsAsFactors = FALSE
  )
}

key_rows <- list()
key_index <- 0L

for (column in training_reach_candidates) {
  key_index <- key_index + 1L

  key_rows[[key_index]] <- audit_key(
    column,
    "reach",
    reach_universe
  )
}

for (column in training_basin_candidates) {
  key_index <- key_index + 1L

  key_rows[[key_index]] <- audit_key(
    column,
    "basin",
    basin_universe
  )
}

if (length(key_rows) == 0L) {
  stop(
    "No candidate training keys found."
  )
}

key_audit <- do.call(
  rbind,
  key_rows
)

key_audit <- key_audit[
  order(
    key_audit$key_type,
    !key_audit$exact_complete_match,
    -key_audit$match_fraction,
    key_audit$n_missing,
    key_audit$training_column
  ),
  ,
  drop = FALSE
]

exact_reach_keys <- key_audit$training_column[
  key_audit$key_type ==
    "reach" &
  key_audit$exact_complete_match
]

exact_basin_keys <- key_audit$training_column[
  key_audit$key_type ==
    "basin" &
  key_audit$exact_complete_match
]

replay_key_ready <-
  length(exact_reach_keys) > 0L &&
  length(exact_basin_keys) > 0L &&
  length(missing_model_features) == 0L

write.csv(
  key_audit,
  file.path(
    out_dir,
    "training_key_candidate_audit.csv"
  ),
  row.names = FALSE
)

write.csv(
  feature_completeness,
  file.path(
    out_dir,
    "model_feature_training_completeness.csv"
  ),
  row.names = FALSE
)

write.csv(
  do.call(
    rbind,
    reach_inventory_rows
  ),
  file.path(
    out_dir,
    "regional_reach_key_inventory.csv"
  ),
  row.names = FALSE
)

writeLines(
  exact_reach_keys,
  file.path(
    out_dir,
    "exact_reach_keys.txt"
  )
)

writeLines(
  exact_basin_keys,
  file.path(
    out_dir,
    "exact_basin_keys.txt"
  )
)

writeLines(
  missing_model_features,
  file.path(
    out_dir,
    "missing_model_features.txt"
  )
)

summary_lines <- c(
  "R58L TRAINING REPLAY KEY AUDIT",
  "================================",
  "",
  paste0(
    "Training rows: ",
    nrow(training)
  ),
  paste0(
    "FULL features: ",
    length(full_features)
  ),
  paste0(
    "CORE features: ",
    length(core_features)
  ),
  paste0(
    "Unique feature union: ",
    length(union_features)
  ),
  paste0(
    "Model features absent from training table: ",
    length(missing_model_features)
  ),
  paste0(
    "Training reach-key candidates: ",
    length(training_reach_candidates)
  ),
  paste0(
    "Training basin-key candidates: ",
    length(training_basin_candidates)
  ),
  paste0(
    "Exact complete reach keys: ",
    length(exact_reach_keys)
  ),
  paste0(
    "Exact complete basin keys: ",
    length(exact_basin_keys)
  ),
  paste0(
    "Reach-key universe size: ",
    length(reach_universe)
  ),
  paste0(
    "Basin-key universe size: ",
    length(basin_universe)
  ),
  paste0(
    "Training deployment replay key ready: ",
    replay_key_ready
  ),
  "",
  "STATUS: R58L TRAINING REPLAY KEY AUDIT PASSED"
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
  "===== TRAINING KEY CANDIDATES =====\n"
)

print(
  key_audit,
  row.names = FALSE
)

cat(
  "\n===== MODEL FEATURE COMPLETENESS =====\n"
)

print(
  feature_completeness,
  row.names = FALSE
)
