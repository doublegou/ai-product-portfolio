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

audit_dir <- file.path(
  "outputs",
  "nrcan_of5529",
  "rudbf_audit"
)

output_dir <- file.path(
  "outputs",
  "nrcan_of5529",
  "age_crosswalk"
)

shp_path <- file.path(
  base_dir,
  "data",
  "ArcMap9_ArcReader9",
  "AllThemesMerged",
  "roxworld.shp"
)

tables_path <- file.path(
  audit_dir,
  "rudbf_tables.rds"
)

dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

if (!file.exists(shp_path)) {
  stop("Missing shapefile: ", shp_path)
}

if (!file.exists(tables_path)) {
  stop("Missing DBF tables RDS: ", tables_path)
}

clean_text <- function(x) {
  x <- as.character(x)

  x <- iconv(
    x,
    from = "latin1",
    to = "UTF-8",
    sub = ""
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

cat("Reading roxworld...\n")

rox <- st_read(
  shp_path,
  quiet = TRUE,
  stringsAsFactors = FALSE
)

rox_attributes <- st_drop_geometry(rox) |>
  transmute(
    polygon_row = row_number(),
    RUNO = clean_numeric(RUNO),
    GROUP = clean_text(GROUP)
  )

cat("Reading audited DBF tables...\n")

tables <- readRDS(tables_path)

required_tables <- c(
  "rudt",
  "ruagedt",
  "agetsmlt"
)

missing_tables <- setdiff(
  required_tables,
  names(tables)
)

if (length(missing_tables) > 0L) {
  stop(
    "Missing required tables: ",
    paste(
      missing_tables,
      collapse = ", "
    )
  )
}

rudt <- as_tibble(
  tables[["rudt"]]
) |>
  transmute(
    RUNO = clean_numeric(RUNO),
    ID2 = clean_numeric(ID2),
    RUNO_ID2 = clean_numeric(RUNO_ID2),
    RUCODE = clean_text(RUCODE),
    DEFLT = toupper(
      clean_text(DEFLT)
    ),
    OFFSHORE = toupper(
      clean_text(OFFSHORE)
    ),
    AREAOFPLY = clean_numeric(AREAOFPLY),
    PERCENPLY = clean_numeric(PERCENPLY)
  )

ruagedt <- as_tibble(
  tables[["ruagedt"]]
) |>
  transmute(
    RUNO = clean_numeric(RUNO),
    ID2 = clean_numeric(ID2),
    RUNO_ID2 = clean_numeric(RUNO_ID2),
    STARTAGE = clean_text(STARTAGE),
    STARTQU = clean_text(STARTQU),
    ENDAGE = clean_text(ENDAGE),
    ENDQU = clean_text(ENDQU),
    STARTCAT = clean_text(STARTCAT),
    ENDCAT = clean_text(ENDCAT)
  )

age_lookup <- as_tibble(
  tables[["agetsmlt"]]
) |>
  transmute(
    AGEDES = clean_text(AGEDES),
    AGEQU = clean_text(AGEQU),
    AGEDESCAT = clean_text(AGEDESCAT),
    STARTMA = clean_numeric(STARTMA),
    ENDMA = clean_numeric(ENDMA),
    SOURCE = clean_text(SOURCE)
  )

age_lookup_duplicates <- age_lookup |>
  count(
    AGEDESCAT,
    name = "n_lookup_rows"
  ) |>
  filter(
    !is.na(AGEDESCAT),
    AGEDESCAT != "",
    n_lookup_rows > 1L
  )

write_csv(
  age_lookup_duplicates,
  file.path(
    output_dir,
    "age_lookup_duplicate_keys.csv"
  )
)

if (nrow(age_lookup_duplicates) > 0L) {
  warning(
    "Duplicated AGEDESCAT keys detected. ",
    "See age_lookup_duplicate_keys.csv."
  )
}

age_lookup_unique <- age_lookup |>
  filter(
    !is.na(AGEDESCAT),
    AGEDESCAT != ""
  ) |>
  arrange(
    AGEDESCAT,
    STARTMA,
    ENDMA
  ) |>
  distinct(
    AGEDESCAT,
    .keep_all = TRUE
  )

start_lookup <- age_lookup_unique |>
  select(
    STARTCAT = AGEDESCAT,
    start_term_oldest_ma = STARTMA,
    start_term_youngest_ma = ENDMA,
    start_lookup_description = AGEDES,
    start_lookup_qualifier = AGEQU
  )

end_lookup <- age_lookup_unique |>
  select(
    ENDCAT = AGEDESCAT,
    end_term_oldest_ma = STARTMA,
    end_term_youngest_ma = ENDMA,
    end_lookup_description = AGEDES,
    end_lookup_qualifier = AGEQU
  )

cat("Joining rock-unit entities to age records...\n")

entity_age <- rudt |>
  full_join(
    ruagedt,
    by = c(
      "RUNO",
      "ID2",
      "RUNO_ID2"
    ),
    suffix = c(
      "_ru",
      "_age"
    )
  ) |>
  left_join(
    start_lookup,
    by = "STARTCAT"
  ) |>
  left_join(
    end_lookup,
    by = "ENDCAT"
  ) |>
  mutate(
    oldest_ma = start_term_oldest_ma,
    youngest_ma = end_term_youngest_ma,
    midpoint_ma = (
      oldest_ma + youngest_ma
    ) / 2,
    duration_ma = oldest_ma - youngest_ma,
    complete_age = (
      is.finite(oldest_ma) &
      is.finite(youngest_ma)
    ),
    valid_age_order = case_when(
      !complete_age ~ NA,
      oldest_ma >= youngest_ma ~ TRUE,
      TRUE ~ FALSE
    ),
    is_default = DEFLT == "Y"
  )

entity_key_duplicates <- entity_age |>
  count(
    RUNO,
    ID2,
    RUNO_ID2,
    name = "n_rows"
  ) |>
  filter(
    n_rows > 1L
  )

polygon_candidate_summary <- entity_age |>
  group_by(RUNO) |>
  summarise(
    n_entity_rows = n(),
    n_distinct_entities = n_distinct(
      RUNO_ID2,
      na.rm = TRUE
    ),
    n_default_entities = n_distinct(
      RUNO_ID2[
        is_default %in% TRUE
      ],
      na.rm = TRUE
    ),
    n_complete_age_rows = sum(
      complete_age,
      na.rm = TRUE
    ),
    n_complete_default_rows = sum(
      complete_age &
        is_default,
      na.rm = TRUE
    ),
    n_invalid_age_order = sum(
      valid_age_order %in% FALSE,
      na.rm = TRUE
    ),
    .groups = "drop"
  )

unambiguous_default_age <- entity_age |>
  filter(
    is_default,
    complete_age,
    valid_age_order
  ) |>
  group_by(RUNO) |>
  filter(
    n_distinct(
      RUNO_ID2
    ) == 1L,
    n() == 1L
  ) |>
  ungroup() |>
  select(
    RUNO,
    ID2,
    RUNO_ID2,
    RUCODE,
    OFFSHORE,
    STARTAGE,
    STARTQU,
    ENDAGE,
    ENDQU,
    STARTCAT,
    ENDCAT,
    oldest_ma,
    youngest_ma,
    midpoint_ma,
    duration_ma
  )

polygon_age_join <- rox_attributes |>
  left_join(
    unambiguous_default_age,
    by = "RUNO"
  ) |>
  mutate(
    has_unambiguous_default_age =
      is.finite(midpoint_ma)
  )

missing_runo_in_rudt <- rox_attributes |>
  anti_join(
    rudt |>
      distinct(RUNO),
    by = "RUNO"
  )

missing_runo_in_ruagedt <- rox_attributes |>
  anti_join(
    ruagedt |>
      distinct(RUNO),
    by = "RUNO"
  )

unmatched_start_categories <- ruagedt |>
  distinct(STARTCAT) |>
  filter(
    !is.na(STARTCAT),
    STARTCAT != ""
  ) |>
  anti_join(
    age_lookup_unique |>
      distinct(
        STARTCAT = AGEDESCAT
      ),
    by = "STARTCAT"
  )

unmatched_end_categories <- ruagedt |>
  distinct(ENDCAT) |>
  filter(
    !is.na(ENDCAT),
    ENDCAT != ""
  ) |>
  anti_join(
    age_lookup_unique |>
      distinct(
        ENDCAT = AGEDESCAT
      ),
    by = "ENDCAT"
  )

qc_summary <- tibble(
  metric = c(
    "roxworld_polygon_rows",
    "roxworld_unique_runo",
    "rudt_rows",
    "rudt_unique_runo",
    "ruagedt_rows",
    "ruagedt_unique_runo",
    "age_lookup_rows",
    "age_lookup_unique_categories",
    "entity_age_rows",
    "entity_key_duplicate_groups",
    "complete_entity_age_rows",
    "invalid_age_order_rows",
    "unambiguous_default_runo",
    "polygon_rows_with_unambiguous_age",
    "missing_runo_in_rudt",
    "missing_runo_in_ruagedt",
    "unmatched_start_categories",
    "unmatched_end_categories"
  ),
  value = c(
    nrow(rox_attributes),
    n_distinct(
      rox_attributes$RUNO,
      na.rm = TRUE
    ),
    nrow(rudt),
    n_distinct(
      rudt$RUNO,
      na.rm = TRUE
    ),
    nrow(ruagedt),
    n_distinct(
      ruagedt$RUNO,
      na.rm = TRUE
    ),
    nrow(age_lookup),
    n_distinct(
      age_lookup$AGEDESCAT,
      na.rm = TRUE
    ),
    nrow(entity_age),
    nrow(entity_key_duplicates),
    sum(
      entity_age$complete_age,
      na.rm = TRUE
    ),
    sum(
      entity_age$valid_age_order %in% FALSE,
      na.rm = TRUE
    ),
    n_distinct(
      unambiguous_default_age$RUNO,
      na.rm = TRUE
    ),
    sum(
      polygon_age_join$has_unambiguous_default_age,
      na.rm = TRUE
    ),
    nrow(missing_runo_in_rudt),
    nrow(missing_runo_in_ruagedt),
    nrow(unmatched_start_categories),
    nrow(unmatched_end_categories)
  )
)

write_csv(
  age_lookup,
  file.path(
    output_dir,
    "age_lookup_full.csv"
  )
)

write_csv(
  entity_age,
  file.path(
    output_dir,
    "rockunit_entity_age.csv"
  )
)

write_csv(
  entity_key_duplicates,
  file.path(
    output_dir,
    "entity_key_duplicates.csv"
  )
)

write_csv(
  polygon_candidate_summary,
  file.path(
    output_dir,
    "runo_age_candidate_summary.csv"
  )
)

write_csv(
  unambiguous_default_age,
  file.path(
    output_dir,
    "runo_unambiguous_default_age.csv"
  )
)

write_csv(
  polygon_age_join,
  file.path(
    output_dir,
    "roxworld_polygon_age_attributes.csv"
  )
)

write_csv(
  missing_runo_in_rudt,
  file.path(
    output_dir,
    "missing_runo_in_rudt.csv"
  )
)

write_csv(
  missing_runo_in_ruagedt,
  file.path(
    output_dir,
    "missing_runo_in_ruagedt.csv"
  )
)

write_csv(
  unmatched_start_categories,
  file.path(
    output_dir,
    "unmatched_start_categories.csv"
  )
)

write_csv(
  unmatched_end_categories,
  file.path(
    output_dir,
    "unmatched_end_categories.csv"
  )
)

write_csv(
  qc_summary,
  file.path(
    output_dir,
    "age_crosswalk_qc_summary.csv"
  )
)

saveRDS(
  entity_age,
  file.path(
    output_dir,
    "rockunit_entity_age.rds"
  )
)

saveRDS(
  polygon_age_join,
  file.path(
    output_dir,
    "roxworld_polygon_age_attributes.rds"
  )
)

cat("\n========================================\n")
cat("NRCan AGE CROSSWALK QC\n")
cat("========================================\n")

print(
  qc_summary,
  n = Inf
)

cat("\nCandidate-count distribution:\n")

print(
  polygon_candidate_summary |>
    count(
      n_default_entities,
      n_complete_default_rows,
      name = "n_runo"
    ) |>
    arrange(
      n_default_entities,
      n_complete_default_rows
    ),
  n = Inf
)

cat("\nExample unambiguous ages:\n")

print(
  unambiguous_default_age |>
    select(
      RUNO,
      RUCODE,
      STARTCAT,
      ENDCAT,
      oldest_ma,
      youngest_ma,
      midpoint_ma
    ) |>
    slice_head(n = 15),
  n = 15,
  width = Inf
)

cat("\nOutputs saved to:\n")
cat(output_dir, "\n")
