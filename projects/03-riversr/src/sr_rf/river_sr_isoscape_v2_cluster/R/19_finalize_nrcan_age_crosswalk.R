suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(readr)
  library(tibble)
})

base_dir <- file.path(
  "data",
  "raw",
  "geology",
  "nrcan_of5529",
  "of_5529_selected"
)

gap_dir <- file.path(
  "outputs",
  "nrcan_of5529",
  "age_gap_diagnosis"
)

audit_dir <- file.path(
  "outputs",
  "nrcan_of5529",
  "rudbf_audit"
)

output_dir <- file.path(
  "outputs",
  "nrcan_of5529",
  "final_age_crosswalk"
)

dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

shp_path <- file.path(
  base_dir,
  "data",
  "ArcMap9_ArcReader9",
  "AllThemesMerged",
  "roxworld.shp"
)

entity_path <- file.path(
  gap_dir,
  "entity_age_with_fallback.rds"
)

diagnosis_path <- file.path(
  gap_dir,
  "runo_gap_diagnosis.csv"
)

tables_path <- file.path(
  audit_dir,
  "rudbf_tables.rds"
)

required_files <- c(
  shp_path,
  entity_path,
  diagnosis_path,
  tables_path
)

missing_files <- required_files[
  !file.exists(required_files)
]

if (length(missing_files) > 0L) {
  stop(
    "Missing required files:\n",
    paste(
      missing_files,
      collapse = "\n"
    )
  )
}

clean_text <- function(x) {

  x <- as.character(x)

  x <- iconv(
    x,
    from = "latin1",
    to = "UTF-8",
    sub = ""
  )

  x <- trimws(x)

  x[x == ""] <- NA_character_

  x
}

normalise_text <- function(x) {

  x <- clean_text(x)
  x <- toupper(x)

  x <- gsub(
    "[[:space:]]+",
    " ",
    x
  )

  x <- gsub(
    "[[:space:]]*,[[:space:]]*",
    ", ",
    x
  )

  trimws(x)
}

clean_numeric <- function(x) {
  suppressWarnings(
    as.numeric(
      clean_text(x)
    )
  )
}

cat("Reading source data...\n")

rox <- st_read(
  shp_path,
  quiet = TRUE,
  stringsAsFactors = FALSE
)

entity <- as_tibble(
  readRDS(entity_path)
)

diagnosis <- read_csv(
  diagnosis_path,
  show_col_types = FALSE
)

tables <- readRDS(tables_path)

if (!"agetsmlt" %in% names(tables)) {
  stop("agetsmlt table missing from DBF archive.")
}

age_lookup <- as_tibble(
  tables[["agetsmlt"]]
) |>
  transmute(
    AGEDES = clean_text(AGEDES),
    AGEQU = clean_text(AGEQU),
    AGEDESCAT = clean_text(AGEDESCAT),
    STARTMA = clean_numeric(STARTMA),
    ENDMA = clean_numeric(ENDMA),
    age_norm = normalise_text(AGEDES),
    qualifier_norm = normalise_text(AGEQU)
  )

jurassic_middle <- age_lookup |>
  filter(
    age_norm == "JURASSIC",
    qualifier_norm == "MIDDLE"
  )

if (nrow(jurassic_middle) != 1L) {
  stop(
    "Expected exactly one JURASSIC MIDDLE lookup row; found ",
    nrow(jurassic_middle)
  )
}

jurassic_middle_oldest <- jurassic_middle$STARTMA[[1]]
jurassic_middle_category <- jurassic_middle$AGEDESCAT[[1]]

cat("Applying documented spelling correction...\n")

