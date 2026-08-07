required_packages <- c(
  "dplyr",
  "readr",
  "tibble"
)

missing_packages <- required_packages[
  !vapply(
    required_packages,
    requireNamespace,
    logical(1),
    quietly = TRUE
  )
]

if (length(missing_packages) > 0L) {
  stop(
    "Missing packages: ",
    paste(
      missing_packages,
      collapse = ", "
    )
  )
}

root <- normalizePath(
  getwd(),
  mustWork = TRUE
)

out_dir <- file.path(
  root,
  "outputs",
  "r58b_rds_asset_audit"
)

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

search_roots <- c(
  file.path(
    root,
    "data"
  ),
  file.path(
    root,
    "inputs"
  ),
  file.path(
    root,
    "derived_data"
  ),
  file.path(
    root,
    "outputs",
    "nrcan_age_hydrobasins_l6"
  ),
  file.path(
    root,
    "outputs",
    "predictor_inventory"
  ),
  file.path(
    root,
    "outputs",
    "verified_asset_inventory"
  ),
  file.path(
    root,
    "outputs",
    "legacy_asset_audit"
  ),
  file.path(
    root,
    "outputs",
    "reuse_audit"
  ),
  file.path(
    root,
    "outputs",
    "p1_reuse_build"
  )
)

search_roots <- search_roots[
  dir.exists(
    search_roots
  )
]

rds_files <- unique(
  unlist(
    lapply(
      search_roots,
      function(search_root) {
        list.files(
          search_root,
          pattern = "\\.[Rr][Dd][Ss]$",
          recursive = TRUE,
          full.names = TRUE
        )
      }
    )
  )
)

rds_files <- sort(
  rds_files
)

inspect_object <- function(path) {
  size_bytes <- file.info(path)$size

  result <- tryCatch(
    {
      object <- readRDS(path)

      object_class <- paste(
        class(object),
        collapse = ";"
      )

      n_rows <- NA_integer_
      n_columns <- NA_integer_
      column_names <- NA_character_
      list_names <- NA_character_

      if (
        is.data.frame(object) ||
        is.matrix(object)
      ) {
        n_rows <- nrow(object)
        n_columns <- ncol(object)

        column_names <- paste(
          names(object),
          collapse = "|"
        )
      } else if (
        is.list(object)
      ) {
        list_names <- paste(
          names(object),
          collapse = "|"
        )

        data_frame_elements <- names(object)[
          vapply(
            object,
            is.data.frame,
            logical(1)
          )
        ]

        if (length(data_frame_elements) > 0L) {
          element_sizes <- vapply(
            object[
              data_frame_elements
            ],
            nrow,
            integer(1)
          )

          largest_element <-
            data_frame_elements[
              which.max(
                element_sizes
              )
            ]

          n_rows <-
            nrow(
              object[[largest_element]]
            )

          n_columns <-
            ncol(
              object[[largest_element]]
            )

          column_names <- paste(
            names(
              object[[largest_element]]
            ),
            collapse = "|"
          )
        }
      }

      tibble::tibble(
        path =
          sub(
            paste0(
              "^",
              root,
              "/?"
            ),
            "",
            path
          ),

        size_bytes =
          size_bytes,

        size_mb =
          size_bytes /
          1024^2,

        status =
          "read_ok",

        object_class =
          object_class,

        n_rows =
          n_rows,

        n_columns =
          n_columns,

        column_names =
          column_names,

        list_names =
          list_names,

        error_message =
          NA_character_
      )
    },

    error = function(error) {
      tibble::tibble(
        path =
          sub(
            paste0(
              "^",
              root,
              "/?"
            ),
            "",
            path
          ),

        size_bytes =
          size_bytes,

        size_mb =
          size_bytes /
          1024^2,

        status =
          "read_failed",

        object_class =
          NA_character_,

        n_rows =
          NA_integer_,

        n_columns =
          NA_integer_,

        column_names =
          NA_character_,

        list_names =
          NA_character_,

        error_message =
          conditionMessage(error)
      )
    }
  )

  result
}

audit <- lapply(
  rds_files,
  inspect_object
) |>
  dplyr::bind_rows() |>
  dplyr::arrange(
    dplyr::desc(
      n_rows
    ),
    dplyr::desc(
      size_bytes
    ),
    path
  )

likely_global_tables <- audit |>
  dplyr::filter(
    status ==
      "read_ok",

    !is.na(
      n_rows
    ),

    n_rows >=
      100000L
  )

likely_predictor_tables <- audit |>
  dplyr::filter(
    status ==
      "read_ok",

    grepl(
      "HYRIV_ID|ORD_FLOW|UPLAND_SKM|DIS_AV_CMS|sp_x|up_geo",
      dplyr::coalesce(
        column_names,
        ""
      ),
      ignore.case = TRUE
    )
  )

readr::write_csv(
  audit,
  file.path(
    out_dir,
    "all_rds_assets.csv"
  )
)

readr::write_csv(
  likely_global_tables,
  file.path(
    out_dir,
    "likely_global_tables.csv"
  )
)

readr::write_csv(
  likely_predictor_tables,
  file.path(
    out_dir,
    "likely_predictor_tables.csv"
  )
)

summary_lines <- c(
  "R58B RDS ASSET STRUCTURE AUDIT",
  "==============================",
  "",
  paste0(
    "RDS files inspected: ",
    nrow(audit)
  ),
  paste0(
    "Successfully read: ",
    sum(
      audit$status ==
        "read_ok"
    )
  ),
  paste0(
    "Read failures: ",
    sum(
      audit$status ==
        "read_failed"
    )
  ),
  paste0(
    "Tables with >=100,000 rows: ",
    nrow(likely_global_tables)
  ),
  paste0(
    "Tables with predictor-like columns: ",
    nrow(likely_predictor_tables)
  ),
  "",
  "STATUS: R58B RDS ASSET AUDIT PASSED"
)

writeLines(
  summary_lines,
  file.path(
    out_dir,
    "run_summary.txt"
  )
)

cat(
  paste(
    summary_lines,
    collapse = "\n"
  ),
  "\n\n"
)

cat(
  "===== LIKELY GLOBAL TABLES =====\n"
)

print(
  likely_global_tables |>
    dplyr::select(
      path,
      size_mb,
      object_class,
      n_rows,
      n_columns
    ),
  n = Inf,
  width = Inf
)

cat(
  "\n===== LIKELY PREDICTOR TABLES =====\n"
)

print(
  likely_predictor_tables |>
    dplyr::select(
      path,
      size_mb,
      object_class,
      n_rows,
      n_columns
    ),
  n = Inf,
  width = Inf
)
