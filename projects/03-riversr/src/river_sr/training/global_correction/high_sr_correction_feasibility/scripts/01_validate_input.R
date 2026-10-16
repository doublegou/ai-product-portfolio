stage_corr_validate_input <- function(context) {
  validated <- corr_validate_input(context)
  corr_log("Validated correction input: ", nrow(validated$data), " rows, ", length(validated$full50),
           " Full50 predictors, ", length(validated$env47), " Env47 predictors.")
  validated
}
