#' (Advanced) Register a matrix fragment in the bundle registry
#'
#' Prefer `wb_bundle_from_*()` or `wb_attach_matrix()` for ordinary ingestion.
#'
#' @param con Bundle SQLite connection.
#' @param matrix_id Logical matrix identifier.
#' @param path_rel Bundle-relative fragment payload path.
#' @param feature_ids Ordered fragment feature IDs.
#' @param cell_ids Ordered fragment cell IDs.
#' @param source Provenance source label.
#' @param created_at Creation timestamp.
#' @param description Optional fragment description.
#' @return Invisibly, the registered fragment identifier.
#' @export
wb_register_matrix_fragment <- function(
    con,
    matrix_id,
    path_rel,
    feature_ids,
    cell_ids,
    source = NULL,
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    description = NULL
) {
  .wb_assert_mutation_context(
    con = con, action = "Low-level matrix-fragment registry writer wb_register_matrix_fragment()",
    allowed = c("assembly", "session_execution", "promotion", "ingestion"),
    replacement = "wb_attach_matrix()/wb_attach_apply() for declared ingestion, or matrix_log_normalize through wb_session_run_op() and promotion"
  )
  .wb_ensure_matrix_fragment_tables(con)

  .wb_assert(is.character(matrix_id) && length(matrix_id) == 1L && !is.na(matrix_id) && nzchar(matrix_id), "matrix_id invalid")
  .wb_assert(is.character(path_rel) && length(path_rel) == 1L && !is.na(path_rel) && nzchar(path_rel), "path_rel invalid")
  context <- .wb_current_mutation_context(con)
  root <- as.character(context$dir %||% .wb_assembly_connection_dir(con) %||% "")[1]
  .wb_assert(nzchar(root), "matrix fragment registration requires a bundle-root mutation context")
  path_status <- .wb_path_status(root, path_rel, expected_type = "directory",
                                 must_exist = file.exists(file.path(root,"manifest.json")),
                                 purpose = "matrix fragment")
  .wb_assert(isTRUE(path_status$ok), paste0(path_status$code, ": invalid matrix fragment path."))
  path_rel <- path_status$relative
  .wb_assert(is.character(feature_ids) && length(feature_ids) > 0L, "feature_ids empty")
  .wb_assert(is.character(cell_ids) && length(cell_ids) > 0L, "cell_ids empty")

  feature_ids <- as.character(feature_ids)
  cell_ids <- as.character(cell_ids)
  .wb_assert(!anyNA(feature_ids) && all(nzchar(feature_ids)), "feature_ids contain missing or empty values")
  .wb_assert(!anyNA(cell_ids) && all(nzchar(cell_ids)), "cell_ids contain missing or empty values")
  .wb_assert(!anyDuplicated(feature_ids), "feature_ids must be unique within a fragment")
  .wb_assert(!anyDuplicated(cell_ids), "cell_ids must be unique within a fragment")

  cell_blocks <- split(cell_ids, ceiling(seq_along(cell_ids) / 500L))
  existing_cells <- unique(unlist(lapply(cell_blocks, function(block) {
    cells_clause <- .wb_sql_in_clause(block)
    DBI::dbGetQuery(
      con,
      paste0(
        "SELECT DISTINCT membership.cell_id ",
        "FROM matrix_fragment_cells AS membership ",
        "JOIN matrix_fragments AS fragment ON fragment.fragment_id = membership.fragment_id ",
        "WHERE fragment.matrix_id = ? AND membership.cell_id ", cells_clause$sql, ";"
      ),
      params = c(list(matrix_id), cells_clause$params)
    )$cell_id
  }), use.names = FALSE))
  .wb_assert(
    !length(existing_cells),
    paste0("matrix fragments for '", matrix_id, "' must have disjoint cell identities; repeated IDs: ",
           paste(head(existing_cells, 10L), collapse = ", "))
  )

  created_at <- as.character(created_at)[1]
  .wb_assert(!is.na(created_at) && nzchar(created_at), "created_at invalid")
  source <- if (is.null(source) || !length(source)) NA_character_ else as.character(source)[1]
  description <- if (is.null(description) || !length(description)) NA_character_ else as.character(description)[1]

  fragment_id <- .wb_new_fragment_id(matrix_id, con)

  feature_ids_json <- .wb_matrix_fragment_axis_json(feature_ids)
  cell_ids_json <- .wb_matrix_fragment_axis_json(cell_ids)

  savepoint <- .wb_allocate_identifier("scwb_fragment_", 12L, purpose = "SQLite savepoint")
  DBI::dbExecute(con, paste("SAVEPOINT", savepoint, ";"))
  released <- FALSE
  on.exit({
    if (!released) {
      try(DBI::dbExecute(con, paste("ROLLBACK TO", savepoint, ";")), silent = TRUE)
      try(DBI::dbExecute(con, paste("RELEASE", savepoint, ";")), silent = TRUE)
    }
  }, add = TRUE)

  DBI::dbExecute(
    con,
    "INSERT INTO matrix_fragments(
       fragment_id, matrix_id, storage, path, n_features, n_cells,
       feature_ids_json, cell_ids_json, source, created_at, description
     ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
    params = list(
      fragment_id,
      matrix_id,
      "bpcells",
      path_rel,
      as.integer(length(feature_ids)),
      as.integer(length(cell_ids)),
      feature_ids_json,
      cell_ids_json,
      source,
      created_at,
      description
    )
  )

  DBI::dbAppendTable(
    con,
    "matrix_fragment_features",
    data.frame(
      fragment_id = rep(fragment_id, length(feature_ids)),
      feature_id = feature_ids,
      stringsAsFactors = FALSE
    )
  )
  DBI::dbAppendTable(
    con,
    "matrix_fragment_cells",
    data.frame(
      fragment_id = rep(fragment_id, length(cell_ids)),
      cell_id = cell_ids,
      stringsAsFactors = FALSE
    )
  )
  DBI::dbExecute(con, paste("RELEASE", savepoint, ";"))
  released <- TRUE

  invisible(fragment_id)
}

