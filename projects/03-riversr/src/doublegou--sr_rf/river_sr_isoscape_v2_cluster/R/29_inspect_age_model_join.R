#!/usr/bin/env Rscript

options(
  stringsAsFactors = FALSE,
  warn = 1
)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
})

model_path <- "data/processed/model_table.rds"

fold_path <- "data/processed/folds_long.rds"

age_path <- paste0(
  "outputs/nrcan_age_hydrobasins_l6/",
  "global_upstream/",
  "l6_nrcan_age_local_upstream_global.rds"
)

output_dir <- "outputs/model_age_test_discovery"

dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)


required_files <- c(
  model_path,
  fold_path,
  age_path
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


drop_geometry_if_needed <- function(x) {

  if (inherits(x, "sf")) {
    return(
      sf::st_drop_geometry(x)
    )
  }

  x
}


to_hybas_key <- function(values) {

  if (is.factor(values)) {
    values <- as.character(values)
  }

  character_values <- trimws(
    as.character(values)
  )

  character_values[
    character_values %in% c(
      "",
      "NA",
      "NaN",
      "NULL"
    )
  ] <- NA_character_

  numeric_values <- suppressWarnings(
    as.numeric(character_values)
  )

  output <- ifelse(
    is.finite(numeric_values),
    sprintf("%.0f", numeric_values),
    character_values
  )

  output[
    !nzchar(output)
  ] <- NA_character_

  output
}


cat("Reading formal P0 model table...\n")

model <- readRDS(
  model_path
) %>%
  drop_geometry_if_needed() %>%
  as_tibble()


cat("Reading formal fold table...\n")

folds <- readRDS(
  fold_path
) %>%
  drop_geometry_if_needed() %>%
  as_tibble()


cat("Reading global geological-age predictors...\n")

age <- readRDS(
  age_path
) %>%
  drop_geometry_if_needed() %>%
  as_tibble()


if (!"HYBAS_ID" %in% names(age)) {
  stop(
    "Global age table lacks HYBAS_ID."
  )
}


age$AGE_HYBAS_KEY <- to_hybas_key(
  age$HYBAS_ID
)

if (
  any(is.na(age$AGE_HYBAS_KEY)) ||
  anyDuplicated(age$AGE_HYBAS_KEY) > 0L
) {
  stop(
    "Global age table has missing or duplicated HYBAS_ID."
  )
}


model_summary <- tibble(
  metric = c(
    "model_row_count",
    "model_column_count",
    "unique_row_id_count",
    "missing_row_id_count",
    "missing_response_count",
    "observed_ge_0p720_count",
    "observed_ge_0p722_count",
    "observed_maximum",
    "age_basin_count",
    "fold_row_count"
  ),

  value = c(
    nrow(model),
    ncol(model),

    if ("row_id" %in% names(model)) {
      length(
        unique(
          model$row_id
        )
      )
    } else {
      NA_real_
    },

    if ("row_id" %in% names(model)) {
      sum(
        is.na(model$row_id)
      )
    } else {
      NA_real_
    },

    if ("sr87_sr86" %in% names(model)) {
      sum(
        !is.finite(
          as.numeric(
            model$sr87_sr86
          )
        )
      )
    } else {
      NA_real_
    },

    if ("sr87_sr86" %in% names(model)) {
      sum(
        as.numeric(
          model$sr87_sr86
        ) >= 0.720,
        na.rm = TRUE
      )
    } else {
      NA_real_
    },

    if ("sr87_sr86" %in% names(model)) {
      sum(
        as.numeric(
          model$sr87_sr86
        ) >= 0.722,
        na.rm = TRUE
      )
    } else {
      NA_real_
    },

    if ("sr87_sr86" %in% names(model)) {
      max(
        as.numeric(
          model$sr87_sr86
        ),
        na.rm = TRUE
      )
    } else {
      NA_real_
    },

    nrow(age),
    nrow(folds)
  )
)


candidate_columns <- names(model)[
  grepl(
    paste0(
      "hybas|basin|catchment|",
      "sub.?basin|level.?6|lev.?06|(^|_)l6($|_)"
    ),
    names(model),
    ignore.case = TRUE
  )
]


candidate_match_results <- lapply(
  candidate_columns,
  function(column_name) {

    model_key <- to_hybas_key(
      model[[column_name]]
    )

    matched <- (
      !is.na(model_key) &
        model_key %in% age$AGE_HYBAS_KEY
    )

    matched_age_index <- match(
      model_key,
      age$AGE_HYBAS_KEY
    )

    tibble(
      model_column = column_name,

      model_nonmissing_count = sum(
        !is.na(model_key)
      ),

      model_unique_key_count = length(
        unique(
          model_key[
            !is.na(model_key)
          ]
        )
      ),

      matched_sample_count = sum(
        matched
      ),

      unmatched_sample_count = sum(
        !is.na(model_key) &
          !matched
      ),

      missing_sample_key_count = sum(
        is.na(model_key)
      ),

      matched_fraction_all_samples =
        mean(matched),

      matched_fraction_nonmissing = ifelse(
        sum(!is.na(model_key)) > 0,
        sum(matched) /
          sum(!is.na(model_key)),
        NA_real_
      ),

      matched_unique_age_basin_count =
        length(
          unique(
            age$AGE_HYBAS_KEY[
              matched_age_index[
                !is.na(matched_age_index)
              ]
            ]
          )
        )
    )
  }
)


if (length(candidate_match_results) == 0L) {

  candidate_match_table <- tibble(
    model_column = character(),
    model_nonmissing_count = integer(),
    model_unique_key_count = integer(),
    matched_sample_count = integer(),
    unmatched_sample_count = integer(),
    missing_sample_key_count = integer(),
    matched_fraction_all_samples = numeric(),
    matched_fraction_nonmissing = numeric(),
    matched_unique_age_basin_count = integer()
  )

} else {

  candidate_match_table <- bind_rows(
    candidate_match_results
  ) %>%
    arrange(
      desc(matched_sample_count),
      unmatched_sample_count,
      missing_sample_key_count
    )
}


coordinate_candidates <- names(model)[
  grepl(
    paste0(
      "longitude|latitude|",
      "(^|_)lon($|_)|(^|_)lat($|_)|",
      "(^|_)x($|_)|(^|_)y($|_)"
    ),
    names(model),
    ignore.case = TRUE
  )
]


response_candidates <- names(model)[
  grepl(
    "sr87|87.*86|response|outcome",
    names(model),
    ignore.case = TRUE
  )
]


fold_scheme_summary <- if (
  all(
    c(
      "scheme",
      "fold"
    ) %in% names(folds)
  )
) {

  folds %>%
    count(
      scheme,
      fold,
      name = "n"
    ) %>%
    arrange(
      scheme,
      fold
    )

} else {

  tibble(
    scheme = character(),
    fold = integer(),
    n = integer()
  )
}


write_csv(
  model_summary,
  file.path(
    output_dir,
    "age_join_model_summary.csv"
  )
)

write_csv(
  candidate_match_table,
  file.path(
    output_dir,
    "age_join_candidate_columns.csv"
  )
)

write_csv(
  fold_scheme_summary,
  file.path(
    output_dir,
    "formal_fold_scheme_summary.csv"
  )
)

write_lines(
  names(model),
  file.path(
    output_dir,
    "formal_model_table_columns.txt"
  )
)


cat("\n========================================\n")
cat("FORMAL MODEL–AGE JOIN INSPECTION\n")
cat("========================================\n")


cat("\nModel summary:\n")

print(
  model_summary,
  n = Inf,
  width = Inf
)


cat("\nResponse candidates:\n")

cat(
  if (
    length(response_candidates) > 0L
  ) {
    paste(
      response_candidates,
      collapse = "\n"
    )
  } else {
    "NONE"
  },
  "\n"
)


cat("\nCoordinate candidates:\n")

cat(
  if (
    length(coordinate_candidates) > 0L
  ) {
    paste(
      coordinate_candidates,
      collapse = "\n"
    )
  } else {
    "NONE"
  },
  "\n"
)


cat("\nPossible basin join columns:\n")

if (nrow(candidate_match_table) == 0L) {

  cat(
    "No model-table columns matched the ",
    "basin-name search pattern.\n",
    sep = ""
  )

} else {

  print(
    candidate_match_table,
    n = Inf,
    width = Inf
  )
}


cat("\nFormal fold schemes:\n")

print(
  fold_scheme_summary,
  n = Inf,
  width = Inf
)


cat("\nOutputs written to:\n")
cat(output_dir, "\n")
