rrisk11_assert <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

rrisk11_packages <- function() c("yaml", "jsonlite", "digest", "data.table", "mgcv", "PRROC", "pROC")

rrisk11_require_packages <- function(packages = rrisk11_packages()) {
  missing <- packages[!vapply(packages, requireNamespace, logical(1L), quietly = TRUE)]
  rrisk11_assert(length(missing) == 0L, paste("Missing R packages. Run Rscript env/bootstrap.R:", paste(missing, collapse = ", ")))
}

rrisk11_context <- function(repo_root, project_dir) {
  rrisk11_require_packages()
  config_path <- file.path(project_dir, "config", "default.yml")
  rrisk11_assert(file.exists(config_path), paste("Missing Regional Risk V1.1 config:", config_path))
  context <- list(
    repo_root = normalizePath(repo_root, winslash = "/", mustWork = TRUE),
    project_dir = normalizePath(project_dir, winslash = "/", mustWork = TRUE),
    config_path = normalizePath(config_path, winslash = "/", mustWork = TRUE),
    config = yaml::read_yaml(config_path)
  )
  configured_paths <- unlist(c(context$config$input[names(context$config$input) != "expected_md5"], context$config$output), use.names = FALSE)
  rrisk11_assert(!any(grepl("regional_risk_v2", configured_paths, fixed = TRUE)), "Regional Risk V1.1 must not read or write Regional Risk V2 paths.")
  context
}

rrisk11_path <- function(context, relative_path) {
  if (grepl("^[A-Za-z]:[/\\\\]|^/", relative_path)) return(relative_path)
  file.path(context$repo_root, relative_path)
}

rrisk11_output_path <- function(context, key, ...) rrisk11_path(context, file.path(context$config$output[[key]], ...))

rrisk11_read_lines <- function(path) {
  rrisk11_assert(file.exists(path), paste("Missing text manifest:", path))
  values <- trimws(readLines(path, warn = FALSE, encoding = "UTF-8"))
  values[nzchar(values) & !startsWith(values, "#")]
}

rrisk11_read_csv <- function(path) {
  rrisk11_assert(file.exists(path), paste("Missing CSV:", path))
  as.data.frame(data.table::fread(path, na.strings = c("", "NA", "NaN"), integer64 = "character", data.table = FALSE))
}

rrisk11_text_signature <- function(path) {
  rrisk11_assert(file.exists(path), paste("Missing signature target:", path))
  info <- file.info(path)
  normalized <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  list(
    path = gsub("\\\\", "/", normalizePath(path, mustWork = TRUE)),
    bytes = unname(info$size), modified_at = format(info$mtime, "%Y-%m-%dT%H:%M:%S%z"),
    md5 = digest::digest(normalized, algo = "md5", serialize = FALSE), hash_method = "normalized_lf_text_md5"
  )
}

rrisk11_implementation_signature <- function(context) {
  paths <- sort(c(Sys.glob(file.path(context$project_dir, "R", "*.R")), Sys.glob(file.path(context$project_dir, "scripts", "*.R"))))
  rrisk11_assert(length(paths) > 0L, "Regional Risk V1.1 implementation files are absent.")
  files <- lapply(paths, function(path) {
    signature <- rrisk11_text_signature(path)
    signature$path <- substring(gsub("\\\\", "/", normalizePath(path, mustWork = TRUE)), nchar(context$project_dir) + 2L)
    signature
  })
  payload <- paste(vapply(files, function(x) paste(x$path, x$md5, sep = "="), character(1L)), collapse = "\n")
  list(sha256 = digest::digest(payload, algo = "sha256", serialize = FALSE), files = files)
}

rrisk11_atomic_target <- function(path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tempfile(pattern = "regional_risk_v1_1_", tmpdir = dirname(path))
}

rrisk11_write_csv <- function(x, path) {
  temporary <- rrisk11_atomic_target(path); on.exit(unlink(temporary), add = TRUE)
  data.table::fwrite(x, temporary, na = "")
  if (file.exists(path)) unlink(path)
  rrisk11_assert(file.rename(temporary, path), paste("Could not write:", path)); invisible(path)
}

rrisk11_write_json <- function(x, path) {
  temporary <- rrisk11_atomic_target(path); on.exit(unlink(temporary), add = TRUE)
  jsonlite::write_json(x, temporary, auto_unbox = TRUE, pretty = TRUE, null = "null", digits = 16)
  if (file.exists(path)) unlink(path)
  rrisk11_assert(file.rename(temporary, path), paste("Could not write:", path)); invisible(path)
}

rrisk11_write_yaml <- function(x, path) {
  temporary <- rrisk11_atomic_target(path); on.exit(unlink(temporary), add = TRUE)
  yaml::write_yaml(x, temporary)
  if (file.exists(path)) unlink(path)
  rrisk11_assert(file.rename(temporary, path), paste("Could not write:", path)); invisible(path)
}

