v2_assign_units_balanced <- function(units, k, seed) {
  v2_assert(is.data.frame(units) && all(c("validation_unit", "n_rows") %in% names(units)), "units must contain validation_unit and n_rows.")
  k <- as.integer(k)
  v2_assert(nrow(units) >= k && k >= 2L, "Not enough validation units for requested folds.")
  set.seed(as.integer(seed))
  work <- units
  work$.original_order <- seq_len(nrow(work))
  work$.random_tie_breaker <- stats::runif(nrow(work))
  work <- work[order(-work$n_rows, work$.random_tie_breaker), , drop = FALSE]
  fold_rows <- rep(0L, k)
  fold_units <- rep(0L, k)
  assigned <- integer(nrow(work))
  for (i in seq_len(nrow(work))) {
    candidates <- which(fold_rows == min(fold_rows))
    if (length(candidates) > 1L) candidates <- candidates[fold_units[candidates] == min(fold_units[candidates])]
    chosen <- if (length(candidates) == 1L) candidates[[1L]] else sample(candidates, 1L)
    assigned[[i]] <- chosen
    fold_rows[[chosen]] <- fold_rows[[chosen]] + work$n_rows[[i]]
    fold_units[[chosen]] <- fold_units[[chosen]] + 1L
  }
  work$fold <- assigned
  work <- work[order(work$.original_order), , drop = FALSE]
  work$.original_order <- NULL
  work$.random_tie_breaker <- NULL
  rownames(work) <- NULL
  work
}

v2_task_roles <- function(universe_rows, branch_map, assessment_branches, downstream_pairs) {
  universe_rows <- as.character(universe_rows)
  assessment_branches <- as.character(assessment_branches)
  assessment_rows <- branch_map$row_id[branch_map$branch_id %in% assessment_branches]
  assessment_rows <- intersect(universe_rows, assessment_rows)
  downstream_rows <- downstream_pairs$downstream_row_id[
    downstream_pairs$upstream_row_id %in% assessment_rows &
      downstream_pairs$downstream_row_id %in% universe_rows
  ]
  downstream_rows <- setdiff(unique(as.character(downstream_rows)), assessment_rows)
  contaminated_branches <- unique(branch_map$branch_id[
    branch_map$row_id %in% downstream_rows & !is.na(branch_map$branch_id)
  ])
  if (length(contaminated_branches)) {
    downstream_rows <- union(
      downstream_rows,
      intersect(universe_rows, branch_map$row_id[branch_map$branch_id %in% contaminated_branches])
    )
  }
  downstream_rows <- setdiff(downstream_rows, assessment_rows)
  role <- rep("analysis", length(universe_rows))
  role[universe_rows %in% downstream_rows] <- "purged_downstream"
  role[universe_rows %in% assessment_rows] <- "assessment"
  result <- data.frame(
    row_id = universe_rows,
    branch_id = branch_map$branch_id[match(universe_rows, branch_map$row_id)],
    role = role,
    stringsAsFactors = FALSE
  )
  v2_assert(!anyNA(result$role), "Task role assignment is incomplete.")
  v2_assert(length(intersect(result$row_id[result$role == "assessment"], result$row_id[result$role == "analysis"])) == 0L, "Assessment and analysis overlap.")
  v2_assert(length(intersect(result$row_id[result$role == "assessment"], result$row_id[result$role == "purged_downstream"])) == 0L, "Assessment and downstream purge overlap.")
  result
}

v2_branch_units <- function(branch_map, universe_rows = NULL) {
  current <- branch_map[branch_map$assessment_eligible & !is.na(branch_map$branch_id), , drop = FALSE]
  if (!is.null(universe_rows)) current <- current[current$row_id %in% universe_rows, , drop = FALSE]
  sizes <- stats::aggregate(row_id ~ branch_id, current, length)
  names(sizes) <- c("validation_unit", "n_rows")
  sizes
}

