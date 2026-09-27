risk_assert <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

risk_require_packages <- function(packages) {
  missing <- packages[!vapply(packages, requireNamespace, logical(1L), quietly = TRUE)]
  risk_assert(
    length(missing) == 0L,
    paste("Missing R packages. Run Rscript env/bootstrap.R:", paste(missing, collapse = ", "))
  )
  invisible(TRUE)
}

risk_packages <- function() {
  c("yaml", "jsonlite", "digest", "data.table", "glmnet", "ranger", "PRROC", "pROC")
}

risk_context <- function(repo_root, project_dir) {
  risk_require_packages(risk_packages())
  config_path <- file.path(project_dir, "config", "default.yml")
  risk_assert(file.exists(config_path), paste("Missing Risk V1 config:", config_path))
  list(
    repo_root = normalizePath(repo_root, winslash = "/", mustWork = TRUE),
    project_dir = normalizePath(project_dir, winslash = "/", mustWork = TRUE),
    config_path = normalizePath(config_path, winslash = "/", mustWork = TRUE),
    config = yaml::read_yaml(config_path)
  )
}

risk_path <- function(context, relative_path) {
  if (grepl("^[A-Za-z]:[/\\\\]|^/", relative_path)) return(relative_path)
  file.path(context$repo_root, relative_path)
}

risk_output_path <- function(context, key, ...) {
  risk_path(context, file.path(context$config$output[[key]], ...))
}

risk_read_lines <- function(path) {
  risk_assert(file.exists(path), paste("Missing text manifest:", path))
  values <- trimws(readLines(path, warn = FALSE, encoding = "UTF-8"))
  values[nzchar(values) & !startsWith(values, "#")]
}

risk_read_predictors <- function(context) {
  predictors <- risk_read_lines(risk_path(context, context$config$input$predictors))
  expected <- as.integer(context$config$validation$expected_predictors)
  risk_assert(length(predictors) == expected, paste("Expected", expected, "NonSpatial predictors; found", length(predictors)))
  risk_assert(!anyDuplicated(predictors), "NonSpatial47 predictor manifest contains duplicates.")
  predictors
}

risk_text_signature <- function(path) {
  risk_assert(file.exists(path), paste("Missing signature target:", path))
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

risk_config_signature <- function(context) risk_text_signature(context$config_path)
risk_data_signature <- function(context) risk_text_signature(risk_path(context, context$config$input$table))

risk_read_training_data <- function(context) {
  path <- risk_path(context, context$config$input$table)
  risk_assert(file.exists(path), paste("Frozen Base V1 training table is missing:", path))
  as.data.frame(data.table::fread(
    path, na.strings = c("", "NA", "NaN"), integer64 = "character", data.table = FALSE
  ))
}

risk_atomic_target <- function(path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tempfile(pattern = "risk_v1_", tmpdir = dirname(path))
}

risk_write_csv <- function(x, path) {
  temporary <- risk_atomic_target(path)
  on.exit(unlink(temporary), add = TRUE)
  data.table::fwrite(x, temporary, na = "")
  if (file.exists(path)) unlink(path)
  risk_assert(file.rename(temporary, path), paste("Could not write:", path))
  invisible(path)
}

risk_write_json <- function(x, path) {
  temporary <- risk_atomic_target(path)
  on.exit(unlink(temporary), add = TRUE)
  jsonlite::write_json(x, temporary, auto_unbox = TRUE, pretty = TRUE, null = "null")
  if (file.exists(path)) unlink(path)
  risk_assert(file.rename(temporary, path), paste("Could not write:", path))
  invisible(path)
}

risk_write_yaml <- function(x, path) {
  temporary <- risk_atomic_target(path)
  on.exit(unlink(temporary), add = TRUE)
  yaml::write_yaml(x, temporary)
  if (file.exists(path)) unlink(path)
  risk_assert(file.rename(temporary, path), paste("Could not write:", path))
  invisible(path)
}

risk_write_text <- function(lines, path) {
  temporary <- risk_atomic_target(path)
  on.exit(unlink(temporary), add = TRUE)
  writeLines(lines, temporary, useBytes = TRUE)
  if (file.exists(path)) unlink(path)
  risk_assert(file.rename(temporary, path), paste("Could not write:", path))
  invisible(path)
}

risk_log <- function(...) {
  line <- paste0("[", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "] ", paste(..., collapse = ""))
  message(line)
  path <- getOption("river_sr.risk_v1.log_file", NULL)
  if (!is.null(path)) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    cat(line, "\n", sep = "", file = path, append = TRUE)
  }
  invisible(line)
}

