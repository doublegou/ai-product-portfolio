file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) {
  stop("Run bootstrap with Rscript env/bootstrap.R", call. = FALSE)
}

script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
source(file.path(repo_root, "env", "activate.R"), local = TRUE)

if (getRversion() < "4.3.0") {
  stop("RiverSR requires R >= 4.3.0; found ", getRversion(), call. = FALSE)
}

options(repos = c(
  CRAN = Sys.getenv("RIVER_SR_CRAN", "https://cloud.r-project.org")
))

project_library <- river_sr_library_path(repo_root)
dir.create(project_library, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(project_library, .libPaths()))

if (!requireNamespace("renv", quietly = TRUE)) {
  install.packages("renv", lib = project_library)
}

renv::consent(provided = TRUE)
renv::restore(
  project = repo_root,
  library = project_library,
  lockfile = file.path(repo_root, "env", "renv.lock"),
  prompt = FALSE
)

message("RiverSR environment is ready: ", project_library)
