source("R/functions/core.R")

check_packages(
  c(
    "dplyr",
    "readr",
    "tidyr",
    "tibble"
  )
)

root <- project_root()

feature_sets_file <- file.path(
  root,
  "outputs",
  "r50b_feature_architecture",
  "model_feature_sets.rds"
)

validation_file <- file.path(
  root,
  "outputs",
  "r51a_validation_design",
  "validation_design.rds"
)

out_dir <- file.path(
  root,
  "outputs",
  "r52_nested_spatial_rf"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

feature_sets <- readRDS(
  feature_sets_file
)

validation_design <- readRDS(
  validation_file
)

model_names <- c(
  "M0_P0_FULL",
  "M_CORE_MECHANISTIC",
  "M_FULL_MECHANISTIC"
)

expected_sizes <- c(
  M0_P0_FULL = 28L,
  M_CORE_MECHANISTIC = 42L,
  M_FULL_MECHANISTIC = 50L
)

observed_sizes <- vapply(
  model_names,
  function(model_name) {
    length(
      feature_sets[[model_name]]
    )
  },
  integer(1)
)

if (!identical(
  observed_sizes,
  expected_sizes
)) {
  stop(
    "Frozen model feature-set sizes changed."
  )
}

validation_schemes <- paste0(
  "spatial_",
  validation_design$spatial_scales_km,
  "km"
)

task_manifest <- tidyr::expand_grid(
  validation_scheme =
    validation_schemes,

  outer_fold =
    1:5,

  model_name =
    model_names
) |>
  dplyr::arrange(
    validation_scheme,
    outer_fold,
    match(
      model_name,
      model_names
    )
  ) |>
  dplyr::mutate(
    task_id =
      dplyr::row_number(),

    n_features =
      observed_sizes[
        model_name
      ],

    task_label =
      paste(
        validation_scheme,
        paste0(
          "fold",
          outer_fold
        ),
        model_name,
        sep = "__"
      )
  ) |>
  dplyr::relocate(
    task_id,
    task_label
  )

if (nrow(task_manifest) != 45L) {
  stop(
    "Expected 45 tasks; found ",
    nrow(task_manifest)
  )
}

if (
  !identical(
    task_manifest$task_id,
    1:45
  )
) {
  stop(
    "Task IDs are not exactly 1:45."
  )
}

readr::write_csv(
  task_manifest,
  file.path(
    out_dir,
    "task_manifest.csv"
  )
)

saveRDS(
  task_manifest,
  file.path(
    out_dir,
    "task_manifest.rds"
  ),
  version = 3
)

summary_lines <- c(
  "R52A NESTED SPATIAL RF TASK MANIFEST",
  "====================================",
  "",
  paste0(
    "Tasks: ",
    nrow(task_manifest)
  ),
  paste0(
    "Validation schemes: ",
    paste(
      validation_schemes,
      collapse = ", "
    )
  ),
  "Outer folds per scheme: 5",
  "Models per fold: 3",
  "",
  "STATUS: R52A TASK MANIFEST PASSED"
)

writeLines(
  summary_lines,
  file.path(
    out_dir,
    "task_manifest_summary.txt"
  )
)

cat(
  paste(
    summary_lines,
    collapse = "\n"
  ),
  "\n"
)
