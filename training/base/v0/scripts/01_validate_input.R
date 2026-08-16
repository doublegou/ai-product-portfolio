stage_validate_input <- function(context) {
  v0_log("Validating Full50 training input.")
  result <- v0_validate_input(context)
  v0_log(
    "Input ready: ", result$n_rows, " rows, ", result$n_predictors,
    " predictors, ", result$n_reference_groups, " reference groups."
  )
  result
}
