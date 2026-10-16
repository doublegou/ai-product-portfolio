suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(ggplot2)
  library(sf)
  library(scales)
})

report_date <- format(Sys.Date(), "%Y-%m-%d")

out_dir <- file.path(
  "outputs/global",
  paste0("mentor_report_", report_date)
)

fig_dir <- file.path(out_dir, "figures")
tab_dir <- file.path(out_dir, "tables")
meta_dir <- file.path(out_dir, "metadata")

dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(meta_dir, recursive = TRUE, showWarnings = FALSE)

theme_report <- theme_bw(base_size = 11) +
  theme(
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(linewidth = 0.2),
    plot.title = element_text(face = "bold"),
    axis.title = element_text(face = "bold"),
    legend.title = element_text(face = "bold")
  )

safe_read_csv <- function(path) {
  if (!file.exists(path)) {
    stop("Missing file: ", path)
  }
  read_csv(path, show_col_types = FALSE)
}

safe_copy <- function(from, to_dir) {
  if (length(from) == 0) return(invisible(NULL))
  file.copy(from, to_dir, overwrite = TRUE)
}

cat("\n========================================\n")
cat("MENTOR REPORT MATERIALS\n")
cat("Output directory:\n")
cat(out_dir, "\n")
cat("========================================\n")

# ============================================================
# 0. Inventory current materials
# ============================================================

inventory_file <- file.path(meta_dir, "current_materials_inventory.txt")

system(
  paste(
    "find outputs/global -maxdepth 3 -type f",
    "\\( -name '*.csv' -o -name '*.png' -o -name '*.rds' \\)",
    "| sort >",
    shQuote(inventory_file)
  )
)

# Copy current preview maps
current_maps <- list.files(
  "outputs/global/final_maps",
  pattern = "\\.(png|csv)$",
  full.names = TRUE
)

safe_copy(current_maps, fig_dir)

# ============================================================
# 1. Read modelling sites and observations
# ============================================================

sites <- safe_read_csv(
  "outputs/global/qc/global_model_primary_sites_5km.csv"
) %>%
  select(
    site_id,
    longitude,
    latitude,
    observed = sr,
    region,
    snap_dist_m,
    river_HYRIV_ID,
    ORD_FLOW,
    predictors_complete
  ) %>%
  distinct(site_id, .keep_all = TRUE)

obs_file <- "outputs/global/qc/global_model_primary_observations_5km.csv"

if (file.exists(obs_file)) {
  observations <- read_csv(obs_file, show_col_types = FALSE)
} else {
  observations <- tibble()
}

data_inventory <- tibble(
  item = c(
    "Primary observations",
    "Unique modelling sites",
    "HydroSHEDS regions represented",
    "Median snap distance, m",
    "95th percentile snap distance, m",
    "Maximum snap distance, m",
    "Sites with complete predictors"
  ),
  value = c(
    ifelse(nrow(observations) > 0, nrow(observations), NA),
    nrow(sites),
    n_distinct(sites$region),
    round(median(sites$snap_dist_m, na.rm = TRUE), 2),
    round(quantile(sites$snap_dist_m, 0.95, na.rm = TRUE), 2),
    round(max(sites$snap_dist_m, na.rm = TRUE), 2),
    sum(sites$predictors_complete, na.rm = TRUE)
  )
)

write_csv(
  data_inventory,
  file.path(tab_dir, "Table_01_data_inventory.csv")
)

regional_samples <- sites %>%
  count(region, name = "n_sites") %>%
  arrange(desc(n_sites))

write_csv(
  regional_samples,
  file.path(tab_dir, "Table_02_sample_counts_by_region.csv")
)

# ============================================================
# 2. Land background for maps
# ============================================================

land_cache <- "data_processed/global/article_land_background_robin.rds"

robin <- "+proj=robin +datum=WGS84 +units=m +no_defs"

