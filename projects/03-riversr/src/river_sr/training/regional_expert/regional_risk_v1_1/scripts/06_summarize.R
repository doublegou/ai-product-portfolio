stage_rrisk11_summarize <- function(context, run_id) {
  validation_dir <- rrisk11_output_path(context, "validation_dir")
  required <- c("gate_metrics.csv", "probability_metrics.csv", "oof_manifest.json")
  rrisk11_assert(all(file.exists(file.path(validation_dir, required))), "Run aggregation before Regional Risk V1.1 summarization.")
  gate_metrics <- rrisk11_read_csv(file.path(validation_dir, "gate_metrics.csv"))
  probability_metrics <- rrisk11_read_csv(file.path(validation_dir, "probability_metrics.csv"))
  lines <- rrisk11_decision_markdown(gate_metrics, probability_metrics, context, run_id)
  rrisk11_write_text(lines, file.path(validation_dir, "DECISION.md"))
  rrisk11_write_text(lines, rrisk11_run_dir(context, run_id, "reports", "DECISION.md"))
  primary <- gate_metrics[gate_metrics$operating_point == "primary", , drop = FALSE]
  passed <- any(as.logical(primary$primary_gate_pass))
  decision <- if (passed) "OPERATIONAL_GATE_EVIDENCE_SUPPORTED" else "RANKING_SIGNAL_NOT_OPERATIONAL_GATE"
  rrisk11_finish_run(context, run_id, "complete", list(
    decision = decision, training_tasks = 34L, gam_fits = 578L, oof_predictions = 744L,
    probability_calibrated = TRUE, gate_evaluated = TRUE, final_model_fitted = FALSE,
    release_created = FALSE, v2_dependency = FALSE
  ))
  rrisk11_log("Regional Risk V1.1 summary complete; no full-data model or release created.")
  invisible(lines)
}
