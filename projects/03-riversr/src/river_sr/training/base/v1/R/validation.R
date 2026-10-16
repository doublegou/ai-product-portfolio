v1_validate_input <- function(context) {
  dat <- v1_read_training_data(context)
  predictors <- v1_read_predictors(context)
  columns <- unlist(context$config$columns, use.names = TRUE)
  required <- unique(c(columns, predictors))
  missing <- setdiff(required, names(dat))
  v1_assert(length(missing) == 0L, paste("Training table lacks required columns:", paste(missing, collapse = ", ")))

  expected_rows <- as.integer(context$config$validation$expected_rows)
  v1_assert(nrow(dat) == expected_rows, paste("Expected", expected_rows, "training rows; found", nrow(dat)))
  row_id <- trimws(as.character(dat[[columns[["row_id"]]]]))
  site_id <- trimws(as.character(dat[[columns[["site_id"]]]]))
  v1_assert(!anyNA(row_id) && all(nzchar(row_id)) && !anyDuplicated(row_id), "row_id must be complete and unique.")
  v1_assert(!anyNA(site_id) && all(nzchar(site_id)) && !anyDuplicated(site_id), "site_id must be complete and unique.")

  for (name in c("longitude", "latitude", "response")) {
    values <- dat[[columns[[name]]]]
    v1_assert(is.numeric(values), paste(name, "must be numeric."))
    v1_assert(!anyNA(values) && all(is.finite(values)), paste(name, "contains missing or non-finite values."))
  }
  v1_assert(all(dat[[columns[["longitude"]]]] >= -180 & dat[[columns[["longitude"]]]] <= 180), "Longitude is outside [-180, 180].")
  v1_assert(all(dat[[columns[["latitude"]]]] >= -90 & dat[[columns[["latitude"]]]] <= 90), "Latitude is outside [-90, 90].")

  reference <- trimws(as.character(dat[[columns[["reference"]]]]))
  hybas <- trimws(as.character(dat[[columns[["current_hybas_id"]]]]))
  v1_assert(!anyNA(reference) && all(nzchar(reference)), "reference_id contains missing or blank values.")
  v1_assert(!anyNA(hybas) && all(nzchar(hybas)), "current HydroBASINS L6 ID contains missing or blank values.")
  v1_assert(length(unique(reference)) >= 5L, "Fewer than five reference groups are available.")

  non_numeric <- predictors[!vapply(dat[predictors], is.numeric, logical(1L))]
  v1_assert(length(non_numeric) == 0L, paste("Full50 predictors must be numeric:", paste(non_numeric, collapse = ", ")))
  nonfinite <- predictors[vapply(dat[predictors], function(x) any(!is.na(x) & !is.finite(x)), logical(1L))]
  v1_assert(length(nonfinite) == 0L, paste("Predictors contain non-finite values:", paste(nonfinite, collapse = ", ")))
  all_missing <- predictors[vapply(dat[predictors], function(x) all(is.na(x)), logical(1L))]
  v1_assert(length(all_missing) == 0L, paste("Predictors are entirely missing:", paste(all_missing, collapse = ", ")))

  dat[[columns[["row_id"]]]] <- row_id
  dat[[columns[["site_id"]]]] <- site_id
  dat[[columns[["current_hybas_id"]]]] <- hybas
  list(
    data = dat,
    predictors = predictors,
    signature = v1_data_signature(context),
    config_signature = v1_config_signature(context),
    n_rows = nrow(dat),
    n_predictors = length(predictors),
    n_reference_groups = length(unique(reference)),
    n_l6_basins = length(unique(hybas))
  )
}

v1_fold_paths <- function(context) {
  root <- v1_output_path(context, "folds_dir")
  stats::setNames(file.path(root, c(
    "fold_manifest.json",
    "hydrological_groups.csv",
    "primary_outer_assignments.csv",
    "primary_inner_assignments.csv",
    "deployment_assignments.csv",
    "stress_assignments.csv",
    "fold_diagnostics.csv"
  )), c("manifest", "groups", "primary_outer", "primary_inner", "deployment", "stress", "diagnostics"))
}

v1_assert_folds_current <- function(context) {
  paths <- v1_fold_paths(context)
  v1_assert(all(file.exists(paths)), "V1 folds are not prepared. Run: Rscript training/base/v1/scripts/run.R --stage prepare")
  manifest <- jsonlite::read_json(paths[["manifest"]], simplifyVector = TRUE)
  current_data <- v1_data_signature(context)
  current_config <- v1_config_signature(context)
  v1_assert(identical(as.character(manifest$input$md5), as.character(current_data$md5)), "Training data changed after V1 folds were frozen.")
  v1_assert(identical(as.character(manifest$config$md5), as.character(current_config$md5)), "V1 config changed after folds were frozen. Rebuild folds explicitly.")
  v1_assert(identical(as.character(manifest$predictors), v1_read_predictors(context)), "Full50 predictor definition changed after folds were frozen.")
  groups <- data.table::fread(paths[["groups"]], integer64 = "character", data.table = FALSE)
  v1_assert(nrow(groups) == as.integer(context$config$validation$expected_rows), "Frozen hydrological group map has the wrong number of rows.")
  v1_assert(length(unique(groups$hydrological_group)) == as.integer(context$config$validation$expected_hydrological_groups), "Frozen hydrological group count changed.")
  invisible(manifest)
}