if (file.exists(land_cache)) {

  land_robin <- readRDS(land_cache)

} else {

  basin_files <- list.files(
    "data_raw/hydrosheds/HydroBASINS_global",
    pattern = "hybas_.*_lev06_v1c\\.shp$",
    recursive = TRUE,
    full.names = TRUE,
    ignore.case = TRUE
  )

  if (length(basin_files) == 0) {
    stop("No HydroBASINS L6 shapefiles found.")
  }

  land_list <- lapply(
    basin_files,
    function(f) {
      x <- st_read(f, quiet = TRUE)
      x <- x[, 0, drop = FALSE]
      st_transform(x, robin)
    }
  )

  land_robin <- do.call(rbind, land_list)

  dir.create(
    dirname(land_cache),
    recursive = TRUE,
    showWarnings = FALSE
  )

  saveRDS(land_robin, land_cache)
}

sites_sf <- st_as_sf(
  sites,
  coords = c("longitude", "latitude"),
  crs = 4326,
  remove = FALSE
) %>%
  st_transform(robin)

# ============================================================
# Figure 1A. Observed sample coverage
# ============================================================

sr_limits <- quantile(
  sites$observed,
  probs = c(0.01, 0.99),
  na.rm = TRUE
)

p_sample <- ggplot() +
  geom_sf(
    data = land_robin,
    fill = "grey94",
    colour = NA
  ) +
  geom_sf(
    data = sites_sf,
    aes(colour = observed),
    size = 0.9,
    alpha = 0.82
  ) +
  scale_colour_gradientn(
    colours = hcl.colors(100, "Plasma"),
    limits = sr_limits,
    oob = squish,
    name = expression(paste("Observed ", {}^{87}, "Sr/", {}^{86}, "Sr"))
  ) +
  labs(
    title = "Figure 1A. Global river-water Sr observation sites",
    subtitle = paste0(
      format(nrow(sites), big.mark = ","),
      " unique modelling sites after 5 km HydroRIVERS snapping"
    ),
    x = NULL,
    y = NULL
  ) +
  theme_report +
  theme(
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    panel.grid = element_blank()
  )

ggsave(
  file.path(fig_dir, "Figure_1A_global_observed_sample_sites.png"),
  p_sample,
  width = 13,
  height = 7.2,
  dpi = 300
)

# ============================================================
# Figure 1B. Sample count by region
# ============================================================

p_region_samples <- ggplot(
  regional_samples,
  aes(
    x = reorder(region, n_sites),
    y = n_sites
  )
) +
  geom_col() +
  coord_flip() +
  labs(
    title = "Figure 1B. Number of modelling sites by HydroSHEDS region",
    x = "Region",
    y = "Number of modelling sites"
  ) +
  theme_report

ggsave(
  file.path(fig_dir, "Figure_1B_sample_counts_by_region.png"),
  p_region_samples,
  width = 7.5,
  height = 5.3,
  dpi = 300
)

# ============================================================
# 3. Read model-comparison results
# ============================================================

baseline <- safe_read_csv(
  "outputs/global/baseline_models/global_baseline_model_comparison.csv"
)

geology <- safe_read_csv(
  "outputs/global/geology_models/global_geology_model_comparison.csv"
)

climate <- safe_read_csv(
  "outputs/global/climate_models/global_climate_model_comparison.csv"
)

soil <- safe_read_csv(
  "outputs/global/soil_models/global_soil_model_comparison.csv"
)

# ============================================================
# Figure 2A. Main model-development chain
# ============================================================

model_chain <- bind_rows(
  baseline %>%
    filter(model == "hydro") %>%
    mutate(stage = "Hydrology only", order = 1),

  baseline %>%
    filter(model == "spatial") %>%
    mutate(stage = "Spatial only", order = 2),

  baseline %>%
    filter(model == "space_hydro") %>%
    mutate(stage = "Spatial + hydrology", order = 3),

  geology %>%
    filter(model == "space_hydro_upstream") %>%
    mutate(stage = "+ upstream geology", order = 4),

  climate %>%
    filter(model == "upstream_geo_plus_all_upstream_environment") %>%
    mutate(stage = "+ upstream environment", order = 5),

  soil %>%
    filter(model == "upstream_environment_plus_upstream_clay") %>%
    mutate(stage = "+ upstream clay", order = 6)
) %>%
  mutate(
    stage = factor(stage, levels = unique(stage[order(order)])),
    validation_label = recode(
      validation,
      random_cv = "Random CV",
      spatial_block_cv = "Spatial block CV"
    )
  )

