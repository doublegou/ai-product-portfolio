v2_id_string <- function(x) {
  result <- rep(NA_character_, length(x))
  valid <- !is.na(x) & is.finite(as.numeric(x))
  result[valid] <- sprintf("%.0f", as.numeric(x[valid]))
  result
}

v2_read_dbf_columns <- function(path, columns) {
  v2_assert(file.exists(path), paste("Missing DBF:", path))
  raw <- foreign::read.dbf(path, as.is = TRUE)
  missing <- setdiff(columns, names(raw))
  v2_assert(length(missing) == 0L, paste("DBF lacks required columns:", paste(missing, collapse = ", "), path))
  as.data.frame(raw[columns], stringsAsFactors = FALSE)
}

v2_load_hydrobasins_attributes <- function(root, level) {
  pattern <- sprintf("hybas_*_lev%02d_v1c.dbf", as.integer(level))
  paths <- Sys.glob(file.path(root, "*", pattern))
  v2_assert(length(paths) == 9L, paste("Expected 9 regional HydroBASINS L", level, " DBFs; found ", length(paths), ".", sep = ""))
  required <- c("HYBAS_ID", "NEXT_DOWN", "MAIN_BAS", "PFAF_ID", "SUB_AREA", "UP_AREA", "ORDER")
  parts <- lapply(paths, function(path) {
    x <- v2_read_dbf_columns(path, required)
    data.frame(
      hybas_id = v2_id_string(x$HYBAS_ID),
      next_down = v2_id_string(x$NEXT_DOWN),
      main_bas = v2_id_string(x$MAIN_BAS),
      pfaf_id = sprintf("%012.0f", as.numeric(x$PFAF_ID)),
      sub_area_km2 = as.numeric(x$SUB_AREA),
      upstream_area_km2 = as.numeric(x$UP_AREA),
      basin_order = as.integer(x$ORDER),
      stringsAsFactors = FALSE
    )
  })
  result <- do.call(rbind, parts)
  v2_assert(!anyNA(result$hybas_id) && !anyDuplicated(result$hybas_id), paste("HydroBASINS L", level, " IDs are incomplete or duplicated.", sep = ""))
  result
}

v2_load_frozen_hydrology <- function(context, dat) {
  path <- v2_path(context, context$config$input$hydrology_interim)
  v2_assert(
    file.exists(path),
    paste("Missing rebuildable Full50 hydrology checkpoint:", path,
          "Run the sr_full50_v1 data pipeline through step 03 before Base V2 prepare.")
  )
  hydrology <- as.data.frame(readRDS(path), stringsAsFactors = FALSE)
  required <- c(
    "site_id", "snap_distance_m", "snapped_longitude", "snapped_latitude",
    "HYRIV_ID", "NEXT_DOWN", "MAIN_RIV", "DIST_DN_KM", "ORD_STRA", "ORD_CLAS"
  )
  missing <- setdiff(required, names(hydrology))
  v2_assert(length(missing) == 0L, paste("Hydrology checkpoint lacks:", paste(missing, collapse = ", ")))
  index <- match(as.character(dat[[context$config$columns$site_id]]), as.character(hydrology$site_id))
  v2_assert(!anyNA(index), "One or more Full50 sites are absent from the hydrology checkpoint.")
  hydrology <- hydrology[index, , drop = FALSE]
  v2_assert(identical(as.character(hydrology$site_id), as.character(dat[[context$config$columns$site_id]])), "Hydrology checkpoint changed Full50 site order.")
  v2_assert(!anyNA(hydrology$HYRIV_ID), "One or more Full50 rows lack a snapped HydroRIVERS reach.")
  hydrology
}

