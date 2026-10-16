#!/usr/bin/env Rscript

options(
  stringsAsFactors = FALSE,
  warn = 1
)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
  library(sf)
})

output_dir <- "outputs/hydrobasins_asset_audit"

dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

core_inventory_path <- paste0(
  "outputs/verified_asset_inventory/",
  "upstream_framework_core.txt"
)

expected_name_pattern <- paste0(
  "^l6_",
  "(glim|climate_terrain|soil)",
  "_local_upstream_",
  "([a-z]{2})",
  "\\.rds$"
)

project_root <- normalizePath(
  ".",
  winslash = "/",
  mustWork = TRUE
)

cat("Project root:\n")
cat(project_root, "\n\n")


# ------------------------------------------------------------
# 1. Locate the 27 verified regional RDS assets
# ------------------------------------------------------------

legacy_root <- "/home/zhangmeng/projects/sr_global"

if (!dir.exists(legacy_root)) {
  stop(
    "Legacy project root does not exist: ",
    legacy_root
  )
}

asset_directories <- c(
  glim = file.path(
    legacy_root,
    "data_processed/global/glim_l6_by_region"
  ),
  climate_terrain = file.path(
    legacy_root,
    "data_processed/global/climate_terrain_l6_by_region"
  ),
  soil = file.path(
    legacy_root,
    "data_processed/global/soil_l6_by_region"
  )
)

missing_directories <- asset_directories[
  !dir.exists(asset_directories)
]

if (length(missing_directories) > 0L) {
  stop(
    "Missing verified asset directories: ",
    paste(
      missing_directories,
      collapse = "; "
    )
  )
}

expected_regions <- c(
  "af",
  "ar",
  "as",
  "au",
  "eu",
  "gr",
  "na",
  "sa",
  "si"
)

family_patterns <- c(
  glim =
    "^l6_glim_local_upstream_[a-z]{2}\\.rds$",
  climate_terrain =
    "^l6_climate_terrain_local_upstream_[a-z]{2}\\.rds$",
  soil =
    "^l6_soil_local_upstream_[a-z]{2}\\.rds$"
)

parse_asset_name <- function(path_value) {

  filename <- basename(path_value)

  matched <- regexec(
    expected_name_pattern,
    filename,
    perl = TRUE
  )

  pieces <- regmatches(
    filename,
    matched
  )[[1]]

  if (length(pieces) != 3L) {
    stop(
      "Unexpected HydroBASINS asset filename: ",
      filename
    )
  }

  tibble(
    family = pieces[[2]],
    region = pieces[[3]]
  )
}

asset_rows <- list()

for (family_name in names(asset_directories)) {

  family_directory <- asset_directories[[family_name]]

  family_pattern <- family_patterns[[family_name]]

  family_paths <- list.files(
    family_directory,
    pattern = family_pattern,
    full.names = TRUE,
    recursive = FALSE,
    ignore.case = FALSE
  )

  family_paths <- normalizePath(
    family_paths,
    winslash = "/",
    mustWork = TRUE
  )

  cat(
    "Located ",
    length(family_paths),
    " assets for family ",
    family_name,
    " in ",
    family_directory,
    "\n",
    sep = ""
  )

  if (length(family_paths) != 9L) {
    stop(
      "Expected 9 ",
      family_name,
      " assets; found ",
      length(family_paths),
      "."
    )
  }

  asset_rows[[length(asset_rows) + 1L]] <- bind_rows(
    lapply(
      family_paths,
      function(path_value) {

        parsed <- parse_asset_name(
          path_value
        )

        if (
          !identical(
            parsed$family[[1]],
            family_name
          )
        ) {
          stop(
            "Filename family mismatch for ",
            path_value,
            ": parsed ",
            parsed$family[[1]],
            ", expected ",
            family_name
          )
        }

        tibble(
          path = path_value,
          filename = basename(path_value),
          family = parsed$family[[1]],
          region = parsed$region[[1]],
          size_bytes =
            file.info(path_value)$size,
          modified_time = as.character(
            file.info(path_value)$mtime
          ),
          source_root = legacy_root,
          source_directory =
            family_directory,
          listed_in_verified_inventory =
            TRUE,
          found_in_project_scan =
            FALSE
        )
      }
    )
  )
}

