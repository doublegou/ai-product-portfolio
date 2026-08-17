stage_fa_validate <- function(context) {
  x <- fa_validate_inputs(context)
  fa_log("Validated frozen V2 inputs: 372 stations, 64 predictors, ", length(x$missed_branches), " completely missed branches and ", length(x$missed_ids), " missed high-Sr sites.")
  invisible(x)
}
