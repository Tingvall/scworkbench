.engine_schema_environment <- function() getOption(
  "scworkbench.engine_schema_test_environment", asNamespace("scworkbench"))

.engine_schema_function <- function(name) get(name,
  envir = .engine_schema_environment(), inherits = TRUE)

.engine_schema_tracker <- function() {
  env <- new.env(parent = .engine_schema_environment())
  counts <- new.env(parent = emptyenv()); counts$fk <- 0L; counts$ledger <- 0L
  foreign <- .engine_schema_function(".wb_schema_table_foreign_key_status")
  ledger <- .engine_schema_function(".wb_schema_ledger_exists")
  env$.wb_schema_table_foreign_key_status <- function(con, table) {
    counts$fk <- counts$fk + 1L; foreign(con, table)
  }
  env$.wb_schema_ledger_exists <- function(con) {
    counts$ledger <- counts$ledger + 1L; ledger(con)
  }
  status <- .engine_schema_function(".wb_schema_status"); environment(status) <- env
  env$.wb_schema_status <- status
  public <- .engine_schema_function("wb_bundle_schema_status"); environment(public) <- env
  list(status = status, public = public, counts = counts)
}

test_engine_schema_observation_ledger_and_full_reads_contract <- function() {
  root <- tempfile("scwb_schema_observation_")
  b <- wb_init_bundle(root)
  on.exit({try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE)}, add = TRUE)
  con <- b$con; con@ref$wb_schema_structure_observation <- NULL
  tracked <- .engine_schema_tracker(); status <- tracked$status
  first <- status(con); fk <- tracked$counts$fk; ledger <- tracked$counts$ledger
  stopifnot(first$status == "current", fk > 0L,
    is.list(con@ref$wb_schema_structure_observation),
    identical(status(con), first), tracked$counts$fk == fk,
    tracked$counts$ledger == ledger + 1L)
  # No row-data verdict is reused: the ledger stays authoritative on every call.
  migration <- DBI::dbGetQuery(con,
    "SELECT version,migration_id FROM bundle_schema_migrations ORDER BY version DESC LIMIT 1;")
  DBI::dbExecute(con, "UPDATE bundle_schema_migrations SET migration_id='wrong' WHERE version=?;",
    params = list(migration$version[[1L]]))
  stopifnot(status(con)$status == "invalid_ledger", tracked$counts$fk == fk)
  DBI::dbExecute(con, "UPDATE bundle_schema_migrations SET migration_id=? WHERE version=?;",
    params = list(migration$migration_id[[1L]], migration$version[[1L]]))
  stopifnot(identical(status(con), first))
  before <- tracked$counts$fk
  stopifnot(identical(status(con, verify_structure = TRUE), first),
    tracked$counts$fk > before)
  before <- tracked$counts$fk
  stopifnot(identical(tracked$public(b), first), tracked$counts$fk > before)
  con@ref$wb_graph_policy <- list(schema_observation_test = TRUE)
  before <- tracked$counts$fk
  stopifnot(identical(status(con), first), tracked$counts$fk > before,
    is.null(con@ref$wb_schema_structure_observation))
  con@ref$wb_graph_policy <- NULL
  TRUE
}

