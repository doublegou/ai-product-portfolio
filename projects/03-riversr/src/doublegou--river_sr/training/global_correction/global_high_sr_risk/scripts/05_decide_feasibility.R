stage_risk_decide_feasibility <- function(context, run_id) {
  risk_assert_folds_current(context)
  reports <- risk_run_dir(context, run_id, "reports")
  repeat_path <- file.path(reports, "repeat_metrics.csv")
  model_path <- file.path(reports, "model_summary.csv")
  risk_assert(file.exists(repeat_path) && file.exists(model_path), "Run aggregation before the feasibility decision.")
  repeat_metrics <- data.table::fread(repeat_path, data.table = FALSE)
  model_summary <- data.table::fread(model_path, data.table = FALSE)
  model_summary$model_pass <- as.logical(model_summary$model_pass)
  repeat_metrics$repeat_pass <- as.logical(repeat_metrics$repeat_pass)
  decision <- risk_decision_record(model_summary, repeat_metrics, context, run_id)
  risk_write_json(decision, file.path(reports, "decision.json"))
  risk_write_text(risk_decision_markdown(decision, model_summary), file.path(reports, "decision.md"))
  risk_finish_run(
    context, run_id, "complete",
    list(experiment_pass = decision$experiment_pass, decision = decision$decision, training_tasks = 30L, final_model_fitted = FALSE)
  )
  risk_log("Risk V1 decision complete: ", decision$decision, ".")
  invisible(decision)
}
