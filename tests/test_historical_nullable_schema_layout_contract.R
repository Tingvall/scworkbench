test_historical_nullable_schema_unexpected_column_rejects_contract <- function() {
  source("tests/fixtures/historical_schema_payload_order_support.R", local = TRUE)
  con <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE artifact_labels(artifact_id TEXT NOT NULL,cell_id TEXT NOT NULL,label TEXT NOT NULL,PRIMARY KEY(artifact_id,cell_id));")
  DBI::dbExecute(con, "CREATE TABLE artifact_pseudotime(artifact_id TEXT NOT NULL,cell_id TEXT NOT NULL,lineage_id TEXT NOT NULL,pseudotime REAL NOT NULL,PRIMARY KEY(artifact_id,cell_id,lineage_id));")
  DBI::dbExecute(con, "INSERT INTO artifact_pseudotime VALUES('a','c','l',0.25);")
  fixture_restore_pre_graph_payload_layout(con)
  DBI::dbExecute(con, "ALTER TABLE artifact_pseudotime ADD COLUMN unexpected_source INTEGER;")
  before <- DBI::dbGetQuery(con, "SELECT type,name,sql FROM sqlite_schema ORDER BY type,name;")
  rows <- DBI::dbGetQuery(con, "SELECT * FROM artifact_pseudotime;")
  failed <- tryCatch(scworkbench:::.wb_schema_migration_010(con), error = identity)
  stopifnot(inherits(failed, "error"), grepl("exact historical artifact_pseudotime columns", conditionMessage(failed), fixed = TRUE),
    identical(before, DBI::dbGetQuery(con, "SELECT type,name,sql FROM sqlite_schema ORDER BY type,name;")),
    identical(rows, DBI::dbGetQuery(con, "SELECT * FROM artifact_pseudotime;")))
  TRUE
}
