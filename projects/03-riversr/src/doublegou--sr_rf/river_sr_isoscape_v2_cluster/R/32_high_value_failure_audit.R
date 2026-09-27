#!/usr/bin/env Rscript

options(
  stringsAsFactors = FALSE,
  scipen = 999
)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(ggplot2)
  library(tibble)
})

project_dir <- normalizePath(
  "~/river_sr_isoscape_v2_cluster",
  mustWork = TRUE
)

setwd(project_dir)

model_path <- "data/processed/model_table_age_test.rds"
oof_path   <- "outputs/experiment_age_stop_test/oof_predictions.rds"
out_dir    <- "outputs/high_value_failure_diagnosis"

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

message("Project directory: ", project_dir)
message("Reading model table: ", model_path)
message("Reading OOF predictions: ", oof_path)


# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

drop_geometry_safely <- function(x) {
  if (inherits(x, "sf")) {
    if (!requireNamespace("sf", quietly = TRUE)) {
      stop(
        "The model table is an sf object, but package 'sf' ",
        "is unavailable."
      )
    }

    x <- sf::st_drop_geometry(x)
  }

  as.data.frame(x)
}


flatten_prediction_object <- function(x) {
  if (is.data.frame(x)) {
    return(as.data.frame(x))
  }

  if (is.list(x)) {
    candidates <- c(
      "predictions",
      "oof_predictions",
      "results",
      "data"
    )

    for (candidate in candidates) {
      if (
        candidate %in% names(x) &&
        is.data.frame(x[[candidate]])
      ) {
        return(as.data.frame(x[[candidate]]))
      }
    }

    attempt <- tryCatch(
      dplyr::bind_rows(x),
      error = function(e) NULL
    )

    if (!is.null(attempt) && nrow(attempt) > 0L) {
      return(as.data.frame(attempt))
    }
  }

  stop(
    "Could not convert oof_predictions.rds ",
    "to a data frame."
  )
}


pick_column <- function(
  data,
  exact = character(),
  regex = character(),
  required = TRUE,
  label = "column"
) {
  existing_exact <- exact[exact %in% names(data)]

  if (length(existing_exact) > 0L) {
    return(existing_exact[[1]])
  }

  for (pattern in regex) {
    hit <- grep(
      pattern,
      names(data),
      ignore.case = TRUE,
      value = TRUE
    )

    if (length(hit) > 0L) {
      return(hit[[1]])
    }
  }

  if (required) {
    stop(
      "Could not identify ", label, ".\n",
      "Available columns:\n",
      paste(names(data), collapse = "\n")
    )
  }

  NA_character_
}


safe_numeric <- function(x) {
  suppressWarnings(as.numeric(as.character(x)))
}


rmse_value <- function(observed, predicted) {
  keep <- is.finite(observed) & is.finite(predicted)

  if (!any(keep)) {
    return(NA_real_)
  }

  sqrt(
    mean(
      (predicted[keep] - observed[keep])^2
    )
  )
}


mae_value <- function(observed, predicted) {
  keep <- is.finite(observed) & is.finite(predicted)

  if (!any(keep)) {
    return(NA_real_)
  }

  mean(
    abs(predicted[keep] - observed[keep])
  )
}


bias_value <- function(observed, predicted) {
  keep <- is.finite(observed) & is.finite(predicted)

  if (!any(keep)) {
    return(NA_real_)
  }

  mean(
    predicted[keep] - observed[keep]
  )
}


slope_value <- function(observed, predicted) {
  keep <- is.finite(observed) & is.finite(predicted)

  if (
    sum(keep) < 3L ||
    length(unique(observed[keep])) < 2L
  ) {
    return(NA_real_)
  }

  unname(
    coef(
      lm(
        predicted[keep] ~ observed[keep]
      )
    )[[2]]
  )
}


