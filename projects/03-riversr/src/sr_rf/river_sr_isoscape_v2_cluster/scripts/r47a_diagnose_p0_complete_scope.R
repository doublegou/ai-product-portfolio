#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(data.table)
})

options(
  stringsAsFactors = FALSE,
  scipen = 999
)

p0_file <- "data/processed/model_table_p0_full_range.rds"

r46_file <- paste0(
  "outputs/r46_full_range_local_lithology_compatibility/",
  "full_range_local_upstream_lithology_candidate.rds"
)

folds_file <- "data/processed/folds_long.rds"

out_dir <- "outputs/r47a_p0_scope_diagnosis"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

p0 <- as.data.table(readRDS(p0_file))
r46 <- as.data.table(readRDS(r46_file))
folds <- as.data.table(readRDS(folds_file))

clean_id <- function(x) {
  out <- trimws(as.character(x))
  out <- sub("\\.0+$", "", out)
  out[out %in% c("", "NA", "NaN", "NULL")] <- NA_character_
  out
}

count_complete <- function(dt, columns) {
  if (length(columns) == 0L) {
    return(NA_integer_)
  }

  sum(complete.cases(dt[, ..columns]))
}

cat("============================================================\n")
cat("R47A: P0 complete-sample diagnosis\n")
cat("============================================================\n")
cat("P0 rows:       ", nrow(p0), "\n")
cat("R46 rows:      ", nrow(r46), "\n")
cat("Folds rows:    ", nrow(folds), "\n")
cat("P0 columns:    ", ncol(p0), "\n\n")

# ------------------------------------------------------------------
# 1. Missingness of every P0 column
# ------------------------------------------------------------------

column_audit <- data.table(
  column = names(p0),
  class = vapply(
    p0,
    function(x) paste(class(x), collapse = "/"),
    character(1)
  ),
  n_missing = vapply(
    p0,
    function(x) sum(is.na(x)),
    integer(1)
  ),
  n_nonmissing = vapply(
    p0,
    function(x) sum(!is.na(x)),
    integer(1)
  ),
  n_unique_nonmissing = vapply(
    p0,
    function(x) uniqueN(x, na.rm = TRUE),
    integer(1)
  )
)

setorder(
  column_audit,
  -n_missing,
  column
)

fwrite(
  column_audit,
  file.path(out_dir, "p0_column_missingness.csv")
)

cat("Columns with exactly 4485 non-missing values:\n")

exact_4485_columns <- column_audit[
  n_nonmissing == 4485
]

if (nrow(exact_4485_columns) == 0L) {
  cat("  NONE\n")
} else {
  print(exact_4485_columns)
}

cat("\n")

# ------------------------------------------------------------------
# 2. Candidate baseline P0 feature groups
# ------------------------------------------------------------------

p0_prefixed <- grep(
  "^p0__",
  names(p0),
  value = TRUE
)

p0_numeric <- p0_prefixed[
  vapply(
    p0[, ..p0_prefixed],
    is.numeric,
    logical(1)
  )
]

p0_up_geo <- grep(
  "^p0__up_geo_",
  names(p0),
  value = TRUE
)

p0_non_geo <- setdiff(
  p0_prefixed,
  p0_up_geo
)

p0_numeric_non_geo <- intersect(
  p0_numeric,
  p0_non_geo
)

# Detect likely measured Sr response.
normalised_names <- tolower(
  gsub("[^a-z0-9]+", "_", names(p0))
)

exact_sr_names <- c(
  "sr",
  "sr_ratio",
  "sr87_86",
  "sr_87_86",
  "87sr_86sr",
  "87sr_86sr_ratio",
  "measured_sr"
)

sr_candidates <- names(p0)[
  normalised_names %in% exact_sr_names
]

if (length(sr_candidates) == 0L) {
  sr_candidates <- names(p0)[
    grepl("sr", normalised_names) &
      !grepl(
        "p0_|up_geo|lith|pred|resid|fold|sd$|se$",
        normalised_names
      )
  ]
}

sr_candidates <- sr_candidates[
  vapply(
    p0[, ..sr_candidates],
    is.numeric,
    logical(1)
  )
]

candidate_groups <- list(
  all_p0_prefixed = p0_prefixed,
  numeric_p0_prefixed = p0_numeric,
  p0_up_geo_only = p0_up_geo,
  p0_non_geo = p0_non_geo,
  numeric_p0_non_geo = p0_numeric_non_geo
)

if (length(sr_candidates) > 0L) {
  candidate_groups[
    ["numeric_p0_plus_first_sr"]
  ] <- list(
    unique(c(
      p0_numeric,
      sr_candidates[1L]
    ))
  )
}

