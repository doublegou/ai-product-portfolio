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
  "age_gap_diagnosis"
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

if (!file.exists(shp_path)) {
  stop("Missing roxworld shapefile: ", shp_path)
}

if (!file.exists(tables_path)) {
  stop("Missing DBF table archive: ", tables_path)
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

polygon_counts <- rox_attributes |>
  group_by(RUNO) |>
  summarise(
    n_polygon_parts = n(),
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

cat("Reading DBF tables...\n")

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
    ENDCAT = clean_text(ENDCAT),
    start_age_norm = normalise_text(STARTAGE),
    start_qu_norm = normalise_text(STARTQU),
    end_age_norm = normalise_text(ENDAGE),
    end_qu_norm = normalise_text(ENDQU),
    start_cat_norm = normalise_text(STARTCAT),
    end_cat_norm = normalise_text(ENDCAT)
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
    age_norm = normalise_text(AGEDES),
    qual_norm = normalise_text(AGEQU),
    cat_norm = normalise_text(AGEDESCAT)
  )

cat_lookup_duplicates <- age_lookup |>
  count(
    cat_norm,
    name = "n_lookup_rows"
  ) |>
  filter(
    !is.na(cat_norm),
    n_lookup_rows > 1L
  )

pair_lookup_duplicates <- age_lookup |>
  count(
    age_norm,
    qual_norm,
    name = "n_lookup_rows"
  ) |>
  filter(
    !is.na(age_norm),
    n_lookup_rows > 1L
  )

write_csv(
  cat_lookup_duplicates,
  file.path(
    output_dir,
    "duplicate_category_lookup_keys.csv"
  )
)

write_csv(
  pair_lookup_duplicates,
  file.path(
    output_dir,
    "duplicate_age_qualifier_lookup_keys.csv"
  )
)

category_lookup <- age_lookup |>
  filter(
    !is.na(cat_norm)
  ) |>
  arrange(
    cat_norm,
    STARTMA,
    ENDMA
  ) |>
  distinct(
    cat_norm,
    .keep_all = TRUE
  )

pair_lookup <- age_lookup |>
  filter(
    !is.na(age_norm)
  ) |>
  arrange(
    age_norm,
    qual_norm,
    STARTMA,
    ENDMA
  ) |>
  distinct(
    age_norm,
    qual_norm,
    .keep_all = TRUE
  )

start_category_lookup <- category_lookup |>
  select(
    start_cat_norm = cat_norm,
    start_cat_oldest_ma = STARTMA,
    start_cat_youngest_ma = ENDMA
  )

end_category_lookup <- category_lookup |>
  select(
    end_cat_norm = cat_norm,
    end_cat_oldest_ma = STARTMA,
    end_cat_youngest_ma = ENDMA
  )

start_pair_lookup <- pair_lookup |>
  select(
    start_age_norm = age_norm,
    start_qu_norm = qual_norm,
    start_pair_oldest_ma = STARTMA,
    start_pair_youngest_ma = ENDMA,
    start_pair_category = AGEDESCAT
  )

end_pair_lookup <- pair_lookup |>
  select(
    end_age_norm = age_norm,
    end_qu_norm = qual_norm,
    end_pair_oldest_ma = STARTMA,
    end_pair_youngest_ma = ENDMA,
    end_pair_category = AGEDESCAT
  )

cat("Joining entity and age records...\n")

entity_age <- rudt |>
  left_join(
    ruagedt,
    by = c(
      "RUNO",
      "ID2",
      "RUNO_ID2"
    )
  ) |>
  left_join(
    start_category_lookup,
    by = "start_cat_norm"
  ) |>
  left_join(
    end_category_lookup,
    by = "end_cat_norm"
  ) |>
  left_join(
    start_pair_lookup,
    by = c(
      "start_age_norm",
      "start_qu_norm"
    )
  ) |>
  left_join(
    end_pair_lookup,
    by = c(
      "end_age_norm",
      "end_qu_norm"
    )
  ) |>
  mutate(
    is_default = DEFLT == "Y",

    has_age_record =
      !is.na(STARTAGE) |
      !is.na(ENDAGE) |
      !is.na(STARTCAT) |
      !is.na(ENDCAT),

    start_exact_match =
      is.finite(start_cat_oldest_ma),

    end_exact_match =
      is.finite(end_cat_youngest_ma),

    start_pair_match =
      is.finite(start_pair_oldest_ma),

    end_pair_match =
      is.finite(end_pair_youngest_ma),

    resolved_oldest_ma = coalesce(
      start_cat_oldest_ma,
      start_pair_oldest_ma
    ),

    resolved_youngest_ma = coalesce(
      end_cat_youngest_ma,
      end_pair_youngest_ma
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

    start_match_method = case_when(
      start_exact_match ~ "category",
      !start_exact_match &
        start_pair_match ~ "age_qualifier",
      TRUE ~ "unresolved"
    ),

    end_match_method = case_when(
      end_exact_match ~ "category",
      !end_exact_match &
        end_pair_match ~ "age_qualifier",
      TRUE ~ "unresolved"
    )
  )

default_entities <- entity_age |>
  filter(
    is_default
  )

runo_diagnosis <- polygon_counts |>
  left_join(
    rudt |>
      group_by(RUNO) |>
      summarise(
        n_entities = n(),
        n_default_entities = sum(
          DEFLT == "Y",
          na.rm = TRUE
        ),
        .groups = "drop"
      ),
    by = "RUNO"
  ) |>
  left_join(
    default_entities |>
      group_by(RUNO) |>
      summarise(
        n_default_age_records = sum(
          has_age_record,
          na.rm = TRUE
        ),
        n_complete_category_ages = sum(
          start_exact_match &
            end_exact_match &
            valid_age_order %in% TRUE,
          na.rm = TRUE
        ),
        n_complete_resolved_ages = sum(
          complete_resolved_age &
            valid_age_order %in% TRUE,
          na.rm = TRUE
        ),
        n_start_pair_recoveries = sum(
          start_match_method ==
            "age_qualifier",
          na.rm = TRUE
        ),
        n_end_pair_recoveries = sum(
          end_match_method ==
            "age_qualifier",
          na.rm = TRUE
        ),
        n_unresolved_start = sum(
          start_match_method ==
            "unresolved",
          na.rm = TRUE
        ),
        n_unresolved_end = sum(
          end_match_method ==
            "unresolved",
          na.rm = TRUE
        ),
        .groups = "drop"
      ),
    by = "RUNO"
  ) |>
  mutate(
    across(
      starts_with("n_"),
      ~ ifelse(
        is.na(.x),
        0,
        .x
      )
    ),
    resolution_class = case_when(
      n_entities == 0 ~
        "no_rudt_entity",

      n_default_entities == 0 ~
        "no_default_entity",

      n_complete_resolved_ages == 1 &
        n_default_entities == 1 ~
        "single_default_complete",

      n_complete_resolved_ages == 1 &
        n_default_entities > 1 ~
        "one_complete_among_multiple_defaults",

      n_complete_resolved_ages > 1 ~
        "multiple_complete_default_entities",

      n_default_age_records == 0 ~
        "default_without_age_record",

      n_unresolved_start > 0 &
        n_unresolved_end > 0 ~
        "unresolved_start_and_end",

      n_unresolved_start > 0 ~
        "unresolved_start",

      n_unresolved_end > 0 ~
        "unresolved_end",

      TRUE ~
        "other_incomplete"
    )
  )

resolution_summary <- runo_diagnosis |>
  group_by(resolution_class) |>
  summarise(
    n_runo = n(),
    n_polygon_rows = sum(
      n_polygon_parts,
      na.rm = TRUE
    ),
    .groups = "drop"
  ) |>
  arrange(
    desc(n_polygon_rows)
  )

unmatched_start_frequency <- default_entities |>
  filter(
    start_match_method == "unresolved"
  ) |>
  count(
    STARTAGE,
    STARTQU,
    STARTCAT,
    start_age_norm,
    start_qu_norm,
    start_cat_norm,
    sort = TRUE,
    name = "n_default_entities"
  )

unmatched_end_frequency <- default_entities |>
  filter(
    end_match_method == "unresolved"
  ) |>
  count(
    ENDAGE,
    ENDQU,
    ENDCAT,
    end_age_norm,
    end_qu_norm,
    end_cat_norm,
    sort = TRUE,
    name = "n_default_entities"
  )

fallback_recoveries <- default_entities |>
  filter(
    start_match_method ==
      "age_qualifier" |
    end_match_method ==
      "age_qualifier"
  ) |>
  select(
    RUNO,
    ID2,
    RUNO_ID2,
    RUCODE,
    STARTAGE,
    STARTQU,
    STARTCAT,
    start_match_method,
    start_pair_category,
    ENDAGE,
    ENDQU,
    ENDCAT,
    end_match_method,
    end_pair_category,
    resolved_oldest_ma,
    resolved_youngest_ma
  )

multiple_defaults <- default_entities |>
  add_count(
    RUNO,
    name = "n_default_entities"
  ) |>
  filter(
    n_default_entities > 1
  ) |>
  arrange(
    RUNO,
    ID2
  ) |>
  select(
    RUNO,
    ID2,
    RUNO_ID2,
    RUCODE,
    AREAOFPLY,
    PERCENPLY,
    STARTCAT,
    ENDCAT,
    resolved_oldest_ma,
    resolved_youngest_ma,
    complete_resolved_age,
    n_default_entities
  )

write_csv(
  runo_diagnosis,
  file.path(
    output_dir,
    "runo_gap_diagnosis.csv"
  )
)

write_csv(
  resolution_summary,
  file.path(
    output_dir,
    "resolution_summary.csv"
  )
)

write_csv(
  unmatched_start_frequency,
  file.path(
    output_dir,
    "unmatched_start_frequency.csv"
  )
)

write_csv(
  unmatched_end_frequency,
  file.path(
    output_dir,
    "unmatched_end_frequency.csv"
  )
)

write_csv(
  fallback_recoveries,
  file.path(
    output_dir,
    "age_qualifier_fallback_recoveries.csv"
  )
)

write_csv(
  multiple_defaults,
  file.path(
    output_dir,
    "multiple_default_entities.csv"
  )
)

write_csv(
  entity_age,
  file.path(
    output_dir,
    "entity_age_with_fallback.csv"
  )
)

saveRDS(
  entity_age,
  file.path(
    output_dir,
    "entity_age_with_fallback.rds"
  )
)

cat("\n========================================\n")
cat("AGE GAP DIAGNOSIS\n")
cat("========================================\n")

print(
  resolution_summary,
  n = Inf
)

cat("\nFallback recovery counts:\n")

print(
  tibble(
    metric = c(
      "start_age_qualifier_recoveries",
      "end_age_qualifier_recoveries",
      "complete_default_entities_after_fallback"
    ),
    value = c(
      sum(
        default_entities$start_match_method ==
          "age_qualifier",
        na.rm = TRUE
      ),
      sum(
        default_entities$end_match_method ==
          "age_qualifier",
        na.rm = TRUE
      ),
      sum(
        default_entities$complete_resolved_age &
          default_entities$valid_age_order %in% TRUE,
        na.rm = TRUE
      )
    )
  ),
  n = Inf
)

cat("\nTop unresolved start terms:\n")

print(
  unmatched_start_frequency |>
    slice_head(n = 25),
  n = 25,
  width = Inf
)

cat("\nTop unresolved end terms:\n")

print(
  unmatched_end_frequency |>
    slice_head(n = 25),
  n = 25,
  width = Inf
)

cat("\nMultiple-default entity rows:\n")
cat(nrow(multiple_defaults), "\n")

cat("\nOutputs saved to:\n")
cat(output_dir, "\n")