manifest <- bind_rows(
  asset_rows
) %>%
  mutate(
    asset_key = paste(
      family,
      region,
      sep = "__"
    )
  ) %>%
  arrange(
    region,
    family,
    path
  )

if (nrow(manifest) == 0L) {
  stop(
    "No verified HydroBASINS assets were located."
  )
}

write_csv(
  manifest,
  file.path(
    output_dir,
    "hydrobasins_asset_manifest.csv"
  )
)

duplicate_assets <- manifest %>%
  count(
    asset_key,
    family,
    region,
    name = "n_candidates"
  ) %>%
  filter(n_candidates != 1L)

write_csv(
  duplicate_assets,
  file.path(
    output_dir,
    "duplicate_or_missing_asset_keys.csv"
  )
)

expected_grid <- tidyr::expand_grid(
  family = names(asset_directories),
  region = expected_regions
) %>%
  mutate(
    asset_key = paste(
      family,
      region,
      sep = "__"
    )
  )

asset_key_coverage <- expected_grid %>%
  left_join(
    manifest %>%
      count(
        asset_key,
        name = "n_matching_files"
      ),
    by = "asset_key"
  ) %>%
  mutate(
    n_matching_files = ifelse(
      is.na(n_matching_files),
      0L,
      n_matching_files
    )
  ) %>%
  arrange(
    region,
    family
  )

write_csv(
  asset_key_coverage,
  file.path(
    output_dir,
    "asset_key_coverage.csv"
  )
)

cat("\nAsset-key coverage:\n")
print(
  asset_key_coverage,
  n = Inf
)

observed_regions <- sort(
  unique(manifest$region)
)

if (
  nrow(manifest) != 27L ||
  n_distinct(manifest$asset_key) != 27L ||
  !identical(
    observed_regions,
    sort(expected_regions)
  ) ||
  any(
    asset_key_coverage$n_matching_files != 1L
  )
) {
  stop(
    paste0(
      "Expected exactly 27 unique assets ",
      "(9 regions x 3 families). Found ",
      nrow(manifest),
      " files and ",
      n_distinct(manifest$asset_key),
      " unique keys. Inspect ",
      "hydrobasins_asset_manifest.csv and ",
      "asset_key_coverage.csv."
    )
  )
}

cat(
  "\nVerified 27 assets across regions: ",
  paste(
    observed_regions,
    collapse = ", "
  ),
  "\n",
  sep = ""
)


# ------------------------------------------------------------
# 2. Object extraction helpers
# ------------------------------------------------------------

extract_tabular_object <- function(object) {

  if (
    inherits(object, "sf") ||
    inherits(object, "data.frame")
  ) {

    return(
      list(
        data = object,
        component = "<root>"
      )
    )
  }

  if (is.list(object)) {

    candidate_names <- names(object)

    if (is.null(candidate_names)) {
      candidate_names <- as.character(
        seq_along(object)
      )
    }

    candidate_index <- which(
      vapply(
        object,
        function(element) {
          inherits(element, "sf") ||
            inherits(element, "data.frame")
        },
        logical(1)
      )
    )

    if (length(candidate_index) == 1L) {

      selected_index <- candidate_index[[1]]

      return(
        list(
          data = object[[selected_index]],
          component =
            candidate_names[[selected_index]]
        )
      )
    }

    preferred_names <- c(
      "data",
      "table",
      "basins",
      "hydrobasins",
      "attributes"
    )

    preferred_index <- which(
      candidate_names %in% preferred_names &
        vapply(
          object,
          function(element) {
            inherits(element, "sf") ||
              inherits(element, "data.frame")
          },
          logical(1)
        )
    )

    if (length(preferred_index) == 1L) {

      selected_index <- preferred_index[[1]]

      return(
        list(
          data = object[[selected_index]],
          component =
            candidate_names[[selected_index]]
        )
      )
    }
  }

  stop(
    paste0(
      "Could not identify a unique tabular ",
      "data component in the RDS object."
    )
  )
}


