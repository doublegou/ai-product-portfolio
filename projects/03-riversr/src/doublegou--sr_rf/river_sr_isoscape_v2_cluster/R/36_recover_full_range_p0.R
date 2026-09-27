options(stringsAsFactors = FALSE, scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

root <- normalizePath(
  "~/river_sr_isoscape_v2_cluster",
  mustWork = TRUE
)

setwd(root)

legacy_root <- file.path(
  Sys.getenv("HOME"),
  "projects/sr_global"
)

out_dir <- file.path(
  root,
  "outputs/full_range_p0_recovery"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

regions <- c(
  "af", "ar", "as", "au", "eu",
  "gr", "na", "sa", "si"
)

# ============================================================
# 1. LOAD CURRENT / FULL-RANGE / LEGACY DATA
# ============================================================

model <- readRDS(
  "data/processed/model_table_age_test.rds"
)

pred_current <- readRDS(
  "data/external/predictors_at_sites.rds"
)

full_sites <- readRDS(
  "outputs/full_range_rescue/full_range_5km_site_base.rds"
)

legacy_glim_sites <- readRDS(
  file.path(
    legacy_root,
    paste0(
      "data_processed/global/",
      "global_model_sites_5km_with_l6_glim.rds"
    )
  )
)

drop_sf <- function(x) {
  if (inherits(x, "sf")) {
    x <- sf::st_drop_geometry(x)
  }
  as.data.frame(x)
}

model <- drop_sf(model)
pred_current <- drop_sf(pred_current)
full_sites <- drop_sf(full_sites)
legacy_glim_sites <- drop_sf(legacy_glim_sites)

model$row_id <- as.character(model$row_id)
pred_current$row_id <- as.character(pred_current$row_id)

# ============================================================
# 2. SITE IDS IN CURRENT MODEL TABLE
# ============================================================

model_sites <- model |>
  mutate(
    site_id = paste0(
      sprintf("%.5f", longitude),
      "_",
      sprintf("%.5f", latitude)
    ),
    hybas_key = ifelse(
      is.finite(
        suppressWarnings(
          as.numeric(HYBAS_ID)
        )
      ),
      sprintf(
        "%.0f",
        as.numeric(HYBAS_ID)
      ),
      NA_character_
    )
  ) |>
  select(
    row_id,
    site_id,
    longitude,
    latitude,
    HYBAS_ID,
    hybas_key,
    basin_region
  )

if (anyDuplicated(model_sites$site_id)) {
  stop(
    "Current model table contains duplicated site_id."
  )
}

if (anyDuplicated(full_sites$site_id)) {
  stop(
    "Full-range site table contains duplicated site_id."
  )
}

# ============================================================
# 3. VALIDATE CURRENT HYBAS AGAINST LEGACY HYBAS
# ============================================================

legacy_hybas <- legacy_glim_sites |>
  mutate(
    site_id = as.character(site_id),
    legacy_hybas_key = ifelse(
      is.finite(
        suppressWarnings(
          as.numeric(HYBAS_ID)
        )
      ),
      sprintf(
        "%.0f",
        as.numeric(HYBAS_ID)
      ),
      NA_character_
    )
  ) |>
  select(
    site_id,
    legacy_HYBAS_ID = HYBAS_ID,
    legacy_hybas_key
  )

hybas_validation <- legacy_hybas |>
  left_join(
    model_sites |>
      select(
        site_id,
        current_HYBAS_ID = HYBAS_ID,
        current_hybas_key = hybas_key
      ),
    by = "site_id"
  ) |>
  mutate(
    same_hybas =
      legacy_hybas_key ==
      current_hybas_key
  )

write_csv(
  hybas_validation,
  file.path(
    out_dir,
    "hybas_validation_legacy_vs_current.csv"
  )
)

cat(
  "\n===== HYBAS VALIDATION =====\n"
)

cat(
  "Legacy sites: ",
  nrow(hybas_validation),
  "\n",
  sep = ""
)

cat(
  "Matched current site IDs: ",
  sum(
    !is.na(
      hybas_validation$current_hybas_key
    )
  ),
  "\n",
  sep = ""
)

cat(
  "Same HYBAS_ID: ",
  sum(
    hybas_validation$same_hybas,
    na.rm = TRUE
  ),
  "\n",
  sep = ""
)

cat(
  "Different HYBAS_ID: ",
  sum(
    !hybas_validation$same_hybas,
    na.rm = TRUE
  ),
  "\n",
  sep = ""
)

# ============================================================
# 4. ATTACH CURRENT HYBAS TO ALL 4485 FULL-RANGE SITES
# ============================================================

sites <- full_sites |>
  mutate(
    site_id = as.character(site_id),
    region = as.character(region)
  ) |>
  left_join(
    model_sites |>
      select(
        row_id,
        site_id,
        current_HYBAS_ID = HYBAS_ID,
        hybas_key
      ),
    by = "site_id"
  )

if (sum(is.na(sites$row_id)) > 0L) {
  stop(
    "Some full-range sites could not be mapped to current row_id."
  )
}

if (sum(is.na(sites$hybas_key)) > 0L) {
  stop(
    "Some full-range sites lack current HYBAS_ID."
  )
}

cat(
  "\nFull-range sites mapped to current rows: ",
  nrow(sites),
  "\n",
  sep = ""
)

# ============================================================
# 5. LOAD REGIONAL L6 ASSETS
# ============================================================

load_regional_assets <- function(
    directory,
    prefix,
    regions
) {

  pieces <- lapply(
    regions,
    function(r) {

      path <- file.path(
        directory,
        paste0(
          prefix,
          r,
          ".rds"
        )
      )

      if (!file.exists(path)) {
        stop(
          "Missing regional asset: ",
          path
        )
      }

      x <- readRDS(path)
      x <- drop_sf(x)

      if (!"region" %in% names(x)) {
        x$region <- r
      }

      x$region <- as.character(
        x$region
      )

      if (!"HYBAS_ID" %in% names(x)) {
        stop(
          "Missing HYBAS_ID in: ",
          path
        )
      }

      x$hybas_key <- sprintf(
        "%.0f",
        as.numeric(
          x$HYBAS_ID
        )
      )

      x
    }
  )

  bind_rows(pieces)
}

glim <- load_regional_assets(
  file.path(
    legacy_root,
    "data_processed/global/glim_l6_by_region"
  ),
  "l6_glim_local_upstream_",
  regions
)

climate <- load_regional_assets(
  file.path(
    legacy_root,
    "data_processed/global/climate_terrain_l6_by_region"
  ),
  "l6_climate_terrain_local_upstream_",
  regions
)

soil <- load_regional_assets(
  file.path(
    legacy_root,
    "data_processed/global/soil_l6_by_region"
  ),
  "l6_soil_local_upstream_",
  regions
)

# ============================================================
# 6. REQUIRED VARIABLES
# ============================================================

geo_vars <- c(
  "up_geo_unconsolidated_frac",
  "up_geo_siliciclastic_frac",
  "up_geo_mixed_sedimentary_frac",
  "up_geo_carbonate_frac",
  "up_geo_metamorphic_frac",
  "up_geo_plutonic_frac",
  "up_geo_volcanic_frac",
  "up_geo_evaporite_frac"
)

climate_vars <- c(
  "up_bio1_C",
  "up_bio4_C_sd",
  "up_bio12_mm",
  "up_bio15_cv",
  "up_ai_ratio",
  "up_et0_mm",
  "up_elevation_m"
)

soil_vars <- c(
  "up_soil_clay_pct_0_30cm"
)

check_required <- function(
    dat,
    vars,
    label
) {
  miss <- setdiff(
    vars,
    names(dat)
  )

  if (length(miss) > 0L) {
    stop(
      label,
      " missing variables: ",
      paste(
        miss,
        collapse = ", "
      )
    )
  }
}

check_required(
  glim,
  geo_vars,
  "GLiM"
)

check_required(
  climate,
  climate_vars,
  "Climate"
)

check_required(
  soil,
  soil_vars,
  "Soil"
)

# ============================================================
# 7. CHECK UNIQUE JOIN KEYS
# ============================================================

check_unique_key <- function(
    dat,
    label
) {

  dup <- dat |>
    count(
      region,
      hybas_key
    ) |>
    filter(
      n > 1
    )

  if (nrow(dup) > 0L) {
    stop(
      label,
      " has duplicated region + HYBAS_ID keys."
    )
  }
}

check_unique_key(
  glim,
  "GLiM"
)

check_unique_key(
  climate,
  "Climate"
)

check_unique_key(
  soil,
  "Soil"
)

# ============================================================
# 8. JOIN L6 ENVIRONMENT TO FULL-RANGE SITES
# ============================================================

glim_join <- glim |>
  select(
    region,
    hybas_key,
    all_of(
      geo_vars
    )
  )

climate_join <- climate |>
  select(
    region,
    hybas_key,
    all_of(
      climate_vars
    )
  )

soil_join <- soil |>
  select(
    region,
    hybas_key,
    all_of(
      soil_vars
    )
  )

sites_env <- sites |>
  left_join(
    glim_join,
    by = c(
      "region",
      "hybas_key"
    )
  ) |>
  left_join(
    climate_join,
    by = c(
      "region",
      "hybas_key"
    )
  ) |>
  left_join(
    soil_join,
    by = c(
      "region",
      "hybas_key"
    )
  )

if (nrow(sites_env) != 4485L) {
  stop(
    "Unexpected full-range row count after joins: ",
    nrow(sites_env)
  )
}

# ============================================================
# 9. RECONSTRUCT THE 25 NON-SPATIAL P0 VARIABLES
# ============================================================

recon <- sites_env |>
  transmute(
    row_id,

    p0__log_DIS_AV_CMS =
      log_DIS_AV_CMS,

    p0__log_UPLAND_SKM =
      log_UPLAND_SKM,

    p0__log_CATCH_SKM =
      log_CATCH_SKM,

    p0__log_LENGTH_KM =
      log_LENGTH_KM,

    p0__log_DIST_DN_KM =
      log_DIST_DN_KM,

    p0__log_DIST_UP_KM =
      log_DIST_UP_KM,

    p0__ORD_STRA =
      ORD_STRA,

    p0__ORD_CLAS =
      ORD_CLAS,

    p0__ORD_FLOW =
      ORD_FLOW,

    p0__up_geo_unconsolidated_frac =
      up_geo_unconsolidated_frac,

    p0__up_geo_siliciclastic_frac =
      up_geo_siliciclastic_frac,

    p0__up_geo_mixed_sedimentary_frac =
      up_geo_mixed_sedimentary_frac,

    p0__up_geo_carbonate_frac =
      up_geo_carbonate_frac,

    p0__up_geo_metamorphic_frac =
      up_geo_metamorphic_frac,

    p0__up_geo_plutonic_frac =
      up_geo_plutonic_frac,

    p0__up_geo_volcanic_frac =
      up_geo_volcanic_frac,

    p0__up_geo_evaporite_frac =
      up_geo_evaporite_frac,

    p0__up_bio1_C =
      up_bio1_C,

    p0__up_bio4_C_sd =
      up_bio4_C_sd,

    p0__up_bio12_mm =
      up_bio12_mm,

    p0__up_bio15_cv =
      up_bio15_cv,

    p0__up_ai_ratio =
      up_ai_ratio,

    p0__up_et0_mm =
      up_et0_mm,

    p0__up_elevation_m =
      up_elevation_m,

    p0__up_soil_clay_pct_0_30cm =
      up_soil_clay_pct_0_30cm
  )

nonspatial_p0 <- setdiff(
  grep(
    "^p0__",
    names(pred_current),
    value = TRUE
  ),
  c(
    "p0__sp_x",
    "p0__sp_y",
    "p0__sp_z"
  )
)

if (!setequal(
  nonspatial_p0,
  names(recon)[
    names(recon) != "row_id"
  ]
)) {
  stop(
    "Reconstructed P0 variable names do not match current non-spatial P0 set."
  )
}

# ============================================================
# 10. VALIDATE RECONSTRUCTION AGAINST EXISTING 4465
# ============================================================

validation <- pred_current |>
  select(
    row_id,
    all_of(
      nonspatial_p0
    )
  ) |>
  inner_join(
    recon,
    by = "row_id",
    suffix = c(
      "_old",
      "_recon"
    )
  )

validation_rows <- validation |>
  filter(
    if_all(
      ends_with("_old"),
      is.finite
    )
  )

variable_validation <- lapply(
  nonspatial_p0,
  function(v) {

    old_name <- paste0(
      v,
      "_old"
    )

    new_name <- paste0(
      v,
      "_recon"
    )

    old <- suppressWarnings(
      as.numeric(
        validation_rows[[old_name]]
      )
    )

    new <- suppressWarnings(
      as.numeric(
        validation_rows[[new_name]]
      )
    )

    valid <-
      is.finite(old) &
      is.finite(new)

    data.frame(
      variable = v,
      n_compared =
        sum(valid),

      n_missing_reconstructed =
        sum(
          is.finite(old) &
          !is.finite(new)
        ),

      max_abs_diff =
        if (
          sum(valid) > 0L
        ) {
          max(
            abs(
              old[valid] -
              new[valid]
            )
          )
        } else {
          NA_real_
        },

      mean_abs_diff =
        if (
          sum(valid) > 0L
        ) {
          mean(
            abs(
              old[valid] -
              new[valid]
            )
          )
        } else {
          NA_real_
        },

      stringsAsFactors = FALSE
    )
  }
) |>
  bind_rows()

write_csv(
  variable_validation,
  file.path(
    out_dir,
    "p0_reconstruction_validation.csv"
  )
)

cat(
  "\n===== P0 RECONSTRUCTION VALIDATION =====\n"
)

print(
  variable_validation,
  n = Inf
)

bad_validation <- variable_validation |>
  filter(
    n_missing_reconstructed > 0 |
      (
        is.finite(max_abs_diff) &
        max_abs_diff > 1e-8
      )
  )

if (nrow(bad_validation) > 0L) {

  cat(
    "\nWARNING: reconstructed P0 does not exactly reproduce legacy P0.\n"
  )

  print(
    bad_validation,
    n = Inf
  )

  stop(
    "Validation failed. Do not create full-range predictor asset."
  )
}

cat(
  "\nLegacy P0 reconstruction validated.\n"
)

# ============================================================
# 11. IDENTIFY THE 20 RESCUED ROWS
# ============================================================

current_p0 <- grep(
  "^p0__",
  names(pred_current),
  value = TRUE
)

current_finite <- vapply(
  pred_current[current_p0],
  function(x) {
    is.finite(
      suppressWarnings(
        as.numeric(
          as.character(x)
        )
      )
    )
  },
  logical(nrow(pred_current))
)

current_finite <- as.matrix(
  current_finite
)

pred_current$p0_nonmissing_n <-
  rowSums(
    current_finite
  )

rescued_ids <- pred_current |>
  filter(
    p0_nonmissing_n == 3L,
    row_id %in% recon$row_id
  ) |>
  pull(
    row_id
  )

cat(
  "\nRescued row IDs eligible for filling: ",
  length(rescued_ids),
  "\n",
  sep = ""
)

if (length(rescued_ids) != 20L) {
  stop(
    "Expected 20 rescued rows, found ",
    length(rescued_ids)
  )
}

# ============================================================
# 12. CREATE NEW FULL-RANGE PREDICTOR ASSET
# ============================================================

pred_full <- pred_current |>
  select(
    -p0_nonmissing_n
  )

recon_index <- match(
  pred_full$row_id,
  recon$row_id
)

fill_rows <- which(
  pred_full$row_id %in%
    rescued_ids
)

for (v in nonspatial_p0) {

  source_values <- recon[[v]][
    recon_index[
      fill_rows
    ]
  ]

  pred_full[
    fill_rows,
    v
  ] <- source_values
}

# ============================================================
# 13. FINAL COMPLETENESS CHECK
# ============================================================

final_finite <- vapply(
  pred_full[current_p0],
  function(x) {
    is.finite(
      suppressWarnings(
        as.numeric(
          as.character(x)
        )
      )
    )
  },
  logical(nrow(pred_full))
)

final_finite <- as.matrix(
  final_finite
)

final_nonmissing_n <-
  rowSums(
    final_finite
  )

summary_out <- data.frame(
  metric = c(
    "total_rows",
    "complete_28",
    "only_spatial_3",
    "rescued_rows",
    "remaining_incomplete"
  ),

  value = c(
    nrow(pred_full),

    sum(
      final_nonmissing_n == 28L
    ),

    sum(
      final_nonmissing_n == 3L
    ),

    length(
      rescued_ids
    ),

    sum(
      final_nonmissing_n < 28L
    )
  )
)

write_csv(
  summary_out,
  file.path(
    out_dir,
    "full_range_predictor_summary.csv"
  )
)

rescued_qc <- model_sites |>
  filter(
    row_id %in%
      rescued_ids
  ) |>
  left_join(
    sites_env |>
      select(
        row_id,
        region,
        current_HYBAS_ID,
        sr
      ),
    by = "row_id"
  ) |>
  arrange(
    desc(sr)
  )

write_csv(
  rescued_qc,
  file.path(
    out_dir,
    "rescued20_qc.csv"
  )
)

saveRDS(
  pred_full,
  "data/external/predictors_at_sites_full_range.rds"
)

write_csv(
  pred_full,
  file.path(
    out_dir,
    "predictors_at_sites_full_range.csv"
  )
)

cat(
  "\n===== FINAL FULL-RANGE P0 SUMMARY =====\n"
)

print(
  summary_out,
  row.names = FALSE
)

cat(
  "\nExpected result:\n",
  "total_rows = 4527\n",
  "complete_28 = 4485\n",
  "only_spatial_3 = 42\n",
  "rescued_rows = 20\n",
  sep = ""
)

cat(
  "\nSaved:\n",
  normalizePath(
    "data/external/predictors_at_sites_full_range.rds",
    mustWork = TRUE
  ),
  "\n",
  sep = ""
)

