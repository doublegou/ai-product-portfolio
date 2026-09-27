`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x

project_root <- function() {
  root <- Sys.getenv("RIVER_SR_PROJECT_ROOT", unset = "")
  if (nzchar(root)) return(normalizePath(root, mustWork = TRUE))
  here::here()
}

read_config <- function() {
  yaml::read_yaml(file.path(project_root(), "config", "project.yml"))
}

ensure_dirs <- function(cfg = read_config()) {
  dirs <- c(
    "data/interim","data/processed","outputs/qc","outputs/folds",
    "outputs/experiment_A","outputs/experiment_B","outputs/diagnostics",
    "outputs/experiment_C","outputs/experiment_D","outputs/experiment_E",
    "outputs/final","logs"
  )
  invisible(lapply(file.path(project_root(), dirs), fs::dir_create, recurse = TRUE))
}

log_msg <- function(...) {
  cat(sprintf("[%s] ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")), ..., "\n", sep = "")
}

stop_missing <- function(path, note = NULL) {
  if (!file.exists(path)) {
    msg <- paste0("Required file is missing: ", path)
    if (!is.null(note)) msg <- paste(msg, note, sep = "\n")
    stop(msg, call. = FALSE)
  }
}

write_atomic_rds <- function(x, path) {
  fs::dir_create(dirname(path), recurse = TRUE)
  tmp <- paste0(path, ".tmp")
  saveRDS(x, tmp, compress = "xz")
  file.rename(tmp, path)
  invisible(path)
}

write_csv_safe <- function(x, path) {
  fs::dir_create(dirname(path), recurse = TRUE)
  readr::write_csv(x, path, na = "")
  invisible(path)
}

safe_name <- function(x) {
  x <- stringr::str_to_lower(as.character(x))
  x <- stringr::str_replace_all(x, "[^a-z0-9]+", "_")
  stringr::str_replace_all(x, "^_|_$", "")
}

check_packages <- function(pkgs) {
  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing)) {
    stop("Missing R packages: ", paste(missing, collapse = ", "),
         "\nRun: Rscript install_packages.R", call. = FALSE)
  }
  invisible(TRUE)
}

read_observations <- function() {
  path <- file.path(project_root(), "data", "processed", "river_sr_site_model_input.rds")
  stop_missing(path, "Create the site-level model input after QC.")
  readRDS(path)
}

read_model_table <- function() {
  path <- file.path(project_root(), "data", "processed", "model_table.rds")
  stop_missing(path, "Place predictors_at_sites.rds in data/external and run stage 02.")
  readRDS(path)
}
