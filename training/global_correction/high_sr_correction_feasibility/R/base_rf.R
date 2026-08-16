corr_threads <- function(context) {
  value <- suppressWarnings(as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", unset = as.character(context$config$model$threads))))
  if (is.na(value) || value < 1L) 1L else value
}

corr_base_parameters <- function(context) list(
  mtry = as.integer(context$config$base_rf$mtry),
  min_node_size = as.integer(context$config$base_rf$min_node_size),
  sample_fraction = as.numeric(context$config$base_rf$sample_fraction),
  replace = as.logical(context$config$base_rf$replace)
)

corr_fit_ranger <- function(x, y, parameters, trees, seed, threads, splitrule = "variance") {
  ranger::ranger(
    x = x, y = as.numeric(y), num.trees = as.integer(trees), mtry = as.integer(parameters$mtry),
    min.node.size = as.integer(parameters$min_node_size), sample.fraction = as.numeric(parameters$sample_fraction),
    replace = as.logical(parameters$replace), splitrule = splitrule, importance = "none",
    num.threads = as.integer(threads), seed = as.integer(seed), write.forest = TRUE, verbose = FALSE
  )
}

corr_predict_ranger <- function(model, x, threads) as.numeric(predict(model, data = x, num.threads = as.integer(threads))$predictions)

corr_base_fit_predict <- function(dat, train_ids, predict_ids, predictors, context, seed) {
  columns <- context$config$columns
  train <- dat[match(train_ids, dat[[columns$row_id]]), , drop = FALSE]
  assessment <- dat[match(predict_ids, dat[[columns$row_id]]), , drop = FALSE]
  corr_assert(!anyNA(train[[columns$row_id]]) && !anyNA(assessment[[columns$row_id]]), "Base fit received unknown row IDs.")
  matrices <- corr_prepare_matrices(train, assessment, predictors, standardize = FALSE)
  model <- corr_fit_ranger(matrices$train, train[[columns$response]], corr_base_parameters(context),
                           as.integer(context$config$base_rf$trees), seed, corr_threads(context), "variance")
  predicted <- corr_predict_ranger(model, matrices$assessment, corr_threads(context))
  list(predicted = predicted, medians = matrices$medians)
}

corr_single_seed <- function(context, task_id, excluded_fold) {
  as.integer(context$config$base_rf$single_seed_base) + as.integer(task_id) * 10L + as.integer(excluded_fold)
}

corr_pair_seed <- function(context, task_id, excluded_low, excluded_high) {
  as.integer(context$config$base_rf$pair_seed_base) + as.integer(task_id) * 100L + as.integer(excluded_low) * 10L + as.integer(excluded_high)
}

corr_full_seed <- function(context, task_id) as.integer(context$config$base_rf$full_seed_base) + as.integer(task_id)

corr_fit_manifest_row <- function(task_id, fit_type, key, included, excluded, predicted, seed, medians, dat, context) {
  columns <- context$config$columns
  data.frame(
    task_id = task_id, fit_type = fit_type, fit_key = key,
    included_folds = paste(included, collapse = "+"), excluded_folds = paste(excluded, collapse = "+"),
    seed = seed, trees = as.integer(context$config$base_rf$trees),
    n_training_rows = length(dat[[columns$row_id]][dat$.inner_fold %in% included | fit_type == "outer_full"]),
    n_prediction_rows = length(predicted),
    training_rows_md5 = corr_ids_md5(dat[[columns$row_id]][dat$.inner_fold %in% included | fit_type == "outer_full"]),
    training_groups_md5 = corr_ids_md5(dat$.hydrological_group[dat$.inner_fold %in% included | fit_type == "outer_full"]),
    prediction_rows_md5 = corr_ids_md5(predicted),
    medians_md5 = digest::digest(paste(names(medians), format(medians, digits = 17), collapse = "\n"), algo = "md5", serialize = FALSE),
    stringsAsFactors = FALSE
  )
}

corr_run_base_task <- function(context, task_id, force = FALSE) {
  frozen <- corr_assert_frozen_current(context)
  task_id <- as.integer(task_id)
  task <- frozen$base_tasks[frozen$base_tasks$task_id == task_id, , drop = FALSE]
  corr_assert(nrow(task) == 1L, "Base task ID must resolve to exactly one task in 1..15.")
  repeat_id <- as.integer(task$repeat_id); outer_fold <- as.integer(task$outer_fold)
  output_dir <- corr_base_task_dir(context, repeat_id, outer_fold)
  if (corr_base_task_complete(output_dir) && !force) {
    info <- jsonlite::read_json(file.path(output_dir, "task_info.json"), simplifyVector = TRUE)
    corr_assert(identical(as.character(info$config_md5), as.character(frozen$manifest$config$md5)), "Existing Base task used another config.")
    corr_assert(identical(as.character(info$implementation_md5), as.character(frozen$manifest$implementation$md5)), "Existing Base task used another implementation.")
    corr_log("Base task already complete; skipped: ", task_id, ".")
    return(invisible(info))
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  options(river_sr.correction.log_file = file.path(output_dir, "run.log"))
  dat <- frozen$validated$data; columns <- context$config$columns; predictors <- frozen$validated$full50
  outer_design <- frozen$validated$outer[frozen$validated$outer$repeat_id == repeat_id, , drop = FALSE]
  outer_test_ids <- as.character(outer_design$row_id[outer_design$outer_fold == outer_fold])
  outer_train_ids <- setdiff(as.character(dat[[columns$row_id]]), outer_test_ids)
  inner <- frozen$validated$inner[frozen$validated$inner$repeat_id == repeat_id & frozen$validated$inner$outer_fold == outer_fold, , drop = FALSE]
  corr_assert(setequal(inner$row_id, outer_train_ids), "Base task Inner assignment differs from Outer train.")
  outer_train <- dat[match(outer_train_ids, dat[[columns$row_id]]), , drop = FALSE]
  outer_train$.inner_fold <- as.integer(inner$inner_fold[match(outer_train[[columns$row_id]], inner$row_id)])
  outer_test <- dat[match(outer_test_ids, dat[[columns$row_id]]), , drop = FALSE]
  outer_test$.inner_fold <- NA_integer_
  inner_k <- as.integer(context$config$validation$inner_folds)
  fit_manifest <- list(); medians_records <- list(); single_records <- list(); pair_records <- list(); index <- 0L
  corr_log("Base task ", task_id, ": fitting five single-exclusion Base models.")
  for (excluded in seq_len(inner_k)) {
    train_ids <- outer_train[[columns$row_id]][outer_train$.inner_fold != excluded]
    predict_ids <- outer_train[[columns$row_id]][outer_train$.inner_fold == excluded]
    seed <- corr_single_seed(context, task_id, excluded)
    result <- corr_base_fit_predict(outer_train, train_ids, predict_ids, predictors, context, seed)
    assessment <- outer_train[match(predict_ids, outer_train[[columns$row_id]]), , drop = FALSE]
    index <- index + 1L
    single_records[[index]] <- data.frame(
      task_id = task_id, repeat_id = repeat_id, outer_fold = outer_fold, excluded_fold = excluded,
      row_id = predict_ids, row_inner_fold = excluded, site_id = assessment[[columns$site_id]],
      hydrological_group = assessment$.hydrological_group, longitude = assessment[[columns$longitude]], latitude = assessment[[columns$latitude]],
      reference_id = assessment[[columns$reference]], observed = assessment[[columns$response]],
      base_prediction = result$predicted, prediction_error = result$predicted - assessment[[columns$response]],
      residual_observed = assessment[[columns$response]] - result$predicted, seed = seed, stringsAsFactors = FALSE
    )
    fit_manifest[[length(fit_manifest) + 1L]] <- corr_fit_manifest_row(task_id, "single_exclusion", sprintf("single_%02d", excluded),
      setdiff(seq_len(inner_k), excluded), excluded, predict_ids, seed, result$medians, outer_train, context)
    medians_records[[length(medians_records) + 1L]] <- data.frame(task_id = task_id, fit_key = sprintf("single_%02d", excluded),
      feature = predictors, training_median = as.numeric(result$medians[predictors]), stringsAsFactors = FALSE)
  }
  standard_oof <- do.call(rbind, single_records)
  corr_assert(nrow(standard_oof) == nrow(outer_train) && !anyDuplicated(standard_oof$row_id) && setequal(standard_oof$row_id, outer_train_ids), "Single-exclusion Base OOF is incomplete.")

  corr_log("Base task ", task_id, ": fitting ten canonical pair-exclusion Base models.")
  pair_index <- 0L
  for (low in seq_len(inner_k - 1L)) for (high in seq.int(low + 1L, inner_k)) {
    train_folds <- setdiff(seq_len(inner_k), c(low, high))
    train_ids <- outer_train[[columns$row_id]][outer_train$.inner_fold %in% train_folds]
    predict_ids <- outer_train[[columns$row_id]][outer_train$.inner_fold %in% c(low, high)]
    seed <- corr_pair_seed(context, task_id, low, high)
    result <- corr_base_fit_predict(outer_train, train_ids, predict_ids, predictors, context, seed)
    assessment <- outer_train[match(predict_ids, outer_train[[columns$row_id]]), , drop = FALSE]
    pair_index <- pair_index + 1L
    pair_records[[pair_index]] <- data.frame(
      task_id = task_id, repeat_id = repeat_id, outer_fold = outer_fold,
      excluded_fold_low = low, excluded_fold_high = high, predicted_fold = assessment$.inner_fold,
      row_id = predict_ids, observed = assessment[[columns$response]], base_prediction = result$predicted,
      prediction_error = result$predicted - assessment[[columns$response]], residual_observed = assessment[[columns$response]] - result$predicted,
      seed = seed, stringsAsFactors = FALSE
    )
    key <- sprintf("pair_%02d_%02d", low, high)
    fit_manifest[[length(fit_manifest) + 1L]] <- corr_fit_manifest_row(task_id, "pair_exclusion", key,
      train_folds, c(low, high), predict_ids, seed, result$medians, outer_train, context)
    medians_records[[length(medians_records) + 1L]] <- data.frame(task_id = task_id, fit_key = key,
      feature = predictors, training_median = as.numeric(result$medians[predictors]), stringsAsFactors = FALSE)
  }
  pair_predictions <- do.call(rbind, pair_records)
  corr_assert(length(unique(paste(pair_predictions$excluded_fold_low, pair_predictions$excluded_fold_high))) == 10L, "Pair-exclusion fit count is not ten.")

  corr_log("Base task ", task_id, ": fitting complete Outer-train Base model.")
  full_seed <- corr_full_seed(context, task_id)
  full_result <- corr_base_fit_predict(rbind(outer_train, outer_test), outer_train_ids, outer_test_ids, predictors, context, full_seed)
  outer_predictions <- data.frame(
    task_id = task_id, repeat_id = repeat_id, outer_fold = outer_fold,
    row_id = outer_test[[columns$row_id]], site_id = outer_test[[columns$site_id]], hydrological_group = outer_test$.hydrological_group,
    longitude = outer_test[[columns$longitude]], latitude = outer_test[[columns$latitude]], reference_id = outer_test[[columns$reference]],
    observed = outer_test[[columns$response]], base_prediction = full_result$predicted,
    prediction_error = full_result$predicted - outer_test[[columns$response]], residual_observed = outer_test[[columns$response]] - full_result$predicted,
    oracle_elevated = outer_test[[columns$response]] >= as.numeric(context$config$oracle$elevated_lower), seed = full_seed,
    stringsAsFactors = FALSE
  )
  outer_for_manifest <- rbind(outer_train, outer_test); outer_for_manifest$.inner_fold <- ifelse(is.na(outer_for_manifest$.inner_fold), 0L, outer_for_manifest$.inner_fold)
  fit_manifest[[length(fit_manifest) + 1L]] <- data.frame(
    task_id = task_id, fit_type = "outer_full", fit_key = "outer_full", included_folds = paste(seq_len(inner_k), collapse = "+"), excluded_folds = "outer_test",
    seed = full_seed, trees = as.integer(context$config$base_rf$trees), n_training_rows = nrow(outer_train), n_prediction_rows = nrow(outer_test),
    training_rows_md5 = corr_ids_md5(outer_train_ids), prediction_rows_md5 = corr_ids_md5(outer_test_ids),
    training_groups_md5 = corr_ids_md5(outer_train$.hydrological_group),
    medians_md5 = digest::digest(paste(names(full_result$medians), format(full_result$medians, digits = 17), collapse = "\n"), algo = "md5", serialize = FALSE),
    stringsAsFactors = FALSE
  )
  medians_records[[length(medians_records) + 1L]] <- data.frame(task_id = task_id, fit_key = "outer_full", feature = predictors,
    training_median = as.numeric(full_result$medians[predictors]), stringsAsFactors = FALSE)

  context_records <- vector("list", inner_k)
  for (assessment_fold in seq_len(inner_k)) {
    pieces <- vector("list", inner_k)
    for (row_fold in seq_len(inner_k)) {
      ids <- outer_train[[columns$row_id]][outer_train$.inner_fold == row_fold]
      if (row_fold == assessment_fold) {
        source <- standard_oof[match(ids, standard_oof$row_id), , drop = FALSE]
        low <- NA_integer_; high <- NA_integer_; source_type <- "single_exclusion"; role <- "correction_assessment"
      } else {
        low <- min(row_fold, assessment_fold); high <- max(row_fold, assessment_fold)
        candidates <- pair_predictions[pair_predictions$excluded_fold_low == low & pair_predictions$excluded_fold_high == high, , drop = FALSE]
        source <- candidates[match(ids, candidates$row_id), , drop = FALSE]
        source_type <- "pair_exclusion"; role <- "correction_train"
      }
      corr_assert(!anyNA(source$row_id) && identical(as.character(source$row_id), as.character(ids)), "Context-specific Base prediction join failed.")
      original <- outer_train[match(ids, outer_train[[columns$row_id]]), , drop = FALSE]
      pieces[[row_fold]] <- data.frame(
        task_id = task_id, repeat_id = repeat_id, outer_fold = outer_fold, correction_assessment_fold = assessment_fold,
        row_id = ids, row_inner_fold = row_fold, role = role, base_source_type = source_type,
        excluded_fold_low = low, excluded_fold_high = high, base_prediction = source$base_prediction,
        observed = original[[columns$response]], residual_observed = original[[columns$response]] - source$base_prediction,
        hydrological_group = original$.hydrological_group,
        oracle_elevated = original[[columns$response]] >= as.numeric(context$config$oracle$elevated_lower), stringsAsFactors = FALSE
      )
    }
    context_records[[assessment_fold]] <- do.call(rbind, pieces)
  }
  meta <- do.call(rbind, context_records)
  corr_assert(nrow(meta) == nrow(outer_train) * inner_k, "Context-specific meta-feature artifact has wrong size.")
  corr_assert(!anyDuplicated(meta[c("correction_assessment_fold", "row_id")]), "Context-specific meta-feature key is not unique.")
  corr_assert(all(meta$role == ifelse(meta$row_inner_fold == meta$correction_assessment_fold, "correction_assessment", "correction_train")), "Context roles are inconsistent.")
  standard_oof$oracle_elevated <- standard_oof$observed >= as.numeric(context$config$oracle$elevated_lower)

  manifest_frame <- do.call(rbind, fit_manifest)
  corr_assert(nrow(manifest_frame) == as.integer(context$config$validation$expected_unique_base_fits_per_outer), "Base task did not produce exactly 16 unique fits.")
  corr_write_csv(manifest_frame, file.path(output_dir, "base_fit_manifest.csv"))
  corr_write_csv(standard_oof, file.path(output_dir, "outer_train_base_oof.csv"))
  corr_write_csv(outer_predictions, file.path(output_dir, "outer_test_base_predictions.csv"))
  corr_write_csv(pair_predictions, file.path(output_dir, "nested_pair_base_predictions.csv"))
  corr_write_csv(meta, file.path(output_dir, "correction_inner_meta_features.csv"))
  corr_write_csv(do.call(rbind, medians_records), file.path(output_dir, "training_medians.csv"))
  info <- list(
    status = "complete", task_id = task_id, repeat_id = repeat_id, outer_fold = outer_fold,
    n_outer_train = nrow(outer_train), n_outer_test = nrow(outer_test), unique_base_fits = nrow(manifest_frame),
    single_exclusion_fits = sum(manifest_frame$fit_type == "single_exclusion"),
    pair_exclusion_fits = sum(manifest_frame$fit_type == "pair_exclusion"), full_outer_fits = sum(manifest_frame$fit_type == "outer_full"),
    context_specific_rows = nrow(meta), config_md5 = frozen$manifest$config$md5,
    implementation_md5 = frozen$manifest$implementation$md5,
    fold_manifest_md5 = corr_text_signature(corr_fold_paths(context)[["manifest"]])$md5,
    completed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"), runtime = corr_runtime_info()
  )
  corr_write_json(info, file.path(output_dir, "task_info.json"))
  corr_log("Base task ", task_id, " complete with 16 unique Base fits.")
  invisible(info)
}
