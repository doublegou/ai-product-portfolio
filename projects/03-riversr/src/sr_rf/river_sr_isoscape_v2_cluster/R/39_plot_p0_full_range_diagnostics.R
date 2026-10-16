suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(ggplot2)
})

infile <- "outputs/experiment_p0_full_range_1500/oof_predictions.rds"
out_dir <- "outputs/experiment_p0_full_range_1500/diagnostic_plots"

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

pred <- readRDS(infile)

pred <- pred |>
  filter(
    scheme == "spatial_1500km",
    predictor_set == "P0_FULL",
    is.finite(observed),
    is.finite(predicted)
  ) |>
  mutate(
    residual = predicted - observed,
    abs_error = abs(residual)
  )

cat("\n===== DATA =====\n")
print(
  pred |>
    count(algorithm)
)

# ============================================================
# Metric function
# ============================================================

metric_fn <- function(x) {

  data.frame(
    n = nrow(x),

    observed_min =
      min(x$observed),

    observed_max =
      max(x$observed),

    predicted_min =
      min(x$predicted),

    predicted_max =
      max(x$predicted),

    rmse =
      sqrt(
        mean(
          (x$predicted - x$observed)^2
        )
      ),

    mae =
      mean(
        abs(
          x$predicted - x$observed
        )
      ),

    bias =
      mean(
        x$predicted - x$observed
      ),

    median_bias =
      median(
        x$predicted - x$observed
      )
  )
}

summaries <- bind_rows(

  pred |>
    group_by(algorithm) |>
    group_modify(
      ~metric_fn(.x)
    ) |>
    mutate(
      sample = "all"
    ),

  pred |>
    filter(
      observed < 0.800
    ) |>
    group_by(algorithm) |>
    group_modify(
      ~metric_fn(.x)
    ) |>
    mutate(
      sample = "observed_lt_0p800"
    ),

  pred |>
    filter(
      observed >= 0.800
    ) |>
    group_by(algorithm) |>
    group_modify(
      ~metric_fn(.x)
    ) |>
    mutate(
      sample = "observed_ge_0p800"
    )

) |>
  ungroup()

write_csv(
  summaries,
  file.path(
    out_dir,
    "diagnostic_metrics_summary.csv"
  )
)

cat("\n===== METRIC SUMMARY =====\n")
print(
  summaries,
  row.names = FALSE
)

# ============================================================
# Common theme
# ============================================================

theme_sr <- theme_bw(
  base_size = 13
) +
  theme(
    panel.grid.minor =
      element_blank(),

    plot.title =
      element_text(
        face = "bold"
      )
  )

# ============================================================
# FIGURE 1
# ALL DATA
# ============================================================

all_lim <- range(
  c(
    pred$observed,
    pred$predicted
  ),
  na.rm = TRUE
)

p1 <- ggplot(
  pred,
  aes(
    observed,
    predicted
  )
) +
  geom_point(
    alpha = 0.30,
    size = 1.2
  ) +
  geom_abline(
    slope = 1,
    intercept = 0,
    linetype = 2
  ) +
  facet_wrap(
    ~algorithm
  ) +
  coord_equal(
    xlim = all_lim,
    ylim = all_lim
  ) +
  labs(
    title =
      "Observed vs Predicted — Full Dataset",

    subtitle =
      "OOF predictions | spatial 1500-km block CV",

    x =
      "Observed 87Sr/86Sr",

    y =
      "Predicted 87Sr/86Sr"
  ) +
  theme_sr

ggsave(
  file.path(
    out_dir,
    "01_observed_vs_predicted_ALL.png"
  ),
  p1,
  width = 10,
  height = 5.5,
  dpi = 300
)

# ============================================================
# FIGURE 2
# EXCLUDE >= 0.800
# ============================================================

main <- pred |>
  filter(
    observed < 0.800
  )

main_lim <- range(
  c(
    main$observed,
    main$predicted
  ),
  na.rm = TRUE
)

p2 <- ggplot(
  main,
  aes(
    observed,
    predicted
  )
) +
  geom_point(
    alpha = 0.30,
    size = 1.2
  ) +
  geom_abline(
    slope = 1,
    intercept = 0,
    linetype = 2
  ) +
  facet_wrap(
    ~algorithm
  ) +
  coord_equal(
    xlim = main_lim,
    ylim = main_lim
  ) +
  labs(
    title =
      "Observed vs Predicted — Observed < 0.800",

    subtitle =
      "Extreme radiogenic tail removed",

    x =
      "Observed 87Sr/86Sr",

    y =
      "Predicted 87Sr/86Sr"
  ) +
  theme_sr

