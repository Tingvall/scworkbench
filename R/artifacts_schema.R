.wb_create_artifacts_schema <- function(con) {
  # core artifacts registry
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS artifacts (
      artifact_id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      name TEXT,
      description TEXT,
      created_at TEXT NOT NULL,
      created_by TEXT,
      source_op TEXT,
      input_space_id TEXT,
      input_matrix_id TEXT,
      cell_set TEXT,
      provenance_json TEXT NOT NULL,
      scworkbench_version TEXT
    );
  ")

  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_artifacts_type ON artifacts(type);")

  # cell_vector stored as per-cell labels (string)
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS artifact_labels (
      artifact_id TEXT NOT NULL,
      cell_id TEXT NOT NULL,
      label TEXT NOT NULL,
      PRIMARY KEY (artifact_id, cell_id)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_labels_artifact ON artifact_labels(artifact_id);")

  # cell_vector_family stored as pseudotime-like (numeric)
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS artifact_pseudotime (
      artifact_id TEXT NOT NULL,
      cell_id TEXT NOT NULL,
      lineage_id TEXT NOT NULL,
      pseudotime REAL NOT NULL,
      PRIMARY KEY (artifact_id, cell_id, lineage_id)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_pt_artifact ON artifact_pseudotime(artifact_id);")

  # path_2d_family
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS artifact_curves_2d (
      artifact_id TEXT NOT NULL,
      lineage_id TEXT NOT NULL,
      point INTEGER NOT NULL,
      x REAL NOT NULL,
      y REAL NOT NULL,
      PRIMARY KEY (artifact_id, lineage_id, point)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_curve_artifact ON artifact_curves_2d(artifact_id);")

  # optional snapshot of 2D space
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS artifact_space_2d (
      artifact_id TEXT NOT NULL,
      cell_id     TEXT NOT NULL,
      x           REAL NOT NULL,
      y           REAL NOT NULL,
      PRIMARY KEY (artifact_id, cell_id)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_art_space2d_artifact ON artifact_space_2d(artifact_id);")

  # optional UMAP model reference
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS artifact_umap_model (
      artifact_id TEXT PRIMARY KEY,
      space_id TEXT NOT NULL,
      model_path TEXT NOT NULL
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_art_umap_model_space ON artifact_umap_model(space_id);")

  invisible(TRUE)
}
