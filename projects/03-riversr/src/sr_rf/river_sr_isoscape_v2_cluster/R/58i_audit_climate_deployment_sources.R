root <- normalizePath(
  getwd(),
  mustWork = TRUE
)

candidate_file <- file.path(
  root,
  "outputs",
  "r58h_deployment_source_manifest",
  "base_variable_source_candidates.csv"
)

out_dir <- file.path(
  root,
  "outputs",
  "r58i_climate_source_audit"
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

read_largest_table <- function(path) {
  object <- readRDS(path)

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
    which.max(table_rows)
  ]

  object[[selected_index]]
}

find_key_column <- function(columns) {
  preferred <- c(
    "HYBAS_ID",
    "hybas_id",
    "HYBAS_KEY",
    "hybas_key"
  )

  matched <- preferred[
    preferred %in%
      columns
  ]

  if (length(matched) == 0L) {
    return(NA_character_)
  }

  matched[[1L]]
}

candidates <- read.csv(
  candidate_file,
  stringsAsFactors = FALSE,
  check.names = FALSE
)

candidates$valid_join_key <- as.logical(
  candidates$valid_join_key
)

candidates$has_hybas_key <- as.logical(
  candidates$has_hybas_key
)

climate_candidates <- candidates[
  candidates$base_variable %in%
    climate_variables &
  candidates$valid_join_key &
  candidates$has_hybas_key,
  ,
  drop = FALSE
]

candidate_paths <- unique(
  climate_candidates$path
)

audit_rows <- list()
variable_rows <- list()
audit_index <- 0L
variable_index <- 0L

for (path in candidate_paths) {
  if (!file.exists(path)) {
    next
  }

  table <- tryCatch(
    read_largest_table(path),
    error = function(error) {
      NULL
    }
  )

  if (is.null(table)) {
    next
  }

  columns <- names(table)
  key_column <- find_key_column(columns)

  if (is.na(key_column)) {
    rm(table)
    invisible(gc())
    next
  }

  key_values <- as.character(
    table[[key_column]]
  )

  nonmissing_keys <- key_values[
    !is.na(key_values) &
    nzchar(key_values)
  ]

  variables_present <- intersect(
    climate_variables,
    columns
  )

  path_records <- climate_candidates[
    climate_candidates$path ==
      path,
    ,
    drop = FALSE
  ]

  regions_reported <- sort(
    unique(
      path_records$region
    )
  )

  region_label <- paste(
    regions_reported,
    collapse = "|"
  )

  path_lower <- tolower(path)

  site_like <- grepl(
    paste0(
      "site|observation|snap|",
      "world_river_water|",
      "primary_[0-9]|",
      "model2_df"
    ),
    path_lower
  )

  prediction_like <- grepl(
    paste0(
      "final_prediction|",
      "river_prediction_chunks|",
      "river_predictions_"
    ),
    path_lower
  )

  all_variables_present <- all(
    climate_variables %in%
      columns
  )

  key_unique <- length(nonmissing_keys) ==
    length(
      unique(nonmissing_keys)
    )

  global_l6_shape <-
    "global" %in%
      regions_reported &&
    nrow(table) >= 15000L &&
    nrow(table) <= 18000L

  regional_shape <-
    any(
      regions %in%
        regions_reported
    ) &&
    nrow(table) > 0L &&
    nrow(table) < 10000L

  deployment_candidate <-
    all_variables_present &&
    key_unique &&
    !site_like &&
    !prediction_like &&
    (
      global_l6_shape |
      regional_shape
    )

  finite_counts <- if (
    length(variables_present) > 0L
  ) {
    vapply(
      variables_present,
      function(variable) {
        values <- table[[variable]]

        if (is.numeric(values)) {
          sum(
            is.finite(values)
          )
        } else {
          sum(
            !is.na(values)
          )
        }
      },
      integer(1)
    )
  } else {
    integer()
  }

  minimum_finite <- if (
    length(finite_counts) > 0L
  ) {
    min(finite_counts)
  } else {
    0L
  }

  audit_index <- audit_index + 1L

  audit_rows[[audit_index]] <- data.frame(
    path = path,
    region = region_label,
    source_role = paste(
      sort(
        unique(
          path_records$source_role
        )
      ),
      collapse = "|"
    ),
    n_rows = nrow(table),
    n_columns = ncol(table),
    key_column = key_column,
    key_nonmissing = length(nonmissing_keys),
    key_unique_count = length(
      unique(nonmissing_keys)
    ),
    key_duplicates = length(nonmissing_keys) -
      length(
        unique(nonmissing_keys)
      ),
    key_unique = key_unique,
    climate_variables_present =
      length(variables_present),
    all_climate_variables_present =
      all_variables_present,
    minimum_variable_finite =
      minimum_finite,
    site_like = site_like,
    prediction_like = prediction_like,
    global_l6_shape = global_l6_shape,
    regional_shape = regional_shape,
    deployment_candidate =
      deployment_candidate,
    stringsAsFactors = FALSE
  )

  for (variable in climate_variables) {
    variable_index <- variable_index + 1L

    present <- variable %in%
      columns

    finite_count <- 0L

    if (present) {
      values <- table[[variable]]

      finite_count <- if (
        is.numeric(values)
      ) {
        sum(
          is.finite(values)
        )
      } else {
        sum(
          !is.na(values)
        )
      }
    }

    variable_rows[[variable_index]] <- data.frame(
      path = path,
      region = region_label,
      variable = variable,
      present = present,
      finite_count = finite_count,
      n_rows = nrow(table),
      finite_fraction = if (
        nrow(table) > 0L
      ) {
        finite_count /
          nrow(table)
      } else {
        NA_real_
      },
      stringsAsFactors = FALSE
    )
  }

  rm(table)
  invisible(gc())
}