group_audit <- rbindlist(
  lapply(
    names(candidate_groups),
    function(group_name) {
      columns <- candidate_groups[[group_name]]

      data.table(
        group = group_name,
        n_columns = length(columns),
        n_complete_rows = count_complete(p0, columns),
        n_excluded_rows =
          nrow(p0) - count_complete(p0, columns),
        columns = paste(columns, collapse = ";")
      )
    }
  ),
  fill = TRUE
)

fwrite(
  group_audit,
  file.path(out_dir, "candidate_complete_case_counts.csv")
)

cat("Candidate complete-case definitions:\n")
print(
  group_audit[
    ,
    .(
      group,
      n_columns,
      n_complete_rows,
      n_excluded_rows
    )
  ]
)

cat("\nLikely Sr response candidates:\n")
print(sr_candidates)

# ------------------------------------------------------------------
# 3. Look for existing inclusion or completeness flags
# ------------------------------------------------------------------

flag_name_hits <- names(p0)[
  grepl(
    paste(
      c(
        "complete",
        "included",
        "include",
        "eligible",
        "analysis",
        "model",
        "keep",
        "usable",
        "valid",
        "p0_sample"
      ),
      collapse = "|"
    ),
    names(p0),
    ignore.case = TRUE
  )
]

flag_rows <- list()
flag_i <- 0L

for (column in flag_name_hits) {
  x <- p0[[column]]

  if (is.logical(x)) {
    flag_i <- flag_i + 1L

    flag_rows[[flag_i]] <- data.table(
      column = column,
      rule = "logical_TRUE",
      selected_n = sum(x %in% TRUE, na.rm = TRUE),
      missing_n = sum(is.na(x))
    )
  }

  if (is.numeric(x)) {
    values <- sort(unique(x[!is.na(x)]))

    if (length(values) <= 10L) {
      for (value in values) {
        flag_i <- flag_i + 1L

        flag_rows[[flag_i]] <- data.table(
          column = column,
          rule = paste0("numeric_equals_", value),
          selected_n = sum(x == value, na.rm = TRUE),
          missing_n = sum(is.na(x))
        )
      }
    }
  }

  if (is.character(x) || is.factor(x)) {
    x_char <- as.character(x)
    values <- unique(x_char[!is.na(x_char)])

    if (length(values) <= 10L) {
      for (value in values) {
        flag_i <- flag_i + 1L

        flag_rows[[flag_i]] <- data.table(
          column = column,
          rule = paste0("value_equals_", value),
          selected_n = sum(x_char == value, na.rm = TRUE),
          missing_n = sum(is.na(x_char))
        )
      }
    }
  }
}

if (length(flag_rows) > 0L) {
  flag_audit <- rbindlist(flag_rows, fill = TRUE)
  setorder(flag_audit, abs(selected_n - 4485))

  fwrite(
    flag_audit,
    file.path(out_dir, "candidate_flag_counts.csv")
  )

  cat("\nPotential inclusion flags closest to 4485 rows:\n")
  print(head(flag_audit, 30))
} else {
  flag_audit <- data.table()
  cat("\nNo likely inclusion-flag columns detected.\n")
}

# ------------------------------------------------------------------
# 4. Determine whether any natural definition gives exactly 4485
# ------------------------------------------------------------------

exact_groups <- group_audit[
  n_complete_rows == 4485
]

exact_flags <- if (nrow(flag_audit) > 0L) {
  flag_audit[selected_n == 4485]
} else {
  data.table()
}

diagnosis <- c(
  "R47A P0 SCOPE DIAGNOSIS",
  "=======================",
  "",
  paste0("Raw P0 rows: ", nrow(p0)),
  paste0("R46 rows: ", nrow(r46)),
  paste0(
    "R46 unique row_id: ",
    if ("row_id" %in% names(r46)) {
      uniqueN(clean_id(r46$row_id), na.rm = TRUE)
    } else {
      "row_id not present"
    }
  ),
  paste0(
    "Folds unique row_id: ",
    if ("row_id" %in% names(folds)) {
      uniqueN(clean_id(folds$row_id), na.rm = TRUE)
    } else {
      "row_id not present"
    }
  ),
  "",
  paste0(
    "Complete-case groups yielding 4485: ",
    if (nrow(exact_groups) == 0L) {
      "NONE"
    } else {
      paste(exact_groups$group, collapse = ", ")
    }
  ),
  paste0(
    "Flag rules yielding 4485: ",
    if (nrow(exact_flags) == 0L) {
      "NONE"
    } else {
      paste(
        paste0(exact_flags$column, ":", exact_flags$rule),
        collapse = ", "
      )
    }
  )
)

writeLines(
  diagnosis,
  file.path(out_dir, "diagnosis_summary.txt")
)

cat("\n============================================================\n")
cat(paste(diagnosis, collapse = "\n"))
cat("\n============================================================\n")
