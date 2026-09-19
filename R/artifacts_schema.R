.wb_create_artifacts_schema <- function(con) {
  ensure_model_tree_columns <- function() {
    columns <- c(
      model_primary_path = "TEXT",
      model_tree_manifest_json = "TEXT",
      payload_manifest_identity_json = "TEXT"
    )
    for (column in names(columns)) {
      if (!.wb_db_has_column(con, "artifact_model_ref", column)) {
        DBI::dbExecute(con, paste0(
          "ALTER TABLE artifact_model_ref ADD COLUMN ", column, " ",
          columns[[column]], ";"
        ))
      }
    }
    invisible(TRUE)
  }
  if (.wb_schema_component_is_current(con, c(
    "artifacts", "artifact_labels", "artifact_pseudotime", "artifact_relation_rows",
    "artifact_curves_2d", "artifact_space_path_meta", "artifact_space_path_rows",
    "artifact_umap_model", "artifact_model_ref", "artifact_tables",
    "artifact_table_rows"
  ))) {
    if (!.wb_db_has_column(con, "artifact_model_ref", "linkage_json"))
      DBI::dbExecute(con,
        "ALTER TABLE artifact_model_ref ADD COLUMN linkage_json TEXT;")
    ensure_model_tree_columns()
    return(invisible(TRUE))
  }
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
      provenance_snapshot_id TEXT,
      lineage_status TEXT,
      provenance_json TEXT NOT NULL,
      scworkbench_version TEXT
    );
  ")

  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_artifacts_type ON artifacts(type);")
  if (!.wb_db_has_column(con, "artifacts", "provenance_snapshot_id")) {
    DBI::dbExecute(con, "ALTER TABLE artifacts ADD COLUMN provenance_snapshot_id TEXT;")
  }
  if (!.wb_db_has_column(con, "artifacts", "lineage_status")) {
    DBI::dbExecute(con, "ALTER TABLE artifacts ADD COLUMN lineage_status TEXT;")
  }

  # cell_vector stored as per-cell labels (string)
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS artifact_labels (
      artifact_id TEXT NOT NULL,
      cell_id TEXT NOT NULL,
      label TEXT NOT NULL,
      PRIMARY KEY (artifact_id, cell_id)
    );
  ")
  if (!.wb_db_has_column(con, "artifact_labels", "value_type")) {
    DBI::dbExecute(con, "ALTER TABLE artifact_labels ADD COLUMN value_type TEXT;")
  }
  if (!.wb_db_has_column(con, "artifact_labels", "value_num")) {
    DBI::dbExecute(con, "ALTER TABLE artifact_labels ADD COLUMN value_num REAL;")
  }
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

  # generic long relation rows (relation_family)
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS artifact_relation_rows (
      artifact_id TEXT NOT NULL,
      relation_key TEXT NOT NULL,
      cell_id TEXT NOT NULL,
      weight REAL,
      value REAL,
      distance REAL,
      PRIMARY KEY (artifact_id, relation_key, cell_id)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_relation_rows_artifact ON artifact_relation_rows(artifact_id);")

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

  # analytical high-dimensional paths
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS artifact_space_path_meta (
      artifact_id TEXT PRIMARY KEY,
      meta_json TEXT
    );
  ")
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS artifact_space_path_rows (
      artifact_id TEXT NOT NULL,
      space_id TEXT NOT NULL,
      path_id TEXT NOT NULL,
      point INTEGER NOT NULL,
      dim INTEGER NOT NULL,
      value REAL NOT NULL,
      PRIMARY KEY (artifact_id, path_id, point, dim)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_space_path_rows_artifact ON artifact_space_path_rows(artifact_id);")

  # optional UMAP model reference
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS artifact_umap_model (
      artifact_id TEXT PRIMARY KEY,
      space_id TEXT NOT NULL,
      model_path TEXT NOT NULL
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_art_umap_model_space ON artifact_umap_model(space_id);")

  # generic model references (engine-tagged; supports non-UMAP models such as slingshot fits)
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS artifact_model_ref (
      artifact_id TEXT PRIMARY KEY,
      engine TEXT NOT NULL,
      model_space_id TEXT NOT NULL,
      in_space_id TEXT,
      model_type TEXT,
      model_path TEXT NOT NULL
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_art_model_ref_engine ON artifact_model_ref(engine);")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_art_model_ref_space ON artifact_model_ref(model_space_id);")
  if (!.wb_db_has_column(con, "artifact_model_ref", "linkage_json")) {
    DBI::dbExecute(con,
      "ALTER TABLE artifact_model_ref ADD COLUMN linkage_json TEXT;")
  }
  ensure_model_tree_columns()

  # generic tabular outputs (feature_table / obs_table)
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS artifact_tables (
      artifact_id TEXT PRIMARY KEY,
      table_type TEXT NOT NULL,
      entity_kind TEXT NOT NULL,
      meta_json TEXT
    );
  ")
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS artifact_table_rows (
      artifact_id TEXT NOT NULL,
      row_idx INTEGER NOT NULL,
      row_json TEXT NOT NULL,
      PRIMARY KEY (artifact_id, row_idx)
    );
  ")
  DBI::dbExecute(con, "CREATE INDEX IF NOT EXISTS idx_art_table_rows_artifact ON artifact_table_rows(artifact_id);")

  invisible(TRUE)
}