write_csv(
  model_chain,
  file.path(tab_dir, "Table_03_main_model_development_chain.csv")
)

p_chain <- ggplot(
  model_chain,
  aes(
    x = stage,
    y = r2_sse_mean,
    group = validation_label,
    colour = validation_label
  )
) +
  geom_hline(
    yintercept = 0,
    linetype = 2,
    linewidth = 0.45
  ) +
  geom_errorbar(
    aes(
      ymin = r2_sse_mean - r2_sse_sd,
      ymax = r2_sse_mean + r2_sse_sd
    ),
    width = 0.12,
    linewidth = 0.5
  ) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 2.8) +
  labs(
    title = "Figure 2A. Random CV versus spatial block CV",
    subtitle = "Random CV strongly overestimates spatial transferability",
    x = NULL,
    y = expression(R^2[SSE]),
    colour = "Validation"
  ) +
  theme_report +
  theme(
    axis.text.x = element_text(
      angle = 30,
      hjust = 1
    )
  )

ggsave(
  file.path(fig_dir, "Figure_2A_random_vs_spatial_model_chain.png"),
  p_chain,
  width = 10,
  height = 5.8,
  dpi = 300
)

# ============================================================
# Figure 2B. All spatial-CV candidate models
# ============================================================

all_candidates <- bind_rows(
  baseline %>% mutate(model_group = "1 Baseline"),
  geology %>% mutate(model_group = "2 Geology"),
  climate %>% mutate(model_group = "3 Climate and terrain"),
  soil %>% mutate(model_group = "4 Soil")
) %>%
  filter(validation == "spatial_block_cv") %>%
  mutate(
    model_label = gsub("_", " ", model),
    selected_final =
      model == "upstream_environment_plus_upstream_clay"
  )

write_csv(
  all_candidates,
  file.path(tab_dir, "Table_04_all_spatial_CV_candidate_models.csv")
)

p_candidates <- ggplot(
  all_candidates,
  aes(
    x = reorder(model_label, r2_sse_mean),
    y = r2_sse_mean
  )
) +
  geom_hline(
    yintercept = 0,
    linetype = 2,
    linewidth = 0.4
  ) +
  geom_col(
    aes(alpha = selected_final)
  ) +
  coord_flip() +
  facet_wrap(
    ~ model_group,
    scales = "free_y",
    ncol = 1
  ) +
  scale_alpha_manual(
    values = c(`TRUE` = 1, `FALSE` = 0.65),
    guide = "none"
  ) +
  labs(
    title = "Figure 2B. Candidate models under spatial block CV",
    subtitle = "The final model is near-optimal but selected for parsimony and interpretability",
    x = NULL,
    y = expression(R^2[SSE])
  ) +
  theme_report

ggsave(
  file.path(fig_dir, "Figure_2B_all_candidate_models_spatial_CV.png"),
  p_candidates,
  width = 9.5,
  height = 11,
  dpi = 300
)

# ============================================================
# Figure 2C. Upstream clay paired shift comparison
# ============================================================

soil_shift <- safe_read_csv(
  "outputs/global/soil_models/spatial_block_cv_metrics_by_scheme.csv"
) %>%
  filter(
    model %in% c(
      "reference_upstream_environment",
      "upstream_environment_plus_upstream_clay"
    )
  ) %>%
  mutate(
    model_label = recode(
      model,
      reference_upstream_environment =
        "Reference upstream environment",
      upstream_environment_plus_upstream_clay =
        "+ upstream clay"
    )
  )

