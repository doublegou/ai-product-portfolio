stage_select_final_params <- function(context, run_id) {
  v0_log("Selecting final RF parameters from 15 spatial outer tasks.")
  selected <- v0_collect_selected_parameters(context)
  consensus <- v0_select_consensus(selected)
  models_dir <- v0_run_dir(context, run_id, "models")
  dir.create(models_dir, recursive = TRUE, showWarnings = FALSE)
  v0_write_csv(selected, file.path(models_dir, "spatial_selected_params.csv"))
  v0_write_csv(consensus$table, file.path(models_dir, "consensus_table.csv"))
  chosen <- consensus$selected
  record <- list(
    mtry = as.integer(chosen$mtry[[1L]]),
    min_node_size = as.integer(chosen$min_node_size[[1L]]),
    sample_fraction = as.numeric(chosen$sample_fraction[[1L]]),
    n_tasks_supporting = as.integer(chosen$n_tasks[[1L]]),
    mean_selected_inner_rmse = as.numeric(chosen$mean_selected_inner_rmse[[1L]]),
    source_tasks = 15L,
    excluded_scheme = "reference",
    selection_order = "n_tasks desc, mean_selected_inner_rmse asc, mtry asc, min_node_size desc, sample_fraction asc"
  )
  v0_write_yaml(record, file.path(models_dir, "selected_params.yml"))
  v0_log(
    "Consensus selected: mtry=", record$mtry, ", min.node.size=", record$min_node_size,
    ", sample.fraction=", record$sample_fraction, ", support=", record$n_tasks_supporting, "/15."
  )
  record
}
