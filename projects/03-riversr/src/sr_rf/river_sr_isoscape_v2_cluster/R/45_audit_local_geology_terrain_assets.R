suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
})

# ============================================================
# 0. Configuration
# ============================================================

out_dir <-
  "outputs/r45_local_geology_terrain_asset_audit"

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

search_roots <- c(
  "data",
  "outputs"
)

code_roots <- c(
  "R",
  "slurm",
  "config"
)

# Avoid reading very large compressed R objects during an audit.
# Large files will still be listed, but their schemas will be
# inspected separately only after we decide they are necessary.

max_rds_size_mb <- 300
max_assets_to_inspect <- 150
max_vector_layers_to_inspect <- 5

# ============================================================
# 1. Search patterns
# ============================================================

module_patterns <- list(

  local_geology =
    paste0(
      "(",
      paste(
        c(
          "local[_-]?geo",
          "site[_-]?geo",
          "local[_-]?lith",
          "site[_-]?lith",
          "glim",
          "litholog",
          "lithology"
        ),
        collapse = "|"
      ),
      ")"
    ),

  upstream_geology =
    paste0(
      "(",
      paste(
        c(
          "up[_-]?geo",
          "upstream.*geo",
          "upstream.*lith",
          "hydrobasin",
          "hydrobasins",
          "hybas",
          "basin.*geo",
          "l6.*geo",
          "geo.*l6"
        ),
        collapse = "|"
      ),
      ")"
    ),

  geological_age =
    paste0(
      "(",
      paste(
        c(
          "geo.*age",
          "age.*geo",
          "nrcan",
          "macrostrat",
          "harland",
          "roxworld"
        ),
        collapse = "|"
      ),
      ")"
    ),

  terrain =
    paste0(
      "(",
      paste(
        c(
          "dem",
          "elev",
          "elevation",
          "slope",
          "relief",
          "rugged",
          "terrain",
          "topograph",
          "topo"
        ),
        collapse = "|"
      ),
      ")"
    ),

  glacier =
    paste0(
      "(",
      paste(
        c(
          "glacier",
          "glaci",
          "rgi",
          "ice",
          "snow"
        ),
        collapse = "|"
      ),
      ")"
    ),

  hydrology =
    paste0(
      "(",
      paste(
        c(
          "runoff",
          "discharge",
          "hydro",
          "precip",
          "flow",
          "et0",
          "aridity"
        ),
        collapse = "|"
      ),
      ")"
    )
)

# ============================================================
# 2. List project files
# ============================================================

all_paths <- unlist(
  lapply(
    search_roots,
    function(root) {

      if (!dir.exists(root)) {
        return(character(0))
      }

      list.files(
        root,
        recursive = TRUE,
        full.names = TRUE,
        include.dirs = FALSE
      )
    }
  ),
  use.names = FALSE
)

all_paths <- unique(
  all_paths
)

# Exclude outputs produced by this script itself.

all_paths <- all_paths[
  !grepl(
    "^outputs/r45_local_geology_terrain_asset_audit/",
    all_paths
  )
]

file_info <- file.info(
  all_paths
)

file_inventory <- data.frame(

  path =
    all_paths,

  extension =
    tolower(
      tools::file_ext(
        all_paths
      )
    ),

  size_bytes =
    file_info$size,

  size_mb =
    file_info$size /
    1024^2,

  modified =
    as.character(
      file_info$mtime
    ),

  stringsAsFactors =
    FALSE
)

write_csv(
  file_inventory,
  file.path(
    out_dir,
    "all_project_file_inventory.csv"
  )
)

# ============================================================
# 3. Match files to candidate modules
# ============================================================

module_file_matches <- list()
counter <- 1L

for (
  module_name in names(module_patterns)
) {

  pattern <-
    module_patterns[[module_name]]

  keep <- grepl(
    pattern,
    tolower(
      file_inventory$path
    ),
    perl = TRUE
  )

  if (
    any(keep)
  ) {

    module_file_matches[[
      counter
    ]] <- file_inventory[
      keep,
      ,
      drop = FALSE
    ] |>
      mutate(
        module =
          module_name
      ) |>
      select(
        module,
        everything()
      )

    counter <-
      counter + 1L
  }
}

