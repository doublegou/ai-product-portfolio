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
  "verification_v2"
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

required_anchor <- c(
  "row_id",
  "site_id",
  "longitude",
  "latitude",
  "sr87_sr86",
  "p0__log_DIS_AV_CMS",
  "p0__log_UPLAND_SKM",
  "p0__log_CATCH_SKM",
  "p0__log_LENGTH_KM",
  "p0__log_DIST_DN_KM",
  "p0__log_DIST_UP_KM",
  "p0__ORD_STRA",
  "p0__ORD_CLAS",
  "p0__ORD_FLOW"
)

required_hydrology <- c(
  "global_row_id",
  "site_id",
  "longitude",
  "latitude",
  "sr",
  "log_DIS_AV_CMS",
  "log_UPLAND_SKM",
  "log_CATCH_SKM",
  "log_LENGTH_KM",
  "log_DIST_DN_KM",
  "log_DIST_UP_KM",
  "ORD_STRA",
  "ORD_CLAS",
  "ORD_FLOW"
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
    "Missing anchor columns: ",
    paste(
      missing_anchor,
      collapse = ", "
    )
  )
}

if (length(missing_hydrology) > 0L) {
  stop(
    "Missing hydrology columns: ",
    paste(
      missing_hydrology,
      collapse = ", "
    )
  )
}

normalise_id <- function(x) {
  trimws(
    as.character(x)
  )
}

numeric_comparison <- function(
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

  same_missing <-
    is.na(x) &
    is.na(y)

  both_present <-
    !is.na(x) &
    !is.na(y)

  difference <- rep(
    NA_real_,
    length(x)
  )

  difference[both_present] <-
    abs(
      x[both_present] -
        y[both_present]
    )

  matched <-
    same_missing |
    (
      both_present &
        difference <= tolerance
    )

  list(
    all_match = all(matched),
    n_match = sum(matched),
    match_fraction = mean(matched),
    max_absolute_difference =
      if (all(is.na(difference))) {
        NA_real_
      } else {
        max(
          difference,
          na.rm = TRUE
        )
      }
  )
}

# ==============================================================================
# Examine all plausible identifier pairs
# ==============================================================================

id_pairs <- tibble::tribble(
  ~anchor_id, ~hydrology_id,
  "row_id", "global_row_id",
  "row_id", "site_id",
  "site_id", "global_row_id",
  "site_id", "site_id"
)

id_diagnostics <- dplyr::bind_rows(
  lapply(
    seq_len(
      nrow(id_pairs)
    ),
    function(i) {
      anchor_id <-
        id_pairs$anchor_id[[i]]

      hydrology_id <-
        id_pairs$hydrology_id[[i]]

      anchor_values <- normalise_id(
        anchor[[anchor_id]]
      )

      hydrology_values <- normalise_id(
        hydrology[[hydrology_id]]
      )

      tibble::tibble(
        anchor_id = anchor_id,
        hydrology_id = hydrology_id,

        anchor_unique =
          !anyDuplicated(anchor_values),

        hydrology_unique =
          !anyDuplicated(hydrology_values),

        intersection_n =
          length(
            intersect(
              anchor_values,
              hydrology_values
            )
          ),

        set_equal =
          setequal(
            anchor_values,
            hydrology_values
          ),

        current_rowwise_equal =
          identical(
            anchor_values,
            hydrology_values
          )
      )
    }
  )
)

readr::write_csv(
  id_diagnostics,
  file.path(
    out_dir,
    "identifier_diagnostics.csv"
  )
)

hydrology_index <- NULL
alignment_method <- NA_character_
alignment_proof <- NA_character_

# ==============================================================================
# Method 1: a genuine one-to-one identifier mapping
# ==============================================================================

