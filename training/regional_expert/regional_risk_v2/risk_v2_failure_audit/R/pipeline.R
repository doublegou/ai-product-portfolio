run_project <- function(config_path) {
  if (!file.exists(config_path)) {
    stop("Missing project config: ", config_path, call. = FALSE)
  }
  stop("training_regional_risk_v2_failure_audit is scaffolded but not implemented yet.", call. = FALSE)
}
