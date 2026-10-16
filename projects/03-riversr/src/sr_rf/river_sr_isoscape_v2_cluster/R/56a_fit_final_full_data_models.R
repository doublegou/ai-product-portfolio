required_packages <- c(
  "dplyr",
  "readr",
  "ranger",
  "tibble"
)

missing_packages <- required_packages[
  !vapply(
    required_packages,
    requireNamespace,
    logical(1),
    quietly = TRUE
  )
]

if (length(missing_packages) > 0L) {
  stop(
    "Missing packages: ",
    paste(
      missing_packages,
      collapse = ", "
    )
  )
}

root <- normalizePath(
  getwd(),
  mustWork = TRUE
)

input_table_file <- file.path(
  root,
  "outputs",
  "r50b_feature_architecture",
  "integrated_model_table.rds"
)

feature_sets_file <- file.path(
  root,
  "outputs",
  "r50b_feature_architecture",
  "model_feature_sets.rds"
)

model_decision_file <- file.path(
  root,
  "outputs",
  "r55_model_selection",
  "model_decision.rds"
)

r52_manifest_file <- file.path(
  root,
  "outputs",
  "r52_nested_spatial_rf",
  "task_manifest.csv"
)

r52_tasks_dir <- file.path(
  root,
  "outputs",
  "r52_nested_spatial_rf",
  "tasks"
)

out_dir <- file.path(
  root,
  "outputs",
  "r56_final_models"
)

model_dir <- file.path(
  out_dir,
  "models"
)

metadata_dir <- file.path(
  out_dir,
  "metadata"
)

