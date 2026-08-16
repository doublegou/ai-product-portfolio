rrisk_numeric_predictors <- function(dat, predictors) {
  x <- dat[predictors]
  non_numeric <- predictors[!vapply(x, is.numeric, logical(1L))]
  rrisk_assert(length(non_numeric) == 0L, paste("Non-numeric predictors:", paste(non_numeric, collapse = ", ")))
  x
}

rrisk_fit_medians <- function(x) {
  medians <- vapply(x, function(column) if (all(is.na(column))) NA_real_ else stats::median(column, na.rm = TRUE), numeric(1L))
  rrisk_assert(!anyNA(medians), paste("Predictors entirely missing in Outer training:", paste(names(medians)[is.na(medians)], collapse = ", ")))
  medians
}

rrisk_apply_medians <- function(x, medians) {
  rrisk_assert(identical(names(x), names(medians)), "Predictor order differs from the imputation vector.")
  result <- x
  for (feature in names(medians)) { missing <- is.na(result[[feature]]); if (any(missing)) result[[feature]][missing] <- medians[[feature]] }
  rrisk_assert(!anyNA(result), "Missing values remain after Outer-training median imputation.")
  result
}

rrisk_branch_weights <- function(branch_id) {
  sizes <- table(branch_id); raw <- 1 / sqrt(as.numeric(sizes[branch_id])); raw / mean(raw)
}
