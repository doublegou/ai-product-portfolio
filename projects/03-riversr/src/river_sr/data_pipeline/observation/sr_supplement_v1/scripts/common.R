supplement_assert <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

supplement_context <- function(script_path) {
  project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
  repo_root <- project_dir
  repeat {
    if (file.exists(file.path(repo_root, "env", "activate.R"))) break
    parent <- dirname(repo_root)
    supplement_assert(!identical(parent, repo_root), "Cannot find the RiverSR repository root.")
    repo_root <- parent
  }
  repo_root <- normalizePath(repo_root, mustWork = TRUE)
  source(file.path(repo_root, "env", "activate.R"), local = TRUE)
  river_sr_activate(repo_root)
  list(
    repo_root = repo_root,
    project_dir = project_dir,
    config = yaml::read_yaml(file.path(project_dir, "config", "default.yml"))
  )
}

supplement_path <- function(context, relative_path) file.path(context$repo_root, relative_path)

supplement_atomic_rds <- function(object, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(pattern = "sr_supplement_", tmpdir = dirname(path))
  on.exit(unlink(temporary), add = TRUE)
  saveRDS(object, temporary, version = 3L)
  if (file.exists(path)) unlink(path)
  supplement_assert(file.rename(temporary, path), paste("Could not write:", path))
}

supplement_atomic_csv <- function(object, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(pattern = "sr_supplement_", tmpdir = dirname(path))
  on.exit(unlink(temporary), add = TRUE)
  data.table::fwrite(object, temporary, na = "")
  if (file.exists(path)) unlink(path)
  supplement_assert(file.rename(temporary, path), paste("Could not write:", path))
}

supplement_atomic_json <- function(object, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile(pattern = "sr_supplement_", tmpdir = dirname(path), fileext = ".json")
  on.exit(unlink(temporary), add = TRUE)
  jsonlite::write_json(object, temporary, auto_unbox = TRUE, pretty = TRUE, na = "null")
  if (file.exists(path)) unlink(path)
  supplement_assert(file.rename(temporary, path), paste("Could not write:", path))
}

supplement_sha256 <- function(path) {
  digest::digest(file = path, algo = "sha256", serialize = FALSE)
}

supplement_file_record <- function(path, repo_root) {
  info <- file.info(path)
  list(
    path = gsub("\\\\", "/", substring(normalizePath(path), nchar(normalizePath(repo_root)) + 2L)),
    bytes = unname(info$size),
    sha256 = supplement_sha256(path)
  )
}

supplement_band <- function(sr) {
  cut(
    as.numeric(sr),
    breaks = c(-Inf, 0.72, 0.75, 0.80, Inf),
    right = FALSE,
    labels = c("lt_0.72", "0.72_to_0.75", "0.75_to_0.80", "ge_0.80")
  )
}

supplement_named_counts <- function(x) {
  result <- as.list(as.integer(x))
  names(result) <- names(x)
  result
}
