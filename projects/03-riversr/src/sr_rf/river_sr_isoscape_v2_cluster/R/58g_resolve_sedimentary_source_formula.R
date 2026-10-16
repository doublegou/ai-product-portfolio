root <- normalizePath(
  getwd(),
  mustWork = TRUE
)

training_file <- file.path(
  root,
  "outputs",
  "r50b_feature_architecture",
  "integrated_model_table.rds"
)

out_dir <- file.path(
  root,
  "outputs",
  "r58g_sedimentary_formula_resolution"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

read_largest_table <- function(path) {
  object <- readRDS(path)

  if (is.data.frame(object)) {
    return(object)
  }

  if (!is.list(object)) {
    stop("Training object contains no data frame.")
  }

  table_indices <- which(
    vapply(
      object,
      is.data.frame,
      logical(1)
    )
  )

  if (length(table_indices) == 0L) {
    stop("Training object contains no data frame.")
  }

  table_sizes <- vapply(
    object[table_indices],
    nrow,
    integer(1)
  )

  object[[table_indices[[which.max(table_sizes)]]]]
}

calculate_metrics <- function(observed, predicted) {
  keep <- is.finite(observed) &
    is.finite(predicted)

  if (!any(keep)) {
    return(
      c(
        n_complete = 0,
        rmse = NA_real_,
        mae = NA_real_,
        max_abs_difference = NA_real_,
        correlation = NA_real_
      )
    )
  }

  observed <- observed[keep]
  predicted <- predicted[keep]
  difference <- predicted - observed

  correlation <- NA_real_

  if (
    length(observed) >= 3L &&
    stats::sd(observed) > 0 &&
    stats::sd(predicted) > 0
  ) {
    correlation <- stats::cor(
      observed,
      predicted
    )
  }

  c(
    n_complete = length(observed),
    rmse = sqrt(mean(difference^2)),
    mae = mean(abs(difference)),
    max_abs_difference = max(abs(difference)),
    correlation = correlation
  )
}

training <- read_largest_table(
  training_file
)

target_name <- "r50__local_sedimentary_source"

if (!target_name %in% names(training)) {
  stop(
    "Target absent from training table: ",
    target_name
  )
}

target <- training[[target_name]]

candidate_names <- grep(
  paste0(
    "(",
    "^r47__local_geo_",
    "|^local_geo_.*frac",
    "|^p0__local_geo_.*frac",
    ")"
  ),
  names(training),
  value = TRUE,
  ignore.case = TRUE
)

candidate_names <- setdiff(
  candidate_names,
  target_name
)

candidate_names <- candidate_names[
  grepl(
    paste(
      c(
        "carbonate",
        "evaporite",
        "metamorphic",
        "plutonic",
        "siliciclastic",
        "unconsolidated",
        "volcanic",
        "mixed",
        "sedimentary"
      ),
      collapse = "|"
    ),
    candidate_names,
    ignore.case = TRUE
  )
]

candidate_names <- candidate_names[
  vapply(
    training[candidate_names],
    is.numeric,
    logical(1)
  )
]

candidate_names <- unique(
  candidate_names
)

if (length(candidate_names) == 0L) {
  stop("No candidate local-geology columns found.")
}

unique_candidates <- character()

for (candidate in candidate_names) {
  duplicate_vector <- any(
    vapply(
      unique_candidates,
      function(existing) {
        isTRUE(
          all.equal(
            training[[candidate]],
            training[[existing]],
            tolerance = 0
          )
        )
      },
      logical(1)
    )
  )

  if (!duplicate_vector) {
    unique_candidates <- c(
      unique_candidates,
      candidate
    )
  }
}

candidate_names <- unique_candidates

candidate_summary <- do.call(
  rbind,
  lapply(
    candidate_names,
    function(candidate) {
      values <- training[[candidate]]
      finite <- values[is.finite(values)]

      metric <- calculate_metrics(
        target,
        values
      )

      data.frame(
        candidate = candidate,
        n_finite = length(finite),
        minimum = min(finite),
        mean = mean(finite),
        maximum = max(finite),
        direct_rmse = metric[["rmse"]],
        direct_correlation = metric[["correlation"]],
        stringsAsFactors = FALSE
      )
    }
  )
)

if (length(candidate_names) > 14L) {
  stop(
    "Too many unique candidates for exhaustive search: ",
    length(candidate_names),
    ". Inspect candidate_columns.csv."
  )
}

formula_rows <- list()
row_index <- 0L

for (subset_size in seq_along(candidate_names)) {
  combinations <- utils::combn(
    candidate_names,
    subset_size,
    simplify = FALSE
  )

  for (columns in combinations) {
    matrix_values <- as.matrix(
      training[
        ,
        columns,
        drop = FALSE
      ]
    )

    raw_sum <- rowSums(
      matrix_values,
      na.rm = FALSE
    )

    row_maximum <- apply(
      matrix_values,
      1,
      max,
      na.rm = FALSE
    )

    row_mean <- rowMeans(
      matrix_values,
      na.rm = FALSE
    )

    formula_values <- list(
      raw_sum = raw_sum,
      sum_clipped_at_1 = pmin(raw_sum, 1),
      one_minus_sum = 1 - raw_sum,
      one_minus_sum_clipped = pmin(
        pmax(
          1 - raw_sum,
          0
        ),
        1
      ),
      row_maximum = row_maximum,
      row_mean = row_mean,
      any_positive = as.numeric(
        raw_sum > 0
      )
    )

    for (formula_type in names(formula_values)) {
      metric <- calculate_metrics(
        target,
        formula_values[[formula_type]]
      )

      row_index <- row_index + 1L

      formula_rows[[row_index]] <- data.frame(
        formula_type = formula_type,
        source_columns = paste(
          columns,
          collapse = "+"
        ),
        n_source_columns = length(columns),
        n_complete = metric[["n_complete"]],
        rmse = metric[["rmse"]],
        mae = metric[["mae"]],
        max_abs_difference =
          metric[["max_abs_difference"]],
        correlation = metric[["correlation"]],
        stringsAsFactors = FALSE
      )
    }
  }
}

formula_diagnostics <- do.call(
  rbind,
  formula_rows
)

formula_diagnostics <- formula_diagnostics[
  order(
    formula_diagnostics$rmse,
    formula_diagnostics$n_source_columns
  ),
  ,
  drop = FALSE
]

model_frame <- training[
  ,
  c(
    target_name,
    candidate_names
  ),
  drop = FALSE
]

complete_rows <- stats::complete.cases(
  model_frame
)

model_frame <- model_frame[
  complete_rows,
  ,
  drop = FALSE
]

linear_no_intercept <- stats::lm(
  stats::reformulate(
    candidate_names,
    response = target_name,
    intercept = FALSE
  ),
  data = model_frame
)

linear_with_intercept <- stats::lm(
  stats::reformulate(
    candidate_names,
    response = target_name,
    intercept = TRUE
  ),
  data = model_frame
)

extract_linear_result <- function(model, model_type) {
  predictions <- stats::predict(
    model,
    newdata = model_frame
  )

  metric <- calculate_metrics(
    model_frame[[target_name]],
    predictions
  )

  coefficient_table <- data.frame(
    model_type = model_type,
    term = names(stats::coef(model)),
    coefficient = unname(stats::coef(model)),
    model_rmse = metric[["rmse"]],
    model_mae = metric[["mae"]],
    model_max_abs_difference =
      metric[["max_abs_difference"]],
    stringsAsFactors = FALSE
  )

  coefficient_table
}

linear_coefficients <- rbind(
  extract_linear_result(
    linear_no_intercept,
    "no_intercept"
  ),
  extract_linear_result(
    linear_with_intercept,
    "with_intercept"
  )
)

target_finite <- target[
  is.finite(target)
]

target_summary <- data.frame(
  n_rows = length(target),
  n_finite = length(target_finite),
  n_unique = length(unique(target_finite)),
  minimum = min(target_finite),
  q25 = unname(
    stats::quantile(
      target_finite,
      0.25
    )
  ),
  median = stats::median(target_finite),
  mean = mean(target_finite),
  q75 = unname(
    stats::quantile(
      target_finite,
      0.75
    )
  ),
  maximum = max(target_finite),
  stringsAsFactors = FALSE
)

write.csv(
  candidate_summary,
  file.path(
    out_dir,
    "candidate_columns.csv"
  ),
  row.names = FALSE
)

write.csv(
  formula_diagnostics,
  file.path(
    out_dir,
    "formula_diagnostics.csv"
  ),
  row.names = FALSE
)

write.csv(
  formula_diagnostics[
    seq_len(
      min(
        100L,
        nrow(formula_diagnostics)
      )
    ),
    ,
    drop = FALSE
  ],
  file.path(
    out_dir,
    "top_100_formulas.csv"
  ),
  row.names = FALSE
)

write.csv(
  linear_coefficients,
  file.path(
    out_dir,
    "linear_coefficients.csv"
  ),
  row.names = FALSE
)

write.csv(
  target_summary,
  file.path(
    out_dir,
    "target_summary.csv"
  ),
  row.names = FALSE
)

best <- formula_diagnostics[
  1,
  ,
  drop = FALSE
]

exact_formula_found <-
  is.finite(best$rmse) &&
  best$rmse < 1e-12

summary_lines <- c(
  "R58G SEDIMENTARY SOURCE FORMULA RESOLUTION",
  "===========================================",
  "",
  paste0(
    "Training rows: ",
    nrow(training)
  ),
  paste0(
    "Unique candidate columns: ",
    length(candidate_names)
  ),
  paste0(
    "Formulas tested: ",
    nrow(formula_diagnostics)
  ),
  paste0(
    "Best formula type: ",
    best$formula_type
  ),
  paste0(
    "Best source columns: ",
    best$source_columns
  ),
  paste0(
    "Best RMSE: ",
    format(
      best$rmse,
      digits = 14
    )
  ),
  paste0(
    "Best maximum absolute difference: ",
    format(
      best$max_abs_difference,
      digits = 14
    )
  ),
  paste0(
    "Exact formula found: ",
    exact_formula_found
  ),
  "",
  "STATUS: R58G SEDIMENTARY SOURCE FORMULA RESOLUTION PASSED"
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
  "\n\n"
)

cat(
  "===== CANDIDATE COLUMNS =====\n"
)

print(
  candidate_summary,
  row.names = FALSE
)

cat(
  "\n===== TOP 20 FORMULAS =====\n"
)

print(
  formula_diagnostics[
    seq_len(
      min(
        20L,
        nrow(formula_diagnostics)
      )
    ),
    ,
    drop = FALSE
  ],
  row.names = FALSE
)

cat(
  "\n===== LINEAR COEFFICIENTS =====\n"
)

print(
  linear_coefficients,
  row.names = FALSE
)