entity <- entity |>
  mutate(
    manual_typo_correction =
      RUNO == 9403 &
      normalise_text(STARTAGE) ==
        "JURRASSIC" &
      normalise_text(STARTQU) ==
        "MIDDLE",

    original_STARTAGE = STARTAGE,
    original_STARTCAT = STARTCAT,

    corrected_STARTAGE = if_else(
      manual_typo_correction,
      "JURASSIC",
      STARTAGE
    ),

    corrected_STARTCAT = if_else(
      manual_typo_correction,
      jurassic_middle_category,
      STARTCAT
    ),

    resolved_oldest_ma = if_else(
      manual_typo_correction,
      jurassic_middle_oldest,
      resolved_oldest_ma
    ),

    start_match_method = if_else(
      manual_typo_correction,
      "manual_typo_correction",
      start_match_method
    ),

    complete_resolved_age =
      is.finite(resolved_oldest_ma) &
      is.finite(resolved_youngest_ma),

    valid_age_order = case_when(
      !complete_resolved_age ~ NA,
      resolved_oldest_ma >=
        resolved_youngest_ma ~ TRUE,
      TRUE ~ FALSE
    ),

    age_midpoint_ma = (
      resolved_oldest_ma +
      resolved_youngest_ma
    ) / 2,

    valid_complete =
      complete_resolved_age &
      valid_age_order %in% TRUE
  )

rox_attributes <- st_drop_geometry(rox) |>
  transmute(
    polygon_row = row_number(),
    RUNO = clean_numeric(RUNO),
    GROUP = clean_text(GROUP)
  )

runo_universe <- rox_attributes |>
  group_by(RUNO) |>
  summarise(
    n_polygon_rows = n(),
    groups = paste(
      sort(
        unique(
          GROUP[
            !is.na(GROUP)
          ]
        )
      ),
      collapse = ";"
    ),
    .groups = "drop"
  )

entity_stats <- entity |>
  group_by(RUNO) |>
  summarise(
    n_entities = n(),

    n_default_entities = sum(
      is_default %in% TRUE,
      na.rm = TRUE
    ),

    n_complete_default = sum(
      is_default %in% TRUE &
        valid_complete,
      na.rm = TRUE
    ),

    n_complete_all = sum(
      valid_complete,
      na.rm = TRUE
    ),

    n_distinct_default_age_ranges =
      n_distinct(
        paste(
          resolved_oldest_ma[
            is_default %in% TRUE &
              valid_complete
          ],
          resolved_youngest_ma[
            is_default %in% TRUE &
              valid_complete
          ],
          sep = "_"
        )
      ),

    n_positive_percent_weights = sum(
      is_default %in% TRUE &
        valid_complete &
        is.finite(PERCENPLY) &
        PERCENPLY > 0,
      na.rm = TRUE
    ),

    percent_weight_sum = sum(
      PERCENPLY[
        is_default %in% TRUE &
          valid_complete &
          is.finite(PERCENPLY) &
          PERCENPLY > 0
      ],
      na.rm = TRUE
    ),

    .groups = "drop"
  )

runo_status <- runo_universe |>
  left_join(
    entity_stats,
    by = "RUNO"
  ) |>
  left_join(
    diagnosis |>
      select(
        RUNO,
        original_resolution_class =
          resolution_class
      ),
    by = "RUNO"
  ) |>
  mutate(
    across(
      c(
        n_entities,
        n_default_entities,
        n_complete_default,
        n_complete_all,
        n_distinct_default_age_ranges,
        n_positive_percent_weights,
        percent_weight_sum
      ),
      ~ ifelse(
        is.na(.x),
        0,
        .x
      )
    ),

    has_complete_percent_weights =
      n_complete_default > 1 &
      n_positive_percent_weights ==
        n_complete_default &
      percent_weight_sum >= 99 &
      percent_weight_sum <= 101,

    resolution_method = case_when(
      n_entities == 0 ~
        "unresolved_no_entity",

      RUNO == 9403 &
        n_complete_default == 1 ~
        "manual_typo_correction",

      n_default_entities == 1 &
        n_complete_default == 1 ~
        "single_default_complete",

      n_default_entities > 1 &
        n_complete_default == 1 ~
        "one_complete_among_multiple_defaults",

      n_complete_default > 1 &
        n_distinct_default_age_ranges == 1 ~
        "multiple_defaults_same_age",

      n_complete_default > 1 &
        has_complete_percent_weights ~
        "multiple_defaults_percent_weighted",

      n_default_entities == 0 &
        n_complete_all == 1 ~
        "unique_complete_nondefault",

      n_complete_default > 1 ~
        "unresolved_multiple_without_weights",

      n_default_entities > 0 &
        n_complete_default == 0 ~
        "unresolved_no_age",

      TRUE ~
        "unresolved_other"
    ),

    resolved = !grepl(
      "^unresolved",
      resolution_method
    ),

    confidence_tier = case_when(
      resolution_method ==
        "single_default_complete" ~
        "high",

      resolution_method ==
        "multiple_defaults_same_age" ~
        "high",

      resolution_method ==
        "multiple_defaults_percent_weighted" ~
        "medium_high",

      resolution_method %in% c(
        "manual_typo_correction",
        "one_complete_among_multiple_defaults",
        "unique_complete_nondefault"
      ) ~
        "medium",

      TRUE ~
        "unresolved"
    )
  )

