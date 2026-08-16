v1_assert <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

v1_require_packages <- function(packages) {
  missing <- packages[!vapply(packages, requireNamespace, logical(1L), quietly = TRUE)]
  v1_assert(
    length(missing) == 0L,
    paste("Missing R packages. Run Rscript env/bootstrap.R:", paste(missing, collapse = ", "))
  )
  invisible(TRUE)
}

v1_context <- function(repo_root, project_dir) {
  packages <- c("yaml", "jsonlite", "digest", "data.table", "ranger", "dplyr", "tidyr")
  v1_require_packages(packages)
  config_path <- file.path(project_dir, "config", "default.yml")
  v1_assert(file.exists(config_path), paste("Missing V1 config:", config_path))
  list(
    repo_root = normalizePath(repo_root, winslash = "/", mustWork = TRUE),
    project_dir = normalizePath(project_dir, winslash = "/", mustWork = TRUE),
    config_path = normalizePath(config_path, winslash = "/", mustWork = TRUE),
    config = yaml::read_yaml(config_path)
  )
}

v1_runtime_info <- function() {
  packages <- c("yaml", "jsonlite", "digest", "data.table", "ranger", "dplyr", "tidyr")
  list(
    r_version = R.version.string,
    platform = R.version$platform,
    packages = stats::setNames(
      as.list(vapply(packages, function(x) as.character(utils::packageVersion(x)), character(1L))),
      packages
    ),
    slurm_job_id = Sys.getenv("SLURM_JOB_ID", unset = ""),
    slurm_array_task_id = Sys.getenv("SLURM_ARRAY_TASK_ID", unset = "")
  )
}

v1_path <- function(context, relative_path) {
  if (grepl("^[A-Za-z]:[/\\\\]|^/", relative_path)) return(relative_path)
  file.path(context$repo_root, relative_path)
}

v1_output_path <- function(context, key, ...) {
  v1_path(context, file.path(context$config$output[[key]], ...))
}

v1_read_predictors <- function(context) {
  path <- v1_path(context, context$config$input$predictors)
  v1_assert(file.exists(path), paste("Missing Full50 predictor manifest:", path))
  predictors <- trimws(readLines(path, warn = FALSE, encoding = "UTF-8"))
  predictors <- predictors[nzchar(predictors) & !startsWith(predictors, "#")]
  expected <- as.integer(context$config$validation$expected_predictors)
  v1_assert(length(predictors) == expected, paste("Expected", expected, "predictors; found", length(predictors)))
  v1_assert(!anyDuplicated(predictors), "Full50 predictor manifest contains duplicates.")
  predictors
}

v1_text_signature <- function(path) {
  v1_assert(file.exists(path), paste("Missing signature target:", path))
  info <- file.info(path)
  normalized <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  list(
    path = gsub("\\\\", "/", normalizePath(path, mustWork = TRUE)),
    bytes = unname(info$size),
    modified_at = format(info$mtime, "%Y-%m-%dT%H:%M:%S%z"),
    md5 = digest::digest(normalized, algo = "md5", serialize = FALSE),
    hash_method = "normalized_lf_text_md5"
  )
}

v1_data_signature <- function(context) {
  v1_text_signature(v1_path(context, context$config$input$table))
}

v1_config_signature <- function(context) {
  v1_text_signature(context$config_path)
}

v1_read_training_data <- function(context) {
  path <- v1_path(context, context$config$input$table)
  v1_assert(file.exists(path), paste("Training table is not ready:", path))
  as.data.frame(data.table::fread(
    path,
    na.strings = c("", "NA", "NaN"),
    integer64 = "character",
    data.table = FALSE
  ))
}

v1_atomic_target <- function(path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tempfile(pattern = "v1_", tmpdir = dirname(path))
}

v1_write_csv <- function(x, path) {
  temporary <- v1_atomic_target(path)
  on.exit(unlink(temporary), add = TRUE)
  data.table::fwrite(x, temporary, na = "")
  if (file.exists(path)) unlink(path)
  v1_assert(file.rename(temporary, path), paste("Could not write:", path))
  invisible(path)
}

v1_write_json <- function(x, path) {
  temporary <- v1_atomic_target(path)
  on.exit(unlink(temporary), add = TRUE)
  jsonlite::write_json(x, temporary, auto_unbox = TRUE, pretty = TRUE, null = "null")
  if (file.exists(path)) unlink(path)
  v1_assert(file.rename(temporary, path), paste("Could not write:", path))
  invisible(path)
}

