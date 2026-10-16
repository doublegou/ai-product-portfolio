suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tibble)
})

# ============================================================
# 0. Paths
# ============================================================

out_dir <- "outputs/predictor_inventory_audit"

dir.create(
  out_dir,
  recursive = TRUE,
  showWarnings = FALSE
)

sources <- c(
  p0_full =
    "data/processed/model_table_p0_full_range.rds",

  age_test =
    "data/processed/model_table_age_test.rds",

  site_predictors_full =
    "data/external/predictors_at_sites_full_range.rds"
)

# ============================================================
# 1. Helper: summarize one data frame
# ============================================================

summarise_columns <- function(dat, source_name, source_path) {

  if (!is.data.frame(dat)) {
    stop(
      source_name,
      " is not a data.frame/tibble."
    )
  }

  out <- vector(
    "list",
    length(names(dat))
  )

  for (i in seq_along(names(dat))) {

    nm <- names(dat)[i]
    x <- dat[[nm]]

    cls <- paste(
      class(x),
      collapse = ";"
    )

    n_missing <- sum(
      is.na(x)
    )

    pct_missing <-
      100 * n_missing / length(x)

    n_unique <- tryCatch(
      dplyr::n_distinct(
        x,
        na.rm = TRUE
      ),
      error = function(e) NA_integer_
    )

    numeric_min <- NA_real_
    numeric_max <- NA_real_
    numeric_mean <- NA_real_
    numeric_sd <- NA_real_

    if (
      is.numeric(x) ||
      is.integer(x)
    ) {

      xx <- x[
        is.finite(x)
      ]

      if (length(xx) > 0L) {

        numeric_min <-
          min(xx)

        numeric_max <-
          max(xx)

        numeric_mean <-
          mean(xx)

        numeric_sd <-
          sd(xx)
      }
    }

    out[[i]] <- data.frame(
      source =
        source_name,

      path =
        source_path,

      n_rows =
        nrow(dat),

      variable =
        nm,

      class =
        cls,

      n_missing =
        n_missing,

      pct_missing =
        pct_missing,

      n_unique =
        n_unique,

      min =
        numeric_min,

      max =
        numeric_max,

      mean =
        numeric_mean,

      sd =
        numeric_sd,

      stringsAsFactors =
        FALSE
    )
  }

  bind_rows(out)
}

# ============================================================
# 2. Read all key RDS files
# ============================================================

inventory_list <- list()

dataset_summary <- list()

counter <- 1L

for (nm in names(sources)) {

  path <- sources[[nm]]

  if (!file.exists(path)) {

    cat(
      "WARNING: missing file: ",
      path,
      "\n",
      sep = ""
    )

    next
  }

  dat <- readRDS(path)

  dataset_summary[[counter]] <-
    data.frame(
      source =
        nm,

      path =
        path,

      object_class =
        paste(
          class(dat),
          collapse = ";"
        ),

      n_rows =
        if (is.data.frame(dat))
          nrow(dat)
        else
          NA_integer_,

      n_cols =
        if (is.data.frame(dat))
          ncol(dat)
        else
          NA_integer_
    )

  if (is.data.frame(dat)) {

    inventory_list[[counter]] <-
      summarise_columns(
        dat,
        nm,
        path
      )
  }

  counter <- counter + 1L
}

inventory <- bind_rows(
  inventory_list
)

dataset_summary <- bind_rows(
  dataset_summary
)

write_csv(
  dataset_summary,
  file.path(
    out_dir,
    "dataset_summary.csv"
  )
)

write_csv(
  inventory,
  file.path(
    out_dir,
    "all_variable_inventory.csv"
  )
)

# ============================================================
# 3. Keyword modules
# ============================================================

keyword_modules <- list(

  age = c(
    "age",
    "geochron",
    "ma_",
    "_ma",
    "nrcan"
  ),

  geology_general = c(
    "geo",
    "geol",
    "rock",
    "lith"
  ),

  lithology = c(
    "carbonate",
    "plutonic",
    "metamorphic",
    "volcanic",
    "siliciclastic",
    "sedimentary",
    "evaporite",
    "unconsolidated"
  ),

  local = c(
    "local",
    "loc_"
  ),

  upstream = c(
    "upstream",
    "up_",
    "upland"
  ),

  terrain = c(
    "slope",
    "relief",
    "rugged",
    "terrain",
    "elev"
  ),

  glacier = c(
    "glacier",
    "glaci",
    "ice",
    "snow"
  ),

  hydrology = c(
    "runoff",
    "discharge",
    "flow",
    "precip",
    "bio12",
    "aridity",
    "ai_",
    "et0"
  ),

  soil = c(
    "soil",
    "clay",
    "sand",
    "silt"
  )
)

