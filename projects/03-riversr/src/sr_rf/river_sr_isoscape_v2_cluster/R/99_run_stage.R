args <- commandArgs(trailingOnly=TRUE)
if (!length(args)) stop("Usage: Rscript R/99_run_stage.R <stage>")
stage <- args[[1]]
scripts <- c(
  setup="R/00_setup_check.R",
  qc="R/01_ingest_qc.R",
  table="R/02_build_model_table.R",
  folds="R/03_make_folds.R",
  A="R/04_experiment_A.R",
  B="R/05_experiment_B.R",
  diagnose="R/06_diagnose_oof_residuals.R",
  C="R/07_high_value_expert.R",
  D="R/08_environment_experts.R",
  E="R/09_weighting_sensitivity.R",
  final="R/10_finalize_aoa_predict.R"
)
if (!stage %in% names(scripts)) stop("Unknown stage. Choose: ",paste(names(scripts),collapse=", "))
source(scripts[[stage]], chdir=FALSE)