v1_write_yaml <- function(x, path) {
  temporary <- v1_atomic_target(path)
  on.exit(unlink(temporary), add = TRUE)
  yaml::write_yaml(x, temporary)
  if (file.exists(path)) unlink(path)
  v1_assert(file.rename(temporary, path), paste("Could not write:", path))
  invisible(path)
}

v1_save_rds <- function(x, path) {
  temporary <- v1_atomic_target(path)
  on.exit(unlink(temporary), add = TRUE)
  saveRDS(x, temporary, version = 3L)
  if (file.exists(path)) unlink(path)
  v1_assert(file.rename(temporary, path), paste("Could not write:", path))
  invisible(path)
}

v1_log <- function(...) {
  line <- paste0("[", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "] ", paste(..., collapse = ""))
  message(line)
  path <- getOption("river_sr.v1.log_file", NULL)
  if (!is.null(path)) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    cat(line, "\n", file = path, append = TRUE)
  }
  invisible(line)
}

v1_make_run_id <- function() paste(format(Sys.time(), "%Y%m%d_%H%M%S"), "full", sep = "_")

v1_run_dir <- function(context, run_id, ...) {
  v1_output_path(context, "runs_dir", run_id, ...)
}

v1_begin_run <- function(context, run_id, arguments) {
  run_dir <- v1_run_dir(context, run_id)
  for (name in c("models", "reports", "logs", "deployment", "slurm")) {
    dir.create(file.path(run_dir, name), recursive = TRUE, showWarnings = FALSE)
  }
  options(river_sr.v1.log_file = file.path(run_dir, "logs", "run.log"))
  config_copy <- file.path(run_dir, "config_used.yml")
  if (!file.exists(config_copy)) v1_write_yaml(context$config, config_copy)
  info_path <- file.path(run_dir, "run_info.json")
  if (file.exists(info_path)) return(jsonlite::read_json(info_path, simplifyVector = FALSE))
  info <- list(
    run_id = run_id,
    status = "running",
    started_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    arguments = arguments,
    runtime = v1_runtime_info()
  )
  v1_write_json(info, info_path)
  info
}

v1_finish_run <- function(context, run_id, status, extra = list()) {
  path <- v1_run_dir(context, run_id, "run_info.json")
  info <- if (file.exists(path)) jsonlite::read_json(path, simplifyVector = FALSE) else list(run_id = run_id)
  info$status <- status
  info$finished_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  if (length(extra)) info[names(extra)] <- extra
  v1_write_json(info, path)
  invisible(info)
}

v1_primary_task_dir <- function(context, repeat_id, outer_fold) {
  v1_output_path(
    context, "validation_dir", "primary",
    sprintf("repeat_%02d", as.integer(repeat_id)), sprintf("fold_%02d", as.integer(outer_fold))
  )
}

v1_stress_task_dir <- function(context, scheme, outer_fold) {
  v1_output_path(context, "validation_dir", "stress", scheme, sprintf("fold_%02d", as.integer(outer_fold)))
}

v1_task_complete <- function(path, kind = c("primary", "stress")) {
  kind <- match.arg(kind)
  required <- if (kind == "primary") {
    c("selected_params.yml", "outer_predictions.csv", "outer_metrics.csv", "task_info.json",
      "coarse_summary.csv", "refinement_summary.csv")
  } else {
    c("outer_predictions.csv", "outer_metrics.csv", "task_info.json")
  }
  all(file.exists(file.path(path, required)))
}

v1_parse_cli <- function(args) {
  result <- list(
    mode = "full", stage = NULL, task_type = NULL, repeat_id = NULL, scheme = NULL,
    outer_fold = NULL, run_id = NULL, release = NULL, force = FALSE
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
      v1_assert(startsWith(token, "--") && i < length(args), paste("Invalid argument:", token))
      key <- gsub("-", "_", substring(token, 3L))
      value <- args[[i + 1L]]
      i <- i + 1L
    }
    v1_assert(key %in% names(result), paste("Unknown argument:", token))
    result[[key]] <- value
    i <- i + 1L
  }
  for (key in c("repeat_id", "outer_fold")) {
    if (!is.null(result[[key]])) result[[key]] <- suppressWarnings(as.integer(result[[key]]))
  }
  result
}
