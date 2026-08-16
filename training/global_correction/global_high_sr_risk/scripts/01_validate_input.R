stage_risk_validate_input <- function(context) {
  risk_log("Validating frozen Base V1 input and NonSpatial47 boundary.")
  result <- risk_validate_input(context)
  risk_log(
    "Input ready: ", nrow(result$data), " rows, ", length(result$predictors),
    " predictors, ", length(unique(result$data$.hydrological_group)), " hydrological groups, ",
    sum(result$data$.positive), " positive rows."
  )
  result
}
