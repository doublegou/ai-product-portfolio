stage_risk_build_folds <- function(context, validated = NULL, force = FALSE) {
  paths <- risk_fold_paths(context)
  if (file.exists(paths[["manifest"]]) && !force) {
    current <- risk_assert_folds_current(context)
    risk_log("Frozen Risk V1 Inner folds already match all source signatures; preparation skipped.")
    return(invisible(current$manifest))
  }
  validation_dir <- risk_output_path(context, "validation_dir")
  completed <- list.files(validation_dir, pattern = "task_info\\.json$", recursive = TRUE, full.names = TRUE)
  risk_assert(length(completed) == 0L, "Validation task outputs exist. Archive them before rebuilding Risk V1 folds.")
  if (is.null(validated)) validated <- stage_risk_validate_input(context)
  built <- risk_build_inner_folds(validated, context)
  minimum <- as.integer(context$config$validation$minimum_positive_groups_per_inner_assessment)
  risk_assert(all(built$diagnostics$n_positive_groups >= minimum), paste("An Inner assessment has fewer than", minimum, "positive hydrological systems."))

  inner <- built$inner
  groups_crossing <- stats::aggregate(inner_fold ~ repeat_id + outer_fold + validation_unit, inner, function(x) length(unique(x)))
  risk_assert(all(groups_crossing$inner_fold == 1L), "A hydrological system crosses a Risk V1 Inner fold.")
  expected_inner_rows <- 0L
  for (repeat_id in seq_len(as.integer(context$config$validation$repeats))) {
    current_outer <- validated$outer[validated$outer$repeat_id == repeat_id, , drop = FALSE]
    for (outer_fold in seq_len(as.integer(context$config$validation$outer_folds))) {
      expected <- current_outer$row_id[current_outer$outer_fold != outer_fold]
      current <- inner[inner$repeat_id == repeat_id & inner$outer_fold == outer_fold, , drop = FALSE]
      risk_assert(setequal(current$row_id, expected) && !anyDuplicated(current$row_id), paste("Risk Inner rows differ from Outer training rows:", repeat_id, outer_fold))
      risk_assert(setequal(unique(current$inner_fold), seq_len(as.integer(context$config$validation$inner_folds))), paste("Risk Inner task lacks a fold:", repeat_id, outer_fold))
      expected_inner_rows <- expected_inner_rows + length(expected)
    }
  }
  risk_assert(nrow(inner) == expected_inner_rows, "Risk Inner assignments have the wrong total row count.")
  tasks <- risk_task_manifest(context)
  risk_assert(nrow(tasks) == 30L, "Risk V1 task manifest must contain 30 tasks.")

  dir.create(risk_output_path(context, "folds_dir"), recursive = TRUE, showWarnings = FALSE)
  risk_write_csv(inner, paths[["inner"]])
  risk_write_csv(built$diagnostics, paths[["diagnostics"]])
  risk_write_csv(tasks, paths[["tasks"]])
  manifest <- list(
    status = "frozen", created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    input = validated$data_signature, config = validated$config_signature,
    base_v1_fold_manifest = validated$base_manifest_signature,
    base_outer_assignments = validated$outer_signature,
    hydrological_groups = validated$groups_signature,
    n_rows = nrow(validated$data), n_predictors = length(validated$predictors), predictors = validated$predictors,
    outer = list(source = "Base V1 frozen Primary assignments", repeats = 3L, folds = 5L),
    inner = list(
      folds = 3L, tasks = 15L, expected_assignment_rows = nrow(inner),
      assignment = "positive hydrological systems first; balance positive-system count, positive rows, then total rows; fixed seeded ties",
      minimum_positive_groups_per_assessment = minimum
    ),
    models = c("elastic_net", "probability_rf"), training_tasks = nrow(tasks)
  )
  risk_write_json(manifest, paths[["manifest"]])
  risk_log("Risk V1 folds frozen: 15 Outer designs, 45 Inner assessments and 30 model tasks.")
  invisible(manifest)
}
