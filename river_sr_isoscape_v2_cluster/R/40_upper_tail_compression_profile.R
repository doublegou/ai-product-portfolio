suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(ggplot2)
})

infile <- "outputs/experiment_p0_full_range_1500/oof_predictions.rds"
out_dir <- "outputs/experiment_p0_full_range_1500/upper_tail_profile"

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

pred <- readRDS(infile) |>
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

# ============================================================
# 1. Fixed observed-Sr bins
# ============================================================

breaks <- c(
  0.700,
  0.710,
  0.720,
  0.730,
  0.740,
  0.750,
  0.775,
  0.800,
  0.900,
  Inf
)

labels <- c(
  "0.700-0.710",
  "0.710-0.720",
  "0.720-0.730",
  "0.730-0.740",
  "0.740-0.750",
  "0.750-0.775",
  "0.775-0.800",
  "0.800-0.900",
  ">=0.900"
)

pred <- pred |>
  mutate(
    sr_bin = cut(
      observed,
      breaks = breaks,
      labels = labels,
      right = FALSE,
      include.lowest = TRUE
    )
  )

bin_profile <- pred |>
  filter(!is.na(sr_bin)) |>
  group_by(
    algorithm,
    sr_bin
  ) |>
  summarise(
    n = n(),

    observed_mean =
      mean(observed),

    observed_sd =
      sd(observed),

    observed_min =
      min(observed),

    observed_max =
      max(observed),

    predicted_mean =
      mean(predicted),

    predicted_sd =
      sd(predicted),

    predicted_min =
      min(predicted),

    predicted_max =
      max(predicted),

    bias =
      mean(predicted - observed),

    median_bias =
      median(predicted - observed),

    mae =
      mean(abs(predicted - observed)),

    rmse =
      sqrt(
        mean(
          (predicted - observed)^2
        )
      ),

    .groups = "drop"
  ) |>
  mutate(
    sd_compression_ratio =
      ifelse(
        is.finite(observed_sd) &
          observed_sd > 0,
        predicted_sd / observed_sd,
        NA_real_
      )
  )

write_csv(
  bin_profile,
  file.path(
    out_dir,
    "sr_bin_performance.csv"
  )
)

cat(
  "\n===== BIN PROFILE =====\n"
)

print(
  bin_profile,
  n = Inf,
  width = Inf
)

# ============================================================
# 2. Cumulative upper-tail profile
# ============================================================

thresholds <- c(
  0.720,
  0.730,
  0.740,
  0.750,
  0.775,
  0.800,
  0.900
)

tail_list <- list()

for (alg in unique(pred$algorithm)) {

  d_alg <- pred |>
    filter(
      algorithm == alg
    )

  for (thr in thresholds) {

    z <- d_alg |>
      filter(
        observed >= thr
      )

    if (nrow(z) == 0L) {
      next
    }

    tail_list[[length(tail_list) + 1L]] <-
      data.frame(
        algorithm = alg,
        threshold = thr,
        n = nrow(z),

        observed_mean =
          mean(z$observed),

        predicted_mean =
          mean(z$predicted),

        rmse =
          sqrt(
            mean(
              (z$predicted - z$observed)^2
            )
          ),

        mae =
          mean(
            abs(
              z$predicted - z$observed
            )
          ),

        bias =
          mean(
            z$predicted - z$observed
          ),

        median_bias =
          median(
            z$predicted - z$observed
          ),

        observed_max =
          max(z$observed),

        predicted_max =
          max(z$predicted)
      )
  }
}

tail_profile <- bind_rows(
  tail_list
)

write_csv(
  tail_profile,
  file.path(
    out_dir,
    "cumulative_tail_performance.csv"
  )
)

cat(
  "\n===== CUMULATIVE TAIL PROFILE =====\n"
)

print(
  tail_profile,
  row.names = FALSE
)

# ============================================================
# 3. Plot: mean observed vs mean predicted by bin
# ============================================================

p1 <- ggplot(
  bin_profile,
  aes(
    x = observed_mean,
    y = predicted_mean
  )
) +
  geom_point(
    size = 2.5
  ) +
  geom_line(
    aes(
      group = algorithm
    )
  ) +
  geom_abline(
    slope = 1,
    intercept = 0,
    linetype = 2
  ) +
  facet_wrap(
    ~algorithm
  ) +
  labs(
    title =
      "Mean Observed vs Mean Predicted by Sr Bin",

    subtitle =
      "OOF predictions | spatial 1500-km block CV",

    x =
      "Mean observed 87Sr/86Sr",

    y =
      "Mean predicted 87Sr/86Sr"
  ) +
  theme_bw(
    base_size = 13
  )

ggsave(
  file.path(
    out_dir,
    "01_bin_mean_observed_vs_predicted.png"
  ),
  p1,
  width = 10,
  height = 5.5,
  dpi = 300
)

# ============================================================
# 4. Plot: bias by observed-Sr bin
# ============================================================

p2 <- ggplot(
  bin_profile,
  aes(
    x = observed_mean,
    y = bias
  )
) +
  geom_hline(
    yintercept = 0,
    linetype = 2
  ) +
  geom_point(
    size = 2.5
  ) +
  geom_line(
    aes(
      group = algorithm
    )
  ) +
  facet_wrap(
    ~algorithm
  ) +
  labs(
    title =
      "Prediction Bias across Observed Sr",

    subtitle =
      "Bias = predicted - observed",

    x =
      "Mean observed 87Sr/86Sr",

    y =
      "Mean bias"
  ) +
  theme_bw(
    base_size = 13
  )

ggsave(
  file.path(
    out_dir,
    "02_bias_by_sr_bin.png"
  ),
  p2,
  width = 10,
  height = 5.5,
  dpi = 300
)

# ============================================================
# 5. Plot: RMSE by observed-Sr bin
# ============================================================

p3 <- ggplot(
  bin_profile,
  aes(
    x = observed_mean,
    y = rmse
  )
) +
  geom_point(
    size = 2.5
  ) +
  geom_line(
    aes(
      group = algorithm
    )
  ) +
  facet_wrap(
    ~algorithm
  ) +
  labs(
    title =
      "RMSE across Observed Sr",

    x =
      "Mean observed 87Sr/86Sr",

    y =
      "RMSE"
  ) +
  theme_bw(
    base_size = 13
  )

ggsave(
  file.path(
    out_dir,
    "03_rmse_by_sr_bin.png"
  ),
  p3,
  width = 10,
  height = 5.5,
  dpi = 300
)

cat(
  "\n===== DONE =====\n"
)

cat(
  "Saved to: ",
  out_dir,
  "\n",
  sep = ""
)