for (i in seq_len(nrow(id_pairs))) {
  anchor_id <-
    id_pairs$anchor_id[[i]]

  hydrology_id <-
    id_pairs$hydrology_id[[i]]

  anchor_values <- normalise_id(
    anchor[[anchor_id]]
  )

  hydrology_values <- normalise_id(
    hydrology[[hydrology_id]]
  )

  if (
    !anyDuplicated(anchor_values) &&
    !anyDuplicated(hydrology_values) &&
    setequal(
      anchor_values,
      hydrology_values
    )
  ) {
    hydrology_index <- match(
      anchor_values,
      hydrology_values
    )

    alignment_method <-
      "direct_identifier_mapping"

    alignment_proof <- paste0(
      anchor_id,
      " = ",
      hydrology_id
    )

    break
  }
}

# ==============================================================================
# Verification plan
# ==============================================================================

verification_plan <- tibble::tribble(
  ~role, ~anchor_feature, ~hydrology_feature, ~tolerance,

  "alignment_control",
  "longitude",
  "longitude",
  1e-8,

  "alignment_control",
  "latitude",
  "latitude",
  1e-8,

  "outcome_alignment_control",
  "sr87_sr86",
  "sr",
  1e-12,

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

        tolerance <-
          verification_plan$
            tolerance[[i]]

        comparison <- numeric_comparison(
          anchor[[anchor_feature]],
          hydrology[
            index,
            hydrology_feature
          ],
          tolerance
        )

        tibble::tibble(
          role =
            verification_plan$
              role[[i]],

          anchor_feature =
            anchor_feature,

          hydrology_feature =
            hydrology_feature,

          tolerance =
            tolerance,

          n_match =
            comparison$n_match,

          match_fraction =
            comparison$match_fraction,

          max_absolute_difference =
            comparison$
              max_absolute_difference,

          all_match =
            comparison$all_match
        )
      }
    )
  )
}

# ==============================================================================
# Method 2: prove that current row order is already identical
# ==============================================================================

if (is.null(hydrology_index)) {
  current_order_index <-
    seq_len(nrow(hydrology))

  current_order_results <-
    compare_with_index(
      current_order_index
    )

  readr::write_csv(
    current_order_results,
    file.path(
      out_dir,
      "current_row_order_test.csv"
    )
  )

  if (all(current_order_results$all_match)) {
    hydrology_index <-
      current_order_index

    alignment_method <-
      "current_row_order_proven"

    alignment_proof <-
      paste(
        "longitude, latitude, Sr and all nine",
        "P0 hydrology variables match row-by-row"
      )
  }
}

# ==============================================================================
# Method 3: unique longitude-latitude-Sr composite key
# ==============================================================================

make_composite_key <- function(
  longitude,
  latitude,
  sr
) {
  paste(
    formatC(
      as.numeric(longitude),
      format = "f",
      digits = 7
    ),
    formatC(
      as.numeric(latitude),
      format = "f",
      digits = 7
    ),
    formatC(
      as.numeric(sr),
      format = "f",
      digits = 10
    ),
    sep = "|"
  )
}

anchor_key <- make_composite_key(
  anchor$longitude,
  anchor$latitude,
  anchor$sr87_sr86
)

hydrology_key <- make_composite_key(
  hydrology$longitude,
  hydrology$latitude,
  hydrology$sr
)

composite_key_diagnostics <- tibble::tibble(
  anchor_unique_keys =
    dplyr::n_distinct(anchor_key),

  hydrology_unique_keys =
    dplyr::n_distinct(hydrology_key),

  anchor_duplicate_keys =
    sum(duplicated(anchor_key)),

  hydrology_duplicate_keys =
    sum(duplicated(hydrology_key)),

  shared_keys =
    length(
      intersect(
        anchor_key,
        hydrology_key
      )
    ),

  set_equal =
    setequal(
      anchor_key,
      hydrology_key
    )
)

readr::write_csv(
  composite_key_diagnostics,
  file.path(
    out_dir,
    "composite_key_diagnostics.csv"
  )
)

