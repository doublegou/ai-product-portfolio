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

out_dir <- "outputs/full_range_p0_recovery_safe"

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

regions <- c(
  "af", "ar", "as", "au", "eu",
  "gr", "na", "sa", "si"
)

drop_sf <- function(x) {
  if (inherits(x, "sf")) {
    x <- sf::st_drop_geometry(x)
  }
  as.data.frame(x)
}

# ============================================================
# 1. LOAD
# ============================================================

model <- drop_sf(
  readRDS(
    "data/processed/model_table_age_test.rds"
  )
)

pred_old <- drop_sf(
  readRDS(
    "data/external/predictors_at_sites.rds"
  )
)

full_sites <- drop_sf(
  readRDS(
    "outputs/full_range_rescue/full_range_5km_site_base.rds"
  )
)

legacy_final <- drop_sf(
  readRDS(
    file.path(
      legacy_root,
      paste0(
        "data_processed/global/",
        "global_model_sites_5km_with_geology_",
        "climate_terrain_soil_complete.rds"
      )
    )
  )
)

model$row_id <- as.character(model$row_id)
pred_old$row_id <- as.character(pred_old$row_id)

model <- model |>
  mutate(
    site_id = paste0(
      sprintf("%.5f", longitude),
      "_",
      sprintf("%.5f", latitude)
    )
  )

# ============================================================
# 2. IDENTIFY EXACTLY THE 20 NEW SITES
# ============================================================

old_site_ids <- as.character(
  legacy_final$site_id
)

rescued20 <- full_sites |>
  filter(
    !site_id %in% old_site_ids
  ) |>
  left_join(
    model |>
      select(
        row_id,
        site_id,
        current_HYBAS_ID = HYBAS_ID,
        current_basin_region = basin_region,
        basin_assignment_method,
        nearest_basin_distance_km,
        reference_id,
        sr87_sr86
      ),
    by = "site_id"
  ) |>
  mutate(
    hybas_key = sprintf(
      "%.0f",
      as.numeric(current_HYBAS_ID)
    )
  ) |>
  arrange(
    desc(sr)
  )

write_csv(
  rescued20,
  file.path(
    out_dir,
    "rescued20_assignment_audit.csv"
  )
)

cat(
  "\n===== RESCUED SITE COUNT =====\n"
)

cat(
  "n = ",
  nrow(rescued20),
  "\n",
  sep = ""
)

if (nrow(rescued20) != 20L) {
  stop(
    "Expected exactly 20 rescued sites."
  )
}

if (any(is.na(rescued20$row_id))) {
  stop(
    "Some rescued sites have no current row_id."
  )
}

if (any(is.na(rescued20$current_HYBAS_ID))) {
  stop(
    "Some rescued sites lack current HYBAS_ID."
  )
}

cat(
  "\n===== BASIN ASSIGNMENT METHODS =====\n"
)

print(
  rescued20 |>
    count(
      basin_assignment_method
    )
)

# We do NOT silently accept nearest-basin assignments
if (
  any(
    rescued20$basin_assignment_method != "within",
    na.rm = TRUE
  )
) {

  print(
    rescued20 |>
      filter(
        basin_assignment_method != "within"
      ) |>
      select(
        site_id,
        sr,
        current_HYBAS_ID,
        current_basin_region,
        basin_assignment_method,
        nearest_basin_distance_km
      )
  )

  stop(
    "At least one rescued site is not assigned by 'within'. ",
    "Inspect before continuing."
  )
}

# River region and basin region should agree
region_check <- rescued20 |>
  mutate(
    region_same =
      as.character(region) ==
      as.character(current_basin_region)
  )

if (
  any(
    !region_check$region_same,
    na.rm = TRUE
  )
) {

  print(
    region_check |>
      filter(
        !region_same
      ) |>
      select(
        site_id,
        sr,
        region,
        current_basin_region,
        current_HYBAS_ID
      )
  )

  stop(
    "River region and current basin region disagree."
  )
}

