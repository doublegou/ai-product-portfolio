stage_validate_input <- function(context) {
  validated <- v2_validate_input(context)
  v2_log(
    "Validated Base V2 input: ", validated$n_rows, " rows, ", validated$n_predictors,
    " ordered Full50 predictors, ", validated$n_l6_basins, " represented L6 basins."
  )
  invisible(validated)
}
