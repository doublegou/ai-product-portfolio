regional_data_assert <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

regional_data_require <- function(packages) {
  missing <- packages[!vapply(packages, requireNamespace, logical(1L), quietly = TRUE)]
  regional_data_assert(
    length(missing) == 0L,
    paste("Missing R packages. Run Rscript env/bootstrap.R:", paste(missing, collapse = ", "))
  )
}

regional_data_path <- function(context, relative_path) {
  if (grepl("^[A-Za-z]:[/\\\\]|^/", relative_path)) return(relative_path)
  file.path(context$repo_root, relative_path)
}

regional_data_signature <- function(path, relative_to = NULL) {
  regional_data_assert(file.exists(path), paste("Missing signature target:", path))
  info <- file.info(path)
  text_file <- tolower(tools::file_ext(path)) %in% c("csv", "json", "md", "txt", "yml", "yaml")
  md5 <- if (text_file) {
    normalized <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    digest::digest(normalized, algo = "md5", serialize = FALSE)
  } else {
    digest::digest(path, algo = "md5", serialize = FALSE, file = TRUE)
  }
  normalized_path <- gsub("\\\\", "/", normalizePath(path, mustWork = TRUE))
  if (!is.null(relative_to)) {
    normalized_root <- gsub("\\\\", "/", normalizePath(relative_to, mustWork = TRUE))
    root_prefix <- paste0(normalized_root, "/")
    if (startsWith(tolower(normalized_path), tolower(root_prefix))) {
      normalized_path <- substring(normalized_path, nchar(root_prefix) + 1L)
    }
  }
  list(
    path = normalized_path,
    bytes = unname(info$size),
    modified_at = format(info$mtime, "%Y-%m-%dT%H:%M:%S%z"),
    md5 = md5,
    sha256 = digest::digest(path, algo = "sha256", serialize = FALSE, file = TRUE),
    hash_method = if (text_file) "normalized_lf_text_md5" else "raw_bytes"
  )
}

regional_data_read_csv <- function(path) {
  regional_data_assert(file.exists(path), paste("Missing CSV:", path))
  as.data.frame(data.table::fread(
    path, na.strings = c("", "NA", "NaN"), integer64 = "character", data.table = FALSE
  ))
}

regional_data_write_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(pattern = "himalaya_risk_v1_", tmpdir = dirname(path))
  on.exit(unlink(temporary), add = TRUE)
  data.table::fwrite(x, temporary, na = "")
  if (file.exists(path)) unlink(path)
  regional_data_assert(file.rename(temporary, path), paste("Could not write:", path))
  invisible(path)
}

regional_data_log <- function(...) {
  message("[", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "] ", paste(..., collapse = ""))
}
