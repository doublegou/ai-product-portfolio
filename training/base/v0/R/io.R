v0_assert <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

v0_require_packages <- function(packages) {
  missing <- packages[!vapply(packages, requireNamespace, logical(1L), quietly = TRUE)]
  v0_assert(
    length(missing) == 0L,
    paste("Missing R packages. Run Rscript env/bootstrap.R:", paste(missing, collapse = ", "))
  )
  invisible(TRUE)
}

v0_context <- function(repo_root, project_dir) {
  v0_require_packages(c("yaml", "jsonlite", "digest", "data.table", "ranger"))
  config_path <- file.path(project_dir, "config", "default.yml")
  v0_assert(file.exists(config_path), paste("Missing V0 config:", config_path))
  list(
    repo_root = normalizePath(repo_root, winslash = "/", mustWork = TRUE),
    project_dir = normalizePath(project_dir, winslash = "/", mustWork = TRUE),
    config_path = normalizePath(config_path, winslash = "/", mustWork = TRUE),
    config = yaml::read_yaml(config_path)
  )
}

v0_path <- function(context, relative_path) {
  if (grepl("^[A-Za-z]:[/\\\\]|^/", relative_path)) return(relative_path)
  file.path(context$repo_root, relative_path)
}

v0_output_path <- function(context, key, ...) {
  v0_path(context, file.path(context$config$output[[key]], ...))
}

v0_read_predictors <- function(context) {
  path <- v0_path(context, context$config$input$predictors)
  v0_assert(file.exists(path), paste("Missing Full50 predictor manifest:", path))
  predictors <- trimws(readLines(path, warn = FALSE, encoding = "UTF-8"))
  predictors <- predictors[nzchar(predictors) & !startsWith(predictors, "#")]
  v0_assert(length(predictors) == 50L, paste("Full50 must contain 50 predictors; found", length(predictors)))
  v0_assert(!anyDuplicated(predictors), "Full50 predictor manifest contains duplicates.")
  predictors
}

v0_data_signature <- function(context) {
  path <- v0_path(context, context$config$input$table)
  v0_assert(file.exists(path), paste("Training table is not ready:", path))
  info <- file.info(path)
  list(
    path = gsub("\\\\", "/", normalizePath(path, mustWork = TRUE)),
    bytes = unname(info$size),
    modified_at = format(info$mtime, "%Y-%m-%dT%H:%M:%S%z"),
    md5 = unname(tools::md5sum(path))
  )
}

v0_read_training_data <- function(context) {
  path <- v0_path(context, context$config$input$table)
  v0_assert(file.exists(path), paste("Training table is not ready:", path))
  as.data.frame(data.table::fread(path, na.strings = c("", "NA", "NaN"), data.table = FALSE))
}

v0_atomic_target <- function(path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tempfile(pattern = "v0_", tmpdir = dirname(path))
}

v0_write_csv <- function(x, path) {
  temporary <- v0_atomic_target(path)
  on.exit(unlink(temporary), add = TRUE)
  data.table::fwrite(x, temporary, na = "")
  if (file.exists(path)) unlink(path)
  v0_assert(file.rename(temporary, path), paste("Could not write:", path))
  invisible(path)
}

v0_write_json <- function(x, path) {
  temporary <- v0_atomic_target(path)
  on.exit(unlink(temporary), add = TRUE)
  jsonlite::write_json(x, temporary, auto_unbox = TRUE, pretty = TRUE, null = "null")
  if (file.exists(path)) unlink(path)
  v0_assert(file.rename(temporary, path), paste("Could not write:", path))
  invisible(path)
}

v0_write_yaml <- function(x, path) {
  temporary <- v0_atomic_target(path)
  on.exit(unlink(temporary), add = TRUE)
  yaml::write_yaml(x, temporary)
  if (file.exists(path)) unlink(path)
  v0_assert(file.rename(temporary, path), paste("Could not write:", path))
  invisible(path)
}

v0_save_rds <- function(x, path) {
  temporary <- v0_atomic_target(path)
  on.exit(unlink(temporary), add = TRUE)
  saveRDS(x, temporary, version = 3L)
  if (file.exists(path)) unlink(path)
  v0_assert(file.rename(temporary, path), paste("Could not write:", path))
  invisible(path)
}

v0_log <- function(...) {
  line <- paste0("[", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "] ", paste(..., collapse = ""))
  message(line)
  log_file <- getOption("river_sr.v0.log_file", NULL)
  if (!is.null(log_file)) {
    dir.create(dirname(log_file), recursive = TRUE, showWarnings = FALSE)
    cat(line, "\n", file = log_file, append = TRUE)
  }
  invisible(line)
}

v0_make_run_id <- function(mode) {
  paste(format(Sys.time(), "%Y%m%d_%H%M%S"), mode, sep = "_")
}

v0_run_dir <- function(context, run_id, ...) {
  v0_output_path(context, "runs_dir", run_id, ...)
}

v0_begin_run <- function(context, run_id, mode, arguments) {
  run_dir <- v0_run_dir(context, run_id)
  dir.create(file.path(run_dir, "models"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(run_dir, "reports"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(run_dir, "logs"), recursive = TRUE, showWarnings = FALSE)
  if (identical(mode, "smoke")) dir.create(file.path(run_dir, "smoke"), recursive = TRUE, showWarnings = FALSE)
  options(river_sr.v0.log_file = file.path(run_dir, "logs", "run.log"))
  v0_write_yaml(context$config, file.path(run_dir, "config_used.yml"))
  info <- list(
    run_id = run_id,
    mode = mode,
    status = "running",
    started_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    arguments = arguments
  )
  v0_write_json(info, file.path(run_dir, "run_info.json"))
  info
}

v0_finish_run <- function(context, run_id, info, status, extra = list()) {
  info$status <- status
  info$finished_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  if (length(extra)) info[names(extra)] <- extra
  v0_write_json(info, v0_run_dir(context, run_id, "run_info.json"))
  invisible(info)
}

v0_parse_cli <- function(args) {
  result <- list(
    mode = "full", stage = NULL, scheme = NULL, outer_fold = NULL,
    run_id = NULL, release = NULL, force = FALSE
  )
  i <- 1L
  while (i <= length(args)) {
    token <- args[[i]]
    if (token == "--force") {
      result$force <- TRUE
      i <- i + 1L
      next
    }
    matched <- regexec("^--([a-z-]+)=(.*)$", token)
    parts <- regmatches(token, matched)[[1L]]
    if (length(parts) == 3L) {
      key <- gsub("-", "_", parts[[2L]])
      value <- parts[[3L]]
    } else {
      v0_assert(startsWith(token, "--"), paste("Unknown argument:", token))
      v0_assert(i < length(args), paste("Missing value for", token))
      key <- gsub("-", "_", substring(token, 3L))
      value <- args[[i + 1L]]
      i <- i + 1L
    }
    v0_assert(key %in% names(result), paste("Unknown argument:", token))
    result[[key]] <- value
    i <- i + 1L
  }
  if (!is.null(result$outer_fold)) result$outer_fold <- suppressWarnings(as.integer(result$outer_fold))
  result
}

v0_task_dir <- function(context, scheme, outer_fold) {
  v0_output_path(context, "validation_dir", scheme, sprintf("fold_%02d", as.integer(outer_fold)))
}

v0_task_complete <- function(path) {
  all(file.exists(file.path(path, c(
    "selected_params.yml", "outer_predictions.csv", "outer_metrics.csv", "task_info.json"
  ))))
}