cat("Constructing resolved age components...\n")

single_methods <- c(
  "single_default_complete",
  "manual_typo_correction",
  "one_complete_among_multiple_defaults"
)

single_components <- entity |>
  inner_join(
    runo_status |>
      filter(
        resolution_method %in%
          single_methods
      ) |>
      select(
        RUNO,
        resolution_method,
        confidence_tier,
        n_entities,
        n_default_entities
      ),
    by = "RUNO"
  ) |>
  filter(
    is_default %in% TRUE,
    valid_complete
  ) |>
  group_by(RUNO) |>
  slice_head(n = 1) |>
  ungroup() |>
  mutate(
    component_weight = 1
  )

nondefault_components <- entity |>
  inner_join(
    runo_status |>
      filter(
        resolution_method ==
          "unique_complete_nondefault"
      ) |>
      select(
        RUNO,
        resolution_method,
        confidence_tier,
        n_entities,
        n_default_entities
      ),
    by = "RUNO"
  ) |>
  filter(
    valid_complete
  ) |>
  group_by(RUNO) |>
  slice_head(n = 1) |>
  ungroup() |>
  mutate(
    component_weight = 1
  )

same_age_components <- entity |>
  inner_join(
    runo_status |>
      filter(
        resolution_method ==
          "multiple_defaults_same_age"
      ) |>
      select(
        RUNO,
        resolution_method,
        confidence_tier,
        n_entities,
        n_default_entities
      ),
    by = "RUNO"
  ) |>
  filter(
    is_default %in% TRUE,
    valid_complete
  ) |>
  group_by(RUNO) |>
  slice_head(n = 1) |>
  ungroup() |>
  mutate(
    component_weight = 1
  )

weighted_components <- entity |>
  inner_join(
    runo_status |>
      filter(
        resolution_method ==
          "multiple_defaults_percent_weighted"
      ) |>
      select(
        RUNO,
        resolution_method,
        confidence_tier,
        n_entities,
        n_default_entities
      ),
    by = "RUNO"
  ) |>
  filter(
    is_default %in% TRUE,
    valid_complete,
    is.finite(PERCENPLY),
    PERCENPLY > 0
  ) |>
  group_by(RUNO) |>
  mutate(
    component_weight =
      PERCENPLY /
      sum(PERCENPLY)
  ) |>
  ungroup()

components <- bind_rows(
  single_components,
  nondefault_components,
  same_age_components,
  weighted_components
) |>
  transmute(
    RUNO,
    resolution_method,
    confidence_tier,
    source_ID2 = ID2,
    source_RUNO_ID2 = RUNO_ID2,
    RUCODE,
    is_default,
    component_weight,
    PERCENPLY,
    STARTAGE = corrected_STARTAGE,
    STARTQU,
    STARTCAT = corrected_STARTCAT,
    ENDAGE,
    ENDQU,
    ENDCAT,
    oldest_ma = resolved_oldest_ma,
    youngest_ma = resolved_youngest_ma,
    midpoint_ma = age_midpoint_ma,
    start_match_method,
    end_match_method,
    manual_typo_correction,
    original_STARTAGE,
    original_STARTCAT
  ) |>
  arrange(
    RUNO,
    desc(component_weight),
    source_ID2
  )

