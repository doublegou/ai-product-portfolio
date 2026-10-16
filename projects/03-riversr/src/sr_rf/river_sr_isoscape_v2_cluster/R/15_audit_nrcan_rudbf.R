suppressPackageStartupMessages({
  library(sf)
  library(foreign)
})

base_dir <- file.path(
  "data",
  "raw",
  "geology",
  "nrcan_of5529",
  "of_5529_selected"
)

shp_path <- file.path(
  base_dir,
  "data",
  "ArcMap9_ArcReader9",
  "AllThemesMerged",
  "roxworld.shp"
)

rudbf_dir <- file.path(
  base_dir,
  "data",
  "DBase_Files",
  "rudbf"
)

output_dir <- file.path(
  "outputs",
  "nrcan_of5529",
  "rudbf_audit"
)

dir.create(
  output_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

if (!file.exists(shp_path)) {
  stop("Missing shapefile: ", shp_path)
}

if (!dir.exists(rudbf_dir)) {
  stop("Missing DBF directory: ", rudbf_dir)
}

cat("Reading roxworld shapefile...\n")

rox <- st_read(
  shp_path,
  quiet = TRUE,
  stringsAsFactors = FALSE
)

if (!"RUNO" %in% names(rox)) {
  stop("RUNO field not found in roxworld.")
}

rox_runo <- suppressWarnings(
  as.numeric(
    as.character(
      st_drop_geometry(rox)$RUNO
    )
  )
)

rox_runo <- sort(
  unique(
    rox_runo[
      is.finite(rox_runo)
    ]
  )
)

cat("roxworld polygons:", nrow(rox), "\n")
cat("Unique RUNO values:", length(rox_runo), "\n")

dbf_files <- list.files(
  rudbf_dir,
  pattern = "\\.dbf$",
  full.names = TRUE,
  ignore.case = TRUE
)

cat("DBF files discovered:", length(dbf_files), "\n")

read_dbf_safe <- function(path) {
  tryCatch(
    {
      data <- foreign::read.dbf(
        path,
        as.is = TRUE
      )

      list(
        ok = TRUE,
        data = data,
        error = NA_character_
      )
    },
    error = function(e) {
      list(
        ok = FALSE,
        data = NULL,
        error = conditionMessage(e)
      )
    }
  )
}

table_results <- lapply(
  dbf_files,
  read_dbf_safe
)

names(table_results) <- tools::file_path_sans_ext(
  basename(dbf_files)
)

successful_tables <- table_results[
  vapply(
    table_results,
    function(x) x$ok,
    logical(1)
  )
]

failed_tables <- table_results[
  !vapply(
    table_results,
    function(x) x$ok,
    logical(1)
  )
]

cat("Successfully read:", length(successful_tables), "\n")
cat("Read failures:", length(failed_tables), "\n")

table_summary_rows <- list()
column_catalog_rows <- list()
runo_overlap_rows <- list()

summary_index <- 1L
column_index <- 1L
overlap_index <- 1L

for (table_name in names(successful_tables)) {

  table_data <- successful_tables[[table_name]]$data

  table_summary_rows[[summary_index]] <- data.frame(
    table = table_name,
    n_rows = nrow(table_data),
    n_columns = ncol(table_data),
    columns = paste(
      names(table_data),
      collapse = ";"
    ),
    stringsAsFactors = FALSE
  )

  summary_index <- summary_index + 1L

  for (column_name in names(table_data)) {

    column_data <- table_data[[column_name]]

    nonmissing <- column_data[
      !is.na(column_data)
    ]

    column_catalog_rows[[column_index]] <- data.frame(
      table = table_name,
      column = column_name,
      class = paste(
        class(column_data),
        collapse = ";"
      ),
      n_nonmissing = length(nonmissing),
      n_unique = length(
        unique(nonmissing)
      ),
      stringsAsFactors = FALSE
    )

    column_index <- column_index + 1L

    character_values <- as.character(column_data)

    character_values <- iconv(
      character_values,
      from = "latin1",
      to = "UTF-8",
      sub = ""
    )

    numeric_values <- suppressWarnings(
      as.numeric(
        trimws(character_values)
      )
    )

    numeric_values <- sort(
      unique(
        numeric_values[
          is.finite(numeric_values)
        ]
      )
    )

    overlap_values <- intersect(
      numeric_values,
      rox_runo
    )

    runo_overlap_rows[[overlap_index]] <- data.frame(
      table = table_name,
      column = column_name,
      n_numeric_unique = length(numeric_values),
      n_overlap_runo = length(overlap_values),
      coverage_rox_runo = if (
        length(rox_runo) > 0
      ) {
        length(overlap_values) /
          length(rox_runo)
      } else {
        NA_real_
      },
      coverage_column = if (
        length(numeric_values) > 0
      ) {
        length(overlap_values) /
          length(numeric_values)
      } else {
        NA_real_
      },
      overlap_examples = paste(
        head(overlap_values, 10),
        collapse = ";"
      ),
      stringsAsFactors = FALSE
    )

    overlap_index <- overlap_index + 1L
  }
}

table_summary <- do.call(
  rbind,
  table_summary_rows
)

column_catalog <- do.call(
  rbind,
  column_catalog_rows
)

runo_overlap <- do.call(
  rbind,
  runo_overlap_rows
)

table_summary <- table_summary[
  order(table_summary$table),
]

runo_overlap <- runo_overlap[
  order(
    -runo_overlap$n_overlap_runo,
    -runo_overlap$coverage_rox_runo,
    runo_overlap$table,
    runo_overlap$column
  ),
]

candidate_pattern <- paste(
  c(
    "RUNO",
    "RU_NO",
    "ROCK",
    "AGE",
    "TERM",
    "MIN",
    "MAX",
    "TOP",
    "BASE",
    "BOTTOM",
    "FROM",
    "TO",
    "ID",
    "CODE"
  ),
  collapse = "|"
)

candidate_fields <- column_catalog[
  grepl(
    candidate_pattern,
    toupper(column_catalog$column)
  ),
]

write.csv(
  table_summary,
  file.path(
    output_dir,
    "rudbf_table_summary.csv"
  ),
  row.names = FALSE
)

write.csv(
  column_catalog,
  file.path(
    output_dir,
    "rudbf_column_catalog.csv"
  ),
  row.names = FALSE
)

write.csv(
  runo_overlap,
  file.path(
    output_dir,
    "rudbf_runo_overlap.csv"
  ),
  row.names = FALSE
)

write.csv(
  candidate_fields,
  file.path(
    output_dir,
    "rudbf_candidate_fields.csv"
  ),
  row.names = FALSE
)

if (length(failed_tables) > 0) {

  failure_table <- do.call(
    rbind,
    lapply(
      names(failed_tables),
      function(table_name) {
        data.frame(
          table = table_name,
          error = failed_tables[[table_name]]$error,
          stringsAsFactors = FALSE
        )
      }
    )
  )

  write.csv(
    failure_table,
    file.path(
      output_dir,
      "rudbf_read_failures.csv"
    ),
    row.names = FALSE
  )
}

saveRDS(
  lapply(
    successful_tables,
    function(x) x$data
  ),
  file.path(
    output_dir,
    "rudbf_tables.rds"
  )
)

cat("\n========================================\n")
cat("TOP RUNO OVERLAP CANDIDATES\n")
cat("========================================\n")

top_overlap <- runo_overlap[
  runo_overlap$n_overlap_runo > 0,
]

print(
  head(
    top_overlap,
    50
  ),
  row.names = FALSE
)

core_tables <- c(
  "agetsmlt",
  "ruagedf",
  "ruagedt",
  "ruct",
  "rudf",
  "rudt",
  "rulinkct",
  "rupo"
)

for (table_name in core_tables) {

  if (!table_name %in% names(successful_tables)) {
    cat(
      "\nTABLE NOT FOUND:",
      table_name,
      "\n"
    )

    next
  }

  table_data <- successful_tables[[table_name]]$data

  cat("\n========================================\n")
  cat("TABLE:", table_name, "\n")
  cat("========================================\n")

  cat(
    "Dimensions:",
    nrow(table_data),
    "rows x",
    ncol(table_data),
    "columns\n"
  )

  cat("Columns:\n")

  print(
    names(table_data)
  )

  cat("First eight records:\n")

  print(
    head(
      table_data,
      8
    ),
    row.names = FALSE
  )
}

cat("\nAudit outputs saved to:\n")
cat(output_dir, "\n")