summarise_metrics <- function(data) {
  tibble(
    n = nrow(data),

    observed_min = ifelse(
      nrow(data) > 0L,
      min(data$observed, na.rm = TRUE),
      NA_real_
    ),

    observed_max = ifelse(
      nrow(data) > 0L,
      max(data$observed, na.rm = TRUE),
      NA_real_
    ),

    predicted_min = ifelse(
      nrow(data) > 0L,
      min(data$predicted, na.rm = TRUE),
      NA_real_
    ),

    predicted_max = ifelse(
      nrow(data) > 0L,
      max(data$predicted, na.rm = TRUE),
      NA_real_
    ),

    rmse = rmse_value(
      data$observed,
      data$predicted
    ),

    mae = mae_value(
      data$observed,
      data$predicted
    ),

    bias_pred_minus_obs = bias_value(
      data$observed,
      data$predicted
    ),

    median_bias_pred_minus_obs = median(
      data$predicted - data$observed,
      na.rm = TRUE
    ),

    mean_underprediction_obs_minus_pred = mean(
      data$observed - data$predicted,
      na.rm = TRUE
    ),

    slope_pred_on_obs = slope_value(
      data$observed,
      data$predicted
    )
  )
}


# ------------------------------------------------------------
# Read inputs
# ------------------------------------------------------------

if (!file.exists(model_path)) {
  stop("Missing model table: ", model_path)
}

if (!file.exists(oof_path)) {
  stop("Missing OOF predictions: ", oof_path)
}

model <- readRDS(model_path) |>
  drop_geometry_safely()

oof <- readRDS(oof_path) |>
  flatten_prediction_object()


# ------------------------------------------------------------
# Identify key fields
# ------------------------------------------------------------

model_id_col <- pick_column(
  model,
  exact = c(
    "row_id",
    "sample_id",
    "id"
  ),
  regex = c(
    "^row_?id$",
    "sample.*id"
  ),
  label = "model-table row identifier"
)

oof_id_col <- pick_column(
  oof,
  exact = c(
    "row_id",
    "sample_id",
    "id"
  ),
  regex = c(
    "^row_?id$",
    "sample.*id"
  ),
  label = "OOF row identifier"
)

model_outcome_col <- pick_column(
  model,
  exact = c(
    "sr87_sr86",
    "observed",
    "obs",
    "truth"
  ),
  regex = c(
    "sr87.*sr86",
    "^observed$",
    "^truth$"
  ),
  label = "model-table outcome"
)

predictor_set_col <- pick_column(
  oof,
  exact = c(
    "predictor_set",
    "scenario",
    "feature_set"
  ),
  regex = c(
    "predictor.*set",
    "feature.*set"
  ),
  label = "predictor-set field"
)

algorithm_col <- pick_column(
  oof,
  exact = c(
    "algorithm",
    "model",
    "learner"
  ),
  regex = c(
    "^algorithm$",
    "^model$",
    "learner"
  ),
  label = "algorithm field"
)

fold_col <- pick_column(
  oof,
  exact = c(
    "outer_fold",
    "fold",
    "fold_id"
  ),
  regex = c(
    "outer.*fold",
    "^fold$"
  ),
  label = "outer-fold field"
)

predicted_col <- pick_column(
  oof,
  exact = c(
    "predicted",
    "prediction",
    "pred",
    ".pred",
    "estimate",
    "yhat"
  ),
  regex = c(
    "^predicted$",
    "^prediction$",
    "^pred$",
    "\\.pred$",
    "^estimate$",
    "yhat"
  ),
  label = "predicted-value field"
)

observed_oof_col <- pick_column(
  oof,
  exact = c(
    "sr87_sr86",
    "observed",
    "obs",
    "truth",
    "actual"
  ),
  regex = c(
    "sr87.*sr86",
    "^observed$",
    "^truth$",
    "^actual$"
  ),
  required = FALSE,
  label = "OOF observed-value field"
)


# ------------------------------------------------------------
# Standardise row identifier
# ------------------------------------------------------------

names(model)[names(model) == model_id_col] <- "row_id"
names(oof)[names(oof) == oof_id_col] <- "row_id"

