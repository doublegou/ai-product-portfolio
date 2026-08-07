source("R/functions/core.R")

check_packages(
  c(
    "dplyr",
    "readr",
    "tibble",
    "tidyr"
  )
)

root <- project_root()

feature_sets_file <- file.path(
  root,
  "outputs",
  "r50b_feature_architecture",
  "model_feature_sets.rds"
)

reference_design_file <- file.path(
  root,
  "outputs",
  "r51b_reference_validation",
  "reference_validation_design.rds"
)

out_dir <- file.path(
  root,
  "outputs",
  "r54_nested_reference_rf"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

required_files <- c(
  feature_sets_file,
  reference_design_file
)

missing_files <- required_files[
  !file.exists(required_files)
]

if (length(missing_files) > 0L) {
  stop(
    "Missing required files: ",
    paste(
      missing_files,
      collapse = ", "
    )
  )
}

feature_sets <- readRDS(
  feature_sets_file
)

reference_design <- readRDS(
  reference_design_file
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
    "Frozen feature-set sizes changed."
  )
}

if (
  is.null(
    reference_design$
      outer_reference_group_folds
  ) ||
  is.null(
    reference_design$
      inner_reference_group_folds
  )
) {
  stop(
    "R51b reference-validation design is incomplete."
  )
}

task_manifest <- tidyr::expand_grid(
  outer_fold =
    1:5,

  model_name =
    model_names
) |>
  dplyr::arrange(
    outer_fold,
    match(
      model_name,
      model_names
    )
  ) |>
  dplyr::mutate(
    task_id =
      dplyr::row_number(),

    validation_scheme =
      "reference_grouped_5fold",

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
    task_label,
    validation_scheme
  )

if (nrow(task_manifest) != 15L) {
  stop(
    "Expected 15 R54 tasks; found ",
    nrow(task_manifest)
  )
}

if (!identical(
  task_manifest$task_id,
  1:15
)) {
  stop(
    "R54 task IDs are not exactly 1:15."
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
  "R54 NESTED REFERENCE-GROUP RF TASK MANIFEST",
  "===========================================",
  "",
  paste0(
    "Tasks: ",
    nrow(task_manifest)
  ),
  "Outer reference-group folds: 5",
  "Inner reference-group folds: 3",
  "Models per outer fold: 3",
  "",
  "STATUS: R54 TASK MANIFEST PASSED"
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
