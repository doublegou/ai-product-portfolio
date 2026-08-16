stage_check_v2 <- function(context) {
  validated <- stage_validate_input(context)
  manifest <- v2_assert_folds_current(context)
  paths <- v2_fold_paths(context)
  outer <- data.table::fread(paths[["primary_outer"]], integer64 = "character", data.table = FALSE)
  inner <- data.table::fread(paths[["primary_inner"]], integer64 = "character", data.table = FALSE)
  deployment <- data.table::fread(paths[["deployment"]], integer64 = "character", data.table = FALSE)
  diagnostics <- data.table::fread(paths[["diagnostics"]], data.table = FALSE)
  catalog <- data.table::fread(paths[["branch_catalog"]], integer64 = "character", data.table = FALSE)
  repeats <- as.integer(context$config$validation$repeats)
  eligible <- as.integer(manifest$topology$n_primary_eligible_rows)
  primary_scale <- as.character(manifest$topology$selected_scale)
  primary_catalog <- catalog[catalog$scale == primary_scale & catalog$assessment_eligible, , drop = FALSE]
  branch_sizes <- table(primary_catalog$branch_id)
  primary_definition <- context$config$topology$scales[[primary_scale]]
  v2_assert(min(branch_sizes) >= as.integer(primary_definition$minimum_station_support), "A frozen Primary branch is below minimum support.")
  v2_assert(max(branch_sizes) < as.integer(primary_definition$station_trunk_support), "A frozen Primary branch reaches or exceeds the station-trunk support threshold.")
  outlets_per_branch <- stats::aggregate(branch_outlet_reach_id ~ branch_id, primary_catalog, function(x) length(unique(x)))
  v2_assert(all(outlets_per_branch$branch_outlet_reach_id == 1L), "A frozen Primary branch has multiple outlet reaches.")
  for (repeat_id in seq_len(repeats)) {
    current <- outer[outer$repeat_id == repeat_id & outer$role == "assessment", , drop = FALSE]
    v2_assert(nrow(current) == eligible, paste("Repeat", repeat_id, "does not assess every eligible row exactly once."))
    v2_assert(!anyDuplicated(current$row_id), paste("Repeat", repeat_id, "contains duplicated Primary assessment rows."))
  }
  outer_keys <- unique(outer[c("repeat_id", "outer_fold")])
  for (i in seq_len(nrow(outer_keys))) {
    current <- outer[
      outer$repeat_id == outer_keys$repeat_id[[i]] & outer$outer_fold == outer_keys$outer_fold[[i]], , drop = FALSE
    ]
    assessment_branches <- unique(current$branch_id[current$role == "assessment"])
    analysis_branches <- unique(current$branch_id[current$role == "analysis" & !is.na(current$branch_id)])
    v2_assert(length(intersect(assessment_branches, analysis_branches)) == 0L, "A Primary branch crosses an Outer assessment/analysis boundary.")
  }
  inner_keys <- unique(inner[c("repeat_id", "outer_fold", "inner_fold")])
  for (i in seq_len(nrow(inner_keys))) {
    current <- inner[
      inner$repeat_id == inner_keys$repeat_id[[i]] &
        inner$outer_fold == inner_keys$outer_fold[[i]] &
        inner$inner_fold == inner_keys$inner_fold[[i]], , drop = FALSE
    ]
    assessment_branches <- unique(current$branch_id[current$role == "assessment"])
    analysis_branches <- unique(current$branch_id[current$role == "analysis" & !is.na(current$branch_id)])
    v2_assert(length(intersect(assessment_branches, analysis_branches)) == 0L, "A Primary branch crosses an Inner assessment/analysis boundary.")
  }
  for (fold in seq_len(as.integer(context$config$validation$deployment_folds))) {
    current <- deployment[deployment$deployment_fold == fold, , drop = FALSE]
    v2_assert(any(current$role == "assessment") && any(current$role == "analysis"), "A deployment fold lacks assessment or analysis rows.")
  }
  primary_diag <- diagnostics[diagnostics$level == "primary_outer", , drop = FALSE]
  sanity <- context$config$topology$sanity
  v2_assert(min(primary_diag$n_purged) >= as.integer(sanity$minimum_primary_outer_purge), "A Primary Outer fold purges too few downstream rows.")
  v2_assert(max(primary_diag$n_purged) <= as.integer(sanity$maximum_primary_outer_purge), "A Primary Outer fold purges too many downstream rows.")
  v2_log(
    "Base V2 engineering check passed: ", manifest$topology$n_primary_branches, " Primary branches, ",
    eligible, " eligible rows; assessment range ", min(primary_diag$n_assessment), "-", max(primary_diag$n_assessment),
    "; purge range ", min(primary_diag$n_purged), "-", max(primary_diag$n_purged), "."
  )
  invisible(list(validated = validated, manifest = manifest))
}
