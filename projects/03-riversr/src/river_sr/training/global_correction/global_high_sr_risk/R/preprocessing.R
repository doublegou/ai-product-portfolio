risk_numeric_predictors <- function(dat, predictors) {
  x <- dat[predictors]
  non_numeric <- predictors[!vapply(x, is.numeric, logical(1L))]
  risk_assert(length(non_numeric) == 0L, paste("Non-numeric predictors:", paste(non_numeric, collapse = ", ")))
  x
}

risk_fit_medians <- function(x) {
  medians <- vapply(x, function(column) {
    if (all(is.na(column))) return(NA_real_)
    stats::median(column, na.rm = TRUE)
  }, numeric(1L))
  risk_assert(!anyNA(medians), paste("Predictors entirely missing in training fold:", paste(names(medians)[is.na(medians)], collapse = ", ")))
  medians
}

risk_apply_medians <- function(x, medians) {
  risk_assert(identical(names(x), names(medians)), "Predictor order differs from the imputation vector.")
  result <- x
  for (feature in names(medians)) {
    missing <- is.na(result[[feature]])
    if (any(missing)) result[[feature]][missing] <- medians[[feature]]
  }
  risk_assert(!anyNA(result), "Missing values remain after training-fold median imputation.")
  result
}
