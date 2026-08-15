run_project <- function(config_path) {
  if (!file.exists(config_path)) {
    stop("Missing project config: ", config_path, call. = FALSE)
  }
  stop("training_global_high_sr_risk is scaffolded but not implemented yet.", call. = FALSE)
}