model$row_id <- as.character(model$row_id)
oof$row_id   <- as.character(oof$row_id)


# ------------------------------------------------------------
# Keep useful model metadata
# ------------------------------------------------------------

metadata_patterns <- c(
  "^p0__",
  "age",
  "frac_midpoint",
  "ancient",
  "hybas",
  "longitude",
  "latitude",
  "^lon$",
  "^lat$",
  "reference",
  "citation",
  "source",
  "paper",
  "study",
  "author",
  "doi",
  "region",
  "country",
  "continent",
  "join",
  "distance"
)

metadata_flag <- rep(
  FALSE,
  ncol(model)
)

for (pattern in metadata_patterns) {
  metadata_flag <- metadata_flag |
    grepl(
      pattern,
      names(model),
      ignore.case = TRUE
    )
}

model_keep_cols <- unique(
  c(
    "row_id",
    model_outcome_col,
    names(model)[metadata_flag]
  )
)

model_meta <- model |>
  select(
    any_of(model_keep_cols)
  ) |>
  distinct(
    row_id,
    .keep_all = TRUE
  )


# ------------------------------------------------------------
# Join OOF predictions to model metadata
# ------------------------------------------------------------

joined <- oof |>
  left_join(
    model_meta,
    by = "row_id",
    suffix = c("", "_model")
  )

observed_joined_col <- if (
  !is.na(observed_oof_col) &&
  observed_oof_col %in% names(joined)
) {
  observed_oof_col
} else if (
  model_outcome_col %in% names(joined)
) {
  model_outcome_col
} else if (
  paste0(model_outcome_col, "_model") %in% names(joined)
) {
  paste0(model_outcome_col, "_model")
} else {
  stop("Could not recover observed outcome after join.")
}


# ------------------------------------------------------------
# Restrict diagnosis to formal P0 baseline
# ------------------------------------------------------------

available_sets <- unique(
  as.character(
    joined[[predictor_set_col]]
  )
)

if (!"P0" %in% available_sets) {
  stop(
    "P0 was not found in predictor-set values: ",
    paste(available_sets, collapse = ", ")
  )
}

audit <- joined |>
  filter(
    .data[[predictor_set_col]] == "P0"
  ) |>
  mutate(
    predictor_set = as.character(
      .data[[predictor_set_col]]
    ),

    algorithm = as.character(
      .data[[algorithm_col]]
    ),

    outer_fold = as.character(
      .data[[fold_col]]
    ),

    observed = safe_numeric(
      .data[[observed_joined_col]]
    ),

    predicted = safe_numeric(
      .data[[predicted_col]]
    ),

    residual_pred_minus_obs =
      predicted - observed,

    underprediction_obs_minus_pred =
      observed - predicted,

    abs_error =
      abs(predicted - observed),

    squared_error =
      (predicted - observed)^2,

    high_ge_0p720 =
      observed >= 0.720,

    high_ge_0p750 =
      observed >= 0.750,

    extreme_ge_0p800 =
      observed >= 0.800,

    extreme_ge_0p900 =
      observed >= 0.900
  ) |>
  filter(
    is.finite(observed),
    is.finite(predicted)
  )


# ------------------------------------------------------------
# Detect useful descriptive columns
# ------------------------------------------------------------

source_col <- pick_column(
  audit,
  exact = c(
    "reference",
    "source",
    "paper",
    "study",
    "citation",
    "doi"
  ),
  regex = c(
    "reference",
    "citation",
    "source",
    "paper",
    "study",
    "author",
    "doi"
  ),
  required = FALSE,
  label = "source/reference field"
)

lon_col <- pick_column(
  audit,
  exact = c(
    "longitude",
    "lon",
    "LONGITUDE",
    "LONG"
  ),
  regex = c(
    "^longitude$",
    "^lon$",
    "sample.*lon"
  ),
  required = FALSE,
  label = "longitude field"
)