# This is only the fragment registry's existing JSON array representation, not
# a canonical-identity encoder. Keep unfamiliar carriers on the literal old
# route, without attempting serialization or dispatching another coercion.
.wb_matrix_fragment_axis_json_vector_eligible <- function(ids) {
  if (typeof(ids) != "character" || !is.null(attributes(ids))) return(FALSE)
  if (!length(ids) || anyNA(ids)) return(FALSE)
  if (!identical(as.character(utils::packageVersion("jsonlite")), "1.8.8")) return(FALSE)
  if (any(Encoding(ids) != "unknown") || any(grepl("[^ -~]", ids, useBytes = TRUE))) return(FALSE)
  limit <- getOption("scworkbench.max_dense_materialize_mb", 256)
  if (!is.null(attributes(limit)) || !(typeof(limit) %in% c("integer", "double"))) return(FALSE)
  if (length(limit) != 1L || !is.finite(limit) || limit <= 0) return(FALSE)
  # ASCII quotes/backslashes at most double. Include the fetched character
  # carrier and eight simultaneous encoded carriers; this optimization may
  # decline admission but must never introduce a new public memory error.
  n <- length(ids)
  encoded_bound <- 2 * sum(nchar(ids, type = "bytes")) + 3 * n + 2
  working_bound <- 128 * n + 8 * encoded_bound
  is.finite(working_bound) && working_bound <= min(32 * 1024^2, limit * 1024^2 / 8)
}

.wb_matrix_fragment_axis_json <- function(ids) {
  if (.wb_matrix_fragment_axis_json_vector_eligible(ids)) {
    return(as.character(jsonlite::toJSON(ids, auto_unbox = FALSE)))
  }
  as.character(jsonlite::toJSON(as.list(ids), auto_unbox = TRUE))
}

.wb_new_fragment_id <- function(matrix_id, con = NULL) {
  .wb_allocate_db_identifier(
    con, "matrix_fragments", "fragment_id",
    paste0("mf_", matrix_id, "_", format(Sys.time(), "%Y%m%d_%H%M%S"), "_"),
    n = 8L, purpose = "matrix fragment"
  )
}

