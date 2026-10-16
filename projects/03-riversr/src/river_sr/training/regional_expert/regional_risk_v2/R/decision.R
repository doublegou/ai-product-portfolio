rrisk2_decision_markdown <- function(gate, ranking, run_id) {
  passed <- gate$model_id[as.logical(gate$gate_pass)]
  status <- if (length(passed)) "REGIONAL_RISK_GATE_SUPPORTED" else "NO_CANDIDATE_MET_COMPLETE_REGIONAL_GATE"
  lines <- c("# Regional Risk V2 decision", "", paste0("Run ID: `", run_id, "`"), "", "## Status", "", paste0("`", status, "`"), "",
             "Four prespecified candidates were evaluated under strict nested Leave-One-Branch-Out validation. Each outer threshold was selected only from its outer-training branches.", "",
             "| Candidate | Background FPR | Recall | Precision | Positive branches | Extreme systems | Gate |", "|---|---:|---:|---:|---:|---:|---|")
  for (i in seq_len(nrow(gate))) lines <- c(lines, sprintf("| %s | %.1f%% | %.1f%% | %.1f%% | %d/%d | %d/%d | %s |", gate$model_id[i],
    100*gate$background_fpr[i], 100*gate$recall[i], 100*gate$precision[i], gate$positive_branches_detected[i], gate$positive_branches_total[i],
    gate$extreme_branches_detected[i], gate$extreme_branches_total[i], ifelse(gate$gate_pass[i], "yes", "no")))
  lines <- c(lines, "", "## Interpretation", "")
  if (length(passed)) lines <- c(lines, paste("At least one candidate met the complete predefined Gate:", paste(passed, collapse = ", "), ".")) else
    lines <- c(lines, "No frozen candidate met every Gate criterion. Ranking improvements alone do not qualify a Regional Risk Gate; stop further tuning within these algorithms and feature sets, preserve the experiment, and only then consider a separate failure audit.")
  c(lines, "", "No full-data release model was fitted. Ranking metrics are secondary diagnostics.", "", paste0("Ranking metric rows: ", nrow(ranking)))
}