component_weight_qc <- components |>
  group_by(RUNO) |>
  summarise(
    component_weight_sum =
      sum(component_weight),
    .groups = "drop"
  ) |>
  filter(
    abs(
      component_weight_sum - 1
    ) > 1e-8
  )

if (nrow(component_weight_qc) > 0L) {
  stop(
    "Component weights do not sum to one for ",
    nrow(component_weight_qc),
    " RUNO values."
  )
}

cat("Summarising RUNO-level ages...\n")

component_means <- components |>
  group_by(RUNO) |>
  mutate(
    weighted_mean_midpoint_ma =
      sum(
        component_weight *
          midpoint_ma
      )
  ) |>
  ungroup()

resolved_summary <- component_means |>
  group_by(
    RUNO,
    resolution_method,
    confidence_tier
  ) |>
  summarise(
    n_age_components = n(),

    weighted_mean_midpoint_ma =
      first(
        weighted_mean_midpoint_ma
      ),

    weighted_sd_midpoint_ma =
      sqrt(
        sum(
          component_weight *
            (
              midpoint_ma -
                weighted_mean_midpoint_ma
            )^2
        )
      ),

    maximum_oldest_ma =
      max(oldest_ma),

    minimum_youngest_ma =
      min(youngest_ma),

    fraction_midpoint_gt_500 =
      sum(
        component_weight *
          as.numeric(
            midpoint_ma > 500
          )
      ),

    fraction_midpoint_gt_1000 =
      sum(
        component_weight *
          as.numeric(
            midpoint_ma > 1000
          )
      ),

    fraction_midpoint_gt_1500 =
      sum(
        component_weight *
          as.numeric(
            midpoint_ma > 1500
          )
      ),

    fraction_midpoint_gt_2000 =
      sum(
        component_weight *
          as.numeric(
            midpoint_ma > 2000
          )
      ),

    age_match_source = case_when(
      any(
        manual_typo_correction
      ) ~
        "manual_typo_correction",

      any(
        start_match_method ==
          "age_qualifier" |
        end_match_method ==
          "age_qualifier"
      ) ~
        "age_qualifier_fallback",

      TRUE ~
        "category_lookup"
    ),

    .groups = "drop"
  )

final_runo <- runo_status |>
  left_join(
    resolved_summary,
    by = c(
      "RUNO",
      "resolution_method",
      "confidence_tier"
    )
  ) |>
  arrange(RUNO)

if (
  sum(final_runo$resolved) !=
    n_distinct(components$RUNO)
) {
  stop(
    "Resolved RUNO count does not match ",
    "component RUNO count."
  )
}

cat("Joining final ages to polygons...\n")

rox_final <- rox |>
  mutate(
    RUNO = clean_numeric(RUNO),
    source_crs_epsg = 4322
  ) |>
  left_join(
    final_runo |>
      select(
        -n_polygon_rows,
        -groups
      ),
    by = "RUNO"
  )

cat("Transforming output geometry to WGS 84...\n")

rox_wgs84 <- suppressWarnings(
  st_transform(
    rox_final,
    4326
  )
)

gpkg_path <- file.path(
  output_dir,
  "roxworld_age_wgs84.gpkg"
)

if (file.exists(gpkg_path)) {
  file.remove(gpkg_path)
}

st_write(
  rox_wgs84,
  gpkg_path,
  layer = "roxworld_age",
  quiet = TRUE
)

cat("Calculating polygon-area coverage...\n")

area_geometry <- rox_wgs84

valid_geometry <- suppressWarnings(
  st_is_valid(area_geometry)
)

n_invalid <- sum(
  !valid_geometry,
  na.rm = TRUE
)

if (n_invalid > 0L) {
  cat(
    "Repairing",
    n_invalid,
    "invalid geometries for area QC...\n"
  )

  area_geometry <- suppressWarnings(
    st_make_valid(area_geometry)
  )
}

