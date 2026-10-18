.engine_manifest_small_fixture <- function(extended_types = FALSE) {
  path <- tempfile("manifest_small_", fileext = ".sqlite")
  list(path = path, con = DBI::dbConnect(RSQLite::SQLite(), path,
    extended_types = extended_types))
}
.engine_manifest_small_close <- function(fixture) {
  if (DBI::dbIsValid(fixture$con)) DBI::dbDisconnect(fixture$con)
  unlink(paste0(fixture$path, c("", "-wal", "-shm")))
}

# Frozen materialized registry-table.v1 algorithm, independent of the optimized
# chunk admission/hash helper. Keep 5000-row logical framing and R type metadata.
.engine_manifest_small_oracle <- function(con, table, chunk_size = 5000L) {
  hash <- function(value) digest::digest(jsonlite::serializeJSON(value, digits = NA),
    algo = "sha256", serialize = FALSE)
  fields <- DBI::dbGetQuery(con, paste0("PRAGMA table_info(", DBI::dbQuoteIdentifier(con, table), ");"))
  state <- hash(list(schema = "scworkbench.manifest.registry-table.v1", table = table,
    columns = fields[, intersect(c("name", "type", "notnull", "pk"), names(fields)), drop = FALSE]))
  query <- DBI::dbSendQuery(con, paste0("SELECT * FROM ", DBI::dbQuoteIdentifier(con, table), " ORDER BY rowid;"))
  on.exit(DBI::dbClearResult(query), add = TRUE)
  n <- 0L
  repeat {
    rows <- DBI::dbFetch(query, n = as.integer(chunk_size))
    if (!nrow(rows)) break
    n <- n + nrow(rows)
    json <- as.character(jsonlite::toJSON(rows, dataframe = "rows", auto_unbox = TRUE,
      null = "null", na = "null"))
    state <- hash(list(previous = state,
      rows_sha256 = digest::digest(json, algo = "sha256", serialize = FALSE)))
  }
  list(row_count = as.integer(n), content_sha256 = state)
}

test_engine_manifest_small_chunk_boundaries_contract <- function() {
  f <- .engine_manifest_small_fixture(); con <- f$con
  on.exit(.engine_manifest_small_close(f), add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE boundary(id INTEGER,label TEXT,value REAL);")
  for (count in c(0L, 1L, 4999L, 5000L, 5001L)) {
    DBI::dbExecute(con, "DELETE FROM boundary;")
    if (count) DBI::dbAppendTable(con, "boundary", data.frame(id = seq_len(count),
      label = rep(c("Tokyo東京é😀\n\001\r\t\"\\", "", NA_character_), length.out = count),
      value = seq_len(count) / 13))
    stopifnot(identical(.engine_manifest_small_oracle(con, "boundary"),
      scworkbench:::.wb_manifest_table_identity(con, "boundary")))
  }
  # Rowid order is signed int64, independent of an ordinary scientific id field.
  DBI::dbExecute(con, "DELETE FROM boundary;")
  DBI::dbExecute(con, "INSERT INTO boundary(rowid,id,label,value) VALUES(-4,1,'negative',1),(9007199254740993,2,'large',2);")
  stopifnot(identical(.engine_manifest_small_oracle(con, "boundary", 1L),
    scworkbench:::.wb_manifest_table_identity(con, "boundary", 1L)))
  TRUE
}

test_engine_manifest_small_chunk_types_and_deferred_contract <- function() {
  f <- .engine_manifest_small_fixture(TRUE); con <- f$con
  on.exit(.engine_manifest_small_close(f), add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE extended(v,d DATE,t TIMESTAMP,z TIME,caption TEXT);")
  for (i in seq_len(7L)) DBI::dbExecute(con, "INSERT INTO extended VALUES(?,?,?,?,?);",
    params = list(if (i < 3L) i else if (i == 6L) NA else i + .25,
      if (i == 4L) NA else 120 + i, if (i == 4L) NA else 123456 + i,
      if (i == 4L) NA else 3600 + i, if (i == 4L) NA_character_ else "東京\n\r\t\"\\"))
  for (chunk in c(1L, 2L, 5000L)) stopifnot(identical(
    .engine_manifest_small_oracle(con, "extended", chunk),
    scworkbench:::.wb_manifest_table_identity(con, "extended", chunk)))
  DBI::dbExecute(con, "CREATE TABLE mixed(value);")
  for (value in list(1L, 2L, 2.5, "123", "hello", NA))
    DBI::dbExecute(con, "INSERT INTO mixed VALUES(?);", params = list(value))
  for (chunk in c(1L, 2L, 5000L)) stopifnot(identical(
    suppressWarnings(.engine_manifest_small_oracle(con, "mixed", chunk)),
    suppressWarnings(scworkbench:::.wb_manifest_table_identity(con, "mixed", chunk))))
  DBI::dbExecute(con, "CREATE TABLE deferred(caption TEXT,payload BLOB);")
  DBI::dbExecute(con, "CREATE TABLE text_boundary(caption TEXT);")
  for (caption in c(strrep("a", 256L), strrep("a", 257L),
      strrep("é", 128L), paste0(strrep("é", 128L), "z"))) {
    DBI::dbExecute(con, "INSERT INTO deferred VALUES(?,?);",
      params = list(caption, list(as.raw(c(0, 255, 1, 2)))))
    DBI::dbExecute(con, "INSERT INTO text_boundary VALUES(?);", params = list(caption))
  }
  # A late deferred field excludes the ENTIRE chunk, never only its first row.
  seen <- 0L; old <- options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "manifest_small_chunk" && state$table %in% c("deferred", "text_boundary"))
      seen <<- seen + 1L
  })
  on.exit(options(old), add = TRUE)
  stopifnot(identical(.engine_manifest_small_oracle(con, "deferred"),
    scworkbench:::.wb_manifest_table_identity(con, "deferred")),
    identical(.engine_manifest_small_oracle(con, "text_boundary"),
      scworkbench:::.wb_manifest_table_identity(con, "text_boundary")), seen == 0L)
  TRUE
}