# ============================================================
# 3. LOAD EXISTING REGIONAL L6 ASSETS
# ============================================================

load_assets <- function(
    directory,
    prefix
) {

  result <- lapply(
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
          "Missing asset: ",
          path
        )
      }

      x <- drop_sf(
        readRDS(path)
      )

      if (!"region" %in% names(x)) {
        x$region <- r
      }

      x$region <- as.character(
        x$region
      )

      x$hybas_key <- sprintf(
        "%.0f",
        as.numeric(
          x$HYBAS_ID
        )
      )

      x
    }
  )

  bind_rows(result)
}

glim <- load_assets(
  file.path(
    legacy_root,
    "data_processed/global/glim_l6_by_region"
  ),
  "l6_glim_local_upstream_"
)

climate <- load_assets(
  file.path(
    legacy_root,
    "data_processed/global/climate_terrain_l6_by_region"
  ),
  "l6_climate_terrain_local_upstream_"
)

soil <- load_assets(
  file.path(
    legacy_root,
    "data_processed/global/soil_l6_by_region"
  ),
  "l6_soil_local_upstream_"
)

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

# ============================================================
# 4. UNIQUE KEYS
# ============================================================

check_unique <- function(x, label) {

  dup <- x |>
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

check_unique(
  glim,
  "GLiM"
)

check_unique(
  climate,
  "Climate"
)

check_unique(
  soil,
  "Soil"
)

# ============================================================
# 5. JOIN ONLY THE 20 RESCUED SITES
# ============================================================

rescued_env <- rescued20 |>
  left_join(
    glim |>
      select(
        region,
        hybas_key,
        all_of(geo_vars)
      ),
    by = c(
      "region",
      "hybas_key"
    )
  ) |>
  left_join(
    climate |>
      select(
        region,
        hybas_key,
        all_of(climate_vars)
      ),
    by = c(
      "region",
      "hybas_key"
    )
  ) |>
  left_join(
    soil |>
      select(
        region,
        hybas_key,
        all_of(soil_vars)
      ),
    by = c(
      "region",
      "hybas_key"
    )
  )

if (nrow(rescued_env) != 20L) {
  stop(
    "Join changed rescued-site row count."
  )
}

# ============================================================
# 6. RECONSTRUCT 25 NON-SPATIAL P0 VARIABLES
# ============================================================

recon20 <- rescued_env |>
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
    names(pred_old),
    value = TRUE
  ),
  c(
    "p0__sp_x",
    "p0__sp_y",
    "p0__sp_z"
  )
)

if (
  !setequal(
    nonspatial_p0,
    setdiff(
      names(recon20),
      "row_id"
    )
  )
) {
  stop(
    "Reconstructed predictor names do not match P0."
  )
}

# ============================================================
# 7. MAKE SURE ALL 20 x 25 VALUES ARE FINITE
# ============================================================

finite_matrix <- sapply(
  recon20[
    nonspatial_p0
  ],
  function(x) {
    is.finite(
      suppressWarnings(
        as.numeric(x)
      )
    )
  }
)

finite_matrix <- as.matrix(
  finite_matrix
)

recon20$p0_nonmissing_n <-
  rowSums(
    finite_matrix
  )

rescued_env_qc <- rescued_env |>
  select(
    row_id,
    site_id,
    sr,
    reference_id,
    region,
    current_HYBAS_ID,
    basin_assignment_method
  ) |>
  left_join(
    recon20 |>
      select(
        row_id,
        p0_nonmissing_n
      ),
    by = "row_id"
  ) |>
  arrange(
    desc(sr)
  )

write_csv(
  rescued_env_qc,
  file.path(
    out_dir,
    "rescued20_environment_qc.csv"
  )
)

cat(
  "\n===== RESCUED 20 ENVIRONMENT COMPLETENESS =====\n"
)