lat_col <- pick_column(
  audit,
  exact = c(
    "latitude",
    "lat",
    "LATITUDE"
  ),
  regex = c(
    "^latitude$",
    "^lat$",
    "sample.*lat"
  ),
  required = FALSE,
  label = "latitude field"
)

local_age_col <- pick_column(
  audit,
  exact = c(
    "local_age_mean_ma",
    "local_geo_age_mean_ma",
    "age_local_mean_ma"
  ),
  regex = c(
    "local.*age.*mean",
    "age.*local.*mean"
  ),
  required = FALSE,
  label = "local mean geological age"
)

upstream_age_col <- pick_column(
  audit,
  exact = c(
    "upstream_age_mean_ma",
    "up_geo_age_mean_ma",
    "age_upstream_mean_ma"
  ),
  regex = c(
    "upstream.*age.*mean",
    "up.*geo.*age.*mean",
    "age.*upstream.*mean"
  ),
  required = FALSE,
  label = "upstream mean geological age"
)

audit <- audit |>
  mutate(
    source_label = if (
      !is.na(source_col)
    ) {
      as.character(
        .data[[source_col]]
      )
    } else {
      NA_character_
    },

    longitude_std = if (
      !is.na(lon_col)
    ) {
      safe_numeric(
        .data[[lon_col]]
      )
    } else {
      NA_real_
    },

    latitude_std = if (
      !is.na(lat_col)
    ) {
      safe_numeric(
        .data[[lat_col]]
      )
    } else {
      NA_real_
    },

    local_age_mean_std = if (
      !is.na(local_age_col)
    ) {
      safe_numeric(
        .data[[local_age_col]]
      )
    } else {
      NA_real_
    },

    upstream_age_mean_std = if (
      !is.na(upstream_age_col)
    ) {
      safe_numeric(
        .data[[upstream_age_col]]
      )
    } else {
      NA_real_
    },

    local_minus_upstream_age = ifelse(
      is.finite(local_age_mean_std) &
        is.finite(upstream_age_mean_std),
      local_age_mean_std -
        upstream_age_mean_std,
      NA_real_
    )
  )


# ------------------------------------------------------------
# Write point-level audit tables
# ------------------------------------------------------------

write_csv(
  audit,
  file.path(
    out_dir,
    "p0_oof_failure_audit_all_rows.csv"
  )
)

write_csv(
  audit |>
    filter(
      observed >= 0.720
    ) |>
    arrange(
      algorithm,
      desc(underprediction_obs_minus_pred)
    ),
  file.path(
    out_dir,
    "p0_high_value_points_ge_0p720.csv"
  )
)

write_csv(
  audit |>
    filter(
      observed >= 0.750
    ) |>
    arrange(
      algorithm,
      desc(underprediction_obs_minus_pred)
    ),
  file.path(
    out_dir,
    "p0_high_value_points_ge_0p750.csv"
  )
)

write_csv(
  audit |>
    filter(
      observed >= 0.800
    ) |>
    arrange(
      algorithm,
      desc(underprediction_obs_minus_pred)
    ),
  file.path(
    out_dir,
    "p0_extreme_points_ge_0p800.csv"
  )
)

write_csv(
  audit |>
    arrange(
      desc(underprediction_obs_minus_pred)
    ) |>
    slice_head(
      n = 200
    ),
  file.path(
    out_dir,
    "top_200_underpredicted_oof_rows.csv"
  )
)


# ------------------------------------------------------------
# Summary metrics
# ------------------------------------------------------------

overall_summary <- audit |>
  group_by(
    algorithm
  ) |>
  group_modify(
    ~ summarise_metrics(.x)
  ) |>
  ungroup()

write_csv(
  overall_summary,
  file.path(
    out_dir,
    "overall_p0_oof_metrics.csv"
  )
)


thresholds <- c(
  0.720,
  0.750,
  0.800,
  0.900
)

