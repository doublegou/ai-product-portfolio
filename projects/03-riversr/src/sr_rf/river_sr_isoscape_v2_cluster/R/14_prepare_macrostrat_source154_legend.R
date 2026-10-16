suppressPackageStartupMessages({
  library(jsonlite)
  library(dplyr)
  library(readr)
  library(tibble)
})

input_path <- file.path(
  "data/raw/geology/macrostrat_source_154",
  "source_154_legend.json"
)

processed_dir <- file.path(
  "data/processed/geology"
)

output_dir <- file.path(
  "outputs/macrostrat_source_154"
)

dir.create(
  processed_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

if (!file.exists(input_path)) {
  stop(
    "Missing source-154 legend: ",
    input_path
  )
}

raw <- fromJSON(
  input_path,
  simplifyVector = FALSE
)

records <- raw$success$data

if (
  is.null(records) ||
  length(records) == 0L
) {
  stop("Legend response contains no records.")
}

flatten_values <- function(x) {
  if (
    is.null(x) ||
    length(x) == 0L
  ) {
    return(character())
  }

  values <- unlist(
    x,
    recursive = TRUE,
    use.names = FALSE
  )

  values[
    !is.na(values)
  ]
}

first_character <- function(x) {
  values <- flatten_values(x)

  if (length(values) == 0L) {
    return(NA_character_)
  }

  as.character(values[[1]])
}

first_numeric <- function(x) {
  values <- flatten_values(x)

  if (length(values) == 0L) {
    return(NA_real_)
  }

  suppressWarnings(
    as.numeric(values[[1]])
  )
}

first_integer <- function(x) {
  values <- flatten_values(x)

  if (length(values) == 0L) {
    return(NA_integer_)
  }

  suppressWarnings(
    as.integer(values[[1]])
  )
}

collapse_values <- function(x) {
  values <- flatten_values(x)

  if (length(values) == 0L) {
    return(NA_character_)
  }

  paste(
    unique(
      as.character(values)
    ),
    collapse = ";"
  )
}

count_values <- function(x) {
  length(
    flatten_values(x)
  )
}

legend <- bind_rows(
  lapply(
    records,
    function(record) {
      tibble(
        legend_id = first_integer(
          record$legend_id
        ),

        source_id = first_integer(
          record$source_id
        ),

        scale = first_character(
          record$scale
        ),

        map_unit_name = first_character(
          record$map_unit_name
        ),

        strat_name = first_character(
          record$strat_name
        ),

        age_label = first_character(
          record$age
        ),

        lith = first_character(
          record$lith
        ),

        descrip = first_character(
          record$descrip
        ),

        comments = first_character(
          record$comments
        ),

        t_age_ma = first_numeric(
          record$t_age
        ),

        b_age_ma = first_numeric(
          record$b_age
        ),

        b_interval = first_integer(
          record$b_interval
        ),

        t_interval = first_integer(
          record$t_interval
        ),

        # These fields may contain multiple IDs.
        strat_name_ids = collapse_values(
          record$strat_name_id
        ),

        n_strat_name_ids = count_values(
          record$strat_name_id
        ),

        unit_ids = collapse_values(
          record$unit_id
        ),

        n_unit_ids = count_values(
          record$unit_id
        ),

        lith_classes = collapse_values(
          record$lith_classes
        ),

        lith_types = collapse_values(
          record$lith_types
        ),

        lith_ids = collapse_values(
          record$lith_id
        ),

        n_lith_ids = count_values(
          record$lith_id
        ),

        color = first_character(
          record$color
        ),

        area = first_numeric(
          record$area
        ),

        tiny_area = first_numeric(
          record$tiny_area
        ),

        small_area = first_numeric(
          record$small_area
        ),

        medium_area = first_numeric(
          record$medium_area
        ),

        large_area = first_numeric(
          record$large_area
        )
      )
    }
  )
)

legend <- legend |>
  mutate(
    age_complete =
      is.finite(t_age_ma) &
      is.finite(b_age_ma),

    age_order_valid =
      !age_complete |
      b_age_ma >= t_age_ma,

    age_mid_ma = if_else(
      age_complete,
      (
        t_age_ma +
        b_age_ma
      ) / 2,
      NA_real_
    ),

    age_range_ma = if_else(
      age_complete,
      b_age_ma -
        t_age_ma,
      NA_real_
    ),

    age_gt_500 = if_else(
      age_complete,
      age_mid_ma > 500,
      NA
    ),

    age_gt_1000 = if_else(
      age_complete,
      age_mid_ma > 1000,
      NA
    ),

    age_gt_1500 = if_else(
      age_complete,
      age_mid_ma > 1500,
      NA
    ),

    age_gt_2000 = if_else(
      age_complete,
      age_mid_ma > 2000,
      NA
    )
  ) |>
  arrange(
    legend_id
  )

valid_source_ids <- unique(
  legend$source_id[
    !is.na(legend$source_id)
  ]
)

if (
  length(valid_source_ids) != 1L ||
  valid_source_ids[[1]] != 154L
) {
  stop(
    "Unexpected source IDs: ",
    paste(
      valid_source_ids,
      collapse = ", "
    )
  )
}

safe_min <- function(x) {
  x <- x[
    is.finite(x)
  ]

  if (length(x) == 0L) {
    return(NA_real_)
  }

  min(x)
}

safe_max <- function(x) {
  x <- x[
    is.finite(x)
  ]

  if (length(x) == 0L) {
    return(NA_real_)
  }

  max(x)
}

qc <- tibble(
  metric = c(
    "n_records",
    "n_unique_legend_id",
    "n_duplicate_legend_id",
    "n_complete_age",
    "n_missing_age",
    "n_invalid_age_order",
    "minimum_t_age_ma",
    "maximum_b_age_ma",
    "n_unique_map_unit_name",
    "n_unique_lith",
    "n_records_multiple_strat_name_ids",
    "n_records_multiple_unit_ids",
    "n_records_multiple_lith_ids",
    "total_reported_area"
  ),

  value = c(
    nrow(legend),

    n_distinct(
      legend$legend_id,
      na.rm = TRUE
    ),

    sum(
      duplicated(
        legend$legend_id[
          !is.na(legend$legend_id)
        ]
      )
    ),

    sum(
      legend$age_complete
    ),

    sum(
      !legend$age_complete
    ),

    sum(
      !legend$age_order_valid
    ),

    safe_min(
      legend$t_age_ma
    ),

    safe_max(
      legend$b_age_ma
    ),

    n_distinct(
      legend$map_unit_name,
      na.rm = TRUE
    ),

    n_distinct(
      legend$lith,
      na.rm = TRUE
    ),

    sum(
      legend$n_strat_name_ids > 1L
    ),

    sum(
      legend$n_unit_ids > 1L
    ),

    sum(
      legend$n_lith_ids > 1L
    ),

    sum(
      legend$area,
      na.rm = TRUE
    )
  )
)

saveRDS(
  legend,
  file.path(
    processed_dir,
    "macrostrat_source154_legend.rds"
  )
)

write_csv(
  legend,
  file.path(
    output_dir,
    "source_154_legend_clean.csv"
  ),
  na = ""
)

write_csv(
  qc,
  file.path(
    output_dir,
    "source_154_legend_qc.csv"
  )
)

cat("\nSource 154 legend QC:\n")

print(
  qc,
  n = Inf,
  width = Inf
)

cat(
  "\nSaved processed legend:",
  file.path(
    processed_dir,
    "macrostrat_source154_legend.rds"
  ),
  "\n"
)

cat(
  "Saved clean CSV:",
  file.path(
    output_dir,
    "source_154_legend_clean.csv"
  ),
  "\n"
)

cat(
  "Saved QC CSV:",
  file.path(
    output_dir,
    "source_154_legend_qc.csv"
  ),
  "\n"
)