v2_build_reduced_reach_graph <- function(context, station_reach_ids) {
  path <- v2_path(context, context$config$input$hydrorivers_dbf)
  v2_log("Reading HydroRIVERS attributes without global geometry: ", path)
  raw <- v2_read_dbf_columns(path, c(
    "HYRIV_ID", "NEXT_DOWN", "MAIN_RIV", "LENGTH_KM", "DIST_DN_KM",
    "ORD_STRA", "ORD_CLAS", "HYBAS_L12"
  ))
  ids <- as.numeric(raw$HYRIV_ID)
  v2_assert(all(diff(ids) > 0), "HydroRIVERS IDs are not strictly sorted; deterministic closure indexing is unavailable.")
  station_index <- match(as.numeric(station_reach_ids), ids)
  v2_assert(!anyNA(station_index), "A snapped station reach is absent from HydroRIVERS.")
  next_index <- match(as.numeric(raw$NEXT_DOWN), ids)
  keep <- logical(length(ids))
  for (start in unique(station_index)) {
    current <- start
    steps <- 0L
    repeat {
      if (keep[[current]]) break
      keep[[current]] <- TRUE
      downstream <- next_index[[current]]
      if (is.na(downstream)) break
      current <- downstream
      steps <- steps + 1L
      v2_assert(steps <= 100000L, "HydroRIVERS downstream traversal exceeded 100,000 reaches; possible cycle.")
    }
  }
  selected <- which(keep)
  old_to_new <- integer(length(ids))
  old_to_new[selected] <- seq_along(selected)
  graph <- data.frame(
    reach_id = ids[selected],
    next_down = as.numeric(raw$NEXT_DOWN[selected]),
    main_riv = as.numeric(raw$MAIN_RIV[selected]),
    length_km = as.numeric(raw$LENGTH_KM[selected]),
    distance_downstream_km = as.numeric(raw$DIST_DN_KM[selected]),
    strahler_order = as.integer(raw$ORD_STRA[selected]),
    classical_order = as.integer(raw$ORD_CLAS[selected]),
    hybas_l12 = as.numeric(raw$HYBAS_L12[selected]),
    next_index = ifelse(is.na(next_index[selected]), NA_integer_, old_to_new[next_index[selected]]),
    stringsAsFactors = FALSE
  )
  v2_assert(!anyNA(match(as.numeric(station_reach_ids), graph$reach_id)), "Reduced graph dropped a station reach.")
  v2_assert(!anyDuplicated(graph$reach_id), "Reduced graph contains duplicate reach IDs.")
  v2_log("Reduced HydroRIVERS graph: ", nrow(graph), " of ", nrow(raw), " global reaches retained for 4,485 stations.")
  graph
}

v2_trace_backbone_entries <- function(station_graph_index, graph, backbone_max_order) {
  vapply(station_graph_index, function(start) {
    if (graph$classical_order[[start]] <= backbone_max_order) return(NA_integer_)
    current <- start
    steps <- 0L
    repeat {
      downstream <- graph$next_index[[current]]
      if (is.na(downstream)) return(current)
      if (graph$classical_order[[downstream]] <= backbone_max_order) return(downstream)
      current <- downstream
      steps <- steps + 1L
      v2_assert(steps <= 100000L, "Reduced reach graph contains a downstream cycle.")
    }
  }, integer(1L))
}

