args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop("Usage: bootstrap_r_packages.R <project-dir> <package-list>")
}

project_dir <- normalizePath(args[[1L]], mustWork = TRUE)
package_file <- normalizePath(args[[2L]], mustWork = TRUE)
conda_prefix <- Sys.getenv("CONDA_PREFIX", unset = "")

if (!nzchar(conda_prefix)) {
  stop("CONDA_PREFIX is not set; run this script inside the sr_rf environment.")
}
if (basename(conda_prefix) != "sr_rf") {
  stop("Expected Conda environment 'sr_rf', got: ", conda_prefix)
}

project_library <- file.path(conda_prefix, "renv-library", "sr_rf")
staging_library <- file.path(conda_prefix, "renv-staging", "sr_rf")
conda_library <- file.path(conda_prefix, "lib")
wrapper_bin <- file.path(dirname(package_file), "bin")
dir.create(project_library, recursive = TRUE, showWarnings = FALSE)
dir.create(staging_library, recursive = TRUE, showWarnings = FALSE)

prepend_path <- function(value, current = "") {
  entries <- c(value, current)
  paste(entries[nzchar(entries)], collapse = .Platform$path.sep)
}

Sys.setenv(
  RENV_PATHS_LIBRARY = project_library,
  RENV_PATHS_LIBRARY_STAGING = staging_library,
  RENV_CONFIG_AUTO_SNAPSHOT = "FALSE",
  RENV_CONFIG_VCS_MANAGE_IGNORES = "FALSE",
  PATH = prepend_path(wrapper_bin, Sys.getenv("PATH", unset = "")),
  GDAL_DATA = file.path(conda_prefix, "share", "gdal"),
  PROJ_DATA = file.path(conda_prefix, "share", "proj"),
  PROJ_LIB = file.path(conda_prefix, "share", "proj"),
  PKG_CONFIG_PATH = prepend_path(
    file.path(conda_prefix, "lib", "pkgconfig"),
    Sys.getenv("PKG_CONFIG_PATH", unset = "")
  ),
  DYLD_FALLBACK_LIBRARY_PATH = prepend_path(
    conda_library,
    Sys.getenv("DYLD_FALLBACK_LIBRARY_PATH", unset = "")
  ),
  LD_LIBRARY_PATH = prepend_path(
    conda_library,
    Sys.getenv("LD_LIBRARY_PATH", unset = "")
  ),
  LDFLAGS = paste(
    Sys.getenv("LDFLAGS", unset = ""),
    paste0("-Wl,-rpath,", conda_library)
  )
)
options(repos = c(CRAN = "https://cloud.r-project.org"))

packages <- trimws(readLines(package_file, warn = FALSE))
packages <- packages[nzchar(packages) & !startsWith(packages, "#")]
if (!length(packages)) {
  stop("No R packages were declared in ", package_file)
}

lockfile <- file.path(project_dir, "renv.lock")

if (!file.exists(file.path(project_dir, "renv", "activate.R"))) {
  message("Initializing renv in ", project_dir)
  renv::init(project = project_dir, bare = TRUE, restart = FALSE)
}

renv::settings$vcs.manage.ignores(FALSE, project = project_dir)
renv::settings$snapshot.type("all", project = project_dir)
generated_ignore <- file.path(project_dir, "renv", ".gitignore")
if (file.exists(generated_ignore)) {
  unlink(generated_ignore)
}

renv::load(project = project_dir)

if (file.exists(lockfile)) {
  message("Restoring R packages from renv.lock")
  renv::restore(project = project_dir, prompt = FALSE)
} else {
  message("Creating the initial R package library")
  renv::install(packages, project = project_dir, prompt = FALSE)
}

missing_packages <- packages[
  !vapply(packages, requireNamespace, logical(1L), quietly = TRUE)
]
if (length(missing_packages)) {
  message("Installing packages added after the last lockfile snapshot")
  renv::install(missing_packages, project = project_dir, prompt = FALSE)
}

renv::snapshot(
  project = project_dir,
  type = "all",
  prompt = FALSE,
  force = TRUE
)

if (file.exists(generated_ignore)) {
  unlink(generated_ignore)
}

message("R package library: ", project_library)
