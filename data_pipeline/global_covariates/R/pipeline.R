run_project <- function(config_path) {
  if (!file.exists(config_path)) {
    stop("Missing project config: ", config_path, call. = FALSE)
  }
  stop("data_pipeline_global_covariates is scaffolded but not implemented yet.", call. = FALSE)
}
