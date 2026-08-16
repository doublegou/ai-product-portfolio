stage_rrisk11_validate_input <- function(context) {
  validated <- rrisk11_validate_input(context)
  rrisk11_log(
    "Validated frozen Regional Risk V1 input: ", validated$audit$rows, " rows, ", validated$audit$branches,
    " branches, ", validated$audit$positive, " positives, ", validated$audit$extreme, " extreme rows."
  )
  invisible(validated)
}