rrisk11_write_text <- function(lines, path) {
  temporary <- rrisk11_atomic_target(path); on.exit(unlink(temporary), add = TRUE)
  writeLines(lines, temporary, useBytes = TRUE)
  if (file.exists(path)) unlink(path)
  rrisk11_assert(file.rename(temporary, path), paste("Could not write:", path)); invisible(path)
}

rrisk11_log <- function(...) {
  line <- paste0("[", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "] ", paste(..., collapse = ""))
  message(line)
  path <- getOption("river_sr.regional_risk_v1_1.log_file", NULL)
  if (!is.null(path)) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    cat(line, "\n", sep = "", file = path, append = TRUE)
  }
  invisible(line)
}

rrisk11_fold_paths <- function(context) {
  root <- rrisk11_output_path(context, "folds_dir")
  stats::setNames(
    file.path(root, c("branch_map.csv", "outer_assignments.csv", "task_manifest.csv", "fold_manifest.json")),
    c("branches", "outer", "tasks", "manifest")
  )
}

rrisk11_task_dir <- function(context, model_id, outer_fold) {
  rrisk11_output_path(context, "validation_dir", model_id, sprintf("fold_%02d", as.integer(outer_fold)))
}

rrisk11_task_complete <- function(path) {
  required <- c(
    "inner_oof.csv", "outer_predictions.csv", "calibrator.csv", "thresholds.csv", "threshold_curve.csv",
    "gam_diagnostics.csv", "outer_training_medians.csv", "task_info.json"
  )
  all(file.exists(file.path(path, required)))
}

rrisk11_runtime_info <- function() {
  packages <- rrisk11_packages()
  list(
    r_version = R.version.string, platform = R.version$platform,
    packages = stats::setNames(as.list(vapply(packages, function(x) as.character(utils::packageVersion(x)), character(1L))), packages),
    slurm_job_id = Sys.getenv("SLURM_JOB_ID", unset = ""),
    slurm_array_task_id = Sys.getenv("SLURM_ARRAY_TASK_ID", unset = "")
  )
}

rrisk11_run_dir <- function(context, run_id, ...) rrisk11_output_path(context, "runs_dir", run_id, ...)

rrisk11_begin_run <- function(context, run_id, arguments) {
  rrisk11_assert(grepl("^[A-Za-z0-9._-]+$", run_id), "run_id contains unsupported characters.")
  run_dir <- rrisk11_run_dir(context, run_id)
  for (name in c("reports", "logs", "slurm")) dir.create(file.path(run_dir, name), recursive = TRUE, showWarnings = FALSE)
  options(river_sr.regional_risk_v1_1.log_file = file.path(run_dir, "logs", "run.log"))
  if (!file.exists(file.path(run_dir, "config_used.yml"))) rrisk11_write_yaml(context$config, file.path(run_dir, "config_used.yml"))
  path <- file.path(run_dir, "run_info.json")
  if (file.exists(path)) return(jsonlite::read_json(path, simplifyVector = FALSE))
  info <- list(
    run_id = run_id, status = "aggregating", started_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    arguments = arguments, runtime = rrisk11_runtime_info()
  )
  rrisk11_write_json(info, path); info
}

rrisk11_finish_run <- function(context, run_id, status, extra = list()) {
  path <- rrisk11_run_dir(context, run_id, "run_info.json")
  info <- if (file.exists(path)) jsonlite::read_json(path, simplifyVector = FALSE) else list(run_id = run_id)
  info$status <- status; info$finished_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  if (length(extra)) info[names(extra)] <- extra
  rrisk11_write_json(info, path); invisible(info)
}

rrisk11_parse_cli <- function(args) {
  result <- list(stage = NULL, task_id = NULL, run_id = NULL, force = FALSE)
  i <- 1L
  while (i <= length(args)) {
    token <- args[[i]]
    if (token == "--force") { result$force <- TRUE; i <- i + 1L; next }
    matched <- regexec("^--([a-z-]+)=(.*)$", token); parts <- regmatches(token, matched)[[1L]]
    if (length(parts) == 3L) {
      key <- gsub("-", "_", parts[[2L]]); value <- parts[[3L]]
    } else {
      rrisk11_assert(startsWith(token, "--") && i < length(args), paste("Invalid argument:", token))
      key <- gsub("-", "_", substring(token, 3L)); value <- args[[i + 1L]]; i <- i + 1L
    }
    rrisk11_assert(key %in% names(result), paste("Unknown argument:", token))
    result[[key]] <- value; i <- i + 1L
  }
  if (!is.null(result$task_id)) result$task_id <- suppressWarnings(as.integer(result$task_id))
  result
}
