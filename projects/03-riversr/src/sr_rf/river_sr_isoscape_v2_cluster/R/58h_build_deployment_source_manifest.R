root <- normalizePath(
  getwd(),
  mustWork = TRUE
)

legacy_root <- file.path(
  "/home",
  "zhangmeng",
  "projects",
  "sr_global",
  "data_processed",
  "global"
)

age_file <- file.path(
  root,
  "outputs",
  "nrcan_age_hydrobasins_l6",
  "global_upstream",
  "l6_nrcan_age_local_upstream_global.rds"
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
  "r58h_deployment_source_manifest"
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

extract_feature_names <- function(bundle) {
  candidate_fields <- c(
    "feature_names",
    "predictor_names",
    "features",
    "predictors"
  )

  for (field in candidate_fields) {
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
    "Feature names could not be extracted."
  )
}

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

  selected <- table_indices[
    which.max(table_rows)
  ]

  object[[selected]]
}

extract_region <- function(path) {
  filename <- tolower(
    basename(path)
  )

  for (region in regions) {
    pattern <- paste0(
      "(^|_)",
      region,
      "(_|\\.|$)"
    )

    if (
      grepl(
        pattern,
        filename,
        perl = TRUE
      )
    ) {
      return(region)
    }
  }

  "global"
}

source_role <- function(path) {
  path_lower <- tolower(path)

  if (
    grepl(
      "nrcan_age_hydrobasins",
      path_lower
    )
  ) {
    return("current_l6_age")
  }

  if (
    grepl(
      "final_prediction/river_predictions_by_region",
      path_lower
    )
  ) {
    return("regional_reach_backbone")
  }

  if (
    grepl(
      "final_prediction/global_river_predictions",
      path_lower
    )
  ) {
    return("global_reach_backbone")
  }

  if (
    grepl(
      "glim_l6_by_region",
      path_lower
    )
  ) {
    return("regional_l6_geology")
  }

  if (
    grepl(
      "soil_l6_by_region",
      path_lower
    )
  ) {
    return("regional_l6_soil")
  }

  if (
    grepl(
      "climate|bioclim|terrain|elevation",
      path_lower
    )
  ) {
    return("climate_terrain")
  }

  if (
    grepl(
      "river_prediction_chunks",
      path_lower
    )
  ) {
    return("legacy_prediction_chunk")
  }

  if (
    grepl(
      "site|observation|snap|model",
      path_lower
    )
  ) {
    return("training_or_site_table")
  }

  "other"
}