threshold_summary <- lapply(
  thresholds,
  function(threshold_value) {
    audit |>
      filter(
        observed >= threshold_value
      ) |>
      group_by(
        algorithm
      ) |>
      group_modify(
        ~ summarise_metrics(.x)
      ) |>
      ungroup() |>
      mutate(
        threshold = threshold_value,
        .before = 1
      )
  }
) |>
  bind_rows()

write_csv(
  threshold_summary,
  file.path(
    out_dir,
    "metrics_by_high_value_threshold.csv"
  )
)


fold_summary <- audit |>
  filter(
    observed >= 0.720
  ) |>
  group_by(
    algorithm,
    outer_fold
  ) |>
  group_modify(
    ~ summarise_metrics(.x)
  ) |>
  ungroup()

write_csv(
  fold_summary,
  file.path(
    out_dir,
    "high_value_metrics_by_outer_fold.csv"
  )
)


fold_extreme_counts <- audit |>
  group_by(
    algorithm,
    outer_fold
  ) |>
  summarise(
    n_total = n(),

    n_ge_0p720 = sum(
      observed >= 0.720
    ),

    n_ge_0p750 = sum(
      observed >= 0.750
    ),

    n_ge_0p800 = sum(
      observed >= 0.800
    ),

    n_ge_0p900 = sum(
      observed >= 0.900
    ),

    max_observed = max(
      observed,
      na.rm = TRUE
    ),

    max_predicted = max(
      predicted,
      na.rm = TRUE
    ),

    .groups = "drop"
  )

write_csv(
  fold_extreme_counts,
  file.path(
    out_dir,
    "high_value_counts_by_outer_fold.csv"
  )
)


if (!all(is.na(audit$source_label))) {
  source_summary <- audit |>
    filter(
      !is.na(source_label),
      nzchar(source_label)
    ) |>
    group_by(
      algorithm,
      source_label
    ) |>
    summarise(
      n_total = n(),

      n_ge_0p720 = sum(
        observed >= 0.720
      ),

      n_ge_0p750 = sum(
        observed >= 0.750
      ),

      n_ge_0p800 = sum(
        observed >= 0.800
      ),

      mean_observed = mean(
        observed,
        na.rm = TRUE
      ),

      max_observed = max(
        observed,
        na.rm = TRUE
      ),

      mean_predicted = mean(
        predicted,
        na.rm = TRUE
      ),

      max_predicted = max(
        predicted,
        na.rm = TRUE
      ),

      mean_underprediction = mean(
        underprediction_obs_minus_pred,
        na.rm = TRUE
      ),

      high_mean_underprediction = ifelse(
        any(observed >= 0.720),
        mean(
          underprediction_obs_minus_pred[
            observed >= 0.720
          ],
          na.rm = TRUE
        ),
        NA_real_
      ),

      .groups = "drop"
    ) |>
    arrange(
      algorithm,
      desc(n_ge_0p800),
      desc(n_ge_0p750),
      desc(high_mean_underprediction)
    )

  write_csv(
    source_summary,
    file.path(
      out_dir,
      "failure_summary_by_source.csv"
    )
  )
}


# ------------------------------------------------------------
# Plot 1: observed versus OOF predicted
# ------------------------------------------------------------

plot_scatter <- ggplot(
  audit,
  aes(
    x = observed,
    y = predicted
  )
) +
  geom_point(
    aes(
      shape = extreme_ge_0p800
    ),
    alpha = 0.45,
    size = 1.4
  ) +
  geom_abline(
    slope = 1,
    intercept = 0,
    linewidth = 0.7,
    linetype = 2
  ) +
  geom_vline(
    xintercept = c(
      0.720,
      0.750,
      0.800
    ),
    linewidth = 0.35,
    linetype = 3
  ) +
  facet_wrap(
    ~ algorithm
  ) +
  labs(
    title = "P0 spatial OOF predictions",
    subtitle = paste(
      "Dashed line is 1:1;",
      "vertical lines mark 0.720, 0.750 and 0.800"
    ),
    x = expression(
      paste(
        "Observed ",
        {}^87,
        "Sr/",
        {}^86,
        "Sr"
      )
    ),
    y = expression(
      paste(
        "OOF-predicted ",
        {}^87,
        "Sr/",
        {}^86,
        "Sr"
      )
    ),
    shape = "Observed ≥ 0.800"
  ) +
  theme_bw(
    base_size = 11
  )

