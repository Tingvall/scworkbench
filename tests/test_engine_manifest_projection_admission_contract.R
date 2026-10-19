.engine_manifest_projection_fixture <- function(wal = FALSE) {
  path <- tempfile("manifest_projection_admission_", fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  if (wal) DBI::dbExecute(con, "PRAGMA journal_mode=WAL;")
  list(path = path, con = con)
}

.engine_manifest_projection_close <- function(f) {
  on.exit(unlink(paste0(f$path, c("", "-wal", "-shm"))), add = TRUE)
  if (DBI::dbIsValid(f$con)) DBI::dbDisconnect(f$con)
}

test_engine_manifest_projection_coarse_capacity_and_identity_contract <- function() {
  f <- .engine_manifest_projection_fixture(); con <- f$con
  on.exit(.engine_manifest_projection_close(f), add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE entries(id INTEGER,label TEXT,payload BLOB);")
  DBI::dbAppendTable(con, "entries", data.frame(id = seq_len(5001L),
    label = rep(c("東京é", "short", NA_character_), length.out = 5001L),
    payload = I(rep(list(raw()), 5001L))))
  DBI::dbExecute(con, "UPDATE entries SET id=2147483648,label=? WHERE rowid=5000;",
    params = list(strrep("東京", 1000L)))
  DBI::dbExecute(con, "UPDATE entries SET payload=? WHERE rowid=2;",
    params = list(list(as.raw(c(0, 1, 255)))))
  expected <- scworkbench:::.wb_manifest_table_identity_materialized(con, "entries")
  before <- list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;"),
    temp = DBI::dbGetQuery(con, "PRAGMA temp_store;"), policy = con@ref$wb_graph_policy,
    reservation = con@ref$wb_graph_cache_kib)
  events <- list()
  old <- options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "manifest_projection_admission") {
      events[[length(events) + 1L]] <<- state
      stopifnot(state$mode == "coarse", state$reserved_capacity == 5000L,
        state$admitted_rows == 5000L, state$admitted_bytes == 320 * 5000 * 3,
        state$carrier_bytes + state$admitted_bytes + state$cache_bytes +
          state$decoded_reservation_bytes + state$fixed_bytes <= as.numeric(state$budgets$memory_bytes))
    }
  })
  on.exit(options(old), add = TRUE)
  stopifnot(identical(expected, scworkbench:::.wb_manifest_table_identity(con, "entries")),
    length(events) == 2L, events[[2L]]$admitted_rows == 5000L,
    identical(before, list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;"),
      temp = DBI::dbGetQuery(con, "PRAGMA temp_store;"), policy = con@ref$wb_graph_policy,
      reservation = con@ref$wb_graph_cache_kib)))
  TRUE
}

test_engine_manifest_projection_exact_fallback_and_predecode_rejection_contract <- function() {
  f <- .engine_manifest_projection_fixture(); con <- f$con
  on.exit(.engine_manifest_projection_close(f), add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE entries(a TEXT,b TEXT,c TEXT,d TEXT);")
  DBI::dbAppendTable(con, "entries", data.frame(a = rep("a", 5000L), b = "b", c = "c", d = "d"))
  policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608",
    sqlite_cache_kib = 2048L, partition_bytes = 262144L, partition_rows = 2L,
    collect_bytes = 4194304L))
  expected <- scworkbench:::.wb_manifest_table_identity_materialized(con, "entries")
  modes <- character(); decoded <- 0L
  old <- options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "manifest_projection_admission") {
      modes <<- c(modes, state$mode)
      stopifnot(state$mode == "exact", state$reserved_capacity == 5000L,
        state$admitted_rows == 5000L, state$admitted_bytes == 65 * 5000 * 4)
    }
    if (event %in% c("manifest_projection_decoded", "manifest_chunk", "manifest_scalar_batch", "manifest_small_chunk"))
      decoded <<- decoded + 1L
  })
  on.exit(options(old), add = TRUE)
  stopifnot(identical(expected, scworkbench:::.wb_manifest_table_identity(con, "entries", budgets = policy)),
    identical(modes, "exact"), decoded > 0L)
  DBI::dbExecute(con, "UPDATE entries SET a=?,b=?,c=?,d=?;", params = rep(list(strrep("x", 256L)), 4L))
  modes <- character(); decoded <- 0L
  failure <- tryCatch(scworkbench:::.wb_manifest_table_identity(con, "entries", budgets = policy), error = identity)
  stopifnot(inherits(failure, "wb_graph_error"), failure$code == "GRAPH_RESOURCE_EXCEEDED",
    length(modes) == 0L, decoded == 0L)
  DBI::dbExecute(con, "UPDATE entries SET a='a',b='b',c='c',d='d';")
  stopifnot(identical(expected, scworkbench:::.wb_manifest_table_identity(con, "entries", budgets = policy)))
  TRUE
}