v2_build_primary_roles <- function(context, all_rows, branch_map, downstream_pairs) {
  repeats <- as.integer(context$config$validation$repeats)
  outer_k <- as.integer(context$config$validation$outer_folds)
  inner_k <- as.integer(context$config$validation$inner_folds)
  outer_records <- list()
  inner_records <- list()
  outer_index <- 0L
  inner_index <- 0L
  units <- v2_branch_units(branch_map)
  for (repeat_id in seq_len(repeats)) {
    assigned <- v2_assign_units_balanced(
      units, outer_k,
      as.integer(context$config$validation$primary_outer_seed_base) + repeat_id
    )
    branch_fold <- stats::setNames(assigned$fold, assigned$validation_unit)
    for (outer_fold in seq_len(outer_k)) {
      assessment_branches <- names(branch_fold)[branch_fold == outer_fold]
      roles <- v2_task_roles(all_rows, branch_map, assessment_branches, downstream_pairs)
      outer_index <- outer_index + 1L
      outer_records[[outer_index]] <- data.frame(
        repeat_id = repeat_id,
        outer_fold = outer_fold,
        roles,
        stringsAsFactors = FALSE
      )
      outer_analysis <- roles$row_id[roles$role == "analysis"]
      inner_units <- v2_branch_units(branch_map, outer_analysis)
      expected_inner_branches <- unique(branch_map$branch_id[
        branch_map$row_id %in% outer_analysis & branch_map$assessment_eligible
      ])
      v2_assert(setequal(inner_units$validation_unit, expected_inner_branches), "An Outer purge partially retained a Primary branch.")
      inner_assigned <- v2_assign_units_balanced(
        inner_units, inner_k,
        as.integer(context$config$validation$primary_inner_seed_base) + repeat_id * 100L + outer_fold
      )
      inner_branch_fold <- stats::setNames(inner_assigned$fold, inner_assigned$validation_unit)
      for (inner_fold in seq_len(inner_k)) {
        inner_assessment <- names(inner_branch_fold)[inner_branch_fold == inner_fold]
        inner_roles <- v2_task_roles(outer_analysis, branch_map, inner_assessment, downstream_pairs)
        inner_index <- inner_index + 1L
        inner_records[[inner_index]] <- data.frame(
          repeat_id = repeat_id,
          outer_fold = outer_fold,
          inner_fold = inner_fold,
          inner_roles,
          stringsAsFactors = FALSE
        )
      }
    }
  }
  list(outer = do.call(rbind, outer_records), inner = do.call(rbind, inner_records))
}

v2_build_deployment_roles <- function(context, all_rows, branch_map, downstream_pairs) {
  k <- as.integer(context$config$validation$deployment_folds)
  units <- v2_branch_units(branch_map)
  assigned <- v2_assign_units_balanced(units, k, as.integer(context$config$validation$deployment_seed))
  branch_fold <- stats::setNames(assigned$fold, assigned$validation_unit)
  records <- lapply(seq_len(k), function(fold) {
    roles <- v2_task_roles(all_rows, branch_map, names(branch_fold)[branch_fold == fold], downstream_pairs)
    data.frame(deployment_fold = fold, roles, stringsAsFactors = FALSE)
  })
  do.call(rbind, records)
}