module_file_matches <- bind_rows(
  module_file_matches
)

write_csv(
  module_file_matches,
  file.path(
    out_dir,
    "candidate_files_by_module.csv"
  )
)

# ============================================================
# 4. Assign asset role and priority score
# ============================================================

candidate_assets <- module_file_matches |>
  mutate(

    asset_role =
      case_when(

        grepl(
          "model_table|predictors_at_sites|site_predict",
          tolower(path)
        ) ~
          "site-level table",

        grepl(
          "hydrobasin|hybas|upstream|l6",
          tolower(path)
        ) ~
          "basin/upstream asset",

        extension %in%
          c(
            "tif",
            "tiff",
            "vrt"
          ) ~
          "raster source",

        extension %in%
          c(
            "gpkg",
            "shp",
            "geojson"
          ) ~
          "vector source",

        extension %in%
          c(
            "rds",
            "csv",
            "tsv",
            "parquet"
          ) ~
          "tabular/intermediate asset",

        TRUE ~
          "other"
      ),

    priority_score =

      5L *
      grepl(
        "local[_-]?geo|local[_-]?lith|site[_-]?geo|site[_-]?lith",
        tolower(path),
        perl = TRUE
      ) +

      4L *
      grepl(
        "glim|litholog|lithology",
        tolower(path),
        perl = TRUE
      ) +

      4L *
      grepl(
        "slope|relief|rugged|dem",
        tolower(path),
        perl = TRUE
      ) +

      3L *
      grepl(
        "predictor|model_table|hydrobasin|hybas|upstream|l6",
        tolower(path),
        perl = TRUE
      ) +

      2L *
      grepl(
        "elev|terrain|topo|glacier|rgi|runoff",
        tolower(path),
        perl = TRUE
      ) +

      1L *
      extension %in%
      c(
        "rds",
        "csv",
        "tsv",
        "gpkg",
        "shp",
        "tif",
        "tiff",
        "parquet"
      )
  ) |>
  arrange(
    desc(
      priority_score
    ),
    size_mb,
    path
  )

# A file can match several modules.
# Keep one unique row for schema selection.

unique_assets <- candidate_assets |>
  distinct(
    path,
    .keep_all = TRUE
  ) |>
  mutate(
    inspection_selected =
      row_number() <=
      max_assets_to_inspect
  )

write_csv(
  candidate_assets,
  file.path(
    out_dir,
    "candidate_asset_ranking_by_module.csv"
  )
)

write_csv(
  unique_assets,
  file.path(
    out_dir,
    "unique_candidate_asset_ranking.csv"
  )
)

# ============================================================
# 5. Helpers for schema inspection
# ============================================================

empty_field_table <- function() {

  data.frame(
    path =
      character(0),

    object_component =
      character(0),

    field =
      character(0),

    field_class =
      character(0),

    stringsAsFactors =
      FALSE
  )
}

make_summary_row <- function(
  path,
  status,
  object_class = NA_character_,
  n_rows = NA_real_,
  n_cols = NA_real_,
  n_layers = NA_real_,
  notes = NA_character_
) {

  data.frame(
    path =
      path,

    extension =
      tolower(
        tools::file_ext(
          path
        )
      ),

    status =
      status,

    object_class =
      object_class,

    n_rows =
      n_rows,

    n_cols =
      n_cols,

    n_layers =
      n_layers,

    notes =
      notes,

    stringsAsFactors =
      FALSE
  )
}

