rrisk11_decision_markdown <- function(gate_metrics, probability_metrics, context, run_id) {
  primary <- gate_metrics[gate_metrics$operating_point == "primary", , drop = FALSE]
  passed <- primary$model_id[primary$primary_gate_pass]
  status <- if (length(passed)) "OPERATIONAL_GATE_EVIDENCE_SUPPORTED" else "RANKING_SIGNAL_NOT_OPERATIONAL_GATE"
  lines <- c(
    "# Regional Risk V1.1 decision", "", paste0("Run ID: `", run_id, "`"), "", "## Status", "", paste0("`", status, "`"), "",
    "V1.1 is independent of Regional Risk V2. It evaluates only the two frozen V1 GAM candidates under strict Nested LOBO, inner-only Platt calibration and inner-only threshold selection.", "",
    "## Primary Gate", "",
    "| Model | Background FPR | Recall | Precision | Positive branches | Extreme branches | Pass |",
    "|---|---:|---:|---:|---:|---:|---|"
  )
  for (i in seq_len(nrow(primary))) lines <- c(lines, sprintf(
    "| %s | %.1f%% | %.1f%% | %.1f%% | %d/%d | %d/%d | %s |",
    primary$model_id[[i]], 100 * primary$background_fpr[[i]], 100 * primary$recall[[i]], 100 * primary$precision[[i]],
    primary$positive_branches_detected[[i]], primary$positive_branches_total[[i]],
    primary$extreme_branches_detected[[i]], primary$extreme_branches_total[[i]], ifelse(primary$primary_gate_pass[[i]], "yes", "no")
  ))
  lines <- c(lines, "", "## Interpretation boundary", "")
  if (length(passed)) {
    lines <- c(lines, paste("Primary Gate evidence targets were met by:", paste(passed, collapse = ", "), ". This authorizes separate deployment planning; it does not create a release or full-data expert."))
  } else {
    lines <- c(lines, "Neither frozen GAM met all independent V1.1 Primary Gate targets. Stop tuning the GAM specification, calibrator and threshold rule; preserve V1 and V1.1 unchanged.")
  }
  c(
    lines, "", "The 5% Strict Gate is diagnostic only. Regional Risk V2 criteria, algorithms and features are not used in this decision.", "",
    "## Provenance", "", paste0("- Probability metric rows: ", nrow(probability_metrics)),
    "- Final model fitted: false", "- Release created: false"
  )
}