v2_build_standard_stress_assignments <- function(context, dat, site_topology) {
  columns <- context$config$columns
  row_id <- as.character(dat[[columns$row_id]])
  outer_k <- as.integer(context$config$validation$outer_folds)
  records <- list()
  index <- 0L
  terminal_rows <- data.frame(row_id = row_id, validation_unit = site_topology$terminal_component_id, stringsAsFactors = FALSE)
  terminal_units <- stats::aggregate(row_id ~ validation_unit, terminal_rows, length)
  names(terminal_units)[[2L]] <- "n_rows"
  terminal_assigned <- v2_assign_units_balanced(terminal_units, outer_k, as.integer(context$config$validation$terminal_outer_seed))
  terminal <- merge(terminal_rows, terminal_assigned[c("validation_unit", "fold")], by = "validation_unit", sort = FALSE)
  terminal <- terminal[match(row_id, terminal$row_id), , drop = FALSE]
  index <- index + 1L
  records[[index]] <- data.frame(row_id = row_id, scheme = "terminal", outer_fold = terminal$fold, validation_unit = terminal$validation_unit)

  radius <- 6371008.8
  longitude_rad <- as.numeric(dat[[columns$longitude]]) * pi / 180
  latitude_rad <- as.numeric(dat[[columns$latitude]]) * pi / 180
  cv_x_m <- radius * longitude_rad * cos(latitude_rad)
  cv_y_m <- radius * latitude_rad
  for (scale_km in as.integer(unlist(context$config$validation$spatial_scales_km))) {
    scheme <- paste0("spatial_", scale_km)
    unit <- paste(scheme, floor(cv_x_m / (scale_km * 1000)), floor(cv_y_m / (scale_km * 1000)), sep = "__")
    rows <- data.frame(row_id = row_id, validation_unit = unit, stringsAsFactors = FALSE)
    units <- stats::aggregate(row_id ~ validation_unit, rows, length)
    names(units)[[2L]] <- "n_rows"
    assigned <- v2_assign_units_balanced(units, outer_k, as.integer(context$config$validation$spatial_outer_seed_base) + scale_km)
    current <- merge(rows, assigned[c("validation_unit", "fold")], by = "validation_unit", sort = FALSE)
    current <- current[match(row_id, current$row_id), , drop = FALSE]
    index <- index + 1L
    records[[index]] <- data.frame(row_id = row_id, scheme = scheme, outer_fold = current$fold, validation_unit = current$validation_unit)
  }
  reference_rows <- data.frame(row_id = row_id, validation_unit = as.character(dat[[columns$reference]]), stringsAsFactors = FALSE)
  reference_units <- stats::aggregate(row_id ~ validation_unit, reference_rows, length)
  names(reference_units)[[2L]] <- "n_rows"
  reference_assigned <- v2_assign_units_balanced(reference_units, outer_k, as.integer(context$config$validation$reference_outer_seed))
  reference <- merge(reference_rows, reference_assigned[c("validation_unit", "fold")], by = "validation_unit", sort = FALSE)
  reference <- reference[match(row_id, reference$row_id), , drop = FALSE]
  index <- index + 1L
  records[[index]] <- data.frame(row_id = row_id, scheme = "reference", outer_fold = reference$fold, validation_unit = reference$validation_unit)
  do.call(rbind, records)
}

v2_fold_diagnostics <- function(primary, deployment, stress, branch_diagnostics) {
  records <- list()
  index <- 0L
  for (i in seq_len(nrow(branch_diagnostics))) {
    index <- index + 1L
    records[[index]] <- data.frame(
      level = "topology_scale", scheme = branch_diagnostics$scale[[i]],
      repeat_id = NA_integer_, outer_fold = NA_integer_, inner_fold = NA_integer_,
      n_analysis = NA_integer_, n_assessment = branch_diagnostics$n_eligible_rows[[i]],
      n_purged = NA_integer_, n_units = branch_diagnostics$n_branches[[i]],
      stringsAsFactors = FALSE
    )
  }
  keys <- unique(primary$outer[c("repeat_id", "outer_fold")])
  for (i in seq_len(nrow(keys))) {
    current <- primary$outer[primary$outer$repeat_id == keys$repeat_id[[i]] & primary$outer$outer_fold == keys$outer_fold[[i]], , drop = FALSE]
    index <- index + 1L
    records[[index]] <- data.frame(
      level = "primary_outer", scheme = "purged_branch", repeat_id = keys$repeat_id[[i]],
      outer_fold = keys$outer_fold[[i]], inner_fold = NA_integer_,
      n_analysis = sum(current$role == "analysis"), n_assessment = sum(current$role == "assessment"),
      n_purged = sum(current$role == "purged_downstream"),
      n_units = length(unique(current$branch_id[current$role == "assessment"])), stringsAsFactors = FALSE
    )
  }
  inner_keys <- unique(primary$inner[c("repeat_id", "outer_fold", "inner_fold")])
  for (i in seq_len(nrow(inner_keys))) {
    current <- primary$inner[
      primary$inner$repeat_id == inner_keys$repeat_id[[i]] &
        primary$inner$outer_fold == inner_keys$outer_fold[[i]] &
        primary$inner$inner_fold == inner_keys$inner_fold[[i]], , drop = FALSE
    ]
    index <- index + 1L
    records[[index]] <- data.frame(
      level = "primary_inner", scheme = "purged_branch", repeat_id = inner_keys$repeat_id[[i]],
      outer_fold = inner_keys$outer_fold[[i]], inner_fold = inner_keys$inner_fold[[i]],
      n_analysis = sum(current$role == "analysis"), n_assessment = sum(current$role == "assessment"),
      n_purged = sum(current$role == "purged_downstream"),
      n_units = length(unique(current$branch_id[current$role == "assessment"])), stringsAsFactors = FALSE
    )
  }
  for (fold in sort(unique(deployment$deployment_fold))) {
    current <- deployment[deployment$deployment_fold == fold, , drop = FALSE]
    index <- index + 1L
    records[[index]] <- data.frame(
      level = "deployment", scheme = "purged_branch", repeat_id = NA_integer_, outer_fold = fold,
      inner_fold = NA_integer_, n_analysis = sum(current$role == "analysis"),
      n_assessment = sum(current$role == "assessment"), n_purged = sum(current$role == "purged_downstream"),
      n_units = length(unique(current$branch_id[current$role == "assessment"])), stringsAsFactors = FALSE
    )
  }
  for (scheme in unique(stress$scheme)) for (fold in sort(unique(stress$outer_fold[stress$scheme == scheme]))) {
    current <- stress[stress$scheme == scheme & stress$outer_fold == fold, , drop = FALSE]
    index <- index + 1L
    records[[index]] <- data.frame(
      level = "stress", scheme = scheme, repeat_id = NA_integer_, outer_fold = fold,
      inner_fold = NA_integer_, n_analysis = NA_integer_, n_assessment = nrow(current),
      n_purged = 0L, n_units = length(unique(current$validation_unit)), stringsAsFactors = FALSE
    )
  }
  do.call(rbind, records)
}

