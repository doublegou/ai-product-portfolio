#!/usr/bin/env Rscript

options(
  stringsAsFactors = FALSE,
  warn = 1
)

suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(readr)
  library(tibble)
})

age_path <- paste0(
  "outputs/nrcan_of5529/final_age_crosswalk/",
  "roxworld_age_wgs84.gpkg"
)

overlap_path <- paste0(
  "outputs/nrcan_age_hydrobasins_l6/",
  "repair_checks/",
  "si_target_basin_pairwise_geology_overlap.csv"
)

output_dir <- paste0(
  "outputs/nrcan_age_hydrobasins_l6/",
  "repair_checks"
)

target_runo <- c(
  3916,
  3978,
  3982,
  3977,
  3991
)

if (!file.exists(age_path)) {
  stop(
    "Missing geology layer: ",
    age_path
  )
}

if (!file.exists(overlap_path)) {
  stop(
    "Missing overlap table: ",
    overlap_path
  )
}


cat("Reading target geological units...\n")

age <- st_read(
  age_path,
  layer = "roxworld_age",
  quiet = TRUE
)

age$original_feature_row <- seq_len(
  nrow(age)
)

units <- age %>%
  filter(
    RUNO %in% target_runo
  )

if (nrow(units) != length(target_runo)) {

  cat(
    "Target RUNOs requested: ",
    length(target_runo),
    "; features found: ",
    nrow(units),
    "\n",
    sep = ""
  )
}


units_equal <- units %>%
  st_make_valid() %>%
  st_transform(6933)

units$total_polygon_area_km2 <- as.numeric(
  st_area(units_equal)
) / 1e6


overlap <- read_csv(
  overlap_path,
  show_col_types = FALSE
)


overlap_by_unit_1 <- overlap %>%
  transmute(
    RUNO = RUNO_1,
    overlap_area_km2
  )

overlap_by_unit_2 <- overlap %>%
  transmute(
    RUNO = RUNO_2,
    overlap_area_km2
  )

overlap_summary <- bind_rows(
  overlap_by_unit_1,
  overlap_by_unit_2
) %>%
  group_by(RUNO) %>%
  summarise(
    target_pairwise_overlap_km2 = sum(
      overlap_area_km2,
      na.rm = TRUE
    ),
    overlap_pair_count = n(),
    .groups = "drop"
  )


units_attributes <- units %>%
  st_drop_geometry() %>%
  left_join(
    overlap_summary,
    by = "RUNO"
  ) %>%
  mutate(
    target_pairwise_overlap_km2 = coalesce(
      target_pairwise_overlap_km2,
      0
    ),

    overlap_pair_count = coalesce(
      overlap_pair_count,
      0L
    ),

    overlap_fraction_of_total_polygon = ifelse(
      total_polygon_area_km2 > 0,
      target_pairwise_overlap_km2 /
        total_polygon_area_km2,
      NA_real_
    )
  ) %>%
  arrange(RUNO)


write_csv(
  units_attributes,
  file.path(
    output_dir,
    "si_overlap_units_full_attributes.csv"
  )
)


candidate_attribute_names <- names(
  units_attributes
)[
  grepl(
    paste0(
      "RUNO|AGE|DESC|NAME|ROCK|LITH|UNIT|",
      "TYPE|SOURCE|CAT|CONF|METHOD|STATUS|",
      "START|END|MIDPOINT|RESOLVED|PERCENT"
    ),
    names(units_attributes),
    ignore.case = TRUE
  )
]

always_keep <- c(
  "original_feature_row",
  "RUNO",
  "resolved",
  "weighted_mean_midpoint_ma",
  "weighted_sd_midpoint_ma",
  "maximum_oldest_ma",
  "minimum_youngest_ma",
  "total_polygon_area_km2",
  "target_pairwise_overlap_km2",
  "overlap_pair_count",
  "overlap_fraction_of_total_polygon"
)

compact_columns <- unique(
  c(
    always_keep[
      always_keep %in%
        names(units_attributes)
    ],
    candidate_attribute_names
  )
)

compact <- units_attributes %>%
  select(
    all_of(compact_columns)
  )


write_csv(
  compact,
  file.path(
    output_dir,
    "si_overlap_units_compact_attributes.csv"
  )
)


cat("\n===== TARGET UNIT AREA SUMMARY =====\n")

area_summary <- units_attributes %>%
  select(
    any_of(
      c(
        "original_feature_row",
        "RUNO",
        "resolved",
        "weighted_mean_midpoint_ma",
        "weighted_sd_midpoint_ma",
        "maximum_oldest_ma",
        "minimum_youngest_ma",
        "total_polygon_area_km2",
        "target_pairwise_overlap_km2",
        "overlap_pair_count",
        "overlap_fraction_of_total_polygon"
      )
    )
  )

print(
  as_tibble(area_summary),
  n = Inf,
  width = Inf
)


cat("\n===== AVAILABLE DESCRIPTIVE FIELDS =====\n")

cat(
  paste(
    candidate_attribute_names,
    collapse = "\n"
  ),
  "\n"
)


cat("\n===== COMPACT UNIT ATTRIBUTES =====\n")

print(
  as_tibble(compact),
  n = Inf,
  width = Inf
)


cat("\nOutputs written to:\n")

cat(
  file.path(
    output_dir,
    "si_overlap_units_full_attributes.csv"
  ),
  "\n"
)

cat(
  file.path(
    output_dir,
    "si_overlap_units_compact_attributes.csv"
  ),
  "\n"
)
