stage_rrisk2_validate_input <- function(context) {
  x <- rrisk2_validate_input(context)
  rrisk2_log("Validated V2 input: ", x$audit$rows, " rows, ", x$audit$branches, " branches, ", x$audit$positive, " positives, ", x$audit$extreme, " extremes.")
  invisible(x)
}