v2_build_site_topology <- function(context, dat, hydrology, graph, l6, l12) {
  columns <- context$config$columns
  graph_index <- match(as.numeric(hydrology$HYRIV_ID), graph$reach_id)
  v2_assert(!anyNA(graph_index), "Station-to-reduced-graph mapping is incomplete.")
  l12_index <- match(v2_id_string(graph$hybas_l12[graph_index]), l12$hybas_id)
  l6_index <- match(as.character(dat[[columns$current_hybas_id]]), l6$hybas_id)
  v2_assert(!anyNA(l12_index), "One or more station reaches do not map to HydroBASINS L12 attributes.")
  v2_assert(!anyNA(l6_index), "One or more Full50 L6 IDs do not map to HydroBASINS L6 attributes.")
  backbone_max_order <- as.integer(context$config$topology$backbone_max_classical_order)
  entry_index <- v2_trace_backbone_entries(graph_index, graph, backbone_max_order)
  entry_l12_index <- match(v2_id_string(graph$hybas_l12[entry_index]), l12$hybas_id)
  off_backbone <- graph$classical_order[graph_index] > backbone_max_order
  v2_assert(!anyNA(entry_l12_index[off_backbone]), "An off-backbone station lacks entry HydroBASINS L12 context.")
  data.frame(
    row_id = as.character(dat[[columns$row_id]]),
    site_id = as.character(dat[[columns$site_id]]),
    longitude = as.numeric(dat[[columns$longitude]]),
    latitude = as.numeric(dat[[columns$latitude]]),
    snap_distance_m = as.numeric(hydrology$snap_distance_m),
    reach_id = v2_id_string(graph$reach_id[graph_index]),
    next_down_reach_id = v2_id_string(graph$next_down[graph_index]),
    connected_basin_id = v2_id_string(graph$main_riv[graph_index]),
    distance_downstream_km = as.numeric(graph$distance_downstream_km[graph_index]),
    strahler_order = as.integer(graph$strahler_order[graph_index]),
    classical_order = as.integer(graph$classical_order[graph_index]),
    is_backbone = !off_backbone,
    l12_id = l12$hybas_id[l12_index],
    l12_pfaf_id = l12$pfaf_id[l12_index],
    l6_id = l6$hybas_id[l6_index],
    terminal_component_id = l6$main_bas[l6_index],
    entry_context_reach_id = ifelse(off_backbone, v2_id_string(graph$reach_id[entry_index]), NA_character_),
    entry_l12_id = ifelse(off_backbone, l12$hybas_id[entry_l12_index], NA_character_),
    entry_l12_pfaf_id = ifelse(off_backbone, l12$pfaf_id[entry_l12_index], NA_character_),
    stringsAsFactors = FALSE
  )
}

v2_build_downstream_pairs <- function(site_topology, graph) {
  graph_index <- match(as.numeric(site_topology$reach_id), graph$reach_id)
  rows_by_reach <- split(seq_len(nrow(site_topology)), site_topology$reach_id)
  records <- vector("list", nrow(site_topology))
  for (source_row in seq_len(nrow(site_topology))) {
    current <- graph_index[[source_row]]
    downstream_rows <- integer()
    steps <- 0L
    repeat {
      current <- graph$next_index[[current]]
      if (is.na(current)) break
      hit <- rows_by_reach[[v2_id_string(graph$reach_id[[current]])]]
      if (length(hit)) downstream_rows <- c(downstream_rows, hit)
      steps <- steps + 1L
      v2_assert(steps <= 100000L, "Downstream station traversal exceeded 100,000 reaches.")
    }
    downstream_rows <- unique(downstream_rows)
    if (length(downstream_rows)) {
      records[[source_row]] <- data.frame(
        upstream_row_id = site_topology$row_id[[source_row]],
        downstream_row_id = site_topology$row_id[downstream_rows],
        stringsAsFactors = FALSE
      )
    }
  }
  result <- do.call(rbind, records[lengths(records) > 0L])
  if (is.null(result)) result <- data.frame(upstream_row_id = character(), downstream_row_id = character())
  result <- unique(result)
  v2_assert(!any(result$upstream_row_id == result$downstream_row_id), "Downstream relation contains a self-pair.")
  result
}

v2_accumulate_station_support <- function(station_graph_index, graph) {
  support <- integer(nrow(graph))
  for (start in station_graph_index) {
    current <- start
    steps <- 0L
    repeat {
      support[[current]] <- support[[current]] + 1L
      downstream <- graph$next_index[[current]]
      if (is.na(downstream)) break
      current <- downstream
      steps <- steps + 1L
      v2_assert(steps <= 100000L, "Station-support accumulation exceeded 100,000 reaches; possible cycle.")
    }
  }
  support
}

v2_trace_station_frontier_outlets <- function(station_graph_index, graph, station_support, trunk_support) {
  trunk_support <- as.integer(trunk_support)
  v2_assert(trunk_support >= 2L, "station_trunk_support must be at least two.")
  vapply(station_graph_index, function(start) {
    if (station_support[[start]] >= trunk_support) return(NA_integer_)
    current <- start
    steps <- 0L
    repeat {
      downstream <- graph$next_index[[current]]
      if (is.na(downstream) || station_support[[downstream]] >= trunk_support) return(current)
      current <- downstream
      steps <- steps + 1L
      v2_assert(steps <= 100000L, "Station-frontier traversal exceeded 100,000 reaches; possible cycle.")
    }
  }, integer(1L))
}