test_engine_manifest_small_chunk_reservation_and_fallback_contract <- function() {
  f <- .engine_manifest_small_fixture(); con <- f$con
  on.exit(.engine_manifest_small_close(f), add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE admitted(id INTEGER,label TEXT,value REAL);")
  DBI::dbExecute(con, "INSERT INTO admitted VALUES(1,'escaped \"\\',1.5);")
  seen <- 0L; before <- list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;"),
    temp = DBI::dbGetQuery(con, "PRAGMA temp_store;"), policy = con@ref$wb_graph_policy)
  old <- options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "manifest_small_chunk") {
      seen <<- seen + 1L
      stopifnot(state$carrier_bytes + 8 * state$encoded_bytes == state$reservation_bytes,
        state$reservation_bytes <= state$decoded_reservation_bytes,
        state$fetched_carrier_bytes + state$budgets$sqlite_cache_kib * 1024 +
          state$decoded_reservation_bytes + 65536 <= as.numeric(state$budgets$memory_bytes))
    }
  })
  on.exit(options(old), add = TRUE)
  expected <- .engine_manifest_small_oracle(con, "admitted")
  stopifnot(identical(expected, scworkbench:::.wb_manifest_table_identity(con, "admitted")), seen == 1L)
  tiny <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608", sqlite_cache_kib = 2048L,
    partition_bytes = 128L, partition_rows = 256L, collect_bytes = 4194304L))
  stopifnot(identical(expected, scworkbench:::.wb_manifest_table_identity(con, "admitted", budgets = tiny)),
    seen == 1L) # Existing streamed route, not an after-serialization rejection.
  too_small <- tiny; too_small$token_bytes <- "1"
  failure <- tryCatch(scworkbench:::.wb_manifest_table_identity(con, "admitted", budgets = too_small), error = identity)
  stopifnot(inherits(failure, "error"), identical(before,
    list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;"), temp = DBI::dbGetQuery(con, "PRAGMA temp_store;"),
      policy = con@ref$wb_graph_policy)))
  options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "manifest_small_chunk") stop("SMALL_CHUNK_INJECTED")
  })
  failure <- tryCatch(scworkbench:::.wb_manifest_table_identity(con, "admitted"), error = identity)
  stopifnot(inherits(failure, "error"), grepl("SMALL_CHUNK_INJECTED", conditionMessage(failure)))
  options(old)
  stopifnot(identical(expected, scworkbench:::.wb_manifest_table_identity(con, "admitted")))
  TRUE
}