test_engine_manifest_projection_foreign_insert_and_fault_cleanup_contract <- function() {
  f <- .engine_manifest_projection_fixture(TRUE); con <- f$con
  on.exit(.engine_manifest_projection_close(f), add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE entries(id INTEGER,label TEXT);")
  DBI::dbExecute(con, "INSERT INTO entries VALUES(1,'original');")
  writer <- DBI::dbConnect(RSQLite::SQLite(), f$path)
  on.exit(if (DBI::dbIsValid(writer)) DBI::dbDisconnect(writer), add = TRUE, after = FALSE)
  before <- list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;"),
    temp = DBI::dbGetQuery(con, "PRAGMA temp_store;"), policy = con@ref$wb_graph_policy,
    reservation = con@ref$wb_graph_cache_kib)
  inserted <- FALSE; admissions <- 0L; decoded_rows <- 0L
  old <- options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "manifest_before_cursor") {
      stopifnot(state$count == 1L)
      DBI::dbAppendTable(writer, "entries", data.frame(id = 2:1001, label = strrep("x", 256L)))
      inserted <<- TRUE
    }
    if (event == "manifest_projection_admission") {
      admissions <<- admissions + 1L
      stopifnot(inserted, state$mode == "coarse", state$reserved_capacity == 5000L,
        state$admitted_rows == 5000L, state$admitted_bytes == 320 * 5000 * 2)
    }
    if (event == "manifest_projection_decoded") {
      decoded_rows <<- state$rows
      stopifnot(state$initial_count == 1L, state$rows == 1001L,
        state$rows <= state$reserved_capacity, state$rows <= state$admitted_rows)
    }
  })
  on.exit(options(old), add = TRUE)
  failure <- tryCatch(scworkbench:::.wb_manifest_table_identity(con, "entries"), error = identity)
  options(old)
  stopifnot(inserted, admissions == 1L, decoded_rows == 1001L, inherits(failure, "wb_graph_error"),
    failure$code == "GRAPH_SOURCE_PAYLOAD_INVALID",
    grepl("logical chunk did not match", conditionMessage(failure), fixed = TRUE))
  # Real SQL after failure detects pending-cursor cleanup warnings as errors.
  withCallingHandlers(stopifnot(DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM entries;")$n[[1L]] == 1001L),
    warning = function(w) stop(conditionMessage(w)))
  DBI::dbExecute(writer, "DELETE FROM entries WHERE id>1;")
  expected <- scworkbench:::.wb_manifest_table_identity_materialized(con, "entries")
  options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "manifest_projection_admission") stop("PROJECTION_ADMISSION_FAULT")
  })
  failure <- tryCatch(scworkbench:::.wb_manifest_table_identity(con, "entries"), error = identity)
  options(old)
  stopifnot(inherits(failure, "error"), grepl("PROJECTION_ADMISSION_FAULT", conditionMessage(failure), fixed = TRUE),
    identical(expected, scworkbench:::.wb_manifest_table_identity(con, "entries")),
    identical(before, list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;"),
      temp = DBI::dbGetQuery(con, "PRAGMA temp_store;"), policy = con@ref$wb_graph_policy,
      reservation = con@ref$wb_graph_cache_kib)))
  TRUE
}
