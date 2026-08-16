stage_rrisk_build_folds <- function(context, validated = NULL, force = FALSE) {
  paths <- rrisk_fold_paths(context)
  if (file.exists(paths[["manifest"]]) && !force) {
    current <- rrisk_assert_folds_current(context)
    rrisk_log("Frozen Regional Risk V1 folds already match source signatures; preparation skipped.")
    return(invisible(current$manifest))
  }
  completed <- list.files(rrisk_output_path(context, "validation_dir"), pattern = "task_info\\.json$", recursive = TRUE, full.names = TRUE)
  rrisk_assert(length(completed) == 0L, "Validation task outputs exist. Archive them before rebuilding Regional Risk V1 folds.")
  if (is.null(validated)) validated <- stage_rrisk_validate_input(context)
  graph <- rrisk_load_l12_graph(context)
  built <- rrisk_build_branch_map(validated$data, graph, context)
  diagnostics <- rrisk_branch_diagnostics(built$map)
  labels <- rrisk_label_audit(validated$data, built$map, context)
  lobo <- rrisk_build_lobo_assignments(built$map)
  tasks <- rrisk_task_manifest(context)
  rrisk_assert(nrow(lobo) == 372L * 17L, "LOBO preparation did not produce 6,324 row-role records.")
  for (fold in 1:17) {
    current <- lobo[lobo$outer_fold == fold, , drop = FALSE]
    rrisk_assert(sum(current$role == "assessment") == labels$n_stations[labels$branch_order == fold], paste("LOBO assessment size changed for fold", fold))
    rrisk_assert(length(intersect(unique(current$regional_branch_id[current$role == "assessment"]), unique(current$regional_branch_id[current$role == "analysis"]))) == 0L, "A regional branch crosses a LOBO boundary.")
  }
  dir.create(rrisk_output_path(context, "folds_dir"), recursive = TRUE, showWarnings = FALSE)
  rrisk_write_csv(built$map, paths[["branches"]]); rrisk_write_csv(diagnostics, paths[["diagnostics"]])
  rrisk_write_csv(labels, paths[["labels"]]); rrisk_write_csv(lobo, paths[["lobo"]]); rrisk_write_csv(tasks, paths[["tasks"]])
  dbf_path <- rrisk_path(context, context$config$input$hydrobasins_l12_dbf)
  manifest <- list(
    status = "FROZEN_RESPONSE_BLIND_BRANCH_MAP", created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    input = validated$data_signature, config = validated$config_signature,
    environment_predictors = validated$predictor_signature, data_pipeline_config = validated$data_pipeline_config_signature,
    hydrobasins_l12 = rrisk_file_signature(dbf_path),
    implementation = rrisk_implementation_signature(context),
    branch_generation = list(
      version = context$config$branches$version, response_used = FALSE,
      algorithm = "bottom_up_unassigned_station_accumulation_cut_and_reset",
      threshold = as.integer(context$config$branches$minimum_unassigned_station_support),
      cut_branches = 16L, residual_root_branch = 1L, branches = 17L,
      l12_main_basin_id = as.character(context$config$domain$l12_main_basin_id),
      canonical_order = as.character(context$config$branches$canonical_order)
    ),
    audit = list(
      rows = 372L, positive = 80L, negative = 292L, mixed_branches = 14L,
      all_negative_branches = 3L, all_positive_branches = 0L,
      sorted_branch_sizes = sort(as.integer(diagnostics$n_stations))
    ),
    validation = list(design = "strict_LOBO", outer_folds = 17L, model_arms = 5L, training_tasks = 85L, expected_oof_predictions = 1860L),
    elastic_alpha = list(value = as.numeric(context$config$elastic_net$alpha), status = as.character(context$config$elastic_net$alpha_status))
  )
  rrisk_write_json(manifest, paths[["manifest"]])
  rrisk_log("Regional Risk V1 folds frozen: 372 rows, 17 branches, 85 model tasks; response_used=false.")
  invisible(manifest)
}