risk_runtime_info <- function() {
  packages <- risk_packages()
  list(
    r_version = R.version.string,
    platform = R.version$platform,
    packages = stats::setNames(
      as.list(vapply(packages, function(x) as.character(utils::packageVersion(x)), character(1L))), packages
    ),
    slurm_job_id = Sys.getenv("SLURM_JOB_ID", unset = ""),
    slurm_array_task_id = Sys.getenv("SLURM_ARRAY_TASK_ID", unset = "")
  )
}

risk_task_dir <- function(context, model, repeat_id, outer_fold) {
  risk_output_path(
    context, "validation_dir", model,
    sprintf("repeat_%02d", as.integer(repeat_id)), sprintf("fold_%02d", as.integer(outer_fold))
  )
}

risk_task_complete <- function(path) {
  required <- c(
    "candidate_summary.csv", "selected_params.yml", "inner_winner_oof.csv",
    "outer_predictions.csv", "outer_metrics.csv", "outer_training_medians.csv", "task_info.json"
  )
  all(file.exists(file.path(path, required)))
}

risk_make_run_id <- function() paste(format(Sys.time(), "%Y%m%d_%H%M%S"), "risk_v1", sep = "_")

risk_run_dir <- function(context, run_id, ...) {
  risk_output_path(context, "runs_dir", run_id, ...)
}

risk_begin_run <- function(context, run_id, arguments) {
  risk_assert(grepl("^[A-Za-z0-9._-]+$", run_id), "run_id contains unsupported characters.")
  run_dir <- risk_run_dir(context, run_id)
  for (name in c("reports", "logs", "slurm")) dir.create(file.path(run_dir, name), recursive = TRUE, showWarnings = FALSE)
  options(river_sr.risk_v1.log_file = file.path(run_dir, "logs", "run.log"))
  config_copy <- file.path(run_dir, "config_used.yml")
  if (!file.exists(config_copy)) risk_write_yaml(context$config, config_copy)
  info_path <- file.path(run_dir, "run_info.json")
  if (file.exists(info_path)) return(jsonlite::read_json(info_path, simplifyVector = FALSE))
  info <- list(
    run_id = run_id, status = "aggregating", started_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    arguments = arguments, runtime = risk_runtime_info()
  )
  risk_write_json(info, info_path)
  info
}

risk_finish_run <- function(context, run_id, status, extra = list()) {
  path <- risk_run_dir(context, run_id, "run_info.json")
  info <- if (file.exists(path)) jsonlite::read_json(path, simplifyVector = FALSE) else list(run_id = run_id)
  info$status <- status
  info$finished_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  if (length(extra)) info[names(extra)] <- extra
  risk_write_json(info, path)
  invisible(info)
}

risk_parse_cli <- function(args) {
  result <- list(stage = NULL, task_id = NULL, run_id = NULL, force = FALSE)
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
      risk_assert(startsWith(token, "--") && i < length(args), paste("Invalid argument:", token))
      key <- gsub("-", "_", substring(token, 3L))
      value <- args[[i + 1L]]
      i <- i + 1L
    }
    risk_assert(key %in% names(result), paste("Unknown argument:", token))
    result[[key]] <- value
    i <- i + 1L
  }
  if (!is.null(result$task_id)) result$task_id <- suppressWarnings(as.integer(result$task_id))
  result
}
