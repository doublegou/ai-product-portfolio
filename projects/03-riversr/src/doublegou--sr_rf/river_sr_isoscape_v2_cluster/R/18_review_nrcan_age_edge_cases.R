suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
})

input_dir <- file.path(
  "outputs",
  "nrcan_of5529",
  "age_gap_diagnosis"
)

output_dir <- file.path(
  "outputs",
  "nrcan_of5529",
  "age_edge_review"
)

dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

diagnosis_path <- file.path(
  input_dir,
  "runo_gap_diagnosis.csv"
)

entity_path <- file.path(
  input_dir,
  "entity_age_with_fallback.csv"
)

if (!file.exists(diagnosis_path)) {
  stop("Missing diagnosis file: ", diagnosis_path)
}

if (!file.exists(entity_path)) {
  stop("Missing entity-age file: ", entity_path)
}

diagnosis <- read_csv(
  diagnosis_path,
  show_col_types = FALSE
)

entity_age <- read_csv(
  entity_path,
  show_col_types = FALSE
)

edge_runo <- diagnosis |>
  filter(
    resolution_class !=
      "single_default_complete"
  ) |>
  arrange(
    resolution_class,
    desc(n_polygon_parts),
    RUNO
  )

no_rudt <- diagnosis |>
  filter(
    resolution_class ==
      "no_rudt_entity"
  ) |>
  arrange(
    desc(n_polygon_parts)
  )

nonstandard_unresolved <- diagnosis |>
  filter(
    resolution_class %in% c(
      "default_without_age_record",
      "no_default_entity",
      "unresolved_start",
      "unresolved_end",
      "unresolved_start_and_end",
      "other_incomplete"
    )
  ) |>
  left_join(
    entity_age |>
      select(
        RUNO,
        ID2,
        RUNO_ID2,
        RUCODE,
        DEFLT,
        OFFSHORE,
        AREAOFPLY,
        PERCENPLY,
        STARTAGE,
        STARTQU,
        STARTCAT,
        ENDCAT,
        ENDAGE,
        ENDQU,
        ENDCAT,
        start_match_method,
        end_match_method,
        resolved_oldest_ma,
        resolved_youngest_ma,
        complete_resolved_age,
        valid_age_order
      ),
    by = "RUNO"
  ) |>
  arrange(
    resolution_class,
    RUNO,
    ID2
  )

default_complete <- entity_age |>
  filter(
    is_default %in% TRUE,
    complete_resolved_age %in% TRUE,
    valid_age_order %in% TRUE
  )

multiple_complete <- diagnosis |>
  filter(
    resolution_class %in% c(
      "multiple_complete_default_entities",
      "one_complete_among_multiple_defaults"
    )
  ) |>
  select(
    RUNO,
    resolution_class,
    n_polygon_parts,
    groups
  ) |>
  left_join(
    entity_age |>
      filter(
        is_default %in% TRUE
      ),
    by = "RUNO"
  ) |>
  arrange(
    RUNO,
    ID2
  )

multiple_summary <- multiple_complete |>
  group_by(
    RUNO,
    resolution_class,
    n_polygon_parts,
    groups
  ) |>
  summarise(
    n_default_rows = n(),

    n_complete_rows = sum(
      complete_resolved_age %in% TRUE &
        valid_age_order %in% TRUE,
      na.rm = TRUE
    ),

    n_positive_percent_weights = sum(
      is.finite(PERCENPLY) &
        PERCENPLY > 0,
      na.rm = TRUE
    ),

    percent_weight_sum = sum(
      PERCENPLY[
        is.finite(PERCENPLY) &
          PERCENPLY > 0
      ],
      na.rm = TRUE
    ),

    n_positive_area_weights = sum(
      is.finite(AREAOFPLY) &
        AREAOFPLY > 0,
      na.rm = TRUE
    ),

    area_weight_sum = sum(
      AREAOFPLY[
        is.finite(AREAOFPLY) &
          AREAOFPLY > 0
      ],
      na.rm = TRUE
    ),

    n_distinct_age_ranges =
      n_distinct(
        paste(
          resolved_oldest_ma,
          resolved_youngest_ma,
          sep = "_"
        )[
          complete_resolved_age %in% TRUE &
            valid_age_order %in% TRUE
        ]
      ),

    minimum_oldest_ma = suppressWarnings(
      min(
        resolved_oldest_ma[
          complete_resolved_age %in% TRUE
        ],
        na.rm = TRUE
      )
    ),

    maximum_oldest_ma = suppressWarnings(
      max(
        resolved_oldest_ma[
          complete_resolved_age %in% TRUE
        ],
        na.rm = TRUE
      )
    ),

    minimum_youngest_ma = suppressWarnings(
      min(
        resolved_youngest_ma[
          complete_resolved_age %in% TRUE
        ],
        na.rm = TRUE
      )
    ),

    maximum_youngest_ma = suppressWarnings(
      max(
        resolved_youngest_ma[
          complete_resolved_age %in% TRUE
        ],
        na.rm = TRUE
      )
    ),

    .groups = "drop"
  ) |>
  mutate(
    across(
      c(
        minimum_oldest_ma,
        maximum_oldest_ma,
        minimum_youngest_ma,
        maximum_youngest_ma
      ),
      ~ ifelse(
        is.infinite(.x),
        NA_real_,
        .x
      )
    ),

    weight_status = case_when(
      n_positive_percent_weights ==
        n_complete_rows &
        percent_weight_sum > 0 ~
        "complete_percent_weights",

      n_positive_area_weights ==
        n_complete_rows &
        area_weight_sum > 0 ~
        "complete_area_weights",

      n_positive_percent_weights > 0 |
        n_positive_area_weights > 0 ~
        "partial_weights",

      TRUE ~
        "no_positive_weights"
    )
  ) |>
  arrange(
    weight_status,
    RUNO
  )

weight_status_summary <- multiple_summary |>
  count(
    resolution_class,
    weight_status,
    name = "n_runo"
  ) |>
  arrange(
    resolution_class,
    weight_status
  )

write_csv(
  edge_runo,
  file.path(
    output_dir,
    "all_edge_runo.csv"
  )
)

write_csv(
  no_rudt,
  file.path(
    output_dir,
    "no_rudt_entity_runo.csv"
  )
)

write_csv(
  nonstandard_unresolved,
  file.path(
    output_dir,
    "unresolved_entity_details.csv"
  )
)

write_csv(
  multiple_complete,
  file.path(
    output_dir,
    "multiple_default_entity_details.csv"
  )
)

write_csv(
  multiple_summary,
  file.path(
    output_dir,
    "multiple_default_summary.csv"
  )
)

write_csv(
  weight_status_summary,
  file.path(
    output_dir,
    "multiple_default_weight_status.csv"
  )
)

cat("\n========================================\n")
cat("NRCan AGE EDGE-CASE REVIEW\n")
cat("========================================\n")

cat("\nRUNO without RUDT entities:\n")

print(
  no_rudt,
  n = Inf,
  width = Inf
)

cat("\nUnresolved or nonstandard records:\n")

print(
  nonstandard_unresolved,
  n = Inf,
  width = Inf
)

cat("\nMultiple-default weight status:\n")

print(
  weight_status_summary,
  n = Inf,
  width = Inf
)

cat("\nMultiple-default RUNO summary:\n")

print(
  multiple_summary,
  n = Inf,
  width = Inf
)

cat("\nOutputs saved to:\n")
cat(output_dir, "\n")
