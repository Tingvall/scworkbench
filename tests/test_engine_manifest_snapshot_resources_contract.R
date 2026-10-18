.engine_manifest_snapshot_fixture <- function(extended_types = FALSE) {
  path <- tempfile("engine_manifest_snapshot_", fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), path, extended_types = extended_types)
  ns <- asNamespace("scworkbench")
  for (table in get(".wb_manifest_registry_table_names", ns)())
    DBI::dbExecute(con, paste0("CREATE TABLE ", DBI::dbQuoteIdentifier(con, table),
      " (id INTEGER PRIMARY KEY, label TEXT, value REAL);"))
  list(con = con, path = path)
}

.engine_manifest_snapshot_oracle <- function(con) {
  ns <- asNamespace("scworkbench")
  tables <- get(".wb_manifest_registry_table_names", ns)()
  tables <- intersect(tables, DBI::dbListTables(con))
  rows <- setNames(lapply(tables, function(table)
    get(".wb_manifest_table_identity_materialized", ns)(con, table)), tables)
  list(schema = "scworkbench.manifest.registry-state.v1",
    fingerprint = get(".wb_prov_sha256_object", ns)(rows), tables = rows)
}

test_engine_manifest_snapshot_shared_resources_contract <- function() {
  ns <- asNamespace("scworkbench")
  f <- .engine_manifest_snapshot_fixture()
  con <- f$con
  on.exit({DBI::dbDisconnect(con); unlink(c(f$path, paste0(f$path, c("-wal", "-shm"))))}, add = TRUE)
  DBI::dbExecute(con, "INSERT INTO cells VALUES(1,'one',1.5),(2,NULL,NULL);")
  before <- DBI::dbGetQuery(con, "PRAGMA cache_size;")
  temp <- DBI::dbGetQuery(con, "PRAGMA temp_store;")
  env <- new.env(parent = ns); count <- 0L; finished <- 0L; closed <- 0L
  original <- get(".wb_manifest_observation_resources", ns)
  env$.wb_manifest_observation_resources <- function(con, budgets) {
    count <<- count + 1L
    resources <- original(con, budgets)
    finish <- resources$observer$finish; close <- resources$close
    resources$observer$finish <- function() {finished <<- finished + 1L; finish()}
    resources$close <- function() {closed <<- closed + 1L; close()}
    resources
  }
  snapshot <- get(".wb_manifest_registry_snapshot", ns); environment(snapshot) <- env
  actual <- snapshot(con)
  stopifnot(identical(actual, .engine_manifest_snapshot_oracle(con)), count == 1L,
    finished == 1L, closed == 1L, length(actual$tables) == 46L,
    identical(DBI::dbGetQuery(con, "PRAGMA cache_size;"), before),
    identical(DBI::dbGetQuery(con, "PRAGMA temp_store;"), temp),
    is.null(con@ref$wb_graph_policy))
  # No cross-invocation state is reused, and ordinary registry changes remain visible.
  DBI::dbExecute(con, "UPDATE cells SET label='changed' WHERE id=1;")
  changed <- snapshot(con)
  stopifnot(count == 2L, finished == 2L, closed == 2L,
    !identical(changed$fingerprint, actual$fingerprint),
    identical(changed, .engine_manifest_snapshot_oracle(con)))
  # Scope restoration also preserves a caller's already constrained graph policy.
  policy <- get(".wb_graph_budgets", ns)(list(partition_rows = 2L))
  con@ref$wb_graph_policy <- policy
  con@ref$wb_graph_cache_kib <- 1024L
  stopifnot(identical(snapshot(con), changed),
    identical(con@ref$wb_graph_policy, policy),
    identical(con@ref$wb_graph_cache_kib, 1024L))
  con@ref$wb_graph_policy <- NULL; con@ref$wb_graph_cache_kib <- NULL
  TRUE
}