normalise_key <- function(values) {

  result <- trimws(
    as.character(values)
  )

  result[
    result %in% c(
      "",
      "NA",
      "NaN",
      "NULL"
    )
  ] <- NA_character_

  result
}


class_string <- function(object) {

  paste(
    class(object),
    collapse = ";"
  )
}


same_with_na <- function(x, y) {

  (
    is.na(x) &
      is.na(y)
  ) |
    (
      !is.na(x) &
        !is.na(y) &
        x == y
    )
}


# ------------------------------------------------------------
# 3. Read and audit every table sequentially
# ------------------------------------------------------------

file_summaries <- list()
field_catalogues <- list()
key_samples <- list()
key_maps <- list()
audit_errors <- list()

for (row_index in seq_len(nrow(manifest))) {

  asset <- manifest[
    row_index,
  ]

  cat(
    "\nReading:",
    asset$filename,
    "\n"
  )

  audit_result <- tryCatch(
    {

      raw_object <- readRDS(
        asset$path
      )

      extracted <- extract_tabular_object(
        raw_object
      )

      data_object <- extracted$data

      is_sf <- inherits(
        data_object,
        "sf"
      )

      attribute_table <- if (is_sf) {
        st_drop_geometry(data_object)
      } else {
        as.data.frame(data_object)
      }

      field_names <- names(
        attribute_table
      )

      has_hybas_id <- "HYBAS_ID" %in%
        field_names

      has_next_down <- "NEXT_DOWN" %in%
        field_names

      hybas_id <- if (has_hybas_id) {
        normalise_key(
          attribute_table$HYBAS_ID
        )
      } else {
        rep(
          NA_character_,
          nrow(attribute_table)
        )
      }

      next_down <- if (has_next_down) {
        normalise_key(
          attribute_table$NEXT_DOWN
        )
      } else {
        rep(
          NA_character_,
          nrow(attribute_table)
        )
      }

      nonmissing_hybas <- hybas_id[
        !is.na(hybas_id)
      ]

      valid_downstream <- (
        !is.na(next_down) &
          next_down != "0"
      )

      downstream_outside_table <- (
        valid_downstream &
          !next_down %in% nonmissing_hybas
      )

      area_fields <- grep(
        "area",
        field_names,
        value = TRUE,
        ignore.case = TRUE
      )

      local_fields <- grep(
        "local",
        field_names,
        value = TRUE,
        ignore.case = TRUE
      )

      upstream_fields <- grep(
        "upstream|^up_|_up_",
        field_names,
        value = TRUE,
        ignore.case = TRUE
      )

      geometry_types <- if (is_sf) {
        paste(
          sort(
            unique(
              as.character(
                st_geometry_type(
                  data_object
                )
              )
            )
          ),
          collapse = ";"
        )
      } else {
        NA_character_
      }

      crs_epsg <- if (is_sf) {
        st_crs(data_object)$epsg
      } else {
        NA_integer_
      }

      crs_name <- if (is_sf) {
        st_crs(data_object)$Name
      } else {
        NA_character_
      }

      invalid_geometry_count <- if (is_sf) {
        sum(
          !st_is_valid(data_object),
          na.rm = TRUE
        )
      } else {
        NA_integer_
      }

      empty_geometry_count <- if (is_sf) {
        sum(
          st_is_empty(data_object),
          na.rm = TRUE
        )
      } else {
        NA_integer_
      }

      file_summary <- tibble(
        asset_key = asset$asset_key,
        family = asset$family,
        region = asset$region,
        filename = asset$filename,
        path = asset$path,
        file_size_bytes = asset$size_bytes,
        root_object_class =
          class_string(raw_object),
        extracted_component =
          extracted$component,
        extracted_class =
          class_string(data_object),
        n_rows = nrow(attribute_table),
        n_fields = ncol(attribute_table),
        has_sf_geometry = is_sf,
        geometry_types = geometry_types,
        crs_epsg = crs_epsg,
        crs_name = crs_name,
        invalid_geometry_count =
          invalid_geometry_count,
        empty_geometry_count =
          empty_geometry_count,
        has_HYBAS_ID = has_hybas_id,
        has_NEXT_DOWN = has_next_down,
        missing_HYBAS_ID = sum(
          is.na(hybas_id)
        ),
        duplicated_HYBAS_ID = sum(
          duplicated(
            nonmissing_hybas
          )
        ),
        missing_NEXT_DOWN = sum(
          is.na(next_down)
        ),
        outlet_NEXT_DOWN_zero = sum(
          next_down == "0",
          na.rm = TRUE
        ),
        downstream_ID_outside_table = sum(
          downstream_outside_table,
          na.rm = TRUE
        ),
        area_fields = paste(
          area_fields,
          collapse = ";"
        ),
        local_fields = paste(
          local_fields,
          collapse = ";"
        ),
        upstream_fields = paste(
          upstream_fields,
          collapse = ";"
        )
      )

      field_catalogue <- bind_rows(
        lapply(
          field_names,
          function(field_name) {

            field_value <- attribute_table[[field_name]]

            tibble(
              asset_key = asset$asset_key,
              family = asset$family,
              region = asset$region,
              filename = asset$filename,
              field = field_name,
              class = class_string(
                field_value
              ),
              n_missing = sum(
                is.na(field_value)
              ),
              n_unique = dplyr::n_distinct(
                field_value,
                na.rm = TRUE
              ),
              is_area_candidate = grepl(
                "area",
                field_name,
                ignore.case = TRUE
              ),
              is_local_candidate = grepl(
                "local",
                field_name,
                ignore.case = TRUE
              ),
              is_upstream_candidate = grepl(
                "upstream|^up_|_up_",
                field_name,
                ignore.case = TRUE
              )
            )
          }
        )
      )

      sample_fields <- unique(
        c(
          "HYBAS_ID",
          "NEXT_DOWN",
          area_fields
        )
      )

      sample_fields <- intersect(
        sample_fields,
        field_names
      )

      key_sample <- if (
        length(sample_fields) > 0L
      ) {

        as_tibble(
          attribute_table[
            seq_len(
              min(
                5L,
                nrow(attribute_table)
              )
            ),
            sample_fields,
            drop = FALSE
          ]
        ) %>%
          mutate(
            asset_key = asset$asset_key,
            family = asset$family,
            region = asset$region,
            .before = 1
          )

      } else {

        tibble(
          asset_key = asset$asset_key,
          family = asset$family,
          region = asset$region
        )
      }

      key_map <- tibble(
        HYBAS_ID = hybas_id,
        NEXT_DOWN = next_down,
        row_position = seq_along(
          hybas_id
        )
      )

      list(
        summary = file_summary,
        fields = field_catalogue,
        sample = key_sample,
        key_map = key_map
      )
    },
    error = function(error_condition) {

      audit_errors[[length(audit_errors) + 1L]] <<- tibble(
        asset_key = asset$asset_key,
        family = asset$family,
        region = asset$region,
        path = asset$path,
        error_message = conditionMessage(
          error_condition
        )
      )

      NULL
    }
  )

  if (!is.null(audit_result)) {

    file_summaries[[length(file_summaries) + 1L]] <- audit_result$summary

    field_catalogues[[length(field_catalogues) + 1L]] <- audit_result$fields

    key_samples[[length(key_samples) + 1L]] <- audit_result$sample

    key_maps[[asset$asset_key]] <- list(
      audit_result$key_map
    )
  }

  rm(audit_result)

  invisible(
    gc()
  )
}


