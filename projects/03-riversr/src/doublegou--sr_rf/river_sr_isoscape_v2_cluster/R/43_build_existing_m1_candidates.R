suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

# ============================================================
# 0. Paths
# ============================================================

p0_file <-
  "data/processed/model_table_p0_full_range.rds"

age_file <-
  "data/processed/model_table_age_test.rds"

out_file <-
  "data/processed/model_table_m1_existing_candidates.rds"

out_dir <-
  "outputs/m1_existing_candidate_audit"

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

# ============================================================
# 1. Read data
# ============================================================

p0 <- readRDS(
  p0_file
)

age <- readRDS(
  age_file
)

if (!"row_id" %in% names(p0)) {
  stop("row_id missing from P0 table.")
}

if (!"row_id" %in% names(age)) {
  stop("row_id missing from age table.")
}

if (anyDuplicated(p0$row_id)) {
  stop("Duplicated row_id in P0 table.")
}

if (anyDuplicated(age$row_id)) {
  stop("Duplicated row_id in age table.")
}

cat(
  "\n===== INPUT =====\n"
)

cat(
  "P0 rows: ",
  nrow(p0),
  "\n",
  sep = ""
)

cat(
  "Age rows: ",
  nrow(age),
  "\n",
  sep = ""
)

# ============================================================
# 2. Identify 8 lithology fractions
# ============================================================

lith_vars <- c(
  "p0__up_geo_unconsolidated_frac",
  "p0__up_geo_siliciclastic_frac",
  "p0__up_geo_mixed_sedimentary_frac",
  "p0__up_geo_carbonate_frac",
  "p0__up_geo_metamorphic_frac",
  "p0__up_geo_plutonic_frac",
  "p0__up_geo_volcanic_frac",
  "p0__up_geo_evaporite_frac"
)

missing_lith <- setdiff(
  lith_vars,
  names(p0)
)

if (length(missing_lith) > 0L) {
  stop(
    "Missing lithology variables: ",
    paste(
      missing_lith,
      collapse = ", "
    )
  )
}

# ============================================================
# 3. Derive lithological heterogeneity
# ============================================================

lith_mat <- as.matrix(
  p0[
    ,
    lith_vars,
    drop = FALSE
  ]
)

storage.mode(lith_mat) <-
  "numeric"

row_total <- rowSums(
  lith_mat,
  na.rm = FALSE
)

# Normalize fractions to sum to 1.
# This protects against tiny rounding deviations.

p_mat <- lith_mat /
  row_total

shannon_entropy <- apply(
  p_mat,
  1,
  function(p) {

    p <- p[
      is.finite(p) &
      p > 0
    ]

    if (length(p) == 0L) {
      return(NA_real_)
    }

    -sum(
      p * log(p)
    )
  }
)

normalized_entropy <-
  shannon_entropy /
  log(
    length(lith_vars)
  )

dominant_fraction <- apply(
  p_mat,
  1,
  function(p) {

    if (
      all(
        !is.finite(p)
      )
    ) {
      return(NA_real_)
    }

    max(
      p,
      na.rm = TRUE
    )
  }
)

effective_lithologies <-
  exp(
    shannon_entropy
  )

simpson_diversity <- apply(
  p_mat,
  1,
  function(p) {

    p <- p[
      is.finite(p)
    ]

    if (length(p) == 0L) {
      return(NA_real_)
    }

    1 -
      sum(
        p^2
      )
  }
)

p0 <- p0 |>
  mutate(
    m1a__lith_entropy =
      shannon_entropy,

    m1a__lith_entropy_norm =
      normalized_entropy,

    m1a__lith_dominant_frac =
      dominant_fraction,

    m1a__lith_effective_n =
      effective_lithologies,

    m1a__lith_simpson =
      simpson_diversity
  )

# ============================================================
# 4. Select age variables
# ============================================================

age_vars <- c(
  "row_id",

  "local_geo_age_mean_ma",
  "local_geo_age_sd_ma",
  "local_geo_age_max_oldest_ma",

  "up_geo_age_mean_ma",
  "up_geo_age_sd_ma",
  "up_geo_age_max_oldest_ma",

  "local_minus_up_geo_age_mean_ma",

  "local_geo_age_resolved_coverage",
  "up_geo_age_resolved_coverage",
  "up_geo_age_quality_tier"
)

missing_age <- setdiff(
  age_vars,
  names(age)
)

if (length(missing_age) > 0L) {
  stop(
    "Missing age variables: ",
    paste(
      missing_age,
      collapse = ", "
    )
  )
}

age_small <- age |>
  select(
    all_of(
      age_vars
    )
  )

# ============================================================
# 5. Join age onto full-range P0
# ============================================================

dat <- p0 |>
  left_join(
    age_small,
    by = "row_id"
  )

if (nrow(dat) != nrow(p0)) {
  stop(
    "Row count changed after age join."
  )
}

# ============================================================
# 6. Additional mechanistic age contrasts
# ============================================================

