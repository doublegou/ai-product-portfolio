stage_corr_decide_feasibility <- function(context, run_id) {
  corr_assert_frozen_current(context)
  reports <- corr_run_dir(context, run_id, "reports")
  candidate_path <- file.path(reports, "candidate_summary.csv")
  corr_assert(file.exists(candidate_path), "Run aggregate before decide.")
  candidate_summary <- corr_read_table(candidate_path)
  for (column in c("residual_signal_pass", "raw_base_safety_pass", "candidate_promotion_pass")) candidate_summary[[column]] <- as.logical(candidate_summary[[column]])
  decision <- corr_decision_record(candidate_summary, run_id)
  corr_write_json(decision, file.path(reports, "decision.json"))
  corr_write_text(corr_decision_markdown(decision, candidate_summary), file.path(reports, "decision.md"))
  corr_finish_run(context, run_id, "complete", list(
    outcome = decision$outcome, residual_signal_any = decision$residual_signal_any,
    oracle_promotion_pass = decision$oracle_promotion_pass, training_tasks = 45L,
    unique_base_fits = 240L, final_model_fitted = FALSE, base_v1_replaced = FALSE
  ))
  corr_log("Correction feasibility decision complete: ", decision$outcome, ".")
  invisible(decision)
}