write_csv(
  soil_shift,
  file.path(tab_dir, "Table_05_upstream_clay_shift_comparison.csv")
)

p_shift <- ggplot(
  soil_shift,
  aes(
    x = model_label,
    y = r2_sse,
    group = run_id
  )
) +
  geom_line(
    aes(colour = run_id),
    linewidth = 0.7,
    alpha = 0.8
  ) +
  geom_point(
    aes(colour = run_id),
    size = 2.7
  ) +
  labs(
    title = "Figure 2C. Upstream clay across four spatial block shifts",
    x = NULL,
    y = expression(R^2[SSE]),
    colour = "Block shift"
  ) +
  theme_report

ggsave(
  file.path(fig_dir, "Figure_2C_upstream_clay_shift_comparison.png"),
  p_shift,
  width = 7.2,
  height = 5.4,
  dpi = 300
)

# ============================================================
# 4. Final model validation
# ============================================================

final_shift_metrics <- safe_read_csv(
  "outputs/global/soil_models/spatial_block_cv_metrics_by_scheme.csv"
) %>%
  filter(model == "upstream_environment_plus_upstream_clay")

write_csv(
  final_shift_metrics,
  file.path(tab_dir, "Table_06_final_model_metrics_by_spatial_shift.csv")
)

final_metrics_summary <- final_shift_metrics %>%
  summarise(
    n_shifts = n(),
    rmse_mean = mean(rmse),
    rmse_min = min(rmse),
    rmse_max = max(rmse),
    mae_mean = mean(mae),
    bias_mean = mean(bias),
    r2_sse_mean = mean(r2_sse),
    r2_sse_min = min(r2_sse),
    r2_sse_max = max(r2_sse),
    r2_cor_mean = mean(r2_cor)
  )

write_csv(
  final_metrics_summary,
  file.path(tab_dir, "Table_07_final_model_metrics_summary.csv")
)

oof_raw <- safe_read_csv(
  "outputs/global/soil_models/spatial_block_cv_predictions.csv"
) %>%
  filter(model == "upstream_environment_plus_upstream_clay")

oof_site <- oof_raw %>%
  group_by(site_id) %>%
  summarise(
    observed = first(observed),
    predicted = median(predicted, na.rm = TRUE),
    n_shifts = n_distinct(run_id),
    .groups = "drop"
  ) %>%
  mutate(
    residual = predicted - observed,
    abs_residual = abs(residual)
  ) %>%
  left_join(
    sites %>%
      select(
        site_id,
        longitude,
        latitude,
        region
      ),
    by = "site_id"
  )

write_csv(
  oof_site,
  file.path(tab_dir, "Table_08_final_model_site_median_OOF_predictions.csv")
)

rmse_oof <- sqrt(
  mean(
    (oof_site$predicted - oof_site$observed)^2,
    na.rm = TRUE
  )
)

mae_oof <- mean(
  abs(oof_site$predicted - oof_site$observed),
  na.rm = TRUE
)

bias_oof <- mean(
  oof_site$predicted - oof_site$observed,
  na.rm = TRUE
)

r2_oof <- 1 -
  sum(
    (oof_site$observed - oof_site$predicted)^2,
    na.rm = TRUE
  ) /
  sum(
    (oof_site$observed - mean(oof_site$observed, na.rm = TRUE))^2,
    na.rm = TRUE
  )

site_median_metrics <- tibble(
  metric = c("RMSE", "MAE", "Bias", "R2_SSE"),
  value = c(rmse_oof, mae_oof, bias_oof, r2_oof)
)

write_csv(
  site_median_metrics,
  file.path(tab_dir, "Table_09_site_median_OOF_metrics.csv")
)

# ------------------------------------------------------------
# Figure 3A. Observed versus predicted
# ------------------------------------------------------------

lims <- range(
  c(oof_site$observed, oof_site$predicted),
  na.rm = TRUE
)

