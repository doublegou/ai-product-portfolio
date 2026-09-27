args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop("Usage: check_environment.R <project-dir> <package-list>")
}

project_dir <- normalizePath(args[[1L]], mustWork = TRUE)
package_file <- normalizePath(args[[2L]], mustWork = TRUE)
repo_root <- dirname(project_dir)
conda_prefix <- Sys.getenv("CONDA_PREFIX", unset = "")
generated_ignore <- file.path(project_dir, "renv", ".gitignore")

if (!nzchar(conda_prefix) || basename(conda_prefix) != "sr_rf") {
  stop("Environment check must run inside the Conda environment 'sr_rf'.")
}

project_library <- file.path(conda_prefix, "renv-library", "sr_rf")
conda_library <- file.path(conda_prefix, "lib")
wrapper_bin <- file.path(dirname(package_file), "bin")
prepend_path <- function(value, current = "") {
  entries <- c(value, current)
  paste(entries[nzchar(entries)], collapse = .Platform$path.sep)
}
Sys.setenv(
  RENV_PATHS_LIBRARY = project_library,
  RENV_PATHS_LIBRARY_STAGING = file.path(conda_prefix, "renv-staging", "sr_rf"),
  RENV_CONFIG_VCS_MANAGE_IGNORES = "FALSE",
  PATH = prepend_path(wrapper_bin, Sys.getenv("PATH", unset = "")),
  GDAL_DATA = file.path(conda_prefix, "share", "gdal"),
  PROJ_DATA = file.path(conda_prefix, "share", "proj"),
  PROJ_LIB = file.path(conda_prefix, "share", "proj"),
  DYLD_FALLBACK_LIBRARY_PATH = prepend_path(
    conda_library,
    Sys.getenv("DYLD_FALLBACK_LIBRARY_PATH", unset = "")
  ),
  LD_LIBRARY_PATH = prepend_path(
    conda_library,
    Sys.getenv("LD_LIBRARY_PATH", unset = "")
  )
)
renv::load(project = project_dir)
if (file.exists(generated_ignore)) {
  unlink(generated_ignore)
}

packages <- trimws(readLines(package_file, warn = FALSE))
packages <- packages[nzchar(packages) & !startsWith(packages, "#")]
available <- vapply(packages, requireNamespace, logical(1L), quietly = TRUE)

if (any(!available)) {
  stop("Missing R packages: ", paste(packages[!available], collapse = ", "))
}

r_files <- c(
  list.files(file.path(project_dir, "R"), pattern = "[.]R$", recursive = TRUE, full.names = TRUE),
  list.files(file.path(repo_root, "projects"), pattern = "[.]R$", recursive = TRUE, full.names = TRUE)
)
parse_errors <- character()
for (r_file in r_files) {
  tryCatch(
    parse(file = r_file),
    error = function(error) {
      parse_errors <<- c(parse_errors, paste(r_file, conditionMessage(error), sep = ": "))
    }
  )
}
if (length(parse_errors)) {
  stop("R syntax errors:\n", paste(parse_errors, collapse = "\n"))
}

library_path <- normalizePath(.libPaths()[[1L]], mustWork = TRUE)
if (startsWith(library_path, paste0(normalizePath(repo_root), .Platform$file.sep))) {
  stop("The runtime R library must not be stored inside the Git repository: ", library_path)
}

cat("Environment check passed.\n")
cat("Conda prefix:", conda_prefix, "\n")
cat("R:", R.version.string, "\n")
cat("R library:", library_path, "\n")
cat("Required R packages:", length(packages), "\n")
cat("Parsed R files:", length(r_files), "\n")
cat("GDAL:", unname(sf::sf_extSoftVersion()[["GDAL"]]), "\n")
cat("GEOS:", unname(sf::sf_extSoftVersion()[["GEOS"]]), "\n")
cat("PROJ:", unname(sf::sf_extSoftVersion()[["PROJ"]]), "\n")
