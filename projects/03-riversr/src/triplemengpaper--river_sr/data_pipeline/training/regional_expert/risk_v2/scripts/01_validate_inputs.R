regional_v2_validate_inputs <- function(context) {
  cfg <- context$config
  paths <- lapply(cfg$input[setdiff(names(cfg$input), "expected_md5")], regional_v2_path, context = context)
  regional_v2_assert(all(vapply(paths, file.exists, logical(1L))), "A frozen Regional Risk V2 data input is missing.")

  v1 <- regional_v2_read_csv(paths$v1_table)
  branches <- regional_v2_read_csv(paths$v1_branch_map)
  full50 <- regional_v2_read_lines(paths$full50_predictors)
  process14 <- regional_v2_read_lines(paths$process14_predictors)
  dictionary <- yaml::read_yaml(paths$process14_formula_dictionary)

  expected_md5 <- cfg$input$expected_md5
  for (name in names(expected_md5)) {
    observed <- regional_v2_signature(paths[[name]])$md5
    regional_v2_assert(
      identical(observed, as.character(expected_md5[[name]])),
      paste("Frozen input hash changed for", name, ":", observed)
    )
  }

  regional_v2_assert(nrow(v1) == as.integer(cfg$domain$expected_rows), "V1 regional table must contain 372 rows.")
  regional_v2_assert(ncol(v1) == as.integer(cfg$domain$expected_input_columns), "V1 regional table column count changed.")
  regional_v2_assert(length(full50) == as.integer(cfg$domain$expected_full50_predictors), "Full50 manifest must contain 50 fields.")
  regional_v2_assert(length(process14) == as.integer(cfg$domain$expected_process_predictors), "Process14 manifest must contain 14 fields.")
  regional_v2_assert(!anyDuplicated(full50), "Full50 manifest contains duplicate fields.")
  regional_v2_assert(!anyDuplicated(process14), "Process14 manifest contains duplicate fields.")
  regional_v2_assert(length(intersect(full50, process14)) == 0L, "Full50 and Process14 manifests overlap.")
  regional_v2_assert(length(setdiff(full50, names(v1))) == 0L, "V1 regional table lacks a frozen Full50 field.")
  regional_v2_assert(length(intersect(process14, names(v1))) == 0L, "A Process14 target already exists in the V1 table; refuse to overwrite it.")

  row_id <- cfg$columns$row_id
  site_id <- cfg$columns$site_id
  branch_id <- cfg$columns$branch_id
  regional_v2_assert(!anyDuplicated(v1[[row_id]]) && !anyDuplicated(v1[[site_id]]), "V1 regional identities are duplicated.")
  regional_v2_assert(!anyDuplicated(branches[[row_id]]), "Frozen branch map row_id is duplicated.")
  branches <- branches[match(as.character(v1[[row_id]]), as.character(branches[[row_id]])), , drop = FALSE]
  regional_v2_assert(!anyNA(branches[[row_id]]), "Frozen branch map does not cover all 372 V1 rows.")
  regional_v2_assert(
    identical(as.character(v1[[site_id]]), as.character(branches[[site_id]])),
    "V1 table and frozen branch map site identities differ."
  )
  regional_v2_assert(length(unique(branches[[branch_id]])) == as.integer(cfg$domain$expected_branches), "Frozen branch count changed.")

  dictionary_names <- names(dictionary$features)
  regional_v2_assert(identical(dictionary_names, process14), "Formula dictionary order/names differ from Process14 manifest.")
  statuses <- vapply(dictionary$features, function(x) as.character(x$status), character(1L))
  regional_v2_assert(
    identical(unique(statuses), "frozen_before_modeling"),
    "Every Process14 formula must be frozen before modeling."
  )
  regional_v2_assert(
    identical(as.character(dictionary$dictionary_status), as.character(cfg$formula_contract$status)),
    "Formula dictionary status differs from the data contract."
  )
  source_columns <- unique(unlist(lapply(dictionary$features, function(x) x$source_columns), use.names = FALSE))
  regional_v2_assert(length(setdiff(source_columns, names(v1))) == 0L, "V1 table lacks a Process14 source column.")
  regional_v2_assert(
    all(vapply(v1[, source_columns, drop = FALSE], function(x) all(is.finite(as.numeric(x))), logical(1L))),
    "A Process14 source column contains missing or non-finite values."
  )

  list(
    v1 = v1,
    branches = branches,
    full50 = full50,
    process14 = process14,
    dictionary = dictionary,
    paths = paths
  )
}
