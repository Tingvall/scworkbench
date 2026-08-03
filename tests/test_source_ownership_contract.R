test_source_ownership_contract <- function() {
  root <- normalizePath(".", winslash = "/", mustWork = TRUE)
  r_dir <- file.path(root, "R")
  r_files <- sort(list.files(r_dir, pattern = "\\.[Rr]$", full.names = TRUE))

  scan_functions <- function(files) {
    rows <- list()
    row_index <- 0L
    for (path in files) {
      expressions <- parse(path, keep.source = TRUE)
      source_refs <- attr(expressions, "srcref")
      for (index in seq_along(expressions)) {
        expression <- expressions[[index]]
        if (!is.call(expression)) next
        operator <- expression[[1L]]
        left_assignment <- identical(operator, as.name("<-")) || identical(operator, as.name("="))
        right_assignment <- identical(operator, as.name("->"))
        if (!left_assignment && !right_assignment) next
        name_expression <- if (left_assignment) expression[[2L]] else expression[[3L]]
        value_expression <- if (left_assignment) expression[[3L]] else expression[[2L]]
        if (!is.symbol(name_expression) || !is.call(value_expression) ||
            !identical(value_expression[[1L]], as.name("function"))) next
        source_ref <- if (length(source_refs) >= index) source_refs[[index]] else NULL
        row_index <- row_index + 1L
        rows[[row_index]] <- data.frame(
          name = as.character(name_expression),
          file = sub(paste0("^", root, "/"), "", normalizePath(path, winslash = "/")),
          line = if (is.null(source_ref)) NA_integer_ else as.integer(source_ref[[1L]]),
          stringsAsFactors = FALSE
        )
      }
    }
    do.call(rbind, rows)
  }

  scan_schema <- function(files) {
    pattern <- "CREATE\\s+TABLE\\s+(?:IF\\s+NOT\\s+EXISTS\\s+)?([A-Za-z0-9_]+)"
    rows <- list()
    row_index <- 0L
    for (path in files) {
      text <- paste(readLines(path, warn = FALSE), collapse = "\n")
      locations <- gregexpr(pattern, text, ignore.case = TRUE, perl = TRUE)[[1L]]
      if (identical(locations[[1L]], -1L)) next
      matches <- regmatches(text, list(locations))[[1L]]
      for (index in seq_along(matches)) {
        row_index <- row_index + 1L
        offset <- locations[[index]]
        rows[[row_index]] <- data.frame(
          table = tolower(sub(pattern, "\\1", matches[[index]], ignore.case = TRUE, perl = TRUE)),
          file = sub(paste0("^", root, "/"), "", normalizePath(path, winslash = "/")),
          line = 1L + lengths(regmatches(substr(text, 1L, max(0L, offset - 1L)), gregexpr("\n", substr(text, 1L, max(0L, offset - 1L)), fixed = TRUE))),
          stringsAsFactors = FALSE
        )
      }
    }
    do.call(rbind, rows)
  }

  assert_no_unapproved_duplicates <- function(inventory, key, exceptions, label) {
    if (length(exceptions)) {
      stopifnot(!is.null(names(exceptions)), all(nzchar(names(exceptions))), all(nzchar(trimws(exceptions))))
    }
    values <- as.character(inventory[[key]])
    duplicate_names <- unique(values[duplicated(values)])
    unapproved <- setdiff(duplicate_names, names(exceptions))
    if (length(unapproved)) {
      details <- vapply(unapproved, function(value) {
        rows <- inventory[values == value, , drop = FALSE]
        paste0(value, " [", paste0(rows$file, ":", rows$line, collapse = ", "), "]")
      }, character(1))
      stop("Duplicate ", label, " definition(s): ", paste(details, collapse = "; "), call. = FALSE)
    }
    stale <- setdiff(names(exceptions), duplicate_names)
    if (length(stale)) {
      stop("Stale duplicate ", label, " exception(s): ", paste(stale, collapse = ", "), call. = FALSE)
    }
    invisible(TRUE)
  }

  function_inventory <- scan_functions(r_files)
  schema_inventory <- scan_schema(r_files)

  # There are intentionally no exceptions. A future exception must name the
  # collision and carry a narrow reason; stale exceptions fail this contract.
  function_exceptions <- character()
  schema_exceptions <- character()
  assert_no_unapproved_duplicates(function_inventory, "name", function_exceptions, "top-level function")
  assert_no_unapproved_duplicates(schema_inventory, "table", schema_exceptions, "schema table")

  expected_function_owners <- c(
    `%||%` = "R/internal_contracts.R",
    .wb_require_cols = "R/internal_contracts.R",
    wb_register_matrix_fragment = "R/matrix_fragments.R",
    .wb_ensure_matrix_fragment_tables = "R/matrix_fragments.R",
    .wb_ensure_schema_app_bundle = "R/schema_core.R",
    .wb_create_artifacts_schema = "R/artifacts_schema.R",
    wb_migrate_artifacts = "R/promote_primitives.R",
    .wb_migrate_provenance_tables = "R/provenance_store.R",
    .wb_prov_schema_version = "R/provenance_store.R"
  )
  for (function_name in names(expected_function_owners)) {
    owner <- function_inventory$file[function_inventory$name == function_name]
    stopifnot(identical(owner, unname(expected_function_owners[[function_name]])))
  }

  expected_schema_owners <- c(
    datasets = "R/schema_core.R",
    cells = "R/schema_core.R",
    cell_set_membership = "R/schema_core.R",
    spaces = "R/schema_core.R",
    space_coords = "R/schema_core.R",
    space_2d = "R/schema_core.R",
    features = "R/schema_core.R",
    matrices = "R/schema_core.R",
    matrix_cells = "R/schema_core.R",
    cell_set_styles = "R/schema_core.R",
    matrix_fragments = "R/matrix_fragments.R",
    matrix_fragment_cells = "R/matrix_fragments.R",
    matrix_fragment_features = "R/matrix_fragments.R",
    artifacts = "R/artifacts_schema.R",
    artifact_labels = "R/artifacts_schema.R",
    artifact_pseudotime = "R/artifacts_schema.R",
    artifact_relation_rows = "R/artifacts_schema.R",
    artifact_curves_2d = "R/artifacts_schema.R",
    artifact_space_path_meta = "R/artifacts_schema.R",
    artifact_space_path_rows = "R/artifacts_schema.R",
    artifact_space_2d = "R/artifacts_schema.R",
    artifact_umap_model = "R/artifacts_schema.R",
    artifact_model_ref = "R/artifacts_schema.R",
    artifact_tables = "R/artifacts_schema.R",
    artifact_table_rows = "R/artifacts_schema.R"
  )
  for (table_name in names(expected_schema_owners)) {
    owner <- schema_inventory$file[schema_inventory$table == table_name]
    stopifnot(identical(owner, unname(expected_schema_owners[[table_name]])))
  }
  core_provenance <- schema_inventory[grepl("^prov_", schema_inventory$table), , drop = FALSE]
  non_registry_provenance <- core_provenance$table != "prov_registry_mutations"
  stopifnot(all(core_provenance$file[non_registry_provenance] == "R/provenance_store.R"))
  stopifnot(identical(
    core_provenance$file[core_provenance$table == "prov_registry_mutations"],
    "R/registry_materialization.R"
  ))

  operation_docs <- readLines(file.path(root, "R", "operation_docs.R"), warn = FALSE)
  stopifnot(
    grepl("Generated from the runtime operation interface catalog", operation_docs[[1L]], fixed = TRUE),
    file.exists(file.path(root, "inst", "dev", "generate_operation_docs.R")),
    !any(function_inventory$file == "R/operation_docs.R")
  )

  namespace <- readLines(file.path(root, "NAMESPACE"), warn = FALSE)
  stopifnot(sum(namespace == "export(wb_register_matrix_fragment)") == 1L)
  rd <- readLines(file.path(root, "man", "wb_register_matrix_fragment.Rd"), warn = FALSE)
  stopifnot(
    any(grepl("Please edit documentation in R/matrix_fragments.R", rd, fixed = TRUE)),
    any(grepl("source = NULL", rd, fixed = TRUE)),
    any(grepl("description = NULL", rd, fixed = TRUE))
  )

  fresh_dir <- tempfile("scwb_fragment_fresh_")
  fresh <- wb_init_bundle(fresh_dir, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(fresh), silent = TRUE)
    unlink(fresh_dir, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  registered <- withVisible(wb_register_matrix_fragment(
    fresh$con,
    matrix_id = "RNA_counts",
    path_rel = "mat/fresh_fragment",
    feature_ids = c("g2", "g1"),
    cell_ids = c("c2", "c1"),
    created_at = "2026-08-02 12:00:00"
  ))
  stopifnot(!registered$visible, startsWith(registered$value, "mf_RNA_counts_"))
  fresh_row <- DBI::dbGetQuery(
    fresh$con,
    "SELECT * FROM matrix_fragments WHERE fragment_id = ?;",
    params = list(registered$value)
  )
  stopifnot(
    nrow(fresh_row) == 1L,
    identical(jsonlite::fromJSON(fresh_row$feature_ids_json[[1L]]), c("g2", "g1")),
    identical(jsonlite::fromJSON(fresh_row$cell_ids_json[[1L]]), c("c2", "c1")),
    is.na(fresh_row$source[[1L]]),
    is.na(fresh_row$description[[1L]])
  )
  fresh_features <- DBI::dbGetQuery(
    fresh$con,
    "SELECT feature_id FROM matrix_fragment_features WHERE fragment_id = ? ORDER BY rowid;",
    params = list(registered$value)
  )$feature_id
  fresh_cells <- DBI::dbGetQuery(
    fresh$con,
    "SELECT cell_id FROM matrix_fragment_cells WHERE fragment_id = ? ORDER BY rowid;",
    params = list(registered$value)
  )$cell_id
  stopifnot(identical(fresh_features, c("g2", "g1")), identical(fresh_cells, c("c2", "c1")))

  migrated_path <- tempfile("scwb_fragment_migrated_", fileext = ".sqlite")
  migrated <- DBI::dbConnect(RSQLite::SQLite(), migrated_path)
  on.exit({
    try(DBI::dbDisconnect(migrated), silent = TRUE)
    unlink(migrated_path, force = TRUE)
  }, add = TRUE)
  DBI::dbExecute(migrated, "
    CREATE TABLE matrix_fragments (
      fragment_id TEXT PRIMARY KEY,
      matrix_id TEXT NOT NULL,
      storage TEXT NOT NULL,
      path TEXT NOT NULL,
      n_features INTEGER,
      n_cells INTEGER,
      source TEXT,
      created_at TEXT NOT NULL,
      description TEXT
    );
  ")
  DBI::dbExecute(
    migrated,
    "INSERT INTO matrix_fragments(fragment_id, matrix_id, storage, path, n_features, n_cells, source, created_at, description) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?);",
    params = list("legacy_fragment", "RNA_counts", "bpcells", "mat/legacy", 1L, 1L, "legacy", "2026-01-01 00:00:00", NA_character_)
  )
  DBI::dbExecute(migrated, "CREATE TABLE matrix_fragment_features (fragment_id TEXT NOT NULL, feature_id TEXT NOT NULL, PRIMARY KEY(fragment_id, feature_id));")
  DBI::dbExecute(migrated, "CREATE TABLE matrix_fragment_cells (fragment_id TEXT NOT NULL, cell_id TEXT NOT NULL, PRIMARY KEY(fragment_id, cell_id));")
  DBI::dbExecute(migrated, "INSERT INTO matrix_fragment_features(fragment_id, feature_id) VALUES('legacy_fragment', 'legacy_gene');")
  DBI::dbExecute(migrated, "INSERT INTO matrix_fragment_cells(fragment_id, cell_id) VALUES('legacy_fragment', 'legacy_cell');")
  migrated_registered <- scworkbench:::.wb_with_mutation_context(
    con = migrated, route = "ingestion",
    code = withVisible(wb_register_matrix_fragment(
      migrated,
      matrix_id = "RNA_counts",
      path_rel = "mat/migrated_fragment",
      feature_ids = c("g1", "g2"),
      cell_ids = c("c1", "c2"),
      source = "migration_contract",
      created_at = "2026-08-02 13:00:00",
      description = "registered after schema migration"
    ))
  )
  stopifnot(!migrated_registered$visible)
  migrated_columns <- DBI::dbListFields(migrated, "matrix_fragments")
  stopifnot(all(c("feature_ids_json", "cell_ids_json") %in% migrated_columns))
  legacy_row <- DBI::dbGetQuery(migrated, "SELECT * FROM matrix_fragments WHERE fragment_id = 'legacy_fragment';")
  stopifnot(
    identical(jsonlite::fromJSON(legacy_row$feature_ids_json[[1L]]), "legacy_gene"),
    identical(jsonlite::fromJSON(legacy_row$cell_ids_json[[1L]]), "legacy_cell")
  )
  migrated_row <- DBI::dbGetQuery(
    migrated,
    "SELECT * FROM matrix_fragments WHERE fragment_id = ?;",
    params = list(migrated_registered$value)
  )
  stopifnot(
    nrow(migrated_row) == 1L,
    identical(jsonlite::fromJSON(migrated_row$feature_ids_json[[1L]]), c("g1", "g2")),
    identical(jsonlite::fromJSON(migrated_row$cell_ids_json[[1L]]), c("c1", "c2")),
    identical(migrated_row$source[[1L]], "migration_contract"),
    identical(migrated_row$description[[1L]], "registered after schema migration"),
    DBI::dbGetQuery(migrated, "SELECT COUNT(*) AS n FROM matrix_fragment_features WHERE fragment_id = ?;", params = list(migrated_registered$value))$n[[1L]] == 2L,
    DBI::dbGetQuery(migrated, "SELECT COUNT(*) AS n FROM matrix_fragment_cells WHERE fragment_id = ?;", params = list(migrated_registered$value))$n[[1L]] == 2L
  )

  TRUE
}