ggsave(
  file.path(
    out_dir,
    "02_observed_vs_predicted_LT0800.png"
  ),
  p2,
  width = 10,
  height = 5.5,
  dpi = 300
)

# ============================================================
# FIGURE 3
# ALSO ZOOM TO < 0.750
# ============================================================

main75 <- pred |>
  filter(
    observed < 0.750
  )

lim75 <- range(
  c(
    main75$observed,
    main75$predicted
  ),
  na.rm = TRUE
)

p3 <- ggplot(
  main75,
  aes(
    observed,
    predicted
  )
) +
  geom_point(
    alpha = 0.30,
    size = 1.2
  ) +
  geom_abline(
    slope = 1,
    intercept = 0,
    linetype = 2
  ) +
  facet_wrap(
    ~algorithm
  ) +
  coord_equal(
    xlim = lim75,
    ylim = lim75
  ) +
  labs(
    title =
      "Observed vs Predicted — Observed < 0.750",

    subtitle =
      "Zoom on the main body of the distribution",

    x =
      "Observed 87Sr/86Sr",

    y =
      "Predicted 87Sr/86Sr"
  ) +
  theme_sr

ggsave(
  file.path(
    out_dir,
    "03_observed_vs_predicted_LT0750.png"
  ),
  p3,
  width = 10,
  height = 5.5,
  dpi = 300
)

# ============================================================
# FIGURE 4
# EXTREME >= 0.800
# ============================================================

extreme <- pred |>
  filter(
    observed >= 0.800
  )

extreme_lim <- range(
  c(
    extreme$observed,
    extreme$predicted
  ),
  na.rm = TRUE
)

p4 <- ggplot(
  extreme,
  aes(
    observed,
    predicted
  )
) +
  geom_point(
    alpha = 0.85,
    size = 2
  ) +
  geom_abline(
    slope = 1,
    intercept = 0,
    linetype = 2
  ) +
  facet_wrap(
    ~algorithm
  ) +
  coord_equal(
    xlim = extreme_lim,
    ylim = extreme_lim
  ) +
  labs(
    title =
      "Observed vs Predicted — Extreme Tail",

    subtitle =
      "Observed >= 0.800",

    x =
      "Observed 87Sr/86Sr",

    y =
      "Predicted 87Sr/86Sr"
  ) +
  theme_sr

ggsave(
  file.path(
    out_dir,
    "04_observed_vs_predicted_GE0800.png"
  ),
  p4,
  width = 10,
  height = 5.5,
  dpi = 300
)

# ============================================================
# FIGURE 5
# RESIDUAL VS OBSERVED
# ============================================================

p5 <- ggplot(
  pred,
  aes(
    observed,
    residual
  )
) +
  geom_point(
    alpha = 0.30,
    size = 1.2
  ) +
  geom_hline(
    yintercept = 0,
    linetype = 2
  ) +
  geom_smooth(
    method = "loess",
    se = FALSE
  ) +
  facet_wrap(
    ~algorithm
  ) +
  labs(
    title =
      "Residual vs Observed",

    subtitle =
      "Residual = predicted - observed",

    x =
      "Observed 87Sr/86Sr",

    y =
      "Residual"
  ) +
  theme_sr

ggsave(
  file.path(
    out_dir,
    "05_residual_vs_observed.png"
  ),
  p5,
  width = 10,
  height = 5.5,
  dpi = 300
)

# ============================================================
# FIGURE 6
# ABSOLUTE ERROR
# ============================================================

p6 <- ggplot(
  pred,
  aes(
    observed,
    abs_error
  )
) +
  geom_point(
    alpha = 0.30,
    size = 1.2
  ) +
  geom_smooth(
    method = "loess",
    se = FALSE
  ) +
  facet_wrap(
    ~algorithm
  ) +
  labs(
    title =
      "Absolute Error vs Observed",

    x =
      "Observed 87Sr/86Sr",

    y =
      "Absolute error"
  ) +
  theme_sr

ggsave(
  file.path(
    out_dir,
    "06_absolute_error_vs_observed.png"
  ),
  p6,
  width = 10,
  height = 5.5,
  dpi = 300
)

cat("\n===== DONE =====\n")
cat("Plots saved in:\n")
cat(out_dir, "\n")

print(
  list.files(
    out_dir,
    pattern = "\\.png$"
  )
)
