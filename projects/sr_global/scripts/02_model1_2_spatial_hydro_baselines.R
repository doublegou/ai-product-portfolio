############################################################
# Step 2: Model 1-2 spatial and HydroRIVERS baselines
############################################################

rm(list = ls())
gc()

suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(readr)
  library(tidyr)
  library(ggplot2)
  library(viridis)
  library(ranger)
})

site_dir <- Sys.getenv("SR_SITE_DIR", unset = path.expand("~/projects/sr_global"))
sr_pr_file <- file.path(site_dir, "data_processed", "sr_solute_pearl_southchina.rds")
hydrorivers_shp <- Sys.getenv("SR_HYDRORIVERS_SHP", unset = "")

if (hydrorivers_shp == "") {
  candidate <- list.files(
    file.path(site_dir, "data_raw", "hydrosheds", "HydroRIVERS"),
    pattern = "\\.shp$",
    recursive = TRUE,
    full.names = TRUE
  )
  if (length(candidate) == 0) {
    stop("No HydroRIVERS shapefile found. Put the whole HydroRIVERS shapefile folder under data_raw/hydrosheds/HydroRIVERS or set SR_HYDRORIVERS_SHP.")
  }
  hydrorivers_shp <- candidate[1]
}

message("site_dir: ", site_dir)
message("sr_pr_file: ", sr_pr_file)
message("HydroRIVERS shapefile: ", hydrorivers_shp)
stopifnot(file.exists(sr_pr_file))
stopifnot(file.exists(hydrorivers_shp))

