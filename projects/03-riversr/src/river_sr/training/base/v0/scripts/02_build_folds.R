stage_build_folds <- function(context, validated = NULL, force = FALSE) {
  folds_dir <- v0_output_path(context, "folds_dir")
  manifest_path <- file.path(folds_dir, "fold_manifest.json")
  if (file.exists(manifest_path) && !force) {
    v0_assert_folds_current(context)
    v0_log("Frozen V0 folds already match the training data; preparation skipped.")
    return(invisible(jsonlite::read_json(manifest_path, simplifyVector = TRUE)))
  }

  validation_dir <- v0_output_path(context, "validation_dir")
  completed_tasks <- list.files(validation_dir, pattern = "task_info\\.json$", recursive = TRUE, full.names = TRUE)
  v0_assert(
    length(completed_tasks) == 0L,
    "Validation results already exist. Archive them before rebuilding the shared V0 folds."
  )
  if (is.null(validated)) validated <- stage_validate_input(context)
  dat <- validated$data
  columns <- context$config$columns
  outer_k <- as.integer(context$config$validation$outer_folds)
  inner_k <- as.integer(context$config$validation$inner_folds)

  v0_log("Building frozen R51a spatial folds.")
  spatial <- v0_build_spatial_folds(dat, context)
  v0_log("Building frozen R51b reference-group folds.")
  reference <- v0_build_reference_folds(dat, context)
  outer <- rbind(spatial$outer, reference$outer)
  inner <- rbind(spatial$inner, reference$inner)

  schemes <- c(paste0("spatial_", as.integer(unlist(context$config$validation$spatial_scales_km))), "reference")
  v0_assert(nrow(outer) == nrow(dat) * length(schemes), "Unexpected number of outer-fold assignments.")
  v0_assert(!anyNA(outer$outer_fold) && all(outer$outer_fold %in% seq_len(outer_k)), "Invalid outer-fold assignment.")
  v0_assert(!anyNA(inner$inner_fold) && all(inner$inner_fold %in% seq_len(inner_k)), "Invalid inner-fold assignment.")

  outer_split <- stats::aggregate(outer_fold ~ scheme + validation_unit, outer, function(x) length(unique(x)))
  v0_assert(all(outer_split$outer_fold == 1L), "A validation unit was split across outer folds.")
  inner_split <- stats::aggregate(inner_fold ~ scheme + outer_fold + validation_unit, inner, function(x) length(unique(x)))
  v0_assert(all(inner_split$inner_fold == 1L), "A validation unit was split across inner folds.")

  outer_diagnostics <- do.call(rbind, lapply(schemes, function(scheme) {
    scheme_rows <- outer[outer$scheme == scheme, , drop = FALSE]
    do.call(rbind, lapply(seq_len(outer_k), function(fold) {
      test <- scheme_rows[scheme_rows$outer_fold == fold, , drop = FALSE]
      data.frame(
        level = "outer", scheme = scheme, outer_fold = fold, inner_fold = NA_integer_,
        n_analysis = nrow(dat) - nrow(test), n_assessment = nrow(test),
        n_units = length(unique(test$validation_unit))
      )
    }))
  }))
  inner_diagnostics <- do.call(rbind, lapply(schemes, function(scheme) {
    do.call(rbind, lapply(seq_len(outer_k), function(outer_fold) {
      rows <- inner[inner$scheme == scheme & inner$outer_fold == outer_fold, , drop = FALSE]
      v0_assert(setequal(sort(unique(rows$inner_fold)), seq_len(inner_k)), paste("Missing inner fold for", scheme, outer_fold))
      do.call(rbind, lapply(seq_len(inner_k), function(inner_fold) {
        assessment <- rows[rows$inner_fold == inner_fold, , drop = FALSE]
        data.frame(
          level = "inner", scheme = scheme, outer_fold = outer_fold, inner_fold = inner_fold,
          n_analysis = nrow(rows) - nrow(assessment), n_assessment = nrow(assessment),
          n_units = length(unique(assessment$validation_unit))
        )
      }))
    }))
  }))
  diagnostics <- rbind(outer_diagnostics, inner_diagnostics)

  dir.create(folds_dir, recursive = TRUE, showWarnings = FALSE)
  v0_write_csv(outer, file.path(folds_dir, "outer_assignments.csv"))
  v0_write_csv(inner, file.path(folds_dir, "inner_assignments.csv"))
  v0_write_csv(diagnostics, file.path(folds_dir, "fold_diagnostics.csv"))

  task_manifest <- expand.grid(
    outer_fold = seq_len(outer_k),
    scheme = schemes,
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  task_manifest <- task_manifest[order(match(task_manifest$scheme, schemes), task_manifest$outer_fold), ]
  task_manifest$task_id <- seq_len(nrow(task_manifest))
  task_manifest <- task_manifest[c("task_id", "scheme", "outer_fold")]
  dir.create(validation_dir, recursive = TRUE, showWarnings = FALSE)
  v0_write_csv(task_manifest, file.path(validation_dir, "task_manifest.csv"))

  manifest <- list(
    status = "frozen",
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    input = validated$signature,
    n_rows = validated$n_rows,
    predictors = validated$predictors,
    response = columns$response,
    outer_folds = outer_k,
    inner_folds = inner_k,
    schemes = schemes,
    spatial_projection = "manual spherical sinusoidal; Earth radius 6371008.8 m; antimeridian is a block boundary",
    assignment = "whole units sorted by descending row count with seeded random ties, greedily balanced by fold rows then unit count",
    legacy_mapping = list(spatial = "R51a", reference = "R51b")
  )
  v0_write_json(manifest, manifest_path)
  v0_write_json(
    list(
      status = "prepared",
      expected_tasks = nrow(task_manifest),
      schemes = schemes,
      inner_trees = context$config$model$inner_trees,
      outer_trees = context$config$model$outer_trees,
      fold_input_md5 = validated$signature$md5
    ),
    file.path(validation_dir, "validation_manifest.json")
  )
  v0_log("Frozen folds written: ", nrow(task_manifest), " validation tasks prepared.")
  invisible(manifest)
}