match_module <- function(variable, patterns) {

  v <- tolower(variable)

  any(
    vapply(
      patterns,
      function(p) {
        grepl(
          p,
          v,
          fixed = TRUE
        )
      },
      logical(1)
    )
  )
}

module_matches <- list()

counter <- 1L

for (module_name in names(keyword_modules)) {

  patterns <-
    keyword_modules[[module_name]]

  tmp <- inventory |>
    filter(
      vapply(
        variable,
        match_module,
        logical(1),
        patterns = patterns
      )
    ) |>
    mutate(
      module =
        module_name
    ) |>
    select(
      module,
      source,
      variable,
      class,
      pct_missing,
      n_unique,
      min,
      max
    )

  module_matches[[counter]] <-
    tmp

  counter <- counter + 1L
}

module_matches <- bind_rows(
  module_matches
)

write_csv(
  module_matches,
  file.path(
    out_dir,
    "variables_by_candidate_module.csv"
  )
)

# ============================================================
# 4. Inspect file names in data/ and outputs/
# ============================================================

search_roots <- c(
  "data",
  "outputs"
)

all_paths <- unlist(
  lapply(
    search_roots,
    function(root) {

      if (!dir.exists(root)) {
        return(
          character(0)
        )
      }

      list.files(
        root,
        recursive = TRUE,
        full.names = TRUE
      )
    }
  ),
  use.names = FALSE
)

file_matches <- list()

counter <- 1L

for (module_name in names(keyword_modules)) {

  patterns <-
    keyword_modules[[module_name]]

  keep <- vapply(
    all_paths,
    function(path) {

      p <- tolower(path)

      any(
        vapply(
          patterns,
          function(k) {
            grepl(
              k,
              p,
              fixed = TRUE
            )
          },
          logical(1)
        )
      )
    },
    logical(1)
  )

  hits <- all_paths[
    keep
  ]

  if (length(hits) > 0L) {

    file_matches[[counter]] <-
      data.frame(
        module =
          module_name,

        file =
          hits,

        stringsAsFactors =
          FALSE
      )

    counter <- counter + 1L
  }
}

file_matches <- bind_rows(
  file_matches
)

write_csv(
  file_matches,
  file.path(
    out_dir,
    "matching_project_files.csv"
  )
)

# ============================================================
# 5. Availability helpers
# ============================================================

vars_lower <- tolower(
  unique(
    inventory$variable
  )
)

count_any <- function(patterns) {

  sum(
    vapply(
      vars_lower,
      function(v) {

        any(
          vapply(
            patterns,
            function(p) {
              grepl(
                p,
                v,
                fixed = TRUE
              )
            },
            logical(1)
          )
        )
      },
      logical(1)
    )
  )
}

get_matches <- function(patterns) {

  unique(
    inventory$variable[
      vapply(
        tolower(
          inventory$variable
        ),
        function(v) {

          any(
            vapply(
              patterns,
              function(p) {
                grepl(
                  p,
                  v,
                  fixed = TRUE
                )
              },
              logical(1)
            )
          )
        },
        logical(1)
      )
    ]
  )
}

# ============================================================
# 6. Key availability counts
# ============================================================

age_matches <- get_matches(
  c("age")
)

lith_matches <- get_matches(
  c(
    "carbonate",
    "plutonic",
    "metamorphic",
    "volcanic",
    "siliciclastic",
    "sedimentary",
    "evaporite",
    "unconsolidated"
  )
)

local_matches <- get_matches(
  c(
    "local"
  )
)

upstream_geo_matches <- get_matches(
  c(
    "up_geo",
    "upstream"
  )
)

terrain_matches <- get_matches(
  c(
    "slope",
    "relief",
    "rugged",
    "terrain",
    "elev"
  )
)

glacier_matches <- get_matches(
  c(
    "glacier",
    "glaci",
    "ice",
    "snow"
  )
)

runoff_matches <- get_matches(
  c(
    "runoff",
    "discharge",
    "dis_av",
    "bio12",
    "precip"
  )
)

# ============================================================
# 7. Candidate M1 availability table
# ============================================================

