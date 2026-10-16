corr_numeric_frame <- function(dat, predictors) {
  x <- dat[predictors]
  bad <- predictors[!vapply(x, is.numeric, logical(1L))]
  corr_assert(length(bad) == 0L, paste("Non-numeric predictors:", paste(bad, collapse = ", ")))
  x
}

corr_fit_medians <- function(x) {
  values <- vapply(x, function(column) if (all(is.na(column))) NA_real_ else stats::median(column, na.rm = TRUE), numeric(1L))
  corr_assert(!anyNA(values), paste("Predictors entirely missing in training data:", paste(names(values)[is.na(values)], collapse = ", ")))
  values
}

corr_apply_medians <- function(x, medians) {
  corr_assert(identical(names(x), names(medians)), "Predictor order differs from the median vector.")
  result <- x
  for (feature in names(medians)) {
    missing <- is.na(result[[feature]])
    if (any(missing)) result[[feature]][missing] <- medians[[feature]]
  }
  corr_assert(!anyNA(result), "Missing values remain after training-only median imputation.")
  result
}

corr_fit_scaler <- function(x, tolerance) {
  center <- vapply(x, mean, numeric(1L))
  scale <- vapply(x, stats::sd, numeric(1L))
  scale[!is.finite(scale) | scale <= tolerance] <- 1
  list(center = center, scale = scale)
}

corr_apply_scaler <- function(x, scaler) {
  corr_assert(identical(names(x), names(scaler$center)) && identical(names(x), names(scaler$scale)), "Scaler predictor order changed.")
  result <- sweep(as.matrix(x), 2L, scaler$center, "-")
  result <- sweep(result, 2L, scaler$scale, "/")
  storage.mode(result) <- "double"
  corr_assert(all(is.finite(result)), "Non-finite values remain after scaling.")
  result
}

corr_prepare_matrices <- function(train, assessment, predictors, standardize = FALSE, tolerance = 1e-12) {
  x_train_raw <- corr_numeric_frame(train, predictors)
  x_assessment_raw <- corr_numeric_frame(assessment, predictors)
  medians <- corr_fit_medians(x_train_raw)
  x_train <- corr_apply_medians(x_train_raw, medians)
  x_assessment <- corr_apply_medians(x_assessment_raw, medians)
  if (standardize) {
    scaler <- corr_fit_scaler(x_train, tolerance)
    train_matrix <- corr_apply_scaler(x_train, scaler)
    assessment_matrix <- corr_apply_scaler(x_assessment, scaler)
  } else {
    scaler <- NULL
    train_matrix <- as.matrix(x_train)
    assessment_matrix <- as.matrix(x_assessment)
    storage.mode(train_matrix) <- "double"
    storage.mode(assessment_matrix) <- "double"
  }
  list(train = train_matrix, assessment = assessment_matrix, medians = medians, scaler = scaler)
}
