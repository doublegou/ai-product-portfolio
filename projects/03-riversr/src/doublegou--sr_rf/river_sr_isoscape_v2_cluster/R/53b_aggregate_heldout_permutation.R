source("R/functions/core.R")

check_packages(
  c(
    "dplyr",
    "readr",
    "tibble"
  )
)

root <- project_root()

r52_dir <- file.path(
  root,
  "outputs",
  "r52_nested_spatial_rf"
)

r53_dir <- file.path(
  root,
  "outputs",
  "r53_heldout_permutation"
)

task_root <- file.path(
  r53_dir,
  "tasks"
)

out_dir <- file.path(
  r53_dir,
  "aggregate"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

manifest_file <- file.path(
  r52_dir,
  "task_manifest.csv"
)

if (!file.exists(manifest_file)) {
  stop(
    "Missing task manifest: ",
    manifest_file
  )
}

manifest <- readr::read_csv(
  manifest_file,
  show_col_types = FALSE
)

if (
  nrow(manifest) != 45L ||
  !identical(
    as.integer(manifest$task_id),
    1:45
  )
) {
  stop(
    "R52 task manifest must contain task IDs 1:45."
  )
}

required_task_files <- c(
  "run_summary.txt",
  "baseline_reproduction.csv",
  "baseline_metrics.csv",
  "feature_group_map.csv",
  "feature_permutation_summary.csv",
  "group_permutation_summary.csv",
  "task_metadata.rds"
)

task_directory <- function(
  task_id,
  task_label
) {
  file.path(
    task_root,
    sprintf(
      "task_%03d__%s",
      task_id,
      task_label
    )
  )
}

# ==============================================================================
# Completion and reproduction audit
# ==============================================================================

audit_records <- lapply(
  seq_len(nrow(manifest)),
  function(i) {
    task_id <- manifest$task_id[[i]]
    task_label <- manifest$task_label[[i]]

    task_dir <- task_directory(
      task_id,
      task_label
    )

    expected_paths <- file.path(
      task_dir,
      required_task_files
    )

    summary_file <- file.path(
      task_dir,
      "run_summary.txt"
    )

    summary_lines <- if (
      file.exists(summary_file)
    ) {
      readLines(
        summary_file,
        warn = FALSE
      )
    } else {
      character()
    }

    reproduction_file <- file.path(
      task_dir,
      "baseline_reproduction.csv"
    )

    reproduction <- if (
      file.exists(reproduction_file)
    ) {
      readr::read_csv(
        reproduction_file,
        show_col_types = FALSE
      )
    } else {
      NULL
    }

    reproduction_passed <- if (
      is.null(reproduction) ||
      nrow(reproduction) != 1L
    ) {
      FALSE
    } else {
      isTRUE(
        reproduction$
          reproduction_passed[[1]]
      )
    }

    maximum_difference <- if (
      is.null(reproduction) ||
      nrow(reproduction) != 1L
    ) {
      NA_real_
    } else {
      as.numeric(
        reproduction$
          maximum_absolute_difference[[1]]
      )
    }

    tibble::tibble(
      task_id =
        task_id,

      task_label =
        task_label,

      validation_scheme =
        manifest$validation_scheme[[i]],

      outer_fold =
        manifest$outer_fold[[i]],

      model_name =
        manifest$model_name[[i]],

      task_directory =
        task_dir,

      directory_exists =
        dir.exists(task_dir),

      n_required_files_present =
        sum(
          file.exists(
            expected_paths
          )
        ),

      n_required_files_expected =
        length(
          required_task_files
        ),

      all_required_files_present =
        all(
          file.exists(
            expected_paths
          )
        ),

      status_passed =
        any(
          grepl(
            paste0(
              "^STATUS: R53 HELD-OUT ",
              "PERMUTATION TASK PASSED$"
            ),
            summary_lines
          )
        ),

      reproduction_passed =
        reproduction_passed,

      maximum_reproduction_difference =
        maximum_difference
    )
  }
)

completion_audit <- dplyr::bind_rows(
  audit_records
)

readr::write_csv(
  completion_audit,
  file.path(
    out_dir,
    "task_completion_audit.csv"
  )
)

incomplete_tasks <- completion_audit |>
  dplyr::filter(
    !directory_exists |
      !all_required_files_present |
      !status_passed |
      !reproduction_passed |
      is.na(
        maximum_reproduction_difference
      ) |
      maximum_reproduction_difference >
        1e-8
  )

if (nrow(incomplete_tasks) > 0L) {
  readr::write_csv(
    incomplete_tasks,
    file.path(
      out_dir,
      "incomplete_tasks.csv"
    )
  )

  stop(
    "R53 aggregation stopped: ",
    nrow(incomplete_tasks),
    " tasks are incomplete or invalid. ",
    "Inspect outputs/r53_heldout_permutation/",
    "aggregate/incomplete_tasks.csv."
  )
}

# ==============================================================================
# Read task outputs
# ==============================================================================

read_task_csv <- function(
  task_id,
  task_label,
  filename
) {
  readr::read_csv(
    file.path(
      task_directory(
        task_id,
        task_label
      ),
      filename
    ),
    show_col_types = FALSE
  )
}

reproduction_records <- list()
feature_map_records <- list()
feature_summary_records <- list()
group_summary_records <- list()

for (i in seq_len(nrow(manifest))) {
  task_id <- manifest$task_id[[i]]
  task_label <- manifest$task_label[[i]]

  reproduction_records[[i]] <-
    read_task_csv(
      task_id,
      task_label,
      "baseline_reproduction.csv"
    )

  feature_map_records[[i]] <-
    read_task_csv(
      task_id,
      task_label,
      "feature_group_map.csv"
    ) |>
    dplyr::mutate(
      task_id =
        task_id,

      task_label =
        task_label,

      validation_scheme =
        manifest$validation_scheme[[i]],

      outer_fold =
        manifest$outer_fold[[i]],

      model_name =
        manifest$model_name[[i]]
    ) |>
    dplyr::relocate(
      task_id,
      task_label,
      validation_scheme,
      outer_fold,
      model_name
    )

  feature_summary_records[[i]] <-
    read_task_csv(
      task_id,
      task_label,
      "feature_permutation_summary.csv"
    )

  group_summary_records[[i]] <-
    read_task_csv(
      task_id,
      task_label,
      "group_permutation_summary.csv"
    )
}

all_reproduction <- dplyr::bind_rows(
  reproduction_records
)

all_feature_maps <- dplyr::bind_rows(
  feature_map_records
)

all_feature_summary <- dplyr::bind_rows(
  feature_summary_records
)

all_group_summary <- dplyr::bind_rows(
  group_summary_records
)

# ==============================================================================
# Structural invariants
# ==============================================================================

if (
  nrow(all_reproduction) != 45L ||
  any(
    !all_reproduction$
      reproduction_passed
  ) ||
  any(
    all_reproduction$
      maximum_absolute_difference >
        1e-8
  )
) {
  stop(
    "One or more R53 models failed to reproduce R52 predictions."
  )
}

expected_subsets <- c(
  "all",
  "ge_072",
  "ge_075",
  "ge_080"
)

feature_structure_audit <- lapply(
  seq_len(nrow(manifest)),
  function(i) {
    current_task_id <-
      manifest$task_id[[i]]

    feature_rows <- all_feature_summary |>
      dplyr::filter(
        task_id ==
          .env$current_task_id
      )

    map_rows <- all_feature_maps |>
      dplyr::filter(
        task_id ==
          .env$current_task_id
      )

    duplicate_keys <- feature_rows |>
      dplyr::count(
        entity_name,
        evaluation_subset,
        name = "n_key_rows"
      ) |>
      dplyr::filter(
        n_key_rows != 1L
      )

    tibble::tibble(
      task_id =
        current_task_id,

      expected_features =
        manifest$n_features[[i]],

      mapped_features =
        dplyr::n_distinct(
          map_rows$feature
        ),

      expected_summary_rows =
        manifest$n_features[[i]] *
        length(expected_subsets),

      observed_summary_rows =
        nrow(feature_rows),

      duplicate_keys =
        nrow(duplicate_keys),

      n_subsets =
        dplyr::n_distinct(
          feature_rows$
            evaluation_subset
        ),

      all_repeats_equal_ten =
        all(
          feature_rows$n_repeats ==
            10L
        )
    )
  }
) |>
  dplyr::bind_rows()

group_structure_audit <- lapply(
  seq_len(nrow(manifest)),
  function(i) {
    current_task_id <-
      manifest$task_id[[i]]

    group_rows <- all_group_summary |>
      dplyr::filter(
        task_id ==
          .env$current_task_id
      )

    map_rows <- all_feature_maps |>
      dplyr::filter(
        task_id ==
          .env$current_task_id
      )

    expected_groups <-
      dplyr::n_distinct(
        map_rows$feature_group
      )

    duplicate_keys <- group_rows |>
      dplyr::count(
        entity_name,
        evaluation_subset,
        name = "n_key_rows"
      ) |>
      dplyr::filter(
        n_key_rows != 1L
      )

    tibble::tibble(
      task_id =
        current_task_id,

      expected_groups =
        expected_groups,

      expected_summary_rows =
        expected_groups *
        length(expected_subsets),

      observed_summary_rows =
        nrow(group_rows),

      duplicate_keys =
        nrow(duplicate_keys),

      n_subsets =
        dplyr::n_distinct(
          group_rows$
            evaluation_subset
        ),

      all_repeats_equal_ten =
        all(
          group_rows$n_repeats ==
            10L
        )
    )
  }
) |>
  dplyr::bind_rows()

readr::write_csv(
  feature_structure_audit,
  file.path(
    out_dir,
    "feature_task_audit.csv"
  )
)

readr::write_csv(
  group_structure_audit,
  file.path(
    out_dir,
    "group_task_audit.csv"
  )
)

invalid_feature_tasks <- feature_structure_audit |>
  dplyr::filter(
    mapped_features !=
      expected_features |
      observed_summary_rows !=
        expected_summary_rows |
      duplicate_keys !=
        0L |
      n_subsets !=
        4L |
      !all_repeats_equal_ten
  )

invalid_group_tasks <- group_structure_audit |>
  dplyr::filter(
    observed_summary_rows !=
      expected_summary_rows |
      duplicate_keys !=
        0L |
      n_subsets !=
        4L |
      !all_repeats_equal_ten
  )

if (
  nrow(invalid_feature_tasks) > 0L ||
  nrow(invalid_group_tasks) > 0L
) {
  readr::write_csv(
    invalid_feature_tasks,
    file.path(
      out_dir,
      "invalid_feature_tasks.csv"
    )
  )

  readr::write_csv(
    invalid_group_tasks,
    file.path(
      out_dir,
      "invalid_group_tasks.csv"
    )
  )

  stop(
    "R53 task outputs failed structural validation."
  )
}

# ==============================================================================
# Safe summary helpers
# ==============================================================================

finite_values <- function(x) {
  x[
    is.finite(x)
  ]
}

safe_mean <- function(x) {
  values <- finite_values(x)

  if (length(values) == 0L) {
    return(NA_real_)
  }

  mean(values)
}

safe_median <- function(x) {
  values <- finite_values(x)

  if (length(values) == 0L) {
    return(NA_real_)
  }

  stats::median(values)
}

safe_sd <- function(x) {
  values <- finite_values(x)

  if (length(values) < 2L) {
    return(NA_real_)
  }

  stats::sd(values)
}

safe_min <- function(x) {
  values <- finite_values(x)

  if (length(values) == 0L) {
    return(NA_real_)
  }

  min(values)
}

safe_max <- function(x) {
  values <- finite_values(x)

  if (length(values) == 0L) {
    return(NA_real_)
  }

  max(values)
}

weighted_mean_safe <- function(
  values,
  weights
) {
  valid <-
    is.finite(values) &
    is.finite(weights) &
    weights >
      0

  if (!any(valid)) {
    return(NA_real_)
  }

  stats::weighted.mean(
    values[
      valid
    ],
    weights[
      valid
    ]
  )
}

# ==============================================================================
# Aggregate mechanism-group importance
# ==============================================================================

group_importance_by_scheme <-
  all_group_summary |>
  dplyr::rename(
    fold_delta_mse =
      mean_delta_mse,

    fold_relative_delta_mse =
      mean_relative_delta_mse,

    fold_positive_repeat_fraction =
      positive_importance_fraction
  ) |>
  dplyr::group_by(
    validation_scheme,
    model_name,
    entity_name,
    evaluation_subset
  ) |>
  dplyr::summarise(
    n_outer_folds =
      dplyr::n_distinct(
        outer_fold
      ),

    folds_with_data =
      sum(
        evaluation_n >
          0
      ),

    total_evaluation_n =
      sum(
        evaluation_n,
        na.rm = TRUE
      ),

    n_group_features =
      dplyr::first(
        n_group_features
      ),

    folds_positive =
      sum(
        is.finite(
          fold_delta_mse
        ) &
        fold_delta_mse >
          0
      ),

    folds_negative =
      sum(
        is.finite(
          fold_delta_mse
        ) &
        fold_delta_mse <
          0
      ),

    mean_delta_mse =
      safe_mean(
        fold_delta_mse
      ),

    weighted_mean_delta_mse =
      weighted_mean_safe(
        fold_delta_mse,
        evaluation_n
      ),

    median_delta_mse =
      safe_median(
        fold_delta_mse
      ),

    sd_delta_mse =
      safe_sd(
        fold_delta_mse
      ),

    minimum_delta_mse =
      safe_min(
        fold_delta_mse
      ),

    maximum_delta_mse =
      safe_max(
        fold_delta_mse
      ),

    weighted_mean_relative_delta_mse =
      weighted_mean_safe(
        fold_relative_delta_mse,
        evaluation_n
      ),

    mean_positive_repeat_fraction =
      safe_mean(
        fold_positive_repeat_fraction
      ),

    .groups = "drop"
  ) |>
  dplyr::group_by(
    validation_scheme,
    model_name,
    evaluation_subset
  ) |>
  dplyr::arrange(
    dplyr::desc(
      weighted_mean_delta_mse
    ),
    dplyr::desc(
      folds_positive
    ),
    .by_group = TRUE
  ) |>
  dplyr::mutate(
    importance_rank =
      dplyr::row_number(),

    stable_positive_all_folds =
      folds_positive ==
        n_outer_folds
  ) |>
  dplyr::ungroup()

# ==============================================================================
# Aggregate individual-feature importance
# ==============================================================================

feature_importance_by_scheme <-
  all_feature_summary |>
  dplyr::rename(
    fold_delta_mse =
      mean_delta_mse,

    fold_relative_delta_mse =
      mean_relative_delta_mse,

    fold_positive_repeat_fraction =
      positive_importance_fraction
  ) |>
  dplyr::group_by(
    validation_scheme,
    model_name,
    entity_name,
    feature_group,
    evaluation_subset
  ) |>
  dplyr::summarise(
    n_outer_folds =
      dplyr::n_distinct(
        outer_fold
      ),

    folds_with_data =
      sum(
        evaluation_n >
          0
      ),

    total_evaluation_n =
      sum(
        evaluation_n,
        na.rm = TRUE
      ),

    folds_positive =
      sum(
        is.finite(
          fold_delta_mse
        ) &
        fold_delta_mse >
          0
      ),

    folds_negative =
      sum(
        is.finite(
          fold_delta_mse
        ) &
        fold_delta_mse <
          0
      ),

    mean_delta_mse =
      safe_mean(
        fold_delta_mse
      ),

    weighted_mean_delta_mse =
      weighted_mean_safe(
        fold_delta_mse,
        evaluation_n
      ),

    median_delta_mse =
      safe_median(
        fold_delta_mse
      ),

    sd_delta_mse =
      safe_sd(
        fold_delta_mse
      ),

    weighted_mean_relative_delta_mse =
      weighted_mean_safe(
        fold_relative_delta_mse,
        evaluation_n
      ),

    mean_positive_repeat_fraction =
      safe_mean(
        fold_positive_repeat_fraction
      ),

    .groups = "drop"
  ) |>
  dplyr::group_by(
    validation_scheme,
    model_name,
    evaluation_subset
  ) |>
  dplyr::arrange(
    dplyr::desc(
      weighted_mean_delta_mse
    ),
    dplyr::desc(
      folds_positive
    ),
    .by_group = TRUE
  ) |>
  dplyr::mutate(
    importance_rank =
      dplyr::row_number(),

    stable_positive_all_folds =
      folds_positive ==
        n_outer_folds
  ) |>
  dplyr::ungroup()

# ==============================================================================
# Descriptive cross-scale stability
#
# The same observations are reused across the three blocking scales.
# These are robustness summaries, not 15 independent replicates.
# ==============================================================================

group_cross_scale_summary <-
  group_importance_by_scheme |>
  dplyr::group_by(
    model_name,
    entity_name,
    evaluation_subset
  ) |>
  dplyr::summarise(
    n_spatial_scales =
      dplyr::n_distinct(
        validation_scheme
      ),

    total_outer_folds =
      sum(
        n_outer_folds
      ),

    total_folds_positive =
      sum(
        folds_positive
      ),

    spatial_scales_positive =
      sum(
        is.finite(
          weighted_mean_delta_mse
        ) &
        weighted_mean_delta_mse >
          0
      ),

    spatial_scales_top_three =
      sum(
        importance_rank <=
          3L
      ),

    mean_weighted_delta_mse_across_scales =
      safe_mean(
        weighted_mean_delta_mse
      ),

    median_rank_across_scales =
      safe_median(
        importance_rank
      ),

    best_rank =
      safe_min(
        importance_rank
      ),

    worst_rank =
      safe_max(
        importance_rank
      ),

    .groups = "drop"
  ) |>
  dplyr::group_by(
    model_name,
    evaluation_subset
  ) |>
  dplyr::arrange(
    dplyr::desc(
      mean_weighted_delta_mse_across_scales
    ),
    dplyr::desc(
      total_folds_positive
    ),
    .by_group = TRUE
  ) |>
  dplyr::mutate(
    cross_scale_rank =
      dplyr::row_number()
  ) |>
  dplyr::ungroup()

feature_cross_scale_summary <-
  feature_importance_by_scheme |>
  dplyr::group_by(
    model_name,
    entity_name,
    feature_group,
    evaluation_subset
  ) |>
  dplyr::summarise(
    n_spatial_scales =
      dplyr::n_distinct(
        validation_scheme
      ),

    total_outer_folds =
      sum(
        n_outer_folds
      ),

    total_folds_positive =
      sum(
        folds_positive
      ),

    spatial_scales_positive =
      sum(
        is.finite(
          weighted_mean_delta_mse
        ) &
        weighted_mean_delta_mse >
          0
      ),

    spatial_scales_top_ten =
      sum(
        importance_rank <=
          10L
      ),

    mean_weighted_delta_mse_across_scales =
      safe_mean(
        weighted_mean_delta_mse
      ),

    median_rank_across_scales =
      safe_median(
        importance_rank
      ),

    .groups = "drop"
  ) |>
  dplyr::group_by(
    model_name,
    evaluation_subset
  ) |>
  dplyr::arrange(
    dplyr::desc(
      mean_weighted_delta_mse_across_scales
    ),
    dplyr::desc(
      total_folds_positive
    ),
    .by_group = TRUE
  ) |>
  dplyr::mutate(
    cross_scale_rank =
      dplyr::row_number()
  ) |>
  dplyr::ungroup()

unique_feature_group_map <-
  all_feature_maps |>
  dplyr::distinct(
    model_name,
    feature,
    feature_group
  ) |>
  dplyr::arrange(
    model_name,
    feature_group,
    feature
  )

# ==============================================================================
# Save outputs
# ==============================================================================

readr::write_csv(
  all_reproduction,
  file.path(
    out_dir,
    "all_baseline_reproduction.csv"
  )
)

readr::write_csv(
  all_group_summary,
  file.path(
    out_dir,
    "all_group_permutation_summaries.csv"
  )
)

readr::write_csv(
  all_feature_summary,
  file.path(
    out_dir,
    "all_feature_permutation_summaries.csv"
  )
)

readr::write_csv(
  unique_feature_group_map,
  file.path(
    out_dir,
    "feature_group_map.csv"
  )
)

readr::write_csv(
  group_importance_by_scheme,
  file.path(
    out_dir,
    "group_importance_by_scheme_model.csv"
  )
)

readr::write_csv(
  feature_importance_by_scheme,
  file.path(
    out_dir,
    "feature_importance_by_scheme_model.csv"
  )
)

readr::write_csv(
  group_cross_scale_summary,
  file.path(
    out_dir,
    "group_importance_cross_scale.csv"
  )
)

readr::write_csv(
  feature_cross_scale_summary,
  file.path(
    out_dir,
    "feature_importance_cross_scale.csv"
  )
)

readr::write_csv(
  group_importance_by_scheme |>
    dplyr::filter(
      importance_rank <=
        5L
    ),
  file.path(
    out_dir,
    "top_group_results.csv"
  )
)

readr::write_csv(
  feature_importance_by_scheme |>
    dplyr::filter(
      importance_rank <=
        15L
    ),
  file.path(
    out_dir,
    "top_feature_results.csv"
  )
)

aggregate_results <- list(
  completion_audit =
    completion_audit,

  baseline_reproduction =
    all_reproduction,

  group_task_results =
    all_group_summary,

  feature_task_results =
    all_feature_summary,

  group_importance_by_scheme =
    group_importance_by_scheme,

  feature_importance_by_scheme =
    feature_importance_by_scheme,

  group_cross_scale_summary =
    group_cross_scale_summary,

  feature_cross_scale_summary =
    feature_cross_scale_summary,

  feature_group_map =
    unique_feature_group_map
)

saveRDS(
  aggregate_results,
  file.path(
    out_dir,
    "aggregate_results.rds"
  ),
  version = 3
)

top_overall_groups <-
  group_cross_scale_summary |>
  dplyr::filter(
    evaluation_subset ==
      "all"
  ) |>
  dplyr::group_by(
    model_name
  ) |>
  dplyr::slice_min(
    cross_scale_rank,
    n = 1,
    with_ties = FALSE
  ) |>
  dplyr::ungroup() |>
  dplyr::arrange(
    model_name
  )

top_group_lines <- paste0(
  top_overall_groups$model_name,
  ": ",
  top_overall_groups$entity_name,
  " (",
  top_overall_groups$total_folds_positive,
  "/",
  top_overall_groups$total_outer_folds,
  " positive folds)"
)

summary_lines <- c(
  "R53 HELD-OUT PERMUTATION IMPORTANCE AGGREGATION",
  "================================================",
  "",
  paste0(
    "Completed tasks: ",
    sum(
      completion_audit$status_passed
    ),
    " / 45"
  ),
  paste0(
    "Tasks reproducing R52 predictions: ",
    sum(
      completion_audit$
        reproduction_passed
    ),
    " / 45"
  ),
  paste0(
    "Maximum reproduction difference: ",
    max(
      completion_audit$
        maximum_reproduction_difference
    )
  ),
  "",
  "TOP OVERALL MECHANISM GROUP BY MODEL:",
  top_group_lines,
  "",
  "INTERPRETATION RULES:",
  paste(
    "Mechanism-group importance is primary;",
    "single-feature importance is supplementary."
  ),
  paste(
    "Cross-scale summaries describe robustness",
    "across blocking schemes."
  ),
  paste(
    "Negative importance does not trigger predictor deletion;",
    "correlated predictors can substitute for each other."
  ),
  "",
  "STATUS: ALL R53 AGGREGATION INVARIANTS PASSED"
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