test_engine_manifest_snapshot_types_and_fallback_contract <- function() {
  ns <- asNamespace("scworkbench")
  f <- .engine_manifest_snapshot_fixture(extended_types = TRUE); con <- f$con
  on.exit({DBI::dbDisconnect(con); unlink(f$path)}, add = TRUE)
  DBI::dbExecute(con, "DROP TABLE cells;")
  DBI::dbExecute(con, "CREATE TABLE cells (id INTEGER PRIMARY KEY,numeric_value,day DATE,stamp TIMESTAMP,body TEXT,bytes BLOB);")
  for (i in seq_len(7L)) DBI::dbExecute(con,
    "INSERT INTO cells VALUES(?,?,?,?,?,?);", params = list(i,
      if (i < 4L) as.integer(i) else i + .25, as.numeric(as.Date("2020-01-01")) + i,
      as.numeric(as.POSIXct("2020-01-01", tz = "UTC")) + i,
      if (i == 6L) paste(rep("\u00e9\n\\\"", 2000L), collapse = "") else paste0("row", i),
      list(as.raw(rep(seq_len(255L), if (i == 7L) 20L else 1L)))))
  table <- get(".wb_manifest_table_identity", ns)
  oracle <- get(".wb_manifest_table_identity_materialized", ns)
  stopifnot(identical(table(con, "cells", chunk_size = 2L),
    suppressWarnings(oracle(con, "cells", chunk_size = 2L))),
    identical(get(".wb_manifest_registry_snapshot", ns)(con),
      .engine_manifest_snapshot_oracle(con)))
  # Existing transaction fallback includes caller uncommitted rows and leaves TX open.
  DBI::dbBegin(con)
  DBI::dbExecute(con, "INSERT INTO matrices VALUES(1,'uncommitted',2);")
  stopifnot(identical(get(".wb_manifest_registry_snapshot", ns)(con),
    .engine_manifest_snapshot_oracle(con)), RSQLite::sqliteIsTransacting(con))
  DBI::dbRollback(con)
  mem <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(mem), add = TRUE)
  DBI::dbExecute(mem, "CREATE TABLE cells (id INTEGER PRIMARY KEY, label TEXT);")
  stopifnot(identical(get(".wb_manifest_registry_snapshot", ns)(mem),
    .engine_manifest_snapshot_oracle(mem)))
  TRUE
}

test_engine_manifest_snapshot_wal_change_and_cleanup_contract <- function() {
  ns <- asNamespace("scworkbench")
  f <- .engine_manifest_snapshot_fixture(); con <- f$con
  on.exit({DBI::dbDisconnect(con); unlink(c(f$path, paste0(f$path, c("-wal", "-shm"))))}, add = TRUE)
  DBI::dbGetQuery(con, "PRAGMA journal_mode=WAL;")
  writer <- DBI::dbConnect(RSQLite::SQLite(), f$path)
  on.exit(DBI::dbDisconnect(writer), add = TRUE)
  before <- DBI::dbGetQuery(con, "PRAGMA cache_size;")
  temp <- DBI::dbGetQuery(con, "PRAGMA temp_store;")
  env <- new.env(parent = ns); index <- 0L
  original <- get(".wb_manifest_table_identity", ns)
  env$.wb_manifest_table_identity <- function(...) {
    out <- original(...); index <<- index + 1L
    if (index == 1L) DBI::dbExecute(writer, "INSERT INTO cells VALUES(1,'concurrent',1);")
    out
  }
  snapshot <- get(".wb_manifest_registry_snapshot", ns); environment(snapshot) <- env
  error <- tryCatch(snapshot(con), error = identity)
  stopifnot(inherits(error, "error"), grepl("source changed", conditionMessage(error)),
    identical(DBI::dbGetQuery(con, "PRAGMA cache_size;"), before),
    identical(DBI::dbGetQuery(con, "PRAGMA temp_store;"), temp),
    is.null(con@ref$wb_graph_policy))
  env$.wb_manifest_table_identity <- function(...) stop("injected table failure")
  error <- tryCatch(snapshot(con), error = identity)
  stopifnot(inherits(error, "error"), grepl("injected table failure", conditionMessage(error)),
    identical(DBI::dbGetQuery(con, "PRAGMA cache_size;"), before),
    identical(DBI::dbGetQuery(con, "PRAGMA temp_store;"), temp))
  # All cursors/observers close on failures: writer checkpoint and next snapshot work.
  checkpoint <- DBI::dbGetQuery(writer, "PRAGMA wal_checkpoint(TRUNCATE);")
  stopifnot(checkpoint$busy[[1L]] == 0L,
    identical(get(".wb_manifest_registry_snapshot", ns)(con),
      .engine_manifest_snapshot_oracle(con)))
  TRUE
}