.wb_ensure_matrix_fragment_tables <- function(con) {
  if (.wb_schema_component_is_current(
    con, c("matrix_fragments", "matrix_fragment_cells", "matrix_fragment_features"),
    list(matrix_fragments = c("storage", "path", "n_features", "n_cells", "feature_ids_json", "cell_ids_json", "source", "created_at", "description"))
  )) return(invisible(TRUE))
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS matrix_fragments (
      fragment_id      TEXT PRIMARY KEY,
      matrix_id        TEXT NOT NULL,
      storage          TEXT NOT NULL,
      path             TEXT NOT NULL,
      n_features       INTEGER,
      n_cells          INTEGER,
      feature_ids_json TEXT NOT NULL,
      cell_ids_json    TEXT NOT NULL,
      source           TEXT,
      created_at       TEXT NOT NULL,
      description      TEXT
    );
  ")

  # Legacy fragment registries predate JSON identity columns and optional
  # descriptive fields. Add current columns in place before any registration.
  migration_columns <- c(
    storage = "TEXT",
    path = "TEXT",
    n_features = "INTEGER",
    n_cells = "INTEGER",
    feature_ids_json = "TEXT",
    cell_ids_json = "TEXT",
    source = "TEXT",
    created_at = "TEXT",
    description = "TEXT"
  )
  for (column in names(migration_columns)) {
    if (!.wb_db_has_column(con, "matrix_fragments", column)) {
      DBI::dbExecute(
        con,
        paste0("ALTER TABLE matrix_fragments ADD COLUMN ", column, " ", migration_columns[[column]], ";")
      )
    }
  }

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS matrix_fragment_cells (
      fragment_id TEXT NOT NULL,
      cell_id     TEXT NOT NULL,
      PRIMARY KEY (fragment_id, cell_id)
    );
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS matrix_fragment_features (
      fragment_id TEXT NOT NULL,
      feature_id  TEXT NOT NULL,
      PRIMARY KEY (fragment_id, feature_id)
    );
  ")

  # Indexes for fast lookups
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_mf_matrix_id ON matrix_fragments(matrix_id);")

  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_mfc_cell_id ON matrix_fragment_cells(cell_id);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_mfc_fragment_id ON matrix_fragment_cells(fragment_id);")

  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_mff_feature_id ON matrix_fragment_features(feature_id);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_mff_fragment_id ON matrix_fragment_features(fragment_id);")

  # Reconcile both historical schema variants. JSON-backed bundles acquire
  # normalized memberships, while membership-backed bundles acquire the JSON
  # identity arrays required by current getters.
  missing_json <- DBI::dbGetQuery(
    con,
    "SELECT fragment_id, feature_ids_json, cell_ids_json
     FROM matrix_fragments
     WHERE feature_ids_json IS NULL OR feature_ids_json = ''
        OR cell_ids_json IS NULL OR cell_ids_json = '';"
  )
  if (nrow(missing_json)) {
    for (index in seq_len(nrow(missing_json))) {
      fragment_id <- as.character(missing_json$fragment_id[[index]])
      if (is.na(missing_json$feature_ids_json[[index]]) || !nzchar(missing_json$feature_ids_json[[index]])) {
        ids <- DBI::dbGetQuery(
          con,
          "SELECT feature_id FROM matrix_fragment_features WHERE fragment_id = ? ORDER BY rowid;",
          params = list(fragment_id)
        )$feature_id
        if (length(ids)) {
          DBI::dbExecute(
            con,
            "UPDATE matrix_fragments SET feature_ids_json = ?, n_features = COALESCE(n_features, ?) WHERE fragment_id = ?;",
            params = list(as.character(jsonlite::toJSON(as.list(ids), auto_unbox = TRUE)), as.integer(length(ids)), fragment_id)
          )
        }
      }
      if (is.na(missing_json$cell_ids_json[[index]]) || !nzchar(missing_json$cell_ids_json[[index]])) {
        ids <- DBI::dbGetQuery(
          con,
          "SELECT cell_id FROM matrix_fragment_cells WHERE fragment_id = ? ORDER BY rowid;",
          params = list(fragment_id)
        )$cell_id
        if (length(ids)) {
          DBI::dbExecute(
            con,
            "UPDATE matrix_fragments SET cell_ids_json = ?, n_cells = COALESCE(n_cells, ?) WHERE fragment_id = ?;",
            params = list(as.character(jsonlite::toJSON(as.list(ids), auto_unbox = TRUE)), as.integer(length(ids)), fragment_id)
          )
        }
      }
    }
  }

  DBI::dbExecute(con, "
    INSERT OR IGNORE INTO matrix_fragment_features(fragment_id, feature_id)
    SELECT mf.fragment_id, CAST(identity.value AS TEXT)
    FROM matrix_fragments AS mf, json_each(mf.feature_ids_json) AS identity
    WHERE mf.feature_ids_json IS NOT NULL
      AND mf.feature_ids_json <> ''
      AND json_valid(mf.feature_ids_json)
      AND NOT EXISTS (
        SELECT 1 FROM matrix_fragment_features AS present
        WHERE present.fragment_id = mf.fragment_id
      );
  ")
  DBI::dbExecute(con, "
    INSERT OR IGNORE INTO matrix_fragment_cells(fragment_id, cell_id)
    SELECT mf.fragment_id, CAST(identity.value AS TEXT)
    FROM matrix_fragments AS mf, json_each(mf.cell_ids_json) AS identity
    WHERE mf.cell_ids_json IS NOT NULL
      AND mf.cell_ids_json <> ''
      AND json_valid(mf.cell_ids_json)
      AND NOT EXISTS (
        SELECT 1 FROM matrix_fragment_cells AS present
        WHERE present.fragment_id = mf.fragment_id
      );
  ")

  invisible(TRUE)
}
.wb_matrix_id_path_safe <- function(x) {
  x <- gsub("[^A-Za-z0-9_.-]+", "_", as.character(x %||% "")[1])
  if (!nzchar(x)) "matrix" else x
}
