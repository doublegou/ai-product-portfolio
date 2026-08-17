#!/usr/bin/env Rscript

source(file.path("training", "base", "v3", "R", "common.R"))
context <- v3_context()
config <- context$config
fold_dir <- file.path(context$base, "folds")
dir.create(fold_dir, recursive = TRUE, showWarnings = FALSE)

message("Reading and auditing the frozen 5,600-site release...")
data <- v3_read_training(context)
predictors <- v3_predictors(context)
columns <- config$columns

mapping <- v3_read_main_basins(context)
data[, basin_l6_key := sprintf("%.0f", as.numeric(get(columns$basin_l6)))]
data <- merge(data, mapping, by.x = "basin_l6_key", by.y = "basin_l6", all.x = TRUE, sort = FALSE)
v3_assert(!anyNA(data$hydro_system_id), "Some sites could not be mapped to HydroBASINS MAIN_BAS.")
data.table::setorderv(data, columns$id)

index <- data.table::data.table(
  site_id = as.character(data[[columns$id]]),
  row_id = seq_len(nrow(data)),
  longitude = as.numeric(data[[columns$longitude]]),
  latitude = as.numeric(data[[columns$latitude]]),
  sr87_sr86 = as.numeric(data[[columns$response]]),
  sr_band = as.character(v3_sr_band(data[[columns$response]])),
  basin_l6 = data$basin_l6_key,
  hydro_system_id = data$hydro_system_id,
  reference_id = as.character(data[[columns$reference]]),
  short_references = as.character(data$short_references),
  source_datasets = as.character(data$source_datasets)
)
for (scheme in names(config$weights)) index[, (paste0("weight_", scheme)) := v3_case_weights(sr87_sr86, scheme, context)]

expected_bands <- as.integer(unlist(config$contract$sr_bands))
actual_bands <- as.integer(table(factor(index$sr_band, levels = c("lt_072", "072_075", "075_080", "ge_080"))))
v3_assert(identical(actual_bands, expected_bands), "Sr-band count contract failed.")
v3_assert(data.table::uniqueN(index$hydro_system_id) == config$contract$hydrological_systems,
          "Hydrological-system count contract failed.")
high75 <- index[, .(high = any(sr87_sr86 >= 0.75)), by = hydro_system_id][high == TRUE, .N]
high80 <- index[, .(high = any(sr87_sr86 >= 0.80)), by = hydro_system_id][high == TRUE, .N]
v3_assert(high75 == config$contract$high_075_systems, "Sr >=0.75 system count contract failed.")
v3_assert(high80 == config$contract$high_080_systems, "Sr >=0.80 system count contract failed.")
v3_assert(all(vapply(data[, ..predictors], function(x) all(is.finite(x)), logical(1))),
          "Frozen Full50 contains non-finite predictor values.")

message("Freezing grouped Primary Nested-CV assignments...")
system_summary <- v3_group_summary(index, "hydro_system_id")
outer_parts <- list()
inner_parts <- list()
outer_seeds <- as.integer(unlist(config$validation$outer_seeds))
for (repeat_id in seq_len(config$validation$outer_repeats)) {
  group_fold <- v3_balance_groups(system_summary, "hydro_system_id", config$validation$outer_folds, outer_seeds[[repeat_id]])
  site_fold <- merge(index[, .(site_id, hydro_system_id)], group_fold, by = "hydro_system_id", sort = FALSE)
  site_fold[, repeat_id := repeat_id]
  outer_parts[[repeat_id]] <- site_fold[, .(site_id, repeat_id, outer_fold = fold, hydro_system_id)]
  for (outer_fold in seq_len(config$validation$outer_folds)) {
    task <- (repeat_id - 1L) * config$validation$outer_folds + outer_fold
    train_index <- index[!hydro_system_id %in% group_fold[fold == outer_fold, hydro_system_id]]
    train_summary <- v3_group_summary(train_index, "hydro_system_id")
    inner_group <- v3_balance_groups(train_summary, "hydro_system_id", config$validation$inner_folds,
                                     as.integer(config$validation$inner_seed_base) + task)
    inner_site <- merge(train_index[, .(site_id, hydro_system_id)], inner_group, by = "hydro_system_id", sort = FALSE)
    inner_site[, `:=`(task = task, repeat_id = repeat_id, outer_fold = outer_fold)]
    inner_parts[[task]] <- inner_site[, .(site_id, task, repeat_id, outer_fold, inner_fold = fold, hydro_system_id)]
  }
}
outer_folds <- data.table::rbindlist(outer_parts)
inner_folds <- data.table::rbindlist(inner_parts)

