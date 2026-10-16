source("R/functions/core.R")

check_packages(c("tibble", "dplyr", "readr"))

cfg <- read_config()
root <- project_root()

anchor_file <- file.path(
  root,
  "data",
  "processed",
  "model_table_p0_full_range_r47_hybrid_local_lithology.rds"
)

hydrology_file <- file.path(
  root,
  "outputs",
  "full_range_rescue",
  "full_range_5km_site_base.rds"
)

out_dir <- file.path(
  root,
  "outputs",
  "r50_hydrology_alignment"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

anchor <- as.data.frame(
  readRDS(anchor_file)
)

hydrology <- as.data.frame(
  readRDS(hydrology_file)
)

row_id_col <- cfg$project$row_id
outcome_col <- cfg$project$outcome

classify_column <- function(name) {
  x <- tolower(name)

  dplyr::case_when(
    grepl(
      "row_id|global_row_id|site_id|hyriv_id|hybas_id",
      x
    ) ~ "identifier",

    grepl(
      "(^|[._])(lat|latitude)($|[._])",
      x
    ) ~ "latitude",

    grepl(
      "(^|[._])(lon|long|longitude)($|[._])",
      x
    ) ~ "longitude",

    grepl(
      "sr87.*sr86|^sr$|^sr[.]|[.]sr$",
      x
    ) &
      !grepl(
        "uncert|concentration|range",
        x
      ) ~ "sr_ratio",

    grepl(
      "catch|dis_av|dist_dn|dist_up|length|upland|ord_",
      x
    ) ~ "hydrology_predictor",

    TRUE ~ "other"
  )
}

describe_table <- function(data, table_name) {
  tibble::tibble(
    table = table_name,
    column = names(data),
    column_class = vapply(
      data,
      function(x) {
        paste(
          class(x),
          collapse = "|"
        )
      },
      character(1)
    ),
    role_guess = vapply(
      names(data),
      classify_column,
      character(1)
    ),
    n_missing = vapply(
      data,
      function(x) {
        sum(is.na(x))
      },
      integer(1)
    ),
    n_unique = vapply(
      data,
      function(x) {
        dplyr::n_distinct(
          x,
          na.rm = TRUE
        )
      },
      integer(1)
    )
  )
}

schema <- dplyr::bind_rows(
  describe_table(
    anchor,
    "anchor"
  ),
  describe_table(
    hydrology,
    "hydrology"
  )
)

readr::write_csv(
  schema,
  file.path(
    out_dir,
    "alignment_schema.csv"
  )
)

candidate_schema <- schema |>
  dplyr::filter(
    role_guess != "other"
  )

readr::write_csv(
  candidate_schema,
  file.path(
    out_dir,
    "alignment_candidate_columns.csv"
  )
)

summary_lines <- c(
  "R50A ALIGNMENT INSPECTION",
  "=========================",
  "",
  paste0(
    "Configured row ID: ",
    row_id_col
  ),
  paste0(
    "Configured outcome: ",
    outcome_col
  ),
  "",
  paste0(
    "Anchor rows: ",
    nrow(anchor)
  ),
  paste0(
    "Hydrology rows: ",
    nrow(hydrology)
  ),
  "",
  "Anchor candidate columns:",
  paste(
    candidate_schema$column[
      candidate_schema$table ==
        "anchor"
    ],
    collapse = ", "
  ),
  "",
  "Hydrology candidate columns:",
  paste(
    candidate_schema$column[
      candidate_schema$table ==
        "hydrology"
    ],
    collapse = ", "
  )
)

writeLines(
  summary_lines,
  file.path(
    out_dir,
    "inspection_summary.txt"
  )
)

cat(
  paste(
    summary_lines,
    collapse = "\n"
  ),
  "\n"
)

cat("\nANCHOR FIRST THREE ROWS\n")
print(
  anchor[
    seq_len(min(3L, nrow(anchor))),
    intersect(
      c(
        row_id_col,
        outcome_col,
        candidate_schema$column[
          candidate_schema$table ==
            "anchor"
        ]
      ),
      names(anchor)
    ),
    drop = FALSE
  ],
  width = Inf
)

cat("\nHYDROLOGY FIRST THREE ROWS\n")
print(
  hydrology[
    seq_len(min(3L, nrow(hydrology))),
    candidate_schema$column[
      candidate_schema$table ==
        "hydrology"
    ],
    drop = FALSE
  ],
  width = Inf
)