metric_label <- paste0(
  "Site-median OOF summary\n",
  "RMSE = ", sprintf("%.5f", rmse_oof),
  "\nMAE = ", sprintf("%.5f", mae_oof),
  "\nBias = ", sprintf("%.5f", bias_oof),
  "\nR² = ", sprintf("%.3f", r2_oof)
)

p_oof <- ggplot(
  oof_site,
  aes(
    x = observed,
    y = predicted
  )
) +
  geom_abline(
    slope = 1,
    intercept = 0,
    linetype = 2,
    linewidth = 0.6
  ) +
  geom_point(
    size = 0.9,
    alpha = 0.45
  ) +
  annotate(
    "text",
    x = lims[1],
    y = lims[2],
    label = metric_label,
    hjust = 0,
    vjust = 1,
    size = 3.4
  ) +
  coord_equal(
    xlim = lims,
    ylim = lims
  ) +
  labs(
    title = "Figure 3A. Spatial out-of-fold observed versus predicted",
    subtitle = "Prediction value is the median across four spatial block shifts",
    x = expression(paste("Observed ", {}^{87}, "Sr/", {}^{86}, "Sr")),
    y = expression(paste("Predicted ", {}^{87}, "Sr/", {}^{86}, "Sr"))
  ) +
  theme_report

ggsave(
  file.path(fig_dir, "Figure_3A_spatial_OOF_observed_vs_predicted.png"),
  p_oof,
  width = 6.5,
  height = 6.2,
  dpi = 300
)

# ------------------------------------------------------------
# Figure 3B. Residual versus observed
# ------------------------------------------------------------

p_resid <- ggplot(
  oof_site,
  aes(
    x = observed,
    y = residual
  )
) +
  geom_hline(
    yintercept = 0,
    linetype = 2,
    linewidth = 0.5
  ) +
  geom_point(
    size = 0.85,
    alpha = 0.42
  ) +
  geom_smooth(
    method = "loess",
    formula = y ~ x,
    se = FALSE,
    linewidth = 0.8
  ) +
  labs(
    title = "Figure 3B. Spatial out-of-fold residuals",
    subtitle = "Residual = predicted − observed; positive values indicate overprediction",
    x = expression(paste("Observed ", {}^{87}, "Sr/", {}^{86}, "Sr")),
    y = "Residual"
  ) +
  theme_report

ggsave(
  file.path(fig_dir, "Figure_3B_residual_vs_observed.png"),
  p_resid,
  width = 7.2,
  height = 5.5,
  dpi = 300
)

# ------------------------------------------------------------
# Figure 3C. Spatial residual map
# ------------------------------------------------------------

oof_sf <- st_as_sf(
  oof_site,
  coords = c("longitude", "latitude"),
  crs = 4326,
  remove = FALSE
) %>%
  st_transform(robin)

res_limit <- quantile(
  oof_site$abs_residual,
  probs = 0.95,
  na.rm = TRUE
)

p_resid_map <- ggplot() +
  geom_sf(
    data = land_robin,
    fill = "grey94",
    colour = NA
  ) +
  geom_sf(
    data = oof_sf,
    aes(
      colour = residual,
      size = abs_residual
    ),
    alpha = 0.75
  ) +
  scale_colour_gradient2(
    low = "#2166ac",
    mid = "white",
    high = "#b2182b",
    midpoint = 0,
    limits = c(-res_limit, res_limit),
    oob = squish,
    name = "Residual"
  ) +
  scale_size_continuous(
    range = c(0.25, 2.2),
    name = "|Residual|"
  ) +
  labs(
    title = "Figure 3C. Spatial distribution of out-of-fold residuals",
    subtitle = "Blue: underprediction; red: overprediction",
    x = NULL,
    y = NULL
  ) +
  theme_report +
  theme(
    axis.text = element_blank(),
    axis.ticks = element_blank(),
    panel.grid = element_blank()
  )

ggsave(
  file.path(fig_dir, "Figure_3C_spatial_residual_map.png"),
  p_resid_map,
  width = 13,
  height = 7.2,
  dpi = 300
)