inspect_rds <- function(
  path,
  size_mb
) {

  if (
    size_mb >
    max_rds_size_mb
  ) {

    return(
      list(

        summary =
          make_summary_row(
            path = path,
            status = "SKIPPED_SIZE",
            notes = paste0(
              "RDS larger than ",
              max_rds_size_mb,
              " MB"
            )
          ),

        fields =
          empty_field_table()
      )
    )
  }

  obj <- tryCatch(
    readRDS(
      path
    ),
    error = function(e) e
  )

  if (
    inherits(
      obj,
      "error"
    )
  ) {

    return(
      list(

        summary =
          make_summary_row(
            path = path,
            status = "READ_ERROR",
            notes = conditionMessage(obj)
          ),

        fields =
          empty_field_table()
      )
    )
  }

  cls <- paste(
    class(obj),
    collapse = ";"
  )

  nr <- if (
    is.data.frame(obj) ||
    is.matrix(obj)
  ) {
    nrow(obj)
  } else {
    NA_real_
  }

  nc <- if (
    is.data.frame(obj) ||
    is.matrix(obj)
  ) {
    ncol(obj)
  } else {
    NA_real_
  }

  if (
    is.data.frame(obj) &&
    ncol(obj) == 0L
  ) {

    return(
      list(

        summary =
          make_summary_row(
            path = path,
            status = "OK_EMPTY_OBJECT",
            object_class = cls,
            n_rows = nrow(obj),
            n_cols = 0,
            notes = "Data frame has zero columns"
          ),

        fields =
          empty_field_table()
      )
    )
  }

  if (
    is.list(obj) &&
    !is.null(names(obj)) &&
    length(names(obj)) == 0L
  ) {

    return(
      list(

        summary =
          make_summary_row(
            path = path,
            status = "OK_EMPTY_OBJECT",
            object_class = cls,
            notes = "Named list has zero components"
          ),

        fields =
          empty_field_table()
      )
    )
  }

  if (
    is.data.frame(obj)
  ) {

    field_table <- data.frame(

      path =
        path,

      object_component =
        "main",

      field =
        names(obj),

      field_class =
        vapply(
          obj,
          function(x) {
            paste(
              class(x),
              collapse = ";"
            )
          },
          character(1)
        ),

      stringsAsFactors =
        FALSE
    )

  } else if (
    is.list(obj) &&
    !is.null(
      names(obj)
    )
  ) {

    field_table <- data.frame(

      path =
        path,

      object_component =
        "list",

      field =
        names(obj),

      field_class =
        vapply(
          obj,
          function(x) {
            paste(
              class(x),
              collapse = ";"
            )
          },
          character(1)
        ),

      stringsAsFactors =
        FALSE
    )

  } else {

    field_table <-
      empty_field_table()
  }

  list(

    summary =
      make_summary_row(
        path = path,
        status = "OK",
        object_class = cls,
        n_rows = nr,
        n_cols = nc,
        notes = if (
          is.list(obj)
        ) {
          paste0(
            "list length=",
            length(obj)
          )
        } else {
          NA_character_
        }
      ),

    fields =
      field_table
  )
}

inspect_delimited <- function(
  path,
  extension
) {

  obj <- tryCatch(

    if (
      extension ==
      "tsv"
    ) {

      read_tsv(
        path,
        n_max = 5,
        show_col_types = FALSE,
        progress = FALSE
      )

    } else {

      read_csv(
        path,
        n_max = 5,
        show_col_types = FALSE,
        progress = FALSE
      )
    },

    error = function(e) e
  )

  if (
    inherits(
      obj,
      "error"
    )
  ) {

    return(
      list(

        summary =
          make_summary_row(
            path = path,
            status = "READ_ERROR",
            notes = conditionMessage(obj)
          ),

        fields =
          empty_field_table()
      )
    )
  }

  if (
    ncol(obj) == 0L ||
    length(names(obj)) == 0L
  ) {

    return(
      list(

        summary =
          make_summary_row(
            path = path,
            status = "OK_EMPTY_HEADER",
            object_class = paste(
              class(obj),
              collapse = ";"
            ),
            n_rows = nrow(obj),
            n_cols = 0,
            notes = "Delimited file parsed with zero columns"
          ),

        fields =
          empty_field_table()
      )
    )
  }

  field_table <- data.frame(

    path =
      path,

    object_component =
      "main",

    field =
      names(obj),

    field_class =
      vapply(
        obj,
        function(x) {
          paste(
            class(x),
            collapse = ";"
          )
        },
        character(1)
      ),

    stringsAsFactors =
      FALSE
  )

  list(

    summary =
      make_summary_row(
        path = path,
        status = "OK_HEADER",
        object_class = paste(
          class(obj),
          collapse = ";"
        ),
        n_rows = nrow(obj),
        n_cols = ncol(obj),
        notes = "Read first five rows only"
      ),

    fields =
      field_table
  )
}

