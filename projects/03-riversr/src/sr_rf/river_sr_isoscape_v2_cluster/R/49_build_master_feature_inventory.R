source("R/functions/core.R")

check_packages(
  c(
    "dplyr",
    "tibble",
    "readr"
  )
)

cfg <- read_config()
ensure_dirs(cfg)

root <- normalizePath(
  project_root(),
  winslash = "/",
  mustWork = TRUE
)

out_dir <- file.path(
  root,
  "outputs",
  "r49_master_feature_inventory"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

row_id_col <- cfg$project$row_id
outcome_col <- cfg$project$outcome

anchor_file <- file.path(
  root,
  "data",
  "processed",
  "model_table_p0_full_range_r47_hybrid_local_lithology.rds"
)

module_file <- file.path(
  root,
  "outputs",
  "r47_hybrid_local_lithology",
  "r47_module_features.rds"
)

if (!file.exists(anchor_file)) {
  stop("Missing R49 anchor table: ", anchor_file)
}

# ==============================================================================
# Utilities
# ==============================================================================

relative_path <- function(path) {
  path_normalized <- normalizePath(
    path,
    winslash = "/",
    mustWork = FALSE
  )

  root_prefix <- paste0(root, "/")

  if (startsWith(path_normalized, root_prefix)) {
    substring(
      path_normalized,
      nchar(root_prefix) + 1L
    )
  } else {
    path_normalized
  }
}

safe_config_path <- function(x) {
  if (
    is.null(x) ||
    length(x) != 1L ||
    is.na(x) ||
    !is.character(x) ||
    !nzchar(x)
  ) {
    return(character())
  }

  file.path(root, x)
}

column_type <- function(x) {
  if (is.factor(x)) {
    return("factor")
  }

  if (is.logical(x)) {
    return("logical")
  }

  if (is.integer(x)) {
    return("integer")
  }

  if (is.numeric(x)) {
    return("numeric")
  }

  if (is.character(x)) {
    return("character")
  }

  if (inherits(x, "Date")) {
    return("Date")
  }

  if (inherits(x, "POSIXt")) {
    return("POSIXt")
  }

  if (is.list(x)) {
    return("list")
  }

  paste(class(x), collapse = "|")
}

is_reserved_column <- function(name) {
  name_lower <- tolower(name)

  exact_reserved <- tolower(
    c(
      row_id_col,
      outcome_col,
      cfg$project$latitude,
      cfg$project$longitude,
      "latitude",
      "longitude",
      "lat",
      "lon",
      "x",
      "y",
      "geometry",
      "geom",
      "fold",
      "outer_fold",
      "inner_fold",
      "block_id",
      "scheme",
      "block_size_km"
    )
  )

  reserved_pattern <- paste(
    c(
      "^doi$",
      "citation",
      "reference",
      "bibliograph",
      "journal",
      "author",
      "paper_title",
      "^title$",
      "^url$",
      "file_path",
      "source_file",
      "sample_id",
      "record_id",
      "site_name",
      "^country$",
      "^continent$"
    ),
    collapse = "|"
  )

  name_lower %in% exact_reserved ||
    grepl(
      reserved_pattern,
      name_lower
    )
}

suggest_mechanism_group <- function(name) {
  x <- tolower(name)

  if (grepl("^p0__", x)) {
    return("upstream_baseline")
  }

  if (grepl("local_minus_up_geo", x)) {
    return("local_upstream_contrast")
  }

  if (grepl("local_geo", x)) {
    return("local_lithology")
  }

  if (
    grepl("radiogenic.*proxy", x) ||
    grepl("siliciclastic.*proxy", x)
  ) {
    return("geology_compact_proxy")
  }

  if (
    grepl(
      "runoff|discharge|streamflow|flow_acc|hydro|drainage|river|catchment_area|basin_area|residence",
      x
    )
  ) {
    return("hydrology_transport")
  }

  if (
    grepl(
      "precip|rain|temperature|temp_|aridity|evapo|climate|moisture|snow|freeze|frost",
      x
    )
  ) {
    return("climate_weathering")
  }

  if (
    grepl(
      "elev|slope|relief|terrain|topo|rugged",
      x
    )
  ) {
    return("topography_erosion")
  }

  if (
    grepl(
      "lith|geol|bedrock|plutonic|volcanic|metamorphic|carbonate|evaporite|sedimentary|siliciclastic|crust|rock_age",
      x
    )
  ) {
    return("geology_source")
  }

  if (
    grepl(
      "soil|sediment|regolith|clay|organic_carbon|soc",
      x
    )
  ) {
    return("soil_surface_process")
  }

  if (
    grepl(
      "groundwater|spring|thermal|hydrothermal|geothermal|glacier|lake|reservoir",
      x
    )
  ) {
    return("special_source_mixing")
  }

  if (
    grepl(
      "qc|quality|uncertain|review|flag|measurement_count|reference_group",
      x
    )
  ) {
    return("observation_qc")
  }

  "unclassified"
}

suggest_spatial_scale <- function(name) {
  x <- tolower(name)

  if (grepl("^p0__", x)) {
    return("upstream_catchment")
  }

  if (grepl("local_minus_up", x)) {
    return("local_vs_upstream")
  }

  if (grepl("r47__local", x)) {
    return("local_hybas")
  }

  if (grepl("upstream|catchment|basin", x)) {
    return("upstream_catchment")
  }

  if (grepl("site|local", x)) {
    return("site_or_local")
  }

  "unknown"
}

suggest_derivation <- function(name) {
  x <- tolower(name)

  if (
    grepl(
      "contrast|minus|proxy|ratio|index|fraction|mean|median|sum|sd|variance|range|quantile|weighted",
      x
    )
  ) {
    return("derived_or_aggregated")
  }

  "unknown_or_direct"
}

vector_md5 <- function(x) {
  temp_file <- tempfile(
    pattern = "r49_vector_",
    fileext = ".rds"
  )

  on.exit(
    unlink(temp_file),
    add = TRUE
  )

  saveRDS(
    x,
    temp_file,
    version = 3
  )

  unname(
    tools::md5sum(temp_file)
  )
}

# ==============================================================================
# Frozen anchor sample
# ==============================================================================

anchor <- as.data.frame(
  readRDS(anchor_file)
)

if (nrow(anchor) != 4485L) {
  stop(
    "Expected 4485 anchor rows; found ",
    nrow(anchor),
    "."
  )
}

if (!row_id_col %in% names(anchor)) {
  stop("Anchor table lacks row ID column: ", row_id_col)
}

if (!outcome_col %in% names(anchor)) {
  stop("Anchor table lacks outcome column: ", outcome_col)
}

if (anyDuplicated(anchor[[row_id_col]])) {
  stop("Anchor table contains duplicate row IDs.")
}

anchor_ids <- as.character(
  anchor[[row_id_col]]
)

p0_features <- grep(
  "^p0__",
  names(anchor),
  value = TRUE
)

if (length(p0_features) != 28L) {
  stop(
    "Expected 28 frozen P0 predictors; found ",
    length(p0_features),
    "."
  )
}

# ==============================================================================
# Discover project feature assets
# ==============================================================================

configured_site_assets <- c(
  safe_config_path(cfg$predictors$sample_file),
  safe_config_path(cfg$weighting$area_table),
  safe_config_path(cfg$weighting$runoff_table),
  safe_config_path(cfg$weighting$sr_flux_table)
)

search_directories <- file.path(
  root,
  c(
    "data/processed",
    "data/external",
    "outputs"
  )
)

search_directories <- search_directories[
  dir.exists(search_directories)
]

all_rds_files <- unique(
  unlist(
    lapply(
      search_directories,
      function(directory) {
        list.files(
          directory,
          pattern = "\\.rds$",
          recursive = TRUE,
          full.names = TRUE,
          ignore.case = TRUE
        )
      }
    ),
    use.names = FALSE
  )
)

candidate_name_pattern <- paste(
  c(
    "model_table",
    "feature",
    "predictor",
    "candidate",
    "covariate",
    "at_sites",
    "site_",
    "area",
    "runoff",
    "srflux",
    "lithology",
    "climate",
    "weather",
    "topo",
    "soil",
    "hydrogeo"
  ),
  collapse = "|"
)

excluded_name_pattern <- paste(
  c(
    "oof_prediction",
    "inner_tuning",
    "baseline_reproduction",
    "model_runtime",
    "model_fit",
    "fitted_model",
    "importance",
    "partial",
    "hydrorivers_prediction",
    "prediction_table",
    "global_prediction",
    "raster",
    "grid"
  ),
  collapse = "|"
)

pattern_selected <- all_rds_files[
  grepl(
    candidate_name_pattern,
    basename(all_rds_files),
    ignore.case = TRUE
  ) &
    !grepl(
      excluded_name_pattern,
      basename(all_rds_files),
      ignore.case = TRUE
    )
]

candidate_files <- unique(
  c(
    anchor_file,
    module_file,
    configured_site_assets,
    pattern_selected
  )
)

candidate_files <- candidate_files[
  file.exists(candidate_files) &
    grepl(
      "\\.rds$",
      candidate_files,
      ignore.case = TRUE
    )
]

candidate_files <- normalizePath(
  candidate_files,
  winslash = "/",
  mustWork = TRUE
)

anchor_file_normalized <- normalizePath(
  anchor_file,
  winslash = "/",
  mustWork = TRUE
)

candidate_files <- c(
  anchor_file_normalized,
  setdiff(
    candidate_files,
    anchor_file_normalized
  )
)

all_rds_inventory <- tibble::tibble(
  source_file = vapply(
    all_rds_files,
    relative_path,
    character(1)
  ),
  file_size_mb = as.numeric(
    file.info(all_rds_files)$size
  ) / 1024^2,
  selected_for_schema_inspection =
    normalizePath(
      all_rds_files,
      winslash = "/",
      mustWork = TRUE
    ) %in% candidate_files
) |>
  dplyr::arrange(
    dplyr::desc(selected_for_schema_inspection),
    source_file
  )

write_csv_safe(
  all_rds_inventory,
  file.path(
    out_dir,
    "all_rds_files_inventory.csv"
  )
)

# ==============================================================================
# Inspect candidate objects
# ==============================================================================

max_file_mb <- suppressWarnings(
  as.numeric(
    Sys.getenv(
      "R49_MAX_FILE_MB",
      unset = "1500"
    )
  )
)

if (!is.finite(max_file_mb)) {
  max_file_mb <- 1500
}

asset_records <- list()
feature_records <- list()
module_records <- list()

for (current_file in candidate_files) {
  source_name <- relative_path(current_file)

  file_size_mb <- as.numeric(
    file.info(current_file)$size
  ) / 1024^2

  is_anchor <- identical(
    current_file,
    anchor_file_normalized
  )

  log_msg(
    "R49 inspecting: ",
    source_name,
    " [",
    round(file_size_mb, 2),
    " MB]"
  )

  if (file_size_mb > max_file_mb) {
    asset_records[[length(asset_records) + 1L]] <-
      tibble::tibble(
        source_file = source_name,
        file_size_mb = file_size_mb,
        is_anchor = is_anchor,
        inspection_status = "skipped_large_file",
        object_class = NA_character_,
        n_rows = NA_integer_,
        n_columns = NA_integer_,
        has_row_id = NA,
        duplicate_row_ids = NA_integer_,
        anchor_id_overlap = NA_integer_,
        alignment_status = "not_inspected",
        message = paste0(
          "File exceeds R49_MAX_FILE_MB=",
          max_file_mb
        )
      )

    next
  }

  object <- tryCatch(
    readRDS(current_file),
    error = function(e) e
  )

  if (inherits(object, "error")) {
    asset_records[[length(asset_records) + 1L]] <-
      tibble::tibble(
        source_file = source_name,
        file_size_mb = file_size_mb,
        is_anchor = is_anchor,
        inspection_status = "read_error",
        object_class = NA_character_,
        n_rows = NA_integer_,
        n_columns = NA_integer_,
        has_row_id = NA,
        duplicate_row_ids = NA_integer_,
        anchor_id_overlap = NA_integer_,
        alignment_status = "not_inspected",
        message = conditionMessage(object)
      )

    next
  }

  object_class <- paste(
    class(object),
    collapse = "|"
  )

  if (
    is.list(object) &&
    !is.data.frame(object) &&
    length(object) > 0L &&
    all(
      vapply(
        object,
        is.character,
        logical(1)
      )
    )
  ) {
    asset_records[[length(asset_records) + 1L]] <-
      tibble::tibble(
        source_file = source_name,
        file_size_mb = file_size_mb,
        is_anchor = is_anchor,
        inspection_status = "module_definition_list",
        object_class = object_class,
        n_rows = NA_integer_,
        n_columns = length(object),
        has_row_id = FALSE,
        duplicate_row_ids = NA_integer_,
        anchor_id_overlap = NA_integer_,
        alignment_status = "module_definition",
        message = NA_character_
      )

    for (module_name in names(object)) {
      module_features <- object[[module_name]]

      module_records[[length(module_records) + 1L]] <-
        tibble::tibble(
          source_file = source_name,
          module_name = module_name,
          n_features = length(module_features),
          features = paste(
            module_features,
            collapse = " | "
          ),
          all_features_present_in_anchor =
            all(module_features %in% names(anchor))
        )
    }

    next
  }

  if (!is.data.frame(object)) {
    asset_records[[length(asset_records) + 1L]] <-
      tibble::tibble(
        source_file = source_name,
        file_size_mb = file_size_mb,
        is_anchor = is_anchor,
        inspection_status = "unsupported_object",
        object_class = object_class,
        n_rows = length(object),
        n_columns = NA_integer_,
        has_row_id = FALSE,
        duplicate_row_ids = NA_integer_,
        anchor_id_overlap = NA_integer_,
        alignment_status = "unsupported",
        message = "Object is neither a data frame nor a character module list."
      )

    next
  }

  object <- as.data.frame(object)

  has_row_id <- row_id_col %in% names(object)

  duplicate_row_ids <- if (has_row_id) {
    sum(
      duplicated(
        as.character(
          object[[row_id_col]]
        )
      )
    )
  } else {
    NA_integer_
  }

  row_match <- NULL

  if (has_row_id && duplicate_row_ids == 0L) {
    object_ids <- as.character(
      object[[row_id_col]]
    )

    row_match <- match(
      anchor_ids,
      object_ids
    )

    anchor_overlap <- sum(
      !is.na(row_match)
    )

    alignment_status <- if (anchor_overlap == 4485L) {
      "full_anchor_row_id_coverage"
    } else if (anchor_overlap > 0L) {
      "partial_anchor_row_id_coverage"
    } else {
      "no_anchor_row_id_overlap"
    }
  } else if (has_row_id) {
    anchor_overlap <- length(
      intersect(
        anchor_ids,
        as.character(
          object[[row_id_col]]
        )
      )
    )

    alignment_status <- "duplicate_row_ids"
  } else {
    anchor_overlap <- NA_integer_

    alignment_status <- if (nrow(object) == 4485L) {
      "same_row_count_but_no_row_id"
    } else {
      "no_row_id"
    }
  }

  asset_records[[length(asset_records) + 1L]] <-
    tibble::tibble(
      source_file = source_name,
      file_size_mb = file_size_mb,
      is_anchor = is_anchor,
      inspection_status = "data_frame_inspected",
      object_class = object_class,
      n_rows = nrow(object),
      n_columns = ncol(object),
      has_row_id = has_row_id,
      duplicate_row_ids = duplicate_row_ids,
      anchor_id_overlap = anchor_overlap,
      alignment_status = alignment_status,
      message = NA_character_
    )

  for (feature_name in names(object)) {
    values <- object[[feature_name]]

    type <- column_type(values)

    if (type == "list") {
      next
    }

    reserved <- is_reserved_column(feature_name)

    nonmissing_values <- values[
      !is.na(values)
    ]

    n_unique_object <- length(
      unique(nonmissing_values)
    )

    low_cardinality_character <-
      is.character(values) &&
      n_unique_object <= 50L

    eligible_as_predictor <-
      !reserved &&
      (
        is.numeric(values) ||
        is.integer(values) ||
        is.logical(values) ||
        is.factor(values) ||
        low_cardinality_character
      )

    if (!is.null(row_match)) {
      aligned_values <- values[row_match]

      coverage_anchor_n <- sum(
        !is.na(row_match)
      )

      nonmissing_anchor_n <- sum(
        !is.na(aligned_values)
      )

      missing_fraction_anchor <- mean(
        is.na(aligned_values)
      )

      aligned_nonmissing <- aligned_values[
        !is.na(aligned_values)
      ]

      n_unique_anchor <- length(
        unique(aligned_nonmissing)
      )

      constant_on_anchor <-
        length(aligned_nonmissing) > 0L &&
        n_unique_anchor <= 1L

      if (
        is.numeric(aligned_values) &&
        length(aligned_nonmissing) > 0L
      ) {
        min_anchor <- min(
          aligned_nonmissing,
          na.rm = TRUE
        )

        max_anchor <- max(
          aligned_nonmissing,
          na.rm = TRUE
        )
      } else {
        min_anchor <- NA_real_
        max_anchor <- NA_real_
      }
    } else {
      coverage_anchor_n <- NA_integer_
      nonmissing_anchor_n <- NA_integer_
      missing_fraction_anchor <- NA_real_
      n_unique_anchor <- NA_integer_
      constant_on_anchor <- NA
      min_anchor <- NA_real_
      max_anchor <- NA_real_
    }

    quality_status <- dplyr::case_when(
      reserved ~ "reserved_non_predictor",
      isTRUE(constant_on_anchor) ~ "constant_on_anchor",
      !is.null(row_match) &&
        coverage_anchor_n == 4485L &&
        missing_fraction_anchor == 0 ~
        "model_ready_on_anchor",
      !is.null(row_match) &&
        coverage_anchor_n == 4485L &&
        missing_fraction_anchor > 0 ~
        "anchor_covered_with_missing_values",
      !is.null(row_match) &&
        coverage_anchor_n < 4485L ~
        "partial_anchor_coverage",
      alignment_status == "same_row_count_but_no_row_id" ~
        "requires_row_alignment_proof",
      TRUE ~ "requires_manual_review"
    )

    mechanism_group <- suggest_mechanism_group(
      feature_name
    )

    feature_records[[length(feature_records) + 1L]] <-
      tibble::tibble(
        source_file = source_name,
        is_anchor = is_anchor,
        feature = feature_name,
        column_type = type,
        reserved_non_predictor = reserved,
        eligible_as_predictor = eligible_as_predictor,
        suggested_mechanism_group = mechanism_group,
        suggested_spatial_scale =
          suggest_spatial_scale(feature_name),
        derivation_guess =
          suggest_derivation(feature_name),
        object_n_rows = nrow(object),
        anchor_coverage_n = coverage_anchor_n,
        anchor_nonmissing_n = nonmissing_anchor_n,
        anchor_missing_fraction = missing_fraction_anchor,
        anchor_n_unique = n_unique_anchor,
        constant_on_anchor = constant_on_anchor,
        anchor_min = min_anchor,
        anchor_max = max_anchor,
        quality_status = quality_status,
        manual_review_required =
          mechanism_group == "unclassified" ||
          quality_status != "model_ready_on_anchor"
      )
  }

  rm(object)
  invisible(gc())
}

asset_inventory <- dplyr::bind_rows(
  asset_records
)

feature_manifest_raw <- dplyr::bind_rows(
  feature_records
)

module_inventory <- dplyr::bind_rows(
  module_records
)

write_csv_safe(
  asset_inventory,
  file.path(
    out_dir,
    "asset_inventory.csv"
  )
)

write_csv_safe(
  feature_manifest_raw,
  file.path(
    out_dir,
    "feature_manifest_raw.csv"
  )
)

if (nrow(module_inventory) > 0L) {
  write_csv_safe(
    module_inventory,
    file.path(
      out_dir,
      "module_inventory.csv"
    )
  )
}

# ==============================================================================
# Duplicate names across assets
# ==============================================================================

feature_name_duplicates <- feature_manifest_raw |>
  dplyr::group_by(feature) |>
  dplyr::summarise(
    n_assets = dplyr::n_distinct(source_file),
    source_files = paste(
      sort(
        unique(source_file)
      ),
      collapse = " | "
    ),
    .groups = "drop"
  ) |>
  dplyr::filter(
    n_assets > 1L
  ) |>
  dplyr::arrange(
    dplyr::desc(n_assets),
    feature
  )

write_csv_safe(
  feature_name_duplicates,
  file.path(
    out_dir,
    "feature_name_duplicates_across_assets.csv"
  )
)

# ==============================================================================
# Exact duplicate columns in the anchor table
# ==============================================================================

anchor_candidate_features <- feature_manifest_raw |>
  dplyr::filter(
    is_anchor,
    eligible_as_predictor
  ) |>
  dplyr::pull(feature) |>
  unique()

anchor_hashes <- if (length(anchor_candidate_features) > 0L) {
  tibble::tibble(
    feature = anchor_candidate_features,
    value_hash = vapply(
      anchor_candidate_features,
      function(feature_name) {
        vector_md5(
          anchor[[feature_name]]
        )
      },
      character(1)
    )
  )
} else {
  tibble::tibble(
    feature = character(),
    value_hash = character()
  )
}

exact_duplicate_groups <- anchor_hashes |>
  dplyr::group_by(value_hash) |>
  dplyr::summarise(
    n_features = dplyr::n(),
    features = paste(
      sort(feature),
      collapse = " | "
    ),
    .groups = "drop"
  ) |>
  dplyr::filter(
    n_features > 1L
  ) |>
  dplyr::arrange(
    dplyr::desc(n_features)
  )

write_csv_safe(
  exact_duplicate_groups,
  file.path(
    out_dir,
    "exact_duplicate_anchor_features.csv"
  )
)

# ==============================================================================
# Known structural redundancy: upstream/local/contrast
# ==============================================================================

lithology_classes <- c(
  "unconsolidated",
  "siliciclastic",
  "mixed_sedimentary",
  "carbonate",
  "metamorphic",
  "plutonic",
  "volcanic",
  "evaporite"
)

structural_relationships <- dplyr::bind_rows(
  lapply(
    lithology_classes,
    function(class_name) {
      upstream_candidates <- grep(
        paste0(
          "^p0__.*",
          class_name
        ),
        names(anchor),
        value = TRUE,
        ignore.case = TRUE
      )

      local_feature <- paste0(
        "r47__local_geo_",
        class_name
      )

      contrast_feature <- paste0(
        "r47__local_minus_up_geo_",
        class_name
      )

      tibble::tibble(
        relationship_group =
          paste0(
            "lithology_",
            class_name
          ),
        upstream_candidates = paste(
          upstream_candidates,
          collapse = " | "
        ),
        local_feature = local_feature,
        contrast_feature = contrast_feature,
        upstream_present =
          length(upstream_candidates) > 0L,
        local_present =
          local_feature %in% names(anchor),
        contrast_present =
          contrast_feature %in% names(anchor),
        mathematical_relationship =
          "contrast = local - upstream",
        full_model_note =
          "Do not include upstream, local and contrast as three independent representations without an explicit redundancy rationale."
      )
    }
  )
)

write_csv_safe(
  structural_relationships,
  file.path(
    out_dir,
    "known_structural_relationships.csv"
  )
)

# ==============================================================================
# Build manual master-feature template
# ==============================================================================

master_feature_template <- feature_manifest_raw |>
  dplyr::filter(
    eligible_as_predictor
  ) |>
  dplyr::mutate(
    source_priority = dplyr::case_when(
      is_anchor ~ 1L,
      quality_status == "model_ready_on_anchor" ~ 2L,
      TRUE ~ 3L
    ),
    coverage_sort = dplyr::coalesce(
      anchor_coverage_n,
      -1L
    ),
    missing_sort = dplyr::coalesce(
      anchor_missing_fraction,
      1
    )
  ) |>
  dplyr::arrange(
    feature,
    source_priority,
    dplyr::desc(coverage_sort),
    missing_sort
  ) |>
  dplyr::group_by(feature) |>
  dplyr::slice(1L) |>
  dplyr::ungroup() |>
  dplyr::transmute(
    feature,
    preferred_source_file = source_file,
    column_type,
    suggested_mechanism_group,
    suggested_spatial_scale,
    derivation_guess,
    quality_status,
    anchor_coverage_n,
    anchor_nonmissing_n,
    anchor_missing_fraction,
    anchor_n_unique,
    constant_on_anchor,
    mechanism_group_final = "",
    scientific_rationale = "",
    parent_features = "",
    include_in_full_model = "",
    include_in_core_model = "",
    exclusion_reason_if_any = "",
    manual_notes = ""
  ) |>
  dplyr::arrange(
    suggested_mechanism_group,
    feature
  )

write_csv_safe(
  master_feature_template,
  file.path(
    out_dir,
    "master_feature_manifest_template.csv"
  )
)

mechanism_group_counts <- master_feature_template |>
  dplyr::count(
    suggested_mechanism_group,
    quality_status,
    name = "n_features"
  ) |>
  dplyr::arrange(
    suggested_mechanism_group,
    quality_status
  )

write_csv_safe(
  mechanism_group_counts,
  file.path(
    out_dir,
    "mechanism_group_counts.csv"
  )
)

# ==============================================================================
# Summary
# ==============================================================================

n_inspected_dataframes <- sum(
  asset_inventory$inspection_status ==
    "data_frame_inspected"
)

n_read_errors <- sum(
  asset_inventory$inspection_status ==
    "read_error"
)

n_skipped_large <- sum(
  asset_inventory$inspection_status ==
    "skipped_large_file"
)

n_model_ready <- sum(
  master_feature_template$quality_status ==
    "model_ready_on_anchor"
)

n_unclassified <- sum(
  master_feature_template$
    suggested_mechanism_group ==
    "unclassified"
)

summary_lines <- c(
  "R49 MASTER FEATURE INVENTORY",
  "============================",
  "",
  paste0(
    "Anchor file: ",
    relative_path(anchor_file)
  ),
  paste0(
    "Anchor rows: ",
    nrow(anchor)
  ),
  paste0(
    "Anchor columns: ",
    ncol(anchor)
  ),
  paste0(
    "Frozen P0 features: ",
    length(p0_features)
  ),
  "",
  paste0(
    "All RDS files discovered: ",
    nrow(all_rds_inventory)
  ),
  paste0(
    "Candidate files selected: ",
    length(candidate_files)
  ),
  paste0(
    "Data-frame assets inspected: ",
    n_inspected_dataframes
  ),
  paste0(
    "Read errors: ",
    n_read_errors
  ),
  paste0(
    "Large files skipped: ",
    n_skipped_large
  ),
  "",
  paste0(
    "Unique predictor candidates in master template: ",
    nrow(master_feature_template)
  ),
  paste0(
    "Model-ready on the 4485-row anchor: ",
    n_model_ready
  ),
  paste0(
    "Unclassified candidates requiring review: ",
    n_unclassified
  ),
  paste0(
    "Duplicate feature names across assets: ",
    nrow(feature_name_duplicates)
  ),
  paste0(
    "Exact duplicate value groups in anchor: ",
    nrow(exact_duplicate_groups)
  ),
  "",
  "IMPORTANT DESIGN RULE:",
  "No variable was included or excluded using model performance.",
  "The manifest records mechanism, coverage, derivation and redundancy only.",
  "",
  "NEXT STEP:",
  "Manually confirm mechanism_group_final, scientific_rationale,",
  "parent_features, include_in_full_model and include_in_core_model.",
  "",
  "STATUS: ALL R49 INVENTORY INVARIANTS PASSED",
  "",
  "R session:",
  paste(
    capture.output(
      sessionInfo()
    ),
    collapse = "\n"
  )
)

writeLines(
  summary_lines,
  file.path(
    out_dir,
    "run_summary.txt"
  )
)

output_files <- c(
  "all_rds_files_inventory.csv",
  "asset_inventory.csv",
  "feature_manifest_raw.csv",
  "feature_name_duplicates_across_assets.csv",
  "exact_duplicate_anchor_features.csv",
  "known_structural_relationships.csv",
  "master_feature_manifest_template.csv",
  "mechanism_group_counts.csv",
  "run_summary.txt"
)

if (file.exists(
  file.path(
    out_dir,
    "module_inventory.csv"
  )
)) {
  output_files <- c(
    output_files,
    "module_inventory.csv"
  )
}

checksum_paths <- file.path(
  out_dir,
  output_files
)

checksum_table <- tibble::tibble(
  file = output_files,
  md5 = unname(
    tools::md5sum(
      checksum_paths
    )
  )
)

write_csv_safe(
  checksum_table,
  file.path(
    out_dir,
    "output_checksums.csv"
  )
)

log_msg(
  "R49 master feature inventory completed."
)
