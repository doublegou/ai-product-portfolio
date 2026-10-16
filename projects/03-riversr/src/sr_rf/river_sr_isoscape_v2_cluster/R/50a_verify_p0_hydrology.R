source("R/functions/core.R")

check_packages(
  c(
    "dplyr",
    "readr",
    "tibble"
  )
)

cfg <- read_config()
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
  "verification"
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

if (nrow(anchor) != 4485L) {
  stop(
    "Anchor does not contain 4485 rows."
  )
}

if (nrow(hydrology) != 4485L) {
  stop(
    "Hydrology table does not contain 4485 rows."
  )
}

if (anyDuplicated(anchor$site_id)) {
  stop(
    "Anchor site_id is not unique."
  )
}

if (anyDuplicated(hydrology$site_id)) {
  stop(
    "Hydrology site_id is not unique."
  )
}

if (!setequal(
  as.character(anchor$site_id),
  as.character(hydrology$site_id)
)) {
  stop(
    "Anchor and hydrology site_id sets differ."
  )
}

hydrology_index <- match(
  as.character(anchor$site_id),
  as.character(hydrology$site_id)
)

if (
  anyNA(hydrology_index) ||
  anyDuplicated(hydrology_index)
) {
  stop(
    "site_id did not produce a complete one-to-one mapping."
  )
}

hydrology_aligned <- hydrology[
  hydrology_index,
  ,
  drop = FALSE
]

if (!identical(
  as.character(anchor$site_id),
  as.character(hydrology_aligned$site_id)
)) {
  stop(
    "Hydrology alignment failed to reproduce anchor site order."
  )
}

compare_numeric <- function(
  anchor_values,
  hydrology_values,
  tolerance = 1e-12
) {
  anchor_values <- as.numeric(
    anchor_values
  )

  hydrology_values <- as.numeric(
    hydrology_values
  )

  both_missing <-
    is.na(anchor_values) &
    is.na(hydrology_values)

  both_observed <-
    !is.na(anchor_values) &
    !is.na(hydrology_values)

  differences <- rep(
    NA_real_,
    length(anchor_values)
  )

  differences[both_observed] <-
    abs(
      anchor_values[both_observed] -
        hydrology_values[both_observed]
    )

  matches <-
    both_missing |
    (
      both_observed &
      differences <= tolerance
    )

  tibble::tibble(
    n = length(anchor_values),
    n_anchor_missing =
      sum(is.na(anchor_values)),
    n_hydrology_missing =
      sum(is.na(hydrology_values)),
    n_matching =
      sum(matches),
    match_fraction =
      mean(matches),
    max_absolute_difference =
      if (all(is.na(differences))) {
        NA_real_
      } else {
        max(
          differences,
          na.rm = TRUE
        )
      },
    tolerance = tolerance,
    all_match = all(matches)
  )
}

comparison_plan <- tibble::tribble(
  ~mechanism_group,
  ~anchor_feature,
  ~hydrology_feature,

  "alignment_control",
  "longitude",
  "longitude",

  "alignment_control",
  "latitude",
  "latitude",

  "outcome_control",
  "sr87_sr86",
  "sr",

  "hydrological_transport",
  "p0__log_DIS_AV_CMS",
  "log_DIS_AV_CMS",

  "catchment_integration",
  "p0__log_UPLAND_SKM",
  "log_UPLAND_SKM",

  "catchment_integration",
  "p0__log_CATCH_SKM",
  "log_CATCH_SKM",

  "network_scale",
  "p0__log_LENGTH_KM",
  "log_LENGTH_KM",

  "network_position",
  "p0__log_DIST_DN_KM",
  "log_DIST_DN_KM",

  "network_position",
  "p0__log_DIST_UP_KM",
  "log_DIST_UP_KM",

  "network_hierarchy",
  "p0__ORD_STRA",
  "ORD_STRA",

  "network_hierarchy",
  "p0__ORD_CLAS",
  "ORD_CLAS",

  "network_hierarchy",
  "p0__ORD_FLOW",
  "ORD_FLOW"
)

