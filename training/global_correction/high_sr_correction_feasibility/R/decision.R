corr_candidate_summary <- function(repeat_metrics, context) {
  eps <- as.numeric(context$config$selection$numerical_epsilon)
  required <- as.integer(context$config$selection$repeats_required)
  candidates <- repeat_metrics[repeat_metrics$feature_set %in% c("env47", "full50"), , drop = FALSE]
  keys <- unique(candidates[c("model", "feature_set")])
  records <- lapply(seq_len(nrow(keys)), function(i) {
    x <- candidates[candidates$model == keys$model[[i]] & candidates$feature_set == keys$feature_set[[i]], , drop = FALSE]
    corr_assert(nrow(x) == as.integer(context$config$validation$repeats), "Candidate does not have exactly three repeat metrics.")
    signal_count <- sum(x$signal_repeat_pass)
    safety_count <- sum(x$raw_base_safety_repeat_pass)
    mean_signal <- mean(x$signal_improvement)
    mean_raw <- mean(x$raw_base_improvement)
    signal_pass <- signal_count >= required && mean_signal > eps
    safety_pass <- safety_count >= required && mean_raw > eps
    data.frame(
      model = keys$model[[i]], feature_set = keys$feature_set[[i]],
      signal_repeats_passed = signal_count, mean_signal_improvement = mean_signal,
      residual_signal_pass = signal_pass, safety_repeats_passed = safety_count,
      mean_raw_base_improvement = mean_raw, raw_base_safety_pass = safety_pass,
      candidate_promotion_pass = signal_pass && safety_pass, stringsAsFactors = FALSE
    )
  })
  do.call(rbind, records)
}

corr_decision_record <- function(candidate_summary, run_id) {
  signal_any <- any(candidate_summary$residual_signal_pass)
  promotion_any <- any(candidate_summary$candidate_promotion_pass)
  status <- if (!signal_any) "NO_STABLE_RESIDUAL_SIGNAL" else if (!promotion_any) "SIGNAL_ONLY_BUT_NOT_USEFUL" else "ORACLE_FEASIBILITY_SUPPORTED"
  outcome <- if (promotion_any) "ELIGIBLE_FOR_FUTURE_DEPLOYABLE_STUDY" else "STOP"
  list(
    run_id = run_id, status = status, outcome = outcome,
    residual_signal_any = signal_any, oracle_promotion_pass = promotion_any,
    final_model_fitted = FALSE, base_v1_replaced = FALSE,
    decided_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
}

corr_decision_markdown <- function(decision, candidate_summary) {
  lines <- c(
    "# High-Sr Correction Feasibility decision", "",
    paste("- Status:", decision$status), paste("- Outcome:", decision$outcome),
    paste("- Any historical residual-signal pass:", decision$residual_signal_any),
    paste("- Oracle promotion pass:", decision$oracle_promotion_pass),
    "- Final model fitted: FALSE", "- Base V1 replaced: FALSE", "",
    "## Candidate gates", "",
    "| Model | Features | Signal repeats | Mean signal improvement | Signal pass | Safety repeats | Mean raw-Base improvement | Safety pass | Promotion pass |",
    "|---|---|---:|---:|---|---:|---:|---|---|"
  )
  rows <- apply(candidate_summary, 1L, function(x) paste0(
    "| ", x[["model"]], " | ", x[["feature_set"]], " | ", x[["signal_repeats_passed"]],
    " | ", format(as.numeric(x[["mean_signal_improvement"]]), digits = 6), " | ", x[["residual_signal_pass"]],
    " | ", x[["safety_repeats_passed"]], " | ", format(as.numeric(x[["mean_raw_base_improvement"]]), digits = 6),
    " | ", x[["raw_base_safety_pass"]], " | ", x[["candidate_promotion_pass"]], " |"
  ))
  c(lines, rows, "", "This project produces no deployable gate, correction model, or release bundle.")
}