inspect_gpkg <- function(
  path
) {

  if (
    !requireNamespace(
      "sf",
      quietly = TRUE
    )
  ) {

    return(
      list(

        summary =
          make_summary_row(
            path = path,
            status = "PACKAGE_MISSING",
            notes = "sf unavailable"
          ),

        fields =
          empty_field_table()
      )
    )
  }

  layers <- tryCatch(
    sf::st_layers(
      path
    ),
    error = function(e) e
  )

  if (
    inherits(
      layers,
      "error"
    )
  ) {

    return(
      list(

        summary =
          make_summary_row(
            path = path,
            status = "READ_ERROR",
            notes = conditionMessage(layers)
          ),

        fields =
          empty_field_table()
      )
    )
  }

  layer_names <-
    layers$name

  selected_layers <- head(
    layer_names,
    max_vector_layers_to_inspect
  )

  field_tables <- list()

  for (
    layer_name in selected_layers
  ) {

    safe_layer <- gsub(
      '"',
      '""',
      layer_name,
      fixed = TRUE
    )

    query <- paste0(
      'SELECT * FROM "',
      safe_layer,
      '" LIMIT 1'
    )

    x <- tryCatch(
      sf::st_read(
        path,
        query = query,
        quiet = TRUE
      ),
      error = function(e) e
    )

    if (
      !inherits(
        x,
        "error"
      )
    ) {

      field_tables[[
        length(field_tables) + 1L
      ]] <- data.frame(

        path =
          path,

        object_component =
          layer_name,

        field =
          names(x),

        field_class =
          vapply(
            x,
            function(z) {
              paste(
                class(z),
                collapse = ";"
              )
            },
            character(1)
          ),

        stringsAsFactors =
          FALSE
      )
    }
  }

  field_table <- if (
    length(field_tables) > 0L
  ) {
    bind_rows(
      field_tables
    )
  } else {
    empty_field_table()
  }

  feature_counts <- tryCatch(
    paste(
      layers$features,
      collapse = ";"
    ),
    error = function(e) NA_character_
  )

  list(

    summary =
      make_summary_row(
        path = path,
        status = "OK",
        object_class = "GeoPackage",
        n_layers = length(layer_names),
        notes = paste0(
          "layers=",
          paste(
            layer_names,
            collapse = ";"
          ),
          " | features=",
          feature_counts
        )
      ),

    fields =
      field_table
  )
}

inspect_raster <- function(
  path
) {

  if (
    !requireNamespace(
      "terra",
      quietly = TRUE
    )
  ) {

    return(
      list(

        summary =
          make_summary_row(
            path = path,
            status = "PACKAGE_MISSING",
            notes = "terra unavailable"
          ),

        fields =
          empty_field_table()
      )
    )
  }

  r <- tryCatch(
    terra::rast(
      path
    ),
    error = function(e) e
  )

  if (
    inherits(
      r,
      "error"
    )
  ) {

    return(
      list(

        summary =
          make_summary_row(
            path = path,
            status = "READ_ERROR",
            notes = conditionMessage(r)
          ),

        fields =
          empty_field_table()
      )
    )
  }

  field_table <- data.frame(

    path =
      path,

    object_component =
      "raster",

    field =
      names(r),

    field_class =
      rep(
        "raster_layer",
        terra::nlyr(r)
      ),

    stringsAsFactors =
      FALSE
  )

  resolution_text <- paste(
    terra::res(r),
    collapse = " x "
  )

  list(

    summary =
      make_summary_row(
        path = path,
        status = "OK_METADATA",
        object_class = "SpatRaster",
        n_rows = terra::nrow(r),
        n_cols = terra::ncol(r),
        n_layers = terra::nlyr(r),
        notes = paste0(
          "resolution=",
          resolution_text,
          " | crs=",
          terra::crs(
            r,
            proj = TRUE
          )
        )
      ),

    fields =
      field_table
  )
}