ggsave(
  filename = file.path(
    out_dir,
    "01_observed_vs_oof_predicted.png"
  ),
  plot = plot_scatter,
  width = 9,
  height = 5.5,
  dpi = 220
)


# ------------------------------------------------------------
# Plot 2: residual map, when coordinates are available
# ------------------------------------------------------------

map_data <- audit |>
  filter(
    is.finite(longitude_std),
    is.finite(latitude_std)
  )

if (nrow(map_data) > 0L) {
  plot_map <- ggplot(
    map_data,
    aes(
      x = longitude_std,
      y = latitude_std
    )
  ) +
    geom_point(
      aes(
        size = pmin(
          pmax(
            underprediction_obs_minus_pred,
            0
          ),
          0.15
        ),
        alpha = observed >= 0.720
      )
    ) +
    facet_wrap(
      ~ algorithm
    ) +
    coord_quickmap() +
    labs(
      title = "Spatial distribution of P0 underprediction",
      subtitle = paste(
        "Point size represents positive residual:",
        "observed minus OOF prediction"
      ),
      x = "Longitude",
      y = "Latitude",
      size = "Underprediction",
      alpha = "Observed ≥ 0.720"
    ) +
    theme_bw(
      base_size = 11
    )

  ggsave(
    filename = file.path(
      out_dir,
      "02_underprediction_map.png"
    ),
    plot = plot_map,
    width = 10,
    height = 5.8,
    dpi = 220
  )
}


# ------------------------------------------------------------
# Plot 3: residual by source
# ------------------------------------------------------------

if (!all(is.na(audit$source_label))) {
  top_sources <- audit |>
    filter(
      observed >= 0.720,
      !is.na(source_label),
      nzchar(source_label)
    ) |>
    count(
      source_label,
      sort = TRUE
    ) |>
    slice_head(
      n = 20
    ) |>
    pull(
      source_label
    )

  source_plot_data <- audit |>
    filter(
      observed >= 0.720,
      source_label %in% top_sources
    ) |>
    mutate(
      source_label = reorder(
        source_label,
        underprediction_obs_minus_pred,
        FUN = median,
        na.rm = TRUE
      )
    )

  if (nrow(source_plot_data) > 0L) {
    plot_source <- ggplot(
      source_plot_data,
      aes(
        x = source_label,
        y = underprediction_obs_minus_pred
      )
    ) +
      geom_hline(
        yintercept = 0,
        linewidth = 0.5,
        linetype = 2
      ) +
      geom_boxplot(
        outlier.shape = NA
      ) +
      geom_jitter(
        width = 0.15,
        alpha = 0.45,
        size = 1.1
      ) +
      facet_wrap(
        ~ algorithm,
        scales = "free_y"
      ) +
      coord_flip() +
      labs(
        title = "High-value underprediction by source",
        subtitle = "Observed values ≥ 0.720",
        x = NULL,
        y = "Observed − OOF prediction"
      ) +
      theme_bw(
        base_size = 10
      )

    ggsave(
      filename = file.path(
        out_dir,
        "03_high_value_residual_by_source.png"
      ),
      plot = plot_source,
      width = 10,
      height = 9,
      dpi = 220
    )
  }
}


# ------------------------------------------------------------
# Plot 4: age versus residual
# ------------------------------------------------------------

age_plot_data <- audit |>
  filter(
    observed >= 0.720
  ) |>
  select(
    algorithm,
    observed,
    predicted,
    underprediction_obs_minus_pred,
    local_age_mean_std,
    upstream_age_mean_std,
    local_minus_upstream_age
  ) |>
  pivot_longer(
    cols = c(
      local_age_mean_std,
      upstream_age_mean_std,
      local_minus_upstream_age
    ),
    names_to = "age_variable",
    values_to = "age_value"
  ) |>
  filter(
    is.finite(age_value),
    is.finite(underprediction_obs_minus_pred)
  )

