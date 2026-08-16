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
