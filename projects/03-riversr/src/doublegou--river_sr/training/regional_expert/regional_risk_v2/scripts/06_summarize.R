stage_rrisk2_summarize <- function(context, run_id) {
  root <- rrisk2_output_path(context, "validation_dir"); required <- c("gate_metrics.csv", "ranking_metrics.csv", "oof_manifest.json")
  rrisk2_assert(all(file.exists(file.path(root, required))), "Run V2 aggregation before summarization.")
  gate <- rrisk2_read_csv(file.path(root, "gate_metrics.csv")); ranking <- rrisk2_read_csv(file.path(root, "ranking_metrics.csv"))
  lines <- rrisk2_decision_markdown(gate, ranking, run_id); rrisk2_write_text(lines, file.path(root, "DECISION.md")); rrisk2_write_text(lines, rrisk2_run_dir(context, run_id, "reports", "DECISION.md"))
  passed <- any(as.logical(gate$gate_pass)); decision <- if (passed) "REGIONAL_RISK_GATE_SUPPORTED" else "NO_CANDIDATE_MET_COMPLETE_REGIONAL_GATE"
  rrisk2_finish_run(context, run_id, "complete", list(decision = decision, training_tasks = 68L, model_fits = 1156L, oof_predictions = 1488L,
    gate_evaluated = TRUE, full_data_model_fitted = FALSE, release_created = FALSE))
  rrisk2_log("V2 summary complete; no full-data model or release created."); invisible(lines)
}
