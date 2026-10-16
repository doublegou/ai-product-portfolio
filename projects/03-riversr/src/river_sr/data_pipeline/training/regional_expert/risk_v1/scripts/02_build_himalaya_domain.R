regional_data_build_domain <- function(validated, context) {
  cfg <- context$config
  topology <- validated$topology
  keep <- as.character(topology$terminal_component_id) == as.character(cfg$domain$terminal_component_id)
  regional_data_assert(sum(keep) == as.integer(cfg$domain$expected_rows), "Himalaya terminal component no longer contains 372 stations.")
  dat <- validated$full50[keep, , drop = FALSE]
  topo <- topology[keep, , drop = FALSE]
  regional_data_assert(identical(as.character(dat[[cfg$columns$row_id]]), as.character(topo$row_id)), "Regional topology join changed row order.")

  additions <- data.frame(
    reach_id = as.character(topo$reach_id),
    connected_basin_id = as.character(topo$connected_basin_id),
    l12_id = as.character(topo$l12_id),
    l12_pfaf_id = as.character(topo$l12_pfaf_id),
    l6_id = as.character(topo$l6_id),
    terminal_component_id = as.character(topo$terminal_component_id),
    distance_downstream_km = as.numeric(topo$distance_downstream_km),
    regional_strahler_order = as.integer(topo$strahler_order),
    regional_classical_order = as.integer(topo$classical_order),
    stringsAsFactors = FALSE
  )
  overlap <- intersect(names(additions), names(dat))
  regional_data_assert(length(overlap) == 0L, paste("Regional topology columns already exist in Full50:", paste(overlap, collapse = ", ")))
  cbind(dat, additions)
}