dat <- dat |>
  mutate(

    m1b__age_mean_local_minus_up =
      local_geo_age_mean_ma -
      up_geo_age_mean_ma,

    m1b__age_mean_abs_contrast =
      abs(
        local_geo_age_mean_ma -
        up_geo_age_mean_ma
      ),

    m1b__age_sd_local_minus_up =
      local_geo_age_sd_ma -
      up_geo_age_sd_ma,

    m1b__age_sd_abs_contrast =
      abs(
        local_geo_age_sd_ma -
        up_geo_age_sd_ma
      ),

    m1a__age_max_local_minus_up =
      local_geo_age_max_oldest_ma -
      up_geo_age_max_oldest_ma,

    m1a__age_max_abs_contrast =
      abs(
        local_geo_age_max_oldest_ma -
        up_geo_age_max_oldest_ma
      )
  )

# Check existing contrast agrees with recomputed one.

contrast_diff <- abs(
  dat$local_minus_up_geo_age_mean_ma -
    dat$m1b__age_mean_local_minus_up
)

cat(
  "\n===== AGE CONTRAST VALIDATION =====\n"
)

cat(
  "Max abs difference: ",
  max(
    contrast_diff,
    na.rm = TRUE
  ),
  "\n",
  sep = ""
)

# ============================================================
# 7. Define candidate groups
# ============================================================

m1_lith <- c(
  "m1a__lith_entropy_norm",
  "m1a__lith_dominant_frac"
)

m1_age_distribution <- c(
  "local_geo_age_mean_ma",
  "local_geo_age_sd_ma",
  "local_geo_age_max_oldest_ma",
  "up_geo_age_mean_ma",
  "up_geo_age_sd_ma",
  "up_geo_age_max_oldest_ma"
)

m1_age_contrast <- c(
  "m1b__age_mean_local_minus_up",
  "m1b__age_mean_abs_contrast",
  "m1b__age_sd_local_minus_up",
  "m1b__age_sd_abs_contrast",
  "m1a__age_max_local_minus_up",
  "m1a__age_max_abs_contrast"
)

candidate_vars <- c(
  m1_lith,
  m1_age_distribution,
  m1_age_contrast
)

# ============================================================
# 8. Missingness audit
# ============================================================

missing_summary <- bind_rows(
  lapply(
    candidate_vars,
    function(v) {

      x <- dat[[v]]

      data.frame(
        variable = v,

        n_nonmissing =
          sum(
            is.finite(x)
          ),

        n_missing =
          sum(
            !is.finite(x)
          ),

        pct_missing =
          100 *
          mean(
            !is.finite(x)
          ),

        min =
          if (
            any(
              is.finite(x)
            )
          )
            min(
              x,
              na.rm = TRUE
            )
          else
            NA_real_,

        median =
          if (
            any(
              is.finite(x)
            )
          )
            median(
              x,
              na.rm = TRUE
            )
          else
            NA_real_,

        max =
          if (
            any(
              is.finite(x)
            )
          )
            max(
              x,
              na.rm = TRUE
            )
          else
            NA_real_
      )
    }
  )
)

write_csv(
  missing_summary,
  file.path(
    out_dir,
    "candidate_missingness.csv"
  )
)

# ============================================================
# 9. Age coverage audit
# ============================================================

coverage_summary <- data.frame(

  metric = c(
    "local_age_coverage",
    "upstream_age_coverage"
  ),

  n_nonmissing = c(
    sum(
      is.finite(
        dat$local_geo_age_resolved_coverage
      )
    ),

    sum(
      is.finite(
        dat$up_geo_age_resolved_coverage
      )
    )
  ),

  median = c(
    median(
      dat$local_geo_age_resolved_coverage,
      na.rm = TRUE
    ),

    median(
      dat$up_geo_age_resolved_coverage,
      na.rm = TRUE
    )
  ),

  p05 = c(
    quantile(
      dat$local_geo_age_resolved_coverage,
      0.05,
      na.rm = TRUE
    ),

    quantile(
      dat$up_geo_age_resolved_coverage,
      0.05,
      na.rm = TRUE
    )
  ),

  p25 = c(
    quantile(
      dat$local_geo_age_resolved_coverage,
      0.25,
      na.rm = TRUE
    ),

    quantile(
      dat$up_geo_age_resolved_coverage,
      0.25,
      na.rm = TRUE
    )
  ),

  p75 = c(
    quantile(
      dat$local_geo_age_resolved_coverage,
      0.75,
      na.rm = TRUE
    ),

    quantile(
      dat$up_geo_age_resolved_coverage,
      0.75,
      na.rm = TRUE
    )
  ),

  p95 = c(
    quantile(
      dat$local_geo_age_resolved_coverage,
      0.95,
      na.rm = TRUE
    ),

    quantile(
      dat$up_geo_age_resolved_coverage,
      0.95,
      na.rm = TRUE
    )
  )
)

write_csv(
  coverage_summary,
  file.path(
    out_dir,
    "age_coverage_summary.csv"
  )
)

# ============================================================
# 10. Complete-case counts
# ============================================================