test_engine_manifest_small_chunk_count_fail_closed_contract <- function() {
  f <- .engine_manifest_small_fixture(); con <- f$con
  on.exit(.engine_manifest_small_close(f), add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE counted(value INTEGER);")
  DBI::dbExecute(con, "INSERT INTO counted VALUES(1),(2);")
  # Instrument ONLY the external fetch in a function copy; all count/guard/hash
  # logic is the actual installed function. Never modify a live SQL cursor/native body.
  instrument <- function(mode) {
    ns <- asNamespace("scworkbench"); env <- new.env(parent = ns)
    env$.engine_fetch <- function(query, n) {
      rows <- DBI::dbFetch(query, n)
      if (mode == "zero") rows[FALSE, , drop = FALSE] else
        if (mode == "short") rows[1L, , drop = FALSE] else rbind(rows, rows[1L, , drop = FALSE])
    }
    fn <- get(".wb_manifest_table_identity", ns)
    text <- paste(deparse(body(fn), width.cutoff = 500L), collapse = "\n")
    stopifnot(length(gregexpr("DBI::dbFetch", text, fixed = TRUE)[[1L]]) == 1L)
    body(fn) <- parse(text = gsub("DBI::dbFetch", ".engine_fetch", text, fixed = TRUE))[[1L]]
    environment(fn) <- env
    fn
  }
  for (mode in c("short", "zero", "over")) {
    failure <- tryCatch(instrument(mode)(con, "counted"), error = identity)
    stopifnot(inherits(failure, "error"), grepl("admitted row count", conditionMessage(failure)))
  }
  stopifnot(identical(.engine_manifest_small_oracle(con, "counted"),
    scworkbench:::.wb_manifest_table_identity(con, "counted")))
  TRUE
}

test_engine_manifest_small_chunk_snapshot_scope_and_wal_contract <- function() {
  f <- .engine_manifest_small_fixture(); con <- f$con
  on.exit(.engine_manifest_small_close(f), add = TRUE)
  DBI::dbGetQuery(con, "PRAGMA journal_mode=WAL;")
  writer <- DBI::dbConnect(RSQLite::SQLite(), f$path)
  on.exit(DBI::dbDisconnect(writer), add = TRUE)
  for (table in c("cells", "matrices")) DBI::dbExecute(con,
    paste0("CREATE TABLE ", table, "(value INTEGER);"))
  DBI::dbExecute(con, "INSERT INTO cells VALUES(1);")
  DBI::dbExecute(con, "INSERT INTO matrices VALUES(2);")
  before <- list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;"),
    temp = DBI::dbGetQuery(con, "PRAGMA temp_store;"))
  for (changed_table in c("cells", "matrices")) {
    changed <- FALSE
    old <- options(scworkbench.graph_storage_test_hook = function(event, state) {
      if (event == "manifest_chunk" && state$table == changed_table && !changed) {
        changed <<- TRUE
        DBI::dbExecute(writer, "UPDATE cells SET value=value+1;")
      }
    })
    failure <- tryCatch(scworkbench:::.wb_manifest_registry_snapshot(con), error = identity)
    options(old)
    stopifnot(inherits(failure, "error"), grepl("source changed", conditionMessage(failure)))
  }
  # Count initial/final graph-spill admission in a scoped helper copy; actual
  # installed snapshot tests above exercise its normal resource lifetime.
  ns <- asNamespace("scworkbench"); env <- new.env(parent = ns); calls <- 0L
  original <- get(".wb_graph_spill_admit", ns)
  env$.wb_graph_spill_admit <- function(...) {calls <<- calls + 1L; original(...)}
  resources <- get(".wb_manifest_observation_resources", ns); environment(resources) <- env
  scope <- resources(con, get(".wb_graph_budgets", ns)())
  scope$observer$finish(); scope$close()
  stopifnot(calls == 2L, identical(before, list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;"),
    temp = DBI::dbGetQuery(con, "PRAGMA temp_store;"))))
  # All-empty snapshots still have initial AND final aggregate admission;
  # either fault must unwind every owned connection/native snapshot and policy.
  DBI::dbExecute(con, "DELETE FROM cells;"); DBI::dbExecute(con, "DELETE FROM matrices;")
  env$.wb_manifest_observation_resources <- resources
  snapshot <- get(".wb_manifest_registry_snapshot", ns); environment(snapshot) <- env
  for (fail_at in c(1L, 2L)) {
    calls <- 0L
    env$.wb_graph_spill_admit <- function(...) {
      calls <<- calls + 1L
      if (calls == fail_at) stop("SNAPSHOT_SPILL_INJECTED")
      original(...)
    }
    failure <- tryCatch(snapshot(con), error = identity)
    stopifnot(inherits(failure, "error"), grepl("SNAPSHOT_SPILL_INJECTED", conditionMessage(failure)),
      calls == fail_at, identical(before, list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;"),
        temp = DBI::dbGetQuery(con, "PRAGMA temp_store;"))))
  }
  checkpoint <- DBI::dbGetQuery(writer, "PRAGMA wal_checkpoint(TRUNCATE);")
  stopifnot(checkpoint$busy[[1L]] == 0L)
  TRUE
}
