stage_fit_final_model <- function(context, run_id, selected_params = NULL) {
  models_dir <- v0_run_dir(context, run_id, "models")
  if (is.null(selected_params)) {
    path <- file.path(models_dir, "selected_params.yml")
    v0_assert(file.exists(path), paste("Missing consensus parameters:", path))
    selected_params <- yaml::read_yaml(path)
  }
  v0_log("Fitting the single Full50 final RF on all training rows.")
  validated <- v0_validate_input(context)
  dat <- validated$data
  predictors <- validated$predictors
  response <- context$config$columns$response
  x_raw <- v0_numeric_predictors(dat, predictors)
  medians <- v0_fit_medians(x_raw)
  x <- v0_apply_medians(x_raw, medians)
  trees <- as.integer(context$config$model$final_trees)
  seed <- as.integer(context$config$model$final_seed)
  model <- v0_fit_rf(
    x, dat[[response]], selected_params, trees, seed,
    v0_ranger_threads(context), write_forest = TRUE
  )
  fitted <- as.numeric(predict(model, data = x, num.threads = v0_ranger_threads(context))$predictions)
  sanity <- v0_calculate_metrics(dat[[response]], fitted)
  fold_manifest <- jsonlite::read_json(
    v0_output_path(context, "folds_dir", "fold_manifest.json"), simplifyVector = TRUE
  )
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
      mtry = as.integer(selected_params$mtry),
      min_node_size = as.integer(selected_params$min_node_size),
      sample_fraction = as.numeric(selected_params$sample_fraction),
      replace = FALSE,
      consensus_task_support = as.integer(selected_params$n_tasks_supporting)
    ),
    seed = seed,
    input = validated$signature,
    fold_input_md5 = fold_manifest$input$md5,
    validation_method = list(
      primary_performance = context$config$validation$primary_scheme,
      final_parameter_consensus = "500/1000/1500 km, 15 spatial outer tasks",
      reference_role = "stress validation only"
    ),
    training_fit_sanity = sanity,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
  )
  model_path <- file.path(models_dir, "full50_rf_model.rds")
  v0_save_rds(bundle, model_path)
  v0_write_csv(
    data.frame(feature = predictors, training_median = as.numeric(medians[predictors])),
    file.path(models_dir, "training_medians.csv")
  )
  v0_log("Final Full50 RF written: ", model_path)
  invisible(bundle)
}
