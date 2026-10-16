stage_fit_final_model <- function(context, run_id) {
  selected_path <- v1_run_dir(context, run_id, "models", "selected_params.yml")
  v1_assert(file.exists(selected_path), paste("Missing deployment-selected recipe:", selected_path))
  selected <- yaml::read_yaml(selected_path)
  recipe_md5 <- v1_recipe_md5(selected)
  v1_assert(identical(as.character(selected$recipe_md5), recipe_md5), "Selected recipe fingerprint is inconsistent.")
  v1_log("Fitting the single 4,000-tree Base V1 RF on all 4,485 rows.")
  validated <- v1_validate_input(context)
  dat <- validated$data
  predictors <- validated$predictors
  response <- context$config$columns$response
  x_raw <- v1_numeric_predictors(dat, predictors)
  medians <- v1_fit_medians(x_raw)
  x <- v1_apply_medians(x_raw, medians)
  trees <- as.integer(context$config$model$final_trees)
  seed <- as.integer(context$config$model$final_seed)
  model <- v1_fit_rf(x, dat[[response]], selected, trees, seed, v1_ranger_threads(context))
  fitted <- as.numeric(predict(model, data = x, num.threads = v1_ranger_threads(context))$predictions)
  sanity <- v1_calculate_metrics(dat[[response]], fitted)
  fold_manifest <- jsonlite::read_json(v1_fold_paths(context)[["manifest"]], simplifyVector = TRUE)
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
    hydrological_group_input_md5 = fold_manifest$hydrological_groups$md5,
    validation_method = list(
      primary = "355 MAIN_BAS systems; 3 repeats x 5 Outer; 5 grouped Inner folds",
      search = "48 coarse recipes at 500 trees; best 16 re-evaluated at 1000 trees; Outer at 2000 trees",
      deployment = "independent fixed-seed hydrological grouped 5-fold recipe selection",
      stress = "frozen recipe; 500/1000/1500 km and reference 5-fold; no retuning"
    ),
    runtime = v1_runtime_info(),
    training_fit_sanity = sanity,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
  models_dir <- v1_run_dir(context, run_id, "models")
  dir.create(models_dir, recursive = TRUE, showWarnings = FALSE)
  v1_save_rds(bundle, file.path(models_dir, "full50_rf_model.rds"))
  v1_write_csv(
    data.frame(feature = predictors, training_median = as.numeric(medians[predictors])),
    file.path(models_dir, "training_medians.csv")
  )
  v1_log("Final Base V1 model written: ", file.path(models_dir, "full50_rf_model.rds"))
  invisible(bundle)
}