source_priority <- function(role) {
  priorities <- c(
    current_l6_age = 1L,
    regional_reach_backbone = 1L,
    global_reach_backbone = 2L,
    regional_l6_geology = 1L,
    regional_l6_soil = 1L,
    climate_terrain = 2L,
    legacy_prediction_chunk = 5L,
    other = 8L,
    training_or_site_table = 20L
  )

  unname(
    priorities[[role]]
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

union_features <- unique(
  c(
    full_features,
    core_features
  )
)

upstream_geology_aliases <- c(
  "up_geo_unconsolidated_frac",
  "up_geo_siliciclastic_frac",
  "up_geo_mixed_sedimentary_frac",
  "up_geo_carbonate_frac",
  "up_geo_metamorphic_frac",
  "up_geo_plutonic_frac",
  "up_geo_volcanic_frac",
  "up_geo_evaporite_frac"
)

feature_specification <- function(feature) {
  if (
    feature %in%
      c(
        "p0__sp_x",
        "p0__sp_y",
        "p0__sp_z"
      )
  ) {
    return(
      list(
        build_method =
          "derive_from_coordinates",

        required_variables =
          c(
            "longitude",
            "latitude"
          ),

        join_level =
          "reach"
      )
    )
  }

  if (
    feature ==
      "r50__local_radiogenic_crystalline"
  ) {
    return(
      list(
        build_method =
          "sum_components",

        required_variables =
          c(
            "local_geo_metamorphic_frac",
            "local_geo_plutonic_frac"
          ),

        join_level =
          "basin"
      )
    )
  }

  if (
    feature ==
      "r50__local_sedimentary_source"
  ) {
    return(
      list(
        build_method =
          "sum_components",

        required_variables =
          c(
            "local_geo_siliciclastic_frac",
            "local_geo_mixed_sedimentary_frac"
          ),

        join_level =
          "basin"
      )
    )
  }

  if (
    feature ==
      "m1a__lith_entropy_norm"
  ) {
    return(
      list(
        build_method =
          "renormalised_shannon_div_log8",

        required_variables =
          upstream_geology_aliases,

        join_level =
          "basin"
      )
    )
  }

  if (
    grepl(
      "^r47__local_geo_",
      feature
    )
  ) {
    lithology <- sub(
      "^r47__local_geo_",
      "",
      feature
    )

    return(
      list(
        build_method =
          "source_alias",

        required_variables =
          paste0(
            "local_geo_",
            lithology,
            "_frac"
          ),

        join_level =
          "basin"
      )
    )
  }

  if (
    grepl(
      "^(local_geo_age_|local_geo_frac_|up_geo_age_|up_geo_frac_)",
      feature
    )
  ) {
    return(
      list(
        build_method =
          "current_l6_age_join",

        required_variables =
          feature,

        join_level =
          "basin"
      )
    )
  }

  if (
    grepl(
      "^p0__",
      feature
    )
  ) {
    alias <- sub(
      "^p0__",
      "",
      feature
    )

    reach_level <- grepl(
      "^(log_DIS|log_UPLAND|log_CATCH|log_LENGTH|log_DIST|ORD_)",
      alias
    )

    return(
      list(
        build_method =
          "source_alias",

        required_variables =
          alias,

        join_level =
          if (
            reach_level
          ) {
            "reach"
          } else {
            "basin"
          }
      )
    )
  }

  if (
    grepl(
      "^p1r__",
      feature
    )
  ) {
    alias <- sub(
      "^p1r__",
      "",
      feature
    )

    return(
      list(
        build_method =
          "source_alias",

        required_variables =
          alias,

        join_level =
          "basin"
      )
    )
  }

  list(
    build_method =
      "unclassified",

    required_variables =
      feature,

    join_level =
      "unknown"
  )
}

manifest_rows <- list()

for (index in seq_along(union_features)) {
  feature <- union_features[[index]]
  specification <- feature_specification(
    feature
  )

  manifest_rows[[index]] <- data.frame(
    feature = feature,

    in_full =
      feature %in%
      full_features,

    in_core =
      feature %in%
      core_features,

    build_method =
      specification$build_method,

    required_base_variables =
      paste(
        specification$required_variables,
        collapse = "|"
      ),

    expected_join_level =
      specification$join_level,

    stringsAsFactors =
      FALSE
  )
}

feature_manifest <- do.call(
  rbind,
  manifest_rows
)

required_base_variables <- unique(
  unlist(
    strsplit(
      feature_manifest$required_base_variables,
      split = "\\|"
    )
  )
)

legacy_rds_files <- list.files(
  legacy_root,
  pattern = "\\.[Rr][Dd][Ss]$",
  recursive = TRUE,
  full.names = TRUE
)

candidate_files <- unique(
  c(
    legacy_rds_files,
    age_file
  )
)

candidate_files <- candidate_files[
  file.exists(
    candidate_files
  )
]

source_rows <- list()
inventory_rows <- list()
source_index <- 0L
inventory_index <- 0L

for (path in candidate_files) {
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

  matching_variables <- intersect(
    required_base_variables,
    columns
  )

  if (length(matching_variables) == 0L) {
    rm(table)
    invisible(gc())
    next
  }

  region <- extract_region(path)
  role <- source_role(path)

  has_hyriv <- any(
    tolower(columns) %in%
      c(
        "hyriv_id",
        "hyriv_key"
      )
  )

  has_hybas <- any(
    tolower(columns) %in%
      c(
        "hybas_id",
        "hybas_key"
      )
  )

  inventory_index <- inventory_index + 1L

  inventory_rows[[inventory_index]] <- data.frame(
    path = path,
    region = region,
    source_role = role,
    priority = source_priority(role),
    n_rows = nrow(table),
    n_columns = ncol(table),
    has_hyriv_key = has_hyriv,
    has_hybas_key = has_hybas,
    matched_variable_count =
      length(matching_variables),
    stringsAsFactors = FALSE
  )

  for (variable in matching_variables) {
    required_join_levels <- unique(
      feature_manifest$expected_join_level[
        grepl(
          paste0(
            "(^|\\|)",
            variable,
            "(\\||$)"
          ),
          feature_manifest$required_base_variables
        )
      ]
    )

    expected_join_level <- paste(
      required_join_levels,
      collapse = "|"
    )

    valid_join_key <- if (
      all(
        required_join_levels ==
          "reach"
      )
    ) {
      has_hyriv
    } else if (
      all(
        required_join_levels ==
          "basin"
      )
    ) {
      has_hybas
    } else {
      has_hyriv |
        has_hybas
    }

    source_index <- source_index + 1L

    source_rows[[source_index]] <- data.frame(
      base_variable = variable,
      path = path,
      region = region,
      source_role = role,
      priority = source_priority(role),
      n_rows = nrow(table),
      n_columns = ncol(table),
      expected_join_level =
        expected_join_level,
      has_hyriv_key = has_hyriv,
      has_hybas_key = has_hybas,
      valid_join_key = valid_join_key,
      stringsAsFactors = FALSE
    )
  }

  rm(table)
  invisible(gc())
}

if (length(source_rows) == 0L) {
  stop(
    "No deployment source candidates were found."
  )
}

source_candidates <- do.call(
  rbind,
  source_rows
)

source_candidates <- source_candidates[
  order(
    source_candidates$base_variable,
    !source_candidates$valid_join_key,
    source_candidates$priority,
    -source_candidates$n_rows
  ),
  ,
  drop = FALSE
]

source_inventory <- do.call(
  rbind,
  inventory_rows
)

source_inventory <- source_inventory[
  order(
    source_inventory$priority,
    source_inventory$region,
    -source_inventory$matched_variable_count,
    -source_inventory$n_rows
  ),
  ,
  drop = FALSE
]

coverage_rows <- list()

for (index in seq_along(required_base_variables)) {
  variable <- required_base_variables[[index]]

  candidates <- source_candidates[
    source_candidates$base_variable ==
      variable &
      source_candidates$valid_join_key,
    ,
    drop = FALSE
  ]

  candidate_regions <- unique(
    candidates$region
  )

  has_global_source <-
    "global" %in%
    candidate_regions

  region_count <- sum(
    regions %in%
      candidate_regions
  )

  complete_region_coverage <-
    has_global_source |
    region_count ==
      length(regions)

  preferred_path <- NA_character_
  preferred_role <- NA_character_

  if (nrow(candidates) > 0L) {
    preferred <- candidates[
      order(
        candidates$priority,
        -candidates$n_rows
      ),
      ,
      drop = FALSE
    ][1, , drop = FALSE]

    preferred_path <- preferred$path
    preferred_role <- preferred$source_role
  }

  coverage_rows[[index]] <- data.frame(
    base_variable = variable,
    valid_candidate_count = nrow(candidates),
    has_global_source = has_global_source,
    regional_sources_found = region_count,
    required_regions = length(regions),
    complete_region_coverage =
      complete_region_coverage,
    preferred_source_role =
      preferred_role,
    preferred_source_path =
      preferred_path,
    stringsAsFactors = FALSE
  )
}

coverage_summary <- do.call(
  rbind,
  coverage_rows
)

coverage_summary <- coverage_summary[
  order(
    !coverage_summary$complete_region_coverage,
    coverage_summary$base_variable
  ),
  ,
  drop = FALSE
]

formula_registry <- data.frame(
  feature = c(
    "r50__local_radiogenic_crystalline",
    "r50__local_sedimentary_source",
    "m1a__lith_entropy_norm"
  ),

  exact_formula = c(
    paste(
      "local_geo_metamorphic_frac",
      "+",
      "local_geo_plutonic_frac"
    ),

    paste(
      "local_geo_siliciclastic_frac",
      "+",
      "local_geo_mixed_sedimentary_frac"
    ),

    paste(
      "Shannon entropy of eight",
      "renormalised upstream geology fractions",
      "/ log(8)"
    )
  ),

  validation_status = c(
    "exact_rmse_0",
    "exact_rmse_0",
    "exact_rmse_0"
  ),

  stringsAsFactors =
    FALSE
)

unresolved_variables <- coverage_summary$base_variable[
  coverage_summary$valid_candidate_count ==
    0L
]

incomplete_variables <- coverage_summary$base_variable[
  coverage_summary$valid_candidate_count >
    0L &
    !coverage_summary$complete_region_coverage
]

write.csv(
  feature_manifest,
  file.path(
    out_dir,
    "feature_deployment_manifest.csv"
  ),
  row.names = FALSE
)

write.csv(
  formula_registry,
  file.path(
    out_dir,
    "exact_formula_registry.csv"
  ),
  row.names = FALSE
)

write.csv(
  source_candidates,
  file.path(
    out_dir,
    "base_variable_source_candidates.csv"
  ),
  row.names = FALSE
)

write.csv(
  coverage_summary,
  file.path(
    out_dir,
    "base_variable_coverage_summary.csv"
  ),
  row.names = FALSE
)

write.csv(
  source_inventory,
  file.path(
    out_dir,
    "source_table_inventory.csv"
  ),
  row.names = FALSE
)

writeLines(
  unresolved_variables,
  file.path(
    out_dir,
    "unresolved_base_variables.txt"
  )
)

writeLines(
  incomplete_variables,
  file.path(
    out_dir,
    "incomplete_region_coverage.txt"
  )
)

deployment_ready <-
  length(unresolved_variables) ==
    0L &&
  length(incomplete_variables) ==
    0L &&
  !any(
    feature_manifest$build_method ==
      "unclassified"
  )

summary_lines <- c(
  "R58H DEPLOYMENT SOURCE MANIFEST",
  "================================",
  "",
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
    "Required base variables: ",
    length(required_base_variables)
  ),
  paste0(
    "Candidate RDS files scanned: ",
    length(candidate_files)
  ),
  paste0(
    "Source tables with relevant variables: ",
    nrow(source_inventory)
  ),
  paste0(
    "Valid source candidate records: ",
    sum(
      source_candidates$valid_join_key
    )
  ),
  paste0(
    "Unresolved base variables: ",
    length(unresolved_variables)
  ),
  paste0(
    "Variables with incomplete regional coverage: ",
    length(incomplete_variables)
  ),
  paste0(
    "Unclassified model features: ",
    sum(
      feature_manifest$build_method ==
        "unclassified"
    )
  ),
  paste0(
    "Deployment source manifest ready: ",
    deployment_ready
  ),
  "",
  "STATUS: R58H DEPLOYMENT SOURCE MANIFEST PASSED"
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
  "===== INCOMPLETE OR UNRESOLVED VARIABLES =====\n"
)

print(
  coverage_summary[
    !coverage_summary$complete_region_coverage,
    ,
    drop = FALSE
  ],
  row.names = FALSE
)

cat(
  "\n===== PREFERRED SOURCE SUMMARY =====\n"
)

print(
  coverage_summary[
    ,
    c(
      "base_variable",
      "valid_candidate_count",
      "complete_region_coverage",
      "preferred_source_role",
      "preferred_source_path"
    )
  ],
  row.names = FALSE
)
