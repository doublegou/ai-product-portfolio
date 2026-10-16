risk_apply_promotion_gates <- function(metrics, context) {
  promotion <- context$config$promotion
  metrics$gate_recall <- metrics$recall >= as.numeric(promotion$min_recall)
  metrics$gate_precision <- metrics$precision >= as.numeric(promotion$min_precision)
  metrics$gate_background_fpr <- metrics$background_fpr <= as.numeric(promotion$max_background_fpr)
  metrics$gate_pr_auc <- metrics$pr_auc >= as.numeric(promotion$min_pr_auc)
  metrics$gate_positive_groups <- metrics$positive_groups_detected >= as.integer(promotion$min_positive_groups_detected)
  metrics$gate_extreme_groups <- metrics$extreme_groups_detected >= as.integer(promotion$min_extreme_groups_detected)
  gate_columns <- c(
    "gate_recall", "gate_precision", "gate_background_fpr", "gate_pr_auc",
    "gate_positive_groups", "gate_extreme_groups"
  )
  metrics$repeat_pass <- apply(metrics[gate_columns], 1L, function(x) all(as.logical(x)))
  metrics
}

risk_model_summary <- function(repeat_metrics, context) {
  models <- unique(repeat_metrics$model)
  rows <- lapply(models, function(model) {
    current <- repeat_metrics[repeat_metrics$model == model, , drop = FALSE]
    n_pass <- sum(current$repeat_pass)
    data.frame(
      model = model, repeats = nrow(current), repeats_passed = n_pass,
      model_pass = n_pass >= as.integer(context$config$promotion$repeats_required),
      mean_recall = mean(current$recall), mean_precision = mean(current$precision),
      mean_background_fpr = mean(current$background_fpr), mean_pr_auc = mean(current$pr_auc),
      mean_positive_groups_detected = mean(current$positive_groups_detected),
      mean_extreme_groups_detected = mean(current$extreme_groups_detected),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

risk_decision_record <- function(model_summary, repeat_metrics, context, run_id) {
  passed_models <- as.character(model_summary$model[model_summary$model_pass])
  experiment_pass <- length(passed_models) > 0L
  list(
    project = context$config$project$id, run_id = run_id,
    decided_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    experiment_pass = experiment_pass, passed_models = passed_models,
    decision = if (experiment_pass) "transferable_signal_feasible_open_risk_v1_1" else "transferable_signal_insufficient_stop",
    consequence = if (experiment_pass) {
      "Open a separate Risk V1.1 project for calibration and deployment; do not promote a model from this feasibility directory."
    } else {
      "Retain the complete OOF evidence and do not fit or release a production High-Sr classifier from these 47 predictors."
    },
    rule = list(
      repeat_gate = "Recall, Precision, background FPR, PR-AUC, positive-system coverage and extreme-system coverage must all pass",
      model_gate = paste0("at least ", as.integer(context$config$promotion$repeats_required), " of 3 repeats pass"),
      experiment_gate = "at least one model passes"
    ),
    models = lapply(seq_len(nrow(model_summary)), function(i) as.list(model_summary[i, , drop = FALSE])),
    repeat_records = lapply(seq_len(nrow(repeat_metrics)), function(i) as.list(repeat_metrics[i, , drop = FALSE]))
  )
}

risk_decision_markdown <- function(decision, model_summary) {
  table_lines <- c(
    "| Model | Repeats passed | Model pass | Mean Recall | Mean Precision | Mean background FPR | Mean PR-AUC |",
    "|---|---:|:---:|---:|---:|---:|---:|"
  )
  for (i in seq_len(nrow(model_summary))) {
    row <- model_summary[i, ]
    table_lines <- c(table_lines, sprintf(
      "| %s | %d/%d | %s | %.4f | %.4f | %.4f | %.4f |",
      row$model, row$repeats_passed, row$repeats, if (row$model_pass) "YES" else "NO",
      row$mean_recall, row$mean_precision, row$mean_background_fpr, row$mean_pr_auc
    ))
  }
  c(
    "# Global High-Sr Risk V1 feasibility decision", "",
    paste("- Run:", decision$run_id),
    paste("- Experiment pass:", if (decision$experiment_pass) "YES" else "NO"),
    paste("- Decision:", decision$decision),
    paste("- Consequence:", decision$consequence), "", table_lines, "",
    "The decision uses complete repeat-level OOF predictions. Probabilities are not averaged across repeats, and this project creates no final model or release."
  )
}