v3_assert(nrow(outer_folds) == nrow(index) * config$validation$outer_repeats,
          "Outer assignment row count failed.")
v3_assert(all(outer_folds[, .N, by = .(site_id, repeat_id)]$N == 1L), "Each site must occur once per Outer repeat.")
for (task_id in seq_len(15L)) {
  coordinates <- v3_task_coordinates(task_id)
  held <- outer_folds[repeat_id == coordinates$repeat_id & outer_fold == coordinates$outer_fold, hydro_system_id]
  trained <- inner_folds[task == task_id, hydro_system_id]
  v3_assert(!length(intersect(held, trained)), paste("Outer leakage in task", task_id))
}

message("Freezing spatial and reference stress folds...")
points <- sf::st_as_sf(index, coords = c("longitude", "latitude"), crs = 4326, remove = FALSE)
projected <- sf::st_transform(points, as.integer(config$validation$spatial_crs))
coordinates <- sf::st_coordinates(projected)
stress_parts <- list()
part <- 1L
for (km in as.integer(unlist(config$validation$spatial_km))) {
  metres <- km * 1000
  blocks <- sprintf("x%s_y%s", floor(coordinates[, 1L] / metres), floor(coordinates[, 2L] / metres))
  spatial_index <- data.table::copy(index)
  spatial_index[, stress_group := blocks]
  summary <- v3_group_summary(spatial_index, "stress_group")
  assignment <- v3_balance_groups(summary, "stress_group", 5L, as.integer(config$validation$stress_seed_base) + km)
  rows <- merge(spatial_index[, .(site_id, stress_group)], assignment, by = "stress_group", sort = FALSE)
  rows[, scheme := paste0("spatial_", km)]
  stress_parts[[part]] <- rows[, .(site_id, scheme, fold, stress_group)]
  part <- part + 1L
}
reference_index <- data.table::copy(index)
reference_index[, stress_group := ifelse(nzchar(reference_id), reference_id, paste0("missing_reference_", site_id))]
reference_summary <- v3_group_summary(reference_index, "stress_group")
reference_assignment <- v3_balance_groups(reference_summary, "stress_group", 5L,
                                           as.integer(config$validation$stress_seed_base) + 1L)
reference_rows <- merge(reference_index[, .(site_id, stress_group)], reference_assignment, by = "stress_group", sort = FALSE)
reference_rows[, scheme := "reference"]
stress_parts[[part]] <- reference_rows[, .(site_id, scheme, fold, stress_group)]
stress_folds <- data.table::rbindlist(stress_parts)

for (scheme_name in unique(stress_folds$scheme)) {
  check <- stress_folds[scheme == scheme_name]
  v3_assert(nrow(check) == nrow(index) && !anyDuplicated(check$site_id), paste("Stress coverage failed:", scheme_name))
}

message("Freezing full and task-specific coarse candidate pools...")
rf_pool <- v3_rf_pool(context)
xgb_pool <- v3_xgb_pool(context)
coarse_parts <- list()
for (task in seq_len(15L)) {
  rf <- v3_maximin(rf_pool, as.integer(config$rf$coarse_structures), seed = 77100L + task)
  rf[, `:=`(model = "rf", task = task, coarse_order = seq_len(.N))]
  xgb <- v3_maximin(xgb_pool, as.integer(config$xgb$coarse_structures), seed = 77200L + task)
  xgb[, `:=`(model = "xgb", task = task, coarse_order = seq_len(.N))]
  coarse_parts[[length(coarse_parts) + 1L]] <- rf
  coarse_parts[[length(coarse_parts) + 1L]] <- xgb
}
coarse_pool <- data.table::rbindlist(coarse_parts, fill = TRUE)

