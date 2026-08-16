regional_data_validate_inputs <- function(context) {
  cfg <- context$config
  paths <- lapply(cfg$input, regional_data_path, context = context)
  regional_data_assert(all(vapply(paths, file.exists, logical(1L))), "A frozen Regional Risk V1 input is missing.")

  full50 <- regional_data_read_csv(paths$full50_table)
  topology <- as.data.frame(readRDS(paths$base_v2_site_topology), stringsAsFactors = FALSE)
  prepare_manifest <- jsonlite::read_json(paths$base_v2_prepare_manifest, simplifyVector = TRUE)
  required_data <- unlist(cfg$columns, use.names = FALSE)
  required_topology <- c(
    "row_id", "site_id", "reach_id", "connected_basin_id", "l12_id", "l12_pfaf_id",
    "l6_id", "terminal_component_id", "distance_downstream_km", "strahler_order", "classical_order"
  )
  regional_data_assert(length(setdiff(required_data, names(full50))) == 0L, "Full50 lacks a required Regional Risk V1 column.")
  regional_data_assert(length(setdiff(required_topology, names(topology))) == 0L, "Base V2 topology lacks a required Regional Risk V1 column.")
  regional_data_assert(nrow(full50) == 4485L && nrow(topology) == 4485L, "Regional Risk V1 inputs must both contain 4,485 rows.")
  regional_data_assert(!anyDuplicated(full50[[cfg$columns$row_id]]), "Full50 row_id is duplicated.")
  regional_data_assert(!anyDuplicated(topology$row_id), "Base V2 topology row_id is duplicated.")
  topology <- topology[match(as.character(full50[[cfg$columns$row_id]]), as.character(topology$row_id)), , drop = FALSE]
  regional_data_assert(!anyNA(topology$row_id), "Base V2 topology does not cover every Full50 row.")
  regional_data_assert(
    identical(as.character(full50[[cfg$columns$site_id]]), as.character(topology$site_id)),
    "Full50 and Base V2 topology site identities differ."
  )
  regional_data_assert(
    identical(as.character(prepare_manifest$status), "TOPOLOGY_PREPARED_RESPONSE_BLIND"),
    "Base V2 topology manifest is not response-blind."
  )
  regional_data_assert(
    identical(as.character(prepare_manifest$inputs$training_table$md5), regional_data_signature(paths$full50_table)$md5),
    "Full50 differs from the table used to prepare Base V2 topology."
  )
  list(full50 = full50, topology = topology, paths = paths, prepare_manifest = prepare_manifest)
}
