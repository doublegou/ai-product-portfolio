v1_fold_diagnostic_row <- function(dat, row_ids, level, scheme, repeat_id, outer_fold, inner_fold, validation_unit) {
  response <- dat$sr87_sr86[match(row_ids, dat$row_id)]
  data.frame(
    level = level,
    scheme = scheme,
    repeat_id = repeat_id,
    outer_fold = outer_fold,
    inner_fold = inner_fold,
    n_assessment = length(row_ids),
    n_units = length(unique(validation_unit)),
    n_ge_0_72 = sum(response >= 0.72),
    n_ge_0_75 = sum(response >= 0.75),
    n_ge_0_80 = sum(response >= 0.80),
    stringsAsFactors = FALSE
  )
}

stage_build_folds <- function(context, validated = NULL, force = FALSE) {
  paths <- v1_fold_paths(context)
  if (file.exists(paths[["manifest"]]) && !force) {
    v1_assert_folds_current(context)
    v1_log("Frozen V1 folds already match the data and config; preparation skipped.")
    return(invisible(jsonlite::read_json(paths[["manifest"]], simplifyVector = TRUE)))
  }
  validation_dir <- v1_output_path(context, "validation_dir")
  completed <- list.files(validation_dir, pattern = "task_info\\.json$", recursive = TRUE, full.names = TRUE)
  v1_assert(length(completed) == 0L, "Validation results exist. Archive them before rebuilding V1 folds.")
  if (is.null(validated)) validated <- stage_validate_input(context)
  dat <- validated$data
  columns <- context$config$columns
  dat$row_id <- as.character(dat[[columns$row_id]])
  dat$sr87_sr86 <- as.numeric(dat[[columns$response]])

  v1_log("Mapping Full50 L6 basins to HydroBASINS MAIN_BAS.")
  groups <- v1_build_hydrological_groups(dat, context)
  v1_log("Building 3 repeated hydrological Outer designs and 15 task-local Inner designs.")
  primary <- v1_build_primary_folds(groups, context)
  v1_log("Building independent hydrological deployment design.")
  deployment <- v1_build_deployment_folds(groups, context)
  v1_log("Building fixed 500/1000/1500 km and reference stress designs.")
  stress <- v1_build_stress_folds(dat, context)

  n <- nrow(dat)
  repeats <- as.integer(context$config$validation$repeats)
  outer_k <- as.integer(context$config$validation$outer_folds)
  inner_k <- as.integer(context$config$validation$inner_folds)
  stress_schemes <- c(paste0("spatial_", as.integer(unlist(context$config$validation$spatial_scales_km))), "reference")
  v1_assert(nrow(primary$outer) == n * repeats, "Primary Outer assignments have the wrong row count.")
  v1_assert(nrow(deployment) == n, "Deployment assignments have the wrong row count.")
  v1_assert(nrow(stress) == n * length(stress_schemes), "Stress assignments have the wrong row count.")
  v1_assert(all(primary$outer$outer_fold %in% seq_len(outer_k)), "Primary Outer fold is invalid.")
  v1_assert(all(primary$inner$inner_fold %in% seq_len(inner_k)), "Primary Inner fold is invalid.")
  v1_assert(all(deployment$deployment_fold %in% seq_len(as.integer(context$config$validation$deployment_folds))), "Deployment fold is invalid.")

  outer_unit_split <- stats::aggregate(outer_fold ~ repeat_id + validation_unit, primary$outer, function(x) length(unique(x)))
  v1_assert(all(outer_unit_split$outer_fold == 1L), "A MAIN_BAS group crosses a Primary Outer fold.")
  inner_unit_split <- stats::aggregate(inner_fold ~ repeat_id + outer_fold + validation_unit, primary$inner, function(x) length(unique(x)))
  v1_assert(all(inner_unit_split$inner_fold == 1L), "A MAIN_BAS group crosses a Primary Inner fold.")
  deployment_split <- stats::aggregate(deployment_fold ~ validation_unit, deployment, function(x) length(unique(x)))
  v1_assert(all(deployment_split$deployment_fold == 1L), "A MAIN_BAS group crosses a deployment fold.")
  stress_split <- stats::aggregate(outer_fold ~ scheme + validation_unit, stress, function(x) length(unique(x)))
  v1_assert(all(stress_split$outer_fold == 1L), "A stress validation unit crosses an Outer fold.")

  diagnostics <- list()
  diagnostic_index <- 0L
  for (repeat_id in seq_len(repeats)) {
    repeat_outer <- primary$outer[primary$outer$repeat_id == repeat_id, , drop = FALSE]
    v1_assert(setequal(repeat_outer$row_id, dat$row_id), paste("Primary repeat", repeat_id, "does not cover all rows."))
    for (outer_fold in seq_len(outer_k)) {
      outer_test <- repeat_outer[repeat_outer$outer_fold == outer_fold, , drop = FALSE]
      diagnostic_index <- diagnostic_index + 1L
      diagnostics[[diagnostic_index]] <- v1_fold_diagnostic_row(
        dat, outer_test$row_id, "primary_outer", "hydrological", repeat_id, outer_fold, NA_integer_, outer_test$validation_unit
      )
      inner <- primary$inner[primary$inner$repeat_id == repeat_id & primary$inner$outer_fold == outer_fold, , drop = FALSE]
      outer_train_ids <- setdiff(dat$row_id, outer_test$row_id)
      v1_assert(setequal(inner$row_id, outer_train_ids), paste("Inner design differs from Outer training rows:", repeat_id, outer_fold))
      v1_assert(setequal(unique(inner$inner_fold), seq_len(inner_k)), paste("Missing Inner fold:", repeat_id, outer_fold))
      for (inner_fold in seq_len(inner_k)) {
        current <- inner[inner$inner_fold == inner_fold, , drop = FALSE]
        diagnostic_index <- diagnostic_index + 1L
        diagnostics[[diagnostic_index]] <- v1_fold_diagnostic_row(
          dat, current$row_id, "primary_inner", "hydrological", repeat_id, outer_fold, inner_fold, current$validation_unit
        )
      }
    }
  }
  for (fold in seq_len(as.integer(context$config$validation$deployment_folds))) {
    current <- deployment[deployment$deployment_fold == fold, , drop = FALSE]
    diagnostic_index <- diagnostic_index + 1L
    diagnostics[[diagnostic_index]] <- v1_fold_diagnostic_row(
      dat, current$row_id, "deployment", "hydrological", NA_integer_, fold, NA_integer_, current$validation_unit
    )
  }
  for (scheme in stress_schemes) {
    current_scheme <- stress[stress$scheme == scheme, , drop = FALSE]
    v1_assert(setequal(current_scheme$row_id, dat$row_id), paste("Stress scheme does not cover all rows:", scheme))
    for (fold in seq_len(outer_k)) {
      current <- current_scheme[current_scheme$outer_fold == fold, , drop = FALSE]
      diagnostic_index <- diagnostic_index + 1L
      diagnostics[[diagnostic_index]] <- v1_fold_diagnostic_row(
        dat, current$row_id, "stress", scheme, NA_integer_, fold, NA_integer_, current$validation_unit
      )
    }
  }
  diagnostics <- do.call(rbind, diagnostics)
  diagnostics$n_analysis <- n - diagnostics$n_assessment
  diagnostics <- diagnostics[c(
    "level", "scheme", "repeat_id", "outer_fold", "inner_fold", "n_analysis", "n_assessment", "n_units",
    "n_ge_0_72", "n_ge_0_75", "n_ge_0_80"
  )]

  dir.create(v1_output_path(context, "folds_dir"), recursive = TRUE, showWarnings = FALSE)
  v1_write_csv(groups, paths[["groups"]])
  v1_write_csv(primary$outer, paths[["primary_outer"]])
  v1_write_csv(primary$inner, paths[["primary_inner"]])
  v1_write_csv(deployment, paths[["deployment"]])
  v1_write_csv(stress, paths[["stress"]])
  v1_write_csv(diagnostics, paths[["diagnostics"]])

  primary_manifest <- expand.grid(
    outer_fold = seq_len(outer_k), repeat_id = seq_len(repeats),
    KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE
  )
  primary_manifest <- primary_manifest[order(primary_manifest$repeat_id, primary_manifest$outer_fold), ]
  primary_manifest$task_id <- seq_len(nrow(primary_manifest))
  primary_manifest <- primary_manifest[c("task_id", "repeat_id", "outer_fold")]
  stress_manifest <- expand.grid(
    outer_fold = seq_len(outer_k), scheme = stress_schemes,
    KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE
  )
  stress_manifest <- stress_manifest[order(match(stress_manifest$scheme, stress_schemes), stress_manifest$outer_fold), ]
  stress_manifest$task_id <- seq_len(nrow(stress_manifest))
  stress_manifest <- stress_manifest[c("task_id", "scheme", "outer_fold")]
  dir.create(file.path(validation_dir, "primary"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(validation_dir, "stress"), recursive = TRUE, showWarnings = FALSE)
  v1_write_csv(primary_manifest, file.path(validation_dir, "primary", "task_manifest.csv"))
  v1_write_csv(stress_manifest, file.path(validation_dir, "stress", "task_manifest.csv"))

  group_signature <- v1_text_signature(paths[["groups"]])
  manifest <- list(
    status = "frozen",
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    input = validated$signature,
    config = validated$config_signature,
    hydrological_groups = group_signature,
    n_rows = n,
    n_predictors = validated$n_predictors,
    n_l6_basins = validated$n_l6_basins,
    n_hydrological_groups = length(unique(groups$hydrological_group)),
    predictors = validated$predictors,
    response = columns$response,
    primary = list(repeats = repeats, outer_folds = outer_k, inner_folds = inner_k, expected_tasks = nrow(primary_manifest)),
    deployment = list(folds = as.integer(context$config$validation$deployment_folds), role = "parameter selection only; not an unbiased benchmark"),
    stress = list(schemes = stress_schemes, outer_folds = outer_k, expected_tasks = nrow(stress_manifest), retuning = FALSE),
    assignment = "whole outcome-blind units greedily balanced by row count, with fixed seeded tie breaks",
    hydrological_definition = "HydroBASINS L6 HYBAS_ID joined to MAIN_BAS; MAIN_BAS is the indivisible group"
  )
  v1_write_json(manifest, paths[["manifest"]])
  v1_write_json(
    list(
      status = "prepared",
      input_md5 = validated$signature$md5,
      config_md5 = validated$config_signature$md5,
      primary_tasks = nrow(primary_manifest),
      stress_tasks = nrow(stress_manifest),
      stress_retuning = FALSE
    ),
    file.path(validation_dir, "validation_manifest.json")
  )
  v1_log("V1 folds frozen: 355 hydrological groups, 15 Primary tasks and 20 stress tasks.")
  invisible(manifest)
}
