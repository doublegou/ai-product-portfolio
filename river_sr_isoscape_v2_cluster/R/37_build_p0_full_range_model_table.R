options(stringsAsFactors = FALSE, scipen = 999)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

base <- readRDS(
  "data/processed/model_table.rds"
)

pfull <- readRDS(
  "data/external/predictors_at_sites_full_range.rds"
)

if (inherits(base, "sf")) {
  base <- sf::st_drop_geometry(base)
}

if (inherits(pfull, "sf")) {
  pfull <- sf::st_drop_geometry(pfull)
}

base <- as.data.frame(base)
pfull <- as.data.frame(pfull)

base$row_id <- as.character(base$row_id)
pfull$row_id <- as.character(pfull$row_id)

if (anyDuplicated(base$row_id)) {
  stop("Duplicate row_id in model_table.rds")
}

if (anyDuplicated(pfull$row_id)) {
  stop("Duplicate row_id in full-range predictor asset")
}

if (!setequal(base$row_id, pfull$row_id)) {
  stop("row_id sets differ between model table and predictor asset")
}

p0 <- grep(
  "^p0__",
  names(base),
  value = TRUE
)

if (length(p0) != 28L) {
  stop(
    "Expected 28 P0 variables; found ",
    length(p0)
  )
}

missing_p0 <- setdiff(
  p0,
  names(pfull)
)

if (length(missing_p0) > 0L) {
  stop(
    "Full-range predictor asset missing: ",
    paste(missing_p0, collapse = ", ")
  )
}

# ------------------------------------------------------------
# Original completeness
# ------------------------------------------------------------

old_complete <- complete.cases(
  base[, p0, drop = FALSE]
)

# ------------------------------------------------------------
# Replace ONLY P0 columns, matched strictly by row_id
# ------------------------------------------------------------

idx <- match(
  base$row_id,
  pfull$row_id
)

if (anyNA(idx)) {
  stop("row_id matching failed")
}

full <- base

for (v in p0) {
  full[[v]] <- pfull[[v]][idx]
}

new_complete <- complete.cases(
  full[, p0, drop = FALSE]
)

# ------------------------------------------------------------
# Ensure previously-complete P0 values did not change
# ------------------------------------------------------------

old_mat <- as.matrix(
  base[old_complete, p0, drop = FALSE]
)

new_mat <- as.matrix(
  full[old_complete, p0, drop = FALSE]
)

storage.mode(old_mat) <- "numeric"
storage.mode(new_mat) <- "numeric"

max_diff <- max(
  abs(old_mat - new_mat),
  na.rm = TRUE
)

if (!is.finite(max_diff) || max_diff > 1e-12) {
  stop(
    "Existing complete P0 rows changed. max diff = ",
    max_diff
  )
}

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

summary <- data.frame(
  metric = c(
    "total_rows",
    "old_complete_p0",
    "new_complete_p0",
    "newly_rescued",
    "remaining_incomplete",
    "complete_sr_ge_0p800",
    "complete_sr_ge_0p900",
    "max_sr_complete",
    "old_complete_max_p0_diff"
  ),
  value = c(
    nrow(full),
    sum(old_complete),
    sum(new_complete),
    sum(!old_complete & new_complete),
    sum(!new_complete),
    sum(
      new_complete &
      full$sr87_sr86 >= 0.800,
      na.rm = TRUE
    ),
    sum(
      new_complete &
      full$sr87_sr86 >= 0.900,
      na.rm = TRUE
    ),
    max(
      full$sr87_sr86[new_complete],
      na.rm = TRUE
    ),
    max_diff
  )
)

write_csv(
  summary,
  "outputs/full_range_p0_recovery_safe/model_table_full_range_summary.csv"
)

saveRDS(
  full,
  "data/processed/model_table_p0_full_range.rds"
)

cat(
  "\n===== FULL-RANGE MODEL TABLE =====\n"
)

print(
  summary,
  row.names = FALSE
)

cat(
  "\nSaved: data/processed/model_table_p0_full_range.rds\n"
)