file_summary_table <- bind_rows(
  file_summaries
)

field_catalogue_table <- bind_rows(
  field_catalogues
)

key_sample_table <- bind_rows(
  key_samples
)

error_table <- bind_rows(
  audit_errors
)

write_csv(
  file_summary_table,
  file.path(
    output_dir,
    "hydrobasins_file_summary.csv"
  )
)

write_csv(
  field_catalogue_table,
  file.path(
    output_dir,
    "hydrobasins_field_catalogue.csv"
  )
)

write_csv(
  key_sample_table,
  file.path(
    output_dir,
    "hydrobasins_key_samples.csv"
  )
)

write_csv(
  error_table,
  file.path(
    output_dir,
    "hydrobasins_audit_errors.csv"
  )
)


if (nrow(error_table) > 0L) {

  stop(
    "One or more HydroBASINS assets could not be audited. ",
    "Inspect hydrobasins_audit_errors.csv."
  )
}


if (
  any(!file_summary_table$has_HYBAS_ID) ||
  any(!file_summary_table$has_NEXT_DOWN)
) {

  stop(
    "At least one table lacks HYBAS_ID or NEXT_DOWN."
  )
}


if (
  any(
    file_summary_table$
      missing_HYBAS_ID > 0
  ) ||
  any(
    file_summary_table$
      duplicated_HYBAS_ID > 0
  )
) {

  stop(
    paste0(
      "Missing or duplicated HYBAS_ID values ",
      "were detected. Inspect ",
      "hydrobasins_file_summary.csv."
    )
  )
}


