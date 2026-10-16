source("R/functions/core.R")
source("R/functions/metrics.R")

check_packages(
  c(
    "dplyr",
    "readr",
    "tibble",
    "ranger"
  )
)

library(dplyr)
library(readr)
library(tibble)
library(ranger)

cfg <- read_config()

out_dir <- file.path(
  project_root(),
  "outputs/p1r_targeted_smoke"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

model_path <- file.path(
  project_root(),
  "data/processed/model_table_p1_reuse.rds"
)

manifest_path <- file.path(
  project_root(),
  "outputs/p1_reuse_build/p1_reuse_feature_manifest.csv"
)

stop_missing(
  model_path,
  "Missing P1R model table."
)

stop_missing(
  manifest_path,
  "Missing P1R feature manifest."
)

dat <- readRDS(model_path)

manifest <- read_csv(
  manifest_path,
  show_col_types = FALSE
)

# ------------------------------------------------------------
# 1. Locate and standardize the fold table
# ------------------------------------------------------------

fold_candidates <- unique(
  c(
    file.path(
      project_root(),
      "data/processed/folds_long.rds"
    ),

    file.path(
      project_root(),
      "data/processed/fold_assignments_long.rds"
    ),

    list.files(
      file.path(
        project_root(),
        "data/processed"
      ),
      pattern = "fold.*\\.rds$",
      full.names = TRUE,
      ignore.case = TRUE
    )
  )
)

fold_candidates <- fold_candidates[
  file.exists(fold_candidates)
]

if (length(fold_candidates) == 0L) {
  stop("No candidate fold RDS files were found.")
}

first_matching_column <- function(
    column_names,
    candidates,
    regex_fallback = NULL
) {
  exact_hit <- candidates[
    candidates %in% column_names
  ]

  if (length(exact_hit) > 0L) {
    return(exact_hit[1])
  }

  if (!is.null(regex_fallback)) {
    regex_hit <- grep(
      regex_fallback,
      column_names,
      value = TRUE,
      ignore.case = TRUE
    )

    if (length(regex_hit) > 0L) {
      return(regex_hit[1])
    }
  }

  NA_character_
}

standardize_fold_data_frame <- function(
    object,
    source_label
) {
  object <- as.data.frame(
    object,
    stringsAsFactors = FALSE
  )

  column_names <- names(object)

  id_column <- first_matching_column(
    column_names,
    c(
      "row_id",
      "site_row_id",
      "observation_row_id",
      "observation_id",
      "obs_id",
      "record_id",
      "id"
    ),
    regex_fallback =
      "(^|_)row(_|\\.)?id$|^observation.*id$"
  )

  scheme_column <- first_matching_column(
    column_names,
    c(
      "scheme",
      "fold_scheme",
      "scheme_name",
      "resampling_scheme",
      "validation_scheme",
      "cv_scheme",
      "fold_type",
      "method"
    ),
    regex_fallback =
      "scheme|resampl|validation.*type|cv.*type"
  )

  fold_column <- first_matching_column(
    column_names,
    c(
      "outer_fold",
      "fold",
      "fold_id",
      "fold_number",
      "outer_id",
      "outer_fold_id",
      "spatial_fold",
      "cluster"
    ),
    regex_fallback =
      "outer.*fold|fold.*(id|number)|^fold$"
  )

  # Long-form fold table.
  if (
    !is.na(id_column) &&
    !is.na(fold_column)
  ) {
    if (!is.na(scheme_column)) {
      scheme_values <-
        as.character(
          object[[scheme_column]]
        )
    } else {
      scheme_values <- rep(
        source_label,
        nrow(object)
      )
    }

    return(
      tibble(
        row_id =
          as.character(
            object[[id_column]]
          ),

        scheme =
          scheme_values,

        outer_fold =
          suppressWarnings(
            as.integer(
              object[[fold_column]]
            )
          ),

        fold_source =
          source_label
      )
    )
  }

  # Wide-form table: one fold column per scheme.
  if (!is.na(id_column)) {
    wide_scheme_columns <- grep(
      paste0(
        "leave.*reference|",
        "reference.*group|",
        "spatial.*500|",
        "spatial.*1000|",
        "spatial.*1500|",
        "500.*km|",
        "1000.*km|",
        "1500.*km"
      ),
      column_names,
      value = TRUE,
      ignore.case = TRUE
    )

    wide_scheme_columns <- setdiff(
      wide_scheme_columns,
      id_column
    )

    if (length(wide_scheme_columns) > 0L) {
      return(
        bind_rows(
          lapply(
            wide_scheme_columns,
            function(scheme_name) {
              tibble(
                row_id =
                  as.character(
                    object[[id_column]]
                  ),

                scheme =
                  scheme_name,

                outer_fold =
                  suppressWarnings(
                    as.integer(
                      object[[scheme_name]]
                    )
                  ),

                fold_source =
                  source_label
              )
            }
          )
        )
      )
    }
  }

  tibble()
}

collect_fold_rows <- function(
    object,
    source_label = "root"
) {
  if (
    is.data.frame(object) ||
    is.matrix(object)
  ) {
    return(
      standardize_fold_data_frame(
        object,
        source_label
      )
    )
  }

  # Some fold objects store named integer vectors.
  if (
    is.atomic(object) &&
    !is.null(names(object)) &&
    length(object) ==
      length(names(object))
  ) {
    return(
      tibble(
        row_id =
          as.character(
            names(object)
          ),

        scheme =
          source_label,

        outer_fold =
          suppressWarnings(
            as.integer(object)
          ),

        fold_source =
          source_label
      )
    )
  }

  if (is.list(object)) {
    object_names <- names(object)

    collected <- vector(
      "list",
      length(object)
    )

    for (i in seq_along(object)) {
      element_name <- if (
        !is.null(object_names) &&
        length(object_names) >= i &&
        !is.na(object_names[i]) &&
        nzchar(object_names[i])
      ) {
        object_names[i]
      } else {
        paste0(
          "element_",
          i
        )
      }

      child_label <- paste(
        source_label,
        element_name,
        sep = "$"
      )

      collected[[i]] <- collect_fold_rows(
        object[[i]],
        child_label
      )
    }

    return(
      bind_rows(collected)
    )
  }

  tibble()
}

normalize_scheme_name <- function(x) {
  original <- as.character(x)

  key <- tolower(
    gsub(
      "[^a-z0-9]+",
      "",
      original
    )
  )

  case_when(
    grepl(
      "1500",
      key
    ) ~
      "spatial_1500km",

    grepl(
      "1000",
      key
    ) ~
      "spatial_1000km",

    grepl(
      "500",
      key
    ) ~
      "spatial_500km",

    grepl(
      "leave",
      key
    ) &
      grepl(
        "reference",
        key
      ) ~
      "leave_reference_group_out",

    grepl(
      "referencegroup",
      key
    ) ~
      "leave_reference_group_out",

    TRUE ~
      original
  )
}

fold_path <- NA_character_
folds <- NULL
fold_diagnostics <- list()

for (candidate_path in fold_candidates) {
  candidate_object <- tryCatch(
    readRDS(candidate_path),
    error = function(e) {
      NULL
    }
  )

  if (is.null(candidate_object)) {
    next
  }

  candidate_rows <- collect_fold_rows(
    candidate_object,
    basename(candidate_path)
  )

  fold_diagnostics[[
    basename(candidate_path)
  ]] <- tibble(
    fold_file =
      candidate_path,

    object_class = paste(
      class(candidate_object),
      collapse = ";"
    ),

    top_level_names = paste(
      names(candidate_object),
      collapse = ";"
    ),

    standardized_rows =
      nrow(candidate_rows),

    standardized_schemes = paste(
      sort(
        unique(
          as.character(
            candidate_rows$scheme
          )
        )
      ),
      collapse = ";"
    )
  )

  if (nrow(candidate_rows) == 0L) {
    next
  }

  candidate_rows <- candidate_rows |>
    mutate(
      scheme =
        normalize_scheme_name(
          scheme
        )
    ) |>
    filter(
      !is.na(row_id),
      nzchar(row_id),
      !is.na(outer_fold)
    )

  if (
    any(
      candidate_rows$scheme ==
        "spatial_1500km"
    )
  ) {
    fold_path <- candidate_path
    folds <- candidate_rows
    break
  }
}

fold_diagnostics_table <- bind_rows(
  fold_diagnostics
)

write_csv(
  fold_diagnostics_table,
  file.path(
    out_dir,
    "fold_loader_diagnostics.csv"
  )
)

if (is.null(folds)) {
  cat(
    "\nFold-loader diagnostics:\n"
  )

  print(
    fold_diagnostics_table,
    n = Inf,
    width = Inf
  )

  stop(
    paste0(
      "No usable spatial_1500km fold assignment ",
      "could be standardized."
    )
  )
}

folds <- folds |>
  select(
    row_id,
    scheme,
    outer_fold,
    fold_source
  ) |>
  distinct()

cat(
  "Fold file: ",
  fold_path,
  "\n",
  sep = ""
)

cat(
  "Fold rows after standardization: ",
  nrow(folds),
  "\n",
  sep = ""
)

cat(
  "Standardized schemes: ",
  paste(
    sort(
      unique(folds$scheme)
    ),
    collapse = ", "
  ),
  "\n",
  sep = ""
)

# ------------------------------------------------------------
# 2. Detect response and coordinate columns
# ------------------------------------------------------------

detect_column <- function(
    data,
    candidates,
    label
) {
  hit <- candidates[
    candidates %in% names(data)
  ]

  if (length(hit) == 0L) {
    stop(
      "Could not detect ",
      label,
      ". Candidates: ",
      paste(
        candidates,
        collapse = ", "
      )
    )
  }

  hit[1]
}

response_column <- detect_column(
  dat,
  c(
    "response",
    "sr87_sr86",
    "site_median",
    "observed",
    "ratio"
  ),
  "response"
)

longitude_column <- detect_column(
  dat,
  c(
    "longitude",
    "lon",
    "LONGITUDE",
    "LONG"
  ),
  "longitude"
)

latitude_column <- detect_column(
  dat,
  c(
    "latitude",
    "lat",
    "LATITUDE",
    "LAT"
  ),
  "latitude"
)

cat(
  "Response column: ",
  response_column,
  "\n",
  sep = ""
)

# ------------------------------------------------------------
# 3. Define predictor sets
# ------------------------------------------------------------

p0_predictors <- grep(
  "^p0__",
  names(dat),
  value = TRUE
)

p1_predictors <- grep(
  "^p1r__",
  names(dat),
  value = TRUE
)

if (length(p0_predictors) != 28L) {
  stop(
    "Expected 28 P0 predictors, found ",
    length(p0_predictors)
  )
}

if (length(p1_predictors) != 52L) {
  stop(
    "Expected 52 P1R predictors, found ",
    length(p1_predictors)
  )
}

manifest <- manifest |>
  filter(
    feature_name %in%
      p1_predictors
  )

process_features <- manifest |>
  filter(
    feature_group %in% c(
      "local_lithology_diversity",
      "upstream_lithology_diversity",
      "process_proxy",
      "process_proxy_contrast",
      "process_interaction"
    )
  ) |>
  pull(feature_name)

local_contrast_features <- manifest |>
  filter(
    feature_group %in% c(
      "direct_local",
      "direct_upstream",
      "local_upstream_contrast",
      "lithology_contrast"
    )
  ) |>
  pull(feature_name)

predictor_sets <- list(
  P0 = p0_predictors,

  P0_PROCESS = unique(
    c(
      p0_predictors,
      process_features
    )
  ),

  P0_LOCAL_CONTRAST = unique(
    c(
      p0_predictors,
      local_contrast_features
    )
  ),

  P0_P1R_FULL = unique(
    c(
      p0_predictors,
      p1_predictors
    )
  )
)

set_manifest <- bind_rows(
  lapply(
    names(predictor_sets),
    function(set_name) {
      tibble(
        predictor_set = set_name,
        predictor =
          predictor_sets[[set_name]]
      )
    }
  )
)

write_csv(
  set_manifest,
  file.path(
    out_dir,
    "predictor_set_manifest.csv"
  )
)

# ------------------------------------------------------------
# 4. Construct common complete-case dataset
# ------------------------------------------------------------

all_predictors <- unique(
  c(
    p0_predictors,
    p1_predictors
  )
)

required_columns <- unique(
  c(
    "row_id",
    response_column,
    longitude_column,
    latitude_column,
    all_predictors
  )
)

missing_columns <- setdiff(
  required_columns,
  names(dat)
)

if (length(missing_columns) > 0L) {
  stop(
    "Missing model columns: ",
    paste(
      missing_columns,
      collapse = ", "
    )
  )
}

complete_index <- complete.cases(
  dat[
    c(
      response_column,
      all_predictors
    )
  ]
)

analysis_dat <- dat[
  complete_index,
  required_columns,
  drop = FALSE
]

analysis_dat$row_id <- as.character(
  analysis_dat$row_id
)

target_folds <- folds |>
  filter(
    scheme ==
      "spatial_1500km"
  ) |>
  transmute(
    row_id =
      as.character(row_id),

    outer_fold =
      as.integer(outer_fold)
  ) |>
  distinct()

fold_duplicates <- target_folds |>
  count(
    row_id,
    name = "n"
  ) |>
  filter(n > 1L)

if (nrow(fold_duplicates) > 0L) {
  stop(
    "Multiple spatial_1500km fold assignments found for some row_id values."
  )
}

analysis_dat <- analysis_dat |>
  inner_join(
    target_folds,
    by = "row_id"
  )

if (nrow(analysis_dat) < 4400L) {
  stop(
    "Unexpectedly few complete joined rows: ",
    nrow(analysis_dat)
  )
}

if (
  !all(
    sort(
      unique(
        analysis_dat$outer_fold
      )
    ) ==
      1:5
  )
) {
  stop(
    "Expected spatial_1500km outer folds 1 through 5."
  )
}

outer_test_fold <- 2L

outer_train <- analysis_dat |>
  filter(
    outer_fold !=
      outer_test_fold
  )

outer_test <- analysis_dat |>
  filter(
    outer_fold ==
      outer_test_fold
  )

cat(
  "Common complete sites: ",
  nrow(analysis_dat),
  "\n",
  sep = ""
)

cat(
  "Outer train n: ",
  nrow(outer_train),
  "\n",
  sep = ""
)

cat(
  "Outer test n: ",
  nrow(outer_test),
  "\n",
  sep = ""
)

# ------------------------------------------------------------
# 5. Helper functions
# ------------------------------------------------------------

retain_nonconstant <- function(
    data,
    predictors
) {
  predictors[
    vapply(
      data[predictors],
      function(x) {
        values <- x[
          is.finite(x)
        ]

        length(
          unique(values)
        ) > 1L
      },
      logical(1)
    )
  ]
}

calculate_basic_metrics <- function(
    observed,
    predicted
) {
  tibble(
    n = length(observed),

    rmse = sqrt(
      mean(
        (
          predicted -
            observed
        )^2
      )
    ),

    mae = mean(
      abs(
        predicted -
          observed
      )
    ),

    bias = mean(
      predicted -
        observed
    )
  )
}

subset_metrics <- function(
    data,
    subset_name
) {
  if (nrow(data) == 0L) {
    return(
      tibble(
        subset = subset_name,
        n = 0L,
        rmse = NA_real_,
        mae = NA_real_,
        bias = NA_real_,
        correlation = NA_real_,
        observed_mean = NA_real_,
        predicted_mean = NA_real_,
        observed_max = NA_real_,
        predicted_max = NA_real_
      )
    )
  }

  tibble(
    subset = subset_name,
    n = nrow(data),

    rmse = sqrt(
      mean(
        (
          data$predicted -
            data$observed
        )^2
      )
    ),

    mae = mean(
      abs(
        data$predicted -
          data$observed
      )
    ),

    bias = mean(
      data$predicted -
        data$observed
    ),

    correlation = if (
      nrow(data) >= 3L &&
      stats::sd(
        data$observed
      ) > 0 &&
      stats::sd(
        data$predicted
      ) > 0
    ) {
      stats::cor(
        data$observed,
        data$predicted
      )
    } else {
      NA_real_
    },

    observed_mean =
      mean(data$observed),

    predicted_mean =
      mean(data$predicted),

    observed_max =
      max(data$observed),

    predicted_max =
      max(data$predicted)
  )
}

thread_n <- as.integer(
  Sys.getenv(
    "SLURM_CPUS_PER_TASK",
    unset = "8"
  )
)

inner_tree_n <- 250L
final_tree_n <- 750L

inner_validation_folds <- sort(
  unique(
    outer_train$outer_fold
  )
)

final_seeds <- c(
  20260728L,
  20260729L,
  20260730L
)

# ------------------------------------------------------------
# 6. Inner spatial tuning
# ------------------------------------------------------------

tuning_results <- list()
best_parameter_rows <- list()
prediction_results <- list()
importance_results <- list()
model_summary_results <- list()

for (
  set_index in seq_along(
    predictor_sets
  )
) {
  set_name <- names(
    predictor_sets
  )[set_index]

  predictors <- retain_nonconstant(
    outer_train,
    predictor_sets[[set_name]]
  )

  predictor_n <- length(predictors)

  mtry_values <- unique(
    pmax(
      1L,
      pmin(
        predictor_n,
        as.integer(
          round(
            predictor_n *
              c(
                0.15,
                0.30,
                0.50
              )
          )
        )
      )
    )
  )

  tuning_grid <- expand.grid(
    mtry = mtry_values,
    min_node_size = c(
      5L,
      10L,
      20L
    ),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )

  set_tuning_rows <- list()

  for (
    grid_index in seq_len(
      nrow(tuning_grid)
    )
  ) {
    grid_mtry <-
      tuning_grid$mtry[grid_index]

    grid_node <-
      tuning_grid$min_node_size[grid_index]

    inner_rows <- list()

    for (
      validation_fold in
        inner_validation_folds
    ) {
      inner_train <- outer_train |>
        filter(
          outer_fold !=
            validation_fold
        )

      inner_valid <- outer_train |>
        filter(
          outer_fold ==
            validation_fold
        )

      train_frame <- inner_train |>
        select(
          all_of(
            c(
              response_column,
              predictors
            )
          )
        )

      names(train_frame)[1] <-
        "response"

      valid_frame <- inner_valid |>
        select(
          all_of(predictors)
        )

      model_seed <- as.integer(
        110000L +
          set_index * 10000L +
          grid_index * 100L +
          validation_fold
      )

      model <- ranger(
        dependent.variable.name =
          "response",

        data =
          train_frame,

        num.trees =
          inner_tree_n,

        mtry =
          grid_mtry,

        min.node.size =
          grid_node,

        importance =
          "none",

        seed =
          model_seed,

        num.threads =
          thread_n,

        write.forest =
          TRUE
      )

      predicted <- predict(
        model,
        data = valid_frame,
        num.threads = thread_n
      )$predictions

      observed <-
        inner_valid[[response_column]]

      all_metrics <- calculate_basic_metrics(
        observed,
        predicted
      )

      high_index <-
        observed >=
        cfg$selection$high_threshold

      high_rmse <- if (
        any(high_index)
      ) {
        sqrt(
          mean(
            (
              predicted[high_index] -
                observed[high_index]
            )^2
          )
        )
      } else {
        NA_real_
      }

      high_bias <- if (
        any(high_index)
      ) {
        mean(
          predicted[high_index] -
            observed[high_index]
        )
      } else {
        NA_real_
      }

      inner_rows[[
        length(inner_rows) + 1L
      ]] <- all_metrics |>
        mutate(
          predictor_set =
            set_name,

          predictor_n =
            predictor_n,

          mtry =
            grid_mtry,

          min_node_size =
            grid_node,

          validation_fold =
            validation_fold,

          high_n =
            sum(high_index),

          high_rmse =
            high_rmse,

          high_bias =
            high_bias
        )
    }

    set_tuning_rows[[
      length(set_tuning_rows) + 1L
    ]] <- bind_rows(
      inner_rows
    )
  }

  set_tuning <- bind_rows(
    set_tuning_rows
  )

  tuning_results[[
    set_name
  ]] <- set_tuning

  tuning_summary <- set_tuning |>
    group_by(
      predictor_set,
      predictor_n,
      mtry,
      min_node_size
    ) |>
    summarise(
      mean_rmse =
        mean(rmse),

      sd_rmse =
        stats::sd(rmse),

      mean_mae =
        mean(mae),

      mean_bias =
        mean(bias),

      mean_high_rmse =
        mean(
          high_rmse,
          na.rm = TRUE
        ),

      mean_high_bias =
        mean(
          high_bias,
          na.rm = TRUE
        ),

      .groups = "drop"
    ) |>
    arrange(
      mean_rmse,
      mean_high_rmse
    )

  best_parameters <-
    tuning_summary |>
    slice_head(n = 1L)

  best_parameter_rows[[
    set_name
  ]] <- best_parameters

  best_mtry <-
    best_parameters$mtry[1]

  best_node <-
    best_parameters$min_node_size[1]

  cat(
    "Best ",
    set_name,
    ": mtry=",
    best_mtry,
    ", min.node.size=",
    best_node,
    ", inner RMSE=",
    signif(
      best_parameters$mean_rmse[1],
      5
    ),
    "\n",
    sep = ""
  )

  # ----------------------------------------------------------
  # 7. Final models and outer-fold predictions
  # ----------------------------------------------------------

  final_train <- outer_train |>
    select(
      all_of(
        c(
          response_column,
          predictors
        )
      )
    )

  names(final_train)[1] <-
    "response"

  final_test <- outer_test |>
    select(
      all_of(predictors)
    )

  seed_predictions <- list()
  seed_importance <- list()

  for (seed_value in final_seeds) {
    final_model <- ranger(
      dependent.variable.name =
        "response",

      data =
        final_train,

      num.trees =
        final_tree_n,

      mtry =
        best_mtry,

      min.node.size =
        best_node,

      importance =
        "permutation",

      seed =
        seed_value,

      num.threads =
        thread_n,

      write.forest =
        TRUE
    )

    seed_predictions[[
      as.character(seed_value)
    ]] <- predict(
      final_model,
      data = final_test,
      num.threads = thread_n
    )$predictions

    seed_importance[[
      as.character(seed_value)
    ]] <- tibble(
      predictor =
        names(
          final_model$variable.importance
        ),

      importance =
        as.numeric(
          final_model$variable.importance
        ),

      seed =
        seed_value
    )
  }

  prediction_matrix <- do.call(
    cbind,
    seed_predictions
  )

  predicted_mean <- rowMeans(
    prediction_matrix
  )

  prediction_results[[
    set_name
  ]] <- tibble(
    row_id =
      outer_test$row_id,

    scheme =
      "spatial_1500km",

    outer_fold =
      outer_test_fold,

    predictor_set =
      set_name,

    observed =
      outer_test[[response_column]],

    predicted =
      predicted_mean,

    longitude =
      outer_test[[longitude_column]],

    latitude =
      outer_test[[latitude_column]],

    residual =
      predicted_mean -
      outer_test[[response_column]]
  )

  importance_results[[
    set_name
  ]] <- bind_rows(
    seed_importance
  ) |>
    group_by(predictor) |>
    summarise(
      importance_mean =
        mean(importance),

      importance_sd =
        stats::sd(importance),

      .groups = "drop"
    ) |>
    mutate(
      predictor_set =
        set_name
    ) |>
    arrange(
      desc(importance_mean)
    )

  model_summary_results[[
    set_name
  ]] <- tibble(
    predictor_set =
      set_name,

    predictor_n =
      predictor_n,

    best_mtry =
      best_mtry,

    best_min_node_size =
      best_node,

    train_n =
      nrow(outer_train),

    test_n =
      nrow(outer_test),

    inner_trees =
      inner_tree_n,

    final_trees =
      final_tree_n,

    final_seed_n =
      length(final_seeds)
  )
}

# ------------------------------------------------------------
# 8. Combine results
# ------------------------------------------------------------

tuning_detail <- bind_rows(
  tuning_results
)

best_parameters <- bind_rows(
  best_parameter_rows
)

predictions <- bind_rows(
  prediction_results
)

importance <- bind_rows(
  importance_results
)

model_summary <- bind_rows(
  model_summary_results
)

# ------------------------------------------------------------
# 9. Outer-test metrics
# ------------------------------------------------------------

global_metrics <- predictions |>
  group_by(
    scheme,
    outer_fold,
    predictor_set
  ) |>
  group_modify(
    ~ metric_row(
      .x$observed,
      .x$predicted,
      cfg$selection$high_threshold
    )
  ) |>
  ungroup()

baseline <- global_metrics |>
  filter(
    predictor_set == "P0"
  )

baseline_values <- baseline |>
  transmute(
    baseline_rmse = rmse,
    baseline_mae = mae,
    baseline_r2 = r2_sse,
    baseline_high_rmse =
      high_rmse,
    baseline_high_bias =
      high_bias,
    baseline_top05_bias =
      top05_bias,
    baseline_range_ratio =
      predicted_range_ratio
  )

global_comparison <- global_metrics |>
  mutate(
    temporary_key = 1L
  ) |>
  left_join(
    baseline_values |>
      mutate(
        temporary_key = 1L
      ),
    by = "temporary_key"
  ) |>
  select(
    -temporary_key
  ) |>
  mutate(
    delta_rmse =
      rmse -
      baseline_rmse,

    delta_mae =
      mae -
      baseline_mae,

    delta_r2 =
      r2_sse -
      baseline_r2,

    delta_high_rmse =
      high_rmse -
      baseline_high_rmse,

    delta_high_bias =
      high_bias -
      baseline_high_bias,

    delta_top05_bias =
      top05_bias -
      baseline_top05_bias,

    delta_range_ratio =
      predicted_range_ratio -
      baseline_range_ratio
  ) |>
  arrange(rmse)

# ------------------------------------------------------------
# 10. Himalaya subset evaluation
# ------------------------------------------------------------

subset_results <- list()

for (
  set_name in unique(
    predictions$predictor_set
  )
) {
  set_data <- predictions |>
    filter(
      predictor_set ==
        set_name
    )

  high_data <- set_data |>
    filter(
      observed >=
        cfg$selection$high_threshold
    )

  himalaya_data <- set_data |>
    filter(
      longitude >= 72,
      longitude <= 90,
      latitude >= 24,
      latitude <= 36
    )

  himalaya_high_data <- himalaya_data |>
    filter(
      observed >=
        cfg$selection$high_threshold
    )

  subset_results[[
    set_name
  ]] <- bind_rows(
    subset_metrics(
      set_data,
      "all_test_sites"
    ),

    subset_metrics(
      high_data,
      "all_high_sr"
    ),

    subset_metrics(
      himalaya_data,
      "himalaya_core"
    ),

    subset_metrics(
      himalaya_high_data,
      "himalaya_core_high_sr"
    )
  ) |>
    mutate(
      predictor_set =
        set_name
    )
}

geographic_metrics <- bind_rows(
  subset_results
) |>
  arrange(
    subset,
    rmse
  )

# ------------------------------------------------------------
# 11. Save outputs
# ------------------------------------------------------------

write_csv(
  tuning_detail,
  file.path(
    out_dir,
    "inner_tuning_detail.csv"
  )
)

write_csv(
  best_parameters,
  file.path(
    out_dir,
    "best_parameters.csv"
  )
)

write_csv(
  predictions,
  file.path(
    out_dir,
    "outer_fold2_predictions.csv"
  )
)

write_atomic_rds(
  predictions,
  file.path(
    out_dir,
    "outer_fold2_predictions.rds"
  )
)

write_csv(
  global_comparison,
  file.path(
    out_dir,
    "global_comparison.csv"
  )
)

write_csv(
  geographic_metrics,
  file.path(
    out_dir,
    "geographic_subset_metrics.csv"
  )
)

write_csv(
  importance,
  file.path(
    out_dir,
    "variable_importance.csv"
  )
)

write_csv(
  model_summary,
  file.path(
    out_dir,
    "model_summary.csv"
  )
)

cat("\nOuter fold 2 global comparison:\n")

print(
  global_comparison |>
    select(
      predictor_set,
      n,
      rmse,
      mae,
      r2_sse,
      bias,
      high_rmse,
      high_bias,
      top05_bias,
      predicted_range_ratio,
      calibration_slope,
      max_predicted,
      delta_rmse,
      delta_r2,
      delta_high_rmse,
      delta_high_bias,
      delta_top05_bias,
      delta_range_ratio
    ),
  n = Inf,
  width = Inf
)

cat("\nHimalaya core high-Sr comparison:\n")

print(
  geographic_metrics |>
    filter(
      subset ==
        "himalaya_core_high_sr"
    ) |>
    select(
      predictor_set,
      n,
      rmse,
      mae,
      bias,
      correlation,
      observed_mean,
      predicted_mean,
      observed_max,
      predicted_max
    ) |>
    arrange(rmse),
  n = Inf,
  width = Inf
)

log_msg(
  "P1R targeted nested smoke test complete: ",
  out_dir
)