if (nrow(age_plot_data) > 0L) {
  plot_age <- ggplot(
    age_plot_data,
    aes(
      x = age_value,
      y = underprediction_obs_minus_pred
    )
  ) +
    geom_hline(
      yintercept = 0,
      linewidth = 0.5,
      linetype = 2
    ) +
    geom_point(
      alpha = 0.4,
      size = 1.2
    ) +
    geom_smooth(
      method = "lm",
      formula = y ~ x,
      se = TRUE,
      linewidth = 0.7
    ) +
    facet_grid(
      algorithm ~ age_variable,
      scales = "free_x"
    ) +
    labs(
      title = "Geological age and high-value underprediction",
      subtitle = "P0 OOF residuals for observed values ≥ 0.720",
      x = "Geological-age variable",
      y = "Observed − OOF prediction"
    ) +
    theme_bw(
      base_size = 10
    )

  ggsave(
    filename = file.path(
      out_dir,
      "04_age_vs_high_value_underprediction.png"
    ),
    plot = plot_age,
    width = 12,
    height = 7,
    dpi = 220
  )
}


# ------------------------------------------------------------
# Manifest
# ------------------------------------------------------------

manifest <- c(
  paste0(
    "Model table rows: ",
    nrow(model)
  ),

  paste0(
    "OOF rows before P0 filtering: ",
    nrow(oof)
  ),

  paste0(
    "P0 audit rows: ",
    nrow(audit)
  ),

  paste0(
    "Algorithms: ",
    paste(
      sort(unique(audit$algorithm)),
      collapse = ", "
    )
  ),

  paste0(
    "Rows observed >= 0.720: ",
    sum(audit$observed >= 0.720)
  ),

  paste0(
    "Rows observed >= 0.750: ",
    sum(audit$observed >= 0.750)
  ),

  paste0(
    "Rows observed >= 0.800: ",
    sum(audit$observed >= 0.800)
  ),

  paste0(
    "Rows observed >= 0.900: ",
    sum(audit$observed >= 0.900)
  ),

  paste0(
    "Detected source column: ",
    ifelse(
      is.na(source_col),
      "NONE",
      source_col
    )
  ),

  paste0(
    "Detected longitude column: ",
    ifelse(
      is.na(lon_col),
      "NONE",
      lon_col
    )
  ),

  paste0(
    "Detected latitude column: ",
    ifelse(
      is.na(lat_col),
      "NONE",
      lat_col
    )
  ),

  paste0(
    "Detected local-age column: ",
    ifelse(
      is.na(local_age_col),
      "NONE",
      local_age_col
    )
  ),

  paste0(
    "Detected upstream-age column: ",
    ifelse(
      is.na(upstream_age_col),
      "NONE",
      upstream_age_col
    )
  )
)

writeLines(
  manifest,
  con = file.path(
    out_dir,
    "audit_manifest.txt"
  )
)


# ------------------------------------------------------------
# Console output
# ------------------------------------------------------------

cat(
  "\n===== AUDIT MANIFEST =====\n"
)

cat(
  paste(
    manifest,
    collapse = "\n"
  ),
  "\n"
)

cat(
  "\n===== METRICS BY HIGH-VALUE THRESHOLD =====\n"
)

print(
  threshold_summary,
  n = Inf,
  width = Inf
)

cat(
  "\n===== HIGH-VALUE METRICS BY OUTER FOLD =====\n"
)

print(
  fold_summary,
  n = Inf,
  width = Inf
)

cat(
  "\nHIGH-VALUE FAILURE AUDIT COMPLETE\n"
)

cat(
  "Outputs written to:\n",
  normalizePath(
    out_dir,
    mustWork = TRUE
  ),
  "\n"
)