# ------------------------------------------------------------
# Figure 3D. Regional validation
# ------------------------------------------------------------

regional_validation <- oof_site %>%
  filter(!is.na(region)) %>%
  group_by(region) %>%
  summarise(
    n = n(),
    rmse = sqrt(mean((predicted - observed)^2)),
    mae = mean(abs(predicted - observed)),
    bias = mean(predicted - observed),
    median_abs_error = median(abs(predicted - observed)),
    r2_sse =
      1 -
      sum((observed - predicted)^2) /
      sum((observed - mean(observed))^2),
    .groups = "drop"
  ) %>%
  arrange(rmse)

write_csv(
  regional_validation,
  file.path(tab_dir, "Table_10_regional_spatial_validation.csv")
)

regional_long <- regional_validation %>%
  select(
    region,
    rmse,
    mae,
    median_abs_error
  ) %>%
  pivot_longer(
    cols = -region,
    names_to = "metric",
    values_to = "value"
  )

p_regional <- ggplot(
  regional_long,
  aes(
    x = reorder(region, value),
    y = value
  )
) +
  geom_col() +
  coord_flip() +
  facet_wrap(
    ~ metric,
    scales = "free_x"
  ) +
  labs(
    title = "Figure 3D. Regional spatial validation performance",
    x = "HydroSHEDS region",
    y = NULL
  ) +
  theme_report

ggsave(
  file.path(fig_dir, "Figure_3D_regional_validation_metrics.png"),
  p_regional,
  width = 9,
  height = 6.5,
  dpi = 300
)

# ============================================================
# 5. Final RF variable importance
# ============================================================

importance <- safe_read_csv(
  "outputs/global/final_RF_QRF/final_RF_variable_importance.csv"
) %>%
  arrange(desc(importance))

write_csv(
  importance,
  file.path(tab_dir, "Table_11_final_RF_variable_importance.csv")
)

importance_top15 <- importance %>%
  slice_head(n = 15)

p_imp <- ggplot(
  importance_top15,
  aes(
    x = reorder(variable, importance),
    y = importance
  )
) +
  geom_col() +
  coord_flip() +
  labs(
    title = "Figure 4. Top 15 predictors in the final RF model",
    subtitle = "Permutation importance; not a causal effect estimate",
    x = NULL,
    y = "Permutation importance"
  ) +
  theme_report

ggsave(
  file.path(fig_dir, "Figure_4_final_RF_top15_variable_importance.png"),
  p_imp,
  width = 8,
  height = 6.5,
  dpi = 300
)

# ============================================================
# 6. Prediction coverage table
# ============================================================

prediction_by_region_fallback <- tibble(
  region = c("af", "ar", "as", "au", "eu", "gr", "na", "sa", "si"),
  region_label = c(
    "Africa",
    "Arctic",
    "Asia",
    "Australasia",
    "Europe",
    "Greenland",
    "North America",
    "South America",
    "Siberia"
  ),
  total_reaches = c(
    1527551,
    324078,
    1428959,
    836472,
    938544,
    137088,
    986463,
    1620963,
    677765
  ),
  predicted_reaches = c(
    1527333,
    323838,
    1428458,
    834941,
    937933,
    75289,
    986371,
    1620942,
    677283
  )
) %>%
  mutate(
    coverage_pct = 100 * predicted_reaches / total_reaches,
    incomplete_reaches = total_reaches - predicted_reaches
  )

write_csv(
  prediction_by_region_fallback,
  file.path(tab_dir, "Table_12_global_prediction_coverage_by_region_from_checkpoint.csv")
)

prediction_global <- prediction_by_region_fallback %>%
  summarise(
    total_reaches = sum(total_reaches),
    predicted_reaches = sum(predicted_reaches),
    incomplete_reaches = sum(incomplete_reaches),
    coverage_pct = 100 * predicted_reaches / total_reaches
  )

