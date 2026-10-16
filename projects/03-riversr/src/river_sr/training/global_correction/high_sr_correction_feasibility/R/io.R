corr_assert <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

corr_require_packages <- function(packages) {
  missing <- packages[!vapply(packages, requireNamespace, logical(1L), quietly = TRUE)]
  corr_assert(length(missing) == 0L, paste("Missing R packages; run env/bootstrap.R:", paste(missing, collapse = ", ")))
  invisible(TRUE)
}

corr_context <- function(repo_root, project_dir) {
  packages <- c("yaml", "jsonlite", "digest", "data.table", "ranger", "glmnet")
  corr_require_packages(packages)
  config_path <- file.path(project_dir, "config", "default.yml")
  corr_assert(file.exists(config_path), paste("Missing correction config:", config_path))
  list(
    repo_root = normalizePath(repo_root, winslash = "/", mustWork = TRUE),
    project_dir = normalizePath(project_dir, winslash = "/", mustWork = TRUE),
    config_path = normalizePath(config_path, winslash = "/", mustWork = TRUE),
    config = yaml::read_yaml(config_path)
  )
}

corr_path <- function(context, relative_path) {
  if (grepl("^[A-Za-z]:[/\\\\]|^/", relative_path)) return(relative_path)
  file.path(context$repo_root, relative_path)
}

corr_output_path <- function(context, key, ...) corr_path(context, file.path(context$config$output[[key]], ...))

corr_assert_not_reference_path <- function(context, path) {
  resolved <- gsub("\\\\", "/", normalizePath(corr_path(context, path), winslash = "/", mustWork = TRUE))
  repo <- gsub("\\\\", "/", context$repo_root)
  prefix <- paste0(tolower(repo), "/")
  relative <- if (startsWith(tolower(resolved), prefix)) substring(resolved, nchar(repo) + 2L) else resolved
  corr_assert(!grepl("(^|/)reference(/|$)", relative), paste("Formal runtime input may not resolve under reference/:", relative))
  invisible(resolved)
}

corr_read_lines <- function(path) {
  values <- trimws(readLines(path, warn = FALSE, encoding = "UTF-8"))
  values[nzchar(values) & !startsWith(values, "#")]
}

corr_read_predictors <- function(context, key) {
  path <- corr_path(context, context$config$input[[key]])
  corr_assert_not_reference_path(context, path)
  values <- corr_read_lines(path)
  corr_assert(!anyDuplicated(values), paste(key, "contains duplicate predictors."))
  values
}

corr_read_table <- function(path) {
  as.data.frame(data.table::fread(path, na.strings = c("", "NA", "NaN"), integer64 = "character", data.table = FALSE))
}

corr_read_training_data <- function(context) {
  path <- corr_path(context, context$config$input$table)
  corr_assert_not_reference_path(context, path)
  corr_read_table(path)
}

corr_text_signature <- function(path) {
  corr_assert(file.exists(path), paste("Missing signature target:", path))
  info <- file.info(path)
  normalized <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  list(
    path = gsub("\\\\", "/", normalizePath(path, winslash = "/", mustWork = TRUE)),
    bytes = unname(info$size),
    md5 = digest::digest(normalized, algo = "md5", serialize = FALSE),
    hash_method = "normalized_lf_text_md5"
  )
}

corr_implementation_signature <- function(context) {
  files <- sort(c(list.files(file.path(context$project_dir, "R"), pattern = "[.]R$", full.names = TRUE),
                  list.files(file.path(context$project_dir, "scripts"), pattern = "[.]R$", full.names = TRUE)))
  corr_assert(length(files) > 0L, "No correction implementation files were found.")
  payload <- paste(vapply(files, function(path) paste0(
    gsub("\\\\", "/", substring(normalizePath(path, winslash = "/", mustWork = TRUE), nchar(context$project_dir) + 2L)),
    "\n", paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  ), character(1L)), collapse = "\n---FILE---\n")
  list(file_count = length(files), md5 = digest::digest(payload, algo = "md5", serialize = FALSE),
       hash_method = "ordered_relative_path_and_normalized_lf_content_md5")
}

corr_ids_md5 <- function(ids) digest::digest(paste(sort(as.character(ids)), collapse = "\n"), algo = "md5", serialize = FALSE)

corr_atomic_target <- function(path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tempfile(pattern = "corr_", tmpdir = dirname(path))
}

corr_write_csv <- function(x, path) {
  temporary <- corr_atomic_target(path)
  on.exit(unlink(temporary), add = TRUE)
  data.table::fwrite(x, temporary, na = "")
  if (file.exists(path)) unlink(path)
  corr_assert(file.rename(temporary, path), paste("Could not write:", path))
  invisible(path)
}

corr_write_json <- function(x, path) {
  temporary <- corr_atomic_target(path)
  on.exit(unlink(temporary), add = TRUE)
  jsonlite::write_json(x, temporary, auto_unbox = TRUE, pretty = TRUE, null = "null")
  if (file.exists(path)) unlink(path)
  corr_assert(file.rename(temporary, path), paste("Could not write:", path))
  invisible(path)
}

corr_write_yaml <- function(x, path) {
  temporary <- corr_atomic_target(path)
  on.exit(unlink(temporary), add = TRUE)
  yaml::write_yaml(x, temporary)
  if (file.exists(path)) unlink(path)
  corr_assert(file.rename(temporary, path), paste("Could not write:", path))
  invisible(path)
}