p0_vars <- grep(
  "^p0__",
  names(dat),
  value = TRUE
)

stopifnot(
  length(p0_vars) == 28L
)

complete_p0 <-
  complete.cases(
    dat[
      ,
      p0_vars,
      drop = FALSE
    ]
  )

complete_lith <-
  complete.cases(
    dat[
      ,
      c(
        p0_vars,
        m1_lith
      ),
      drop = FALSE
    ]
  )

complete_age <-
  complete.cases(
    dat[
      ,
      c(
        p0_vars,
        m1_age_distribution
      ),
      drop = FALSE
    ]
  )

complete_contrast <-
  complete.cases(
    dat[
      ,
      c(
        p0_vars,
        m1_age_contrast
      ),
      drop = FALSE
    ]
  )

complete_all <-
  complete.cases(
    dat[
      ,
      c(
        p0_vars,
        candidate_vars
      ),
      drop = FALSE
    ]
  )

sample_summary <- data.frame(

  predictor_set = c(
    "M0_P0",
    "M1_lith",
    "M1_age_distribution",
    "M1_age_contrast",
    "M1_existing_all"
  ),

  n_complete = c(
    sum(complete_p0),
    sum(complete_lith),
    sum(complete_age),
    sum(complete_contrast),
    sum(complete_all)
  )
)

if ("sr87_sr86" %in% names(dat)) {

  sample_summary$n_ge_075 <- c(
    sum(
      complete_p0 &
        dat$sr87_sr86 >= 0.750,
      na.rm = TRUE
    ),

    sum(
      complete_lith &
        dat$sr87_sr86 >= 0.750,
      na.rm = TRUE
    ),

    sum(
      complete_age &
        dat$sr87_sr86 >= 0.750,
      na.rm = TRUE
    ),

    sum(
      complete_contrast &
        dat$sr87_sr86 >= 0.750,
      na.rm = TRUE
    ),

    sum(
      complete_all &
        dat$sr87_sr86 >= 0.750,
      na.rm = TRUE
    )
  )

  sample_summary$n_ge_080 <- c(
    sum(
      complete_p0 &
        dat$sr87_sr86 >= 0.800,
      na.rm = TRUE
    ),

    sum(
      complete_lith &
        dat$sr87_sr86 >= 0.800,
      na.rm = TRUE
    ),

    sum(
      complete_age &
        dat$sr87_sr86 >= 0.800,
      na.rm = TRUE
    ),

    sum(
      complete_contrast &
        dat$sr87_sr86 >= 0.800,
      na.rm = TRUE
    ),

    sum(
      complete_all &
        dat$sr87_sr86 >= 0.800,
      na.rm = TRUE
    )
  )
}

write_csv(
  sample_summary,
  file.path(
    out_dir,
    "candidate_complete_case_summary.csv"
  )
)

# ============================================================
# 11. Correlation audit
# ============================================================

corr_vars <- candidate_vars

corr_dat <- dat[
  ,
  corr_vars,
  drop = FALSE
]

corr_mat <- cor(
  corr_dat,
  use = "pairwise.complete.obs",
  method = "spearman"
)

write.csv(
  corr_mat,
  file.path(
    out_dir,
    "candidate_spearman_correlation.csv"
  ),
  row.names = TRUE
)

high_corr <- which(
  abs(corr_mat) >= 0.90 &
    abs(corr_mat) < 0.999999,
  arr.ind = TRUE
)

if (nrow(high_corr) > 0L) {

  high_corr_table <- data.frame(
    variable_1 =
      rownames(corr_mat)[
        high_corr[, 1]
      ],

    variable_2 =
      colnames(corr_mat)[
        high_corr[, 2]
      ],

    spearman_r =
      corr_mat[
        high_corr
      ]
  ) |>
    filter(
      variable_1 < variable_2
    ) |>
    arrange(
      desc(
        abs(
          spearman_r
        )
      )
    )

} else {

  high_corr_table <- data.frame(
    variable_1 = character(0),
    variable_2 = character(0),
    spearman_r = numeric(0)
  )
}

write_csv(
  high_corr_table,
  file.path(
    out_dir,
    "high_correlation_pairs.csv"
  )
)

# ============================================================
# 12. Save table
# ============================================================

saveRDS(
  dat,
  out_file
)

# ============================================================
# 13. Terminal output
# ============================================================

cat(
  "\n===== COMPLETE-CASE SUMMARY =====\n"
)

print(
  sample_summary,
  row.names = FALSE
)

cat(
  "\n===== CANDIDATE MISSINGNESS =====\n"
)

print(
  missing_summary,
  row.names = FALSE
)

cat(
  "\n===== AGE COVERAGE =====\n"
)

print(
  coverage_summary,
  row.names = FALSE
)

cat(
  "\n===== HIGH CORRELATION PAIRS |r| >= 0.90 =====\n"
)

print(
  high_corr_table,
  row.names = FALSE
)

cat(
  "\n===== SAVED =====\n"
)

cat(
  out_file,
  "\n"
)

cat(
  "\n===== DONE =====\n"
)