test_engine_schema_observation_ddl_temp_and_rollback_contract <- function() {
  root <- tempfile("scwb_schema_observation_ddl_")
  b <- wb_init_bundle(root)
  on.exit({try(DBI::dbRollback(b$con), silent = TRUE);
    try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE)}, add = TRUE)
  con <- b$con; tracked <- .engine_schema_tracker(); status <- tracked$status
  con@ref$wb_schema_structure_observation <- NULL
  good <- status(con); stopifnot(good$status == "current")
  original <- DBI::dbGetQuery(con,
    "SELECT sql FROM main.sqlite_schema WHERE type='table' AND name='artifact_umap_model';")$sql[[1L]]
  wrong <- sub("REFERENCES spaces", "REFERENCES matrices", original, fixed = TRUE)
  stopifnot(!identical(wrong, original))
  DBI::dbBegin(con)
  DBI::dbExecute(con, "DROP TABLE artifact_umap_model;")
  missing <- status(con)
  stopifnot(missing$status == "invalid_schema", is.null(con@ref$wb_schema_structure_observation))
  DBI::dbExecute(con, wrong)
  invalid <- status(con)
  stopifnot(invalid$status == "invalid_schema", grepl("unexpected=", invalid$message, fixed = TRUE),
    identical(invalid, status(con, verify_structure = TRUE)))
  DBI::dbRollback(con); stopifnot(identical(status(con), good))
  # A successful alternate DDL is rolled back, then an invalid DDL reuses its
  # SQLite epoch. Exact definitions, not the reused epoch, control reuse.
  variant <- sub("(", "( /* schema observation variant */ ", original, fixed = TRUE)
  DBI::dbBegin(con); DBI::dbExecute(con, "DROP TABLE artifact_umap_model;"); DBI::dbExecute(con, variant)
  stopifnot(identical(status(con), good))
  epoch <- DBI::dbGetQuery(con, "PRAGMA main.schema_version;")[[1L]]
  DBI::dbRollback(con)
  DBI::dbBegin(con); DBI::dbExecute(con, "DROP TABLE artifact_umap_model;"); DBI::dbExecute(con, wrong)
  stopifnot(identical(DBI::dbGetQuery(con, "PRAGMA main.schema_version;")[[1L]], epoch),
    status(con)$status == "invalid_schema")
  DBI::dbRollback(con); stopifnot(identical(status(con), good))
  # Case-insensitive TEMP shadow names must not obtain main's cached success.
  DBI::dbExecute(con, "CREATE TEMP TABLE ARTIFACT_UMAP_MODEL(artifact_id TEXT PRIMARY KEY,space_id TEXT,model_path TEXT);")
  stopifnot(status(con)$status == "invalid_schema")
  DBI::dbExecute(con, "DROP TABLE temp.ARTIFACT_UMAP_MODEL;")
  stopifnot(identical(status(con), good))
  nullable <- DBI::dbGetQuery(con,
    "SELECT sql FROM main.sqlite_schema WHERE name='artifact_pseudotime';")$sql[[1L]]
  nonnullable <- sub("pseudotime REAL", "pseudotime REAL NOT NULL", nullable, fixed = TRUE)
  stopifnot(!identical(nullable, nonnullable))
  temp <- sub("CREATE TABLE", "CREATE TEMP TABLE", nonnullable, fixed = TRUE)
  DBI::dbExecute(con, temp)
  shadow <- status(con)
  stopifnot(shadow$status == "invalid_schema", grepl("not nullable", shadow$message, fixed = TRUE))
  DBI::dbExecute(con, "DROP TABLE temp.artifact_pseudotime;")
  stopifnot(identical(status(con), good))
  DBI::dbBegin(con); DBI::dbExecute(con, "DROP TABLE artifact_pseudotime;"); DBI::dbExecute(con, nonnullable)
  invalid <- status(con)
  stopifnot(invalid$status == "invalid_schema", grepl("not nullable", invalid$message, fixed = TRUE),
    identical(invalid, status(con, verify_structure = TRUE)))
  DBI::dbRollback(con); stopifnot(identical(status(con), good))
  TRUE
}

test_engine_schema_observation_connection_backup_and_forget_contract <- function() {
  root <- tempfile("scwb_schema_observation_backup_")
  b <- wb_init_bundle(root)
  on.exit({try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE)}, add = TRUE)
  tracked <- .engine_schema_tracker(); status <- tracked$status
  con <- b$con; con@ref$wb_schema_structure_observation <- NULL
  stopifnot(status(con)$status == "current")
  databases <- DBI::dbGetQuery(con, "PRAGMA database_list;")
  path <- databases$file[databases$name == "main"]
  other <- DBI::dbConnect(RSQLite::SQLite(), path, flags = RSQLite::SQLITE_RO)
  on.exit(try(DBI::dbDisconnect(other), silent = TRUE), add = TRUE)
  stopifnot(is.null(other@ref$wb_schema_structure_observation))
  before <- tracked$counts$fk
  stopifnot(status(other)$status == "current", tracked$counts$fk > before)
  .engine_schema_function(".wb_session_source_forget")(con)
  stopifnot(is.null(con@ref$wb_schema_structure_observation))
  stopifnot(status(con)$status == "current")
  backup <- file.path(root, "schema-observation-backup.sqlite")
  .engine_schema_function(".wb_session_sqlite_backup")(con, backup)
  stopifnot(is.null(con@ref$wb_schema_structure_observation))
  copied <- DBI::dbConnect(RSQLite::SQLite(), backup, flags = RSQLite::SQLITE_RO)
  on.exit(try(DBI::dbDisconnect(copied), silent = TRUE), add = TRUE)
  stopifnot(is.null(copied@ref$wb_schema_structure_observation), status(copied)$status == "current")
  TRUE
}
