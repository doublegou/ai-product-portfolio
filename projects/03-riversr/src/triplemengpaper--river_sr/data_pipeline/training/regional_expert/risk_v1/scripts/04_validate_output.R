regional_data_validate_output <- function(dat, context) {
  cfg <- context$config
  regional_data_assert(nrow(dat) == as.integer(cfg$domain$expected_rows), "Regional output row count changed.")
  regional_data_assert(!anyDuplicated(dat[[cfg$columns$row_id]]), "Regional output row_id is duplicated.")
  regional_data_assert(!anyDuplicated(dat[[cfg$columns$site_id]]), "Regional output site_id is duplicated.")
  regional_data_assert(all(as.character(dat$terminal_component_id) == as.character(cfg$domain$terminal_component_id)), "Regional output crosses terminal components.")
  regional_data_assert(sum(dat$high_sr_label == 1L) == as.integer(cfg$domain$expected_positive_rows), "Regional positive count changed.")
  regional_data_assert(sum(dat$high_sr_label == 0L) == as.integer(cfg$domain$expected_negative_rows), "Regional negative count changed.")
  regional_data_assert(all(is.finite(dat[[cfg$projection$x_column]])) && all(is.finite(dat[[cfg$projection$y_column]])), "Projected coordinates are non-finite.")
  regional_data_assert(length(unique(dat$l12_id)) == 240L, "Regional station L12 coverage changed.")
  invisible(dat)
}

regional_data_validate_published_output <- function(published, expected, context) {
  regional_data_assert(identical(names(published), names(expected)), "Published Regional V1 column order changed during CSV roundtrip.")
  regional_data_assert(identical(dim(published), dim(expected)), "Published Regional V1 dimensions changed during CSV roundtrip.")
  equal_column <- function(name) {
    observed <- published[[name]]
    target <- expected[[name]]
    if (is.numeric(observed) && is.numeric(target)) {
      return(isTRUE(all.equal(as.numeric(observed), as.numeric(target), tolerance = 1e-11, check.attributes = FALSE)))
    }
    identical(as.character(observed), as.character(target))
  }
  changed <- names(expected)[!vapply(names(expected), equal_column, logical(1L))]
  regional_data_assert(
    length(changed) == 0L,
    paste("Published Regional V1 values changed during CSV roundtrip:", paste(changed, collapse = ", "))
  )
  regional_data_validate_output(published, context)
  invisible(published)
}

regional_data_write_manifest <- function(output_path, dat, validated, context) {
  cfg <- context$config
  manifest <- list(
    project = cfg$project$id,
    status = "validated",
    inputs = list(
      full50_table = regional_data_signature(validated$paths$full50_table, context$repo_root),
      base_v2_site_topology = regional_data_signature(validated$paths$base_v2_site_topology, context$repo_root),
      base_v2_prepare_manifest = regional_data_signature(validated$paths$base_v2_prepare_manifest, context$repo_root)
    ),
    output = regional_data_signature(output_path, context$repo_root),
    counts = list(
      rows = nrow(dat),
      columns = ncol(dat),
      positive_rows = sum(dat$high_sr_label == 1L),
      negative_rows = sum(dat$high_sr_label == 0L),
      l12_units = length(unique(dat$l12_id)),
      terminal_components = length(unique(dat$terminal_component_id))
    ),
    contract = list(
      terminal_component_id = as.character(cfg$domain$terminal_component_id),
      positive_lower = as.numeric(cfg$domain$positive_lower),
      topology_response_used = FALSE,
      model_training_performed = FALSE,
      numeric_roundtrip_tolerance = 1e-11
    ),
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
  manifest_path <- regional_data_path(context, cfg$output$manifest)
  dir.create(dirname(manifest_path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(manifest, manifest_path, pretty = TRUE, auto_unbox = TRUE, digits = 16)
  invisible(manifest_path)
}