v2_branch_structure_diagnostics <- function(site_topology, branch_id, eligible) {
  members <- split(which(eligible), branch_id[eligible])
  unique_max <- function(values) {
    if (!length(members)) return(NA_integer_)
    max(vapply(members, function(index) length(unique(values[index])), integer(1L)))
  }
  span <- if (length(members)) vapply(members, function(index) {
    values <- site_topology$distance_downstream_km[index]
    max(values) - min(values)
  }, numeric(1L)) else numeric()
  list(
    branch_reach_max = unique_max(site_topology$reach_id),
    branch_l12_max = unique_max(site_topology$l12_id),
    branch_l6_max = unique_max(site_topology$l6_id),
    branch_station_span_km_p95 = if (length(span)) unname(stats::quantile(span, 0.95)) else NA_real_,
    branch_station_span_km_max = if (length(span)) max(span) else NA_real_
  )
}

v2_build_branch_candidates <- function(context, site_topology, graph, downstream_pairs) {
  scales <- context$config$topology$scales
  station_graph_index <- match(as.numeric(site_topology$reach_id), graph$reach_id)
  v2_assert(!anyNA(station_graph_index), "Station-to-reduced-graph mapping changed before branch construction.")
  station_support <- v2_accumulate_station_support(station_graph_index, graph)
  catalogs <- list()
  diagnostics <- list()
  for (scale in names(scales)) {
    definition <- scales[[scale]]
    trunk_support <- as.integer(definition$station_trunk_support)
    minimum <- as.integer(definition$minimum_station_support)
    v2_assert(minimum >= 2L && minimum < trunk_support, paste("Invalid branch support thresholds for", scale))
    outlet_index <- v2_trace_station_frontier_outlets(
      station_graph_index, graph, station_support, trunk_support
    )
    outlet_id <- v2_id_string(graph$reach_id[outlet_index])
    candidate <- ifelse(
      is.na(outlet_id), NA_character_,
      paste(site_topology$connected_basin_id, outlet_id, sep = "__")
    )
    counts <- table(candidate, useNA = "no")
    support <- rep(0L, length(candidate))
    support[!is.na(candidate)] <- as.integer(counts[candidate[!is.na(candidate)]])
    eligible <- !is.na(candidate) & support >= minimum
    branch_id <- ifelse(eligible, paste(toupper(substr(scale, 1L, 1L)), candidate, sep = "__"), NA_character_)
    structure <- v2_branch_structure_diagnostics(site_topology, branch_id, eligible)
    catalog <- data.frame(
      row_id = site_topology$row_id,
      site_id = site_topology$site_id,
      scale = scale,
      candidate_id = candidate,
      branch_id = branch_id,
      branch_outlet_reach_id = outlet_id,
      station_upstream_support = station_support[station_graph_index],
      station_trunk_support = trunk_support,
      candidate_station_count = support,
      assessment_eligible = eligible,
      support_reason = ifelse(
        is.na(candidate), "station_trunk_support",
        ifelse(eligible, "eligible", "insufficient_station_support")
      ),
      stringsAsFactors = FALSE
    )
    sizes <- as.integer(table(branch_id, useNA = "no"))
    diagnostics[[scale]] <- data.frame(
      scale = scale,
      station_trunk_support = trunk_support,
      minimum_station_support = minimum,
      n_candidate_groups = length(counts),
      n_branches = length(sizes),
      n_eligible_rows = sum(eligible),
      n_station_trunk_rows = sum(is.na(candidate)),
      n_insufficient_support_rows = sum(!is.na(candidate) & !eligible),
      branch_size_min = if (length(sizes)) min(sizes) else NA_integer_,
      branch_size_median = if (length(sizes)) stats::median(sizes) else NA_real_,
      branch_size_mean = if (length(sizes)) mean(sizes) else NA_real_,
      branch_size_p95 = if (length(sizes)) unname(stats::quantile(sizes, 0.95)) else NA_real_,
      branch_size_max = if (length(sizes)) max(sizes) else NA_integer_,
      branch_reach_max = structure$branch_reach_max,
      branch_l12_max = structure$branch_l12_max,
      branch_l6_max = structure$branch_l6_max,
      branch_station_span_km_p95 = structure$branch_station_span_km_p95,
      branch_station_span_km_max = structure$branch_station_span_km_max,
      stringsAsFactors = FALSE
    )
    catalogs[[scale]] <- catalog
  }
  diagnostics <- do.call(rbind, diagnostics)
  anchor_branch <- as.numeric(context$config$topology$primary_selection$historical_branch_anchor)
  anchor_rows <- as.numeric(context$config$topology$primary_selection$historical_eligible_row_anchor)
  diagnostics$relative_branch_distance <- abs(diagnostics$n_branches - anchor_branch) / anchor_branch
  diagnostics$relative_row_distance <- abs(diagnostics$n_eligible_rows - anchor_rows) / anchor_rows
  diagnostics$anchor_distance <- diagnostics$relative_branch_distance + diagnostics$relative_row_distance
  diagnostics <- diagnostics[order(diagnostics$anchor_distance, diagnostics$scale), , drop = FALSE]
  diagnostics$selected_primary <- FALSE
  diagnostics$selected_primary[[1L]] <- TRUE
  selected_scale <- diagnostics$scale[[1L]]
  v2_assert(identical(selected_scale, "primary"), paste("Automatic structural-anchor rule selected", selected_scale, "instead of the configured Primary scale."))

  ordered <- diagnostics[match(c("small", "primary", "large"), diagnostics$scale), , drop = FALSE]
  v2_assert(all(diff(ordered$n_branches) < 0), "Branch counts are not strictly Small > Primary > Large.")
  v2_assert(all(diff(ordered$branch_size_median) > 0), "Median branch sizes are not strictly Small < Primary < Large.")
  sanity <- context$config$topology$sanity
  primary <- ordered[ordered$scale == "primary", , drop = FALSE]
  v2_assert(primary$n_branches >= as.integer(sanity$minimum_primary_branches) && primary$n_branches <= as.integer(sanity$maximum_primary_branches), "Primary branch count is outside the frozen structural sanity range.")
  v2_assert(primary$n_eligible_rows >= as.integer(sanity$minimum_primary_eligible_rows) && primary$n_eligible_rows <= as.integer(sanity$maximum_primary_eligible_rows), "Primary eligible-row count is outside the frozen structural sanity range.")
  v2_assert(primary$branch_size_max <= as.integer(sanity$maximum_primary_branch_size), "Primary contains a composite branch larger than the station-frontier limit.")
  v2_assert(primary$branch_l12_max <= as.integer(sanity$maximum_primary_l12_per_branch), "Primary contains a branch spanning too many L12 units.")
  v2_assert(primary$branch_l6_max <= as.integer(sanity$maximum_primary_l6_per_branch), "Primary contains a branch spanning too many L6 units.")

  catalog_all <- do.call(rbind, catalogs)
  relation_records <- list()
  relation_index <- 0L
  for (scale in names(scales)) {
    current <- catalogs[[scale]]
    upstream <- current$branch_id[match(downstream_pairs$upstream_row_id, current$row_id)]
    downstream <- current$branch_id[match(downstream_pairs$downstream_row_id, current$row_id)]
    keep <- !is.na(upstream) & !is.na(downstream) & upstream != downstream
    if (any(keep)) {
      relation_index <- relation_index + 1L
      relation_records[[relation_index]] <- unique(data.frame(
        scale = scale,
        upstream_branch_id = upstream[keep],
        downstream_branch_id = downstream[keep],
        relation_type = "observed_station_downstream",
        stringsAsFactors = FALSE
      ))
    }
  }
  relations <- if (length(relation_records)) do.call(rbind, relation_records) else data.frame(
    scale = character(), upstream_branch_id = character(), downstream_branch_id = character(), relation_type = character()
  )
  list(catalog = catalog_all, diagnostics = diagnostics, relations = relations, selected_scale = selected_scale)
}