candidate_summary <- data.frame(

  candidate = c(
    "Age distribution: mean/SD/P75/P90",
    "Lithology diversity / entropy",
    "Local-upstream geological contrast",
    "Relief / slope / terrain heterogeneity",
    "Glacier fraction",
    "Runoff / discharge weighting",
    "Hydrologically weighted geology"
  ),

  module = c(
    "M1-A",
    "M1-A",
    "M1-B",
    "M1-C",
    "M1-C",
    "M1-D",
    "M1-D"
  ),

  mechanism = c(
    "Geological source distribution",
    "Geological heterogeneity",
    "Local source versus catchment background",
    "Geomorphic mobilisation",
    "Glacial / high-mountain mobilisation",
    "Hydrological mobilisation",
    "Potential dissolved-source contribution"
  ),

  evidence_count = c(
    length(age_matches),
    length(lith_matches),
    min(
      length(local_matches),
      length(upstream_geo_matches)
    ),
    length(terrain_matches),
    length(glacier_matches),
    length(runoff_matches),
    min(
      length(lith_matches),
      length(runoff_matches)
    )
  ),

  preliminary_status = c(

    if (length(age_matches) > 0)
      "EXISTING AGE DATA; derive distribution if polygon-level data retained"
    else
      "NOT SEEN",

    if (length(lith_matches) >= 4)
      "DERIVABLE FROM EXISTING LITHOLOGY FRACTIONS"
    else
      "CHECK GEOLOGY SOURCE",

    if (
      length(local_matches) > 0 &&
      length(upstream_geo_matches) > 0
    )
      "POTENTIALLY DERIVABLE; inspect matching local/upstream variables"
    else
      "LIKELY NEED LOCAL GEOLOGY EXTRACTION",

    if (length(terrain_matches) > 1)
      "PARTLY AVAILABLE; inspect terrain variables"
    else
      "LIKELY NEED NEW TERRAIN SUMMARIES",

    if (length(glacier_matches) > 0)
      "POSSIBLY AVAILABLE"
    else
      "NOT SEEN; likely new dataset",

    if (length(runoff_matches) > 0)
      "HYDROLOGY AVAILABLE"
    else
      "NOT SEEN",

    if (
      length(lith_matches) >= 4 &&
      length(runoff_matches) > 0
    )
      "CONCEPTUALLY POSSIBLE; requires spatial weighting calculation"
    else
      "REQUIRES ADDITIONAL DATA"
  ),

  priority = c(
    "HIGH",
    "HIGH",
    "VERY HIGH",
    "HIGH",
    "MEDIUM",
    "MEDIUM",
    "MEDIUM"
  ),

  stringsAsFactors =
    FALSE
)

write_csv(
  candidate_summary,
  file.path(
    out_dir,
    "M1_candidate_availability_summary.csv"
  )
)

# ============================================================
# 8. Save exact key matches
# ============================================================

make_match_df <- function(label, vars) {

  if (length(vars) == 0L) {

    return(
      data.frame(
        candidate = character(0),
        variable = character(0),
        stringsAsFactors = FALSE
      )
    )
  }

  data.frame(
    candidate = rep(
      label,
      length(vars)
    ),
    variable = vars,
    stringsAsFactors = FALSE
  )
}

exact_matches <- bind_rows(

  make_match_df(
    "AGE",
    age_matches
  ),

  make_match_df(
    "LITHOLOGY",
    lith_matches
  ),

  make_match_df(
    "LOCAL",
    local_matches
  ),

  make_match_df(
    "UPSTREAM_GEO",
    upstream_geo_matches
  ),

  make_match_df(
    "TERRAIN",
    terrain_matches
  ),

  make_match_df(
    "GLACIER",
    glacier_matches
  ),

  make_match_df(
    "RUNOFF_HYDROLOGY",
    runoff_matches
  )
)

write_csv(
  exact_matches,
  file.path(
    out_dir,
    "key_variable_matches.csv"
  )
)

# ============================================================
# 9. Terminal report
# ============================================================

cat(
  "\n========================================\n"
)

cat(
  "R42 PREDICTOR INVENTORY AUDIT\n"
)

cat(
  "========================================\n"
)

cat(
  "\n===== DATASETS =====\n"
)

print(
  as.data.frame(
    dataset_summary
  ),
  row.names = FALSE
)

cat(
  "\n===== M1 CANDIDATE AVAILABILITY =====\n"
)

print(
  candidate_summary,
  row.names = FALSE
)

cat(
  "\n===== AGE MATCHES =====\n"
)

print(
  age_matches
)

cat(
  "\n===== LITHOLOGY MATCHES =====\n"
)

print(
  lith_matches
)

cat(
  "\n===== LOCAL MATCHES =====\n"
)

print(
  local_matches
)

cat(
  "\n===== UPSTREAM GEOLOGY MATCHES =====\n"
)

print(
  upstream_geo_matches
)

cat(
  "\n===== TERRAIN MATCHES =====\n"
)

print(
  terrain_matches
)

cat(
  "\n===== GLACIER MATCHES =====\n"
)

print(
  glacier_matches
)

cat(
  "\n===== RUNOFF / HYDROLOGY MATCHES =====\n"
)

print(
  runoff_matches
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