write_csv(
  prediction_global,
  file.path(tab_dir, "Table_13_global_prediction_coverage_summary_from_checkpoint.csv")
)

# ============================================================
# 7. Write a mentor-facing summary markdown
# ============================================================

summary_file <- file.path(out_dir, "MENTOR_REPORT_SUMMARY.md")

summary_lines <- c(
  "# Mentor report summary: global river-water 87Sr/86Sr isoscape",
  "",
  paste0("Generated on: ", report_date),
  "",
  "## 1. Current status",
  "",
  "- The global modelling dataset contains 4,465 unique river-water Sr modelling sites.",
  "- Samples were snapped to HydroRIVERS within 5 km.",
  "- Final global predictions were completed for 8,477,883 HydroRIVERS reaches.",
  "- Successfully predicted reaches: 8,412,388.",
  "- Overall prediction coverage: about 99.23%.",
  "- Greenland accounts for most missing predictions because of incomplete upstream covariates.",
  "",
  "## 2. Model design",
  "",
  "- The modelling strategy compares random CV with spatial block CV.",
  "- Spatial block CV uses 1,000 km blocks and a 200 km buffer.",
  "- Four block origins were used: shift_00, shift_x, shift_y, and shift_xy.",
  "- Candidate predictors were added by mechanism: spatial coordinates, river hydrology, upstream geology, upstream climate and terrain, and upstream soil.",
  "",
  "## 3. Main validation message",
  "",
  "- Random CV substantially overestimates predictive performance.",
  "- Spatial-only and hydrology-only models have little spatial extrapolation ability.",
  "- Upstream geology gives the first substantial improvement under spatial block CV.",
  "- Upstream climate and terrain further improve performance.",
  "- The final upstream-clay model is not the numerically highest full model, but it is a near-optimal parsimonious model.",
  "",
  "## 4. Final model",
  "",
  "- Final selected model: upstream_environment_plus_upstream_clay.",
  "- Mean spatial block CV RMSE is approximately 0.00955.",
  "- Mean spatial block CV R2_SSE is approximately 0.174.",
  "- Residual convention: residual = predicted - observed.",
  "- Positive residual means overprediction; negative residual means underprediction.",
  "",
  "## 5. Final-model top predictors",
  "",
  "1. up_geo_metamorphic_frac",
  "2. sp_y",
  "3. sp_z",
  "4. up_bio12_mm",
  "5. sp_x",
  "6. up_bio1_C",
  "7. log_DIST_DN_KM",
  "8. up_elevation_m",
  "9. up_bio4_C_sd",
  "10. up_soil_clay_pct_0_30cm",
  "",
  "## 6. Existing global prediction maps",
  "",
  "- global_river_Sr_RF_mean_ordflow5_preview.png",
  "- global_river_Sr_QRF_p80_width_ordflow5_preview.png",
  "",
  "These are unmasked preview maps. They should be treated as preliminary article figures until AOA and geographic sample support are calculated.",
  "",
  "## 7. Remaining work before manuscript submission",
  "",
  "- Calculate distance to nearest observation.",
  "- Calculate basin-level sample support.",
  "- Calculate Dissimilarity Index.",
  "- Define Area of Applicability.",
  "- Redraw the global prediction map with AOA masking.",
  "- Add HydroLAKES polygons only as neutral geographical background.",
  "- Prepare final multi-panel figures and supplementary figures."
)

writeLines(summary_lines, summary_file)

# ============================================================
# 8. Save session info and file list
# ============================================================

writeLines(
  capture.output(sessionInfo()),
  file.path(meta_dir, "R_sessionInfo.txt")
)

all_report_files <- list.files(
  out_dir,
  recursive = TRUE,
  full.names = FALSE
)

writeLines(
  all_report_files,
  file.path(out_dir, "REPORT_FILE_LIST.txt")
)

cat("\n========================================\n")
cat("MENTOR REPORT MATERIALS COMPLETED\n")
cat("Output directory:\n")
cat(normalizePath(out_dir), "\n")
cat("========================================\n")
