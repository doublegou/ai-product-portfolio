v2_validate_input <- function(context) {
  dat <- v2_read_training_data(context)
  predictors <- v2_read_predictors(context)
  columns <- unlist(context$config$columns, use.names = TRUE)
  required <- unique(c(columns, predictors))
  missing <- setdiff(required, names(dat))
  v2_assert(length(missing) == 0L, paste("Training table lacks required columns:", paste(missing, collapse = ", ")))
  expected_rows <- as.integer(context$config$validation$expected_rows)
  v2_assert(nrow(dat) == expected_rows, paste("Expected", expected_rows, "training rows; found", nrow(dat)))
  row_id <- trimws(as.character(dat[[columns[["row_id"]]]]))
  site_id <- trimws(as.character(dat[[columns[["site_id"]]]]))
  v2_assert(!anyNA(row_id) && all(nzchar(row_id)) && !anyDuplicated(row_id), "row_id must be complete and unique.")
  v2_assert(!anyNA(site_id) && all(nzchar(site_id)) && !anyDuplicated(site_id), "site_id must be complete and unique.")
  for (name in c("longitude", "latitude", "response")) {
    values <- dat[[columns[[name]]]]
    v2_assert(is.numeric(values), paste(name, "must be numeric."))
    v2_assert(!anyNA(values) && all(is.finite(values)), paste(name, "contains missing or non-finite values."))
  }
  v2_assert(all(dat[[columns[["longitude"]]]] >= -180 & dat[[columns[["longitude"]]]] <= 180), "Longitude is outside [-180, 180].")
  v2_assert(all(dat[[columns[["latitude"]]]] >= -90 & dat[[columns[["latitude"]]]] <= 90), "Latitude is outside [-90, 90].")
  reference <- trimws(as.character(dat[[columns[["reference"]]]]))
  hybas <- trimws(as.character(dat[[columns[["current_hybas_id"]]]]))
  v2_assert(!anyNA(reference) && all(nzchar(reference)), "reference_id contains missing or blank values.")
  v2_assert(!anyNA(hybas) && all(nzchar(hybas)), "current HydroBASINS L6 ID contains missing or blank values.")
  v2_assert(length(unique(reference)) >= 5L, "Fewer than five reference groups are available.")
  non_numeric <- predictors[!vapply(dat[predictors], is.numeric, logical(1L))]
  v2_assert(length(non_numeric) == 0L, paste("Full50 predictors must be numeric:", paste(non_numeric, collapse = ", ")))
  nonfinite <- predictors[vapply(dat[predictors], function(x) any(!is.na(x) & !is.finite(x)), logical(1L))]
  v2_assert(length(nonfinite) == 0L, paste("Predictors contain non-finite values:", paste(nonfinite, collapse = ", ")))
  all_missing <- predictors[vapply(dat[predictors], function(x) all(is.na(x)), logical(1L))]
  v2_assert(length(all_missing) == 0L, paste("Predictors are entirely missing:", paste(all_missing, collapse = ", ")))
  dat[[columns[["row_id"]]]] <- row_id
  dat[[columns[["site_id"]]]] <- site_id
  dat[[columns[["current_hybas_id"]]]] <- hybas
  list(
    data = dat,
    predictors = predictors,
    signature = v2_data_signature(context),
    config_signature = v2_config_signature(context),
    n_rows = nrow(dat),
    n_predictors = length(predictors),
    n_reference_groups = length(unique(reference)),
    n_l6_basins = length(unique(hybas))
  )
}

v2_fold_paths <- function(context) {
  root <- v2_output_path(context, "folds_dir")
  files <- c(
    manifest = "fold_manifest.json",
    branch_catalog = "branch_scale_membership.csv",
    branch_relations = "branch_relations.csv",
    primary_outer = "primary_outer_assignments.csv",
    primary_inner = "primary_inner_assignments.csv",
    deployment = "deployment_assignments.csv",
    stress = "stress_assignments.csv",
    diagnostics = "fold_diagnostics.csv"
  )
  stats::setNames(file.path(root, unname(files)), names(files))
}

v2_assert_folds_current <- function(context) {
  paths <- v2_fold_paths(context)
  v2_assert(all(file.exists(paths)), "V2 folds are not prepared. Run: Rscript training/base/v2/scripts/run.R --stage prepare")
  manifest <- jsonlite::read_json(paths[["manifest"]], simplifyVector = TRUE)
  current_data <- v2_data_signature(context)
  current_config <- v2_config_signature(context)
  current_implementation <- v2_implementation_signature(context)
  v2_assert(identical(as.character(manifest$input$md5), as.character(current_data$md5)), "Training data changed after V2 folds were frozen.")
  v2_assert(identical(as.character(manifest$config$md5), as.character(current_config$md5)), "V2 config changed after folds were frozen. Rebuild folds explicitly before training.")
  v2_assert(identical(as.character(manifest$implementation$sha256), as.character(current_implementation$sha256)), "Base V2 implementation changed after folds were frozen. Rebuild and recheck folds before training.")
  v2_assert(identical(as.character(manifest$predictors), v2_read_predictors(context)), "Full50 predictor definition changed after V2 folds were frozen.")
  for (name in setdiff(names(paths), "manifest")) {
    expected_hash <- as.character(manifest$fold_files[[name]]$sha256)
    current_hash <- v2_file_signature(paths[[name]], context$repo_root)$sha256
    v2_assert(
      identical(expected_hash, current_hash),
      paste("Frozen V2 fold artifact changed:", basename(paths[[name]]))
    )
  }
  catalog <- data.table::fread(paths[["branch_catalog"]], integer64 = "character", data.table = FALSE)
  expected <- as.integer(context$config$validation$expected_rows) * length(context$config$topology$scales)
  v2_assert(nrow(catalog) == expected, "Frozen branch-scale membership has the wrong row count.")
  primary <- catalog[catalog$scale == manifest$topology$selected_scale, , drop = FALSE]
  v2_assert(sum(primary$assessment_eligible) == as.integer(manifest$topology$n_primary_eligible_rows), "Frozen Primary eligible-row count changed.")
  outer <- data.table::fread(paths[["primary_outer"]], integer64 = "character", data.table = FALSE)
  repeats <- as.integer(context$config$validation$repeats)
  outer_k <- as.integer(context$config$validation$outer_folds)
  v2_assert(nrow(outer) == as.integer(context$config$validation$expected_rows) * repeats * outer_k, "Primary Outer role table has the wrong row count.")
  v2_assert(all(outer$role %in% c("analysis", "assessment", "purged_downstream", "support_excluded")), "Primary Outer role table contains an invalid role.")
  invisible(manifest)
}