inspect_asset <- function(
  path,
  size_mb
) {

  extension <- tolower(
    tools::file_ext(
      path
    )
  )

  if (
    extension ==
    "rds"
  ) {

    return(
      inspect_rds(
        path,
        size_mb
      )
    )
  }

  if (
    extension %in%
    c(
      "csv",
      "tsv"
    )
  ) {

    return(
      inspect_delimited(
        path,
        extension
      )
    )
  }

  if (
    extension ==
    "gpkg"
  ) {

    return(
      inspect_gpkg(
        path
      )
    )
  }

  if (
    extension %in%
    c(
      "tif",
      "tiff",
      "vrt"
    )
  ) {

    return(
      inspect_raster(
        path
      )
    )
  }

  list(

    summary =
      make_summary_row(
        path = path,
        status = "UNSUPPORTED_EXTENSION",
        notes = extension
      ),

    fields =
      empty_field_table()
  )
}

# ============================================================
# 6. Inspect selected candidate assets
# ============================================================

selected_assets <- unique_assets |>
  filter(
    inspection_selected
  )

inspection_summaries <- list()
inspection_fields <- list()

for (
  i in seq_len(
    nrow(selected_assets)
  )
) {

  path_i <-
    selected_assets$path[i]

  size_i <-
    selected_assets$size_mb[i]

  result <- inspect_asset(
    path_i,
    size_i
  )

  inspection_summaries[[
    length(inspection_summaries) + 1L
  ]] <- result$summary

  if (
    nrow(
      result$fields
    ) > 0L
  ) {

    inspection_fields[[
      length(inspection_fields) + 1L
    ]] <- result$fields
  }
}

asset_object_summary <- bind_rows(
  inspection_summaries
)

asset_field_inventory <- if (
  length(inspection_fields) > 0L
) {
  bind_rows(
    inspection_fields
  )
} else {
  empty_field_table()
}

write_csv(
  asset_object_summary,
  file.path(
    out_dir,
    "asset_object_summary.csv"
  )
)

write_csv(
  asset_field_inventory,
  file.path(
    out_dir,
    "asset_field_inventory.csv"
  )
)

# ============================================================
# 7. Find especially relevant fields
# ============================================================

field_pattern <- paste0(
  "(",
  paste(
    c(
      "local",
      "upstream",
      "up_geo",
      "lith",
      "carbonate",
      "plutonic",
      "metamorphic",
      "volcanic",
      "siliciclastic",
      "sedimentary",
      "evaporite",
      "unconsolidated",
      "slope",
      "relief",
      "rugged",
      "elev",
      "dem",
      "glacier",
      "runoff",
      "discharge",
      "hybas"
    ),
    collapse = "|"
  ),
  ")"
)

relevant_fields <- asset_field_inventory |>
  filter(
    grepl(
      field_pattern,
      tolower(field),
      perl = TRUE
    )
  ) |>
  arrange(
    path,
    object_component,
    field
  )

write_csv(
  relevant_fields,
  file.path(
    out_dir,
    "relevant_asset_fields.csv"
  )
)

# ============================================================
# 8. Scan source code for asset references
# ============================================================

code_paths <- unlist(
  lapply(
    code_roots,
    function(root) {

      if (!dir.exists(root)) {
        return(character(0))
      }

      list.files(
        root,
        recursive = TRUE,
        full.names = TRUE,
        pattern = "\\.(R|Rmd|r|sh|yml|yaml)$"
      )
    }
  ),
  use.names = FALSE
)

code_paths <- unique(
  code_paths
)

