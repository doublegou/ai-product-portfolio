stage_rrisk_summarize_run <- function(context, run_id) {
  validation_dir <- rrisk_output_path(context, "validation_dir")
  required <- c("pooled_metrics.csv", "mixed_branch_macro_metrics.csv", "candidate_roles.csv", "paired_model_contrasts.csv", "oof_manifest.json")
  rrisk_assert(all(file.exists(file.path(validation_dir, required))), "Run aggregation before Regional Risk V1 summarization.")
  pooled <- rrisk_read_csv(file.path(validation_dir, "pooled_metrics.csv"))
  macro <- rrisk_read_csv(file.path(validation_dir, "mixed_branch_macro_metrics.csv"))
  roles <- rrisk_read_csv(file.path(validation_dir, "candidate_roles.csv"))
  contrasts <- rrisk_read_csv(file.path(validation_dir, "paired_model_contrasts.csv"))
  lines <- rrisk_decision_markdown(pooled, macro, roles, contrasts, context, run_id)
  rrisk_write_text(lines, file.path(validation_dir, "DECISION.md"))
  rrisk_write_text(lines, rrisk_run_dir(context, run_id, "reports", "DECISION.md"))
  rrisk_finish_run(context, run_id, "complete", list(
    decision = "SIGNAL_FEASIBILITY_ONLY", training_tasks = 85L, oof_predictions = 1860L,
    gate_selected = FALSE, probability_calibrated = FALSE, final_model_fitted = FALSE, release_created = FALSE
  ))
  rrisk_log("Regional Risk V1 summary complete; no Gate or final model created.")
  invisible(lines)
}
