source("R/functions/core.R")

check_packages(
  c(
    "dplyr",
    "readr",
    "tibble"
  )
)

root <- project_root()

out_dir <- file.path(
  root,
  "outputs",
  "r50b_feature_architecture"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

max_process_missing <- as.numeric(
  Sys.getenv(
    "R50B_MAX_PROCESS_MISSING",
    unset = "0.10"
  )
)

if (
  is.na(max_process_missing) ||
  max_process_missing < 0 ||
  max_process_missing > 1
) {
  stop(
    "Invalid R50B_MAX_PROCESS_MISSING."
  )
}

paths <- list(
  anchor = file.path(
    root,
    "data",
    "processed",
    "model_table_p0_full_range_r47_hybrid_local_lithology.rds"
  ),

  lithology = file.path(
    root,
    "outputs",
    "r46_full_range_local_lithology_compatibility",
    "full_range_local_upstream_lithology_candidate.rds"
  ),

  age = file.path(
    root,
    "data",
    "processed",
    "model_table_age_test.rds"
  ),

  diversity = file.path(
    root,
    "data",
    "processed",
    "model_table_m1_existing_candidates.rds"
  ),

  process = file.path(
    root,
    "data",
    "processed",
    "model_table_p1_reuse.rds"
  ),

  r49_manifest = file.path(
    root,
    "outputs",
    "r49_master_feature_inventory",
    "master_feature_manifest_template.csv"
  )
)

missing_files <- names(paths)[
  !file.exists(
    unlist(paths)
  )
]

if (length(missing_files) > 0L) {
  stop(
    "Missing input files: ",
    paste(
      missing_files,
      collapse = ", "
    )
  )
}

anchor <- as.data.frame(
  readRDS(paths$anchor)
)

lithology <- as.data.frame(
  readRDS(paths$lithology)
)

age <- as.data.frame(
  readRDS(paths$age)
)

diversity <- as.data.frame(
  readRDS(paths$diversity)
)

process_data <- as.data.frame(
  readRDS(paths$process)
)

r49_manifest <- readr::read_csv(
  paths$r49_manifest,
  show_col_types = FALSE
)

if (nrow(anchor) != 4485L) {
  stop(
    "Expected 4485 anchor rows; found ",
    nrow(anchor)
  )
}

if (!"row_id" %in% names(anchor)) {
  stop(
    "Anchor lacks row_id."
  )
}

anchor$row_id <- as.character(
  anchor$row_id
)

if (anyDuplicated(anchor$row_id)) {
  stop(
    "Anchor row_id is not unique."
  )
}

prepare_source <- function(
  data,
  source_name
) {
  if (!"row_id" %in% names(data)) {
    stop(
      source_name,
      " lacks row_id."
    )
  }

  data$row_id <- as.character(
    data$row_id
  )

  if (anyDuplicated(data$row_id)) {
    stop(
      source_name,
      " contains duplicate row_id values."
    )
  }

  data
}

lithology <- prepare_source(
  lithology,
  "Lithology table"
)

age <- prepare_source(
  age,
  "Age table"
)

diversity <- prepare_source(
  diversity,
  "Diversity table"
)

process_data <- prepare_source(
  process_data,
  "Process table"
)

add_columns_by_row_id <- function(
  base,
  source,
  columns,
  source_name
) {
  columns <- unique(columns)

  if (length(columns) == 0L) {
    return(base)
  }

  missing_columns <- setdiff(
    columns,
    names(source)
  )

  if (length(missing_columns) > 0L) {
    stop(
      source_name,
      " lacks required columns: ",
      paste(
        missing_columns,
        collapse = ", "
      )
    )
  }

  duplicate_names <- intersect(
    columns,
    names(base)
  )

  if (length(duplicate_names) > 0L) {
    stop(
      source_name,
      " columns already exist in model table: ",
      paste(
        duplicate_names,
        collapse = ", "
      )
    )
  }

  source_subset <- source |>
    dplyr::select(
      row_id,
      dplyr::all_of(columns)
    )

  result <- base |>
    dplyr::left_join(
      source_subset,
      by = "row_id"
    )

  if (nrow(result) != nrow(base)) {
    stop(
      "Row count changed while joining ",
      source_name,
      "."
    )
  }

  result
}

p0_features <- grep(
  "^p0__",
  names(anchor),
  value = TRUE
)

if (length(p0_features) != 28L) {
  stop(
    "Expected 28 P0 features; found ",
    length(p0_features)
  )
}

local_raw_all <- c(
  "r47__local_geo_carbonate",
  "r47__local_geo_evaporite",
  "r47__local_geo_metamorphic",
  "r47__local_geo_mixed_sedimentary",
  "r47__local_geo_plutonic",
  "r47__local_geo_siliciclastic",
  "r47__local_geo_unconsolidated",
  "r47__local_geo_volcanic"
)

missing_local <- setdiff(
  local_raw_all,
  names(anchor)
)

if (length(missing_local) > 0L) {
  stop(
    "Anchor lacks local lithology variables: ",
    paste(
      missing_local,
      collapse = ", "
    )
  )
}

upstream_raw_all <- c(
  "up_geo_carbonate_frac",
  "up_geo_evaporite_frac",
  "up_geo_metamorphic_frac",
  "up_geo_mixed_sedimentary_frac",
  "up_geo_plutonic_frac",
  "up_geo_siliciclastic_frac",
  "up_geo_unconsolidated_frac",
  "up_geo_volcanic_frac"
)

age_all <- c(
  "local_geo_age_max_oldest_ma",
  "local_geo_age_mean_ma",
  "local_geo_age_resolved_coverage",
  "local_geo_age_sd_ma",
  "local_geo_frac_midpoint_gt_1000",
  "local_geo_frac_midpoint_gt_2000",

  "up_geo_age_max_oldest_ma",
  "up_geo_age_mean_ma",
  "up_geo_age_resolved_coverage",
  "up_geo_age_sd_ma",
  "up_geo_frac_midpoint_gt_1000",
  "up_geo_frac_midpoint_gt_2000"
)

diversity_selected <- c(
  "m1a__lith_entropy_norm"
)

model_table <- anchor

model_table <- add_columns_by_row_id(
  model_table,
  lithology,
  upstream_raw_all,
  "R46 lithology table"
)

model_table <- add_columns_by_row_id(
  model_table,
  age,
  age_all,
  "Age table"
)

model_table <- add_columns_by_row_id(
  model_table,
  diversity,
  diversity_selected,
  "Diversity table"
)

# ==============================================================================
# Process variables: climate-weathering, soil and topography
# ==============================================================================

allowed_process_groups <- c(
  "climate_weathering",
  "soil_surface_process",
  "topography_erosion"
)

all_p1r_manifest <- r49_manifest |>
  dplyr::filter(
    grepl(
      "^p1r",
      feature
    )
  )

process_candidates_initial <- all_p1r_manifest |>
  dplyr::filter(
    suggested_mechanism_group %in%
      allowed_process_groups,

    column_type %in%
      c(
        "numeric",
        "integer"
      ),

    anchor_n_unique > 1,

    anchor_missing_fraction <=
      max_process_missing,

    feature %in%
      names(process_data)
  ) |>
  dplyr::pull(feature) |>
  unique()

already_present <- intersect(
  process_candidates_initial,
  names(model_table)
)

process_candidates_to_join <- setdiff(
  process_candidates_initial,
  names(model_table)
)

model_table <- add_columns_by_row_id(
  model_table,
  process_data,
  process_candidates_to_join,
  "P1 process table"
)

process_candidates_available <- unique(
  c(
    already_present,
    process_candidates_to_join
  )
)

actual_process_missing <- tibble::tibble(
  feature =
    process_candidates_available,

  actual_missing_fraction =
    vapply(
      process_candidates_available,
      function(feature) {
        mean(
          is.na(
            model_table[[feature]]
          )
        )
      },
      numeric(1)
    )
)

process_candidates_available <-
  actual_process_missing |>
  dplyr::filter(
    actual_missing_fraction <=
      max_process_missing
  ) |>
  dplyr::pull(feature)

exact_numeric_equal <- function(
  x,
  y,
  tolerance = 1e-12
) {
  x <- suppressWarnings(
    as.numeric(x)
  )

  y <- suppressWarnings(
    as.numeric(y)
  )

  if (length(x) != length(y)) {
    return(FALSE)
  }

  matches <-
    (
      is.na(x) &
        is.na(y)
    ) |
    (
      !is.na(x) &
        !is.na(y) &
        abs(x - y) <= tolerance
    )

  all(matches)
}

process_features_kept <- character()

process_duplicate_records <- list()

reference_features <- p0_features

for (
  feature in process_candidates_available
) {
  comparison_pool <- c(
    reference_features,
    process_features_kept
  )

  duplicate_of <- comparison_pool[
    vapply(
      comparison_pool,
      function(reference_feature) {
        exact_numeric_equal(
          model_table[[feature]],
          model_table[[
            reference_feature
          ]]
        )
      },
      logical(1)
    )
  ]

  if (length(duplicate_of) == 0L) {
    process_features_kept <- c(
      process_features_kept,
      feature
    )
  } else {
    process_duplicate_records[[
      length(process_duplicate_records) + 1L
    ]] <- tibble::tibble(
      feature = feature,
      duplicate_of = paste(
        duplicate_of,
        collapse = " | "
      )
    )
  }
}

process_duplicate_table <- if (
  length(process_duplicate_records) == 0L
) {
  tibble::tibble(
    feature = character(),
    duplicate_of = character()
  )
} else {
  dplyr::bind_rows(
    process_duplicate_records
  )
}

readr::write_csv(
  process_duplicate_table,
  file.path(
    out_dir,
    "process_exact_duplicates.csv"
  )
)

# ==============================================================================
# Freeze main versus sensitivity-only process covariates
# ==============================================================================

# Main models retain direct environmental measurements.
# Deterministic contrasts, aggregate geology proxies and explicit interaction
# terms are reserved for sensitivity analysis.
main_process_features <- c(
  "p1r__local_soil_clay_pct_0_30cm",
  "p1r__local_soil_pH_0_30cm",
  "p1r__up_soil_pH_0_30cm",
  "p1r__local_elevation_m"
)

missing_main_process <- setdiff(
  main_process_features,
  process_features_kept
)

if (length(missing_main_process) > 0L) {
  stop(
    "Prespecified main process variables were not available: ",
    paste(
      missing_main_process,
      collapse = ", "
    )
  )
}

process_sensitivity_only <- setdiff(
  process_features_kept,
  main_process_features
)

process_features_kept <-
  main_process_features

process_architecture_decisions <- tibble::tibble(
  feature = c(
    process_features_kept,
    process_sensitivity_only
  ),

  architecture_role = c(
    rep(
      "MAIN_CORE_AND_FULL",
      length(process_features_kept)
    ),

    rep(
      "SENSITIVITY_ONLY",
      length(process_sensitivity_only)
    )
  ),

  rationale = c(
    rep(
      paste(
        "Direct environmental covariate;",
        "retained without performance screening."
      ),
      length(process_features_kept)
    ),

    rep(
      paste(
        "Derived contrast, aggregate geological proxy",
        "or explicit interaction term;",
        "reserved for sensitivity analysis to avoid",
        "deterministic or interpretive redundancy."
      ),
      length(process_sensitivity_only)
    )
  )
)

readr::write_csv(
  process_architecture_decisions,
  file.path(
    out_dir,
    "process_architecture_decisions.csv"
  )
)

forbidden_main_patterns <-
  "local_minus_up|carbonate_evaporite_proxy|_x_aridity"

if (
  any(
    grepl(
      forbidden_main_patterns,
      process_features_kept
    )
  )
) {
  stop(
    "A derived contrast, proxy or explicit interaction entered the main models."
  )
}

# ==============================================================================
# Scientifically defined compact geological representation
# ==============================================================================

model_table <- model_table |>
  dplyr::mutate(
    r50__local_radiogenic_crystalline =
      r47__local_geo_metamorphic +
      r47__local_geo_plutonic,

    r50__local_sedimentary_source =
      r47__local_geo_siliciclastic +
      r47__local_geo_mixed_sedimentary,

    r50__upstream_radiogenic_crystalline =
      up_geo_metamorphic_frac +
      up_geo_plutonic_frac,

    r50__upstream_sedimentary_source =
      up_geo_siliciclastic_frac +
      up_geo_mixed_sedimentary_frac
  )

# Upstream lithology is already represented by the frozen P0 variables.
# CORE therefore adds only a compact local-geology representation.
# Unconsolidated material is the omitted local reference group.
core_composition <- c(
  "r47__local_geo_carbonate",
  "r47__local_geo_evaporite",
  "r47__local_geo_volcanic",
  "r50__local_radiogenic_crystalline",
  "r50__local_sedimentary_source"
)

# One broad residual class is omitted at each scale to avoid compositional
# closure redundancy.
full_local_composition <- setdiff(
  local_raw_all,
  "r47__local_geo_mixed_sedimentary"
)

# Do not add a second upstream-lithology version to FULL.
# The complete upstream composition is already contained in frozen P0.
# R46 upstream variables remain available for stratification and sensitivity.
full_upstream_composition <- character()

core_age <- c(
  "local_geo_age_mean_ma",
  "local_geo_frac_midpoint_gt_2000",
  "up_geo_age_mean_ma",
  "up_geo_frac_midpoint_gt_2000"
)

full_age <- c(
  "local_geo_age_max_oldest_ma",
  "local_geo_age_mean_ma",
  "local_geo_age_sd_ma",
  "local_geo_frac_midpoint_gt_1000",
  "local_geo_frac_midpoint_gt_2000",

  "up_geo_age_max_oldest_ma",
  "up_geo_age_mean_ma",
  "up_geo_age_sd_ma",
  "up_geo_frac_midpoint_gt_1000",
  "up_geo_frac_midpoint_gt_2000"
)

m0_features <- p0_features

core_features <- unique(
  c(
    p0_features,
    core_composition,
    core_age,
    diversity_selected,
    process_features_kept
  )
)

full_features <- unique(
  c(
    p0_features,
    full_local_composition,
    full_upstream_composition,
    full_age,
    diversity_selected,
    process_features_kept
  )
)

# ==============================================================================
# Geological regimes for stratified validation
# ==============================================================================

model_table <- model_table |>
  dplyr::mutate(
    r50__local_composition_sum =
      r47__local_geo_carbonate +
      r47__local_geo_evaporite +
      r47__local_geo_metamorphic +
      r47__local_geo_mixed_sedimentary +
      r47__local_geo_plutonic +
      r47__local_geo_siliciclastic +
      r47__local_geo_unconsolidated +
      r47__local_geo_volcanic,

    r50__upstream_composition_sum =
      up_geo_carbonate_frac +
      up_geo_evaporite_frac +
      up_geo_metamorphic_frac +
      up_geo_mixed_sedimentary_frac +
      up_geo_plutonic_frac +
      up_geo_siliciclastic_frac +
      up_geo_unconsolidated_frac +
      up_geo_volcanic_frac,

    regime_carbonate_dominated =
      pmax(
        r47__local_geo_carbonate,
        up_geo_carbonate_frac
      ) >= 0.50,

    regime_radiogenic_crystalline =
      pmax(
        r50__local_radiogenic_crystalline,
        r50__upstream_radiogenic_crystalline
      ) >= 0.50 |
      pmax(
        local_geo_frac_midpoint_gt_2000,
        up_geo_frac_midpoint_gt_2000
      ) >= 0.50,

    regime_volcanic_dominated =
      pmax(
        r47__local_geo_volcanic,
        up_geo_volcanic_frac
      ) >= 0.50,

    regime_sedimentary_dominated =
      pmax(
        r50__local_sedimentary_source,
        r50__upstream_sedimentary_source
      ) >= 0.50,

    regime_unconsolidated_dominated =
      pmax(
        r47__local_geo_unconsolidated,
        up_geo_unconsolidated_frac
      ) >= 0.50,

    regime_evaporite_influenced =
      pmax(
        r47__local_geo_evaporite,
        up_geo_evaporite_frac
      ) >= 0.05,

    regime_mixed_geology =
      !regime_carbonate_dominated &
      !regime_radiogenic_crystalline &
      !regime_volcanic_dominated &
      !regime_sedimentary_dominated &
      !regime_unconsolidated_dominated &
      !regime_evaporite_influenced,

    geological_regime_primary =
      dplyr::case_when(
        regime_evaporite_influenced ~
          "evaporite_influenced",

        regime_radiogenic_crystalline ~
          "radiogenic_crystalline",

        regime_carbonate_dominated ~
          "carbonate_dominated",

        regime_volcanic_dominated ~
          "volcanic_dominated",

        regime_sedimentary_dominated ~
          "sedimentary_dominated",

        regime_unconsolidated_dominated ~
          "unconsolidated_dominated",

        TRUE ~
          "mixed_geology"
      )
  )

regime_columns <- c(
  "regime_carbonate_dominated",
  "regime_radiogenic_crystalline",
  "regime_volcanic_dominated",
  "regime_sedimentary_dominated",
  "regime_unconsolidated_dominated",
  "regime_evaporite_influenced",
  "regime_mixed_geology",
  "geological_regime_primary"
)

regime_table <- model_table |>
  dplyr::select(
    row_id,
    site_id,
    longitude,
    latitude,
    sr87_sr86,
    dplyr::all_of(
      regime_columns
    )
  )

readr::write_csv(
  regime_table,
  file.path(
    out_dir,
    "geological_regime_strata.csv"
  )
)

primary_regime_counts <- model_table |>
  dplyr::count(
    geological_regime_primary,
    name = "n_sites"
  ) |>
  dplyr::mutate(
    fraction =
      n_sites /
      sum(n_sites)
  ) |>
  dplyr::arrange(
    dplyr::desc(n_sites)
  )

readr::write_csv(
  primary_regime_counts,
  file.path(
    out_dir,
    "geological_regime_counts.csv"
  )
)

overlapping_regime_counts <- tibble::tibble(
  regime = regime_columns[
    grepl(
      "^regime_",
      regime_columns
    )
  ],

  n_sites = vapply(
    regime_columns[
      grepl(
        "^regime_",
        regime_columns
      )
    ],
    function(feature) {
      sum(
        model_table[[feature]],
        na.rm = TRUE
      )
    },
    integer(1)
  )
) |>
  dplyr::mutate(
    fraction =
      n_sites /
      nrow(model_table)
  )

readr::write_csv(
  overlapping_regime_counts,
  file.path(
    out_dir,
    "overlapping_geological_regime_counts.csv"
  )
)

composition_qc <- tibble::tibble(
  scale = c(
    "local",
    "upstream"
  ),

  minimum_sum = c(
    min(
      model_table$
        r50__local_composition_sum,
      na.rm = TRUE
    ),

    min(
      model_table$
        r50__upstream_composition_sum,
      na.rm = TRUE
    )
  ),

  median_sum = c(
    median(
      model_table$
        r50__local_composition_sum,
      na.rm = TRUE
    ),

    median(
      model_table$
        r50__upstream_composition_sum,
      na.rm = TRUE
    )
  ),

  maximum_sum = c(
    max(
      model_table$
        r50__local_composition_sum,
      na.rm = TRUE
    ),

    max(
      model_table$
        r50__upstream_composition_sum,
      na.rm = TRUE
    )
  ),

  maximum_absolute_deviation_from_one =
    c(
      max(
        abs(
          model_table$
            r50__local_composition_sum -
            1
        ),
        na.rm = TRUE
      ),

      max(
        abs(
          model_table$
            r50__upstream_composition_sum -
            1
        ),
        na.rm = TRUE
      )
    )
)

readr::write_csv(
  composition_qc,
  file.path(
    out_dir,
    "composition_sum_qc.csv"
  )
)

# ==============================================================================
# Model-set invariants
# ==============================================================================

all_model_features <- unique(
  c(
    m0_features,
    core_features,
    full_features
  )
)

missing_model_features <- setdiff(
  all_model_features,
  names(model_table)
)

if (length(missing_model_features) > 0L) {
  stop(
    "Missing model features: ",
    paste(
      missing_model_features,
      collapse = ", "
    )
  )
}

non_numeric_features <- all_model_features[
  !vapply(
    model_table[
      all_model_features
    ],
    is.numeric,
    logical(1)
  )
]

if (length(non_numeric_features) > 0L) {
  stop(
    "Non-numeric model features: ",
    paste(
      non_numeric_features,
      collapse = ", "
    )
  )
}

leakage_features <- c(
  "sr87_sr86",
  "sr",
  "sr_min",
  "sr_max",
  "sr_mean",
  "sr_median",
  "sr_median_all_rows",
  "is_ge_075",
  "is_ge_080"
)

leakage_in_models <- intersect(
  leakage_features,
  all_model_features
)

if (length(leakage_in_models) > 0L) {
  stop(
    "Outcome leakage entered model sets: ",
    paste(
      leakage_in_models,
      collapse = ", "
    )
  )
}

constant_features <- all_model_features[
  vapply(
    model_table[
      all_model_features
    ],
    function(x) {
      dplyr::n_distinct(
        x,
        na.rm = TRUE
      ) <= 1L
    },
    logical(1)
  )
]

if (length(constant_features) > 0L) {
  stop(
    "Constant features entered model sets: ",
    paste(
      constant_features,
      collapse = ", "
    )
  )
}

find_exact_duplicates <- function(
  data,
  features,
  model_name
) {
  if (length(features) < 2L) {
    return(
      tibble::tibble(
        model = character(),
        feature_1 = character(),
        feature_2 = character()
      )
    )
  }

  result <- list()

  for (i in seq_len(length(features) - 1L)) {
    for (j in seq.int(i + 1L, length(features))) {
      if (
        exact_numeric_equal(
          data[[features[[i]]]],
          data[[features[[j]]]]
        )
      ) {
        result[[
          length(result) + 1L
        ]] <- tibble::tibble(
          model = model_name,
          feature_1 = features[[i]],
          feature_2 = features[[j]]
        )
      }
    }
  }

  if (length(result) == 0L) {
    tibble::tibble(
      model = character(),
      feature_1 = character(),
      feature_2 = character()
    )
  } else {
    dplyr::bind_rows(result)
  }
}

model_duplicate_table <- dplyr::bind_rows(
  find_exact_duplicates(
    model_table,
    m0_features,
    "M0_P0_FULL"
  ),

  find_exact_duplicates(
    model_table,
    core_features,
    "M_CORE_MECHANISTIC"
  ),

  find_exact_duplicates(
    model_table,
    full_features,
    "M_FULL_MECHANISTIC"
  )
)

readr::write_csv(
  model_duplicate_table,
  file.path(
    out_dir,
    "exact_duplicates_within_model_sets.csv"
  )
)

if (nrow(model_duplicate_table) > 0L) {
  stop(
    "Exact duplicate variables remain inside one or more model sets."
  )
}

# ==============================================================================
# Process-feature audit
# ==============================================================================

process_group_lookup <- all_p1r_manifest |>
  dplyr::select(
    feature,
    suggested_mechanism_group
  ) |>
  dplyr::distinct()

process_audit <- all_p1r_manifest |>
  dplyr::select(
    feature,
    suggested_mechanism_group,
    column_type,
    anchor_missing_fraction,
    anchor_n_unique
  ) |>
  dplyr::mutate(
    present_in_process_table =
      feature %in%
      names(process_data),

    actual_missing_fraction =
      actual_process_missing$
        actual_missing_fraction[
          match(
            feature,
            actual_process_missing$
              feature
          )
        ],

    exact_duplicate_of =
      process_duplicate_table$
        duplicate_of[
          match(
            feature,
            process_duplicate_table$
              feature
          )
        ],

    final_decision =
      dplyr::case_when(
        !suggested_mechanism_group %in%
          allowed_process_groups ~
          "EXCLUDE_UNSUPPORTED_MECHANISM_GROUP",

        !column_type %in%
          c(
            "numeric",
            "integer"
          ) ~
          "EXCLUDE_NONNUMERIC",

        anchor_n_unique <= 1 ~
          "EXCLUDE_CONSTANT",

        anchor_missing_fraction >
          max_process_missing ~
          "EXCLUDE_MISSINGNESS_ABOVE_THRESHOLD",

        !present_in_process_table ~
          "EXCLUDE_NOT_PRESENT_IN_SOURCE_TABLE",

        !is.na(actual_missing_fraction) &
          actual_missing_fraction >
          max_process_missing ~
          "EXCLUDE_ACTUAL_MISSINGNESS_ABOVE_THRESHOLD",

        !is.na(exact_duplicate_of) ~
          "EXCLUDE_EXACT_DUPLICATE",

        feature %in%
          process_sensitivity_only ~
          "SENSITIVITY_ONLY_STRUCTURAL_REDUNDANCY",

        feature %in%
          process_features_kept ~
          "INCLUDE_WITH_FOLDWISE_IMPUTATION",

        TRUE ~
          "EXCLUDE_OTHER"
      )
  )

readr::write_csv(
  process_audit,
  file.path(
    out_dir,
    "process_feature_audit.csv"
  )
)

# ==============================================================================
# Feature architecture manifest
# ==============================================================================

classify_p0_mechanism <- function(feature) {
  lower <- tolower(feature)

  if (
    grepl(
      "dis_av|catch|upland|length|dist_dn|dist_up|ord_",
      lower
    )
  ) {
    return(
      "hydrology_transport"
    )
  }

  if (
    grepl(
      "precip|temp|arid|clim|runoff",
      lower
    )
  ) {
    return(
      "climate_weathering"
    )
  }

  if (
    grepl(
      "elev|slope|relief|topo",
      lower
    )
  ) {
    return(
      "topography_erosion"
    )
  }

  if (
    grepl(
      "soil|clay|ph|cec",
      lower
    )
  ) {
    return(
      "soil_surface_process"
    )
  }

  if (
    grepl(
      "geo|lith|rock",
      lower
    )
  ) {
    return(
      "geology_source"
    )
  }

  "frozen_baseline_other"
}

feature_source <- function(feature) {
  if (feature %in% p0_features) {
    return(
      "anchor_frozen_p0"
    )
  }

  if (
    feature %in%
      local_raw_all ||
    grepl(
      "^r50__local_",
      feature
    )
  ) {
    return(
      "R47_local_lithology"
    )
  }

  if (
    feature %in%
      upstream_raw_all ||
    grepl(
      "^r50__upstream_",
      feature
    )
  ) {
    return(
      "R46_upstream_lithology"
    )
  }

  if (feature %in% age_all) {
    return(
      "model_table_age_test"
    )
  }

  if (
    feature %in%
      diversity_selected
  ) {
    return(
      "model_table_m1_existing_candidates"
    )
  }

  if (
    feature %in%
      process_features_kept
  ) {
    return(
      "model_table_p1_reuse"
    )
  }

  "derived"
}

feature_mechanism <- function(feature) {
  if (feature %in% p0_features) {
    return(
      classify_p0_mechanism(
        feature
      )
    )
  }

  if (
    grepl(
      "age|midpoint_gt",
      feature
    )
  ) {
    return(
      "geological_age_radiogenic_potential"
    )
  }

  if (
    grepl(
      "entropy",
      feature
    )
  ) {
    return(
      "geological_heterogeneity"
    )
  }

  if (
    feature %in%
      c(
        local_raw_all,
        upstream_raw_all,
        core_composition
      )
  ) {
    return(
      "geology_source_composition"
    )
  }

  process_match <- process_group_lookup$
    suggested_mechanism_group[
      match(
        feature,
        process_group_lookup$
          feature
      )
    ]

  if (!is.na(process_match)) {
    return(
      process_match
    )
  }

  "other"
}

feature_regime <- function(feature) {
  lower <- tolower(feature)

  if (grepl("carbonate", lower)) {
    return(
      "carbonate_dominated"
    )
  }

  if (grepl("evaporite", lower)) {
    return(
      "evaporite_or_arid"
    )
  }

  if (
    grepl(
      "radiogenic|metamorphic|plutonic|age|midpoint_gt",
      lower
    )
  ) {
    return(
      "radiogenic_crystalline"
    )
  }

  if (grepl("volcanic", lower)) {
    return(
      "volcanic"
    )
  }

  if (
    grepl(
      "siliciclastic|sedimentary",
      lower
    )
  ) {
    return(
      "sedimentary"
    )
  }

  if (
    grepl(
      "unconsolidated",
      lower
    )
  ) {
    return(
      "unconsolidated"
    )
  }

  if (grepl("entropy", lower)) {
    return(
      "mixed_geology"
    )
  }

  "all_geological_regimes"
}

feature_representation <- function(feature) {
  if (feature %in% p0_features) {
    return(
      "frozen_baseline"
    )
  }

  if (
    feature %in%
      core_composition &&
    grepl(
      "^r50__",
      feature
    )
  ) {
    return(
      "compact_aggregated_composition"
    )
  }

  if (
    feature %in%
      c(
        local_raw_all,
        upstream_raw_all
      )
  ) {
    return(
      "raw_composition_reference_class_coding"
    )
  }

  if (feature %in% age_all) {
    return(
      "geological_age_descriptor"
    )
  }

  if (
    feature %in%
      diversity_selected
  ) {
    return(
      "lithological_diversity_descriptor"
    )
  }

  if (
    feature %in%
      process_features_kept
  ) {
    return(
      "environmental_process_covariate"
    )
  }

  "derived"
}

architecture_manifest <- tibble::tibble(
  feature = all_model_features,

  source = vapply(
    all_model_features,
    feature_source,
    character(1)
  ),

  mechanism_group = vapply(
    all_model_features,
    feature_mechanism,
    character(1)
  ),

  geological_regime_applicability =
    vapply(
      all_model_features,
      feature_regime,
      character(1)
    ),

  representation = vapply(
    all_model_features,
    feature_representation,
    character(1)
  ),

  include_in_m0 =
    all_model_features %in%
    m0_features,

  include_in_core =
    all_model_features %in%
    core_features,

  include_in_full =
    all_model_features %in%
    full_features,

  missing_fraction =
    vapply(
      all_model_features,
      function(feature) {
        mean(
          is.na(
            model_table[[feature]]
          )
        )
      },
      numeric(1)
    ),

  foldwise_imputation_required =
    missing_fraction > 0,

  selection_basis =
    dplyr::case_when(
      feature %in% p0_features ~
        "Frozen benchmark baseline.",

      feature %in% core_composition ~
        paste(
          "Predeclared compact geology representation;",
          "not chosen using model performance."
        ),

      feature %in%
        c(
          full_local_composition,
          full_upstream_composition
        ) ~
        paste(
          "Predeclared raw composition representation",
          "with one reference class omitted."
        ),

      feature %in% age_all ~
        paste(
          "Predeclared geological-age mechanism;",
          "coverage fields excluded from prediction."
        ),

      feature %in%
        diversity_selected ~
        paste(
          "Single prespecified lithological",
          "heterogeneity descriptor."
        ),

      feature %in%
        process_features_kept ~
        paste(
          "Mechanism group and missingness threshold;",
          "no performance screening."
        ),

      TRUE ~
        "Mechanistic prespecification."
    )
) |>
  dplyr::arrange(
    mechanism_group,
    feature
  )

readr::write_csv(
  architecture_manifest,
  file.path(
    out_dir,
    "feature_architecture_manifest.csv"
  )
)

# ==============================================================================
# Explicit exclusions
# ==============================================================================

manual_exclusions <- tibble::tribble(
  ~feature_or_pattern,
  ~exclusion_reason,

  "sr87_sr86; sr_min; sr_max; sr_mean; sr_median; is_ge_075; is_ge_080",
  "Outcome or direct transformation of outcome; target leakage.",

  "row_id; site_id; HYBAS_ID; HYRIV_ID; basin_region; asset_region",
  "Identifier or reporting stratum; not an environmental predictor.",

  "duplicate_sensitive_flag; n_removed_as_duplicate; n_unique_measurements",
  "Observation-quality metadata; retained for sensitivity analysis only.",

  "local_minus_up_*; *_contrast; carbonate_evaporite_proxy*; *_x_aridity",
  "Derived contrast, aggregate proxy or explicit interaction based on terms already represented; sensitivity only.",

  "r47 compact proxy variables",
  "Existing proxies are exact duplicates of individual raw lithology fractions.",

  "m1a__lith_effective_n; m1a__lith_entropy; m1a__lith_simpson",
  "Alternative summaries of the same lithological-diversity construct.",

  "local_geo_age_resolved_coverage; up_geo_age_resolved_coverage",
  "Data-coverage indicators; retained as uncertainty or extrapolation flags.",

  "unprefixed R46 up_geo_*_frac variables",
  "Alternative upstream-lithology version; frozen P0 already contains upstream composition. Retained for stratification and sensitivity only.",

  "one added local composition class",
  "The added local-geology representation omits one reference class to avoid deterministic compositional closure."
)

readr::write_csv(
  manual_exclusions,
  file.path(
    out_dir,
    "manual_exclusion_rules.csv"
  )
)

# ==============================================================================
# Missingness and model summaries
# ==============================================================================

feature_missingness <- architecture_manifest |>
  dplyr::select(
    feature,
    mechanism_group,
    include_in_m0,
    include_in_core,
    include_in_full,
    missing_fraction,
    foldwise_imputation_required
  )

readr::write_csv(
  feature_missingness,
  file.path(
    out_dir,
    "feature_missingness.csv"
  )
)

model_set_summary <- tibble::tibble(
  model = c(
    "M0_P0_FULL",
    "M_CORE_MECHANISTIC",
    "M_FULL_MECHANISTIC"
  ),

  n_features = c(
    length(m0_features),
    length(core_features),
    length(full_features)
  ),

  n_rows = nrow(model_table),

  n_complete_rows = c(
    sum(
      stats::complete.cases(
        model_table[
          m0_features
        ]
      )
    ),

    sum(
      stats::complete.cases(
        model_table[
          core_features
        ]
      )
    ),

    sum(
      stats::complete.cases(
        model_table[
          full_features
        ]
      )
    )
  ),

  n_features_requiring_foldwise_imputation =
    c(
      sum(
        vapply(
          m0_features,
          function(feature) {
            any(
              is.na(
                model_table[[feature]]
              )
            )
          },
          logical(1)
        )
      ),

      sum(
        vapply(
          core_features,
          function(feature) {
            any(
              is.na(
                model_table[[feature]]
              )
            )
          },
          logical(1)
        )
      ),

      sum(
        vapply(
          full_features,
          function(feature) {
            any(
              is.na(
                model_table[[feature]]
              )
            )
          },
          logical(1)
        )
      )
    )
)

readr::write_csv(
  model_set_summary,
  file.path(
    out_dir,
    "model_set_summary.csv"
  )
)

feature_sets <- list(
  M0_P0_FULL =
    m0_features,

  M_CORE_MECHANISTIC =
    core_features,

  M_FULL_MECHANISTIC =
    full_features,

  PROCESS_FEATURES =
    process_features_kept,

  PROCESS_SENSITIVITY_ONLY =
    process_sensitivity_only,

  GEOLOGICAL_REGIME_COLUMNS =
    regime_columns
)

saveRDS(
  feature_sets,
  file.path(
    out_dir,
    "model_feature_sets.rds"
  ),
  version = 3
)

saveRDS(
  model_table,
  file.path(
    out_dir,
    "integrated_model_table.rds"
  ),
  version = 3
)

writeLines(
  m0_features,
  file.path(
    out_dir,
    "M0_P0_FULL_features.txt"
  )
)

writeLines(
  core_features,
  file.path(
    out_dir,
    "M_CORE_MECHANISTIC_features.txt"
  )
)

writeLines(
  full_features,
  file.path(
    out_dir,
    "M_FULL_MECHANISTIC_features.txt"
  )
)

summary_lines <- c(
  "R50B MECHANISTIC FEATURE ARCHITECTURE",
  "====================================",
  "",
  paste0(
    "Frozen rows: ",
    nrow(model_table)
  ),
  paste0(
    "Frozen P0 variables: ",
    length(p0_features)
  ),
  paste0(
    "CORE variables: ",
    length(core_features)
  ),
  paste0(
    "FULL variables: ",
    length(full_features)
  ),
  paste0(
    "Additional process variables retained: ",
    length(process_features_kept)
  ),
  paste0(
    "Derived process variables reserved for sensitivity: ",
    length(process_sensitivity_only)
  ),
  paste0(
    "Maximum accepted process missingness: ",
    max_process_missing
  ),
  "",
  "GEOLOGY REPRESENTATION:",
  paste0(
    "CORE composition variables: ",
    length(core_composition)
  ),
  paste0(
    "FULL local composition variables: ",
    length(full_local_composition)
  ),
  paste0(
    "FULL upstream composition variables: ",
    length(full_upstream_composition)
  ),
  "",
  "CORE and FULL are alternative mechanistic representations.",
  "CORE adds aggregated local geological source groups.",
  "FULL adds raw local fractions with one reference class omitted.",
  "Both retain upstream lithology through the frozen P0 baseline.",
  "Derived local-minus-upstream contrasts are sensitivity-only.",
  "",
  "HYDROLOGY:",
  "No new hydrology module was added.",
  "All nine hydrology fields remain represented through frozen P0.",
  "",
  "VALIDATION STRATA:",
  paste(
    primary_regime_counts$
      geological_regime_primary,
    collapse = ", "
  ),
  "",
  "No variable was selected using model performance.",
  "",
  "STATUS: ALL R50B FEATURE ARCHITECTURE INVARIANTS PASSED"
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
  "\n"
)
