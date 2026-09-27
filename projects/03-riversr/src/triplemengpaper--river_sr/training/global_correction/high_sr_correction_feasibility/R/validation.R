corr_expected_input_paths <- function(context) unlist(context$config$input, use.names = TRUE)

corr_validate_input <- function(context) {
  for (path in corr_expected_input_paths(context)) corr_assert_not_reference_path(context, path)
  config_text <- paste(readLines(context$config_path, warn = FALSE), collapse = "\n")
  corr_assert(!grepl("reference/", config_text, fixed = TRUE), "Correction config may not contain a reference/ dependency.")

  dat <- corr_read_training_data(context)
  columns <- context$config$columns
  required <- unlist(columns, use.names = FALSE)
  corr_assert(all(required %in% names(dat)), paste("Training table is missing columns:", paste(setdiff(required, names(dat)), collapse = ", ")))
  dat[[columns$row_id]] <- as.character(dat[[columns$row_id]])
  corr_assert(nrow(dat) == as.integer(context$config$validation$expected_rows), "Training row count changed.")
  corr_assert(!anyDuplicated(dat[[columns$row_id]]), "row_id is not unique.")
  corr_assert(all(is.finite(dat[[columns$response]])), "Response contains missing or non-finite values.")

  upstream <- corr_read_predictors(context, "upstream_full50_predictors")
  full50 <- corr_read_predictors(context, "full50_predictors")
  env47 <- corr_read_predictors(context, "env47_predictors")
  corr_assert(identical(full50, upstream), "Local Full50 manifest differs from the frozen upstream manifest.")
  corr_assert(length(full50) == as.integer(context$config$validation$expected_full50_predictors), "Full50 predictor count changed.")
  corr_assert(length(env47) == as.integer(context$config$validation$expected_env47_predictors), "Env47 predictor count changed.")
  spatial <- c("p0__sp_x", "p0__sp_y", "p0__sp_z")
  corr_assert(identical(env47, full50[!full50 %in% spatial]), "Env47 must be ordered Full50 minus exactly the three spatial coordinates.")
  corr_assert(all(full50 %in% names(dat)), "Training table is missing frozen predictors.")
  corr_numeric_frame(dat, full50)

  groups <- corr_read_table(corr_path(context, context$config$input$base_v1_hydrological_groups))
  groups$row_id <- as.character(groups$row_id); groups$hydrological_group <- as.character(groups$hydrological_group)
  corr_assert(nrow(groups) == nrow(dat) && !anyDuplicated(groups$row_id) && setequal(groups$row_id, dat[[columns$row_id]]), "Hydrological group map changed.")
  corr_assert(length(unique(groups$hydrological_group)) == as.integer(context$config$validation$expected_hydrological_groups), "Hydrological group count changed.")
  dat$.hydrological_group <- groups$hydrological_group[match(dat[[columns$row_id]], groups$row_id)]

  outer <- corr_read_table(corr_path(context, context$config$input$base_v1_outer_assignments))
  inner <- corr_read_table(corr_path(context, context$config$input$base_v1_inner_assignments))
  outer$row_id <- as.character(outer$row_id); inner$row_id <- as.character(inner$row_id)
  repeats <- as.integer(context$config$validation$repeats); outer_k <- as.integer(context$config$validation$outer_folds); inner_k <- as.integer(context$config$validation$inner_folds)
  corr_assert(nrow(outer) == nrow(dat) * repeats, "Outer assignment row count changed.")
  for (repeat_id in seq_len(repeats)) {
    design <- outer[outer$repeat_id == repeat_id, , drop = FALSE]
    corr_assert(nrow(design) == nrow(dat) && !anyDuplicated(design$row_id) && setequal(design$row_id, dat[[columns$row_id]]), paste("Outer coverage changed for repeat", repeat_id))
    corr_assert(identical(sort(unique(as.integer(design$outer_fold))), seq_len(outer_k)), "Outer fold labels changed.")
    group_folds <- tapply(design$outer_fold, design$validation_unit, function(x) length(unique(x)))
    corr_assert(all(group_folds == 1L), "A hydrological group crosses an Outer boundary.")
    for (outer_fold in seq_len(outer_k)) {
      test_ids <- design$row_id[design$outer_fold == outer_fold]
      train_ids <- setdiff(dat[[columns$row_id]], test_ids)
      nested <- inner[inner$repeat_id == repeat_id & inner$outer_fold == outer_fold, , drop = FALSE]
      corr_assert(nrow(nested) == length(train_ids) && !anyDuplicated(nested$row_id) && setequal(nested$row_id, train_ids), "Inner assignment does not cover exactly one Outer train.")
      corr_assert(identical(sort(unique(as.integer(nested$inner_fold))), seq_len(inner_k)), "Inner fold labels changed.")
      inner_group_folds <- tapply(nested$inner_fold, nested$validation_unit, function(x) length(unique(x)))
      corr_assert(all(inner_group_folds == 1L), "A hydrological group crosses an Inner boundary.")
    }
  }

  threshold <- as.numeric(context$config$oracle$elevated_lower)
  elevated <- dat[[columns$response]] >= threshold
  corr_assert(sum(elevated) == as.integer(context$config$validation$expected_elevated_rows), "Elevated row count changed.")
  corr_assert(length(unique(dat$.hydrological_group[elevated])) == as.integer(context$config$validation$expected_elevated_groups), "Elevated group count changed.")
  corr_assert(sum(dat[[columns$response]] >= as.numeric(context$config$oracle$high_lower)) == as.integer(context$config$validation$expected_high_rows), "High-Sr row count changed.")
  corr_assert(sum(dat[[columns$response]] >= as.numeric(context$config$oracle$extreme_lower)) == as.integer(context$config$validation$expected_extreme_rows), "Extreme-Sr row count changed.")

  selected <- yaml::read_yaml(corr_path(context, context$config$input$base_v1_selected_params))
  expected <- context$config$base_rf
  corr_assert(as.integer(selected$mtry) == as.integer(expected$mtry), "Frozen Base mtry changed.")
  corr_assert(as.integer(selected$min_node_size) == as.integer(expected$min_node_size), "Frozen Base min_node_size changed.")
  corr_assert(abs(as.numeric(selected$sample_fraction) - as.numeric(expected$sample_fraction)) < 1e-15, "Frozen Base sample_fraction changed.")
  corr_assert(identical(as.logical(selected$replace), as.logical(expected$replace)), "Frozen Base replace changed.")
  corr_assert(identical(as.character(selected$recipe_md5), as.character(expected$expected_recipe_md5)), "Frozen Base recipe MD5 changed.")
  release <- jsonlite::read_json(corr_path(context, context$config$input$base_v1_release_info), simplifyVector = TRUE)
  corr_assert(identical(as.character(release$status), "frozen"), "Base V1 release is not frozen.")

  list(data = dat, full50 = full50, env47 = env47, groups = groups, outer = outer, inner = inner,
       selected_base = selected, release = release)
}

