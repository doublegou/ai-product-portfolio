fa_robust_scale <- function(dat, predictors) {
  x <- data.matrix(dat[predictors]); center <- apply(x, 2L, stats::median); scale <- apply(x, 2L, stats::IQR)
  bad <- !is.finite(scale) | scale <= 0; if (any(bad)) scale[bad] <- apply(x[, bad, drop = FALSE], 2L, stats::mad)
  bad <- !is.finite(scale) | scale <= 0; if (any(bad)) scale[bad] <- apply(x[, bad, drop = FALSE], 2L, stats::sd)
  keep <- is.finite(scale) & scale > 0; fa_assert(any(keep), "No varying features remain for nearest-neighbor audit.")
  list(x = sweep(sweep(x[, keep, drop = FALSE], 2L, center[keep], "-"), 2L, scale[keep], "/"), retained = predictors[keep], dropped = predictors[!keep])
}

fa_nn_audit <- function(validated, predictors, feature_set, context) {
  dat <- validated$data; scaled <- fa_robust_scale(dat, predictors); query_index <- which(dat$.failure_role == "missed_high_sr")
  max_k <- max(as.integer(unlist(context$config$nearest_neighbor_audit$sensitivity_k))); edges <- vector("list", length(query_index))
  for (i in seq_along(query_index)) {
    query <- query_index[i]; candidates <- which(dat$.regional_branch_id != dat$.regional_branch_id[query]); distance <- sqrt(rowMeans((scaled$x[candidates, , drop = FALSE] - matrix(scaled$x[query, ], nrow = length(candidates), ncol = ncol(scaled$x), byrow = TRUE))^2))
    chosen <- candidates[order(distance, dat[[context$config$columns$row_id]][candidates])[seq_len(min(max_k, length(candidates)))]]
    edges[[i]] <- data.frame(feature_set = feature_set, query_row_id = dat[[context$config$columns$row_id]][query], query_branch = dat$.regional_branch_id[query], query_observed_sr = dat$.observed[query],
      neighbor_rank = seq_along(chosen), neighbor_row_id = dat[[context$config$columns$row_id]][chosen], neighbor_branch = dat$.regional_branch_id[chosen], neighbor_observed_sr = dat$.observed[chosen],
      neighbor_high_sr = dat$.label[chosen], distance = distance[match(chosen, candidates)], query_branch_sqrt_weight = dat$.branch_sqrt_weight[query], neighbor_branch_sqrt_weight = dat$.branch_sqrt_weight[chosen], stringsAsFactors = FALSE)
  }
  edges <- do.call(rbind, edges); k_values <- as.integer(unlist(context$config$nearest_neighbor_audit$sensitivity_k))
  global_station <- mean(dat$.label); global_branch_weighted <- sum(dat$.branch_sqrt_weight * dat$.label) / sum(dat$.branch_sqrt_weight)
  summaries <- do.call(rbind, lapply(k_values, function(k) {
    x <- edges[edges$neighbor_rank <= k, , drop = FALSE]; edge_weight <- x$query_branch_sqrt_weight * x$neighbor_branch_sqrt_weight
    data.frame(feature_set = feature_set, k = k, query_sites = length(unique(x$query_row_id)), neighbor_edges = nrow(x), high_sr_neighbor_fraction_station_equal = mean(x$neighbor_high_sr),
      high_sr_neighbor_fraction_branch_sqrt = sum(edge_weight * x$neighbor_high_sr) / sum(edge_weight), global_high_sr_fraction_station_equal = global_station,
      global_high_sr_fraction_branch_sqrt = global_branch_weighted, station_equal_delta_from_global = mean(x$neighbor_high_sr) - global_station,
      branch_sqrt_delta_from_global = sum(edge_weight * x$neighbor_high_sr) / sum(edge_weight) - global_branch_weighted, stringsAsFactors = FALSE)
  }))
  list(edges = edges, summary = summaries, retained = scaled$retained, dropped = scaled$dropped)
}
