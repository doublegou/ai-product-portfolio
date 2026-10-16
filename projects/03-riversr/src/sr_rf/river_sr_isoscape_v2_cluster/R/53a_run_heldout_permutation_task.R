source("R/functions/core.R")

check_packages(
  c(
    "dplyr",
    "readr",
    "tibble",
    "ranger"
  )
)

root <- project_root()

architecture_dir <- file.path(
  root,
  "outputs",
  "r50b_feature_architecture"
)

validation_dir <- file.path(
  root,
  "outputs",
  "r51a_validation_design"
)

r52_dir <- file.path(
  root,
  "outputs",
  "r52_nested_spatial_rf"
)

out_root <- file.path(
  root,
  "outputs",
  "r53_heldout_permutation",
  "tasks"
)

manifest_file <- file.path(
  r52_dir,
  "task_manifest.csv"
)

model_table_file <- file.path(
  architecture_dir,
  "integrated_model_table.rds"
)

feature_sets_file <- file.path(
  architecture_dir,
  "model_feature_sets.rds"
)

validation_file <- file.path(
  validation_dir,
  "validation_design.rds"
)

task_id_text <- Sys.getenv(
  "R53_TASK_ID",
  unset = Sys.getenv(
    "SLURM_ARRAY_TASK_ID",
    unset = ""
  )
)

task_id <- suppressWarnings(
  as.integer(task_id_text)
)

if (
  is.na(task_id) ||
  task_id < 1L ||
  task_id > 45L
) {
  stop(
    "Set R53_TASK_ID or SLURM_ARRAY_TASK_ID to an integer from 1 to 45."
  )
}

threads <- suppressWarnings(
  as.integer(
    Sys.getenv(
      "R53_THREADS",
      unset = Sys.getenv(
        "SLURM_CPUS_PER_TASK",
        unset = "4"
      )
    )
  )
)

if (
  is.na(threads) ||
  threads < 1L
) {
  threads <- 1L
}

n_repeats <- suppressWarnings(
  as.integer(
    Sys.getenv(
      "R53_REPEATS",
      unset = "10"
    )
  )
)

if (
  is.na(n_repeats) ||
  n_repeats < 2L
) {
  stop(
    "R53_REPEATS must be at least 2."
  )
}

