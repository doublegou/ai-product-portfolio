file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) {
  stop("Run bootstrap with Rscript environment/bootstrap.R", call. = FALSE)
}

script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
repo_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE)
setwd(repo_root)

if (getRversion() < "4.3.0") {
  stop("RiverSR requires R >= 4.3.0; found ", getRversion(), call. = FALSE)
}

options(repos = c(
  CRAN = Sys.getenv("RIVER_SR_CRAN", "https://cloud.r-project.org")
))

bootstrap_library <- file.path(
  repo_root,
  "renv",
  "bootstrap-library",
  paste0("R-", getRversion())
)
dir.create(bootstrap_library, recursive = TRUE, showWarnings = FALSE)

if (!requireNamespace("renv", quietly = TRUE)) {
  .libPaths(c(bootstrap_library, .libPaths()))
  install.packages("renv", lib = bootstrap_library)
}

renv::consent(provided = TRUE)

source(file.path("environment", "packages.R"), local = TRUE)
packages <- unique(unlist(river_sr_packages, use.names = FALSE))

if (file.exists("renv.lock")) {
  renv::restore(prompt = FALSE)
} else {
  renv::init(bare = TRUE, restart = FALSE)
}

renv::load(project = repo_root)
renv::install(packages)
renv::settings$snapshot.type("all")
renv::snapshot(type = "all", prompt = FALSE)

message("RiverSR environment is ready at: ", repo_root)
