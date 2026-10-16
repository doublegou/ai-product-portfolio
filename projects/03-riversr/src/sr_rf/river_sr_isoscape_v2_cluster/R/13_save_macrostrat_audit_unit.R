suppressPackageStartupMessages({
  library(sf)
})

input_path <- file.path(
  "data/raw/geology/macrostrat_map_audit",
  "map_3189448_bare.geojson"
)

output_gpkg <- file.path(
  "data/raw/geology/macrostrat_map_audit",
  "map_3189448.gpkg"
)

output_rds <- file.path(
  "data/raw/geology/macrostrat_map_audit",
  "map_3189448_full.rds"
)

encoding_note <- file.path(
  "outputs/macrostrat_map_audit",
  "map_3189448_list_column_encoding.txt"
)

if (!file.exists(input_path)) {
  stop(
    "Missing input GeoJSON: ",
    input_path
  )
}

dir.create(
  dirname(output_gpkg),
  recursive = TRUE,
  showWarnings = FALSE
)

dir.create(
  dirname(encoding_note),
  recursive = TRUE,
  showWarnings = FALSE
)

x <- st_read(
  input_path,
  quiet = TRUE
)

if (nrow(x) == 0L) {
  stop("Input GeoJSON contains no features.")
}

sf_column <- attr(
  x,
  "sf_column"
)

list_columns <- names(x)[
  vapply(
    x,
    is.list,
    logical(1)
  )
]

# Geometry is internally a list-column but must remain untouched.
attribute_list_columns <- setdiff(
  list_columns,
  sf_column
)

collapse_list_value <- function(value) {
  if (
    is.null(value) ||
    length(value) == 0L
  ) {
    return(NA_character_)
  }

  flattened <- unlist(
    value,
    recursive = TRUE,
    use.names = FALSE
  )

  flattened <- flattened[
    !is.na(flattened)
  ]

  if (length(flattened) == 0L) {
    return(NA_character_)
  }

  paste(
    as.character(flattened),
    collapse = ";"
  )
}

# Preserve the untouched object, including native list-columns.
saveRDS(
  x,
  output_rds
)

x_gpkg <- x

for (column_name in attribute_list_columns) {
  x_gpkg[[column_name]] <- vapply(
    x_gpkg[[column_name]],
    collapse_list_value,
    character(1)
  )
}

st_write(
  x_gpkg,
  output_gpkg,
  layer = "geologic_unit",
  delete_dsn = TRUE,
  quiet = TRUE
)

writeLines(
  c(
    "Macrostrat map-unit export",
    paste0("Input: ", input_path),
    paste0("Full R object: ", output_rds),
    paste0("GeoPackage: ", output_gpkg),
    "",
    "List-columns converted to semicolon-delimited text:",
    if (
      length(attribute_list_columns) > 0L
    ) {
      paste0(
        "- ",
        attribute_list_columns
      )
    } else {
      "- none"
    },
    "",
    "The full RDS preserves the original list-column structure."
  ),
  encoding_note
)

cat("Feature count:", nrow(x_gpkg), "\n")
cat("Geometry:", paste(unique(st_geometry_type(x_gpkg)), collapse = ", "), "\n")
cat(
  "Converted list-columns:",
  paste(attribute_list_columns, collapse = ", "),
  "\n"
)
cat("Saved full RDS:", output_rds, "\n")
cat("Saved GeoPackage:", output_gpkg, "\n")
