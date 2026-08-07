source("R/functions/core.R")

check_packages(
  c(
    "dplyr",
    "readr",
    "tibble",
    "tidyr"
  )
)

root <- project_root()

input_dir <- file.path(
  root,
  "outputs",
  "r50b_feature_architecture"
)

out_dir <- file.path(
  root,
  "outputs",
  "r51a_validation_design"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

model_table_file <- file.path(
  input_dir,
  "integrated_model_table.rds"
)

feature_sets_file <- file.path(
  input_dir,
  "model_feature_sets.rds"
)

if (!file.exists(model_table_file)) {
  stop(
    "Missing integrated model table: ",
    model_table_file
  )
}

if (!file.exists(feature_sets_file)) {
  stop(
    "Missing model feature sets: ",
    feature_sets_file
  )
}

dat <- as.data.frame(
  readRDS(model_table_file)
)

feature_sets <- readRDS(
  feature_sets_file
)

required_columns <- c(
  "row_id",
  "site_id",
  "longitude",
  "latitude",
  "sr87_sr86",
  "geological_regime_primary"
)

missing_required <- setdiff(
  required_columns,
  names(dat)
)

if (length(missing_required) > 0L) {
  stop(
    "Integrated table lacks required columns: ",
    paste(
      missing_required,
      collapse = ", "
    )
  )
}

if (nrow(dat) != 4485L) {
  stop(
    "Expected 4485 rows; found ",
    nrow(dat)
  )
}

dat$row_id <- as.character(
  dat$row_id
)

if (anyDuplicated(dat$row_id)) {
  stop(
    "row_id is not unique."
  )
}

if (
  anyNA(dat$longitude) ||
  anyNA(dat$latitude) ||
  anyNA(dat$sr87_sr86)
) {
  stop(
    "Coordinates or outcome contain missing values."
  )
}

expected_model_sizes <- c(
  M0_P0_FULL = 28L,
  M_CORE_MECHANISTIC = 42L,
  M_FULL_MECHANISTIC = 50L
)

observed_model_sizes <- vapply(
  names(expected_model_sizes),
  function(model_name) {
    length(
      feature_sets[[model_name]]
    )
  },
  integer(1)
)

if (!identical(
  observed_model_sizes,
  expected_model_sizes
)) {
  stop(
    "Frozen feature-set sizes changed. Observed: ",
    paste(
      names(observed_model_sizes),
      observed_model_sizes,
      collapse = "; "
    )
  )
}

forbidden_main_pattern <-
  "local_minus_up|carbonate_evaporite_proxy|_x_aridity"

for (model_name in names(expected_model_sizes)) {
  forbidden <- grep(
    forbidden_main_pattern,
    feature_sets[[model_name]],
    value = TRUE
  )

  if (length(forbidden) > 0L) {
    stop(
      model_name,
      " contains forbidden derived terms: ",
      paste(
        forbidden,
        collapse = ", "
      )
    )
  }
}

dat <- dat |>
  dplyr::mutate(
    tail_ge_072 =
      sr87_sr86 >= 0.72,

    tail_ge_075 =
      sr87_sr86 >= 0.75,

    tail_ge_080 =
      sr87_sr86 >= 0.80
  )

# ==============================================================================
# Project coordinates without sf or an external PROJ database
# ==============================================================================

# Spherical sinusoidal projection:
#   x = R * longitude_radians * cos(latitude_radians)
#   y = R * latitude_radians
#
# This produces deterministic metre-based coordinates and avoids dependence
# on the cluster PROJ installation. The antimeridian is treated as a block
# boundary, which is conservative for spatial cross-validation.

earth_radius_m <- 6371008.8

longitude_rad <-
  dat$longitude *
  pi /
  180

latitude_rad <-
  dat$latitude *
  pi /
  180

dat$cv_x_m <-
  earth_radius_m *
  longitude_rad *
  cos(latitude_rad)

dat$cv_y_m <-
  earth_radius_m *
  latitude_rad

projection_label <-
  paste(
    "manual spherical sinusoidal projection;",
    "Earth radius 6371008.8 m;",
    "antimeridian treated as boundary"
  )

if (
  anyNA(dat$cv_x_m) ||
  anyNA(dat$cv_y_m) ||
  any(!is.finite(dat$cv_x_m)) ||
  any(!is.finite(dat$cv_y_m))
) {
  stop(
    "Manual projected coordinates contain missing or non-finite values."
  )
}

projection_qc <- tibble::tibble(
  coordinate = c(
    "cv_x_m",
    "cv_y_m"
  ),

  minimum = c(
    min(dat$cv_x_m),
    min(dat$cv_y_m)
  ),

  median = c(
    stats::median(dat$cv_x_m),
    stats::median(dat$cv_y_m)
  ),

  maximum = c(
    max(dat$cv_x_m),
    max(dat$cv_y_m)
  ),

  n_missing = c(
    sum(is.na(dat$cv_x_m)),
    sum(is.na(dat$cv_y_m))
  ),

  n_nonfinite = c(
    sum(!is.finite(dat$cv_x_m)),
    sum(!is.finite(dat$cv_y_m))
  )
)

readr::write_csv(
  projection_qc,
  file.path(
    out_dir,
    "projection_qc.csv"
  )
)

# ==============================================================================
# Deterministic balanced assignment of whole blocks or groups to folds
# ==============================================================================

# Primary validation-fold allocation is outcome-blind.
# Fold assignment uses group membership and row counts only.
# Sr values, tail indicators, geological regimes and model performance
# are retained solely for post-allocation diagnostics.
assign_units_balanced <- function(
  units,
  k,
  seed
) {
  if (!is.data.frame(units)) {
    stop(
      "units must be a data frame."
    )
  }

  if (!"n_rows" %in% names(units)) {
    stop(
      "units must contain an n_rows column."
    )
  }

  if (
    length(k) != 1L ||
    !is.finite(k) ||
    k < 2L ||
    k != as.integer(k)
  ) {
    stop(
      "k must be a single integer of at least 2."
    )
  }

  k <- as.integer(k)

  if (nrow(units) < k) {
    stop(
      "Cannot allocate ",
      nrow(units),
      " units across ",
      k,
      " folds."
    )
  }

  if (
    anyNA(units$n_rows) ||
    any(
      !is.finite(
        units$n_rows
      )
    ) ||
    any(
      units$n_rows <=
        0
    )
  ) {
    stop(
      "n_rows must contain finite positive values."
    )
  }

  set.seed(seed)

  work <- units

  work$.original_order <-
    seq_len(
      nrow(work)
    )

  work$.random_tie_breaker <-
    stats::runif(
      nrow(work)
    )

  work <- work[
    order(
      -work$n_rows,
      work$.random_tie_breaker
    ),
    ,
    drop = FALSE
  ]

  fold_rows <-
    rep(
      0,
      k
    )

  fold_units <-
    rep(
      0L,
      k
    )

  assigned_fold <-
    integer(
      nrow(work)
    )

  for (i in seq_len(nrow(work))) {
    if (i <= k) {
      chosen_fold <- i
    } else {
      candidate_folds <- which(
        fold_rows ==
          min(
            fold_rows
          )
      )

      if (length(candidate_folds) > 1L) {
        minimum_units <- min(
          fold_units[
            candidate_folds
          ]
        )

        candidate_folds <-
          candidate_folds[
            fold_units[
              candidate_folds
            ] ==
              minimum_units
          ]
      }

      chosen_fold <- if (
        length(candidate_folds) ==
          1L
      ) {
        candidate_folds[[1]]
      } else {
        sample(
          candidate_folds,
          size = 1L
        )
      }
    }

    assigned_fold[[i]] <-
      chosen_fold

    fold_rows[[chosen_fold]] <-
      fold_rows[[chosen_fold]] +
      work$n_rows[[i]]

    fold_units[[chosen_fold]] <-
      fold_units[[chosen_fold]] +
      1L
  }

  work$fold <-
    assigned_fold

  work <- work[
    order(
      work$.original_order
    ),
    ,
    drop = FALSE
  ]

  work$.original_order <- NULL
  work$.random_tie_breaker <- NULL

  rownames(work) <- NULL

  work
}

summarise_units <- function(
  row_table,
  unit_column
) {
  regime_wide <- row_table |>
    dplyr::count(
      .data[[unit_column]],
      geological_regime_primary,
      name = "n"
    ) |>
    tidyr::pivot_wider(
      names_from =
        geological_regime_primary,

      values_from =
        n,

      values_fill =
        0,

      names_prefix =
        "regime_n__"
    )

  row_table |>
    dplyr::group_by(
      .data[[unit_column]]
    ) |>
    dplyr::summarise(
      n_rows =
        dplyr::n(),

      n_ge_072 =
        sum(
          tail_ge_072
        ),

      n_ge_075 =
        sum(
          tail_ge_075
        ),

      n_ge_080 =
        sum(
          tail_ge_080
        ),

      .groups = "drop"
    ) |>
    dplyr::left_join(
      regime_wide,
      by = unit_column
    )
}

# tidyr is used only after the package check above.
if (!requireNamespace(
  "tidyr",
  quietly = TRUE
)) {
  stop(
    "Package 'tidyr' is required for regime-balanced folds."
  )
}

# ==============================================================================
# Build outer five-fold spatial blocks at 500, 1000 and 1500 km
# ==============================================================================

spatial_scales_km <- c(
  500L,
  1000L,
  1500L
)

outer_spatial_list <- list()
block_summary_list <- list()
inner_spatial_list <- list()

for (
  scale_km in spatial_scales_km
) {
  scheme <- paste0(
    "spatial_",
    scale_km,
    "km"
  )

  block_size_m <-
    scale_km * 1000

  scheme_rows <- dat |>
    dplyr::mutate(
      validation_scheme =
        scheme,

      block_x =
        floor(
          cv_x_m /
            block_size_m
        ),

      block_y =
        floor(
          cv_y_m /
            block_size_m
        ),

      validation_unit =
        paste(
          scheme,
          block_x,
          block_y,
          sep = "__"
        )
    )

  unit_summary <- summarise_units(
    scheme_rows,
    "validation_unit"
  )

  unit_assignment <- assign_units_balanced(
    unit_summary,
    k = 5L,
    seed = 51000L +
      scale_km
  )

  block_summary_list[[
    scheme
  ]] <- unit_assignment |>
    dplyr::mutate(
      validation_scheme =
        scheme,

      block_size_km =
        scale_km,

      outer_fold =
        fold
    ) |>
    dplyr::select(
      -fold
    )

  outer_rows <- scheme_rows |>
    dplyr::left_join(
      unit_assignment |>
        dplyr::select(
          validation_unit,
          outer_fold = fold
        ),
      by = "validation_unit"
    ) |>
    dplyr::transmute(
      row_id,
      site_id,
      longitude,
      latitude,
      sr87_sr86,
      geological_regime_primary,
      tail_ge_072,
      tail_ge_075,
      tail_ge_080,
      validation_scheme,
      block_size_km =
        scale_km,

      validation_unit,
      outer_fold
    )

  outer_spatial_list[[
    scheme
  ]] <- outer_rows

  # ---------------------------------------------------------------------------
  # Inner three-fold blocking inside each outer-training partition
  # ---------------------------------------------------------------------------

  for (
    outer_fold_id in 1:5
  ) {
    training_rows <- outer_rows |>
      dplyr::filter(
        outer_fold !=
          outer_fold_id
      )

    inner_unit_summary <- summarise_units(
      training_rows,
      "validation_unit"
    )

    inner_assignment <- assign_units_balanced(
      inner_unit_summary,
      k = 3L,
      seed =
        52000L +
        scale_km * 10L +
        outer_fold_id
    )

    inner_rows <- training_rows |>
      dplyr::left_join(
        inner_assignment |>
          dplyr::select(
            validation_unit,
            inner_fold = fold
          ),
        by = "validation_unit"
      ) |>
      dplyr::transmute(
        row_id,
        validation_scheme,
        outer_fold =
          outer_fold_id,

        inner_fold,
        validation_unit
      )

    inner_spatial_list[[
      paste(
        scheme,
        outer_fold_id,
        sep = "__"
      )
    ]] <- inner_rows
  }
}

outer_spatial <- dplyr::bind_rows(
  outer_spatial_list
)

inner_spatial <- dplyr::bind_rows(
  inner_spatial_list
)

block_summary <- dplyr::bind_rows(
  block_summary_list
)

# ==============================================================================
# Validation invariants
# ==============================================================================

expected_outer_rows <-
  nrow(dat) *
  length(spatial_scales_km)

if (nrow(outer_spatial) != expected_outer_rows) {
  stop(
    "Unexpected number of outer spatial-fold rows: ",
    nrow(outer_spatial)
  )
}

if (
  anyNA(
    outer_spatial$outer_fold
  ) ||
  any(
    !outer_spatial$outer_fold %in%
      1:5
  )
) {
  stop(
    "Invalid outer-fold assignments."
  )
}

block_split_check <- outer_spatial |>
  dplyr::distinct(
    validation_scheme,
    validation_unit,
    outer_fold
  ) |>
  dplyr::count(
    validation_scheme,
    validation_unit,
    name = "n_folds"
  ) |>
  dplyr::filter(
    n_folds != 1L
  )

if (nrow(block_split_check) > 0L) {
  stop(
    "At least one spatial block was split across outer folds."
  )
}

inner_block_split_check <- inner_spatial |>
  dplyr::distinct(
    validation_scheme,
    outer_fold,
    validation_unit,
    inner_fold
  ) |>
  dplyr::count(
    validation_scheme,
    outer_fold,
    validation_unit,
    name = "n_inner_folds"
  ) |>
  dplyr::filter(
    n_inner_folds != 1L
  )

if (nrow(inner_block_split_check) > 0L) {
  stop(
    "At least one spatial block was split across inner folds."
  )
}

outer_test_counts <- outer_spatial |>
  dplyr::count(
    validation_scheme,
    outer_fold,
    name = "n_test"
  )

expected_validation_schemes <- paste0(
  "spatial_",
  spatial_scales_km,
  "km"
)

expected_outer_fold_grid <- tidyr::expand_grid(
  validation_scheme =
    expected_validation_schemes,

  outer_fold =
    1:5
)

missing_outer_folds <- expected_outer_fold_grid |>
  dplyr::anti_join(
    outer_test_counts |>
      dplyr::select(
        validation_scheme,
        outer_fold
      ),
    by = c(
      "validation_scheme",
      "outer_fold"
    )
  )

if (nrow(missing_outer_folds) > 0L) {
  readr::write_csv(
    missing_outer_folds,
    file.path(
      out_dir,
      "missing_outer_folds.csv"
    )
  )

  stop(
    "One or more required outer folds were not populated."
  )
}

if (
  any(
    outer_test_counts$n_test <=
      0L
  )
) {
  stop(
    "At least one outer fold is empty."
  )
}

inner_fold_presence <- inner_spatial |>
  dplyr::distinct(
    validation_scheme,
    outer_fold,
    inner_fold
  )

expected_inner_fold_grid <- tidyr::expand_grid(
  validation_scheme =
    expected_validation_schemes,

  outer_fold =
    1:5,

  inner_fold =
    1:3
)

missing_inner_folds <- expected_inner_fold_grid |>
  dplyr::anti_join(
    inner_fold_presence,
    by = c(
      "validation_scheme",
      "outer_fold",
      "inner_fold"
    )
  )

if (nrow(missing_inner_folds) > 0L) {
  readr::write_csv(
    missing_inner_folds,
    file.path(
      out_dir,
      "missing_inner_folds.csv"
    )
  )

  stop(
    "One or more required inner folds were not populated."
  )
}

# ==============================================================================
# Fold summaries
# ==============================================================================

outer_fold_summary <- outer_spatial |>
  dplyr::group_by(
    validation_scheme,
    block_size_km,
    outer_fold
  ) |>
  dplyr::summarise(
    n_test =
      dplyr::n(),

    n_train =
      nrow(dat) -
      dplyr::n(),

    n_blocks =
      dplyr::n_distinct(
        validation_unit
      ),

    mean_sr =
      mean(
        sr87_sr86
      ),

    median_sr =
      stats::median(
        sr87_sr86
      ),

    n_ge_072 =
      sum(
        tail_ge_072
      ),

    n_ge_075 =
      sum(
        tail_ge_075
      ),

    n_ge_080 =
      sum(
        tail_ge_080
      ),

    .groups = "drop"
  )

outer_regime_summary <- outer_spatial |>
  dplyr::count(
    validation_scheme,
    block_size_km,
    outer_fold,
    geological_regime_primary,
    name = "n_test"
  ) |>
  dplyr::group_by(
    validation_scheme,
    block_size_km,
    outer_fold
  ) |>
  dplyr::mutate(
    test_fraction =
      n_test /
      sum(n_test)
  ) |>
  dplyr::ungroup()

inner_fold_summary <- inner_spatial |>
  dplyr::count(
    validation_scheme,
    outer_fold,
    inner_fold,
    name = "n_validation"
  )

# ==============================================================================
# Inventory possible reference/study grouping fields
# ==============================================================================

reference_name_pattern <-
  "reference|citation|study|paper|doi|source|dataset|publication"

reference_candidate_names <- names(dat)[
  grepl(
    reference_name_pattern,
    names(dat),
    ignore.case = TRUE
  ) &
  vapply(
    dat,
    function(x) {
      is.character(x) ||
        is.factor(x)
    },
    logical(1)
  )
]

reference_group_candidates <- if (
  length(reference_candidate_names) ==
    0L
) {
  tibble::tibble(
    feature = character(),
    column_class = character(),
    n_missing = integer(),
    n_unique = integer(),
    minimum_group_size = integer(),
    median_group_size = numeric(),
    maximum_group_size = integer(),
    suitable_for_grouped_cv = logical()
  )
} else {
  dplyr::bind_rows(
    lapply(
      reference_candidate_names,
      function(feature) {
        values <- as.character(
          dat[[feature]]
        )

        observed <- values[
          !is.na(values) &
            nzchar(
              trimws(values)
            )
        ]

        group_sizes <- table(
          observed
        )

        tibble::tibble(
          feature = feature,

          column_class =
            paste(
              class(
                dat[[feature]]
              ),
              collapse = "|"
            ),

          n_missing =
            sum(
              is.na(
                dat[[feature]]
              )
            ),

          n_unique =
            dplyr::n_distinct(
              observed
            ),

          minimum_group_size =
            if (
              length(group_sizes) ==
                0L
            ) {
              NA_integer_
            } else {
              min(
                as.integer(
                  group_sizes
                )
              )
            },

          median_group_size =
            if (
              length(group_sizes) ==
                0L
            ) {
              NA_real_
            } else {
              stats::median(
                as.integer(
                  group_sizes
                )
              )
            },

          maximum_group_size =
            if (
              length(group_sizes) ==
                0L
            ) {
              NA_integer_
            } else {
              max(
                as.integer(
                  group_sizes
                )
              )
            },

          suitable_for_grouped_cv =
            length(group_sizes) >=
              5L &&
            length(group_sizes) > 0L &&
            max(
              as.integer(
                group_sizes
              )
            ) <=
              nrow(dat) / 2 &&
            sum(
              is.na(
                dat[[feature]]
              )
            ) == 0L
        )
      }
    )
  ) |>
    dplyr::arrange(
      dplyr::desc(
        suitable_for_grouped_cv
      ),
      n_missing,
      dplyr::desc(n_unique)
    )
}

# ==============================================================================
# Save frozen validation design
# ==============================================================================

readr::write_csv(
  outer_spatial,
  file.path(
    out_dir,
    "outer_spatial_folds.csv"
  )
)

readr::write_csv(
  inner_spatial,
  file.path(
    out_dir,
    "inner_spatial_folds.csv"
  )
)

readr::write_csv(
  block_summary,
  file.path(
    out_dir,
    "spatial_block_summary.csv"
  )
)

readr::write_csv(
  outer_fold_summary,
  file.path(
    out_dir,
    "outer_fold_summary.csv"
  )
)

readr::write_csv(
  outer_regime_summary,
  file.path(
    out_dir,
    "outer_fold_regime_summary.csv"
  )
)

readr::write_csv(
  inner_fold_summary,
  file.path(
    out_dir,
    "inner_fold_summary.csv"
  )
)

readr::write_csv(
  reference_group_candidates,
  file.path(
    out_dir,
    "reference_group_candidates.csv"
  )
)

validation_design <- list(
  outer_spatial =
    outer_spatial,

  inner_spatial =
    inner_spatial,

  spatial_block_summary =
    block_summary,

  outer_fold_summary =
    outer_fold_summary,

  outer_fold_regime_summary =
    outer_regime_summary,

  inner_fold_summary =
    inner_fold_summary,

  reference_group_candidates =
    reference_group_candidates,

  spatial_scales_km =
    spatial_scales_km,

  outer_folds =
    5L,

  inner_folds =
    3L,

  projection =
    projection_label,

  foldwise_imputation =
    paste(
      "Training-fold median only;",
      "never calculate imputation values",
      "using assessment or test rows."
    ),

  feature_set_sizes =
    observed_model_sizes
)

saveRDS(
  validation_design,
  file.path(
    out_dir,
    "validation_design.rds"
  ),
  version = 3
)

reference_status <- if (
  nrow(
    reference_group_candidates |>
      dplyr::filter(
        suitable_for_grouped_cv
      )
  ) == 0L
) {
  paste(
    "No unambiguous reference-group field was frozen.",
    "Inspect reference_group_candidates.csv."
  )
} else {
  paste(
    "Potential reference-group fields were found.",
    "Inspect reference_group_candidates.csv before grouped CV."
  )
}

summary_lines <- c(
  "R51A NESTED SPATIAL VALIDATION DESIGN",
  "====================================",
  "",
  paste0(
    "Rows: ",
    nrow(dat)
  ),
  paste0(
    "Spatial scales: ",
    paste(
      spatial_scales_km,
      collapse = ", "
    ),
    " km"
  ),
  "Outer folds per scale: 5",
  "Inner folds per outer-training split: 3",
  paste0(
    "Projection: ",
    projection_label
  ),
  "",
  paste0(
    "Outer assignment rows: ",
    nrow(outer_spatial)
  ),
  paste0(
    "Inner assignment rows: ",
    nrow(inner_spatial)
  ),
  "",
  "MODEL SETS:",
  paste0(
    "M0_P0_FULL: ",
    observed_model_sizes[
      "M0_P0_FULL"
    ]
  ),
  paste0(
    "M_CORE_MECHANISTIC: ",
    observed_model_sizes[
      "M_CORE_MECHANISTIC"
    ]
  ),
  paste0(
    "M_FULL_MECHANISTIC: ",
    observed_model_sizes[
      "M_FULL_MECHANISTIC"
    ]
  ),
  "",
  "IMPUTATION RULE:",
  paste(
    "Any missing predictor is imputed using",
    "training-fold medians only."
  ),
  "",
  "REFERENCE-GROUP STATUS:",
  reference_status,
  "",
  "No outcome performance was used to define folds.",
  "",
  "STATUS: ALL R51A SPATIAL VALIDATION INVARIANTS PASSED"
)

writeLines(
  summary_lines,
  file.path(
    out_dir,
    "run_summary.txt"
  )
)

cat(
  paste(
    summary_lines,
    collapse = "\n"
  ),
  "\n"
)