outer_balance <- merge(outer_folds, index[, .(site_id, sr87_sr86)], by = "site_id")[, .(
  rows = .N, systems = data.table::uniqueN(hydro_system_id), n_072 = sum(sr87_sr86 >= 0.72),
  n_075 = sum(sr87_sr86 >= 0.75), n_080 = sum(sr87_sr86 >= 0.80)
), by = .(repeat_id, outer_fold)]
inner_balance <- merge(inner_folds, index[, .(site_id, sr87_sr86)], by = "site_id")[, .(
  rows = .N, systems = data.table::uniqueN(hydro_system_id), n_072 = sum(sr87_sr86 >= 0.72),
  n_075 = sum(sr87_sr86 >= 0.75), n_080 = sum(sr87_sr86 >= 0.80)
), by = .(task, repeat_id, outer_fold, inner_fold)]
stress_balance <- merge(stress_folds, index[, .(site_id, sr87_sr86)], by = "site_id")[, .(
  rows = .N, groups = data.table::uniqueN(stress_group), n_072 = sum(sr87_sr86 >= 0.72),
  n_075 = sum(sr87_sr86 >= 0.75), n_080 = sum(sr87_sr86 >= 0.80)
), by = .(scheme, fold)]

release <- list(data = data[, c(columns$id, columns$response, predictors), with = FALSE], index = index, predictors = predictors)
v3_atomic_fwrite(index, file.path(fold_dir, "training_index.csv"))
v3_atomic_fwrite(system_summary, file.path(fold_dir, "hydrological_systems.csv"))
v3_atomic_fwrite(outer_folds, file.path(fold_dir, "outer_folds.csv"))
v3_atomic_fwrite(inner_folds, file.path(fold_dir, "inner_folds.csv"))
v3_atomic_fwrite(stress_folds, file.path(fold_dir, "stress_folds.csv"))
v3_atomic_fwrite(rf_pool, file.path(fold_dir, "rf_pool.csv"))
v3_atomic_fwrite(xgb_pool, file.path(fold_dir, "xgb_pool.csv"))
v3_atomic_fwrite(coarse_pool, file.path(fold_dir, "coarse_pool.csv"))
v3_atomic_fwrite(outer_balance, file.path(fold_dir, "outer_balance.csv"))
v3_atomic_fwrite(inner_balance, file.path(fold_dir, "inner_balance.csv"))
v3_atomic_fwrite(stress_balance, file.path(fold_dir, "stress_balance.csv"))
v3_atomic_rds(release, file.path(fold_dir, "training_release.rds"))

output_paths <- c("training_index.csv", "hydrological_systems.csv", "outer_folds.csv", "inner_folds.csv",
                  "stress_folds.csv", "rf_pool.csv", "xgb_pool.csv", "coarse_pool.csv", "outer_balance.csv",
                  "inner_balance.csv", "stress_balance.csv", "training_release.rds")
manifest <- list(
  project = "base_v3_prepare",
  status = "validated",
  created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
  input = list(
    training_csv = context$config$input$training_csv,
    training_sha256 = v3_sha256(v3_path(context, context$config$input$training_csv)),
    config_sha256 = v3_sha256(context$config_path),
    source_sha256 = v3_source_sha256(context),
    predictor_manifest_sha256 = v3_sha256(v3_path(context, context$config$input$predictors))
  ),
  counts = list(
    rows = nrow(index), predictors = length(predictors), hydrological_systems = data.table::uniqueN(index$hydro_system_id),
    high_075_systems = high75, high_080_systems = high80, outer_tasks = 15L,
    inner_folds_per_task = 5L, stress_tasks_per_model = 20L,
    rf_structures = nrow(rf_pool), xgb_structures = nrow(xgb_pool)
  ),
  outputs = stats::setNames(lapply(output_paths, function(name) list(path = file.path("training/base/v3/folds", name),
                                                                    sha256 = v3_sha256(file.path(fold_dir, name)))), output_paths)
)
v3_atomic_json(manifest, file.path(fold_dir, "manifest.json"))
message("Base V3 preparation complete: ", normalizePath(fold_dir, winslash = "/"))