corr_signature_bundle <- function(context) {
  keys <- names(context$config$input)
  stats::setNames(lapply(keys, function(key) corr_text_signature(corr_path(context, context$config$input[[key]]))), keys)
}

corr_assert_frozen_current <- function(context) {
  paths <- corr_fold_paths(context)
  corr_assert(all(file.exists(paths)), "Frozen correction manifests are missing; run --stage prepare locally.")
  manifest <- jsonlite::read_json(paths[["manifest"]], simplifyVector = FALSE)
  current_config <- corr_text_signature(context$config_path)
  corr_assert(identical(as.character(manifest$config$md5), as.character(current_config$md5)), "Correction config changed after prepare.")
  implementation <- corr_implementation_signature(context)
  corr_assert(identical(as.character(manifest$implementation$md5), as.character(implementation$md5)), "Correction implementation changed after prepare.")
  current <- corr_signature_bundle(context)
  for (key in names(current)) {
    corr_assert(identical(as.character(manifest$inputs[[key]]$md5), as.character(current[[key]]$md5)), paste("Frozen input changed:", key))
  }
  validated <- corr_validate_input(context)
  base_tasks <- corr_read_table(paths[["base_tasks"]])
  correction_tasks <- corr_read_table(paths[["correction_tasks"]])
  base_fit_plan <- corr_read_table(paths[["base_fit_plan"]])
  for (key in c("base", "correction", "base_fit_plan")) {
    file_key <- if (key == "base") "base_tasks" else if (key == "correction") "correction_tasks" else "base_fit_plan"
    signature <- corr_text_signature(paths[[file_key]])
    corr_assert(identical(as.character(manifest$task_manifests[[key]]$md5), as.character(signature$md5)), paste("Frozen task manifest changed:", key))
  }
  corr_assert(nrow(base_tasks) == as.integer(context$config$validation$expected_base_tasks), "Base task manifest must contain 15 tasks.")
  corr_assert(nrow(correction_tasks) == as.integer(context$config$validation$expected_correction_tasks), "Correction task manifest must contain 30 tasks.")
  corr_assert(nrow(base_fit_plan) == as.integer(context$config$validation$expected_unique_base_fits_total), "Base fit plan must contain 240 canonical fits.")
  corr_assert(!anyDuplicated(base_fit_plan[c("task_id", "fit_key")]), "Base fit plan canonical key is not unique.")
  corr_assert(identical(as.integer(base_tasks$task_id), seq_len(15L)), "Base task IDs must be exactly 1..15.")
  corr_assert(identical(as.integer(correction_tasks$correction_task_id), seq_len(30L)), "Correction task IDs must be exactly 1..30.")
  corr_assert(identical(as.character(correction_tasks$model), c(rep("elastic_net", 15L), rep("residual_rf", 15L))), "Correction task model ordering changed.")
  expected_pairs <- apply(t(utils::combn(seq_len(5L), 2L)), 1L, function(x) sprintf("pair_%02d_%02d", x[[1L]], x[[2L]]))
  for (task_id in seq_len(15L)) {
    plan <- base_fit_plan[base_fit_plan$task_id == task_id, , drop = FALSE]
    corr_assert(sum(plan$fit_type == "single_exclusion") == 5L && sum(plan$fit_type == "pair_exclusion") == 10L && sum(plan$fit_type == "outer_full") == 1L,
                paste("Base fit plan does not contain 5+10+1 fits for task", task_id))
    corr_assert(setequal(plan$fit_key[plan$fit_type == "pair_exclusion"], expected_pairs), paste("Canonical pair keys changed for task", task_id))
    corr_assert(!anyDuplicated(plan$seed), paste("Base fit seeds collide within task", task_id))
  }
  list(manifest = manifest, validated = validated, base_tasks = base_tasks, correction_tasks = correction_tasks, base_fit_plan = base_fit_plan)
}
