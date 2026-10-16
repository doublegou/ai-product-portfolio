rrisk11_numeric_predictors <- function(dat, predictors) {
  x <- dat[predictors]
  non_numeric <- predictors[!vapply(x, is.numeric, logical(1L))]
  rrisk11_assert(length(non_numeric) == 0L, paste("Non-numeric predictors:", paste(non_numeric, collapse = ", ")))
  x
}

rrisk11_fit_medians <- function(x) {
  medians <- vapply(x, function(column) if (all(is.na(column))) NA_real_ else stats::median(column, na.rm = TRUE), numeric(1L))
  rrisk11_assert(!anyNA(medians), paste("Predictors entirely missing in training:", paste(names(medians)[is.na(medians)], collapse = ", ")))
  medians
}

rrisk11_apply_medians <- function(x, medians) {
  rrisk11_assert(identical(names(x), names(medians)), "Predictor order differs from the imputation vector.")
  result <- x
  for (feature in names(medians)) {
    missing <- is.na(result[[feature]])
    if (any(missing)) result[[feature]][missing] <- medians[[feature]]
  }
  rrisk11_assert(!anyNA(result), "Missing values remain after training-only median imputation.")
  result
}

rrisk11_add_fit_weights <- function(dat) {
  sizes <- table(dat$.regional_branch_id)
  raw <- 1 / sqrt(as.numeric(sizes[dat$.regional_branch_id]))
  dat$.fit_weight <- raw / mean(raw)
  rrisk11_assert(abs(mean(dat$.fit_weight) - 1) < 1e-12, "GAM fit weights are not normalized to mean one within analysis data.")
  dat
}
