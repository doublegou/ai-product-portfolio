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

spatial_dir <- file.path(
  root,
  "outputs",
  "r51a_validation_design"
)

out_dir <- file.path(
  root,
  "outputs",
  "r51b_reference_validation"
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

spatial_design_file <- file.path(
  spatial_dir,
  "validation_design.rds"
)

required_files <- c(
  model_table_file,
  feature_sets_file,
  spatial_design_file
)

missing_files <- required_files[
  !file.exists(required_files)
]

if (length(missing_files) > 0L) {
  stop(
    "Missing required files: ",
    paste(
      missing_files,
      collapse = ", "
    )
  )
}

dat <- as.data.frame(
  readRDS(model_table_file)
)

feature_sets <- readRDS(
  feature_sets_file
)

spatial_design <- readRDS(
  spatial_design_file
)

if (nrow(dat) != 4485L) {
  stop(
    "Expected 4485 rows; found ",
    nrow(dat)
  )
}

required_columns <- c(
  "row_id",
  "site_id",
  "longitude",
  "latitude",
  "sr87_sr86",
  "geological_regime_primary",
  "reference_id"
)

missing_columns <- setdiff(
  required_columns,
  names(dat)
)

if (length(missing_columns) > 0L) {
  stop(
    "Integrated model table lacks: ",
    paste(
      missing_columns,
      collapse = ", "
    )
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
    "Frozen feature-set sizes changed."
  )
}

# ==============================================================================
# Canonical reference field
# ==============================================================================

canonical_reference_field <- Sys.getenv(
  "R51B_REFERENCE_FIELD",
  unset = "reference_id"
)

if (!canonical_reference_field %in% names(dat)) {
  stop(
    "Requested reference field is absent: ",
    canonical_reference_field
  )
}

normalise_reference <- function(x) {
  x <- trimws(
    as.character(x)
  )

  x[
    is.na(x) |
      !nzchar(x)
  ] <- NA_character_

  x
}

dat$reference_group <- normalise_reference(
  dat[[canonical_reference_field]]
)

if (anyNA(dat$reference_group)) {
  stop(
    "Canonical reference field contains missing or blank values."
  )
}

n_reference_groups <- dplyr::n_distinct(
  dat$reference_group
)

if (n_reference_groups < 5L) {
  stop(
    "Fewer than five reference groups are available."
  )
}

reference_sizes <- table(
  dat$reference_group
)

largest_reference_group <- max(
  as.integer(reference_sizes)
)

if (
  largest_reference_group >
    nrow(dat) / 2
) {
  stop(
    "One reference group contains more than half of all rows."
  )
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
# Audit relationships among available reference fields
# ==============================================================================

candidate_reference_fields <- intersect(
  c(
    "reference_id",
    "short_references",
    "reference_ids",
    "references"
  ),
  names(dat)
)

reference_field_audit <- dplyr::bind_rows(
  lapply(
    candidate_reference_fields,
    function(feature) {
      values <- normalise_reference(
        dat[[feature]]
      )

      group_sizes <- table(
        values[
          !is.na(values)
        ]
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

        n_rows =
          length(values),

        n_missing =
          sum(
            is.na(values)
          ),

        n_unique =
          dplyr::n_distinct(
            values[
              !is.na(values)
            ]
          ),

        minimum_group_size =
          if (
            length(group_sizes) == 0L
          ) {
            NA_integer_
          } else {
            min(
              as.integer(group_sizes)
            )
          },

        median_group_size =
          if (
            length(group_sizes) == 0L
          ) {
            NA_real_
          } else {
            stats::median(
              as.integer(group_sizes)
            )
          },

        maximum_group_size =
          if (
            length(group_sizes) == 0L
          ) {
            NA_integer_
          } else {
            max(
              as.integer(group_sizes)
            )
          },

        canonical =
          feature ==
          canonical_reference_field
      )
    }
  )
)

readr::write_csv(
  reference_field_audit,
  file.path(
    out_dir,
    "reference_field_audit.csv"
  )
)

crosswalk_records <- list()

for (
  alternative_field in setdiff(
    candidate_reference_fields,
    canonical_reference_field
  )
) {
  alternative_values <- normalise_reference(
    dat[[alternative_field]]
  )

  crosswalk_records[[
    alternative_field
  ]] <- tibble::tibble(
    reference_group =
      dat$reference_group,

    alternative_field =
      alternative_field,

    alternative_value =
      alternative_values
  ) |>
    dplyr::group_by(
      reference_group,
      alternative_field
    ) |>
    dplyr::summarise(
      n_alternative_values =
        dplyr::n_distinct(
          alternative_value[
            !is.na(alternative_value)
          ]
        ),

      example_alternative_value =
        dplyr::first(
          alternative_value[
            !is.na(alternative_value)
          ],
          default = NA_character_
        ),

      .groups = "drop"
    )
}

reference_field_crosswalk <- if (
  length(crosswalk_records) == 0L
) {
  tibble::tibble(
    reference_group = character(),
    alternative_field = character(),
    n_alternative_values = integer(),
    example_alternative_value = character()
  )
} else {
  dplyr::bind_rows(
    crosswalk_records
  )
}

readr::write_csv(
  reference_field_crosswalk,
  file.path(
    out_dir,
    "reference_field_crosswalk.csv"
  )
)

# ==============================================================================
# Balanced assignment of complete reference groups
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

summarise_reference_units <- function(
  row_table
) {
  regime_wide <- row_table |>
    dplyr::count(
      reference_group,
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
      reference_group
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

      mean_sr =
        mean(
          sr87_sr86
        ),

      median_sr =
        stats::median(
          sr87_sr86
        ),

      .groups = "drop"
    ) |>
    dplyr::left_join(
      regime_wide,
      by = "reference_group"
    )
}

reference_unit_summary <- summarise_reference_units(
  dat
)

# ==============================================================================
# Outer five-fold reference-grouped CV
# ==============================================================================

outer_group_assignment <- assign_units_balanced(
  reference_unit_summary,
  k = 5L,
  seed = 51101L
) |>
  dplyr::rename(
    outer_fold =
      fold
  )

outer_reference_rows <- dat |>
  dplyr::left_join(
    outer_group_assignment |>
      dplyr::select(
        reference_group,
        outer_fold
      ),
    by = "reference_group"
  ) |>
  dplyr::transmute(
    row_id,
    site_id,
    longitude,
    latitude,
    sr87_sr86,
    geological_regime_primary,
    reference_group,
    tail_ge_072,
    tail_ge_075,
    tail_ge_080,
    validation_scheme =
      "reference_grouped_5fold",

    outer_fold
  )

# ==============================================================================
# Inner three-fold reference grouping
# ==============================================================================

inner_reference_list <- list()

for (
  outer_fold_id in 1:5
) {
  training_rows <- outer_reference_rows |>
    dplyr::filter(
      outer_fold !=
        outer_fold_id
    )

  inner_unit_summary <- summarise_reference_units(
    training_rows
  )

  inner_group_assignment <- assign_units_balanced(
    inner_unit_summary,
    k = 3L,
    seed =
      51200L +
      outer_fold_id
  ) |>
    dplyr::rename(
      inner_fold =
        fold
    )

  inner_reference_list[[
    paste0(
      "outer_",
      outer_fold_id
    )
  ]] <- training_rows |>
    dplyr::left_join(
      inner_group_assignment |>
        dplyr::select(
          reference_group,
          inner_fold
        ),
      by = "reference_group"
    ) |>
    dplyr::transmute(
      row_id,
      reference_group,
      validation_scheme,
      outer_fold =
        outer_fold_id,

      inner_fold
    )
}

inner_reference_rows <- dplyr::bind_rows(
  inner_reference_list
)

# ==============================================================================
# Exact leave-one-reference-out manifest
# ==============================================================================

reference_logo_manifest <- reference_unit_summary |>
  dplyr::arrange(
    reference_group
  ) |>
  dplyr::mutate(
    logo_fold_id =
      dplyr::row_number(),

    n_train =
      nrow(dat) -
      n_rows,

    hyperparameter_rule =
      paste(
        "Use hyperparameters frozen from",
        "nested spatial validation;",
        "do not tune separately within",
        "each leave-one-reference-out fold."
      )
  ) |>
  dplyr::relocate(
    logo_fold_id,
    reference_group
  )

reference_logo_rows <- outer_reference_rows |>
  dplyr::left_join(
    reference_logo_manifest |>
      dplyr::select(
        reference_group,
        logo_fold_id
      ),
    by = "reference_group"
  ) |>
  dplyr::transmute(
    row_id,
    site_id,
    reference_group,
    logo_fold_id
  )

# ==============================================================================
# Validation invariants
# ==============================================================================

if (
  nrow(outer_reference_rows) !=
    nrow(dat)
) {
  stop(
    "Outer reference assignment does not contain all rows."
  )
}

if (
  anyNA(
    outer_reference_rows$outer_fold
  )
) {
  stop(
    "Outer reference folds contain missing assignments."
  )
}

outer_group_split <- outer_reference_rows |>
  dplyr::distinct(
    reference_group,
    outer_fold
  ) |>
  dplyr::count(
    reference_group,
    name = "n_outer_folds"
  ) |>
  dplyr::filter(
    n_outer_folds != 1L
  )

if (nrow(outer_group_split) > 0L) {
  stop(
    "At least one reference group was split across outer folds."
  )
}

outer_fold_presence <- outer_reference_rows |>
  dplyr::distinct(
    outer_fold
  ) |>
  dplyr::arrange(
    outer_fold
  ) |>
  dplyr::pull(
    outer_fold
  )

if (!identical(
  as.integer(
    outer_fold_presence
  ),
  1:5
)) {
  stop(
    "Reference-grouped outer folds 1-5 are not all present."
  )
}

inner_group_split <- inner_reference_rows |>
  dplyr::distinct(
    outer_fold,
    reference_group,
    inner_fold
  ) |>
  dplyr::count(
    outer_fold,
    reference_group,
    name = "n_inner_folds"
  ) |>
  dplyr::filter(
    n_inner_folds != 1L
  )

if (nrow(inner_group_split) > 0L) {
  stop(
    "At least one reference group was split across inner folds."
  )
}

inner_presence <- inner_reference_rows |>
  dplyr::distinct(
    outer_fold,
    inner_fold
  ) |>
  dplyr::count(
    outer_fold,
    name = "n_inner_folds"
  )

if (
  nrow(inner_presence) != 5L ||
  any(
    inner_presence$n_inner_folds !=
      3L
  )
) {
  stop(
    "Every outer-training partition must contain three inner folds."
  )
}

if (
  nrow(reference_logo_manifest) !=
    n_reference_groups
) {
  stop(
    "LOGO manifest does not contain exactly one row per reference group."
  )
}

if (
  anyDuplicated(
    reference_logo_manifest$
      reference_group
  ) ||
  anyDuplicated(
    reference_logo_manifest$
      logo_fold_id
  )
) {
  stop(
    "LOGO reference groups or fold IDs are not unique."
  )
}

# ==============================================================================
# Summaries
# ==============================================================================

outer_reference_summary <- outer_reference_rows |>
  dplyr::group_by(
    outer_fold
  ) |>
  dplyr::summarise(
    n_test =
      dplyr::n(),

    n_train =
      nrow(dat) -
      dplyr::n(),

    n_reference_groups =
      dplyr::n_distinct(
        reference_group
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

outer_reference_regime_summary <-
  outer_reference_rows |>
    dplyr::count(
      outer_fold,
      geological_regime_primary,
      name = "n_test"
    ) |>
    dplyr::group_by(
      outer_fold
    ) |>
    dplyr::mutate(
      test_fraction =
        n_test /
        sum(n_test)
    ) |>
    dplyr::ungroup()

inner_reference_summary <-
  inner_reference_rows |>
    dplyr::group_by(
      outer_fold,
      inner_fold
    ) |>
    dplyr::summarise(
      n_validation =
        dplyr::n(),

      n_reference_groups =
        dplyr::n_distinct(
          reference_group
        ),

      .groups = "drop"
    )

tail_reference_support <- tibble::tibble(
  threshold = c(
    "ge_072",
    "ge_075",
    "ge_080"
  ),

  n_observations = c(
    sum(dat$tail_ge_072),
    sum(dat$tail_ge_075),
    sum(dat$tail_ge_080)
  ),

  n_reference_groups = c(
    dplyr::n_distinct(
      dat$reference_group[
        dat$tail_ge_072
      ]
    ),

    dplyr::n_distinct(
      dat$reference_group[
        dat$tail_ge_075
      ]
    ),

    dplyr::n_distinct(
      dat$reference_group[
        dat$tail_ge_080
      ]
    )
  )
)

# ==============================================================================
# Save frozen designs
# ==============================================================================

readr::write_csv(
  outer_reference_rows,
  file.path(
    out_dir,
    "outer_reference_group_folds.csv"
  )
)

readr::write_csv(
  inner_reference_rows,
  file.path(
    out_dir,
    "inner_reference_group_folds.csv"
  )
)

readr::write_csv(
  outer_group_assignment,
  file.path(
    out_dir,
    "reference_group_outer_assignment.csv"
  )
)

readr::write_csv(
  outer_reference_summary,
  file.path(
    out_dir,
    "outer_reference_fold_summary.csv"
  )
)

readr::write_csv(
  outer_reference_regime_summary,
  file.path(
    out_dir,
    "outer_reference_regime_summary.csv"
  )
)

readr::write_csv(
  inner_reference_summary,
  file.path(
    out_dir,
    "inner_reference_fold_summary.csv"
  )
)

readr::write_csv(
  reference_logo_manifest,
  file.path(
    out_dir,
    "reference_logo_manifest.csv"
  )
)

readr::write_csv(
  reference_logo_rows,
  file.path(
    out_dir,
    "reference_logo_row_assignments.csv"
  )
)

readr::write_csv(
  tail_reference_support,
  file.path(
    out_dir,
    "tail_reference_support.csv"
  )
)

reference_validation_design <- list(
  canonical_reference_field =
    canonical_reference_field,

  n_reference_groups =
    n_reference_groups,

  outer_reference_group_folds =
    outer_reference_rows,

  inner_reference_group_folds =
    inner_reference_rows,

  outer_reference_summary =
    outer_reference_summary,

  inner_reference_summary =
    inner_reference_summary,

  reference_logo_manifest =
    reference_logo_manifest,

  tail_reference_support =
    tail_reference_support,

  feature_set_sizes =
    observed_model_sizes,

  foldwise_imputation =
    paste(
      "Compute medians on analysis rows only;",
      "apply those values to assessment or test rows."
    ),

  logo_hyperparameter_rule =
    paste(
      "Exact leave-one-reference-out uses",
      "hyperparameters selected from spatial CV;",
      "no fold-specific retuning."
    )
)

saveRDS(
  reference_validation_design,
  file.path(
    out_dir,
    "reference_validation_design.rds"
  ),
  version = 3
)

summary_lines <- c(
  "R51B REFERENCE-GROUP VALIDATION DESIGN",
  "======================================",
  "",
  paste0(
    "Rows: ",
    nrow(dat)
  ),
  paste0(
    "Canonical reference field: ",
    canonical_reference_field
  ),
  paste0(
    "Reference groups: ",
    n_reference_groups
  ),
  paste0(
    "Largest reference group: ",
    largest_reference_group
  ),
  "",
  "GROUPED VALIDATION:",
  "Outer reference-group folds: 5",
  "Inner reference-group folds per outer training partition: 3",
  "No reference group crosses a fold boundary.",
  "",
  "EXACT LEAVE-ONE-REFERENCE-OUT:",
  paste0(
    "LOGO folds prepared: ",
    nrow(reference_logo_manifest)
  ),
  paste(
    "LOGO will use hyperparameters frozen",
    "from nested spatial validation."
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
  "No outcome performance was used to define folds.",
  "",
  "STATUS: ALL R51B REFERENCE VALIDATION INVARIANTS PASSED"
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
