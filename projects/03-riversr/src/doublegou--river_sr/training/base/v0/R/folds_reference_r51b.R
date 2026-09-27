v0_build_reference_folds <- function(dat, context) {
  v0_require_packages("dplyr")
  columns <- context$config$columns
  row_id <- as.character(dat[[columns$row_id]])
  reference <- trimws(as.character(dat[[columns$reference]]))
  rows <- data.frame(
    row_id = row_id,
    scheme = "reference",
    validation_unit = reference,
    stringsAsFactors = FALSE
  )
  outer_k <- as.integer(context$config$validation$outer_folds)
  inner_k <- as.integer(context$config$validation$inner_folds)
  units <- dplyr::count(rows, validation_unit, name = "n_rows")
  assigned <- v0_assign_units_balanced(units, outer_k, as.integer(context$config$validation$reference_outer_seed))
  outer <- dplyr::left_join(rows, assigned[c("validation_unit", "fold")], by = "validation_unit")
  names(outer)[names(outer) == "fold"] <- "outer_fold"
  inner_records <- list()

  for (outer_fold in seq_len(outer_k)) {
    training <- outer[outer$outer_fold != outer_fold, , drop = FALSE]
    inner_units <- dplyr::count(training, validation_unit, name = "n_rows")
    inner_assigned <- v0_assign_units_balanced(
      inner_units,
      inner_k,
      as.integer(context$config$validation$reference_inner_seed_base) + outer_fold
    )
    inner <- dplyr::left_join(training, inner_assigned[c("validation_unit", "fold")], by = "validation_unit")
    names(inner)[names(inner) == "fold"] <- "inner_fold"
    inner$outer_fold <- outer_fold
    inner_records[[as.character(outer_fold)]] <- inner[c(
      "row_id", "scheme", "outer_fold", "inner_fold", "validation_unit"
    )]
  }

  list(
    outer = outer[c("row_id", "scheme", "outer_fold", "validation_unit")],
    inner = dplyr::bind_rows(inner_records)
  )
}
