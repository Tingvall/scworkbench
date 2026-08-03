# Canonical owner for the core bundle SQLite schema. Specialized registries
# (matrix fragments, artifacts, provenance, feature sets, and cell vectors)
# own their DDL in their corresponding schema source and are invoked here when
# they are part of fresh-bundle initialization.

.wb_ensure_cell_set_membership_table <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS cell_set_membership (
      cell_set    TEXT NOT NULL,
      cell_id     TEXT NOT NULL,
      source      TEXT,
      created_at  TEXT NOT NULL,
      created_by  TEXT,
      description TEXT,
      PRIMARY KEY(cell_set, cell_id)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_csm_set ON cell_set_membership(cell_set);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_csm_cell ON cell_set_membership(cell_id);")
  invisible(TRUE)
}

.wb_ensure_cell_set_styles_table <- function(con) {
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS cell_set_styles (
      cell_set    TEXT PRIMARY KEY,
      label       TEXT,
      shape       INTEGER,
      size        REAL,
      alpha       REAL,
      stroke      REAL,
      outline     TEXT,
      fill_mode   TEXT,
      created_at  TEXT NOT NULL,
      created_by  TEXT,
      description TEXT
    );
  ")
  invisible(TRUE)
}

.wb_ensure_schema_app_bundle <- function(con) {
  DBI::dbExecute(con, "PRAGMA foreign_keys=ON;")
  DBI::dbExecute(con, "PRAGMA journal_mode=WAL;")
  DBI::dbExecute(con, "PRAGMA synchronous=NORMAL;")

  .wb_entity_lifecycle_tables(con)

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS datasets (
      dataset_id TEXT PRIMARY KEY,
      n_cells INTEGER
    );
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS cells (
      cell_id TEXT PRIMARY KEY,
      dataset_id TEXT
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_cells_dataset ON cells(dataset_id);")

  .wb_ensure_cell_set_membership_table(con)

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS spaces (
      space_id TEXT PRIMARY KEY,
      source TEXT,
      dims INTEGER,
      storage TEXT,
      description TEXT
    );
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS space_coords (
      space_id TEXT,
      cell_id TEXT,
      dim INTEGER,
      value REAL,
      PRIMARY KEY (space_id, cell_id, dim)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_space_coords_space ON space_coords(space_id);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_space_coords_cell ON space_coords(cell_id);")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS space_2d (
      space_id TEXT,
      cell_id TEXT,
      x REAL,
      y REAL,
      PRIMARY KEY (space_id, cell_id)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_space_2d_space ON space_2d(space_id);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_space_2d_cell ON space_2d(cell_id);")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS features (
      matrix_id    TEXT NOT NULL,
      feature_id   TEXT NOT NULL,
      feature_type TEXT,
      chr          TEXT,
      start        INTEGER,
      end          INTEGER,
      PRIMARY KEY (matrix_id, feature_id)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_features_matrix ON features(matrix_id);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_features_feature ON features(feature_id);")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS matrices (
      matrix_id    TEXT PRIMARY KEY,
      layer        TEXT,
      feature_type TEXT,
      n_features   INTEGER,
      n_cells      INTEGER,
      storage      TEXT,
      path         TEXT,
      description  TEXT,
      organism     TEXT,
      genome_build TEXT,
      genome_provider TEXT
    );
  ")

  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS matrix_cells (
      matrix_id TEXT,
      cell_id   TEXT,
      PRIMARY KEY (matrix_id, cell_id)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_matrix_cells_cell ON matrix_cells(cell_id);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_matrix_cells_matrix ON matrix_cells(matrix_id);")

  .wb_ensure_cell_set_styles_table(con)
  .wb_ensure_matrix_fragment_tables(con)

  invisible(TRUE)
}
