file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) {
  stop("Run bootstrap with Rscript env/bootstrap.R", call. = FALSE)
}

script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(repo_root, "env", "activate.R"), local = TRUE)
cli <- commandArgs(trailingOnly = TRUE)
unknown <- setdiff(cli, "--v0-only")
if (length(unknown)) {
  stop("Unknown bootstrap argument: ", paste(unknown, collapse = ", "), call. = FALSE)
}
v0_only <- "--v0-only" %in% cli

if (getRversion() < "4.3.0") {
  stop("RiverSR requires R >= 4.3.0; found ", getRversion(), call. = FALSE)
}

options(repos = c(
  CRAN = Sys.getenv("RIVER_SR_CRAN", "https://cloud.r-project.org")
))
options(Ncpus = max(1L, suppressWarnings(as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", "1"))), na.rm = TRUE))

project_library <- river_sr_library_path(repo_root)
dir.create(project_library, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(project_library, .libPaths()))

if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv", lib = project_library)
}

renv::consent(provided = TRUE)
restore_args <- list(
  project = repo_root,
  library = project_library,
  lockfile = file.path(repo_root, "env", "renv.lock"),
  prompt = FALSE
)
if (v0_only) {
  restore_args$packages <- c("yaml", "jsonlite", "digest", "data.table", "ranger")
}
do.call(renv::restore, restore_args)

message(
  if (v0_only) "RiverSR V0 environment is ready: " else "RiverSR environment is ready: ",
  project_library
)
