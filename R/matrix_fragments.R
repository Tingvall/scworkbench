wb_register_matrix_fragment <- function(
    con,
    matrix_id,
    path_rel,
    feature_ids,
    cell_ids,
    source = "publish",
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    description = NA_character_
) {
  .wb_ensure_matrix_fragments_table(con)

  .wb_assert(is.character(matrix_id) && nzchar(matrix_id), "matrix_id invalid")
  .wb_assert(is.character(path_rel) && nzchar(path_rel), "path_rel invalid")
  .wb_assert(is.character(feature_ids) && length(feature_ids) > 0, "feature_ids empty")
  .wb_assert(is.character(cell_ids) && length(cell_ids) > 0, "cell_ids empty")

  fragment_id <- paste0(
    "frag_", matrix_id, "_",
    format(Sys.time(), "%Y%m%d%H%M%S"),
    "_", paste(sample(c(0:9, letters), 12, TRUE), collapse = "")
  )

  feature_ids_json <- as.character(jsonlite::toJSON(feature_ids, auto_unbox = TRUE))
  cell_ids_json    <- as.character(jsonlite::toJSON(cell_ids,    auto_unbox = TRUE))

  # IMPORTANT: DBI params must be length-1, never NULL
  if (is.null(description) || length(description) == 0) description <- NA_character_
  description <- as.character(description)[1]

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
      as.character(source)[1],
      as.character(created_at)[1],
      description
    )
  )

  invisible(fragment_id)
}


.wb_ensure_matrix_fragment_tables <- function(con) {

  # Core fragment registry (NO JSON membership columns)
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS matrix_fragments (
      fragment_id TEXT PRIMARY KEY,
      matrix_id   TEXT NOT NULL,
      storage     TEXT NOT NULL,
      path        TEXT NOT NULL,
      n_features  INTEGER,
      n_cells     INTEGER,
      source      TEXT,
      created_at  TEXT NOT NULL,
      description TEXT
    );
  ")

  # Membership tables
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

  invisible(TRUE)
}


