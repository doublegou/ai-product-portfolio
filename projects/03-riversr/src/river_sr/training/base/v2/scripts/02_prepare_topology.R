stage_prepare_v2 <- function(context, force = FALSE) {
  validated <- stage_validate_input(context)
  stage_prepare_topology(context, validated, force = force)
  stage_build_folds(context, validated, force = force)
  invisible(v2_assert_folds_current(context))
}
