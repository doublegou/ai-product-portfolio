regional_v2_validate_output <- function(dat, validated, context) {
  cfg <- context$config
  regional_v2_assert(nrow(dat) == as.integer(cfg$domain$expected_rows), "V2 regional output row count changed.")
  regional_v2_assert(ncol(dat) == as.integer(cfg$domain$expected_output_columns), "V2 regional output column count changed.")
  regional_v2_assert(
    identical(names(dat), c(names(validated$v1), validated$process14)),
    "V2 output does not preserve V1 columns followed by frozen Process14 order."
  )
  for (column in names(validated$v1)) {
    regional_v2_assert(identical(dat[[column]], validated$v1[[column]]), paste("V1 column changed while building V2:", column))
  }
  regional_v2_assert(
    all(vapply(dat[, validated$process14, drop = FALSE], function(x) all(is.finite(as.numeric(x))), logical(1L))),
    "A Process14 output contains missing or non-finite values."
  )
  regional_v2_assert(all(dat$relative_downstream_position >= 0 & dat$relative_downstream_position <= 1), "Relative downstream position is outside [0,1].")
  regional_v2_assert(all(dat$upstream_radiogenic_lithology_frac >= 0 & dat$upstream_radiogenic_lithology_frac <= 1), "Upstream radiogenic fraction is outside [0,1].")
  regional_v2_assert(all(dat$old_crust_tail_proxy >= 0 & dat$old_crust_tail_proxy <= 1), "Old-crust tail proxy is outside [0,1].")
  regional_v2_assert(all(dat$old_crust_source_proxy >= 0), "Old-crust source proxy is negative.")

  response <- as.numeric(dat[[cfg$columns$response]])
  background <- response < as.numeric(cfg$domain$background_upper)
  gray <- response >= as.numeric(cfg$domain$background_upper) & response < as.numeric(cfg$domain$positive_lower)
  positive <- response >= as.numeric(cfg$domain$positive_lower)
  extreme <- response >= as.numeric(cfg$domain$extreme_lower)
  regional_v2_assert(sum(background) == as.integer(cfg$domain$expected_background_rows), "Background count changed.")
  regional_v2_assert(sum(gray) == as.integer(cfg$domain$expected_gray_rows), "Gray-zone count changed.")
  regional_v2_assert(sum(positive) == as.integer(cfg$domain$expected_positive_rows), "Positive count changed.")
  regional_v2_assert(sum(extreme) == as.integer(cfg$domain$expected_extreme_rows), "Extreme count changed.")

  branch_id <- cfg$columns$branch_id
  branches <- as.character(validated$branches[[branch_id]])
  regional_v2_assert(length(unique(branches[positive])) == as.integer(cfg$domain$expected_positive_branches), "Positive-branch count changed.")
  regional_v2_assert(length(unique(branches[extreme])) == as.integer(cfg$domain$expected_extreme_branches), "Extreme-system count changed.")
  invisible(dat)
}

regional_v2_validate_published_output <- function(published, validated, context) {
  cfg <- context$config
  regional_v2_assert(
    identical(names(published), c(names(validated$v1), validated$process14)),
    "Published Regional V2 column order changed during CSV roundtrip."
  )
  regional_v2_assert(
    identical(published[, names(validated$v1), drop = FALSE], validated$v1),
    "Published Regional V2 no longer preserves all 133 Regional V1 fields exactly."
  )
  regional_v2_assert(
    all(vapply(published[, validated$process14, drop = FALSE], function(x) all(is.finite(as.numeric(x))), logical(1L))),
    "Published Regional V2 contains a non-finite Process14 value."
  )
  regional_v2_assert(
    nrow(published) == as.integer(cfg$domain$expected_rows) && ncol(published) == as.integer(cfg$domain$expected_output_columns),
    "Published Regional V2 dimensions changed during CSV roundtrip."
  )
  invisible(published)
}

regional_v2_write_manifest <- function(output_path, validated, context) {
  cfg <- context$config
  formula_status <- vapply(validated$dictionary$features, function(x) as.character(x$status), character(1L))
  manifest <- list(
    status = "PROCESS14_FROZEN_BEFORE_MODELING",
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    project = cfg$project,
    inputs = list(
      v1_table = regional_v2_signature(validated$paths$v1_table, context$repo_root),
      v1_branch_map = regional_v2_signature(validated$paths$v1_branch_map, context$repo_root),
      full50_predictors = regional_v2_signature(validated$paths$full50_predictors, context$repo_root),
      process14_predictors = regional_v2_signature(validated$paths$process14_predictors, context$repo_root),
      process14_formula_dictionary = regional_v2_signature(validated$paths$process14_formula_dictionary, context$repo_root)
    ),
    output = regional_v2_signature(output_path, context$repo_root),
    contract = list(
      rows = as.integer(cfg$domain$expected_rows),
      columns = as.integer(cfg$domain$expected_output_columns),
      full50_predictors = validated$full50,
      process14_predictors = validated$process14,
      formula_status = as.list(formula_status),
      formal_model_training_performed = FALSE,
      immutable_after_formal_v2_fit = isTRUE(cfg$formula_contract$immutable_after_formal_v2_fit)
    )
  )
  manifest_path <- regional_v2_path(context, cfg$output$manifest)
  dir.create(dirname(manifest_path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(manifest, manifest_path, pretty = TRUE, auto_unbox = TRUE, digits = 16)
  invisible(manifest_path)
}
