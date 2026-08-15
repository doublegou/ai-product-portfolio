renv_activate <- file.path("renv", "activate.R")
if (file.exists(renv_activate)) {
  source(renv_activate)
}

options(
  stringsAsFactors = FALSE,
  repos = c(CRAN = Sys.getenv("RIVER_SR_CRAN", "https://cloud.r-project.org"))
)