area_equal <- suppressWarnings(
  st_transform(
    area_geometry,
    6933
  )
)

polygon_qc <- st_drop_geometry(
  area_geometry
) |>
  mutate(
    polygon_area_km2 =
      as.numeric(
        st_area(area_equal)
      ) / 1e6
  )

coverage_by_method <- polygon_qc |>
  group_by(
    resolution_method,
    resolved,
    confidence_tier
  ) |>
  summarise(
    n_polygon_rows = n(),
    n_unique_runo = n_distinct(
      RUNO,
      na.rm = TRUE
    ),
    area_km2 = sum(
      polygon_area_km2,
      na.rm = TRUE
    ),
    .groups = "drop"
  ) |>
  mutate(
    area_fraction_all =
      area_km2 /
      sum(area_km2)
  ) |>
  arrange(
    desc(resolved),
    desc(area_km2)
  )

overall_qc <- tibble(
  metric = c(
    "source_polygon_rows",
    "source_unique_runo",
    "resolved_unique_runo",
    "unresolved_unique_runo",
    "resolved_polygon_rows",
    "unresolved_polygon_rows",
    "resolved_polygon_fraction",
    "resolved_area_fraction",
    "invalid_geometry_count_before_area_repair"
  ),
  value = c(
    nrow(rox_final),
    n_distinct(
      rox_final$RUNO,
      na.rm = TRUE
    ),
    sum(
      final_runo$resolved,
      na.rm = TRUE
    ),
    sum(
      !final_runo$resolved,
      na.rm = TRUE
    ),
    sum(
      polygon_qc$resolved,
      na.rm = TRUE
    ),
    sum(
      !polygon_qc$resolved,
      na.rm = TRUE
    ),
    mean(
      polygon_qc$resolved,
      na.rm = TRUE
    ),
    sum(
      polygon_qc$polygon_area_km2[
        polygon_qc$resolved
      ],
      na.rm = TRUE
    ) /
      sum(
        polygon_qc$polygon_area_km2,
        na.rm = TRUE
      ),
    n_invalid
  )
)

unresolved_runo <- final_runo |>
  filter(
    !resolved
  )

write_csv(
  components,
  file.path(
    output_dir,
    "nrcan_runo_age_components.csv"
  )
)

write_csv(
  final_runo,
  file.path(
    output_dir,
    "nrcan_runo_age_summary.csv"
  )
)

write_csv(
  unresolved_runo,
  file.path(
    output_dir,
    "nrcan_unresolved_runo.csv"
  )
)

write_csv(
  polygon_qc,
  file.path(
    output_dir,
    "roxworld_polygon_age_qc.csv"
  )
)

write_csv(
  coverage_by_method,
  file.path(
    output_dir,
    "area_coverage_by_method.csv"
  )
)

write_csv(
  overall_qc,
  file.path(
    output_dir,
    "final_age_crosswalk_qc.csv"
  )
)

saveRDS(
  components,
  file.path(
    output_dir,
    "nrcan_runo_age_components.rds"
  )
)

saveRDS(
  final_runo,
  file.path(
    output_dir,
    "nrcan_runo_age_summary.rds"
  )
)

cat("\n========================================\n")
cat("FINAL NRCan AGE CROSSWALK\n")
cat("========================================\n")

print(
  overall_qc,
  n = Inf
)

cat("\nResolution methods:\n")

print(
  final_runo |>
    count(
      resolution_method,
      confidence_tier,
      resolved,
      name = "n_runo"
    ) |>
    arrange(
      desc(resolved),
      desc(n_runo)
    ),
  n = Inf
)

cat("\nArea coverage by method:\n")

print(
  coverage_by_method,
  n = Inf
)

cat("\nUnresolved RUNO:\n")

print(
  unresolved_runo |>
    select(
      RUNO,
      n_polygon_rows,
      groups,
      resolution_method,
      n_entities,
      n_default_entities,
      n_complete_default
    ),
  n = Inf,
  width = Inf
)

cat("\nOutputs saved to:\n")
cat(output_dir, "\n")
