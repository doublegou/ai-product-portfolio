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

legacy_data_root <- file.path(
  legacy_root,
  "data_processed"
)

global_prediction_file <- file.path(
  legacy_data_root,
  "global",
  "final_prediction",
  "global_river_predictions_RF_QRF.rds"
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
  "r58e_legacy_predictor_source_trace"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

extract_feature_names <- function(bundle) {
  candidates <- c(
    "feature_names",
    "predictor_names",
    "features",
    "predictors"
  )

  for (candidate in candidates) {
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
    "Feature names could not be extracted."
  )
}

table_payloads <- function(
  object,
  object_path = "root"
) {
  output <- list()

  if (is.data.frame(object)) {
    output[[object_path]] <- object
    return(output)
  }

  if (!is.list(object)) {
    return(output)
  }

  object_names <- names(object)

  if (is.null(object_names)) {
    object_names <- paste0(
      "element_",
      seq_along(object)
    )
  }

  for (index in seq_along(object)) {
    element <- object[[index]]

    if (is.data.frame(element)) {
      output[[paste0(
        object_path,
        "$",
        object_names[[index]]
      )]] <- element
    }
  }

  output
}

normalise_feature_alias <- function(feature) {
  sub(
    "^(p0__|p1r__)",
    "",
    feature
  )
}

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

global_prediction <- readRDS(
  global_prediction_file
)

if (!is.data.frame(global_prediction)) {
  stop(
    "Legacy global prediction object is not a data frame."
  )
}

global_columns <- names(
  global_prediction
)

rm(
  global_prediction
)

invisible(
  gc()
)

rds_files <- list.files(
  legacy_data_root,
  pattern = "\\.[Rr][Dd][Ss]$",
  recursive = TRUE,
  full.names = TRUE
)

file_info <- file.info(
  rds_files
)

path_keywords <- grepl(
  paste(
    c(
      "global",
      "river",
      "reach",
      "hydro",
      "basin",
      "predict",
      "climate",
      "soil",
      "geolog",
      "lith",
      "upstream"
    ),
    collapse = "|"
  ),
  rds_files,
  ignore.case = TRUE
)

size_candidate <-
  file_info$size >=
  5 * 1024^2

candidate_files <- rds_files[
  path_keywords |
    size_candidate
]

candidate_files <- sort(
  unique(
    candidate_files
  )
)

schema_rows <- list()
column_registry <- list()
row_index <- 0L

for (file_path in candidate_files) {
  cat(
    "Inspecting: ",
    file_path,
    "\n",
    sep = ""
  )

  result <- tryCatch(
    readRDS(
      file_path
    ),
    error = function(error) {
      error
    }
  )

  if (inherits(result, "error")) {
    row_index <- row_index + 1L

    schema_rows[[row_index]] <- data.frame(
      file_path =
        file_path,

      payload =
        NA_character_,

      file_size_mb =
        file.info(file_path)$size /
        1024^2,

      status =
        "read_failed",

      object_class =
        NA_character_,

      n_rows =
        NA_integer_,

      n_columns =
        NA_integer_,

      has_hyriv_id =
        NA,

      has_hybas_id =
        NA,

      predictor_token_count =
        NA_integer_,

      error_message =
        conditionMessage(result),

      stringsAsFactors =
        FALSE
    )

    next
  }

  payloads <- table_payloads(
    result
  )

  if (length(payloads) == 0L) {
    row_index <- row_index + 1L

    schema_rows[[row_index]] <- data.frame(
      file_path =
        file_path,

      payload =
        NA_character_,

      file_size_mb =
        file.info(file_path)$size /
        1024^2,

      status =
        "no_table_payload",

      object_class =
        paste(
          class(result),
          collapse = ";"
        ),

      n_rows =
        NA_integer_,

      n_columns =
        NA_integer_,

      has_hyriv_id =
        FALSE,

      has_hybas_id =
        FALSE,

      predictor_token_count =
        0L,

      error_message =
        NA_character_,

      stringsAsFactors =
        FALSE
    )

    rm(result)
    invisible(gc())
    next
  }

  for (payload_name in names(payloads)) {
    table <- payloads[[payload_name]]
    columns <- names(table)

    predictor_columns <- grep(
      paste(
        c(
          "log_DIS",
          "log_UPLAND",
          "log_CATCH",
          "ORD_",
          "up_geo",
          "local_geo",
          "bio1",
          "bio4",
          "bio12",
          "bio15",
          "ai_ratio",
          "et0",
          "elevation",
          "soil",
          "clay",
          "lith",
          "longitude",
          "latitude"
        ),
        collapse = "|"
      ),
      columns,
      value = TRUE,
      ignore.case = TRUE
    )

    registry_key <- paste(
      file_path,
      payload_name,
      sep = "::"
    )

    column_registry[[registry_key]] <- columns

    row_index <- row_index + 1L

    schema_rows[[row_index]] <- data.frame(
      file_path =
        file_path,

      payload =
        payload_name,

      file_size_mb =
        file.info(file_path)$size /
        1024^2,

      status =
        "read_ok",

      object_class =
        paste(
          class(table),
          collapse = ";"
        ),

      n_rows =
        nrow(table),

      n_columns =
        ncol(table),

      has_hyriv_id =
        any(
          tolower(columns) %in%
            c(
              "hyriv_id",
              "hyriv_key"
            )
        ),

      has_hybas_id =
        any(
          tolower(columns) %in%
            c(
              "hybas_id",
              "hybas_key"
            )
        ),

      predictor_token_count =
        length(
          predictor_columns
        ),

      error_message =
        NA_character_,

      stringsAsFactors =
        FALSE
    )
  }

  rm(
    result,
    payloads
  )

  invisible(
    gc()
  )
}

schema_audit <- do.call(
  rbind,
  schema_rows
)

schema_audit <- schema_audit[
  order(
    -schema_audit$n_rows,
    -schema_audit$predictor_token_count,
    -schema_audit$file_size_mb
  ),
  ,
  drop = FALSE
]

all_source_columns <- unique(
  unlist(
    column_registry,
    use.names = FALSE
  )
)

build_feature_trace <- function(
  model_name,
  feature_names
) {
  aliases <- vapply(
    feature_names,
    normalise_feature_alias,
    character(1)
  )

  direct_exact <-
    feature_names %in%
    global_columns

  direct_alias <-
    aliases %in%
    global_columns

  available_source_exact <-
    feature_names %in%
    all_source_columns

  available_source_alias <-
    aliases %in%
    all_source_columns

  derivation_type <- ifelse(
    direct_exact,
    "global_exact",
    ifelse(
      direct_alias,
      "global_prefix_alias",
      ifelse(
        feature_names %in%
          c(
            "p0__sp_x",
            "p0__sp_y",
            "p0__sp_z"
          ) &
          all(
            c(
              "longitude",
              "latitude"
            ) %in%
            global_columns
          ),
        "derive_from_coordinates",
        ifelse(
          available_source_exact,
          "legacy_source_exact",
          ifelse(
            available_source_alias,
            "legacy_source_prefix_alias",
            ifelse(
              grepl(
                "^local_geo_age|^up_geo_age|^local_geo_frac|^up_geo_frac",
                feature_names
              ),
              "join_current_l6_age_asset",
              "not_yet_located"
            )
          )
        )
      )
    )
  )

  data.frame(
    model_name =
      model_name,

    feature =
      feature_names,

    alias =
      aliases,

    in_global_exact =
      direct_exact,

    in_global_alias =
      direct_alias,

    in_legacy_source_exact =
      available_source_exact,

    in_legacy_source_alias =
      available_source_alias,

    derivation_type =
      derivation_type,

    stringsAsFactors =
      FALSE
  )
}

full_trace <- build_feature_trace(
  "M_FULL_MECHANISTIC",
  full_features
)

core_trace <- build_feature_trace(
  "M_CORE_MECHANISTIC",
  core_features
)

likely_sources <- schema_audit[
  schema_audit$status ==
    "read_ok" &
    (
      schema_audit$n_rows >=
        100000L |
      schema_audit$predictor_token_count >=
        5L
    ),
  ,
  drop = FALSE
]

write.csv(
  schema_audit,
  file.path(
    out_dir,
    "legacy_rds_schema_audit.csv"
  ),
  row.names = FALSE
)

write.csv(
  likely_sources,
  file.path(
    out_dir,
    "likely_legacy_predictor_sources.csv"
  ),
  row.names = FALSE
)

write.csv(
  full_trace,
  file.path(
    out_dir,
    "full_feature_source_trace.csv"
  ),
  row.names = FALSE
)

write.csv(
  core_trace,
  file.path(
    out_dir,
    "core_feature_source_trace.csv"
  ),
  row.names = FALSE
)

writeLines(
  full_trace$feature[
    full_trace$derivation_type ==
      "not_yet_located"
  ],
  file.path(
    out_dir,
    "full_not_yet_located.txt"
  )
)

writeLines(
  core_trace$feature[
    core_trace$derivation_type ==
      "not_yet_located"
  ],
  file.path(
    out_dir,
    "core_not_yet_located.txt"
  )
)

full_counts <- as.data.frame(
  table(
    full_trace$derivation_type
  ),
  stringsAsFactors = FALSE
)

core_counts <- as.data.frame(
  table(
    core_trace$derivation_type
  ),
  stringsAsFactors = FALSE
)

names(full_counts) <- c(
  "derivation_type",
  "n_features"
)

names(core_counts) <- c(
  "derivation_type",
  "n_features"
)

full_counts$model_name <-
  "M_FULL_MECHANISTIC"

core_counts$model_name <-
  "M_CORE_MECHANISTIC"

derivation_summary <- rbind(
  full_counts,
  core_counts
)

derivation_summary <- derivation_summary[
  ,
  c(
    "model_name",
    "derivation_type",
    "n_features"
  )
]

write.csv(
  derivation_summary,
  file.path(
    out_dir,
    "feature_derivation_summary.csv"
  ),
  row.names = FALSE
)

summary_lines <- c(
  "R58E LEGACY PREDICTOR SOURCE TRACE",
  "==================================",
  "",
  paste0(
    "Candidate RDS files inspected: ",
    length(candidate_files)
  ),
  paste0(
    "Table payloads catalogued: ",
    sum(
      schema_audit$status ==
        "read_ok"
    )
  ),
  paste0(
    "Likely predictor source tables: ",
    nrow(likely_sources)
  ),
  paste0(
    "Distinct legacy source columns: ",
    length(all_source_columns)
  ),
  "",
  paste0(
    "FULL not yet located: ",
    sum(
      full_trace$derivation_type ==
        "not_yet_located"
    )
  ),
  paste0(
    "CORE not yet located: ",
    sum(
      core_trace$derivation_type ==
        "not_yet_located"
    )
  ),
  "",
  "STATUS: R58E LEGACY PREDICTOR SOURCE TRACE PASSED"
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
  "===== FEATURE DERIVATION SUMMARY =====\n"
)

print(
  derivation_summary,
  row.names = FALSE
)

cat(
  "\n===== LIKELY LEGACY SOURCES =====\n"
)

print(
  likely_sources[
    ,
    c(
      "file_path",
      "payload",
      "file_size_mb",
      "n_rows",
      "n_columns",
      "has_hyriv_id",
      "has_hybas_id",
      "predictor_token_count"
    )
  ],
  row.names = FALSE
)