code_hits <- list()
counter <- 1L

for (
  code_path in code_paths
) {

  lines <- tryCatch(
    readLines(
      code_path,
      warn = FALSE
    ),
    error = function(e) character(0)
  )

  if (
    length(lines) == 0L
  ) {
    next
  }

  for (
    module_name in names(module_patterns)
  ) {

    pattern <-
      module_patterns[[module_name]]

    hit_index <- grep(
      pattern,
      tolower(lines),
      perl = TRUE
    )

    if (
      length(hit_index) == 0L
    ) {
      next
    }

    code_hits[[
      counter
    ]] <- data.frame(

      module =
        module_name,

      file =
        code_path,

      line_number =
        hit_index,

      text =
        trimws(
          substr(
            lines[
              hit_index
            ],
            1,
            500
          )
        ),

      stringsAsFactors =
        FALSE
    )

    counter <-
      counter + 1L
  }
}

source_code_hits <- bind_rows(
  code_hits
) |>
  distinct() |>
  arrange(
    module,
    file,
    line_number
  )

write_csv(
  source_code_hits,
  file.path(
    out_dir,
    "source_code_keyword_hits.csv"
  )
)

# ============================================================
# 9. Produce concise next-step candidate table
# ============================================================

next_step_candidates <- unique_assets |>
  filter(
    priority_score >= 3
  ) |>
  left_join(
    asset_object_summary |>
      select(
        path,
        inspection_status =
          status,
        object_class,
        n_rows,
        n_cols,
        n_layers,
        inspection_notes =
          notes
      ),
    by = "path"
  ) |>
  arrange(
    desc(
      priority_score
    ),
    asset_role,
    size_mb,
    path
  )

write_csv(
  next_step_candidates,
  file.path(
    out_dir,
    "next_step_asset_candidates.csv"
  )
)

# ============================================================
# 10. Terminal report helpers
# ============================================================

print_module_candidates <- function(
  module_name,
  n = 25L
) {

  cat(
    "\n===== ",
    toupper(module_name),
    " CANDIDATES =====\n",
    sep = ""
  )

  x <- candidate_assets |>
    filter(
      module ==
        module_name
    ) |>
    distinct(
      path,
      .keep_all = TRUE
    ) |>
    select(
      priority_score,
      asset_role,
      size_mb,
      extension,
      path
    ) |>
    arrange(
      desc(
        priority_score
      ),
      size_mb,
      path
    ) |>
    head(n)

  print(
    as.data.frame(x),
    row.names = FALSE
  )
}

# ============================================================
# 11. Terminal report
# ============================================================

cat(
  "\n========================================\n"
)

cat(
  "R45 LOCAL GEOLOGY / TERRAIN ASSET AUDIT\n"
)

cat(
  "========================================\n"
)

cat(
  "\n===== FILE COUNTS BY MODULE =====\n"
)

module_counts <- module_file_matches |>
  count(
    module,
    extension,
    name = "n_files"
  ) |>
  arrange(
    module,
    desc(
      n_files
    )
  )

print(
  as.data.frame(
    module_counts
  ),
  row.names = FALSE
)

print_module_candidates(
  "local_geology",
  30L
)

print_module_candidates(
  "upstream_geology",
  20L
)

print_module_candidates(
  "terrain",
  30L
)

print_module_candidates(
  "glacier",
  20L
)

print_module_candidates(
  "hydrology",
  20L
)

cat(
  "\n===== RELEVANT DISCOVERED FIELDS =====\n"
)

print(
  as.data.frame(
    head(
      relevant_fields,
      120
    )
  ),
  row.names = FALSE
)

cat(
  "\n===== TOP SOURCE-CODE REFERENCES =====\n"
)

print(
  as.data.frame(
    head(
      source_code_hits,
      120
    )
  ),
  row.names = FALSE
)

cat(
  "\n===== OUTPUT FILES =====\n"
)

print(
  list.files(
    out_dir,
    full.names = FALSE
  )
)

cat(
  "\n===== DONE =====\n"
)