if (length(audit_rows) == 0L) {
  stop(
    "No climate candidate tables could be audited."
  )
}

path_audit <- do.call(
  rbind,
  audit_rows
)

variable_audit <- do.call(
  rbind,
  variable_rows
)

path_audit <- path_audit[
  order(
    !path_audit$deployment_candidate,
    !path_audit$all_climate_variables_present,
    !path_audit$key_unique,
    abs(
      path_audit$n_rows -
        16397L
    ),
    path_audit$path
  ),
  ,
  drop = FALSE
]

global_candidates <- path_audit[
  path_audit$deployment_candidate &
  path_audit$global_l6_shape,
  ,
  drop = FALSE
]

regional_candidates <- path_audit[
  path_audit$deployment_candidate &
  path_audit$regional_shape,
  ,
  drop = FALSE
]

regional_candidate_regions <- unique(
  unlist(
    strsplit(
      regional_candidates$region,
      split = "\\|"
    )
  )
)

complete_regional_set <- all(
  regions %in%
    regional_candidate_regions
)

climate_source_resolved <-
  nrow(global_candidates) ==
    1L |
  complete_regional_set

write.csv(
  path_audit,
  file.path(
    out_dir,
    "climate_candidate_path_audit.csv"
  ),
  row.names = FALSE
)

write.csv(
  variable_audit,
  file.path(
    out_dir,
    "climate_candidate_variable_audit.csv"
  ),
  row.names = FALSE
)

write.csv(
  global_candidates,
  file.path(
    out_dir,
    "valid_global_l6_candidates.csv"
  ),
  row.names = FALSE
)

write.csv(
  regional_candidates,
  file.path(
    out_dir,
    "valid_regional_candidates.csv"
  ),
  row.names = FALSE
)

summary_lines <- c(
  "R58I CLIMATE DEPLOYMENT SOURCE AUDIT",
  "====================================",
  "",
  paste0(
    "Climate variables required: ",
    length(climate_variables)
  ),
  paste0(
    "Candidate paths audited: ",
    nrow(path_audit)
  ),
  paste0(
    "Exact global L6 candidates: ",
    nrow(global_candidates)
  ),
  paste0(
    "Exact regional candidate files: ",
    nrow(regional_candidates)
  ),
  paste0(
    "Regional candidate regions covered: ",
    sum(
      regions %in%
        regional_candidate_regions
    ),
    "/",
    length(regions)
  ),
  paste0(
    "Complete regional source set: ",
    complete_regional_set
  ),
  paste0(
    "Climate deployment source resolved: ",
    climate_source_resolved
  ),
  "",
  "STATUS: R58I CLIMATE DEPLOYMENT SOURCE AUDIT PASSED"
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
  "===== DEPLOYMENT CANDIDATES =====\n"
)

print(
  path_audit[
    path_audit$deployment_candidate,
    ,
    drop = FALSE
  ],
  row.names = FALSE
)

cat(
  "\n===== TOP 30 AUDITED PATHS =====\n"
)

print(
  path_audit[
    seq_len(
      min(
        30L,
        nrow(path_audit)
      )
    ),
    ,
    drop = FALSE
  ],
  row.names = FALSE
)
