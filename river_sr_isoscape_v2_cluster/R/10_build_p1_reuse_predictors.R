source("R/functions/core.R")

check_packages(
  c(
    "dplyr",
    "readr",
    "tibble"
  )
)

library(dplyr)
library(readr)
library(tibble)

out_dir <- file.path(
  project_root(),
  "outputs/p1_reuse_build"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

current_path <- file.path(
  project_root(),
  "data/processed/model_table.rds"
)

legacy_path <- file.path(
  Sys.getenv("HOME"),
  paste0(
    "projects/sr_global/data_processed/global/",
    "global_model_sites_5km_with_geology_",
    "climate_terrain_soil_complete.rds"
  )
)

stop_missing(
  current_path,
  "Current model table is missing."
)

stop_missing(
  legacy_path,
  "Legacy complete predictor table is missing."
)

current <- readRDS(current_path)
legacy <- readRDS(legacy_path)

if (!is.data.frame(current)) {
  stop("Current model table is not a data frame.")
}

if (!is.data.frame(legacy)) {
  stop("Legacy predictor table is not a data frame.")
}

if (!"row_id" %in% names(current)) {
  stop("Current model table does not contain row_id.")
}

if (anyDuplicated(current$row_id)) {
  stop("Current model table contains duplicated row_id.")
}

# ------------------------------------------------------------
# 1. Detect coordinate fields for fallback matching
# ------------------------------------------------------------

detect_column <- function(
    data,
    candidates,
    label
) {
  hit <- candidates[
    candidates %in% names(data)
  ]

  if (length(hit) == 0L) {
    stop(
      "Could not detect ",
      label,
      ". Candidates: ",
      paste(
        candidates,
        collapse = ", "
      )
    )
  }

  hit[1]
}

current_lon <- detect_column(
  current,
  c(
    "longitude",
    "lon",
    "LONGITUDE",
    "LONG",
    "x"
  ),
  "current longitude"
)

current_lat <- detect_column(
  current,
  c(
    "latitude",
    "lat",
    "LATITUDE",
    "LAT",
    "y"
  ),
  "current latitude"
)

legacy_lon <- detect_column(
  legacy,
  c(
    "longitude",
    "lon",
    "LONGITUDE",
    "LONG",
    "x"
  ),
  "legacy longitude"
)

legacy_lat <- detect_column(
  legacy,
  c(
    "latitude",
    "lat",
    "LATITUDE",
    "LAT",
    "y"
  ),
  "legacy latitude"
)

# ------------------------------------------------------------
# 2. Define reusable source columns
# ------------------------------------------------------------

lithology_types <- c(
  "unconsolidated",
  "siliciclastic",
  "mixed_sedimentary",
  "carbonate",
  "metamorphic",
  "plutonic",
  "volcanic",
  "evaporite"
)

local_lithology_columns <- paste0(
  "local_geo_",
  lithology_types,
  "_frac"
)

up_lithology_columns <- paste0(
  "up_geo_",
  lithology_types,
  "_frac"
)

environment_suffixes <- c(
  "bio1_C",
  "bio4_C_sd",
  "bio12_mm",
  "bio15_cv",
  "ai_ratio",
  "et0_mm",
  "elevation_m",
  "soil_clay_pct_0_30cm",
  "soil_pH_0_30cm"
)

local_environment_columns <- paste0(
  "local_",
  environment_suffixes
)

up_environment_columns <- paste0(
  "up_",
  environment_suffixes
)

candidate_source_columns <- unique(
  c(
    local_lithology_columns,
    up_lithology_columns,
    local_environment_columns,
    up_environment_columns
  )
)

available_source_columns <- intersect(
  candidate_source_columns,
  names(legacy)
)

missing_source_columns <- setdiff(
  candidate_source_columns,
  names(legacy)
)

write_lines(
  missing_source_columns,
  file.path(
    out_dir,
    "expected_but_missing_legacy_columns.txt"
  )
)

if (length(available_source_columns) == 0L) {
  stop("No reusable source columns were found.")
}

# ------------------------------------------------------------
# 3. Join current sites to legacy table
# ------------------------------------------------------------

join_method <- NA_character_

if (
  "legacy_site_id" %in% names(current) &&
  "site_id" %in% names(legacy)
) {
  legacy_join <- legacy |>
    mutate(
      legacy_site_id =
        as.character(site_id)
    ) |>
    select(
      legacy_site_id,
      all_of(available_source_columns)
    )

  if (anyDuplicated(legacy_join$legacy_site_id)) {
    stop(
      "Legacy site_id is not unique; cannot join safely."
    )
  }

  joined <- current |>
    mutate(
      legacy_site_id =
        as.character(legacy_site_id)
    ) |>
    left_join(
      legacy_join,
      by = "legacy_site_id"
    )

  join_method <- "legacy_site_id"
} else {
  legacy_join <- legacy |>
    mutate(
      join_longitude =
        round(
          as.numeric(
            .data[[legacy_lon]]
          ),
          6
        ),

      join_latitude =
        round(
          as.numeric(
            .data[[legacy_lat]]
          ),
          6
        )
    ) |>
    select(
      join_longitude,
      join_latitude,
      all_of(available_source_columns)
    )

  duplicate_coordinates <- legacy_join |>
    count(
      join_longitude,
      join_latitude,
      name = "n"
    ) |>
    filter(n > 1L)

  if (nrow(duplicate_coordinates) > 0L) {
    stop(
      "Legacy coordinates are not unique at six decimals."
    )
  }

  joined <- current |>
    mutate(
      join_longitude =
        round(
          as.numeric(
            .data[[current_lon]]
          ),
          6
        ),

      join_latitude =
        round(
          as.numeric(
            .data[[current_lat]]
          ),
          6
        )
    ) |>
    left_join(
      legacy_join,
      by = c(
        "join_longitude",
        "join_latitude"
      )
    ) |>
    select(
      -join_longitude,
      -join_latitude
    )

  join_method <- "coordinates_6dp"
}

matched_marker <- available_source_columns[1]

matched_n <- sum(
  !is.na(
    joined[[matched_marker]]
  )
)

unmatched_n <- nrow(joined) - matched_n

join_audit <- tibble(
  join_method = join_method,
  current_n = nrow(current),
  legacy_n = nrow(legacy),
  matched_n = matched_n,
  unmatched_n = unmatched_n,
  match_fraction =
    matched_n / nrow(current)
)

write_csv(
  join_audit,
  file.path(
    out_dir,
    "join_audit.csv"
  )
)

if (matched_n < 4400L) {
  stop(
    "Too few sites matched the legacy table: ",
    matched_n
  )
}

# ------------------------------------------------------------
# 4. Create output identifiers
# ------------------------------------------------------------

identifier_columns <- intersect(
  c(
    "row_id",
    "site_id",
    "legacy_site_id",
    "longitude",
    "latitude"
  ),
  names(joined)
)

p1 <- joined |>
  select(
    all_of(identifier_columns)
  )

feature_manifest <- tibble(
  feature_name = character(),
  source_columns = character(),
  feature_group = character(),
  calculation = character()
)

add_feature <- function(
    data,
    feature_name,
    values,
    source_columns,
    feature_group,
    calculation
) {
  data[[feature_name]] <- values

  manifest_row <- tibble(
    feature_name = feature_name,
    source_columns = paste(
      source_columns,
      collapse = "; "
    ),
    feature_group = feature_group,
    calculation = calculation
  )

  list(
    data = data,
    manifest = manifest_row
  )
}

# ------------------------------------------------------------
# 5. Direct local predictors
# ------------------------------------------------------------

direct_local_columns <- intersect(
  c(
    local_lithology_columns,
    local_environment_columns
  ),
  names(joined)
)

for (source_name in direct_local_columns) {
  feature_name <- paste0(
    "p1r__",
    source_name
  )

  result <- add_feature(
    p1,
    feature_name,
    joined[[source_name]],
    source_name,
    "direct_local",
    "Directly reused local legacy predictor"
  )

  p1 <- result$data

  feature_manifest <- bind_rows(
    feature_manifest,
    result$manifest
  )
}

# Add upstream soil pH when present because it was not in P0.
if ("up_soil_pH_0_30cm" %in% names(joined)) {
  result <- add_feature(
    p1,
    "p1r__up_soil_pH_0_30cm",
    joined$up_soil_pH_0_30cm,
    "up_soil_pH_0_30cm",
    "direct_upstream",
    "Directly reused upstream soil pH"
  )

  p1 <- result$data

  feature_manifest <- bind_rows(
    feature_manifest,
    result$manifest
  )
}

# ------------------------------------------------------------
# 6. Local-upstream environmental contrasts
# ------------------------------------------------------------

for (suffix in environment_suffixes) {
  local_name <- paste0(
    "local_",
    suffix
  )

  up_name <- paste0(
    "up_",
    suffix
  )

  if (
    local_name %in% names(joined) &&
    up_name %in% names(joined)
  ) {
    feature_name <- paste0(
      "p1r__local_minus_up_",
      suffix
    )

    result <- add_feature(
      p1,
      feature_name,
      joined[[local_name]] -
        joined[[up_name]],
      c(
        local_name,
        up_name
      ),
      "local_upstream_contrast",
      "Local value minus upstream value"
    )

    p1 <- result$data

    feature_manifest <- bind_rows(
      feature_manifest,
      result$manifest
    )
  }
}

# ------------------------------------------------------------
# 7. Lithology contrasts
# ------------------------------------------------------------

for (lithology in lithology_types) {
  local_name <- paste0(
    "local_geo_",
    lithology,
    "_frac"
  )

  up_name <- paste0(
    "up_geo_",
    lithology,
    "_frac"
  )

  if (
    local_name %in% names(joined) &&
    up_name %in% names(joined)
  ) {
    feature_name <- paste0(
      "p1r__local_minus_up_geo_",
      lithology,
      "_frac"
    )

    result <- add_feature(
      p1,
      feature_name,
      joined[[local_name]] -
        joined[[up_name]],
      c(
        local_name,
        up_name
      ),
      "lithology_contrast",
      "Local lithology fraction minus upstream fraction"
    )

    p1 <- result$data

    feature_manifest <- bind_rows(
      feature_manifest,
      result$manifest
    )
  }
}

# ------------------------------------------------------------
# 8. Lithological diversity metrics
# ------------------------------------------------------------

row_normalized_entropy <- function(
    data,
    columns
) {
  matrix_values <- as.matrix(
    data[, columns, drop = FALSE]
  )

  storage.mode(matrix_values) <-
    "double"

  matrix_values[
    !is.finite(matrix_values)
  ] <- NA_real_

  matrix_values[
    matrix_values < 0
  ] <- NA_real_

  matrix_zero <- matrix_values

  matrix_zero[
    is.na(matrix_zero)
  ] <- 0

  row_totals <- rowSums(
    matrix_zero
  )

  proportions <- matrix_zero /
    ifelse(
      row_totals > 0,
      row_totals,
      NA_real_
    )

  entropy_terms <- ifelse(
    proportions > 0,
    proportions *
      log(proportions),
    0
  )

  entropy <- -rowSums(
    entropy_terms,
    na.rm = TRUE
  )

  entropy[
    !is.finite(row_totals) |
      row_totals <= 0
  ] <- NA_real_

  entropy /
    log(ncol(matrix_zero))
}

row_dominant_fraction <- function(
    data,
    columns
) {
  values <- as.matrix(
    data[, columns, drop = FALSE]
  )

  storage.mode(values) <- "double"

  apply(
    values,
    1,
    function(x) {
      if (all(is.na(x))) {
        NA_real_
      } else {
        max(
          x,
          na.rm = TRUE
        )
      }
    }
  )
}

row_source_richness <- function(
    data,
    columns,
    threshold = 0.05
) {
  values <- as.matrix(
    data[, columns, drop = FALSE]
  )

  storage.mode(values) <- "double"

  apply(
    values,
    1,
    function(x) {
      if (all(is.na(x))) {
        NA_real_
      } else {
        sum(
          x >= threshold,
          na.rm = TRUE
        )
      }
    }
  )
}

local_lith_available <- intersect(
  local_lithology_columns,
  names(joined)
)

up_lith_available <- intersect(
  up_lithology_columns,
  names(joined)
)

if (length(local_lith_available) >= 4L) {
  derived_local <- list(
    p1r__local_lithology_entropy =
      row_normalized_entropy(
        joined,
        local_lith_available
      ),

    p1r__local_dominant_lithology_fraction =
      row_dominant_fraction(
        joined,
        local_lith_available
      ),

    p1r__local_lithology_richness_005 =
      row_source_richness(
        joined,
        local_lith_available,
        threshold = 0.05
      )
  )

  for (feature_name in names(derived_local)) {
    result <- add_feature(
      p1,
      feature_name,
      derived_local[[feature_name]],
      local_lith_available,
      "local_lithology_diversity",
      feature_name
    )

    p1 <- result$data

    feature_manifest <- bind_rows(
      feature_manifest,
      result$manifest
    )
  }
}

if (length(up_lith_available) >= 4L) {
  derived_up <- list(
    p1r__up_lithology_entropy =
      row_normalized_entropy(
        joined,
        up_lith_available
      ),

    p1r__up_dominant_lithology_fraction =
      row_dominant_fraction(
        joined,
        up_lith_available
      ),

    p1r__up_lithology_richness_005 =
      row_source_richness(
        joined,
        up_lith_available,
        threshold = 0.05
      )
  )

  for (feature_name in names(derived_up)) {
    result <- add_feature(
      p1,
      feature_name,
      derived_up[[feature_name]],
      up_lith_available,
      "upstream_lithology_diversity",
      feature_name
    )

    p1 <- result$data

    feature_manifest <- bind_rows(
      feature_manifest,
      result$manifest
    )
  }
}

# ------------------------------------------------------------
# 9. Process proxies
# ------------------------------------------------------------

safe_sum <- function(
    data,
    columns
) {
  columns <- intersect(
    columns,
    names(data)
  )

  if (length(columns) == 0L) {
    return(
      rep(
        NA_real_,
        nrow(data)
      )
    )
  }

  values <- as.matrix(
    data[, columns, drop = FALSE]
  )

  storage.mode(values) <- "double"

  result <- rowSums(
    values,
    na.rm = TRUE
  )

  result[
    rowSums(
      !is.na(values)
    ) == 0L
  ] <- NA_real_

  result
}

proxy_specs <- list(
  local_radiogenic_fraction_proxy = c(
    "local_geo_metamorphic_frac",
    "local_geo_plutonic_frac"
  ),

  up_radiogenic_fraction_proxy = c(
    "up_geo_metamorphic_frac",
    "up_geo_plutonic_frac"
  ),

  local_carbonate_evaporite_proxy = c(
    "local_geo_carbonate_frac",
    "local_geo_evaporite_frac"
  ),

  up_carbonate_evaporite_proxy = c(
    "up_geo_carbonate_frac",
    "up_geo_evaporite_frac"
  ),

  local_silicate_fraction_proxy = c(
    "local_geo_siliciclastic_frac",
    "local_geo_metamorphic_frac",
    "local_geo_plutonic_frac",
    "local_geo_volcanic_frac"
  ),

  up_silicate_fraction_proxy = c(
    "up_geo_siliciclastic_frac",
    "up_geo_metamorphic_frac",
    "up_geo_plutonic_frac",
    "up_geo_volcanic_frac"
  )
)

for (proxy_name in names(proxy_specs)) {
  feature_name <- paste0(
    "p1r__",
    proxy_name
  )

  result <- add_feature(
    p1,
    feature_name,
    safe_sum(
      joined,
      proxy_specs[[proxy_name]]
    ),
    proxy_specs[[proxy_name]],
    "process_proxy",
    "Sum of relevant GLiM fractions"
  )

  p1 <- result$data

  feature_manifest <- bind_rows(
    feature_manifest,
    result$manifest
  )
}

proxy_contrasts <- list(
  radiogenic_fraction_proxy = c(
    "p1r__local_radiogenic_fraction_proxy",
    "p1r__up_radiogenic_fraction_proxy"
  ),

  carbonate_evaporite_proxy = c(
    "p1r__local_carbonate_evaporite_proxy",
    "p1r__up_carbonate_evaporite_proxy"
  ),

  silicate_fraction_proxy = c(
    "p1r__local_silicate_fraction_proxy",
    "p1r__up_silicate_fraction_proxy"
  )
)

for (contrast_name in names(proxy_contrasts)) {
  feature_pair <- proxy_contrasts[[contrast_name]]

  if (all(feature_pair %in% names(p1))) {
    feature_name <- paste0(
      "p1r__local_minus_up_",
      contrast_name
    )

    result <- add_feature(
      p1,
      feature_name,
      p1[[feature_pair[1]]] -
        p1[[feature_pair[2]]],
      feature_pair,
      "process_proxy_contrast",
      "Local process proxy minus upstream process proxy"
    )

    p1 <- result$data

    feature_manifest <- bind_rows(
      feature_manifest,
      result$manifest
    )
  }
}

# ------------------------------------------------------------
# 10. Simple process interactions available now
# ------------------------------------------------------------

if (
  all(
    c(
      "p1r__up_radiogenic_fraction_proxy",
      "p1r__local_minus_up_elevation_m"
    ) %in%
      names(p1)
  )
) {
  result <- add_feature(
    p1,
    "p1r__radiogenic_proxy_x_elevation_contrast",
    p1$p1r__up_radiogenic_fraction_proxy *
      abs(
        p1$p1r__local_minus_up_elevation_m
      ),
    c(
      "p1r__up_radiogenic_fraction_proxy",
      "p1r__local_minus_up_elevation_m"
    ),
    "process_interaction",
    paste0(
      "Upstream radiogenic proxy multiplied by ",
      "absolute local-upstream elevation contrast"
    )
  )

  p1 <- result$data

  feature_manifest <- bind_rows(
    feature_manifest,
    result$manifest
  )
}

if (
  all(
    c(
      "p1r__up_carbonate_evaporite_proxy",
      "p1r__local_ai_ratio"
    ) %in%
      names(p1)
  )
) {
  result <- add_feature(
    p1,
    "p1r__carbonate_evaporite_proxy_x_aridity",
    p1$p1r__up_carbonate_evaporite_proxy *
      p1$p1r__local_ai_ratio,
    c(
      "p1r__up_carbonate_evaporite_proxy",
      "p1r__local_ai_ratio"
    ),
    "process_interaction",
    paste0(
      "Upstream carbonate-evaporite proxy ",
      "multiplied by local aridity index"
    )
  )

  p1 <- result$data

  feature_manifest <- bind_rows(
    feature_manifest,
    result$manifest
  )
}

# ------------------------------------------------------------
# 11. Remove unusable predictors
# ------------------------------------------------------------

predictor_columns <- grep(
  "^p1r__",
  names(p1),
  value = TRUE
)

coverage_summary <- tibble(
  feature_name = predictor_columns,

  nonmissing_n = vapply(
    p1[predictor_columns],
    function(x) {
      sum(!is.na(x))
    },
    integer(1)
  ),

  unique_n = vapply(
    p1[predictor_columns],
    function(x) {
      dplyr::n_distinct(
        x,
        na.rm = TRUE
      )
    },
    integer(1)
  )
) |>
  mutate(
    n_rows = nrow(p1),
    nonmissing_fraction =
      nonmissing_n / n_rows
  )

remove_features <- coverage_summary |>
  filter(
    nonmissing_n == 0L |
      unique_n <= 1L
  ) |>
  pull(feature_name)

if (length(remove_features) > 0L) {
  p1 <- p1 |>
    select(
      -all_of(remove_features)
    )

  feature_manifest <- feature_manifest |>
    filter(
      !feature_name %in%
        remove_features
    )
}

predictor_columns <- grep(
  "^p1r__",
  names(p1),
  value = TRUE
)

coverage_summary <- coverage_summary |>
  mutate(
    retained =
      feature_name %in%
        predictor_columns
  )

write_csv(
  coverage_summary,
  file.path(
    out_dir,
    "p1_reuse_coverage_summary.csv"
  )
)

write_csv(
  feature_manifest,
  file.path(
    out_dir,
    "p1_reuse_feature_manifest.csv"
  )
)

write_lines(
  predictor_columns,
  file.path(
    project_root(),
    "manifests/p1_reuse_predictors.txt"
  )
)

# ------------------------------------------------------------
# 12. Create merged model table
# ------------------------------------------------------------

p1_predictors_only <- p1 |>
  select(
    row_id,
    all_of(predictor_columns)
  )

model_table_p1 <- current |>
  left_join(
    p1_predictors_only,
    by = "row_id"
  )

if (nrow(model_table_p1) != nrow(current)) {
  stop("Merged P1 model table changed row count.")
}

write_atomic_rds(
  p1,
  file.path(
    project_root(),
    "data/external/p1_reuse_predictors_at_sites.rds"
  )
)

write_csv(
  p1,
  file.path(
    project_root(),
    "data/external/p1_reuse_predictors_at_sites.csv"
  )
)

write_atomic_rds(
  model_table_p1,
  file.path(
    project_root(),
    "data/processed/model_table_p1_reuse.rds"
  )
)

build_summary <- tibble(
  current_rows = nrow(current),
  matched_legacy_rows = matched_n,
  unmatched_rows = unmatched_n,
  p0_predictor_n = length(
    grep(
      "^p0__",
      names(current)
    )
  ),
  p1_reuse_predictor_n =
    length(predictor_columns),
  merged_column_n =
    ncol(model_table_p1)
)

write_csv(
  build_summary,
  file.path(
    out_dir,
    "p1_reuse_build_summary.csv"
  )
)

cat("\nP1R build summary:\n")

print(
  build_summary,
  n = Inf,
  width = Inf
)

cat("\nJoin audit:\n")

print(
  join_audit,
  n = Inf,
  width = Inf
)

cat("\nP1R predictors:\n")

print(
  feature_manifest |>
    select(
      feature_name,
      feature_group,
      source_columns
    ),
  n = Inf,
  width = Inf
)

log_msg(
  "P1 reuse predictor build complete."
)