if (
  is.null(hydrology_index) &&
  !anyDuplicated(anchor_key) &&
  !anyDuplicated(hydrology_key) &&
  setequal(
    anchor_key,
    hydrology_key
  )
) {
  hydrology_index <- match(
    anchor_key,
    hydrology_key
  )

  alignment_method <-
    "longitude_latitude_sr_composite_key"

  alignment_proof <-
    "unique longitude + latitude + Sr composite key"
}

# ==============================================================================
# Fail safely if no defensible alignment exists
# ==============================================================================

if (
  is.null(hydrology_index) ||
  anyNA(hydrology_index) ||
  anyDuplicated(hydrology_index) ||
  length(hydrology_index) != nrow(anchor)
) {
  summary_lines <- c(
    "R50A P0 HYDROLOGY VERIFICATION V2",
    "=================================",
    "",
    "No defensible one-to-one alignment was found.",
    "",
    "Inspect:",
    "identifier_diagnostics.csv",
    "current_row_order_test.csv",
    "composite_key_diagnostics.csv",
    "",
    "STATUS: ALIGNMENT NOT PROVEN"
  )

  writeLines(
    summary_lines,
    file.path(
      out_dir,
      "run_summary.txt"
    )
  )

  stop(
    "No defensible hydrology alignment was found."
  )
}

# ==============================================================================
# Final verification after alignment
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

hydrology_results <- final_results |>
  dplyr::filter(
    role %in%
      c(
        "hydrological_transport",
        "catchment_integration",
        "network_scale",
        "network_position",
        "network_hierarchy"
      )
  )

all_controls_match <- all(
  final_results$all_match
)

all_hydrology_match <- all(
  hydrology_results$all_match
)

mapping_table <- tibble::tibble(
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
  mapping_table,
  file.path(
    out_dir,
    "alignment_mapping.csv"
  )
)

model_decision <- tibble::tibble(
  decision_item = c(
    "alignment_proven",
    "all_alignment_controls_match",
    "all_nine_p0_hydrology_variables_match",
    "add_separate_hydrology_module",
    "retain_p0_hydrology_in_core",
    "retain_p0_hydrology_in_full"
  ),

  decision = c(
    TRUE,
    all_controls_match,
    all_hydrology_match,
    FALSE,
    all_hydrology_match,
    all_hydrology_match
  ),

  rationale = c(
    paste(
      alignment_method,
      alignment_proof,
      sep = ": "
    ),

    paste(
      "Longitude, latitude and Sr were used only",
      "as alignment controls."
    ),

    paste(
      "All nine source hydrology variables were",
      "compared with their existing P0 versions."
    ),

    paste(
      "A separate module would duplicate",
      "variables already contained in P0."
    ),

    "Hydrology remains represented through the frozen P0 baseline.",

    "Hydrology remains represented through the frozen P0 baseline."
  )
)

readr::write_csv(
  model_decision,
  file.path(
    out_dir,
    "hydrology_model_decision.csv"
  )
)

if (!all_controls_match) {
  stop(
    "Alignment was resolved but one or more control variables did not match."
  )
}

if (!all_hydrology_match) {
  failed <- hydrology_results |>
    dplyr::filter(
      !all_match
    )

  readr::write_csv(
    failed,
    file.path(
      out_dir,
      "failed_hydrology_comparisons.csv"
    )
  )

  stop(
    "Alignment was resolved but one or more P0 hydrology fields differed."
  )
}

summary_lines <- c(
  "R50A P0 HYDROLOGY VERIFICATION V2",
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
    "All controls match: ",
    all_controls_match
  ),
  paste0(
    "All nine P0 hydrology variables match: ",
    all_hydrology_match
  ),
  "",
  "MODEL DECISION:",
  "Do not add a separate hydrology module.",
  "Hydrology is already represented in the frozen P0 baseline.",
  "",
  "No decision used model performance.",
  "",
  "STATUS: ALL R50A V2 HYDROLOGY VERIFICATION INVARIANTS PASSED"
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
