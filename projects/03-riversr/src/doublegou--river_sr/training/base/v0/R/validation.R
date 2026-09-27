v0_validate_input <- function(context) {
  dat <- v0_read_training_data(context)
  predictors <- v0_read_predictors(context)
  columns <- unlist(context$config$columns, use.names = TRUE)
  required <- unique(c(columns, predictors))
  missing <- setdiff(required, names(dat))
  v0_assert(length(missing) == 0L, paste("Training table lacks required columns:", paste(missing, collapse = ", ")))

  row_id <- as.character(dat[[columns[["row_id"]]]])
  v0_assert(nrow(dat) > 0L, "Training table contains no rows.")
  v0_assert(!anyNA(row_id) && all(nzchar(trimws(row_id))), "row_id contains missing or blank values.")
  v0_assert(!anyDuplicated(row_id), "row_id must be unique.")

  for (name in c("longitude", "latitude", "response")) {
    values <- dat[[columns[[name]]]]
    v0_assert(is.numeric(values), paste(name, "must be numeric."))
    v0_assert(!anyNA(values) && all(is.finite(values)), paste(name, "contains missing or non-finite values."))
  }
  v0_assert(all(dat[[columns[["longitude"]]]] >= -180 & dat[[columns[["longitude"]]]] <= 180), "Longitude is outside [-180, 180].")
  v0_assert(all(dat[[columns[["latitude"]]]] >= -90 & dat[[columns[["latitude"]]]] <= 90), "Latitude is outside [-90, 90].")

  reference <- trimws(as.character(dat[[columns[["reference"]]]]))
  v0_assert(!anyNA(reference) && all(nzchar(reference)), "reference_id contains missing or blank values.")
  v0_assert(length(unique(reference)) >= context$config$validation$outer_folds, "Fewer than five reference groups are available.")
  largest_reference <- max(tabulate(match(reference, unique(reference))))
  v0_assert(largest_reference <= nrow(dat) / 2, "One reference group contains more than half of all rows.")

  non_numeric <- predictors[!vapply(dat[predictors], is.numeric, logical(1L))]
  v0_assert(length(non_numeric) == 0L, paste("Full50 predictors must be numeric:", paste(non_numeric, collapse = ", ")))
  nonfinite <- predictors[vapply(dat[predictors], function(x) any(!is.na(x) & !is.finite(x)), logical(1L))]
  v0_assert(length(nonfinite) == 0L, paste("Predictors contain non-finite values:", paste(nonfinite, collapse = ", ")))
  all_missing <- predictors[vapply(dat[predictors], function(x) all(is.na(x)), logical(1L))]
  v0_assert(length(all_missing) == 0L, paste("Predictors are entirely missing:", paste(all_missing, collapse = ", ")))

  dat[[columns[["row_id"]]]] <- row_id
  list(
    data = dat,
    predictors = predictors,
    signature = v0_data_signature(context),
    n_rows = nrow(dat),
    n_predictors = length(predictors),
    n_reference_groups = length(unique(reference))
  )
}

v0_assert_folds_current <- function(context) {
  folds_dir <- v0_output_path(context, "folds_dir")
  required <- file.path(folds_dir, c(
    "fold_manifest.json", "outer_assignments.csv", "inner_assignments.csv", "fold_diagnostics.csv"
  ))
  v0_assert(all(file.exists(required)), "V0 folds are not prepared. Run: Rscript training/base/v0/scripts/run.R --stage prepare")
  manifest <- jsonlite::read_json(file.path(folds_dir, "fold_manifest.json"), simplifyVector = TRUE)
  current <- v0_data_signature(context)
  v0_assert(identical(as.character(manifest$input$md5), as.character(current$md5)), "Training data changed after folds were frozen. Rebuild folds explicitly.")
  predictors <- v0_read_predictors(context)
  v0_assert(identical(as.character(manifest$predictors), predictors), "Full50 predictor definition changed after folds were frozen.")
  invisible(manifest)
}
