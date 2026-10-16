risk_base_paths <- function(context) {
  stats::setNames(vapply(c(
    "base_manifest" = context$config$input$base_v1_fold_manifest,
    "outer" = context$config$input$base_v1_outer_assignments,
    "groups" = context$config$input$base_v1_hydrological_groups
  ), function(path) risk_path(context, path), character(1L)), c("base_manifest", "outer", "groups"))
}

risk_fold_paths <- function(context) {
  root <- risk_output_path(context, "folds_dir")
  stats::setNames(file.path(root, c(
    "fold_manifest.json", "inner_assignments.csv", "fold_diagnostics.csv", "task_manifest.csv"
  )), c("manifest", "inner", "diagnostics", "tasks"))
}

risk_validate_input <- function(context) {
  dat <- risk_read_training_data(context)
  predictors <- risk_read_predictors(context)
  full50 <- risk_read_lines(risk_path(context, context$config$input$full50_predictors))
  excluded <- c("p0__sp_x", "p0__sp_y", "p0__sp_z")
  risk_assert(length(full50) == 50L && !anyDuplicated(full50), "The authoritative Full50 manifest is not a unique 50-variable list.")
  risk_assert(identical(predictors, full50[!full50 %in% excluded]), "NonSpatial47 must be the ordered Full50 manifest with only p0__sp_x/y/z removed.")
  risk_assert(length(intersect(predictors, excluded)) == 0L, "Absolute spatial coordinates entered the Risk V1 predictor set.")

  columns <- unlist(context$config$columns, use.names = TRUE)
  required <- unique(c(columns, predictors))
  missing <- setdiff(required, names(dat))
  risk_assert(length(missing) == 0L, paste("Training table lacks required columns:", paste(missing, collapse = ", ")))
  risk_assert(nrow(dat) == as.integer(context$config$validation$expected_rows), "Risk V1 must use the frozen 4,485-row Base V1 table.")

  row_id <- trimws(as.character(dat[[columns[["row_id"]]]]))
  site_id <- trimws(as.character(dat[[columns[["site_id"]]]]))
  observed <- as.numeric(dat[[columns[["response"]]]])
  risk_assert(!anyNA(row_id) && all(nzchar(row_id)) && !anyDuplicated(row_id), "row_id must be complete and unique.")
  risk_assert(!anyNA(site_id) && all(nzchar(site_id)) && !anyDuplicated(site_id), "site_id must be complete and unique.")
  risk_assert(!anyNA(observed) && all(is.finite(observed)), "Response contains missing or non-finite values.")
  for (name in c("longitude", "latitude")) {
    values <- dat[[columns[[name]]]]
    risk_assert(is.numeric(values) && !anyNA(values) && all(is.finite(values)), paste(name, "must be complete and numeric."))
  }
  non_numeric <- predictors[!vapply(dat[predictors], is.numeric, logical(1L))]
  risk_assert(length(non_numeric) == 0L, paste("NonSpatial47 predictors must be numeric:", paste(non_numeric, collapse = ", ")))
  nonfinite <- predictors[vapply(dat[predictors], function(x) any(!is.na(x) & !is.finite(x)), logical(1L))]
  risk_assert(length(nonfinite) == 0L, paste("Predictors contain non-finite values:", paste(nonfinite, collapse = ", ")))
  all_missing <- predictors[vapply(dat[predictors], function(x) all(is.na(x)), logical(1L))]
  risk_assert(length(all_missing) == 0L, paste("Predictors are entirely missing:", paste(all_missing, collapse = ", ")))

  base_paths <- risk_base_paths(context)
  risk_assert(all(file.exists(base_paths)), "One or more authoritative Base V1 fold files are missing.")
  base_manifest <- jsonlite::read_json(base_paths[["base_manifest"]], simplifyVector = TRUE)
  data_signature <- risk_data_signature(context)
  risk_assert(identical(as.character(base_manifest$input$md5), as.character(data_signature$md5)), "Training data differs from the Base V1 frozen fold manifest.")
  risk_assert(identical(as.character(base_manifest$predictors), full50), "Full50 differs from the Base V1 frozen fold manifest.")

  groups <- data.table::fread(base_paths[["groups"]], integer64 = "character", data.table = FALSE)
  outer <- data.table::fread(base_paths[["outer"]], integer64 = "character", data.table = FALSE)
  groups$row_id <- as.character(groups$row_id)
  groups$hydrological_group <- as.character(groups$hydrological_group)
  outer$row_id <- as.character(outer$row_id)
  outer$validation_unit <- as.character(outer$validation_unit)
  risk_assert(setequal(groups$row_id, row_id) && !anyDuplicated(groups$row_id), "Base V1 hydrological map does not match the training rows.")
  risk_assert(length(unique(groups$hydrological_group)) == as.integer(context$config$validation$expected_hydrological_groups), "Base V1 hydrological group count is not 355.")
  repeats <- as.integer(context$config$validation$repeats)
  outer_k <- as.integer(context$config$validation$outer_folds)
  risk_assert(nrow(outer) == length(row_id) * repeats, "Base V1 Outer assignment row count is invalid.")
  for (repeat_id in seq_len(repeats)) {
    current <- outer[outer$repeat_id == repeat_id, , drop = FALSE]
    risk_assert(setequal(current$row_id, row_id) && !anyDuplicated(current$row_id), paste("Base V1 Outer repeat", repeat_id, "does not cover rows exactly once."))
    risk_assert(setequal(unique(current$outer_fold), seq_len(outer_k)), paste("Base V1 Outer repeat", repeat_id, "does not contain five folds."))
  }
  split_check <- stats::aggregate(outer_fold ~ repeat_id + validation_unit, outer, function(x) length(unique(x)))
  risk_assert(all(split_check$outer_fold == 1L), "A hydrological system crosses a Base V1 Outer fold.")

  dat[[columns[["row_id"]]]] <- row_id
  dat[[columns[["site_id"]]]] <- site_id
  dat$.observed <- observed
  dat$.positive <- observed >= as.numeric(context$config$target$positive_lower)
  dat$.background <- observed < as.numeric(context$config$target$background_upper)
  dat$.gray_zone <- observed >= as.numeric(context$config$target$background_upper) & observed < as.numeric(context$config$target$positive_lower)
  dat$.extreme <- observed >= as.numeric(context$config$target$extreme_lower)
  group_match <- groups[match(row_id, groups$row_id), , drop = FALSE]
  risk_assert(identical(group_match$row_id, row_id), "Hydrological group join changed row identity.")
  dat$.hydrological_group <- group_match$hydrological_group

  expected <- context$config$validation
  checks <- c(
    positive_rows = sum(dat$.positive) == as.integer(expected$expected_positive_rows),
    positive_groups = length(unique(dat$.hydrological_group[dat$.positive])) == as.integer(expected$expected_positive_groups),
    extreme_rows = sum(dat$.extreme) == as.integer(expected$expected_extreme_rows),
    extreme_groups = length(unique(dat$.hydrological_group[dat$.extreme])) == as.integer(expected$expected_extreme_groups)
  )
  risk_assert(all(checks), paste("Frozen high-Sr target counts changed:", paste(names(checks)[!checks], collapse = ", ")))

  list(
    data = dat, predictors = predictors, full50 = full50, groups = groups, outer = outer,
    data_signature = data_signature, config_signature = risk_config_signature(context),
    base_manifest_signature = risk_text_signature(base_paths[["base_manifest"]]),
    outer_signature = risk_text_signature(base_paths[["outer"]]),
    groups_signature = risk_text_signature(base_paths[["groups"]])
  )
}

risk_assert_folds_current <- function(context) {
  paths <- risk_fold_paths(context)
  risk_assert(all(file.exists(paths)), "Risk V1 folds are not prepared. Run --stage prepare locally before cluster training.")
  validated <- risk_validate_input(context)
  manifest <- jsonlite::read_json(paths[["manifest"]], simplifyVector = TRUE)
  risk_assert(identical(as.character(manifest$input$md5), as.character(validated$data_signature$md5)), "Training data changed after Risk V1 folds were frozen.")
  risk_assert(identical(as.character(manifest$config$md5), as.character(validated$config_signature$md5)), "Risk V1 config changed after folds were frozen.")
  risk_assert(identical(as.character(manifest$base_outer_assignments$md5), as.character(validated$outer_signature$md5)), "Base V1 Outer assignments changed after Risk V1 folds were frozen.")
  risk_assert(identical(as.character(manifest$hydrological_groups$md5), as.character(validated$groups_signature$md5)), "Base V1 hydrological groups changed after Risk V1 folds were frozen.")
  risk_assert(identical(as.character(manifest$predictors), validated$predictors), "NonSpatial47 changed after folds were frozen.")
  invisible(list(manifest = manifest, validated = validated))
}