dir.create(
  model_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

dir.create(
  metadata_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

required_files <- c(
  input_table_file,
  feature_sets_file,
  model_decision_file,
  r52_manifest_file
)

missing_files <- required_files[
  !file.exists(
    required_files
  )
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

if (!dir.exists(r52_tasks_dir)) {
  stop(
    "R52 task directory does not exist: ",
    r52_tasks_dir
  )
}

normalise_column_names <- function(x) {
  names(x) <- gsub(
    "\\.",
    "_",
    names(x)
  )

  x
}

infer_task_id <- function(path) {
  path_normalised <- gsub(
    "\\\\",
    "/",
    path
  )

  match_result <- regexec(
    "task[_-]?0*([0-9]+)",
    path_normalised,
    ignore.case = TRUE
  )

  extracted <- regmatches(
    path_normalised,
    match_result
  )[[1]]

  if (length(extracted) < 2L) {
    return(
      NA_integer_
    )
  }

  as.integer(
    extracted[[2]]
  )
}

safe_mean <- function(x) {
  x <- x[
    is.finite(x)
  ]

  if (length(x) == 0L) {
    return(
      NA_real_
    )
  }

  mean(x)
}

manifest <- readr::read_csv(
  r52_manifest_file,
  show_col_types = FALSE
) |>
  normalise_column_names()

required_manifest_columns <- c(
  "task_id",
  "model_name"
)

missing_manifest_columns <- setdiff(
  required_manifest_columns,
  names(manifest)
)

if (length(missing_manifest_columns) > 0L) {
  stop(
    "R52 manifest is missing columns: ",
    paste(
      missing_manifest_columns,
      collapse = ", "
    )
  )
}

selected_files <- list.files(
  r52_tasks_dir,
  pattern =
    "(selected|best).*hyper.*\\.csv$",
  recursive = TRUE,
  full.names = TRUE,
  ignore.case = TRUE
)

if (length(selected_files) == 0L) {
  available_csv <- list.files(
    r52_tasks_dir,
    pattern = "\\.csv$",
    recursive = TRUE,
    full.names = TRUE
  )

  stop(
    paste0(
      "No selected-hyperparameter CSV files were found.\n",
      "Available R52 CSV files include:\n",
      paste(
        head(
          available_csv,
          100L
        ),
        collapse = "\n"
      )
    )
  )
}

selected_rows <- lapply(
  selected_files,
  function(selected_file) {
    x <- readr::read_csv(
      selected_file,
      show_col_types = FALSE
    ) |>
      normalise_column_names()

    if (nrow(x) != 1L) {
      stop(
        "Expected one selected-hyperparameter row in ",
        selected_file,
        "; found ",
        nrow(x),
        "."
      )
    }

    if (
      !"task_id" %in%
        names(x) ||
      is.na(
        x$task_id[[1]]
      )
    ) {
      x$task_id <- infer_task_id(
        selected_file
      )
    }

    x$source_file <-
      selected_file

    x
  }
)

selected <- dplyr::bind_rows(
  selected_rows
)

if (
  anyNA(
    selected$task_id
  )
) {
  stop(
    "One or more selected-hyperparameter files ",
    "could not be linked to an R52 task ID."
  )
}

selected <- selected |>
  dplyr::mutate(
    task_id =
      as.integer(
        task_id
      )
  )

manifest_models <- manifest |>
  dplyr::select(
    task_id,
    manifest_model_name =
      model_name
  )

if (
  !"model_name" %in%
    names(selected)
) {
  selected <- selected |>
    dplyr::left_join(
      manifest_models,
      by = "task_id"
    ) |>
    dplyr::rename(
      model_name =
        manifest_model_name
    )
} else {
  selected <- selected |>
    dplyr::left_join(
      manifest_models,
      by = "task_id"
    )

  disagreement <- selected |>
    dplyr::filter(
      !is.na(
        manifest_model_name
      ),
      model_name !=
        manifest_model_name
    )

  if (nrow(disagreement) > 0L) {
    stop(
      "Model names disagree between selected parameter files ",
      "and the R52 manifest."
    )
  }

  selected <- selected |>
    dplyr::select(
      -manifest_model_name
    )
}

alternative_names <- list(
  min_node_size =
    c(
      "min_node_size",
      "min_nodesize",
      "minimum_node_size"
    ),

  sample_fraction =
    c(
      "sample_fraction",
      "sampling_fraction"
    )
)

for (
  canonical_name in
  names(alternative_names)
) {
  if (
    !canonical_name %in%
      names(selected)
  ) {
    candidates <- intersect(
      alternative_names[[canonical_name]],
      names(selected)
    )

    if (length(candidates) > 0L) {
      names(selected)[
        names(selected) ==
          candidates[[1]]
      ] <- canonical_name
    }
  }
}

required_parameter_columns <- c(
  "model_name",
  "mtry",
  "min_node_size",
  "sample_fraction"
)

missing_parameter_columns <- setdiff(
  required_parameter_columns,
  names(selected)
)

if (length(missing_parameter_columns) > 0L) {
  stop(
    "Selected hyperparameter records are missing columns: ",
    paste(
      missing_parameter_columns,
      collapse = ", "
    )
  )
}

metric_candidates <- intersect(
  c(
    "mean_inner_rmse",
    "inner_rmse",
    "mean_rmse",
    "rmse"
  ),
  names(selected)
)

if (length(metric_candidates) > 0L) {
  selected$selected_inner_rmse <-
    as.numeric(
      selected[[metric_candidates[[1]]]]
    )
} else {
  selected$selected_inner_rmse <-
    NA_real_
}

selected <- selected |>
  dplyr::mutate(
    mtry =
      as.integer(
        mtry
      ),

    min_node_size =
      as.integer(
        min_node_size
      ),

    sample_fraction =
      as.numeric(
        sample_fraction
      )
  )

expected_models <- c(
  "M0_P0_FULL",
  "M_CORE_MECHANISTIC",
  "M_FULL_MECHANISTIC"
)

selected_counts <- selected |>
  dplyr::count(
    model_name,
    name = "n_selected_tasks"
  )

for (model_name in expected_models) {
  model_count <- selected_counts |>
    dplyr::filter(
      model_name ==
        .env$model_name
    ) |>
    dplyr::pull(
      n_selected_tasks
    )

  if (
    length(model_count) != 1L ||
    model_count[[1]] != 15L
  ) {
    stop(
      "Expected 15 selected parameter records for ",
      model_name,
      "; found ",
      ifelse(
        length(model_count) == 0L,
        0L,
        model_count[[1]]
      ),
      "."
    )
  }
}

frequency_table <- selected |>
  dplyr::group_by(
    model_name,
    mtry,
    min_node_size,
    sample_fraction
  ) |>
  dplyr::summarise(
    n_tasks =
      dplyr::n(),

    mean_selected_inner_rmse =
      safe_mean(
        selected_inner_rmse
      ),

    .groups = "drop"
  ) |>
  dplyr::mutate(
    rmse_sort =
      dplyr::if_else(
        is.finite(
          mean_selected_inner_rmse
        ),
        mean_selected_inner_rmse,
        Inf
      )
  ) |>
  dplyr::arrange(
    model_name,
    dplyr::desc(
      n_tasks
    ),
    rmse_sort,
    mtry,
    dplyr::desc(
      min_node_size
    ),
    sample_fraction
  )

consensus <- frequency_table |>
  dplyr::group_by(
    model_name
  ) |>
  dplyr::slice_head(
    n = 1L
  ) |>
  dplyr::ungroup() |>
  dplyr::select(
    model_name,
    mtry,
    min_node_size,
    sample_fraction,
    n_tasks_supporting =
      n_tasks,
    mean_selected_inner_rmse
  )

if (nrow(consensus) != 3L) {
  stop(
    "Failed to derive one consensus parameter set ",
    "for each of the three models."
  )
}

readr::write_csv(
  selected,
  file.path(
    metadata_dir,
    "r52_selected_hyperparameters_all_tasks.csv"
  )
)

readr::write_csv(
  frequency_table |>
    dplyr::select(
      -rmse_sort
    ),
  file.path(
    metadata_dir,
    "consensus_hyperparameter_frequency.csv"
  )
)

readr::write_csv(
  consensus,
  file.path(
    metadata_dir,
    "consensus_hyperparameters.csv"
  )
)

dat <- readRDS(
  input_table_file
)

feature_sets <- readRDS(
  feature_sets_file
)

model_decision <- readRDS(
  model_decision_file
)

outcome_name <- "sr87_sr86"

if (
  !outcome_name %in%
    names(dat)
) {
  stop(
    "Outcome column is absent: ",
    outcome_name
  )
}

y <- as.numeric(
  dat[[outcome_name]]
)

if (
  anyNA(y) ||
  any(
    !is.finite(y)
  )
) {
  stop(
    "The final outcome vector contains missing ",
    "or non-finite values."
  )
}

models_to_fit <- unique(
  c(
    model_decision$
      primary_model,

    model_decision$
      sensitivity_model
  )
)

if (
  length(models_to_fit) != 2L
) {
  stop(
    "Expected exactly one primary and one ",
    "sensitivity model."
  )
}

thread_count <- as.integer(
  Sys.getenv(
    "SLURM_CPUS_PER_TASK",
    unset = "4"
  )
)

if (
  !is.finite(thread_count) ||
  thread_count < 1L
) {
  thread_count <- 1L
}

final_tree_count <- 3000L

model_records <- vector(
  "list",
  length(
    models_to_fit
  )
)

names(model_records) <-
  models_to_fit

for (
  model_index in
  seq_along(
    models_to_fit
  )
) {
  model_name <-
    models_to_fit[[model_index]]

  if (
    !model_name %in%
      names(feature_sets)
  ) {
    stop(
      "Feature set is missing for ",
      model_name,
      "."
    )
  }

  features <-
    feature_sets[[model_name]]

  missing_features <- setdiff(
    features,
    names(dat)
  )

  if (
    length(missing_features) > 0L
  ) {
    stop(
      "The following features are missing for ",
      model_name,
      ": ",
      paste(
        missing_features,
        collapse = ", "
      )
    )
  }

  x <- dat[
    ,
    features,
    drop = FALSE
  ]

  non_numeric_features <- features[
    !vapply(
      x,
      is.numeric,
      logical(1)
    )
  ]

  if (
    length(non_numeric_features) >
      0L
  ) {
    stop(
      "Final feature matrix contains non-numeric predictors: ",
      paste(
        non_numeric_features,
        collapse = ", "
      )
    )
  }

  training_medians <- vapply(
    x,
    function(column) {
      finite_values <- column[
        is.finite(column)
      ]

      if (
        length(finite_values) ==
          0L
      ) {
        stop(
          "Feature has no finite training values: ",
          model_name
        )
      }

      stats::median(
        finite_values
      )
    },
    numeric(1)
  )

  x_imputed <- x

  for (
    feature_name in
    features
  ) {
    replace_index <-
      is.na(
        x_imputed[[feature_name]]
      ) |
      !is.finite(
        x_imputed[[feature_name]]
      )

    if (
      any(
        replace_index
      )
    ) {
      x_imputed[[feature_name]][replace_index] <-
        training_medians[[feature_name]]
    }
  }

  parameters <- consensus |>
    dplyr::filter(
      model_name ==
        .env$model_name
    )

  if (
    nrow(parameters) !=
      1L
  ) {
    stop(
      "Consensus parameters are unavailable for ",
      model_name,
      "."
    )
  }

  model_seed <-
    560000L +
    model_index

  set.seed(
    model_seed
  )

  fitted_model <- ranger::ranger(
    x =
      x_imputed,

    y =
      y,

    num.trees =
      final_tree_count,

    mtry =
      parameters$mtry[[1]],

    min.node.size =
      parameters$
        min_node_size[[1]],

    sample.fraction =
      parameters$
        sample_fraction[[1]],

    replace =
      FALSE,

    num.threads =
      thread_count,

    seed =
      model_seed,

    importance =
      "none",

    write.forest =
      TRUE
  )

  fitted_values <- predict(
    fitted_model,
    data = x_imputed,
    num.threads =
      thread_count
  )$predictions

  training_rmse <- sqrt(
    mean(
      (
        y -
          fitted_values
      )^2
    )
  )

  training_mae <- mean(
    abs(
      y -
        fitted_values
    )
  )

  bundle <- list(
    model_name =
      model_name,

    deployment_role =
      if (
        model_name ==
          model_decision$
            primary_model
      ) {
        "primary_final_isoscape"
      } else {
        "mandatory_sensitivity_isoscape"
      },

    ranger_model =
      fitted_model,

    feature_names =
      features,

    training_medians =
      training_medians,

    outcome_name =
      outcome_name,

    n_training_rows =
      nrow(dat),

    n_features =
      length(features),

    hyperparameters =
      list(
        num_trees =
          final_tree_count,

        mtry =
          parameters$mtry[[1]],

        min_node_size =
          parameters$
            min_node_size[[1]],

        sample_fraction =
          parameters$
            sample_fraction[[1]],

        replace =
          FALSE,

        consensus_task_support =
          parameters$
            n_tasks_supporting[[1]]
      ),

    seed =
      model_seed,

    training_fit_sanity =
      list(
        rmse =
          training_rmse,

        mae =
          training_mae,

        interpretation =
          paste(
            "In-sample values are stored only as",
            "a computational sanity check and are not",
            "used as validation estimates."
          )
      ),

    validation_source =
      list(
        spatial =
          "R52 outcome-blind nested spatial CV",

        reference =
          "R54 outcome-blind grouped reference CV"
      ),

    created_at =
      as.character(
        Sys.time()
      )
  )

  bundle_file <- file.path(
    model_dir,
    paste0(
      model_name,
      "_final_model_bundle.rds"
    )
  )

  saveRDS(
    bundle,
    bundle_file,
    version = 3
  )

  median_table <- tibble::tibble(
    model_name =
      model_name,

    feature =
      features,

    training_median =
      as.numeric(
        training_medians[
          features
        ]
      )
  )

  readr::write_csv(
    median_table,
    file.path(
      metadata_dir,
      paste0(
        model_name,
        "_training_medians.csv"
      )
    )
  )

  model_records[[model_index]] <- tibble::tibble(
    model_name =
      model_name,

    deployment_role =
      bundle$
        deployment_role,

    n_training_rows =
      nrow(dat),

    n_features =
      length(features),

    num_trees =
      final_tree_count,

    mtry =
      parameters$mtry[[1]],

    min_node_size =
      parameters$
        min_node_size[[1]],

    sample_fraction =
      parameters$
        sample_fraction[[1]],

    consensus_task_support =
      parameters$
        n_tasks_supporting[[1]],

    training_rmse_sanity =
      training_rmse,

    training_mae_sanity =
      training_mae,

    model_file =
      bundle_file
  )
}

model_manifest <- dplyr::bind_rows(
  model_records
)

readr::write_csv(
  model_manifest,
  file.path(
    out_dir,
    "final_model_manifest.csv"
  )
)

run_summary <- c(
  "R56 FINAL FULL-DATA RANDOM-FOREST MODELS",
  "========================================",
  "",
  paste0(
    "Training rows: ",
    nrow(dat)
  ),
  paste0(
    "Outcome: ",
    outcome_name
  ),
  paste0(
    "Final trees per model: ",
    final_tree_count
  ),
  "",
  paste0(
    "Primary model: ",
    model_decision$
      primary_model
  ),
  paste0(
    "Sensitivity model: ",
    model_decision$
      sensitivity_model
  ),
  "",
  apply(
    model_manifest,
    1L,
    function(row) {
      paste0(
        row[["model_name"]],
        ": features=",
        row[["n_features"]],
        "; mtry=",
        row[["mtry"]],
        "; min_node_size=",
        row[["min_node_size"]],
        "; sample_fraction=",
        row[["sample_fraction"]],
        "; consensus support=",
        row[["consensus_task_support"]],
        "/15"
      )
    }
  ),
  "",
  paste(
    "All 4485 observations were used for final fitting.",
    "Training-fit metrics are sanity checks only."
  ),
  paste(
    "Predictive performance must be reported from",
    "R52 and R54, not from the final training fit."
  ),
  "",
  "STATUS: R56 FINAL MODEL FITTING PASSED"
)

writeLines(
  run_summary,
  file.path(
    out_dir,
    "run_summary.txt"
  )
)

cat(
  paste(
    run_summary,
    collapse = "\n"
  ),
  "\n"
)