# ------------------------------------------------------------
# 4. Compare keys across the three families within each region
# ------------------------------------------------------------

region_alignment_results <- list()

region_codes <- sort(
  unique(
    manifest$region
  )
)

family_priority <- c(
  "glim",
  "climate_terrain",
  "soil"
)

for (region_code in region_codes) {

  available_families <- family_priority[
    paste(
      family_priority,
      region_code,
      sep = "__"
    ) %in% names(key_maps)
  ]

  if (length(available_families) == 0L) {
    next
  }

  reference_family <- available_families[[1]]

  reference_key <- paste(
    reference_family,
    region_code,
    sep = "__"
  )

  reference_map <- key_maps[[reference_key]][[1]] %>%
    distinct(
      HYBAS_ID,
      .keep_all = TRUE
    )

  for (comparison_family in available_families) {

    comparison_key <- paste(
      comparison_family,
      region_code,
      sep = "__"
    )

    comparison_map <- key_maps[[comparison_key]][[1]] %>%
      distinct(
        HYBAS_ID,
        .keep_all = TRUE
      )

    reference_ids <- reference_map$HYBAS_ID
    comparison_ids <- comparison_map$HYBAS_ID

    joined_downstream <- full_join(
      reference_map %>%
        select(
          HYBAS_ID,
          reference_NEXT_DOWN =
            NEXT_DOWN
        ),
      comparison_map %>%
        select(
          HYBAS_ID,
          comparison_NEXT_DOWN =
            NEXT_DOWN
        ),
      by = "HYBAS_ID"
    )

    in_both <- (
      joined_downstream$HYBAS_ID %in%
        reference_ids &
        joined_downstream$HYBAS_ID %in%
        comparison_ids
    )

    downstream_disagreement <- sum(
      in_both &
        !same_with_na(
          joined_downstream$
            reference_NEXT_DOWN,
          joined_downstream$
            comparison_NEXT_DOWN
        ),
      na.rm = TRUE
    )

    region_alignment_results[[length(region_alignment_results) + 1L]] <- tibble(
      region = region_code,
      reference_family =
        reference_family,
      comparison_family =
        comparison_family,
      reference_rows =
        nrow(reference_map),
      comparison_rows =
        nrow(comparison_map),
      HYBAS_ID_set_equal = setequal(
        reference_ids,
        comparison_ids
      ),
      HYBAS_ID_order_identical =
        identical(
          reference_ids,
          comparison_ids
        ),
      n_reference_only = length(
        setdiff(
          reference_ids,
          comparison_ids
        )
      ),
      n_comparison_only = length(
        setdiff(
          comparison_ids,
          reference_ids
        )
      ),
      n_NEXT_DOWN_disagreements =
        downstream_disagreement
    )
  }
}


regional_key_alignment <- bind_rows(
  region_alignment_results
)

write_csv(
  regional_key_alignment,
  file.path(
    output_dir,
    "regional_key_alignment.csv"
  )
)


# ------------------------------------------------------------
# 5. Identify likely canonical basin geometry/area tables
# ------------------------------------------------------------

