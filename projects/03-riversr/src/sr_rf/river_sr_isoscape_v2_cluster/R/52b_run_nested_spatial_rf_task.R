source("R/functions/core.R")

check_packages(
  c(
    "dplyr",
    "readr",
    "tibble",
    "tidyr",
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

out_root <- file.path(
  root,
  "outputs",
  "r52_nested_spatial_rf",
  "tasks"
)

manifest_file <- file.path(
  root,
  "outputs",
  "r52_nested_spatial_rf",
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

task_id_text <- Sys.getenv(
  "R52_TASK_ID",
  unset = Sys.getenv(
    "SLURM_ARRAY_TASK_ID",
    unset = ""
  )
)

task_id <- suppressWarnings(
  as.integer(
    task_id_text
  )
)

if (
  is.na(task_id) ||
  task_id < 1L
) {
  stop(
    "Set R52_TASK_ID or SLURM_ARRAY_TASK_ID to a valid task number."
  )
}

threads <- suppressWarnings(
  as.integer(
    Sys.getenv(
      "R52_THREADS",
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

inner_trees <- suppressWarnings(
  as.integer(
    Sys.getenv(
      "R52_INNER_TREES",
      unset = "500"
    )
  )
)

outer_trees <- suppressWarnings(
  as.integer(
    Sys.getenv(
      "R52_OUTER_TREES",
      unset = "1500"
    )
  )
)

seed_base <- suppressWarnings(
  as.integer(
    Sys.getenv(
      "R52_SEED_BASE",
      unset = "520000"
    )
  )
)

if (
  is.na(inner_trees) ||
  inner_trees < 100L
) {
  stop(
    "R52_INNER_TREES must be at least 100."
  )
}

if (
  is.na(outer_trees) ||
  outer_trees < 100L
) {
  stop(
    "R52_OUTER_TREES must be at least 100."
  )
}

task_manifest <- readr::read_csv(
  manifest_file,
  show_col_types = FALSE
)

if (!task_id %in% task_manifest$task_id) {
  stop(
    "Task ID is outside the manifest: ",
    task_id
  )
}

task <- task_manifest |>
  dplyr::filter(
    task_id ==
      .env$task_id
  )

if (nrow(task) != 1L) {
  stop(
    "Task manifest did not resolve to exactly one task."
  )
}

validation_scheme <-
  task$validation_scheme[[1]]

outer_fold_id <-
  as.integer(
    task$outer_fold[[1]]
  )

model_name <-
  task$model_name[[1]]

task_label <-
  task$task_label[[1]]

task_dir <- file.path(
  out_root,
  sprintf(
    "task_%03d__%s",
    task_id,
    task_label
  )
)

dir.create(
  task_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

dat <- as.data.frame(
  readRDS(
    model_table_file
  )
)

feature_sets <- readRDS(
  feature_sets_file
)

validation_design <- readRDS(
  validation_file
)

dat$row_id <- as.character(
  dat$row_id
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
    "Feature count differs from task manifest."
  )
}

missing_features <- setdiff(
  features,
  names(dat)
)

if (length(missing_features) > 0L) {
  stop(
    "Model table lacks features: ",
    paste(
      missing_features,
      collapse = ", "
    )
  )
}

if (
  !"sr87_sr86" %in%
    names(dat)
) {
  stop(
    "Outcome sr87_sr86 is absent."
  )
}

outer_design <- validation_design$
  outer_spatial |>
  dplyr::filter(
    validation_scheme ==
      .env$validation_scheme
  )

inner_design <- validation_design$
  inner_spatial |>
  dplyr::filter(
    validation_scheme ==
      .env$validation_scheme,

    outer_fold ==
      .env$outer_fold_id
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
    "Outer train and test rows overlap."
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
    "Outer train and test rows do not cover the full dataset."
  )
}

if (
  anyDuplicated(
    inner_design$row_id
  )
) {
  stop(
    "Inner-design row IDs are duplicated within this outer fold."
  )
}

if (
  !setequal(
    as.character(
      inner_design$row_id
    ),
    outer_train_ids
  )
) {
  stop(
    "Inner-design rows do not equal the outer-training rows."
  )
}

inner_fold_values <- sort(
  unique(
    as.integer(
      inner_design$inner_fold
    )
  )
)

if (!identical(
  inner_fold_values,
  1:3
)) {
  stop(
    "Expected inner folds 1:3."
  )
}

make_numeric_matrix <- function(
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
      "Non-numeric model predictors: ",
      paste(
        non_numeric,
        collapse = ", "
      )
    )
  }

  result
}

fit_imputation_values <- function(
  x
) {
  medians <- vapply(
    x,
    function(column) {
      if (all(is.na(column))) {
        return(
          NA_real_
        )
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
      "At least one feature is entirely missing in a training fold: ",
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

apply_imputation <- function(
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
      "Missing values remain after imputation."
    )
  }

  result
}

calculate_metrics <- function(
  observed,
  predicted
) {
  observed <- as.numeric(
    observed
  )

  predicted <- as.numeric(
    predicted
  )

  valid <-
    is.finite(observed) &
    is.finite(predicted)

  observed <- observed[
    valid
  ]

  predicted <- predicted[
    valid
  ]

  n <- length(observed)

  if (n == 0L) {
    return(
      tibble::tibble(
        n = 0L,
        rmse = NA_real_,
        mae = NA_real_,
        r2 = NA_real_,
        bias = NA_real_,
        calibration_intercept = NA_real_,
        calibration_slope = NA_real_,
        observed_mean = NA_real_,
        predicted_mean = NA_real_,
        predicted_min = NA_real_,
        predicted_max = NA_real_,
        predicted_range = NA_real_,
        underprediction_fraction = NA_real_
      )
    )
  }

  residual <-
    predicted -
    observed

  denominator <- sum(
    (
      observed -
        mean(observed)
    )^2
  )

  r2 <- if (
    denominator <= 0
  ) {
    NA_real_
  } else {
    1 -
      sum(
        residual^2
      ) /
      denominator
  }

  calibration <- if (
    n >= 3L &&
    dplyr::n_distinct(
      predicted
    ) >= 2L
  ) {
    stats::coef(
      stats::lm(
        observed ~
          predicted
      )
    )
  } else {
    c(
      `(Intercept)` =
        NA_real_,

      predicted =
        NA_real_
    )
  }

  tibble::tibble(
    n = n,

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

    r2 =
      r2,

    bias =
      mean(residual),

    calibration_intercept =
      unname(
        calibration[[1]]
      ),

    calibration_slope =
      unname(
        calibration[[2]]
      ),

    observed_mean =
      mean(observed),

    predicted_mean =
      mean(predicted),

    predicted_min =
      min(predicted),

    predicted_max =
      max(predicted),

    predicted_range =
      max(predicted) -
      min(predicted),

    underprediction_fraction =
      mean(
        predicted <
          observed
      )
  )
}

calculate_threshold_metrics <- function(
  observed,
  predicted
) {
  threshold_table <- tibble::tribble(
    ~evaluation_subset,
    ~threshold,

    "all",
    -Inf,

    "ge_072",
    0.72,

    "ge_075",
    0.75,

    "ge_080",
    0.80
  )

  dplyr::bind_rows(
    lapply(
      seq_len(
        nrow(
          threshold_table
        )
      ),
      function(i) {
        threshold <-
          threshold_table$
            threshold[[i]]

        keep <- if (
          is.infinite(
            threshold
          )
        ) {
          rep(
            TRUE,
            length(observed)
          )
        } else {
          observed >=
            threshold
        }

        dplyr::bind_cols(
          threshold_table[
            i,
            ,
            drop = FALSE
          ],
          calculate_metrics(
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

p <- length(features)

mtry_values <- sort(
  unique(
    pmax(
      1L,
      pmin(
        p,
        as.integer(
          round(
            c(
              sqrt(p),
              p / 4,
              p / 2
            )
          )
        )
      )
    )
  )
)

tuning_grid <- tidyr::expand_grid(
  mtry =
    mtry_values,

  min_node_size =
    c(
      5L,
      15L
    ),

  sample_fraction =
    c(
      0.70,
      1.00
    )
) |>
  dplyr::mutate(
    grid_id =
      dplyr::row_number()
  ) |>
  dplyr::relocate(
    grid_id
  )

readr::write_csv(
  tuning_grid,
  file.path(
    task_dir,
    "tuning_grid.csv"
  )
)

inner_metric_records <- list()
record_index <- 0L

for (
  grid_row in seq_len(
    nrow(tuning_grid)
  )
) {
  hyperparameters <-
    tuning_grid[
      grid_row,
      ,
      drop = FALSE
    ]

  for (
    inner_fold_id in 1:3
  ) {
    inner_validation_ids <-
      inner_design |>
      dplyr::filter(
        inner_fold ==
          .env$inner_fold_id
      ) |>
      dplyr::pull(
        row_id
      ) |>
      as.character()

    inner_analysis_ids <- setdiff(
      outer_train_ids,
      inner_validation_ids
    )

    analysis_rows <- dat[
      match(
        inner_analysis_ids,
        dat$row_id
      ),
      ,
      drop = FALSE
    ]

    validation_rows <- dat[
      match(
        inner_validation_ids,
        dat$row_id
      ),
      ,
      drop = FALSE
    ]

    x_analysis <- make_numeric_matrix(
      analysis_rows,
      features
    )

    x_validation <- make_numeric_matrix(
      validation_rows,
      features
    )

    imputation_values <-
      fit_imputation_values(
        x_analysis
      )

    x_analysis <- apply_imputation(
      x_analysis,
      imputation_values
    )

    x_validation <- apply_imputation(
      x_validation,
      imputation_values
    )

    fit_seed <-
      seed_base +
      task_id * 1000L +
      hyperparameters$
        grid_id[[1]] *
        10L +
      inner_fold_id

    model <- ranger::ranger(
      x =
        x_analysis,

      y =
        analysis_rows$
          sr87_sr86,

      num.trees =
        inner_trees,

      mtry =
        as.integer(
          hyperparameters$
            mtry[[1]]
        ),

      min.node.size =
        as.integer(
          hyperparameters$
            min_node_size[[1]]
        ),

      sample.fraction =
        as.numeric(
          hyperparameters$
            sample_fraction[[1]]
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
        fit_seed,

      write.forest =
        TRUE,

      verbose =
        FALSE
    )

    prediction <- predict(
      model,
      data =
        x_validation,

      num.threads =
        threads
    )$predictions

    record_index <-
      record_index +
      1L

    inner_metric_records[[
      record_index
    ]] <- dplyr::bind_cols(
      tibble::tibble(
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

        grid_id =
          hyperparameters$
            grid_id[[1]],

        mtry =
          hyperparameters$
            mtry[[1]],

        min_node_size =
          hyperparameters$
            min_node_size[[1]],

        sample_fraction =
          hyperparameters$
            sample_fraction[[1]],

        inner_fold =
          inner_fold_id,

        n_analysis =
          nrow(
            analysis_rows
          ),

        n_validation =
          nrow(
            validation_rows
          ),

        seed =
          fit_seed
      ),

      calculate_metrics(
        validation_rows$
          sr87_sr86,

        prediction
      )
    )
  }
}

inner_fold_metrics <- dplyr::bind_rows(
  inner_metric_records
)

inner_grid_summary <- inner_fold_metrics |>
  dplyr::group_by(
    grid_id,
    mtry,
    min_node_size,
    sample_fraction
  ) |>
  dplyr::summarise(
    mean_rmse =
      mean(rmse),

    sd_rmse =
      stats::sd(rmse),

    mean_mae =
      mean(mae),

    mean_r2 =
      mean(
        r2,
        na.rm = TRUE
      ),

    mean_bias =
      mean(bias),

    mean_calibration_slope =
      mean(
        calibration_slope,
        na.rm = TRUE
      ),

    .groups = "drop"
  ) |>
  dplyr::arrange(
    mean_rmse,
    mean_mae,
    dplyr::desc(mean_r2),
    mtry,
    min_node_size,
    sample_fraction
  ) |>
  dplyr::mutate(
    tuning_rank =
      dplyr::row_number()
  )

selected_hyperparameters <-
  inner_grid_summary |>
  dplyr::slice(1) |>
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

    selection_rule =
      paste(
        "Minimum mean inner-fold RMSE;",
        "ties resolved by MAE, R2, mtry,",
        "min node size and sample fraction."
      )
  ) |>
  dplyr::relocate(
    task_id,
    task_label,
    validation_scheme,
    outer_fold,
    model_name
  )

readr::write_csv(
  inner_fold_metrics,
  file.path(
    task_dir,
    "inner_fold_metrics.csv"
  )
)

readr::write_csv(
  inner_grid_summary,
  file.path(
    task_dir,
    "inner_grid_summary.csv"
  )
)

readr::write_csv(
  selected_hyperparameters,
  file.path(
    task_dir,
    "selected_hyperparameters.csv"
  )
)

outer_analysis_rows <- dat[
  match(
    outer_train_ids,
    dat$row_id
  ),
  ,
  drop = FALSE
]

outer_test_rows <- dat[
  match(
    outer_test_ids,
    dat$row_id
  ),
  ,
  drop = FALSE
]

x_outer_analysis <- make_numeric_matrix(
  outer_analysis_rows,
  features
)

x_outer_test <- make_numeric_matrix(
  outer_test_rows,
  features
)

outer_imputation_values <-
  fit_imputation_values(
    x_outer_analysis
  )

x_outer_analysis <- apply_imputation(
  x_outer_analysis,
  outer_imputation_values
)

x_outer_test <- apply_imputation(
  x_outer_test,
  outer_imputation_values
)

outer_seed <-
  seed_base +
  task_id * 1000L +
  999L

final_model <- ranger::ranger(
  x =
    x_outer_analysis,

  y =
    outer_analysis_rows$
      sr87_sr86,

  num.trees =
    outer_trees,

  mtry =
    as.integer(
      selected_hyperparameters$
        mtry[[1]]
    ),

  min.node.size =
    as.integer(
      selected_hyperparameters$
        min_node_size[[1]]
    ),

  sample.fraction =
    as.numeric(
      selected_hyperparameters$
        sample_fraction[[1]]
    ),

  replace =
    FALSE,

  splitrule =
    "variance",

  importance =
    "permutation",

  num.threads =
    threads,

  seed =
    outer_seed,

  write.forest =
    TRUE,

  verbose =
    FALSE
)

outer_prediction <- predict(
  final_model,
  data =
    x_outer_test,

  num.threads =
    threads
)$predictions

outer_predictions <- tibble::tibble(
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

  row_id =
    outer_test_rows$
      row_id,

  site_id =
    outer_test_rows$
      site_id,

  longitude =
    outer_test_rows$
      longitude,

  latitude =
    outer_test_rows$
      latitude,

  geological_regime_primary =
    outer_test_rows$
      geological_regime_primary,

  observed_sr =
    outer_test_rows$
      sr87_sr86,

  predicted_sr =
    as.numeric(
      outer_prediction
    ),

  residual =
    as.numeric(
      outer_prediction
    ) -
    outer_test_rows$
      sr87_sr86,

  tail_ge_072 =
    outer_test_rows$
      sr87_sr86 >=
      0.72,

  tail_ge_075 =
    outer_test_rows$
      sr87_sr86 >=
      0.75,

  tail_ge_080 =
    outer_test_rows$
      sr87_sr86 >=
      0.80
)

outer_metrics <- calculate_threshold_metrics(
  outer_predictions$
    observed_sr,

  outer_predictions$
    predicted_sr
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

    mtry =
      selected_hyperparameters$
        mtry[[1]],

    min_node_size =
      selected_hyperparameters$
        min_node_size[[1]],

    sample_fraction =
      selected_hyperparameters$
        sample_fraction[[1]],

    outer_trees =
      outer_trees,

    seed =
      outer_seed
  ) |>
  dplyr::relocate(
    task_id,
    task_label,
    validation_scheme,
    outer_fold,
    model_name
  )

regime_metrics <- outer_predictions |>
  dplyr::group_by(
    geological_regime_primary
  ) |>
  dplyr::group_modify(
    function(
      .x,
      .y
    ) {
      calculate_metrics(
        .x$observed_sr,
        .x$predicted_sr
      )
    }
  ) |>
  dplyr::ungroup() |>
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
      model_name
  ) |>
  dplyr::relocate(
    task_id,
    task_label,
    validation_scheme,
    outer_fold,
    model_name
  )

feature_importance <- tibble::tibble(
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

  feature =
    names(
      final_model$
        variable.importance
    ),

  permutation_importance =
    as.numeric(
      final_model$
        variable.importance
    )
) |>
  dplyr::arrange(
    dplyr::desc(
      permutation_importance
    )
  )

imputation_table <- tibble::tibble(
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

  feature =
    names(
      outer_imputation_values
    ),

  training_median =
    as.numeric(
      outer_imputation_values
    ),

  n_missing_outer_train =
    vapply(
      x_outer_analysis[
        names(
          outer_imputation_values
        )
      ],
      function(x) {
        sum(
          is.na(x)
        )
      },
      integer(1)
    )
)

# Recalculate missingness from the unimputed source table.
imputation_table$n_missing_outer_train <-
  vapply(
    features,
    function(feature) {
      sum(
        is.na(
          outer_analysis_rows[[
            feature
          ]]
        )
      )
    },
    integer(1)
  )

readr::write_csv(
  outer_predictions,
  file.path(
    task_dir,
    "outer_predictions.csv"
  )
)

readr::write_csv(
  outer_metrics,
  file.path(
    task_dir,
    "outer_metrics.csv"
  )
)

readr::write_csv(
  regime_metrics,
  file.path(
    task_dir,
    "outer_regime_metrics.csv"
  )
)

readr::write_csv(
  feature_importance,
  file.path(
    task_dir,
    "feature_importance.csv"
  )
)

readr::write_csv(
  imputation_table,
  file.path(
    task_dir,
    "outer_training_imputation_values.csv"
  )
)

task_metadata <- list(
  task =
    task,

  features =
    features,

  tuning_grid =
    tuning_grid,

  selected_hyperparameters =
    selected_hyperparameters,

  n_outer_train =
    nrow(
      outer_analysis_rows
    ),

  n_outer_test =
    nrow(
      outer_test_rows
    ),

  inner_trees =
    inner_trees,

  outer_trees =
    outer_trees,

  threads =
    threads,

  seed_base =
    seed_base,

  completed_at =
    as.character(
      Sys.time()
    )
)

saveRDS(
  task_metadata,
  file.path(
    task_dir,
    "task_metadata.rds"
  ),
  version = 3
)

summary_lines <- c(
  "R52 NESTED SPATIAL RF TASK",
  "==========================",
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
    "Validation scheme: ",
    validation_scheme
  ),
  paste0(
    "Outer fold: ",
    outer_fold_id
  ),
  paste0(
    "Model: ",
    model_name
  ),
  paste0(
    "Features: ",
    length(features)
  ),
  paste0(
    "Outer training rows: ",
    nrow(
      outer_analysis_rows
    )
  ),
  paste0(
    "Outer test rows: ",
    nrow(
      outer_test_rows
    )
  ),
  paste0(
    "Tuning combinations: ",
    nrow(
      tuning_grid
    )
  ),
  paste0(
    "Inner forests fitted: ",
    nrow(
      tuning_grid
    ) * 3L
  ),
  paste0(
    "Selected mtry: ",
    selected_hyperparameters$
      mtry[[1]]
  ),
  paste0(
    "Selected min.node.size: ",
    selected_hyperparameters$
      min_node_size[[1]]
  ),
  paste0(
    "Selected sample.fraction: ",
    selected_hyperparameters$
      sample_fraction[[1]]
  ),
  "",
  paste0(
    "Outer RMSE: ",
    outer_metrics$
      rmse[
        outer_metrics$
          evaluation_subset ==
          "all"
      ]
  ),
  paste0(
    "Outer MAE: ",
    outer_metrics$
      mae[
        outer_metrics$
          evaluation_subset ==
          "all"
      ]
  ),
  paste0(
    "Outer R2: ",
    outer_metrics$
      r2[
        outer_metrics$
          evaluation_subset ==
          "all"
      ]
  ),
  "",
  "All imputation medians were estimated from training rows only.",
  "",
  "STATUS: R52 NESTED SPATIAL RF TASK PASSED"
)

writeLines(
  summary_lines,
  file.path(
    task_dir,
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
