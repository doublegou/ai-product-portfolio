stage_rrisk_validate_input <- function(context) {
  rrisk_log("Validating the frozen 372-row Himalaya Risk V1 table.")
  result <- rrisk_validate_input(context)
  rrisk_log("Input ready: ", nrow(result$data), " rows; positives=", sum(result$data$.label), "; Environment predictors=", length(result$predictors), ".")
  result
}