corr_write_text <- function(x, path) {
  temporary <- corr_atomic_target(path)
  on.exit(unlink(temporary), add = TRUE)
  writeLines(x, temporary, useBytes = TRUE)
  if (file.exists(path)) unlink(path)
  corr_assert(file.rename(temporary, path), paste("Could not write:", path))
  invisible(path)
}

corr_runtime_info <- function() {
  packages <- c("yaml", "jsonlite", "digest", "data.table", "ranger", "glmnet")
  list(
    r_version = R.version.string,
    platform = R.version$platform,
    packages = stats::setNames(as.list(vapply(packages, function(x) as.character(utils::packageVersion(x)), character(1L))), packages),
    slurm_job_id = Sys.getenv("SLURM_JOB_ID", unset = ""),
    slurm_array_task_id = Sys.getenv("SLURM_ARRAY_TASK_ID", unset = "")
  )
}

corr_log <- function(...) {
  line <- paste0("[", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "] ", paste(..., collapse = ""))
  message(line)
  path <- getOption("river_sr.correction.log_file", NULL)
  if (!is.null(path)) {
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    cat(line, "\n", sep = "", file = path, append = TRUE)
  }
  invisible(line)
}

corr_fold_paths <- function(context) c(
  manifest = corr_output_path(context, "folds_dir", "fold_manifest.json"),
  base_tasks = corr_output_path(context, "folds_dir", "base_task_manifest.csv"),
  correction_tasks = corr_output_path(context, "folds_dir", "correction_task_manifest.csv"),
  base_fit_plan = corr_output_path(context, "folds_dir", "base_fit_plan.csv")
)

corr_base_task_dir <- function(context, repeat_id, outer_fold) {
  corr_output_path(context, "validation_dir", "base", sprintf("repeat_%02d", repeat_id), sprintf("fold_%02d", outer_fold))
}

corr_model_task_dir <- function(context, model, repeat_id, outer_fold) {
  corr_output_path(context, "validation_dir", model, sprintf("repeat_%02d", repeat_id), sprintf("fold_%02d", outer_fold))
}

corr_run_dir <- function(context, run_id, ...) corr_output_path(context, "runs_dir", run_id, ...)

corr_base_task_complete <- function(path) {
  required <- c("base_fit_manifest.csv", "outer_train_base_oof.csv", "outer_test_base_predictions.csv",
                "nested_pair_base_predictions.csv", "correction_inner_meta_features.csv", "training_medians.csv", "task_info.json")
  all(file.exists(file.path(path, required)))
}

corr_model_task_complete <- function(path) {
  required <- c("candidate_summary.csv", "selected_params.csv", "inner_winner_oof.csv",
                "outer_predictions.csv", "outer_metrics.csv", "outer_preprocessing.csv", "task_info.json")
  all(file.exists(file.path(path, required)))
}

corr_begin_run <- function(context, run_id, arguments) {
  run_dir <- corr_run_dir(context, run_id)
  for (name in c("reports", "logs")) dir.create(file.path(run_dir, name), recursive = TRUE, showWarnings = FALSE)
  options(river_sr.correction.log_file = file.path(run_dir, "logs", "run.log"))
  config_copy <- file.path(run_dir, "config_used.yml")
  if (!file.exists(config_copy)) corr_write_yaml(context$config, config_copy)
  path <- file.path(run_dir, "run_info.json")
  if (file.exists(path)) return(jsonlite::read_json(path, simplifyVector = FALSE))
  info <- list(run_id = run_id, status = "running", started_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
               arguments = arguments, runtime = corr_runtime_info())
  corr_write_json(info, path)
  info
}

corr_finish_run <- function(context, run_id, status, extra = list()) {
  path <- corr_run_dir(context, run_id, "run_info.json")
  info <- if (file.exists(path)) jsonlite::read_json(path, simplifyVector = FALSE) else list(run_id = run_id)
  info$status <- status
  info$finished_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  if (length(extra)) info[names(extra)] <- extra
  corr_write_json(info, path)
  invisible(info)
}

corr_parse_cli <- function(args) {
  result <- list(stage = NULL, base_task_id = NULL, correction_task_id = NULL, run_id = NULL, force = FALSE)
  i <- 1L
  while (i <= length(args)) {
    token <- args[[i]]
    if (token == "--force") { result$force <- TRUE; i <- i + 1L; next }
    matched <- regexec("^--([a-z-]+)=(.*)$", token)
    parts <- regmatches(token, matched)[[1L]]
    if (length(parts) == 3L) {
      key <- gsub("-", "_", parts[[2L]]); value <- parts[[3L]]
    } else {
      corr_assert(startsWith(token, "--") && i < length(args), paste("Invalid argument:", token))
      key <- gsub("-", "_", substring(token, 3L)); value <- args[[i + 1L]]; i <- i + 1L
    }
    corr_assert(key %in% names(result), paste("Unknown argument:", token))
    result[[key]] <- value
    i <- i + 1L
  }
  for (key in c("base_task_id", "correction_task_id")) if (!is.null(result[[key]])) result[[key]] <- suppressWarnings(as.integer(result[[key]]))
  result
}
