test_engine_manifest_json_batch_decoupled_rows_and_fold_contract <- function() {
  path <- tempfile("manifest_json_batch_", fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit({DBI::dbDisconnect(con); unlink(path)}, add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE entries(id INTEGER,label TEXT);")
  policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608",
    sqlite_cache_kib = 2048L, partition_bytes = 262144L, partition_rows = 2L,
    collect_bytes = 4194304L))
  before <- list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;"),
    temp = DBI::dbGetQuery(con, "PRAGMA temp_store;"), policy = con@ref$wb_graph_policy,
    reservation = con@ref$wb_graph_cache_kib)
  sizes <- integer(); folds <- integer()
  old <- options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "manifest_scalar_batch") {
      sizes <<- c(sizes, state$rows)
      stopifnot(state$rows <= state$candidate_rows, state$candidate_rows <= 5000L,
        state$budgets$partition_rows == 2L,
        state$carrier_bytes == 4096 + 576 * 2 + (16 * 2 + 32) * state$rows +
          128 * state$candidate_rows,
        state$carrier_bytes + 8 * state$encoded_bytes == state$reservation_bytes,
        state$reservation_bytes <= 8 * state$budgets$partition_bytes,
        state$fetched_carrier_bytes + state$budgets$sqlite_cache_kib * 1024 +
          state$decoded_reservation_bytes + 65536 <= as.numeric(state$budgets$memory_bytes))
    }
    if (event == "manifest_chunk") folds <<- c(folds, state$rows)
  })
  on.exit(options(old), add = TRUE)
  for (count in c(0L, 1L, 4999L, 5000L, 5001L, 10020L)) {
    DBI::dbExecute(con, "DELETE FROM entries;")
    if (count) DBI::dbAppendTable(con, "entries", data.frame(id = seq_len(count),
      label = rep(c("x", "", NA_character_), length.out = count)))
    folds <- integer()
    expected <- scworkbench:::.wb_manifest_table_identity_materialized(con, "entries")
    actual <- scworkbench:::.wb_manifest_table_identity(con, "entries", budgets = policy)
    stopifnot(identical(actual, expected), identical(folds,
      if (!count) integer() else as.integer(c(rep(5000L, count %/% 5000L),
        if (count %% 5000L) count %% 5000L else integer()))),
      identical(before, list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;"),
        temp = DBI::dbGetQuery(con, "PRAGMA temp_store;"), policy = con@ref$wb_graph_policy,
        reservation = con@ref$wb_graph_cache_kib)))
  }
  stopifnot(any(sizes > 512L), any(sizes > policy$partition_rows))
  TRUE
}

test_engine_manifest_json_batch_graph_wire_partition_unchanged_contract <- function() {
  policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608",
    sqlite_cache_kib = 2048L, partition_bytes = 262144L, partition_rows = 2L,
    collect_bytes = 4194304L))
  # The SAME policy still constrains actual graph wire partitions to two
  # rows; only the private registry JSON batching is decoupled.
  graph <- wb_prim_graph(lapply(paste0("node_", seq_len(6L)), function(id)
    list(node_id = id)), list(), list())
  stage <- scworkbench:::.wb_graph_stage_small(graph, policy)
  wire <- tempfile("manifest_json_batch_graph_", fileext = ".jsonl")
  on.exit({scworkbench:::.wb_graph_stage_discard(stage); unlink(wire)}, add = TRUE)
  observations <- scworkbench:::.wb_graph_export_parts(stage$con, "staged", wire, policy)
  parts <- lapply(readLines(wire, warn = FALSE), scworkbench:::.wb_graph_parse)
  nodes <- Filter(function(part) identical(part$component, "nodes"), parts)
  stopifnot(length(nodes) == 3L, all(vapply(parts, function(part)
    length(part$rows) <= 2L, logical(1))),
    sum(vapply(nodes, function(part) length(part$rows), integer(1))) == 6L,
    identical(observations$nodes$rows, "6"), stage$budgets$partition_rows == 2L)
  TRUE
}

test_engine_manifest_json_batch_deferred_policy_fault_and_retry_contract <- function() {
  path <- tempfile("manifest_json_batch_deferred_", fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit({DBI::dbDisconnect(con); unlink(path)}, add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE entries(id INTEGER,label TEXT);")
  labels <- rep(c("é東京😀", "quote\"slash\\", NA_character_, ""), length.out = 5001L)
  labels[c(2L, 4999L, 5001L)] <- c(strrep("q", 257L), strrep("é", 200L), strrep("z", 1000L))
  DBI::dbAppendTable(con, "entries", data.frame(id = seq_len(5001L), label = labels))
  DBI::dbExecute(con, "UPDATE entries SET id=2147483648 WHERE rowid=5000;")
  expected <- scworkbench:::.wb_manifest_table_identity_materialized(con, "entries")
  before <- list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;"),
    temp = DBI::dbGetQuery(con, "PRAGMA temp_store;"), policy = con@ref$wb_graph_policy,
    reservation = con@ref$wb_graph_cache_kib)
  for (partition in c(128L, 4096L, 262144L)) {
    policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608",
      sqlite_cache_kib = 2048L, partition_bytes = partition, partition_rows = 2L,
      collect_bytes = 4194304L))
    batches <- 0L
    old <- options(scworkbench.graph_storage_test_hook = function(event, state) {
      if (event == "manifest_scalar_batch") {
        batches <<- batches + 1L
        stopifnot(state$rows <= state$candidate_rows, state$candidate_rows <= 5000L,
          state$carrier_bytes + 8 * state$encoded_bytes <= 8 * state$budgets$partition_bytes)
      }
    })
    on.exit(options(old), add = TRUE)
    stopifnot(identical(expected,
      scworkbench:::.wb_manifest_table_identity(con, "entries", budgets = policy)))
    if (partition == 128L) stopifnot(batches == 0L)
    options(old)
  }
  old <- options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "manifest_scalar_batch") stop("JSON_BATCH_FAULT")
  })
  on.exit(options(old), add = TRUE)
  failure <- tryCatch(scworkbench:::.wb_manifest_table_identity(con, "entries", budgets = policy),
    error = identity)
  options(old)
  stopifnot(inherits(failure, "error"), grepl("JSON_BATCH_FAULT", conditionMessage(failure), fixed = TRUE),
    identical(expected, scworkbench:::.wb_manifest_table_identity(con, "entries", budgets = policy)),
    identical(before, list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;"),
      temp = DBI::dbGetQuery(con, "PRAGMA temp_store;"), policy = con@ref$wb_graph_policy,
      reservation = con@ref$wb_graph_cache_kib)))
  TRUE
}
