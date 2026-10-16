file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) stop("Run with Rscript training/regional_expert/regional_failure_audit/scripts/run.R", call. = FALSE)
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE); project_dir <- normalizePath(file.path(dirname(script_path), ".."), mustWork = TRUE); repo_root <- normalizePath(file.path(project_dir, "..", "..", ".."), mustWork = TRUE)
source(file.path(repo_root, "env", "activate.R"), local = TRUE); river_sr_activate(repo_root)
for (file in c("io.R", "validation.R", "overlap.R", "nearest_neighbor.R", "reporting.R")) source(file.path(project_dir, "R", file), local = globalenv())
for (file in c("01_validate_inputs.R", "02_run_audit.R", "03_summarize.R")) source(file.path(project_dir, "scripts", file), local = globalenv())
context <- fa_context(repo_root, project_dir); args <- commandArgs(trailingOnly = TRUE); stage <- if (length(args) == 2L && args[1] == "--stage") args[2] else if (length(args) == 1L && startsWith(args[1], "--stage=")) sub("--stage=", "", args[1]) else ""
if (stage == "validate") { stage_fa_validate(context); quit(save = "no", status = 0L) }
if (stage == "audit") { stage_fa_audit(context); quit(save = "no", status = 0L) }
if (stage == "summarize") { stage_fa_summarize(context); quit(save = "no", status = 0L) }
fa_assert(FALSE, "Specify --stage validate|audit|summarize.")
