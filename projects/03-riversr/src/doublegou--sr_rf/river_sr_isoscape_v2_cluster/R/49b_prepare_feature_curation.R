source("R/functions/core.R")

check_packages(
  c(
    "dplyr",
    "readr",
    "tibble"
  )
)

root <- project_root()

inventory_dir <- file.path(
  root,
  "outputs",
  "r49_master_feature_inventory"
)

review_dir <- file.path(
  inventory_dir,
  "review"
)

dir.create(
  review_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

manifest_file <- file.path(
  inventory_dir,
  "master_feature_manifest_template.csv"
)

raw_file <- file.path(
  inventory_dir,
  "feature_manifest_raw.csv"
)

asset_file <- file.path(
  inventory_dir,
  "asset_inventory.csv"
)

duplicate_file <- file.path(
  inventory_dir,
  "exact_duplicate_anchor_features.csv"
)

structural_file <- file.path(
  inventory_dir,
  "known_structural_relationships.csv"
)

required_files <- c(
  manifest_file,
  raw_file,
  asset_file,
  duplicate_file,
  structural_file
)

missing_files <- required_files[
  !file.exists(required_files)
]

if (length(missing_files) > 0L) {
  stop(
    "Missing R49 outputs:\n",
    paste(missing_files, collapse = "\n")
  )
}

manifest <- readr::read_csv(
  manifest_file,
  show_col_types = FALSE
)

raw <- readr::read_csv(
  raw_file,
  show_col_types = FALSE
)

assets <- readr::read_csv(
  asset_file,
  show_col_types = FALSE
)

exact_duplicates <- readr::read_csv(
  duplicate_file,
  show_col_types = FALSE
)

structural_relationships <- readr::read_csv(
  structural_file,
  show_col_types = FALSE
)

# ==============================================================================
# Utility classifications
# ==============================================================================

derive_prefix <- function(feature) {
  dplyr::case_when(
    grepl("^p0__", feature) ~ "p0__",
    grepl("^p1__", feature) ~ "p1__",
    grepl("^p2a__", feature) ~ "p2a__",
    grepl("^p2q__", feature) ~ "p2q__",
    grepl("^p3__", feature) ~ "p3__",
    grepl("^r47__local_minus_up", feature) ~
      "r47__local_minus_up",
    grepl("^r47__local_geo", feature) ~
      "r47__local_geo",
    grepl("^r47__contrast", feature) ~
      "r47__contrast_proxy",
    grepl("^r47__local", feature) ~
      "r47__local_proxy",
    TRUE ~ sub(
      "^([^_]+).*",
      "\\1",
      feature
    )
  )
}

compact_features <- c(
  "r47__local_radiogenic_crystalline_proxy",
  "r47__contrast_radiogenic_crystalline_proxy",
  "r47__local_siliciclastic_source_proxy",
  "r47__contrast_siliciclastic_source_proxy"
)

# ==============================================================================
# Seed decisions based only on scientific structure and data readiness
# ==============================================================================

curation <- manifest |>
  dplyr::mutate(
    feature_prefix = vapply(
      feature,
      derive_prefix,
      character(1)
    ),

    proposed_role = dplyr::case_when(
      grepl("^p0__", feature) ~
        "frozen_upstream_baseline",

      grepl("^r47__local_geo_", feature) ~
        "local_lithology_full_representation",

      feature %in% compact_features ~
        "compact_lithology_core_representation",

      grepl(
        "^r47__local_minus_up_geo_",
        feature
      ) ~
        "contrast_sensitivity_only",

      TRUE ~
        "unresolved_candidate"
    ),

    proposed_full_model = dplyr::case_when(
      grepl("^p0__", feature) ~ "YES",

      grepl(
        "^r47__local_geo_",
        feature
      ) ~ "YES",

      feature %in% compact_features ~
        "NO_REDUNDANT_WITH_FULL_LOCAL",

      grepl(
        "^r47__local_minus_up_geo_",
        feature
      ) ~ "NO_SENSITIVITY_ONLY",

      quality_status != "model_ready_on_anchor" ~
        "NOT_READY",

      TRUE ~ ""
    ),

    proposed_core_model = dplyr::case_when(
      grepl("^p0__", feature) ~ "YES",

      grepl(
        "^r47__local_geo_",
        feature
      ) ~ "NO_REPLACED_BY_COMPACT",

      feature %in% compact_features ~ "YES",

      grepl(
        "^r47__local_minus_up_geo_",
        feature
      ) ~ "NO_SENSITIVITY_ONLY",

      quality_status != "model_ready_on_anchor" ~
        "NOT_READY",

      TRUE ~ ""
    ),

    initial_reason = dplyr::case_when(
      grepl("^p0__", feature) ~
        "Frozen upstream baseline; retained by design.",

      grepl(
        "^r47__local_geo_",
        feature
      ) ~
        paste(
          "Mechanistically explicit local lithology;",
          "retained in FULL irrespective of ablation performance."
        ),

      feature %in% compact_features ~
        paste(
          "Mechanism-based compact representation;",
          "used in CORE instead of the eight raw local fractions."
        ),

      grepl(
        "^r47__local_minus_up_geo_",
        feature
      ) ~
        paste(
          "Mathematically derived from local and upstream;",
          "reserved for sensitivity analysis to avoid structural redundancy."
        ),

      quality_status == "constant_on_anchor" ~
        "Constant on the frozen 4485-row sample.",

      quality_status ==
        "anchor_covered_with_missing_values" ~
        "Requires a predeclared missing-data strategy.",

      quality_status ==
        "requires_row_alignment_proof" ~
        "Cannot be joined until row order or row identity is proven.",

      TRUE ~
        "Requires mechanism-based manual decision."
    ),

    needs_manual_review =
      proposed_role == "unresolved_candidate" |
      suggested_mechanism_group == "unclassified" |
      quality_status != "model_ready_on_anchor"
  ) |>
  dplyr::select(
    feature,
    feature_prefix,
    preferred_source_file,
    column_type,
    suggested_mechanism_group,
    suggested_spatial_scale,
    derivation_guess,
    quality_status,
    anchor_coverage_n,
    anchor_missing_fraction,
    anchor_n_unique,
    proposed_role,
    proposed_full_model,
    proposed_core_model,
    initial_reason,
    needs_manual_review
  ) |>
  dplyr::arrange(
    proposed_role,
    suggested_mechanism_group,
    feature
  )

write_csv_safe(
  curation,
  file.path(
    review_dir,
    "curation_seed.csv"
  )
)

# ==============================================================================
# Model-ready variables that still need a scientific decision
# ==============================================================================

model_ready_unresolved <- curation |>
  dplyr::filter(
    quality_status == "model_ready_on_anchor",
    proposed_role == "unresolved_candidate"
  ) |>
  dplyr::arrange(
    suggested_mechanism_group,
    feature_prefix,
    feature
  )

write_csv_safe(
  model_ready_unresolved,
  file.path(
    review_dir,
    "model_ready_unresolved.csv"
  )
)

unclassified_model_ready <- model_ready_unresolved |>
  dplyr::filter(
    suggested_mechanism_group == "unclassified"
  )

write_csv_safe(
  unclassified_model_ready,
  file.path(
    review_dir,
    "unclassified_model_ready.csv"
  )
)

# ==============================================================================
# Variables requiring row-alignment proof
# ==============================================================================

alignment_review <- curation |>
  dplyr::filter(
    quality_status ==
      "requires_row_alignment_proof"
  ) |>
  dplyr::arrange(
    preferred_source_file,
    suggested_mechanism_group,
    feature
  )

write_csv_safe(
  alignment_review,
  file.path(
    review_dir,
    "row_alignment_review.csv"
  )
)

# ==============================================================================
# Variables with missing values on anchor
# ==============================================================================

missing_value_review <- curation |>
  dplyr::filter(
    quality_status ==
      "anchor_covered_with_missing_values"
  ) |>
  dplyr::arrange(
    anchor_missing_fraction,
    suggested_mechanism_group,
    feature
  )

write_csv_safe(
  missing_value_review,
  file.path(
    review_dir,
    "missing_value_review.csv"
  )
)

# ==============================================================================
# Summaries by prefix, source and mechanism
# ==============================================================================

prefix_summary <- curation |>
  dplyr::count(
    feature_prefix,
    suggested_mechanism_group,
    quality_status,
    name = "n_features"
  ) |>
  dplyr::arrange(
    feature_prefix,
    suggested_mechanism_group,
    quality_status
  )

write_csv_safe(
  prefix_summary,
  file.path(
    review_dir,
    "prefix_summary.csv"
  )
)

source_summary <- raw |>
  dplyr::filter(
    eligible_as_predictor
  ) |>
  dplyr::group_by(
    source_file
  ) |>
  dplyr::summarise(
    n_candidate_columns =
      dplyr::n_distinct(feature),

    n_model_ready =
      dplyr::n_distinct(
        feature[
          quality_status ==
            "model_ready_on_anchor"
        ]
      ),

    n_with_missing =
      dplyr::n_distinct(
        feature[
          quality_status ==
            "anchor_covered_with_missing_values"
        ]
      ),

    n_alignment_unproven =
      dplyr::n_distinct(
        feature[
          quality_status ==
            "requires_row_alignment_proof"
        ]
      ),

    .groups = "drop"
  ) |>
  dplyr::arrange(
    dplyr::desc(n_model_ready),
    source_file
  )

write_csv_safe(
  source_summary,
  file.path(
    review_dir,
    "source_summary.csv"
  )
)

# ==============================================================================
# Create compact plain-text review
# ==============================================================================

format_feature_section <- function(
  data,
  heading,
  max_rows = 250L
) {
  lines <- c(
    "",
    heading,
    paste(
      rep("-", nchar(heading)),
      collapse = ""
    )
  )

  if (nrow(data) == 0L) {
    return(
      c(
        lines,
        "NONE"
      )
    )
  }

  display <- data |>
    dplyr::select(
      feature,
      suggested_mechanism_group,
      preferred_source_file,
      quality_status
    ) |>
    head(max_rows)

  display_lines <- apply(
    display,
    1,
    function(x) {
      paste0(
        x[[1]],
        " | ",
        x[[2]],
        " | ",
        x[[3]],
        " | ",
        x[[4]]
      )
    }
  )

  c(
    lines,
    display_lines
  )
}

review_text <- c(
  "R49B FEATURE CURATION REVIEW",
  "============================",
  "",
  paste0(
    "Total unique candidates: ",
    nrow(curation)
  ),
  paste0(
    "Model-ready unresolved: ",
    nrow(model_ready_unresolved)
  ),
  paste0(
    "Unclassified and model-ready: ",
    nrow(unclassified_model_ready)
  ),
  paste0(
    "Require row-alignment proof: ",
    nrow(alignment_review)
  ),
  paste0(
    "Contain missing values on anchor: ",
    nrow(missing_value_review)
  ),
  "",
  "No decisions in this report use model performance.",
  "",
  format_feature_section(
    model_ready_unresolved,
    "MODEL-READY UNRESOLVED FEATURES"
  ),
  format_feature_section(
    unclassified_model_ready,
    "UNCLASSIFIED MODEL-READY FEATURES"
  ),
  format_feature_section(
    alignment_review,
    "ROW-ALIGNMENT REVIEW"
  ),
  "",
  "EXACT DUPLICATE GROUPS",
  "----------------------",
  capture.output(
    print(
      exact_duplicates,
      n = Inf,
      width = Inf
    )
  ),
  "",
  "KNOWN STRUCTURAL RELATIONSHIPS",
  "------------------------------",
  capture.output(
    print(
      structural_relationships,
      n = Inf,
      width = Inf
    )
  )
)

writeLines(
  review_text,
  file.path(
    review_dir,
    "review_report.txt"
  )
)

summary <- tibble::tibble(
  item = c(
    "total_unique_candidates",
    "frozen_p0",
    "full_local_lithology",
    "core_compact_lithology",
    "contrast_sensitivity",
    "model_ready_unresolved",
    "unclassified_model_ready",
    "requires_row_alignment_proof",
    "anchor_with_missing_values",
    "exact_duplicate_groups"
  ),

  n = c(
    nrow(curation),
    sum(curation$proposed_role ==
          "frozen_upstream_baseline"),
    sum(curation$proposed_role ==
          "local_lithology_full_representation"),
    sum(curation$proposed_role ==
          "compact_lithology_core_representation"),
    sum(curation$proposed_role ==
          "contrast_sensitivity_only"),
    nrow(model_ready_unresolved),
    nrow(unclassified_model_ready),
    nrow(alignment_review),
    nrow(missing_value_review),
    nrow(exact_duplicates)
  )
)

write_csv_safe(
  summary,
  file.path(
    review_dir,
    "review_summary.csv"
  )
)

cat(
  paste(
    review_text,
    collapse = "\n"
  ),
  "\n"
)

log_msg(
  "R49b feature-curation review completed."
)
