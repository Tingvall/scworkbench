.wb_ensure_cell_vectors_tables <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS cell_vectors (
      vector_id     TEXT PRIMARY KEY,
      name          TEXT NOT NULL,
      description   TEXT,
      value_type    TEXT NOT NULL DEFAULT 'numeric',
      source        TEXT,
      created_at    TEXT NOT NULL,
      created_by    TEXT,
      provenance_json TEXT
    );
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS cell_vector_values (
      vector_id TEXT NOT NULL,
      cell_id   TEXT NOT NULL,
      value     REAL,
      PRIMARY KEY (vector_id, cell_id)
    );
  ")

  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_cvv_cell   ON cell_vector_values(cell_id);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_cvv_vec    ON cell_vector_values(vector_id);")

  invisible(TRUE)
}
