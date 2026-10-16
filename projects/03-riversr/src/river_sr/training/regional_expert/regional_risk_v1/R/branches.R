rrisk_id_string <- function(x) {
  result <- rep(NA_character_, length(x)); valid <- !is.na(x) & is.finite(as.numeric(x))
  result[valid] <- sprintf("%.0f", as.numeric(x[valid])); result
}

rrisk_load_l12_graph <- function(context) {
  path <- rrisk_path(context, context$config$input$hydrobasins_l12_dbf)
  rrisk_assert(file.exists(path), paste("Missing HydroBASINS L12 DBF required for local fold preparation:", path))
  raw <- foreign::read.dbf(path, as.is = TRUE)
  required <- c("HYBAS_ID", "NEXT_DOWN", "MAIN_BAS", "PFAF_ID", "SUB_AREA", "UP_AREA", "ORDER")
  rrisk_assert(length(setdiff(required, names(raw))) == 0L, "HydroBASINS L12 DBF lacks required attributes.")
  data.frame(
    l12_id = rrisk_id_string(raw$HYBAS_ID), next_down_l12_id = rrisk_id_string(raw$NEXT_DOWN),
    main_basin_id = rrisk_id_string(raw$MAIN_BAS), pfaf_id = sprintf("%012.0f", as.numeric(raw$PFAF_ID)),
    sub_area_km2 = as.numeric(raw$SUB_AREA), upstream_area_km2 = as.numeric(raw$UP_AREA),
    basin_order = as.integer(raw$ORDER), stringsAsFactors = FALSE
  )
}

rrisk_l12_station_closure <- function(dat, graph, context) {
  l12_column <- context$config$columns$l12_id
  station_l12 <- as.character(dat[[l12_column]])
  index <- stats::setNames(seq_len(nrow(graph)), graph$l12_id)
  rrisk_assert(!anyNA(unname(index[station_l12])), "A regional station L12 is absent from HydroBASINS.")
  main <- unique(graph$main_basin_id[match(station_l12, graph$l12_id)])
  rrisk_assert(identical(main, as.character(context$config$domain$l12_main_basin_id)), "Regional station L12 units do not share the frozen L12 main basin.")
  keep <- logical(nrow(graph))
  for (start_id in unique(station_l12)) {
    current <- unname(index[[start_id]]); steps <- 0L
    while (!is.na(current) && !keep[[current]]) {
      keep[[current]] <- TRUE
      current <- unname(index[graph$next_down_l12_id[[current]]])
      steps <- steps + 1L; rrisk_assert(steps <= 100000L, "L12 downstream closure exceeded 100,000 nodes.")
    }
  }
  closure <- graph[keep, , drop = FALSE]
  closure_index <- stats::setNames(seq_len(nrow(closure)), closure$l12_id)
  closure$next_index <- unname(closure_index[closure$next_down_l12_id])
  counts <- table(station_l12)
  closure$station_count <- as.integer(counts[closure$l12_id]); closure$station_count[is.na(closure$station_count)] <- 0L
  roots <- closure$l12_id[is.na(closure$next_index)]
  rrisk_assert(identical(roots, as.character(context$config$domain$l12_main_basin_id)), "Regional L12 closure does not terminate at the frozen main basin.")
  closure
}

rrisk_cut_l12_tree <- function(closure, context) {
  threshold <- as.integer(context$config$branches$minimum_unassigned_station_support)
  indegree <- tabulate(closure$next_index[!is.na(closure$next_index)], nbins = nrow(closure))
  queue <- which(indegree == 0L)
  accumulated <- as.integer(closure$station_count)
  cut_indices <- integer(); processed <- 0L
  while (length(queue)) {
    current <- queue[[1L]]; queue <- queue[-1L]; processed <- processed + 1L
    pass <- accumulated[[current]]
    if (pass >= threshold) { cut_indices <- c(cut_indices, current); pass <- 0L }
    downstream <- closure$next_index[[current]]
    if (!is.na(downstream)) {
      accumulated[[downstream]] <- accumulated[[downstream]] + pass
      indegree[[downstream]] <- indegree[[downstream]] - 1L
      if (indegree[[downstream]] == 0L) queue <- c(queue, downstream)
    }
  }
  rrisk_assert(processed == nrow(closure), "Regional L12 closure contains a cycle.")
  root_index <- which(is.na(closure$next_index))
  list(
    cut_outlets = closure$l12_id[cut_indices], root = closure$l12_id[root_index],
    residual_station_count = accumulated[root_index], accumulated = accumulated
  )
}

rrisk_assign_station_outlet <- function(station_l12, graph, cut_outlets, root) {
  index <- stats::setNames(seq_len(nrow(graph)), graph$l12_id)
  vapply(station_l12, function(start_id) {
    current <- unname(index[[start_id]]); steps <- 0L
    repeat {
      id <- graph$l12_id[[current]]
      if (id %in% cut_outlets) return(id)
      current <- unname(index[graph$next_down_l12_id[[current]]])
      if (is.na(current)) return(root)
      steps <- steps + 1L; rrisk_assert(steps <= 100000L, "Station-to-branch traversal exceeded 100,000 nodes.")
    }
  }, character(1L))
}

rrisk_build_branch_map <- function(dat, graph, context) {
  closure <- rrisk_l12_station_closure(dat, graph, context)
  cut <- rrisk_cut_l12_tree(closure, context)
  expected_cuts <- as.integer(context$config$branches$expected_branches) - 1L
  rrisk_assert(length(cut$cut_outlets) == expected_cuts, "Bottom-up threshold rule did not produce 16 cut branches.")
  rrisk_assert(as.integer(cut$residual_station_count) == 6L, "Regional root residual is no longer six stations.")
  cut_order <- sort(as.character(cut$cut_outlets))
  outlet_order <- c(cut_order, as.character(cut$root))
  assigned_outlet <- rrisk_assign_station_outlet(as.character(dat[[context$config$columns$l12_id]]), graph, cut$cut_outlets, cut$root)
  branch_order <- match(assigned_outlet, outlet_order)
  branch_id <- sprintf("himalaya_branch_%03d_%s", branch_order, assigned_outlet)
  sizes <- table(branch_id)
  result <- data.frame(
    row_id = as.character(dat[[context$config$columns$row_id]]),
    site_id = as.character(dat[[context$config$columns$site_id]]),
    terminal_component_id = as.character(dat[[context$config$columns$terminal_component_id]]),
    station_l12_id = as.character(dat[[context$config$columns$l12_id]]),
    branch_outlet_l12_id = assigned_outlet, regional_branch_id = branch_id,
    branch_order = as.integer(branch_order), branch_size = as.integer(sizes[branch_id]),
    stringsAsFactors = FALSE
  )
  rrisk_assert(!anyNA(result) && !anyDuplicated(result$row_id), "Branch map membership is incomplete or duplicated.")
  rrisk_assert(length(unique(result$regional_branch_id)) == as.integer(context$config$branches$expected_branches), "Branch map does not contain 17 branches.")
  expected_sizes <- as.integer(unlist(context$config$branches$expected_size_sorted))
  rrisk_assert(identical(sort(as.integer(sizes)), sort(expected_sizes)), "Regional branch sizes changed from the frozen structural anchor.")
  list(map = result, closure = closure, cut = cut)
}