comparison_results <- dplyr::bind_rows(
  lapply(
    seq_len(
      nrow(comparison_plan)
    ),
    function(index) {
      anchor_feature <-
        comparison_plan$
          anchor_feature[[index]]

      hydrology_feature <-
        comparison_plan$
          hydrology_feature[[index]]

      tolerance <- if (
        comparison_plan$
          mechanism_group[[index]] ==
          "alignment_control"
      ) {
        1e-8
      } else {
        1e-12
      }

      result <- compare_numeric(
        anchor[[
          anchor_feature
        ]],
        hydrology_aligned[[
          hydrology_feature
        ]],
        tolerance = tolerance
      )

      dplyr::bind_cols(
        comparison_plan[
          index,
          ,
          drop = FALSE
        ],
        result
      )
    }
  )
)

readr::write_csv(
  comparison_results,
  file.path(
    out_dir,
    "p0_hydrology_equivalence.csv"
  )
)

site_alignment_summary <- tibble::tibble(
  check = c(
    "row_count",
    "unique_anchor_site_id",
    "unique_hydrology_site_id",
    "site_id_set_equality",
    "site_id_mapping_complete",
    "site_id_order_after_alignment"
  ),

  passed = c(
    nrow(anchor) == nrow(hydrology),
    !anyDuplicated(anchor$site_id),
    !anyDuplicated(hydrology$site_id),
    setequal(
      as.character(anchor$site_id),
      as.character(hydrology$site_id)
    ),
    !anyNA(hydrology_index) &&
      !anyDuplicated(hydrology_index),
    identical(
      as.character(anchor$site_id),
      as.character(
        hydrology_aligned$site_id
      )
    )
  )
)

readr::write_csv(
  site_alignment_summary,
  file.path(
    out_dir,
    "site_alignment_summary.csv"
  )
)

hydrology_rows <- comparison_results |>
  dplyr::filter(
    mechanism_group %in%
      c(
        "hydrological_transport",
        "catchment_integration",
        "network_scale",
        "network_position",
        "network_hierarchy"
      )
  )

all_alignment_passed <- all(
  site_alignment_summary$passed
)

all_hydrology_equal <- all(
  hydrology_rows$all_match
)

decision <- tibble::tibble(
  decision_item = c(
    "site_alignment_proven",
    "p0_hydrology_exactly_reproduced",
    "add_hydrology_as_new_module",
    "retain_existing_p0_hydrology"
  ),

  decision = c(
    all_alignment_passed,
    all_hydrology_equal,
    FALSE,
    all_alignment_passed &&
      all_hydrology_equal
  ),

  rationale = c(
    "Anchor and source table align one-to-one using site_id.",
    paste(
      "All nine P0 hydrology variables reproduce",
      "the aligned source variables within declared tolerance."
    ),
    paste(
      "Hydrology is already encoded in P0;",
      "adding it again would duplicate predictors."
    ),
    paste(
      "Existing p0__ hydrology fields remain part",
      "of both CORE and FULL through the frozen P0 baseline."
    )
  )
)

readr::write_csv(
  decision,
  file.path(
    out_dir,
    "hydrology_model_decision.csv"
  )
)

if (!all_alignment_passed) {
  stop(
    "One or more site-alignment checks failed."
  )
}

if (!all_hydrology_equal) {
  failed <- hydrology_rows |>
    dplyr::filter(
      !all_match
    )

  print(
    failed,
    width = 200
  )

  stop(
    "One or more P0 hydrology variables do not match their source fields."
  )
}

summary_lines <- c(
  "R50A P0 HYDROLOGY VERIFICATION",
  "==============================",
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
    "Unique aligned site IDs: ",
    length(
      unique(anchor$site_id)
    )
  ),
  "",
  paste0(
    "Site alignment proven: ",
    all_alignment_passed
  ),
  paste0(
    "Nine P0 hydrology variables exactly reproduced: ",
    all_hydrology_equal
  ),
  "",
  "MODEL DECISION:",
  "Do not add a separate hydrology module.",
  "The hydrology variables are already part of the frozen P0 baseline.",
  "",
  "P0 hydrology retained:",
  paste(
    hydrology_rows$anchor_feature,
    collapse = ", "
  ),
  "",
  "No decision used model performance.",
  "",
  "STATUS: ALL R50A HYDROLOGY VERIFICATION INVARIANTS PASSED"
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
