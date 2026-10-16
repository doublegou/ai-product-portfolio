fa_assert <- function(condition, message) if (!isTRUE(condition)) stop(message, call. = FALSE)

fa_packages <- function() c("yaml", "jsonlite", "digest", "data.table")

fa_require_packages <- function() {
  missing <- fa_packages()[!vapply(fa_packages(), requireNamespace, logical(1L), quietly = TRUE)]
  fa_assert(!length(missing), paste("Missing R packages. Run Rscript env/bootstrap.R:", paste(missing, collapse = ", ")))
}

fa_context <- function(repo_root, project_dir) {
  fa_require_packages(); config_path <- file.path(project_dir, "config", "default.yml")
  fa_assert(file.exists(config_path), "Missing Failure Audit config.")
  list(repo_root = normalizePath(repo_root, winslash = "/", mustWork = TRUE), project_dir = normalizePath(project_dir, winslash = "/", mustWork = TRUE),
       config_path = normalizePath(config_path, winslash = "/", mustWork = TRUE), config = yaml::read_yaml(config_path))
}

fa_path <- function(context, path) if (grepl("^[A-Za-z]:[/\\\\]|^/", path)) path else file.path(context$repo_root, path)

fa_read_lines <- function(path) {
  fa_assert(file.exists(path), paste("Missing manifest:", path)); x <- trimws(readLines(path, warn = FALSE, encoding = "UTF-8")); x[nzchar(x) & !startsWith(x, "#")]
}

fa_read_csv <- function(path) {
  fa_assert(file.exists(path), paste("Missing CSV:", path)); as.data.frame(data.table::fread(path, na.strings = c("", "NA", "NaN"), integer64 = "character", data.table = FALSE))
}

fa_signature <- function(path) {
  fa_assert(file.exists(path), paste("Missing signature target:", path)); normalized <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  list(path = gsub("\\\\", "/", normalizePath(path, mustWork = TRUE)), md5 = digest::digest(normalized, algo = "md5", serialize = FALSE), hash_method = "normalized_lf_text_md5")
}

fa_atomic_target <- function(path) { dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE); tempfile("regional_failure_audit_", tmpdir = dirname(path)) }

fa_write_csv <- function(x, path) { tmp <- fa_atomic_target(path); on.exit(unlink(tmp), add = TRUE); data.table::fwrite(x, tmp, na = ""); if (file.exists(path)) unlink(path); fa_assert(file.rename(tmp, path), paste("Could not write", path)); invisible(path) }

fa_write_json <- function(x, path) { tmp <- fa_atomic_target(path); on.exit(unlink(tmp), add = TRUE); jsonlite::write_json(x, tmp, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = 16); if (file.exists(path)) unlink(path); fa_assert(file.rename(tmp, path), paste("Could not write", path)); invisible(path) }

fa_write_text <- function(x, path) { tmp <- fa_atomic_target(path); on.exit(unlink(tmp), add = TRUE); writeLines(x, tmp, useBytes = TRUE); if (file.exists(path)) unlink(path); fa_assert(file.rename(tmp, path), paste("Could not write", path)); invisible(path) }

fa_results_path <- function(context, ...) {
  relative <- file.path(context$config$output$results_dir, ...)
  vapply(relative, function(path) fa_path(context, path), character(1L), USE.NAMES = FALSE)
}

fa_log <- function(...) message("[", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "] ", paste(..., collapse = ""))