required_files <- c(
  manifest_file,
  model_table_file,
  feature_sets_file,
  validation_file
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

manifest <- readr::read_csv(
  manifest_file,
  show_col_types = FALSE
)

task <- manifest |>
  dplyr::filter(
    task_id ==
      .env$task_id
  )

if (nrow(task) != 1L) {
  stop(
    "Task manifest did not resolve to exactly one task."
  )
}

task_label <-
  task$task_label[[1]]

validation_scheme <-
  task$validation_scheme[[1]]

outer_fold_id <-
  as.integer(
    task$outer_fold[[1]]
  )

model_name <-
  task$model_name[[1]]

r52_task_dir <- file.path(
  r52_dir,
  "tasks",
  sprintf(
    "task_%03d__%s",
    task_id,
    task_label
  )
)

out_dir <- file.path(
  out_root,
  sprintf(
    "task_%03d__%s",
    task_id,
    task_label
  )
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

selected_file <- file.path(
  r52_task_dir,
  "selected_hyperparameters.csv"
)

stored_predictions_file <- file.path(
  r52_task_dir,
  "outer_predictions.csv"
)

metadata_file <- file.path(
  r52_task_dir,
  "task_metadata.rds"
)

required_task_files <- c(
  selected_file,
  stored_predictions_file,
  metadata_file
)

missing_task_files <- required_task_files[
  !file.exists(required_task_files)
]

if (length(missing_task_files) > 0L) {
  stop(
    "Missing R52 task files: ",
    paste(
      missing_task_files,
      collapse = ", "
    )
  )
}

dat <- as.data.frame(
  readRDS(model_table_file)
)

dat$row_id <- as.character(
  dat$row_id
)

feature_sets <- readRDS(
  feature_sets_file
)

validation_design <- readRDS(
  validation_file
)

selected <- readr::read_csv(
  selected_file,
  show_col_types = FALSE
)

stored_predictions <- readr::read_csv(
  stored_predictions_file,
  show_col_types = FALSE
)

stored_predictions$row_id <- as.character(
  stored_predictions$row_id
)

metadata <- readRDS(
  metadata_file
)

features <- feature_sets[[
  model_name
]]

if (is.null(features)) {
  stop(
    "Unknown model feature set: ",
    model_name
  )
}

if (
  length(features) !=
    task$n_features[[1]]
) {
  stop(
    "Feature count differs from the frozen task manifest."
  )
}

missing_features <- setdiff(
  features,
  names(dat)
)

if (length(missing_features) > 0L) {
  stop(
    "Integrated table lacks features: ",
    paste(
      missing_features,
      collapse = ", "
    )
  )
}

if (
  !identical(
    as.character(
      metadata$features
    ),
    as.character(
      features
    )
  )
) {
  stop(
    "R52 metadata features differ from the frozen feature set."
  )
}

# ==============================================================================
# Recover the frozen outer training and test rows
# ==============================================================================

outer_design <- validation_design$
  outer_spatial |>
  dplyr::filter(
    validation_scheme ==
      .env$validation_scheme
  )

outer_test_ids <- outer_design |>
  dplyr::filter(
    outer_fold ==
      .env$outer_fold_id
  ) |>
  dplyr::pull(
    row_id
  ) |>
  as.character()

outer_train_ids <- setdiff(
  dat$row_id,
  outer_test_ids
)

if (
  length(intersect(
    outer_train_ids,
    outer_test_ids
  )) > 0L
) {
  stop(
    "Outer training and test rows overlap."
  )
}

if (
  length(
    union(
      outer_train_ids,
      outer_test_ids
    )
  ) !=
    nrow(dat)
) {
  stop(
    "Outer training and test IDs do not cover the full dataset."
  )
}

train_rows <- dat[
  match(
    outer_train_ids,
    dat$row_id
  ),
  ,
  drop = FALSE
]

test_rows <- dat[
  match(
    outer_test_ids,
    dat$row_id
  ),
  ,
  drop = FALSE
]

make_numeric_predictors <- function(
  data,
  feature_names
) {
  result <- data[
    feature_names
  ]

  non_numeric <- feature_names[
    !vapply(
      result,
      is.numeric,
      logical(1)
    )
  ]

  if (length(non_numeric) > 0L) {
    stop(
      "Non-numeric predictors: ",
      paste(
        non_numeric,
        collapse = ", "
      )
    )
  }

  result
}

fit_medians <- function(x) {
  medians <- vapply(
    x,
    function(column) {
      if (all(is.na(column))) {
        return(NA_real_)
      }

      stats::median(
        column,
        na.rm = TRUE
      )
    },
    numeric(1)
  )

  if (anyNA(medians)) {
    stop(
      "A predictor is entirely missing in the outer training data: ",
      paste(
        names(medians)[
          is.na(medians)
        ],
        collapse = ", "
      )
    )
  }

  medians
}

apply_medians <- function(
  x,
  medians
) {
  result <- x

  for (feature in names(medians)) {
    missing <- is.na(
      result[[feature]]
    )

    if (any(missing)) {
      result[[feature]][missing] <-
        medians[[feature]]
    }
  }

  if (anyNA(result)) {
    stop(
      "Missing predictor values remain after training-fold imputation."
    )
  }

  result
}

x_train_raw <- make_numeric_predictors(
  train_rows,
  features
)

x_test_raw <- make_numeric_predictors(
  test_rows,
  features
)

training_medians <- fit_medians(
  x_train_raw
)

x_train <- apply_medians(
  x_train_raw,
  training_medians
)

x_test <- apply_medians(
  x_test_raw,
  training_medians
)

# ==============================================================================
# Refit the outer model exactly as in R52
# ==============================================================================

outer_trees <- as.integer(
  metadata$outer_trees
)

seed_base <- as.integer(
  metadata$seed_base
)

outer_seed <-
  seed_base +
  task_id * 1000L +
  999L

model <- ranger::ranger(
  x =
    x_train,

  y =
    train_rows$sr87_sr86,

  num.trees =
    outer_trees,

  mtry =
    as.integer(
      selected$mtry[[1]]
    ),

  min.node.size =
    as.integer(
      selected$min_node_size[[1]]
    ),

  sample.fraction =
    as.numeric(
      selected$sample_fraction[[1]]
    ),

  replace =
    FALSE,

  splitrule =
    "variance",

  importance =
    "none",

  num.threads =
    threads,

  seed =
    outer_seed,

  write.forest =
    TRUE,

  verbose =
    FALSE
)

baseline_prediction <- predict(
  model,
  data =
    x_test,

  num.threads =
    threads
)$predictions |>
  as.numeric()

stored_index <- match(
  test_rows$row_id,
  stored_predictions$row_id
)

if (anyNA(stored_index)) {
  stop(
    "Stored R52 predictions do not contain every outer test row."
  )
}

stored_prediction_aligned <-
  stored_predictions$
    predicted_sr[
      stored_index
    ]

maximum_prediction_difference <- max(
  abs(
    baseline_prediction -
      stored_prediction_aligned
  )
)

baseline_reproduction <- tibble::tibble(
  task_id =
    task_id,

  task_label =
    task_label,

  validation_scheme =
    validation_scheme,

  outer_fold =
    outer_fold_id,

  model_name =
    model_name,

  n_test =
    nrow(test_rows),

  maximum_absolute_difference =
    maximum_prediction_difference,

  correlation =
    stats::cor(
      baseline_prediction,
      stored_prediction_aligned
    ),

  tolerance =
    1e-8,

  reproduction_passed =
    maximum_prediction_difference <=
      1e-8
)

readr::write_csv(
  baseline_reproduction,
  file.path(
    out_dir,
    "baseline_reproduction.csv"
  )
)

if (
  !baseline_reproduction$
    reproduction_passed[[1]]
) {
  stop(
    "Refitted predictions do not reproduce R52 within tolerance. ",
    "Maximum difference: ",
    maximum_prediction_difference
  )
}

# ==============================================================================
# Evaluation subsets and metrics
# ==============================================================================

subset_definitions <- list(
  all =
    rep(
      TRUE,
      nrow(test_rows)
    ),

  ge_072 =
    test_rows$sr87_sr86 >=
      0.72,

  ge_075 =
    test_rows$sr87_sr86 >=
      0.75,

  ge_080 =
    test_rows$sr87_sr86 >=
      0.80
)

calculate_basic_metrics <- function(
  observed,
  predicted
) {
  valid <-
    is.finite(observed) &
    is.finite(predicted)

  observed <- observed[
    valid
  ]

  predicted <- predicted[
    valid
  ]

  if (length(observed) == 0L) {
    return(
      tibble::tibble(
        n = 0L,
        mse = NA_real_,
        rmse = NA_real_,
        mae = NA_real_,
        bias = NA_real_
      )
    )
  }

  residual <-
    predicted -
    observed

  tibble::tibble(
    n =
      length(observed),

    mse =
      mean(
        residual^2
      ),

    rmse =
      sqrt(
        mean(
          residual^2
        )
      ),

    mae =
      mean(
        abs(residual)
      ),

    bias =
      mean(residual)
  )
}

calculate_subset_metrics <- function(
  observed,
  predicted
) {
  dplyr::bind_rows(
    lapply(
      names(
        subset_definitions
      ),
      function(subset_name) {
        keep <- subset_definitions[[
          subset_name
        ]]

        dplyr::bind_cols(
          tibble::tibble(
            evaluation_subset =
              subset_name
          ),

          calculate_basic_metrics(
            observed[
              keep
            ],
            predicted[
              keep
            ]
          )
        )
      }
    )
  )
}

baseline_metrics <- calculate_subset_metrics(
  test_rows$sr87_sr86,
  baseline_prediction
)

readr::write_csv(
  baseline_metrics,
  file.path(
    out_dir,
    "baseline_metrics.csv"
  )
)

# ==============================================================================
# Prespecified mechanism groups
# ==============================================================================

classify_feature_group <- function(feature) {
  if (
    grepl(
      "^p0__sp_[xyz]$",
      feature
    )
  ) {
    return(
      "spatial_coordinates"
    )
  }

  if (
    grepl(
      "^p0__(log_|ORD_)",
      feature
    )
  ) {
    return(
      "river_network_hydrology"
    )
  }

  if (
    grepl(
      "^p0__up_geo_",
      feature
    )
  ) {
    return(
      "upstream_lithology"
    )
  }

  if (
    grepl(
      "^p0__up_bio",
      feature
    ) ||
    feature %in%
      c(
        "p0__up_ai_ratio",
        "p0__up_et0_mm"
      )
  ) {
    return(
      "upstream_climate_aridity"
    )
  }

  if (
    feature ==
      "p0__up_elevation_m"
  ) {
    return(
      "upstream_topography"
    )
  }

  if (
    feature ==
      "p0__up_soil_clay_pct_0_30cm"
  ) {
    return(
      "upstream_soil"
    )
  }

  if (
    grepl(
      "^r47__local_geo_|^r50__local_",
      feature
    )
  ) {
    return(
      "local_lithology"
    )
  }

  if (
    grepl(
      "^local_geo_age_|^local_geo_frac_",
      feature
    )
  ) {
    return(
      "local_geological_age"
    )
  }

  if (
    grepl(
      "^up_geo_age_|^up_geo_frac_",
      feature
    )
  ) {
    return(
      "upstream_geological_age"
    )
  }

  if (
    feature ==
      "m1a__lith_entropy_norm"
  ) {
    return(
      "lithological_diversity"
    )
  }

  if (
    grepl(
      "^p1r__local_soil_",
      feature
    )
  ) {
    return(
      "local_soil"
    )
  }

  if (
    feature ==
      "p1r__up_soil_pH_0_30cm"
  ) {
    return(
      "upstream_soil"
    )
  }

  if (
    feature ==
      "p1r__local_elevation_m"
  ) {
    return(
      "local_topography"
    )
  }

  "unclassified"
}

feature_group_map <- tibble::tibble(
  feature =
    features,

  feature_group =
    vapply(
      features,
      classify_feature_group,
      character(1)
    )
)

unclassified_features <- feature_group_map |>
  dplyr::filter(
    feature_group ==
      "unclassified"
  )

if (nrow(unclassified_features) > 0L) {
  readr::write_csv(
    unclassified_features,
    file.path(
      out_dir,
      "unclassified_features.csv"
    )
  )

  stop(
    "One or more predictors lack a prespecified mechanism group."
  )
}

readr::write_csv(
  feature_group_map,
  file.path(
    out_dir,
    "feature_group_map.csv"
  )
)

# ==============================================================================
# Permutation helper
# ==============================================================================

create_permutation_record <- function(
  entity_type,
  entity_name,
  feature_group,
  repeat_id,
  permutation_seed,
  permuted_prediction
) {
  permuted_metrics <- calculate_subset_metrics(
    test_rows$sr87_sr86,
    permuted_prediction
  )

  permuted_metrics |>
    dplyr::left_join(
      baseline_metrics |>
        dplyr::rename(
          baseline_n =
            n,

          baseline_mse =
            mse,

          baseline_rmse =
            rmse,

          baseline_mae =
            mae,

          baseline_bias =
            bias
        ),
      by =
        "evaluation_subset"
    ) |>
    dplyr::mutate(
      task_id =
        task_id,

      task_label =
        task_label,

      validation_scheme =
        validation_scheme,

      outer_fold =
        outer_fold_id,

      model_name =
        model_name,

      entity_type =
        entity_type,

      entity_name =
        entity_name,

      feature_group =
        feature_group,

      repeat_id =
        repeat_id,

      permutation_seed =
        permutation_seed,

      delta_mse =
        mse -
        baseline_mse,

      relative_delta_mse =
        dplyr::if_else(
          is.finite(
            baseline_mse
          ) &
          baseline_mse >
            0,

          delta_mse /
            baseline_mse,

          NA_real_
        ),

      delta_rmse =
        rmse -
        baseline_rmse,

      delta_mae =
        mae -
        baseline_mae,

      delta_bias =
        bias -
        baseline_bias
    ) |>
    dplyr::relocate(
      task_id,
      task_label,
      validation_scheme,
      outer_fold,
      model_name,
      entity_type,
      entity_name,
      feature_group,
      repeat_id,
      permutation_seed,
      evaluation_subset
    )
}

# ==============================================================================
# Single-feature permutation importance
# ==============================================================================

feature_records <- list()
record_index <- 0L

for (
  feature_index in seq_along(
    features
  )
) {
  feature <- features[[
    feature_index
  ]]

  feature_group <- feature_group_map$
    feature_group[
      feature_group_map$
        feature ==
        feature
    ][[1]]

  for (
    repeat_id in seq_len(
      n_repeats
    )
  ) {
    permutation_seed <-
      530000L +
      task_id * 100000L +
      feature_index * 100L +
      repeat_id

    set.seed(
      permutation_seed
    )

    permutation_index <- sample.int(
      nrow(x_test),
      replace = FALSE
    )

    x_permuted <- x_test

    x_permuted[[feature]] <-
      x_test[[feature]][
        permutation_index
      ]

    permuted_prediction <- predict(
      model,
      data =
        x_permuted,

      num.threads =
        threads
    )$predictions |>
      as.numeric()

    record_index <-
      record_index +
      1L

    feature_records[[
      record_index
    ]] <- create_permutation_record(
      entity_type =
        "single_feature",

      entity_name =
        feature,

      feature_group =
        feature_group,

      repeat_id =
        repeat_id,

      permutation_seed =
        permutation_seed,

      permuted_prediction =
        permuted_prediction
    )
  }
}

feature_repeat_results <- dplyr::bind_rows(
  feature_records
)

feature_summary <- feature_repeat_results |>
  dplyr::group_by(
    task_id,
    task_label,
    validation_scheme,
    outer_fold,
    model_name,
    entity_name,
    feature_group,
    evaluation_subset
  ) |>
  dplyr::summarise(
    n_repeats =
      dplyr::n(),

    evaluation_n =
      dplyr::first(
        baseline_n
      ),

    baseline_mse =
      dplyr::first(
        baseline_mse
      ),

    mean_delta_mse =
      mean(
        delta_mse,
        na.rm = TRUE
      ),

    sd_delta_mse =
      stats::sd(
        delta_mse,
        na.rm = TRUE
      ),

    median_delta_mse =
      stats::median(
        delta_mse,
        na.rm = TRUE
      ),

    mean_relative_delta_mse =
      mean(
        relative_delta_mse,
        na.rm = TRUE
      ),

    mean_delta_rmse =
      mean(
        delta_rmse,
        na.rm = TRUE
      ),

    mean_delta_mae =
      mean(
        delta_mae,
        na.rm = TRUE
      ),

    positive_importance_fraction =
      mean(
        delta_mse >
          0,
        na.rm = TRUE
      ),

    .groups = "drop"
  ) |>
  dplyr::group_by(
    evaluation_subset
  ) |>
  dplyr::arrange(
    dplyr::desc(
      mean_delta_mse
    ),
    .by_group = TRUE
  ) |>
  dplyr::mutate(
    importance_rank =
      dplyr::row_number()
  ) |>
  dplyr::ungroup()

# ==============================================================================
# Mechanism-group permutation importance
# ==============================================================================

feature_groups <- split(
  feature_group_map$feature,
  feature_group_map$feature_group
)

group_records <- list()
record_index <- 0L

for (
  group_index in seq_along(
    feature_groups
  )
) {
  group_name <- names(
    feature_groups
  )[[group_index]]

  group_features <- feature_groups[[
    group_index
  ]]

  for (
    repeat_id in seq_len(
      n_repeats
    )
  ) {
    permutation_seed <-
      540000L +
      task_id * 100000L +
      group_index * 100L +
      repeat_id

    set.seed(
      permutation_seed
    )

    permutation_index <- sample.int(
      nrow(x_test),
      replace = FALSE
    )

    x_permuted <- x_test

    x_permuted[
      group_features
    ] <- x_test[
      permutation_index,
      group_features,
      drop = FALSE
    ]

    permuted_prediction <- predict(
      model,
      data =
        x_permuted,

      num.threads =
        threads
    )$predictions |>
      as.numeric()

    record_index <-
      record_index +
      1L

    group_records[[
      record_index
    ]] <- create_permutation_record(
      entity_type =
        "mechanism_group",

      entity_name =
        group_name,

      feature_group =
        group_name,

      repeat_id =
        repeat_id,

      permutation_seed =
        permutation_seed,

      permuted_prediction =
        permuted_prediction
    )
  }
}

group_repeat_results <- dplyr::bind_rows(
  group_records
)

group_summary <- group_repeat_results |>
  dplyr::group_by(
    task_id,
    task_label,
    validation_scheme,
    outer_fold,
    model_name,
    entity_name,
    evaluation_subset
  ) |>
  dplyr::summarise(
    n_group_features =
      length(
        feature_groups[[
          dplyr::first(
            entity_name
          )
        ]]
      ),

    n_repeats =
      dplyr::n(),

    evaluation_n =
      dplyr::first(
        baseline_n
      ),

    baseline_mse =
      dplyr::first(
        baseline_mse
      ),

    mean_delta_mse =
      mean(
        delta_mse,
        na.rm = TRUE
      ),

    sd_delta_mse =
      stats::sd(
        delta_mse,
        na.rm = TRUE
      ),

    median_delta_mse =
      stats::median(
        delta_mse,
        na.rm = TRUE
      ),

    mean_relative_delta_mse =
      mean(
        relative_delta_mse,
        na.rm = TRUE
      ),

    mean_delta_rmse =
      mean(
        delta_rmse,
        na.rm = TRUE
      ),

    mean_delta_mae =
      mean(
        delta_mae,
        na.rm = TRUE
      ),

    positive_importance_fraction =
      mean(
        delta_mse >
          0,
        na.rm = TRUE
      ),

    .groups = "drop"
  ) |>
  dplyr::group_by(
    evaluation_subset
  ) |>
  dplyr::arrange(
    dplyr::desc(
      mean_delta_mse
    ),
    .by_group = TRUE
  ) |>
  dplyr::mutate(
    importance_rank =
      dplyr::row_number()
  ) |>
  dplyr::ungroup()

# ==============================================================================
# Save task outputs
# ==============================================================================

readr::write_csv(
  feature_repeat_results,
  file.path(
    out_dir,
    "feature_permutation_repeats.csv"
  )
)

readr::write_csv(
  feature_summary,
  file.path(
    out_dir,
    "feature_permutation_summary.csv"
  )
)

readr::write_csv(
  group_repeat_results,
  file.path(
    out_dir,
    "group_permutation_repeats.csv"
  )
)

readr::write_csv(
  group_summary,
  file.path(
    out_dir,
    "group_permutation_summary.csv"
  )
)

task_metadata <- list(
  task =
    task,

  features =
    features,

  feature_group_map =
    feature_group_map,

  selected_hyperparameters =
    selected,

  n_repeats =
    n_repeats,

  outer_trees =
    outer_trees,

  outer_seed =
    outer_seed,

  maximum_prediction_difference =
    maximum_prediction_difference,

  completed_at =
    as.character(
      Sys.time()
    )
)

saveRDS(
  task_metadata,
  file.path(
    out_dir,
    "task_metadata.rds"
  ),
  version = 3
)

top_group <- group_summary |>
  dplyr::filter(
    evaluation_subset ==
      "all"
  ) |>
  dplyr::slice_min(
    importance_rank,
    n = 1,
    with_ties = FALSE
  )

top_feature <- feature_summary |>
  dplyr::filter(
    evaluation_subset ==
      "all"
  ) |>
  dplyr::slice_min(
    importance_rank,
    n = 1,
    with_ties = FALSE
  )

summary_lines <- c(
  "R53 HELD-OUT PERMUTATION IMPORTANCE TASK",
  "========================================",
  "",
  paste0(
    "Task ID: ",
    task_id
  ),
  paste0(
    "Task label: ",
    task_label
  ),
  paste0(
    "Model: ",
    model_name
  ),
  paste0(
    "Outer test rows: ",
    nrow(test_rows)
  ),
  paste0(
    "Features: ",
    length(features)
  ),
  paste0(
    "Mechanism groups: ",
    length(feature_groups)
  ),
  paste0(
    "Permutation repeats: ",
    n_repeats
  ),
  paste0(
    "Maximum reproduction difference: ",
    maximum_prediction_difference
  ),
  "",
  paste0(
    "Top mechanism group: ",
    top_group$entity_name[[1]]
  ),
  paste0(
    "Top mechanism-group mean delta MSE: ",
    top_group$mean_delta_mse[[1]]
  ),
  paste0(
    "Top individual feature: ",
    top_feature$entity_name[[1]]
  ),
  paste0(
    "Top individual-feature mean delta MSE: ",
    top_feature$mean_delta_mse[[1]]
  ),
  "",
  paste(
    "Mechanism-group importance is the primary interpretation;",
    "single-feature importance is supplementary."
  ),
  "",
  "STATUS: R53 HELD-OUT PERMUTATION TASK PASSED"
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
