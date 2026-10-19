test_manifest_stream_scalar_and_sql_type_parity_contract <- function() {
  path <- tempfile("manifest_scalar_parity_", fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit({DBI::dbDisconnect(con); unlink(path)}, add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE scalar(a INTEGER,b REAL,caption TEXT,payload BLOB);")
  for (i in seq_len(8L)) DBI::dbExecute(con, "INSERT INTO scalar VALUES(?,?,?,?);", params = list(
    if (i == 5L) bit64::as.integer64("2147483648") else if (i == 6L) 2.5 else if (i == 8L) NA_integer_ else i,
    if (i == 1L) NA_real_ else c(1.23456789, -0, 2.5, 1e-200, 1e200, Inf, -Inf)[[i - 1L]],
    if (i == 1L) NA_character_ else if (i == 2L) "" else
      paste0("東京é😀\n\001\r\t\"\\", strrep("x", if (i %% 2L) 7000L else 5L)),
    list(if (i == 1L) NULL else if (i == 2L) raw() else as.raw(c(0, 1, 2, 255)))))
  for (chunk in c(1L, 2L, 3L, 5000L)) {
    old <- suppressWarnings(scworkbench:::.wb_manifest_table_identity_materialized(con, "scalar", chunk))
    observed <- suppressWarnings(scworkbench:::.wb_manifest_table_identity(con, "scalar", chunk))
    stopifnot(identical(old, observed))
  }
  DBI::dbExecute(con, "CREATE TABLE mixed(value);")
  for (sequence in list(list(1L, "123", "hello", NA), list(1.5, "123.4x", "hello", NA),
    list(bit64::as.integer64("2147483648"), strrep("0", 300L), "123", NA))) {
    DBI::dbExecute(con, "DELETE FROM mixed;")
    for (value in sequence) DBI::dbExecute(con, "INSERT INTO mixed VALUES(?);", params = list(value))
    for (chunk in c(1L, 2L, 5000L)) stopifnot(identical(
      suppressWarnings(scworkbench:::.wb_manifest_table_identity_materialized(con, "mixed", chunk)),
      suppressWarnings(scworkbench:::.wb_manifest_table_identity(con, "mixed", chunk))))
  }
  TRUE
}

test_manifest_stream_logical_chunk_boundary_contract <- function() {
  path <- tempfile("manifest_chunk_boundary_", fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit({DBI::dbDisconnect(con); unlink(path)}, add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE boundary(n INTEGER,caption TEXT);")
  DBI::dbAppendTable(con, "boundary", data.frame(n = seq_len(5001L),
    caption = rep(c("東京😀", "", NA_character_, "slash\\quote\""), length.out = 5001L)))
  for (count in c(4999L, 5000L, 5001L)) {
    DBI::dbExecute(con, "DELETE FROM boundary WHERE n>?;", params = list(count))
    stopifnot(identical(scworkbench:::.wb_manifest_table_identity_materialized(con, "boundary"),
      scworkbench:::.wb_manifest_table_identity(con, "boundary")))
    if (count < 5001L) DBI::dbAppendTable(con, "boundary", data.frame(n = seq.int(count + 1L, 5001L),
      caption = rep(c("東京😀", "", NA_character_, "slash\\quote\""), length.out = 5001L)[seq.int(count + 1L, 5001L)]))
  }
  DBI::dbExecute(con, "UPDATE boundary SET n=2147483648 WHERE rowid=5000;")
  stopifnot(identical(scworkbench:::.wb_manifest_table_identity_materialized(con, "boundary"),
    scworkbench:::.wb_manifest_table_identity(con, "boundary")))
  TRUE
}

test_manifest_stream_huge_single_text_contract <- function() {
  path <- tempfile("manifest_huge_text_", fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit({DBI::dbDisconnect(con); unlink(path)}, add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE huge(caption TEXT);")
  # Whole-object construction/old helper are the independent fixture oracle,
  # outside resource measurements. The production stream admits 8 MiB.
  value <- strrep("東京😀é\"\\\n", 650000L)
  stopifnot(nchar(value, type = "bytes") > 8388608)
  DBI::dbExecute(con, "INSERT INTO huge VALUES(?);", params = list(value))
  old <- scworkbench:::.wb_manifest_table_identity_materialized(con, "huge")
  policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608",
    partition_bytes = 262144L, partition_rows = 256L, collect_bytes = 4194304L,
    sqlite_cache_kib = 2048L))
  observed <- scworkbench:::.wb_manifest_table_identity(con, "huge", budgets = policy)
  stopifnot(identical(old, observed))
  TRUE
}

test_manifest_stream_late_mutation_and_transaction_contract <- function() {
  path <- tempfile("manifest_mutation_", fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  writer <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit({DBI::dbDisconnect(writer); DBI::dbDisconnect(con); unlink(paste0(path,
    c("", "-wal", "-shm")))}, add = TRUE)
  DBI::dbExecute(con, "PRAGMA journal_mode=WAL;")
  DBI::dbExecute(con, "CREATE TABLE mutation(caption TEXT);")
  DBI::dbExecute(con, "INSERT INTO mutation VALUES('original');")
  before_cache <- DBI::dbGetQuery(con, "PRAGMA cache_size;")[[1L]][[1L]]
  hook <- options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "manifest_chunk" && state$table == "mutation")
      DBI::dbExecute(writer, "UPDATE mutation SET caption='changed';")
  })
  on.exit(options(hook), add = TRUE)
  error <- tryCatch(scworkbench:::.wb_manifest_table_identity(con, "mutation"), error = identity)
  options(hook)
  stopifnot(inherits(error, "wb_graph_error"), grepl("source changed", conditionMessage(error), fixed = TRUE),
    DBI::dbGetQuery(con, "PRAGMA cache_size;")[[1L]][[1L]] == before_cache,
    is.null(con@ref$wb_graph_policy))
  DBI::dbBegin(con)
  DBI::dbExecute(con, "UPDATE mutation SET caption='uncommitted';")
  stopifnot(identical(scworkbench:::.wb_manifest_table_identity_materialized(con, "mutation"),
    scworkbench:::.wb_manifest_table_identity(con, "mutation")))
  DBI::dbRollback(con)
  TRUE
}

test_manifest_stream_extended_types_and_mixed_blob_contract <- function() {
  path <- tempfile("manifest_declared_types_", fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), path, extended_types = TRUE)
  on.exit({DBI::dbDisconnect(con); unlink(path)}, add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE extended(d DATE,t TIMESTAMP,z TIME,caption TEXT);")
  DBI::dbExecute(con, "INSERT INTO extended VALUES(123,123456,3600,'first');")
  DBI::dbExecute(con, "INSERT INTO extended VALUES(NULL,NULL,NULL,NULL);")
  for (chunk in c(1L, 2L, 5000L)) stopifnot(identical(
    scworkbench:::.wb_manifest_table_identity_materialized(con, "extended", chunk),
    scworkbench:::.wb_manifest_table_identity(con, "extended", chunk)))
  DBI::dbExecute(con, "CREATE TABLE mixed(value TEXT);")
  for (first_blob in c(FALSE, TRUE)) {
    DBI::dbExecute(con, "DELETE FROM mixed;")
    order <- if (first_blob) c(2L, 1L, 3L) else c(1L, 2L, 3L)
    for (ordinal in seq_along(order)) {
      i <- order[[ordinal]]
      value <- paste0("東京é😀\"\\\n", strrep("z", 6000L))
      DBI::dbExecute(con, "INSERT INTO mixed(rowid,value) VALUES(?,?);",
        params = list(ordinal - 4L, if (i == 2L) list(charToRaw(value)) else value))
    }
    # Signed rowids and storage type coercion preserve the original query's
    # order and late promotion at every fetch boundary.
    for (chunk in c(1L, 2L, 5000L)) stopifnot(identical(
      suppressWarnings(scworkbench:::.wb_manifest_table_identity_materialized(con, "mixed", chunk)),
      suppressWarnings(scworkbench:::.wb_manifest_table_identity(con, "mixed", chunk))))
  }
  TRUE
}


test_manifest_stream_small_batch_aggregate_and_fault_restoration_contract <- function() {
  path <- tempfile("manifest_batch_accounting_", fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
    on.exit({DBI::dbDisconnect(con); unlink(path)}, add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE admitted(cell_id TEXT,score REAL,annotation TEXT,discard INTEGER);")
  DBI::dbAppendTable(con, "admitted", data.frame(cell_id = paste0("cell_", seq_len(5001L), "_", strrep("x", 192L)),
    score = seq_len(5001L) / 13, annotation = NA_character_, discard = NA_integer_))
  expected <- scworkbench:::.wb_manifest_table_identity_materialized(con, "admitted")
  before <- list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;")[[1L]][[1L]],
    temp = DBI::dbGetQuery(con, "PRAGMA temp_store;")[[1L]][[1L]],
    policy = con@ref$wb_graph_policy, cap = con@ref$wb_graph_cache_kib)
  batches <- 0L; max_reserved <- 0; max_batch_rows <- 0L
  hook <- options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "manifest_scalar_batch") {
      batches <<- batches + 1L
      max_batch_rows <<- max(max_batch_rows, state$rows)
      max_reserved <<- max(max_reserved, state$reservation_bytes)
      stopifnot(state$rows <= state$candidate_rows, state$candidate_rows <= 5000L,
        state$carrier_bytes == 4096 + 576 * 4 + (16 * 4 + 32) * state$rows +
          128 * state$candidate_rows,
        state$carrier_bytes + 8 * state$encoded_bytes == state$reservation_bytes,
        state$budgets$memory_bytes == "8388608",
        state$reservation_bytes <= state$decoded_reservation_bytes,
        state$fetched_carrier_bytes + state$budgets$sqlite_cache_kib * 1024 +
          state$decoded_reservation_bytes + 65536 <= as.numeric(state$budgets$memory_bytes),
        state$con@ref$wb_graph_cache_kib + 128L <= 2048L,
        con@ref$wb_graph_policy$memory_bytes == "8388608")
    }
  })
  on.exit(options(hook), add = TRUE)
  for (partition in c(128L, 4096L, 262144L)) {
    policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608", sqlite_cache_kib = 2048L,
      partition_bytes = partition, partition_rows = 256L, collect_bytes = 4194304L))
    previous_batches <- batches
    observed <- scworkbench:::.wb_manifest_table_identity(con, "admitted", budgets = policy)
    stopifnot(identical(expected, observed))
    if (partition == 128L) stopifnot(batches == previous_batches)
    stopifnot(identical(before, list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;")[[1L]][[1L]],
      temp = DBI::dbGetQuery(con, "PRAGMA temp_store;")[[1L]][[1L]],
      policy = con@ref$wb_graph_policy, cap = con@ref$wb_graph_cache_kib)))
  }
  stopifnot(batches > 0L, max_batch_rows > 64L)
  options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "manifest_scalar_batch") stop("BATCH_ACCOUNTING_INJECTED")
  })
  error <- tryCatch({scworkbench:::.wb_manifest_table_identity(con, "admitted", budgets = policy); NULL}, error = identity)
  stopifnot(inherits(error, "error"), grepl("BATCH_ACCOUNTING_INJECTED", conditionMessage(error), fixed = TRUE),
    identical(before, list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;")[[1L]][[1L]],
      temp = DBI::dbGetQuery(con, "PRAGMA temp_store;")[[1L]][[1L]],
      policy = con@ref$wb_graph_policy, cap = con@ref$wb_graph_cache_kib)))
  options(hook)
  TRUE
}
