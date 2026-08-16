rrisk_role_summary <- function(pooled, diagnostics) {
  gam_candidates <- pooled[pooled$model_id %in% c("gam_environment", "gam_combined"), , drop = FALSE]
  ranking <- gam_candidates$model_id[order(-gam_candidates$pr_auc, -gam_candidates$roc_auc)][[1L]]
  probability <- gam_candidates$model_id[order(gam_candidates$brier, gam_candidates$log_loss)][[1L]]
  elastic <- diagnostics[diagnostics$model_type == "elastic_net", , drop = FALSE]
  intercept <- stats::aggregate(intercept_only ~ model_id, elastic, sum)
  data.frame(
    role = c("ranking_candidate", "probability_candidate", "spatial_diagnostic_control", "linear_complexity_baseline_environment", "linear_complexity_baseline_combined"),
    model_id = c(ranking, probability, "gam_spatial_only", "elastic_environment", "elastic_combined"),
    detail = c(
      "Best pooled OOF PR-AUC point estimate among Environment and Combined GAM; ROC-AUC secondary.",
      "Lowest pooled OOF Brier among Environment and Combined GAM; log loss secondary; not calibrated.",
      "Diagnostic only; ineligible for winner selection.",
      paste0("Intercept-only in ", intercept$intercept_only[match("elastic_environment", intercept$model_id)], "/17 Outer folds."),
      paste0("Intercept-only in ", intercept$intercept_only[match("elastic_combined", intercept$model_id)], "/17 Outer folds.")
    ), stringsAsFactors = FALSE
  )
}

rrisk_decision_markdown <- function(pooled, macro, roles, contrasts, context, run_id) {
  metric_lines <- apply(pooled, 1L, function(x) sprintf("| %s | %.6f | %.6f | %.6f | %.6f |", x[["model_id"]], as.numeric(x[["pr_auc"]]), as.numeric(x[["roc_auc"]]), as.numeric(x[["brier"]]), as.numeric(x[["log_loss"]])))
  role_lines <- apply(roles, 1L, function(x) sprintf("- `%s`: `%s` — %s", x[["role"]], x[["model_id"]], x[["detail"]]))
  c(
    "# Regional Risk V1 decision", "", paste0("Run ID: `", run_id, "`"), "",
    "## Status", "", "`SIGNAL_FEASIBILITY_ONLY`", "",
    "本实验只评估喜马拉雅区域高-Sr风险结构在完整陌生regional branch上的迁移能力。它不产生Gate、校准器、hard routing、full-data expert或release。", "",
    "## Pooled station-equal LOBO metrics", "", "| Model | PR-AUC | ROC-AUC | Brier | Log loss |", "|---|---:|---:|---:|---:|",
    metric_lines, "", "## Frozen candidate roles", "", role_lines, "",
    "## Interpretation boundary", "",
    "候选角色依据预先冻结的点估计规则产生。模型间bootstrap contrast用于不确定性诊断；point-estimate winner不等于统计学上确定优于另一GAM。Elastic Net仅回答简单线性结构是否足够。", "",
    paste0("Elastic Net alpha固定为`", context$config$elastic_net$alpha, "`；状态：`", context$config$elastic_net$alpha_status, "`。"), "",
    "最终结论不得表述为可部署Regional Expert。"
  )
}