print(rescued_env_qc, row.names = FALSE)

if (
  any(
    recon20$p0_nonmissing_n != 25L
  )
) {

  stop(
    "At least one rescued site lacks one or more ",
    "non-spatial P0 predictors."
  )
}

# ============================================================
# 8. OPTIONAL BUT IMPORTANT:
# VALIDATE P0 COLUMN MAPPING AGAINST LEGACY FINAL TABLE
# ============================================================

legacy_model_map <- legacy_final |>
  mutate(
    site_id = as.character(site_id)
  ) |>
  left_join(
    model |>
      select(
        row_id,
        site_id
      ),
    by = "site_id"
  )

legacy_recon <- legacy_model_map |>
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

validation <- pred_old |>
  select(
    row_id,
    all_of(nonspatial_p0)
  ) |>
  inner_join(
    legacy_recon,
    by = "row_id",
    suffix = c(
      "_current",
      "_legacy"
    )
  )

validation_summary <- lapply(
  nonspatial_p0,
  function(v) {

    current_name <- paste0(
      v,
      "_current"
    )

    legacy_name <- paste0(
      v,
      "_legacy"
    )

    a <- as.numeric(
      validation[
        ,
        current_name
      ]
    )

    b <- as.numeric(
      validation[
        ,
        legacy_name
      ]
    )

    good <-
      is.finite(a) &
      is.finite(b)

    data.frame(
      variable = v,
      n_compared = sum(good),

      max_abs_diff =
        if (any(good)) {
          max(
            abs(
              a[good] -
              b[good]
            )
          )
        } else {
          NA_real_
        }
    )
  }
) |>
  bind_rows()

write_csv(
  validation_summary,
  file.path(
    out_dir,
    "legacy_p0_mapping_validation.csv"
  )
)

cat(
  "\n===== LEGACY P0 MAPPING VALIDATION =====\n"
)

print(validation_summary, row.names = FALSE)

if (
  any(
    validation_summary$max_abs_diff >
      1e-8,
    na.rm = TRUE
  )
) {
  stop(
    "P0 mapping does not reproduce legacy values."
  )
}

# ============================================================
# 9. FILL ONLY THE 20 OLD-MISSING ROWS
# ============================================================

pred_full <- pred_old

idx_target <- match(
  recon20$row_id,
  pred_full$row_id
)

if (any(is.na(idx_target))) {
  stop(
    "Some rescued row IDs not found in predictor asset."
  )
}

for (v in nonspatial_p0) {

  pred_full[
    idx_target,
    v
  ] <- recon20[
    ,
    v
  ]
}

# ============================================================
# 10. FINAL AUDIT
# ============================================================

all_p0 <- grep(
  "^p0__",
  names(pred_full),
  value = TRUE
)

final_matrix <- sapply(
  pred_full[
    all_p0
  ],
  function(x) {
    is.finite(
      suppressWarnings(
        as.numeric(x)
      )
    )
  }
)

final_matrix <- as.matrix(
  final_matrix
)

final_n <- rowSums(
  final_matrix
)

summary_out <- data.frame(
  metric = c(
    "total_rows",
    "complete_28",
    "only_spatial_3",
    "remaining_incomplete",
    "rescued20_complete"
  ),
  value = c(
    nrow(pred_full),
    sum(final_n == 28L),
    sum(final_n == 3L),
    sum(final_n < 28L),
    sum(
      final_n[idx_target] == 28L
    )
  )
)

write_csv(
  summary_out,
  file.path(
    out_dir,
    "final_summary.csv"
  )
)

saveRDS(
  pred_full,
  "data/external/predictors_at_sites_full_range.rds"
)

cat(
  "\n===== FINAL SUMMARY =====\n"
)

print(
  summary_out,
  row.names = FALSE
)

cat(
  "\nSaved: data/external/",
  "predictors_at_sites_full_range.rds\n",
  sep = ""
)