dir.create(file.path(site_dir, "data_processed"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(site_dir, "models"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(site_dir, "outputs"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(site_dir, "outputs", "figures"), recursive = TRUE, showWarnings = FALSE)

calc_metrics <- function(obs, pred) {
  data.frame(
    RMSE = sqrt(mean((obs - pred)^2, na.rm = TRUE)),
    MAE  = mean(abs(obs - pred), na.rm = TRUE),
    R2   = cor(obs, pred, use = "complete.obs")^2,
    Bias = mean(pred - obs, na.rm = TRUE)
  )
}

safe_log1p <- function(x) log1p(as.numeric(x))

bbox_pr <- sf::st_bbox(
  c(xmin = 96.5, xmax = 116.5, ymin = 20.0, ymax = 27.8),
  crs = sf::st_crs(4326)
)

sr_pr <- readRDS(sr_pr_file)
if (is.na(sf::st_crs(sr_pr))) sf::st_crs(sr_pr) <- 4326
sr_pr <- sf::st_transform(sr_pr, 4326)

if (!("sr87_sr86" %in% names(sr_pr))) {
  stop("sr87_sr86 column not found in sr_pr. Check Step 1 output.")
}

# Model 1 dataset: spatial baseline only
model1_df <- sr_pr %>%
  sf::st_drop_geometry() %>%
  transmute(
    sr = as.numeric(sr87_sr86),
    longitude = as.numeric(longitude),
    latitude = as.numeric(latitude)
  ) %>%
  filter(!is.na(sr), !is.na(longitude), !is.na(latitude))

p_sr_hist <- ggplot(model1_df, aes(x = sr)) +
  geom_histogram(bins = 30) +
  labs(title = "Distribution of dissolved river-water 87Sr/86Sr", x = "87Sr/86Sr", y = "Count") +
  theme_bw()

ggsave(
  file.path(site_dir, "outputs", "figures", "model1_sr_distribution.png"),
  p_sr_hist,
  width = 7,
  height = 5,
  dpi = 300
)

# HydroRIVERS
rivers_asia <- sf::st_read(hydrorivers_shp, quiet = TRUE)
if (is.na(sf::st_crs(rivers_asia))) sf::st_crs(rivers_asia) <- 4326
rivers_asia <- sf::st_transform(rivers_asia, 4326)
rivers_pr <- suppressWarnings(sf::st_crop(rivers_asia, bbox_pr))

if (!"river_row_id" %in% names(rivers_pr)) {
  rivers_pr <- rivers_pr %>% mutate(river_row_id = row_number())
}

message("HydroRIVERS segments in pilot bbox: ", nrow(rivers_pr))

required_hydro_cols <- c(
  "HYRIV_ID", "NEXT_DOWN", "LENGTH_KM", "DIST_DN_KM", "DIST_UP_KM",
  "CATCH_SKM", "UPLAND_SKM", "DIS_AV_CMS", "ORD_STRA", "ORD_CLAS",
  "ORD_FLOW", "HYBAS_L12"
)
missing_hydro_cols <- setdiff(required_hydro_cols, names(rivers_pr))
if (length(missing_hydro_cols) > 0) {
  stop("Missing HydroRIVERS columns: ", paste(missing_hydro_cols, collapse = ", "))
}

# Snap points to nearest river segment
sr_pr_m <- sf::st_transform(sr_pr, 3857)
rivers_pr_m <- sf::st_transform(rivers_pr, 3857)
nearest_idx <- sf::st_nearest_feature(sr_pr_m, rivers_pr_m)

snap_dist_m <- as.numeric(sf::st_distance(
  sr_pr_m,
  rivers_pr_m[nearest_idx, ],
  by_element = TRUE
))

rivers_attr <- rivers_pr_m %>%
  sf::st_drop_geometry() %>%
  mutate(nearest_river_row = row_number())

sr_snapped <- sr_pr_m %>%
  mutate(
    nearest_river_row = nearest_idx,
    snap_dist_m = snap_dist_m
  ) %>%
  left_join(rivers_attr, by = "nearest_river_row") %>%
  sf::st_transform(4326)

saveRDS(sr_snapped, file.path(site_dir, "data_processed", "model1_2_sr_snapped_all.rds"))
write.csv(
  sf::st_drop_geometry(sr_snapped),
  file.path(site_dir, "outputs", "model1_2_sr_snapped_all.csv"),
  row.names = FALSE
)

p_snap_hist <- ggplot(sf::st_drop_geometry(sr_snapped), aes(x = snap_dist_m)) +
  geom_histogram(bins = 40) +
  labs(title = "Snap distance from Sr sample points to nearest HydroRIVERS reach", x = "Snap distance (m)", y = "Count") +
  theme_bw()

ggsave(
  file.path(site_dir, "outputs", "figures", "model1_2_snap_distance_hist.png"),
  p_snap_hist,
  width = 7,
  height = 5,
  dpi = 300
)

sr_snapped_clean <- sr_snapped %>% filter(snap_dist_m <= 5000)
message("Snapped points total: ", nrow(sr_snapped))
message("Snapped points retained within 5 km: ", nrow(sr_snapped_clean))

saveRDS(sr_snapped_clean, file.path(site_dir, "data_processed", "model1_2_sr_snapped_clean_5km.rds"))

p_snap_map <- ggplot() +
  geom_sf(data = rivers_pr, color = "grey75", linewidth = 0.25) +
  geom_sf(data = sr_snapped_clean, aes(color = snap_dist_m), size = 1.8, alpha = 0.85) +
  coord_sf(xlim = c(96.5, 116.5), ylim = c(20.0, 27.8), expand = FALSE) +
  scale_color_viridis_c(name = "Snap distance (m)") +
  labs(
    title = "Sr sample points snapped to HydroRIVERS",
    subtitle = paste0("Points retained within 5 km: n = ", nrow(sr_snapped_clean)),
    x = "Longitude", y = "Latitude"
  ) +
  theme_bw()

ggsave(
  file.path(site_dir, "outputs", "figures", "model1_2_snap_map.png"),
  p_snap_map,
  width = 8,
  height = 5,
  dpi = 300
)

hydro_df <- sr_snapped_clean %>%
  sf::st_drop_geometry() %>%
  transmute(
    sr = as.numeric(sr87_sr86),
    longitude = as.numeric(longitude),
    latitude = as.numeric(latitude),
    snap_dist_m = as.numeric(snap_dist_m),
    HYRIV_ID = HYRIV_ID,
    NEXT_DOWN = NEXT_DOWN,
    LENGTH_KM = as.numeric(LENGTH_KM),
    DIST_DN_KM = as.numeric(DIST_DN_KM),
    DIST_UP_KM = as.numeric(DIST_UP_KM),
    CATCH_SKM = as.numeric(CATCH_SKM),
    UPLAND_SKM = as.numeric(UPLAND_SKM),
    DIS_AV_CMS = as.numeric(DIS_AV_CMS),
    ORD_STRA = as.numeric(ORD_STRA),
    ORD_CLAS = as.numeric(ORD_CLAS),
    ORD_FLOW = as.numeric(ORD_FLOW),
    HYBAS_L12 = HYBAS_L12
  ) %>%
  filter(!is.na(sr))

model2_df <- hydro_df %>%
  mutate(
    log_DIS_AV_CMS = safe_log1p(DIS_AV_CMS),
    log_UPLAND_SKM = safe_log1p(UPLAND_SKM),
    log_CATCH_SKM = safe_log1p(CATCH_SKM),
    log_LENGTH_KM = safe_log1p(LENGTH_KM),
    log_DIST_DN_KM = safe_log1p(DIST_DN_KM),
    log_DIST_UP_KM = safe_log1p(DIST_UP_KM)
  ) %>%
  select(
    sr, longitude, latitude,
    log_DIS_AV_CMS, log_UPLAND_SKM, log_CATCH_SKM,
    log_LENGTH_KM, log_DIST_DN_KM, log_DIST_UP_KM,
    ORD_STRA, ORD_CLAS, ORD_FLOW
  ) %>%
  filter(complete.cases(.))

message("Model 2 dataframe n: ", nrow(model2_df))
saveRDS(model2_df, file.path(site_dir, "data_processed", "model2_df_spatial_hydrorivers_baseline.rds"))
write.csv(model2_df, file.path(site_dir, "outputs", "model2_df_spatial_hydrorivers_baseline.csv"), row.names = FALSE)

set.seed(123)
n <- nrow(model2_df)
train_id <- sample(seq_len(n), size = floor(0.8 * n))
train <- model2_df[train_id, ]
test <- model2_df[-train_id, ]

# Model A: Linear spatial baseline
m_lm_space <- lm(sr ~ longitude + latitude, data = train)
test$pred_lm_space <- predict(m_lm_space, newdata = test)

# Model B: RF spatial baseline
set.seed(123)
m_rf_space <- ranger(
  sr ~ longitude + latitude,
  data = train,
  num.trees = 500,
  importance = "permutation",
  seed = 123
)
test$pred_rf_space <- predict(m_rf_space, data = test)$predictions

# Model C: RF HydroRIVERS only
hydro_formula <- sr ~ log_DIS_AV_CMS + log_UPLAND_SKM + log_CATCH_SKM +
  log_LENGTH_KM + log_DIST_DN_KM + log_DIST_UP_KM +
  ORD_STRA + ORD_CLAS + ORD_FLOW

set.seed(123)
m_rf_hydro <- ranger(
  hydro_formula,
  data = train,
  num.trees = 500,
  importance = "permutation",
  seed = 123
)
test$pred_rf_hydro <- predict(m_rf_hydro, data = test)$predictions

# Model D: RF spatial + HydroRIVERS
space_hydro_formula <- sr ~ longitude + latitude +
  log_DIS_AV_CMS + log_UPLAND_SKM + log_CATCH_SKM +
  log_LENGTH_KM + log_DIST_DN_KM + log_DIST_UP_KM +
  ORD_STRA + ORD_CLAS + ORD_FLOW

set.seed(123)
m_rf_space_hydro <- ranger(
  space_hydro_formula,
  data = train,
  num.trees = 500,
  importance = "permutation",
  seed = 123
)
test$pred_rf_space_hydro <- predict(m_rf_space_hydro, data = test)$predictions

metrics_fair <- bind_rows(
  Linear_spatial = calc_metrics(test$sr, test$pred_lm_space),
  RF_spatial = calc_metrics(test$sr, test$pred_rf_space),
  RF_hydro_only = calc_metrics(test$sr, test$pred_rf_hydro),
  RF_space_plus_hydro = calc_metrics(test$sr, test$pred_rf_space_hydro),
  .id = "model"
)

write.csv(metrics_fair, file.path(site_dir, "outputs", "model1_2_metrics_fair.csv"), row.names = FALSE)
saveRDS(
  list(
    metrics = metrics_fair,
    train = train,
    test = test,
    m_lm_space = m_lm_space,
    m_rf_space = m_rf_space,
    m_rf_hydro = m_rf_hydro,
    m_rf_space_hydro = m_rf_space_hydro
  ),
  file.path(site_dir, "models", "model1_2_spatial_hydro_baselines.rds")
)

metrics_fair_long <- metrics_fair %>%
  tidyr::pivot_longer(cols = c(RMSE, MAE, R2, Bias), names_to = "metric", values_to = "value")

p_metrics <- ggplot(metrics_fair_long, aes(x = model, y = value)) +
  geom_col() +
  facet_wrap(~ metric, scales = "free_y") +
  coord_flip() +
  labs(title = "Model 1-2 comparison: spatial and HydroRIVERS baselines", subtitle = "All models evaluated on the same train/test split", x = NULL, y = "Metric value") +
  theme_bw()

ggsave(file.path(site_dir, "outputs", "figures", "model1_2_metrics_comparison.png"), p_metrics, width = 8, height = 5, dpi = 300)

pred_long <- test %>%
  select(sr, pred_lm_space, pred_rf_space, pred_rf_hydro, pred_rf_space_hydro) %>%
  tidyr::pivot_longer(cols = starts_with("pred_"), names_to = "model", values_to = "prediction") %>%
  mutate(model = recode(
    model,
    pred_lm_space = "Linear spatial",
    pred_rf_space = "RF spatial",
    pred_rf_hydro = "RF HydroRIVERS only",
    pred_rf_space_hydro = "RF spatial + HydroRIVERS"
  ))

p_obs_pred <- ggplot(pred_long, aes(x = sr, y = prediction)) +
  geom_point(alpha = 0.7, size = 1.8) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed") +
  facet_wrap(~ model) +
  labs(title = "Observed vs predicted dissolved river-water 87Sr/86Sr", subtitle = "Spatial and HydroRIVERS baseline models", x = "Observed 87Sr/86Sr", y = "Predicted 87Sr/86Sr") +
  theme_bw()

ggsave(file.path(site_dir, "outputs", "figures", "model1_2_observed_vs_predicted.png"), p_obs_pred, width = 9, height = 6, dpi = 300)

resid_map_df <- test %>%
  mutate(
    resid_rf_space = sr - pred_rf_space,
    resid_rf_hydro = sr - pred_rf_hydro,
    resid_rf_space_hydro = sr - pred_rf_space_hydro
  ) %>%
  select(longitude, latitude, resid_rf_space, resid_rf_hydro, resid_rf_space_hydro) %>%
  tidyr::pivot_longer(cols = starts_with("resid_"), names_to = "model", values_to = "residual") %>%
  mutate(model = recode(
    model,
    resid_rf_space = "RF spatial",
    resid_rf_hydro = "RF HydroRIVERS only",
    resid_rf_space_hydro = "RF spatial + HydroRIVERS"
  ))

p_resid_map <- ggplot(resid_map_df, aes(x = longitude, y = latitude, color = residual)) +
  geom_point(size = 2, alpha = 0.85) +
  coord_equal() +
  scale_color_gradient2(name = "Residual\nObserved - predicted") +
  facet_wrap(~ model) +
  labs(title = "Spatial residuals from baseline models", subtitle = "Positive residuals mean observed 87Sr/86Sr is higher than predicted", x = "Longitude", y = "Latitude") +
  theme_bw()

ggsave(file.path(site_dir, "outputs", "figures", "model1_2_residual_maps.png"), p_resid_map, width = 9, height = 6, dpi = 300)

importance_df <- data.frame(
  variable = names(m_rf_space_hydro$variable.importance),
  importance = as.numeric(m_rf_space_hydro$variable.importance)
) %>%
  arrange(desc(importance))

write.csv(importance_df, file.path(site_dir, "outputs", "model1_2_variable_importance.csv"), row.names = FALSE)

p_importance <- ggplot(importance_df, aes(x = reorder(variable, importance), y = importance)) +
  geom_col() +
  coord_flip() +
  labs(title = "Variable importance: RF spatial + HydroRIVERS model", x = NULL, y = "Permutation importance") +
  theme_bw()

ggsave(file.path(site_dir, "outputs", "figures", "model1_2_variable_importance.png"), p_importance, width = 7, height = 5, dpi = 300)

message("Step 2 finished.")
print(metrics_fair)
