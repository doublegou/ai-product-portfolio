stage_fit_final_model <- function(context, run_id) {
  selected_path <- v2_run_dir(context, run_id, "models", "selected_params.yml")
  v2_assert(file.exists(selected_path), paste("Missing deployment-selected recipe:", selected_path))
  selected <- yaml::read_yaml(selected_path)
  recipe_md5 <- v2_recipe_md5(selected)
  v2_assert(identical(as.character(selected$recipe_md5), recipe_md5), "Selected recipe fingerprint is inconsistent.")
  v2_log("Fitting the single 4,000-tree Base V2 RF on all 4,485 rows.")
  validated <- v2_validate_input(context)
  dat <- validated$data
  predictors <- validated$predictors
  response <- context$config$columns$response
  x_raw <- v2_numeric_predictors(dat, predictors)
  medians <- v2_fit_medians(x_raw)
  x <- v2_apply_medians(x_raw, medians)
  trees <- as.integer(context$config$model$final_trees)
  seed <- as.integer(context$config$model$final_seed)
  model <- v2_fit_rf(x, dat[[response]], selected, trees, seed, v2_ranger_threads(context))
  fitted <- as.numeric(predict(model, data = x, num.threads = v2_ranger_threads(context))$predictions)
  sanity <- v2_calculate_metrics(dat[[response]], fitted)
  fold_manifest <- jsonlite::read_json(v2_fold_paths(context)[["manifest"]], simplifyVector = TRUE)
  bundle <- list(
    model_name = context$config$project$model_name,
    ranger_model = model,
    predictor_names = predictors,
    training_medians = medians,
    response_name = response,
    n_training_rows = nrow(dat),
    n_predictors = length(predictors),
    hyperparameters = list(
      num_trees = trees,
      mtry = as.integer(selected$mtry),
      min_node_size = as.integer(selected$min_node_size),
      sample_fraction = as.numeric(selected$sample_fraction),
      replace = as.logical(selected$replace),
      splitrule = "variance"
    ),
    recipe_md5 = recipe_md5,
    seed = seed,
    input = validated$signature,
    fold_manifest_sha256 = v2_file_signature(v2_fold_paths(context)[["manifest"]], context$repo_root)$sha256,
    topology = fold_manifest$topology,
    validation_method = list(
      primary = "forward-reconstructed Primary Purged-Branch; 3 repeats x 5 Outer; 5 nested Purged-Branch Inner folds",
      search = "48 coarse recipes at 500 trees; best 16 re-evaluated at 1000 trees; Outer at 2000 trees",
      deployment = "all 48 frozen recipes; independent fixed-seed Primary Purged-Branch 5-fold selection",
      stress = "frozen recipe; terminal, 500/1000/1500 km and reference 5-fold; no retuning"
    ),
    runtime = v2_runtime_info(),
    training_fit_sanity = sanity,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
  models_dir <- v2_run_dir(context, run_id, "models")
  dir.create(models_dir, recursive = TRUE, showWarnings = FALSE)
  v2_save_rds(bundle, file.path(models_dir, "full50_rf_model.rds"))
  v2_write_csv(
    data.frame(feature = predictors, training_median = as.numeric(medians[predictors])),
    file.path(models_dir, "training_medians.csv")
  )
  v2_log("Final Base V2 model written: ", file.path(models_dir, "full50_rf_model.rds"))
  invisible(bundle)
}
