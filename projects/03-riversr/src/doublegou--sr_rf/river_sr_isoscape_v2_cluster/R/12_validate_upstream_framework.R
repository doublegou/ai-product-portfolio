source("R/functions/core.R")
source("R/functions/upstream_accumulation.R")

check_packages(
  c(
    "dplyr",
    "readr",
    "tibble"
  )
)

library(dplyr)
library(readr)
library(tibble)

legacy_root <- file.path(
  Sys.getenv("HOME"),
  "projects/sr_global"
)

out_dir <- file.path(
  project_root(),
  "outputs/upstream_framework_validation"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

tolerance <- 1e-8

dataset_specs <- tribble(
  ~dataset, ~kind, ~directory, ~pattern,

  "glim",
  "categorical",
  file.path(
    legacy_root,
    "data_processed/global/glim_l6_by_region"
  ),
  "^l6_glim_local_upstream_[a-z]{2}\\.rds$",

  "climate_terrain",
  "continuous",
  file.path(
    legacy_root,
    "data_processed/global/climate_terrain_l6_by_region"
  ),
  "^l6_climate_terrain_local_upstream_[a-z]{2}\\.rds$",

  "soil",
  "continuous",
  file.path(
    legacy_root,
    "data_processed/global/soil_l6_by_region"
  ),
  "^l6_soil_local_upstream_[a-z]{2}\\.rds$"
)

comparison_difference <- function(
    calculated,
    stored
) {
  difference <- abs(
    calculated -
      stored
  )

  both_missing <- (
    is.na(calculated) &
      is.na(stored)
  )

  one_missing <- xor(
    is.na(calculated),
    is.na(stored)
  )

  difference[both_missing] <- 0
  difference[one_missing] <- Inf

  difference
}

safe_max <- function(x) {
  if (length(x) == 0L) {
    return(NA_real_)
  }

  if (all(is.na(x))) {
    return(NA_real_)
  }

  max(
    x,
    na.rm = TRUE
  )
}

extract_region <- function(path) {
  filename <- basename(path)

  match <- regmatches(
    filename,
    regexpr(
      "_[a-z]{2}\\.rds$",
      filename
    )
  )

  if (length(match) == 0L) {
    return(NA_character_)
  }

  region <- sub(
    "^_",
    "",
    match
  )

  sub(
    "\\.rds$",
    "",
    region
  )
}

validate_categorical <- function(
    data,
    downstream_index,
    dataset,
    region,
    source_file
) {
  local_columns <- grep(
    "^local_area_",
    names(data),
    value = TRUE
  )

  up_columns <- sub(
    "^local_area_",
    "up_area_",
    local_columns
  )

  available <- up_columns %in%
    names(data)

  local_columns <- local_columns[
    available
  ]

  up_columns <- up_columns[
    available
  ]

  if (length(local_columns) == 0L) {
    return(tibble())
  }

  local_matrix <- as.matrix(
    data[
      local_columns
    ]
  )

  calculated <- accumulate_downstream(
    local_matrix,
    downstream_index
  )

  colnames(calculated) <-
    up_columns

  stored <- as.matrix(
    data[
      up_columns
    ]
  )

  difference <- comparison_difference(
    calculated,
    stored
  )

  bind_rows(
    lapply(
      seq_along(up_columns),
      function(i) {
        finite_difference <-
          difference[, i]

        tibble(
          dataset = dataset,
          region = region,
          source_file = source_file,
          variable =
            sub(
              "^up_area_",
              "",
              up_columns[i]
            ),
          comparison_type =
            "accumulated_area",
          n = nrow(data),
          max_abs_difference =
            safe_max(
              finite_difference
            ),
          n_difference_gt_tolerance =
            sum(
              finite_difference >
                tolerance,
              na.rm = TRUE
            ),
          numerical_match =
            all(
              finite_difference <=
                tolerance
            )
        )
      }
    )
  )
}

validate_continuous <- function(
    data,
    downstream_index,
    dataset,
    region,
    source_file
) {
  local_candidates <- grep(
    "^local_",
    names(data),
    value = TRUE
  )

  local_candidates <- local_candidates[
    !grepl(
      paste0(
        "_valid_area_km2$|",
        "_coverage_ratio$|",
        "_numerator$|",
        "^local_total_extracted_area_km2$"
      ),
      local_candidates
    )
  ]

  variable_names <- sub(
    "^local_",
    "",
    local_candidates
  )

  required_complete <- vapply(
    variable_names,
    function(variable_name) {
      all(
        c(
          paste0(
            "local_",
            variable_name
          ),
          paste0(
            "local_",
            variable_name,
            "_valid_area_km2"
          ),
          paste0(
            "up_",
            variable_name
          ),
          paste0(
            "up_",
            variable_name,
            "_valid_area_km2"
          )
        ) %in%
          names(data)
      )
    },
    logical(1)
  )

  variable_names <- variable_names[
    required_complete
  ]

  if (length(variable_names) == 0L) {
    return(tibble())
  }

  accumulation_list <- list()
  accumulation_names <- character()

  for (variable_name in variable_names) {
    local_mean <- data[[
      paste0(
        "local_",
        variable_name
      )
    ]]

    local_area <- data[[
      paste0(
        "local_",
        variable_name,
        "_valid_area_km2"
      )
    ]]

    local_sum <- local_mean *
      local_area

    local_sum[
      !is.finite(local_sum)
    ] <- 0

    local_area[
      !is.finite(local_area)
    ] <- 0

    accumulation_list[[
      length(accumulation_list) + 1L
    ]] <- local_sum

    accumulation_names <- c(
      accumulation_names,
      paste0(
        "sum__",
        variable_name
      )
    )

    accumulation_list[[
      length(accumulation_list) + 1L
    ]] <- local_area

    accumulation_names <- c(
      accumulation_names,
      paste0(
        "area__",
        variable_name
      )
    )
  }

  local_matrix <- do.call(
    cbind,
    accumulation_list
  )

  colnames(local_matrix) <-
    accumulation_names

  accumulated <- accumulate_downstream(
    local_matrix,
    downstream_index
  )

  comparison_rows <- list()

  for (variable_name in variable_names) {
    accumulated_sum <- accumulated[
      ,
      paste0(
        "sum__",
        variable_name
      )
    ]

    accumulated_area <- accumulated[
      ,
      paste0(
        "area__",
        variable_name
      )
    ]

    calculated_mean <- ifelse(
      accumulated_area > 0,
      accumulated_sum /
        accumulated_area,
      NA_real_
    )

    stored_mean <- data[[
      paste0(
        "up_",
        variable_name
      )
    ]]

    stored_area <- data[[
      paste0(
        "up_",
        variable_name,
        "_valid_area_km2"
      )
    ]]

    mean_difference <- comparison_difference(
      calculated_mean,
      stored_mean
    )

    area_difference <- comparison_difference(
      accumulated_area,
      stored_area
    )

    comparison_rows[[
      length(comparison_rows) + 1L
    ]] <- tibble(
      dataset = dataset,
      region = region,
      source_file = source_file,
      variable = variable_name,
      comparison_type =
        "upstream_weighted_mean",
      n = nrow(data),
      max_abs_difference =
        safe_max(
          mean_difference
        ),
      n_difference_gt_tolerance =
        sum(
          mean_difference >
            tolerance,
          na.rm = TRUE
        ),
      numerical_match =
        all(
          mean_difference <=
            tolerance
        )
    )

    comparison_rows[[
      length(comparison_rows) + 1L
    ]] <- tibble(
      dataset = dataset,
      region = region,
      source_file = source_file,
      variable = variable_name,
      comparison_type =
        "upstream_valid_area",
      n = nrow(data),
      max_abs_difference =
        safe_max(
          area_difference
        ),
      n_difference_gt_tolerance =
        sum(
          area_difference >
            tolerance,
          na.rm = TRUE
        ),
      numerical_match =
        all(
          area_difference <=
            tolerance
        )
    )
  }

  bind_rows(
    comparison_rows
  )
}

all_files <- bind_rows(
  lapply(
    seq_len(
      nrow(dataset_specs)
    ),
    function(i) {
      spec <- dataset_specs[i, ]

      if (!dir.exists(spec$directory)) {
        return(tibble())
      }

      paths <- list.files(
        spec$directory,
        pattern = spec$pattern,
        full.names = TRUE
      )

      if (length(paths) == 0L) {
        return(tibble())
      }

      tibble(
        dataset = spec$dataset,
        kind = spec$kind,
        path = paths,
        region = vapply(
          paths,
          extract_region,
          character(1)
        )
      )
    }
  )
)

if (nrow(all_files) == 0L) {
  stop(
    "No legacy regional upstream tables were found."
  )
}

network_rows <- list()
external_rows <- list()
comparison_rows <- list()

for (i in seq_len(nrow(all_files))) {
  dataset <- all_files$dataset[i]
  kind <- all_files$kind[i]
  source_file <- all_files$path[i]
  region <- all_files$region[i]

  cat(
    "Validating ",
    dataset,
    " / ",
    region,
    "\n",
    sep = ""
  )

  data <- readRDS(
    source_file
  )

  required_network_columns <- c(
    "HYBAS_ID",
    "NEXT_DOWN"
  )

  missing_network_columns <- setdiff(
    required_network_columns,
    names(data)
  )

  if (
    length(
      missing_network_columns
    ) > 0L
  ) {
    network_rows[[
      length(network_rows) + 1L
    ]] <- tibble(
      dataset = dataset,
      region = region,
      source_file = source_file,
      n_basins = nrow(data),
      n_external = NA_integer_,
      has_cycle = NA,
      status = paste0(
        "missing_columns:",
        paste(
          missing_network_columns,
          collapse = ";"
        )
      )
    )

    next
  }

  network <- build_downstream_index(
    data$HYBAS_ID,
    data$NEXT_DOWN,
    external_action = "outlet"
  )

  has_cycle <- network_has_cycle(
    network$downstream_index
  )

  network_rows[[
    length(network_rows) + 1L
  ]] <- tibble(
    dataset = dataset,
    region = region,
    source_file = source_file,
    n_basins = nrow(data),
    n_external = network$n_external,
    has_cycle = has_cycle,
    status = ifelse(
      has_cycle,
      "cycle_detected",
      "network_valid"
    )
  )

  if (network$n_external > 0L) {
    external_rows[[
      length(external_rows) + 1L
    ]] <- tibble(
      dataset = dataset,
      region = region,
      source_file = source_file,
      basin_id =
        network$external_basin_id,
      external_next_down =
        network$external_next_down
    )
  }

  if (has_cycle) {
    next
  }

  validation <- if (
    kind ==
      "categorical"
  ) {
    validate_categorical(
      data,
      network$downstream_index,
      dataset,
      region,
      source_file
    )
  } else {
    validate_continuous(
      data,
      network$downstream_index,
      dataset,
      region,
      source_file
    )
  }

  comparison_rows[[
    length(comparison_rows) + 1L
  ]] <- validation
}

network_summary <- bind_rows(
  network_rows
)

external_links <- bind_rows(
  external_rows
)

variable_comparison <- bind_rows(
  comparison_rows
)

if (nrow(external_links) == 0L) {
  external_links <- tibble(
    dataset = character(),
    region = character(),
    source_file = character(),
    basin_id = character(),
    external_next_down = character()
  )
}

if (nrow(variable_comparison) == 0L) {
  variable_comparison <- tibble(
    dataset = character(),
    region = character(),
    source_file = character(),
    variable = character(),
    comparison_type = character(),
    n = integer(),
    max_abs_difference = double(),
    n_difference_gt_tolerance = integer(),
    numerical_match = logical()
  )
}

region_summary <- variable_comparison |>
  group_by(
    dataset,
    region
  ) |>
  summarise(
    n_comparisons = n(),
    all_numerical_match =
      all(numerical_match),
    maximum_difference =
      safe_max(
        max_abs_difference
      ),
    total_differences_gt_tolerance =
      sum(
        n_difference_gt_tolerance
      ),
    .groups = "drop"
  ) |>
  left_join(
    network_summary,
    by = c(
      "dataset",
      "region"
    )
  ) |>
  arrange(
    dataset,
    region
  )

write_csv(
  network_summary,
  file.path(
    out_dir,
    "network_summary.csv"
  )
)

write_csv(
  external_links,
  file.path(
    out_dir,
    "external_downstream_links.csv"
  )
)

write_csv(
  variable_comparison,
  file.path(
    out_dir,
    "variable_comparison.csv"
  )
)

write_csv(
  region_summary,
  file.path(
    out_dir,
    "region_validation_summary.csv"
  )
)

cat("\nNetwork summary:\n")

print(
  network_summary,
  n = Inf,
  width = Inf
)

cat("\nRegional numerical validation:\n")

print(
  region_summary |>
    select(
      dataset,
      region,
      n_basins,
      n_external,
      has_cycle,
      n_comparisons,
      all_numerical_match,
      maximum_difference,
      total_differences_gt_tolerance
    ),
  n = Inf,
  width = Inf
)

cat("\nExternal downstream links:\n")

print(
  external_links,
  n = Inf,
  width = Inf
)

log_msg(
  "Upstream framework validation complete: ",
  out_dir
)