canonical_candidates <- file_summary_table %>%
  mutate(
    complete_network_key =
      has_HYBAS_ID &
        has_NEXT_DOWN &
        missing_HYBAS_ID == 0 &
        duplicated_HYBAS_ID == 0,
    has_area_field =
      nzchar(area_fields),
    canonical_candidate =
      complete_network_key &
        has_sf_geometry &
        has_area_field
  ) %>%
  arrange(
    region,
    desc(canonical_candidate),
    family
  )

write_csv(
  canonical_candidates,
  file.path(
    output_dir,
    "canonical_basin_table_candidates.csv"
  )
)


area_field_catalogue <- field_catalogue_table %>%
  filter(is_area_candidate) %>%
  arrange(
    region,
    family,
    field
  )

write_csv(
  area_field_catalogue,
  file.path(
    output_dir,
    "area_field_catalogue.csv"
  )
)


local_upstream_field_catalogue <-
  field_catalogue_table %>%
  filter(
    is_local_candidate |
      is_upstream_candidate
  ) %>%
  arrange(
    region,
    family,
    field
  )

write_csv(
  local_upstream_field_catalogue,
  file.path(
    output_dir,
    "local_upstream_field_catalogue.csv"
  )
)


# ------------------------------------------------------------
# 6. Final QC
# ------------------------------------------------------------

overall_qc <- tibble(
  metric = c(
    "candidate_file_count",
    "unique_asset_key_count",
    "region_count",
    "family_count",
    "files_with_sf_geometry",
    "files_with_HYBAS_ID",
    "files_with_NEXT_DOWN",
    "files_with_missing_HYBAS_ID",
    "files_with_duplicated_HYBAS_ID",
    "files_with_external_NEXT_DOWN",
    "regional_family_comparisons",
    "HYBAS_ID_set_mismatches",
    "NEXT_DOWN_mapping_mismatches",
    "canonical_candidate_count"
  ),
  value = c(
    nrow(manifest),
    n_distinct(manifest$asset_key),
    n_distinct(manifest$region),
    n_distinct(manifest$family),
    sum(
      file_summary_table$
        has_sf_geometry
    ),
    sum(
      file_summary_table$
        has_HYBAS_ID
    ),
    sum(
      file_summary_table$
        has_NEXT_DOWN
    ),
    sum(
      file_summary_table$
        missing_HYBAS_ID > 0
    ),
    sum(
      file_summary_table$
        duplicated_HYBAS_ID > 0
    ),
    sum(
      file_summary_table$
        downstream_ID_outside_table > 0
    ),
    nrow(regional_key_alignment),
    sum(
      !regional_key_alignment$
        HYBAS_ID_set_equal
    ),
    sum(
      regional_key_alignment$
        n_NEXT_DOWN_disagreements > 0
    ),
    sum(
      canonical_candidates$
        canonical_candidate
    )
  )
)

write_csv(
  overall_qc,
  file.path(
    output_dir,
    "hydrobasins_asset_audit_qc.csv"
  )
)


cat("\n========================================\n")
cat("HYDROBASINS ASSET AUDIT COMPLETE\n")
cat("========================================\n")

cat("\nOverall QC:\n")
print(
  overall_qc,
  n = Inf
)

cat("\nFile summary:\n")
print(
  file_summary_table %>%
    select(
      region,
      family,
      n_rows,
      n_fields,
      has_sf_geometry,
      crs_epsg,
      missing_HYBAS_ID,
      duplicated_HYBAS_ID,
      downstream_ID_outside_table,
      area_fields
    ),
  n = Inf,
  width = Inf
)

cat("\nRegional key alignment:\n")
print(
  regional_key_alignment,
  n = Inf,
  width = Inf
)

cat("\nCanonical basin-table candidates:\n")
print(
  canonical_candidates %>%
    select(
      region,
      family,
      filename,
      n_rows,
      has_sf_geometry,
      crs_epsg,
      area_fields,
      canonical_candidate
    ),
  n = Inf,
  width = Inf
)

cat("\nOutputs saved to:\n")
cat(output_dir, "\n")
