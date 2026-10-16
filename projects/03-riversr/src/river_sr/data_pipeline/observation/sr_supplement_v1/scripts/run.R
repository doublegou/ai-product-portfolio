file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) stop("Run this file with Rscript.", call. = FALSE)
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
source(file.path(dirname(script_path), "common.R"), local = TRUE)
context <- supplement_context(script_path)

args <- commandArgs(trailingOnly = TRUE)
stage_arg <- grep("^--stage=", args, value = TRUE)
stage <- if (length(stage_arg)) sub("^--stage=", "", stage_arg[[1L]]) else "all"
allowed <- c("all", "validate", "build", "check")
supplement_assert(stage %in% allowed, paste("Unknown stage:", stage))

scripts <- c(
  validate = "01_validate_raw.R",
  build = "02_build_release.R",
  check = "03_validate_output.R"
)
run_script <- function(name) {
  status <- system2(file.path(R.home("bin"), "Rscript"), file.path(dirname(script_path), scripts[[name]]))
  supplement_assert(status == 0L, paste("Stage failed:", name))
}

if (stage == "all") {
  for (name in names(scripts)) run_script(name)
} else if (stage == "build") {
  run_script("validate")
  run_script("build")
} else {
  run_script(stage)
}
message("Observation sr_supplement_v1 pipeline completed successfully.")