v2_topology_input_signatures <- function(context) {
  l6 <- Sys.glob(file.path(v2_path(context, context$config$input$hydrobasins_l6_root), "*", "hybas_*_lev06_v1c.dbf"))
  l12 <- Sys.glob(file.path(v2_path(context, context$config$input$hydrobasins_l12_root), "*", "hybas_*_lev12_v1c.dbf"))
  list(
    training_table = v2_data_signature(context),
    config = v2_config_signature(context),
    hydrology_interim = v2_file_signature(v2_path(context, context$config$input$hydrology_interim), context$repo_root),
    hydrorivers_dbf = v2_file_signature(v2_path(context, context$config$input$hydrorivers_dbf), context$repo_root),
    hydrobasins_l6 = lapply(l6, v2_file_signature, relative_to = context$repo_root),
    hydrobasins_l12 = lapply(l12, v2_file_signature, relative_to = context$repo_root)
  )
}

stage_prepare_topology <- function(context, validated = NULL, force = FALSE) {
  if (is.null(validated)) validated <- v2_validate_input(context)
  paths <- lapply(context$config$interim, function(path) v2_path(context, path))
  required <- unlist(paths[c("site_topology", "reach_graph", "downstream_pairs", "branch_candidates", "prepare_manifest")])
  if (all(file.exists(required)) && !force) {
    manifest <- jsonlite::read_json(paths$prepare_manifest, simplifyVector = TRUE)
    v2_assert(identical(as.character(manifest$inputs$training_table$md5), as.character(validated$signature$md5)), "Training table changed after topology preparation; rerun with --force before any training.")
    v2_assert(identical(as.character(manifest$inputs$config$md5), as.character(validated$config_signature$md5)), "V2 config changed after topology preparation; rerun with --force before any training.")
    v2_log("Current Base V2 topology checkpoints already exist; preparation skipped.")
    return(invisible(manifest))
  }
  dat <- validated$data
  hydrology <- v2_load_frozen_hydrology(context, dat)
  graph <- v2_build_reduced_reach_graph(context, hydrology$HYRIV_ID)
  l6 <- v2_load_hydrobasins_attributes(v2_path(context, context$config$input$hydrobasins_l6_root), 6L)
  l12 <- v2_load_hydrobasins_attributes(v2_path(context, context$config$input$hydrobasins_l12_root), 12L)
  site_topology <- v2_build_site_topology(context, dat, hydrology, graph, l6, l12)
  downstream_pairs <- v2_build_downstream_pairs(site_topology, graph)
  branches <- v2_build_branch_candidates(context, site_topology, graph, downstream_pairs)
  v2_save_rds(site_topology, paths$site_topology)
  v2_save_rds(graph, paths$reach_graph)
  v2_save_rds(downstream_pairs, paths$downstream_pairs)
  v2_save_rds(branches, paths$branch_candidates)
  inputs <- v2_topology_input_signatures(context)
  manifest <- list(
    status = "TOPOLOGY_PREPARED_RESPONSE_BLIND",
    method = "method-level forward reconstruction",
    response_used = FALSE,
    n_full50_rows = nrow(site_topology),
    n_unique_station_reaches = length(unique(site_topology$reach_id)),
    n_reduced_reaches = nrow(graph),
    n_downstream_station_pairs = nrow(downstream_pairs),
    selected_scale = branches$selected_scale,
    scale_diagnostics = branches$diagnostics,
    inputs = inputs,
    implementation = v2_implementation_signature(context),
    outputs = list(
      site_topology = v2_file_signature(paths$site_topology, context$repo_root),
      reach_graph = v2_file_signature(paths$reach_graph, context$repo_root),
      downstream_pairs = v2_file_signature(paths$downstream_pairs, context$repo_root),
      branch_candidates = v2_file_signature(paths$branch_candidates, context$repo_root)
    ),
    prepared_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
  v2_write_json(manifest, paths$prepare_manifest)
  v2_log("Base V2 response-blind topology preparation complete; selected scale: ", branches$selected_scale, ".")
  invisible(manifest)
}
