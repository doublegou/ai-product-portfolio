stage_validate_input <- function(context) {
  v1_log("Validating frozen Full50 V1 input.")
  result <- v1_validate_input(context)
  v1_log(
    "Input ready: ", result$n_rows, " rows, ", result$n_predictors,
    " predictors, ", result$n_l6_basins, " represented L6 basins."
  )
  result
}
