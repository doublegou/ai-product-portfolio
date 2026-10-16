v0_collect_selected_parameters <- function(context) {
  scales <- as.integer(unlist(context$config$validation$spatial_scales_km))
  records <- list()
  index <- 0L
  for (scale in scales) {
    scheme <- paste0("spatial_", scale)
    for (outer_fold in seq_len(as.integer(context$config$validation$outer_folds))) {
      path <- file.path(v0_task_dir(context, scheme, outer_fold), "selected_params.yml")
      v0_assert(file.exists(path), paste("Missing selected parameters:", path))
      selected <- yaml::read_yaml(path)
      index <- index + 1L
      records[[index]] <- data.frame(
        scheme = scheme,
        outer_fold = outer_fold,
        mtry = as.integer(selected$mtry),
        min_node_size = as.integer(selected$min_node_size),
        sample_fraction = as.numeric(selected$sample_fraction),
        selected_inner_rmse = as.numeric(selected$mean_rmse)
      )
    }
  }
  result <- do.call(rbind, records)
  v0_assert(nrow(result) == 15L, paste("Expected 15 spatial selected-parameter records; found", nrow(result)))
  result
}

v0_select_consensus <- function(selected) {
  key <- interaction(selected$mtry, selected$min_node_size, selected$sample_fraction, drop = TRUE)
  groups <- split(selected, key)
  table <- do.call(rbind, lapply(groups, function(x) data.frame(
    mtry = x$mtry[[1L]],
    min_node_size = x$min_node_size[[1L]],
    sample_fraction = x$sample_fraction[[1L]],
    n_tasks = nrow(x),
    mean_selected_inner_rmse = mean(x$selected_inner_rmse[is.finite(x$selected_inner_rmse)])
  )))
  table <- table[order(
    -table$n_tasks,
    table$mean_selected_inner_rmse,
    table$mtry,
    -table$min_node_size,
    table$sample_fraction
  ), , drop = FALSE]
  rownames(table) <- NULL
  list(table = table, selected = table[1L, , drop = FALSE])
}