stage_build_folds <- function(context, validated = NULL, force = FALSE) {
  if (is.null(validated)) validated <- v2_validate_input(context)
  paths <- v2_fold_paths(context)
  if (all(file.exists(paths)) && !force) {
    v2_assert_folds_current(context)
    v2_log("Frozen V2 folds already match the data and config; preparation skipped.")
    return(invisible(jsonlite::read_json(paths[["manifest"]], simplifyVector = TRUE)))
  }
  completed <- Sys.glob(file.path(v2_output_path(context, "validation_dir"), "*", "*", "task_info.json"))
  v2_assert(length(completed) == 0L, "Validation results exist. Archive them before rebuilding V2 folds.")
  interim_paths <- lapply(context$config$interim, function(path) v2_path(context, path))
  required <- unlist(interim_paths[c("site_topology", "downstream_pairs", "branch_candidates", "prepare_manifest")])
  v2_assert(all(file.exists(required)), "Topology checkpoints are incomplete; run topology preparation first.")
  site_topology <- readRDS(interim_paths$site_topology)
  downstream_pairs <- readRDS(interim_paths$downstream_pairs)
  branches <- readRDS(interim_paths$branch_candidates)
  selected_scale <- branches$selected_scale
  branch_map <- branches$catalog[branches$catalog$scale == selected_scale, , drop = FALSE]
  all_rows <- as.character(validated$data[[context$config$columns$row_id]])
  v2_assert(identical(branch_map$row_id, all_rows), "Selected branch map changed Full50 row order.")
  primary <- v2_build_primary_roles(context, all_rows, branch_map, downstream_pairs)
  deployment <- v2_build_deployment_roles(context, all_rows, branch_map, downstream_pairs)
  stress <- v2_build_standard_stress_assignments(context, validated$data, site_topology)
  diagnostics <- v2_fold_diagnostics(primary, deployment, stress, branches$diagnostics)
  branch_catalog <- merge(
    branches$catalog,
    site_topology[c("row_id", "reach_id", "connected_basin_id", "l12_id", "l6_id", "terminal_component_id", "is_backbone")],
    by = "row_id", sort = FALSE
  )
  branch_catalog <- branch_catalog[order(match(branch_catalog$row_id, all_rows), match(branch_catalog$scale, names(context$config$topology$scales))), , drop = FALSE]
  dir.create(v2_output_path(context, "folds_dir"), recursive = TRUE, showWarnings = FALSE)
  v2_write_csv(branch_catalog, paths[["branch_catalog"]])
  v2_write_csv(branches$relations, paths[["branch_relations"]])
  v2_write_csv(primary$outer, paths[["primary_outer"]])
  v2_write_csv(primary$inner, paths[["primary_inner"]])
  v2_write_csv(deployment, paths[["deployment"]])
  v2_write_csv(stress, paths[["stress"]])
  v2_write_csv(diagnostics, paths[["diagnostics"]])

  primary_manifest <- expand.grid(
    outer_fold = seq_len(as.integer(context$config$validation$outer_folds)),
    repeat_id = seq_len(as.integer(context$config$validation$repeats))
  )
  primary_manifest <- primary_manifest[order(primary_manifest$repeat_id, primary_manifest$outer_fold), ]
  primary_manifest$task_id <- seq_len(nrow(primary_manifest))
  primary_manifest <- primary_manifest[c("task_id", "repeat_id", "outer_fold")]
  stress_schemes <- c("terminal", paste0("spatial_", as.integer(unlist(context$config$validation$spatial_scales_km))), "reference")
  stress_manifest <- expand.grid(
    outer_fold = seq_len(as.integer(context$config$validation$outer_folds)),
    scheme = stress_schemes,
    stringsAsFactors = FALSE
  )
  stress_manifest <- stress_manifest[order(match(stress_manifest$scheme, stress_schemes), stress_manifest$outer_fold), ]
  stress_manifest$task_id <- seq_len(nrow(stress_manifest))
  stress_manifest <- stress_manifest[c("task_id", "scheme", "outer_fold")]
  primary_manifest_path <- v2_output_path(context, "validation_dir", "primary", "task_manifest.csv")
  stress_manifest_path <- v2_output_path(context, "validation_dir", "stress", "task_manifest.csv")
  v2_write_csv(primary_manifest, primary_manifest_path)
  v2_write_csv(stress_manifest, stress_manifest_path)

  primary_diag <- diagnostics[diagnostics$level == "primary_outer", , drop = FALSE]
  manifest <- list(
    status = "FOLDS_FROZEN_BEFORE_RESPONSE_EVALUATION",
    method = "Full50 ordinary RF with response-blind forward-reconstructed Purged-Branch CV",
    input = validated$signature,
    config = validated$config_signature,
    implementation = v2_implementation_signature(context),
    predictors = validated$predictors,
    topology = list(
      selected_scale = selected_scale,
      n_primary_branches = length(unique(branch_map$branch_id[branch_map$assessment_eligible])),
      n_primary_eligible_rows = sum(branch_map$assessment_eligible),
      selection_rule = context$config$topology$primary_selection$rule,
      response_used = FALSE,
      prepare_manifest_sha256 = v2_file_signature(interim_paths$prepare_manifest, context$repo_root)$sha256,
      scale_diagnostics = branches$diagnostics
    ),
    primary = list(
      repeats = as.integer(context$config$validation$repeats),
      outer_folds = as.integer(context$config$validation$outer_folds),
      inner_folds = as.integer(context$config$validation$inner_folds),
      expected_tasks = nrow(primary_manifest),
      assessment_range = range(primary_diag$n_assessment),
      downstream_purge_range = range(primary_diag$n_purged)
    ),
    deployment = list(
      folds = as.integer(context$config$validation$deployment_folds),
      candidates = 48L,
      role = "parameter selection only; not an unbiased benchmark"
    ),
    stress = list(schemes = stress_schemes, outer_folds = as.integer(context$config$validation$outer_folds), expected_tasks = nrow(stress_manifest), retuning = FALSE),
    fold_files = lapply(paths[names(paths) != "manifest"], v2_file_signature, relative_to = context$repo_root),
    prepared_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
  v2_write_json(manifest, paths[["manifest"]])
  v2_log(
    "V2 folds frozen: ", manifest$topology$n_primary_branches, " branches, ",
    manifest$topology$n_primary_eligible_rows, " eligible rows, 15 Primary and 25 stress tasks."
  )
  invisible(manifest)
}
