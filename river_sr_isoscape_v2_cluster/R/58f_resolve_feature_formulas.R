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

legacy_glim_dir <- file.path(
  "/home",
  "zhangmeng",
  "projects",
  "sr_global",
  "data_processed",
  "global",
  "glim_l6_by_region"
)

out_dir <- file.path(
  root,
  "outputs",
  "r58f_feature_formula_resolution"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

read_table_payload <- function(path) {
  object <- readRDS(path)

  if (is.data.frame(object)) {
    return(object)
  }

  if (!is.list(object)) {
    stop(
      "No data-frame payload in: ",
      path
    )
  }

  table_indices <- which(
    vapply(
      object,
      is.data.frame,
      logical(1)
    )
  )

  if (length(table_indices) == 0L) {
    stop(
      "No data-frame payload in: ",
      path
    )
  }

  table_rows <- vapply(
    object[table_indices],
    nrow,
    integer(1)
  )

  selected_index <- table_indices[
    which.max(table_rows)
  ]

  object[[selected_index]]
}

safe_metrics <- function(observed, predicted) {
  keep <- is.finite(observed) &
    is.finite(predicted)

  n_complete <- sum(keep)

  if (n_complete == 0L) {
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

  difference <- predicted[keep] -
    observed[keep]

  correlation <- NA_real_

  if (
    n_complete >= 3L &&
    stats::sd(observed[keep]) > 0 &&
    stats::sd(predicted[keep]) > 0
  ) {
    correlation <- stats::cor(
      observed[keep],
      predicted[keep]
    )
  }

  c(
    n_complete = n_complete,
    rmse = sqrt(
      mean(
        difference^2
      )
    ),
    mae = mean(
      abs(difference)
    ),
    max_abs_difference = max(
      abs(difference)
    ),
    correlation = correlation
  )
}

rbind_fill <- function(tables) {
  all_columns <- unique(
    unlist(
      lapply(
        tables,
        names
      ),
      use.names = FALSE
    )
  )

  aligned <- lapply(
    tables,
    function(table) {
      missing_columns <- setdiff(
        all_columns,
        names(table)
      )

      for (column in missing_columns) {
        table[[column]] <- NA
      }

      table[
        ,
        all_columns,
        drop = FALSE
      ]
    }
  )

  do.call(
    rbind,
    aligned
  )
}

training <- read_table_payload(
  training_file
)

target_features <- c(
  "r47__local_geo_carbonate",
  "r47__local_geo_evaporite",
  "r47__local_geo_metamorphic",
  "r47__local_geo_plutonic",
  "r47__local_geo_siliciclastic",
  "r47__local_geo_unconsolidated",
  "r47__local_geo_volcanic",
  "r50__local_radiogenic_crystalline",
  "r50__local_sedimentary_source",
  "m1a__lith_entropy_norm"
)

missing_training_targets <- setdiff(
  target_features,
  names(training)
)

if (length(missing_training_targets) > 0L) {
  stop(
    "Target features absent from training table: ",
    paste(
      missing_training_targets,
      collapse = ", "
    )
  )
}

feature_summary_rows <- lapply(
  target_features,
  function(feature) {
    values <- training[[feature]]
    finite_values <- values[
      is.finite(values)
    ]

    data.frame(
      feature = feature,
      n_rows = length(values),
      n_finite = length(finite_values),
      n_unique = length(
        unique(finite_values)
      ),
      minimum = min(
        finite_values
      ),
      q25 = unname(
        stats::quantile(
          finite_values,
          0.25
        )
      ),
      median = stats::median(
        finite_values
      ),
      mean = mean(
        finite_values
      ),
      q75 = unname(
        stats::quantile(
          finite_values,
          0.75
        )
      ),
      maximum = max(
        finite_values
      ),
      stringsAsFactors = FALSE
    )
  }
)

feature_summary <- do.call(
  rbind,
  feature_summary_rows
)

glim_files <- sort(
  list.files(
    legacy_glim_dir,
    pattern = "\\.[Rr][Dd][Ss]$",
    full.names = TRUE
  )
)

if (length(glim_files) != 9L) {
  warning(
    "Expected 9 regional GLiM files; found ",
    length(glim_files)
  )
}

glim_tables <- list()
glim_inventory_rows <- list()
candidate_column_rows <- list()

for (index in seq_along(glim_files)) {
  path <- glim_files[[index]]
  table <- read_table_payload(path)

  region <- sub(
    "^.*_([a-z]{2})\\.[Rr][Dd][Ss]$",
    "\\1",
    basename(path)
  )

  table$source_region_r58f <- region

  key_candidates <- names(table)[
    tolower(names(table)) %in%
      c(
        "hybas_id",
        "hybas_key"
      )
  ]

  key_column <- if (
    "HYBAS_ID" %in%
      names(table)
  ) {
    "HYBAS_ID"
  } else if (
    length(key_candidates) > 0L
  ) {
    key_candidates[[1L]]
  } else {
    NA_character_
  }

  key_values <- if (
    is.na(key_column)
  ) {
    rep(
      NA_character_,
      nrow(table)
    )
  } else {
    as.character(
      table[[key_column]]
    )
  }

  candidate_columns <- grep(
    "local.*(carbonate|evaporite|metamorphic|plutonic|siliciclastic|unconsolidated|volcanic|mixed)|up.*(carbonate|evaporite|metamorphic|plutonic|siliciclastic|unconsolidated|volcanic|mixed)|entropy",
    names(table),
    value = TRUE,
    ignore.case = TRUE
  )

  glim_inventory_rows[[index]] <- data.frame(
    region = region,
    path = path,
    n_rows = nrow(table),
    n_columns = ncol(table),
    key_column = key_column,
    key_nonmissing = sum(
      !is.na(key_values)
    ),
    key_duplicates = sum(
      duplicated(
        key_values[
          !is.na(key_values)
        ]
      )
    ),
    candidate_column_count = length(
      candidate_columns
    ),
    stringsAsFactors = FALSE
  )

  if (length(candidate_columns) > 0L) {
    candidate_column_rows[[index]] <- data.frame(
      region = region,
      column = candidate_columns,
      stringsAsFactors = FALSE
    )
  }

  glim_tables[[index]] <- table
}

glim_inventory <- do.call(
  rbind,
  glim_inventory_rows
)

glim_candidate_columns <- do.call(
  rbind,
  candidate_column_rows
)

glim_all <- rbind_fill(
  glim_tables
)

glim_key_candidates <- names(glim_all)[
  tolower(names(glim_all)) %in%
    c(
      "hybas_id",
      "hybas_key"
    )
]

if (
  "HYBAS_ID" %in%
    names(glim_all)
) {
  glim_key <- "HYBAS_ID"
} else if (
  length(glim_key_candidates) > 0L
) {
  glim_key <- glim_key_candidates[[1L]]
} else {
  stop(
    "No HYBAS key found in legacy GLiM tables."
  )
}

training_key_candidates <- grep(
  "hybas",
  names(training),
  value = TRUE,
  ignore.case = TRUE
)

local_targets <- grep(
  "^r47__local_geo_",
  target_features,
  value = TRUE
)

alias_rows <- list()
alias_index <- 0L

for (target in local_targets) {
  lithology <- sub(
    "^r47__local_geo_",
    "",
    target
  )

  source_candidates <- grep(
    paste0(
      "local.*",
      lithology,
      "|",
      lithology,
      ".*local"
    ),
    names(glim_all),
    value = TRUE,
    ignore.case = TRUE
  )

  source_candidates <- source_candidates[
    vapply(
      glim_all[
        source_candidates
      ],
      is.numeric,
      logical(1)
    )
  ]

  for (training_key in training_key_candidates) {
    training_key_values <- as.character(
      training[[training_key]]
    )

    source_index <- match(
      training_key_values,
      as.character(
        glim_all[[glim_key]]
      )
    )

    for (source_column in source_candidates) {
      predicted <- glim_all[
        source_index,
        source_column
      ]

      observed <- training[[target]]

      metric <- safe_metrics(
        observed,
        predicted
      )

      alias_index <- alias_index + 1L

      alias_rows[[alias_index]] <- data.frame(
        target_feature = target,
        lithology = lithology,
        training_key = training_key,
        legacy_key = glim_key,
        source_column = source_column,
        n_complete = metric[["n_complete"]],
        rmse = metric[["rmse"]],
        mae = metric[["mae"]],
        max_abs_difference =
          metric[["max_abs_difference"]],
        correlation =
          metric[["correlation"]],
        stringsAsFactors = FALSE
      )
    }
  }
}

if (length(alias_rows) > 0L) {
  alias_diagnostics <- do.call(
    rbind,
    alias_rows
  )

  alias_diagnostics <- alias_diagnostics[
    order(
      alias_diagnostics$target_feature,
      alias_diagnostics$rmse,
      -alias_diagnostics$n_complete
    ),
    ,
    drop = FALSE
  ]
} else {
  alias_diagnostics <- data.frame()
}

local_source_columns <- intersect(
  local_targets,
  names(training)
)

subset_rows <- list()
subset_index <- 0L

if (length(local_source_columns) > 0L) {
  combination_ids <- seq_len(
    2^length(local_source_columns) -
      1L
  )

  for (target in c(
    "r50__local_radiogenic_crystalline",
    "r50__local_sedimentary_source"
  )) {
    observed <- training[[target]]

    for (combination_id in combination_ids) {
      included <- as.logical(
        intToBits(
          combination_id
        )[
          seq_along(
            local_source_columns
          )
        ]
      )

      selected_columns <- local_source_columns[
        included
      ]

      predicted_raw <- rowSums(
        training[
          selected_columns
        ],
        na.rm = FALSE
      )

      predicted_clipped <- pmin(
        predicted_raw,
        1
      )

      for (formula_type in c(
        "raw_sum",
        "sum_clipped_at_1"
      )) {
        predicted <- if (
          formula_type ==
            "raw_sum"
        ) {
          predicted_raw
        } else {
          predicted_clipped
        }

        metric <- safe_metrics(
          observed,
          predicted
        )

        subset_index <- subset_index + 1L

        subset_rows[[subset_index]] <- data.frame(
          target_feature = target,
          formula_type = formula_type,
          source_columns = paste(
            selected_columns,
            collapse = "+"
          ),
          n_source_columns = length(
            selected_columns
          ),
          n_complete = metric[["n_complete"]],
          rmse = metric[["rmse"]],
          mae = metric[["mae"]],
          max_abs_difference =
            metric[["max_abs_difference"]],
          correlation =
            metric[["correlation"]],
          stringsAsFactors = FALSE
        )
      }
    }
  }
}

subset_diagnostics <- do.call(
  rbind,
  subset_rows
)

subset_diagnostics <- subset_diagnostics[
  order(
    subset_diagnostics$target_feature,
    subset_diagnostics$rmse,
    subset_diagnostics$n_source_columns
  ),
  ,
  drop = FALSE
]

upstream_fraction_columns <- grep(
  "^p0__up_geo_.*_frac$",
  names(training),
  value = TRUE
)

if (length(upstream_fraction_columns) == 0L) {
  stop(
    "No upstream lithology fractions found."
  )
}

fraction_matrix <- as.matrix(
  training[
    upstream_fraction_columns
  ]
)

fraction_matrix[
  fraction_matrix < 0
] <- NA_real_

entropy_raw <- apply(
  fraction_matrix,
  1,
  function(values) {
    if (any(!is.finite(values))) {
      return(NA_real_)
    }

    positive <- values[
      values > 0
    ]

    if (length(positive) == 0L) {
      return(0)
    }

    -sum(
      positive *
        log(positive)
    )
  }
)

row_totals <- rowSums(
  fraction_matrix,
  na.rm = FALSE
)

normalised_matrix <- fraction_matrix /
  row_totals

entropy_renormalised <- apply(
  normalised_matrix,
  1,
  function(values) {
    if (any(!is.finite(values))) {
      return(NA_real_)
    }

    positive <- values[
      values > 0
    ]

    if (length(positive) == 0L) {
      return(0)
    }

    -sum(
      positive *
        log(positive)
    )
  }
)

positive_counts <- rowSums(
  fraction_matrix > 0,
  na.rm = FALSE
)

normalise_by_positive_count <- function(
  entropy,
  counts
) {
  output <- rep(
    NA_real_,
    length(entropy)
  )

  output[
    counts == 0
  ] <- 0

  output[
    counts == 1
  ] <- 0

  valid <- counts > 1 &
    is.finite(entropy)

  output[valid] <- entropy[valid] /
    log(
      counts[valid]
    )

  output
}

entropy_candidates <- list(
  raw_entropy =
    entropy_raw,

  raw_entropy_div_log8 =
    entropy_raw /
    log(
      length(
        upstream_fraction_columns
      )
    ),

  raw_entropy_div_log_positive =
    normalise_by_positive_count(
      entropy_raw,
      positive_counts
    ),

  renormalised_entropy =
    entropy_renormalised,

  renormalised_entropy_div_log8 =
    entropy_renormalised /
    log(
      length(
        upstream_fraction_columns
      )
    ),

  renormalised_entropy_div_log_positive =
    normalise_by_positive_count(
      entropy_renormalised,
      positive_counts
    )
)

entropy_observed <- training[["m1a__lith_entropy_norm"]]

entropy_rows <- lapply(
  names(entropy_candidates),
  function(formula_name) {
    metric <- safe_metrics(
      entropy_observed,
      entropy_candidates[[formula_name]]
    )

    data.frame(
      formula_name = formula_name,
      n_complete = metric[["n_complete"]],
      rmse = metric[["rmse"]],
      mae = metric[["mae"]],
      max_abs_difference =
        metric[["max_abs_difference"]],
      correlation =
        metric[["correlation"]],
      stringsAsFactors = FALSE
    )
  }
)

entropy_diagnostics <- do.call(
  rbind,
  entropy_rows
)

entropy_diagnostics <- entropy_diagnostics[
  order(
    entropy_diagnostics$rmse
  ),
  ,
  drop = FALSE
]

write.csv(
  feature_summary,
  file.path(
    out_dir,
    "target_feature_training_summary.csv"
  ),
  row.names = FALSE
)

write.csv(
  glim_inventory,
  file.path(
    out_dir,
    "legacy_glim_region_inventory.csv"
  ),
  row.names = FALSE
)

write.csv(
  glim_candidate_columns,
  file.path(
    out_dir,
    "legacy_glim_candidate_columns.csv"
  ),
  row.names = FALSE
)

write.csv(
  alias_diagnostics,
  file.path(
    out_dir,
    "r47_alias_diagnostics.csv"
  ),
  row.names = FALSE
)

write.csv(
  subset_diagnostics,
  file.path(
    out_dir,
    "r50_subset_formula_diagnostics.csv"
  ),
  row.names = FALSE
)

write.csv(
  entropy_diagnostics,
  file.path(
    out_dir,
    "entropy_formula_diagnostics.csv"
  ),
  row.names = FALSE
)

best_aliases <- if (
  nrow(alias_diagnostics) > 0L
) {
  do.call(
    rbind,
    lapply(
      split(
        alias_diagnostics,
        alias_diagnostics$target_feature
      ),
      function(table) {
        table[
          1,
          ,
          drop = FALSE
        ]
      }
    )
  )
} else {
  data.frame()
}

best_subsets <- do.call(
  rbind,
  lapply(
    split(
      subset_diagnostics,
      subset_diagnostics$target_feature
    ),
    function(table) {
      table[
        1,
        ,
        drop = FALSE
      ]
    }
  )
)

write.csv(
  best_aliases,
  file.path(
    out_dir,
    "best_r47_aliases.csv"
  ),
  row.names = FALSE
)

write.csv(
  best_subsets,
  file.path(
    out_dir,
    "best_r50_subset_formulas.csv"
  ),
  row.names = FALSE
)

summary_lines <- c(
  "R58F FEATURE FORMULA RESOLUTION",
  "===============================",
  "",
  paste0(
    "Training rows: ",
    nrow(training)
  ),
  paste0(
    "Regional GLiM files: ",
    length(glim_files)
  ),
  paste0(
    "Combined legacy GLiM rows: ",
    nrow(glim_all)
  ),
  paste0(
    "Training HYBAS key candidates: ",
    length(training_key_candidates)
  ),
  paste0(
    "R47 alias comparisons: ",
    nrow(alias_diagnostics)
  ),
  paste0(
    "R50 subset formulas tested: ",
    nrow(subset_diagnostics)
  ),
  paste0(
    "Entropy formulas tested: ",
    nrow(entropy_diagnostics)
  ),
  "",
  paste0(
    "Best entropy formula: ",
    entropy_diagnostics$formula_name[[1L]]
  ),
  paste0(
    "Best entropy RMSE: ",
    format(
      entropy_diagnostics$rmse[[1L]],
      digits = 12
    )
  ),
  "",
  "STATUS: R58F FEATURE FORMULA RESOLUTION PASSED"
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
  "===== BEST R47 ALIASES =====\n"
)

print(
  best_aliases,
  row.names = FALSE
)

cat(
  "\n===== BEST R50 FORMULAS =====\n"
)

print(
  best_subsets,
  row.names = FALSE
)

cat(
  "\n===== ENTROPY FORMULAS =====\n"
)

print(
  entropy_diagnostics,
  row.names = FALSE
)
