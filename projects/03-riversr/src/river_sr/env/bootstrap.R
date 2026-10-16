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

if (v0_only) {
  manifest_path <- file.path(repo_root, "env", "v0_offline_packages.txt")
  archives <- trimws(readLines(manifest_path, warn = FALSE, encoding = "UTF-8"))
  archives <- archives[nzchar(archives) & !startsWith(archives, "#")]
  archives <- file.path(repo_root, "env", "offline", "src", archives)
  missing_archives <- archives[!file.exists(archives)]
  if (length(missing_archives)) {
    stop(
      "Missing V0 offline package archives: ",
      paste(basename(missing_archives), collapse = ", "),
      call. = FALSE
    )
  }
  Sys.setenv(MAKEFLAGS = paste0("-j", getOption("Ncpus", 1L)))
  for (archive in archives) {
    message("Installing offline package: ", basename(archive))
    install.packages(archive, lib = project_library, repos = NULL, type = "source")
  }
  required <- c("yaml", "jsonlite", "digest", "data.table", "ranger", "dplyr", "tidyr")
  missing <- required[!vapply(required, requireNamespace, logical(1L), quietly = TRUE)]
  if (length(missing)) {
    stop("V0 environment is incomplete: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  message("RiverSR V0 environment is ready: ", project_library)
  quit(save = "no", status = 0L)
}

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
do.call(renv::restore, restore_args)

message("RiverSR environment is ready: ", project_library)
