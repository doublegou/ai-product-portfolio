source("R/functions/core.R")

check_packages(
  c(
    "dplyr",
    "readr",
    "tibble"
  )
)

root <- project_root()

anchor_file <- file.path(
  root,
  "data",
  "processed",
  "model_table_p0_full_range_r47_hybrid_local_lithology.rds"
)

hydrology_file <- file.path(
  root,
  "outputs",
  "full_range_rescue",
  "full_range_5km_site_base.rds"
)

out_dir <- file.path(
  root,
  "outputs",
  "r50_hydrology_alignment",
  "verification_v3"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

anchor <- as.data.frame(
  readRDS(anchor_file)
)

hydrology <- as.data.frame(
  readRDS(hydrology_file)
)

if (nrow(anchor) != 4485L) {
  stop(
    "Anchor row count is not 4485: ",
    nrow(anchor)
  )
}

if (nrow(hydrology) != 4485L) {
  stop(
    "Hydrology row count is not 4485: ",
    nrow(hydrology)
  )
}

verification_plan <- tibble::tribble(
  ~role,
  ~anchor_feature,
  ~hydrology_feature,
  ~tolerance,

  "coordinate_control",
  "longitude",
  "longitude",
  1e-8,

  "coordinate_control",
  "latitude",
  "latitude",
  1e-8,

  "hydrological_transport",
  "p0__log_DIS_AV_CMS",
  "log_DIS_AV_CMS",
  1e-12,

  "catchment_integration",
  "p0__log_UPLAND_SKM",
  "log_UPLAND_SKM",
  1e-12,

  "catchment_integration",
  "p0__log_CATCH_SKM",
  "log_CATCH_SKM",
  1e-12,

  "network_scale",
  "p0__log_LENGTH_KM",
  "log_LENGTH_KM",
  1e-12,

  "network_position",
  "p0__log_DIST_DN_KM",
  "log_DIST_DN_KM",
  1e-12,

  "network_position",
  "p0__log_DIST_UP_KM",
  "log_DIST_UP_KM",
  1e-12,

  "network_hierarchy",
  "p0__ORD_STRA",
  "ORD_STRA",
  1e-12,

  "network_hierarchy",
  "p0__ORD_CLAS",
  "ORD_CLAS",
  1e-12,

  "network_hierarchy",
  "p0__ORD_FLOW",
  "ORD_FLOW",
  1e-12
)

required_anchor <- unique(
  c(
    "row_id",
    "site_id",
    "sr87_sr86",
    verification_plan$anchor_feature
  )
)

required_hydrology <- unique(
  c(
    "global_row_id",
    "site_id",
    "sr",
    verification_plan$hydrology_feature
  )
)

missing_anchor <- setdiff(
  required_anchor,
  names(anchor)
)

missing_hydrology <- setdiff(
  required_hydrology,
  names(hydrology)
)

if (length(missing_anchor) > 0L) {
  stop(
    "Missing anchor variables: ",
    paste(
      missing_anchor,
      collapse = ", "
    )
  )
}

if (length(missing_hydrology) > 0L) {
  stop(
    "Missing hydrology variables: ",
    paste(
      missing_hydrology,
      collapse = ", "
    )
  )
}

compare_numeric <- function(
  x,
  y,
  tolerance
) {
  x <- suppressWarnings(
    as.numeric(x)
  )

  y <- suppressWarnings(
    as.numeric(y)
  )

  same_missing <-
    is.na(x) &
    is.na(y)

  both_present <-
    !is.na(x) &
    !is.na(y)

  differences <- rep(
    NA_real_,
    length(x)
  )

  differences[both_present] <-
    abs(
      x[both_present] -
        y[both_present]
    )

  matches <-
    same_missing |
    (
      both_present &
        differences <= tolerance
    )

  tibble::tibble(
    n = length(x),
    n_matching = sum(matches),
    match_fraction = mean(matches),
    max_absolute_difference =
      if (all(is.na(differences))) {
        NA_real_
      } else {
        max(
          differences,
          na.rm = TRUE
        )
      },
    all_match = all(matches)
  )
}

compare_with_index <- function(index) {
  dplyr::bind_rows(
    lapply(
      seq_len(
        nrow(verification_plan)
      ),
      function(i) {
        anchor_feature <-
          verification_plan$
            anchor_feature[[i]]

        hydrology_feature <-
          verification_plan$
            hydrology_feature[[i]]

        result <- compare_numeric(
          anchor[[anchor_feature]],
          hydrology[[
            hydrology_feature
          ]][index],
          verification_plan$
            tolerance[[i]]
        )

        dplyr::bind_cols(
          verification_plan[
            i,
            ,
            drop = FALSE
          ],
          result
        )
      }
    )
  )
}

# ==============================================================================
# Method 1: test whether current row order is already correct
# ==============================================================================

current_index <- seq_len(
  nrow(hydrology)
)

current_order_results <- compare_with_index(
  current_index
)

readr::write_csv(
  current_order_results,
  file.path(
    out_dir,
    "current_row_order_test.csv"
  )
)

hydrology_index <- NULL
alignment_method <- NA_character_
alignment_proof <- NA_character_

if (all(current_order_results$all_match)) {
  hydrology_index <- current_index

  alignment_method <-
    "current_row_order_proven_without_outcome"

  alignment_proof <- paste(
    "Longitude, latitude and all nine hydrology",
    "variables match row-by-row."
  )
}

# ==============================================================================
# Method 2: build a predictor fingerprint
# ==============================================================================

format_signature_value <- function(
  x,
  digits = 12L
) {
  x <- suppressWarnings(
    as.numeric(x)
  )

  result <- rep(
    "<NA>",
    length(x)
  )

  observed <- !is.na(x)

  result[observed] <- formatC(
    round(
      x[observed],
      digits
    ),
    format = "fg",
    digits = 15,
    flag = "#"
  )

  result
}

build_signature <- function(
  data,
  columns
) {
  formatted <- lapply(
    columns,
    function(column) {
      format_signature_value(
        data[[column]]
      )
    }
  )

  do.call(
    paste,
    c(
      formatted,
      sep = "|"
    )
  )
}

anchor_signature_columns <-
  verification_plan$anchor_feature

hydrology_signature_columns <-
  verification_plan$hydrology_feature

anchor_signature <- build_signature(
  anchor,
  anchor_signature_columns
)

hydrology_signature <- build_signature(
  hydrology,
  hydrology_signature_columns
)

fingerprint_diagnostics <- tibble::tibble(
  anchor_rows = length(
    anchor_signature
  ),

  hydrology_rows = length(
    hydrology_signature
  ),

  anchor_unique_signatures =
    dplyr::n_distinct(
      anchor_signature
    ),

  hydrology_unique_signatures =
    dplyr::n_distinct(
      hydrology_signature
    ),

  anchor_duplicate_signatures =
    sum(
      duplicated(
        anchor_signature
      )
    ),

  hydrology_duplicate_signatures =
    sum(
      duplicated(
        hydrology_signature
      )
    ),

  shared_signatures =
    length(
      intersect(
        anchor_signature,
        hydrology_signature
      )
    ),

  signature_sets_equal =
    setequal(
      anchor_signature,
      hydrology_signature
    )
)

readr::write_csv(
  fingerprint_diagnostics,
  file.path(
    out_dir,
    "predictor_fingerprint_diagnostics.csv"
  )
)

if (
  is.null(hydrology_index) &&
  !anyDuplicated(anchor_signature) &&
  !anyDuplicated(hydrology_signature) &&
  setequal(
    anchor_signature,
    hydrology_signature
  )
) {
  hydrology_index <- match(
    anchor_signature,
    hydrology_signature
  )

  alignment_method <-
    "coordinate_and_hydrology_predictor_fingerprint"

  alignment_proof <- paste(
    "Unique fingerprint using longitude, latitude",
    "and all nine P0 hydrology variables."
  )
}

if (
  is.null(hydrology_index) ||
  anyNA(hydrology_index) ||
  anyDuplicated(hydrology_index)
) {
  summary_lines <- c(
    "R50A P0 HYDROLOGY VERIFICATION V3",
    "=================================",
    "",
    "Neither current row order nor predictor fingerprint",
    "provided a complete one-to-one alignment.",
    "",
    "Inspect:",
    "current_row_order_test.csv",
    "predictor_fingerprint_diagnostics.csv",
    "",
    "STATUS: HYDROLOGY ALIGNMENT NOT PROVEN"
  )

  writeLines(
    summary_lines,
    file.path(
      out_dir,
      "run_summary.txt"
    )
  )

  stop(
    "Hydrology alignment could not be proven without using Sr."
  )
}

# ==============================================================================
# Final predictor verification
# ==============================================================================

final_results <- compare_with_index(
  hydrology_index
)

readr::write_csv(
  final_results,
  file.path(
    out_dir,
    "p0_hydrology_equivalence.csv"
  )
)

all_predictors_match <- all(
  final_results$all_match
)

if (!all_predictors_match) {
  failed_results <- final_results |>
    dplyr::filter(
      !all_match
    )

  readr::write_csv(
    failed_results,
    file.path(
      out_dir,
      "failed_predictor_comparisons.csv"
    )
  )

  stop(
    "Alignment was found, but one or more hydrology variables differ."
  )
}

# ==============================================================================
# Examine Sr differences separately
# ==============================================================================

anchor_sr <- as.numeric(
  anchor$sr87_sr86
)

source_sr <- as.numeric(
  hydrology$sr[
    hydrology_index
  ]
)

sr_difference <- abs(
  anchor_sr -
    source_sr
)

sr_matches <-
  (
    is.na(anchor_sr) &
      is.na(source_sr)
  ) |
  (
    !is.na(anchor_sr) &
      !is.na(source_sr) &
      sr_difference <= 1e-12
  )

sr_comparison_summary <- tibble::tibble(
  n = length(anchor_sr),
  n_matching = sum(sr_matches),
  n_different = sum(!sr_matches),
  match_fraction = mean(sr_matches),
  max_absolute_difference =
    max(
      sr_difference,
      na.rm = TRUE
    )
)

readr::write_csv(
  sr_comparison_summary,
  file.path(
    out_dir,
    "sr_version_comparison_summary.csv"
  )
)

sr_mismatch_rows <- tibble::tibble(
  anchor_row_number =
    seq_len(nrow(anchor)),

  hydrology_original_row_number =
    hydrology_index,

  anchor_row_id =
    anchor$row_id,

  anchor_site_id =
    anchor$site_id,

  hydrology_global_row_id =
    hydrology$global_row_id[
      hydrology_index
    ],

  hydrology_site_id =
    hydrology$site_id[
      hydrology_index
    ],

  longitude =
    anchor$longitude,

  latitude =
    anchor$latitude,

  anchor_sr87_sr86 =
    anchor_sr,

  source_sr =
    source_sr,

  absolute_difference =
    sr_difference
) |>
  dplyr::filter(
    !sr_matches
  )

readr::write_csv(
  sr_mismatch_rows,
  file.path(
    out_dir,
    "sr_version_mismatch_rows.csv"
  )
)

alignment_mapping <- tibble::tibble(
  anchor_row_number =
    seq_len(nrow(anchor)),

  hydrology_original_row_number =
    hydrology_index,

  anchor_row_id =
    anchor$row_id,

  anchor_site_id =
    anchor$site_id,

  hydrology_global_row_id =
    hydrology$global_row_id[
      hydrology_index
    ],

  hydrology_site_id =
    hydrology$site_id[
      hydrology_index
    ],

  alignment_method =
    alignment_method
)

readr::write_csv(
  alignment_mapping,
  file.path(
    out_dir,
    "alignment_mapping.csv"
  )
)

model_decision <- tibble::tibble(
  decision_item = c(
    "hydrology_alignment_proven",
    "all_nine_p0_hydrology_variables_match",
    "response_used_to_define_alignment",
    "separate_hydrology_module_required",
    "retain_p0_hydrology_in_core",
    "retain_p0_hydrology_in_full"
  ),

  decision = c(
    TRUE,
    all_predictors_match,
    FALSE,
    FALSE,
    all_predictors_match,
    all_predictors_match
  ),

  rationale = c(
    paste(
      alignment_method,
      alignment_proof,
      sep = ": "
    ),

    paste(
      "All nine P0 fields reproduce their",
      "source hydrology variables."
    ),

    paste(
      "Sr was excluded from alignment and assessed",
      "only as a separate version-control diagnostic."
    ),

    paste(
      "Adding another hydrology module would",
      "duplicate the frozen P0 variables."
    ),

    "Hydrology remains represented through P0.",

    "Hydrology remains represented through P0."
  )
)

readr::write_csv(
  model_decision,
  file.path(
    out_dir,
    "hydrology_model_decision.csv"
  )
)

summary_lines <- c(
  "R50A P0 HYDROLOGY VERIFICATION V3",
  "=================================",
  "",
  paste0(
    "Anchor rows: ",
    nrow(anchor)
  ),
  paste0(
    "Hydrology rows: ",
    nrow(hydrology)
  ),
  paste0(
    "Alignment method: ",
    alignment_method
  ),
  paste0(
    "Alignment proof: ",
    alignment_proof
  ),
  "",
  paste0(
    "All coordinate and hydrology fields match: ",
    all_predictors_match
  ),
  paste0(
    "Sr rows matching source version: ",
    sum(sr_matches),
    "/",
    length(sr_matches)
  ),
  paste0(
    "Sr version mismatches: ",
    sum(!sr_matches)
  ),
  "",
  "MODEL DECISION:",
  "Do not add a separate hydrology module.",
  "Hydrology is already contained in the frozen P0 baseline.",
  "Sr differences are retained as a version-control diagnostic only.",
  "",
  "No decision used model performance.",
  "",
  "STATUS: ALL R50A V3 HYDROLOGY VERIFICATION INVARIANTS PASSED"
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
