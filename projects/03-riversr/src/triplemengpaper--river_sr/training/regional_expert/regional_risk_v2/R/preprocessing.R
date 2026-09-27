rrisk2_predictors <- function(context, feature_set) {
  full50 <- rrisk2_read_lines(rrisk2_path(context, context$config$input$full50_predictors))
  process14 <- rrisk2_read_lines(rrisk2_path(context, context$config$input$process14_predictors))
  rrisk2_assert(length(full50) == 50L && length(process14) == 14L && !anyDuplicated(c(full50, process14)), "Predictor manifests are invalid.")
  if (identical(feature_set, "full50")) return(full50)
  rrisk2_assert(identical(feature_set, "full50_process"), paste("Unknown feature set:", feature_set))
  c(full50, process14)
}

rrisk2_numeric_matrix <- function(dat, predictors, medians = NULL) {
  x <- dat[predictors]
  rrisk2_assert(all(vapply(x, is.numeric, logical(1L))), "All model predictors must be numeric.")
  if (is.null(medians)) {
    rrisk2_assert(!anyNA(x), "V2 frozen predictors contain missing values; missing-predictor policy is fail.")
    medians <- vapply(x, stats::median, numeric(1L))
  }
  rrisk2_assert(identical(names(x), names(medians)), "Predictor order differs from preprocessing contract.")
  rrisk2_assert(!anyNA(x) && all(vapply(x, function(z) all(is.finite(z)), logical(1L))), "Predictors contain missing or non-finite values.")
  list(x = data.matrix(x), medians = medians)
}

rrisk2_add_fit_weights <- function(dat) {
  sizes <- table(dat$.regional_branch_id)
  raw <- 1 / sqrt(as.numeric(sizes[dat$.regional_branch_id]))
  dat$.fit_weight <- raw / mean(raw)
  rrisk2_assert(abs(mean(dat$.fit_weight) - 1) < 1e-12, "Fit weights are not normalized within analysis data.")
  dat
}

rrisk2_seed <- function(context, task_id, fit_index) as.integer(context$config$randomness$base_seed) + as.integer(task_id) * 1000L + as.integer(fit_index)
