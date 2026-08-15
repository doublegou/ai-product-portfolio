run_project <- function(config_path) {
  if (!file.exists(config_path)) {
    stop("Missing project config: ", config_path, call. = FALSE)
  }
  stop("training_base_v2 is scaffolded but not implemented yet.", call. = FALSE)
}
