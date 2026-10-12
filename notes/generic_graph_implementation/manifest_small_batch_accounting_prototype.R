args <- commandArgs(TRUE)
stopifnot(length(args) == 1L)
.libPaths(c(file.path(args[[1L]], "library"), .libPaths()))
library(scworkbench)
prototype <- new.env(parent = asNamespace("scworkbench"))
sys.source("notes/generic_graph_implementation/prototype_manifest_small_batch.R", prototype)
path <- tempfile("manifest_batch_accounting_", fileext = ".sqlite")
con <- DBI::dbConnect(RSQLite::SQLite(), path)
DBI::dbExecute(con, "CREATE TABLE admitted(cell_id TEXT,score REAL,annotation TEXT,discard INTEGER);")
DBI::dbAppendTable(con, "admitted", data.frame(cell_id = paste0("cell_", seq_len(5001L), "_", strrep("x", 192L)),
  score = seq_len(5001L) / 13, annotation = NA_character_, discard = NA_integer_))
expected <- scworkbench:::.wb_manifest_table_identity_materialized(con, "admitted")
before <- list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;")[[1L]][[1L]],
  temp = DBI::dbGetQuery(con, "PRAGMA temp_store;")[[1L]][[1L]],
  policy = con@ref$wb_graph_policy, cap = con@ref$wb_graph_cache_kib)
batches <- 0L; max_reserved <- 0
hook <- options(scworkbench.graph_storage_test_hook = function(event, state) {
  if (event == "manifest_scalar_batch") {
    batches <<- batches + 1L
    max_reserved <<- max(max_reserved, state$reservation_bytes)
    stopifnot(state$rows <= 64L, state$budgets$memory_bytes == "8388608",
      state$reservation_bytes <= state$decoded_reservation_bytes,
      state$fetched_carrier_bytes + state$budgets$sqlite_cache_kib * 1024 +
        state$decoded_reservation_bytes + 65536 <= as.numeric(state$budgets$memory_bytes),
      state$con@ref$wb_graph_cache_kib + 128L <= 2048L,
      con@ref$wb_graph_policy$memory_bytes == "8388608")
  }
})
for (partition in c(128L, 4096L, 262144L)) {
  policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608", sqlite_cache_kib = 2048L,
    partition_bytes = partition, partition_rows = 256L, collect_bytes = 4194304L))
  previous_batches <- batches
  observed <- prototype$.wb_manifest_table_identity_batched(con, "admitted", budgets = policy)
  stopifnot(identical(expected, observed))
  if (partition == 128L) stopifnot(batches == previous_batches)
  stopifnot(identical(before, list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;")[[1L]][[1L]],
    temp = DBI::dbGetQuery(con, "PRAGMA temp_store;")[[1L]][[1L]],
    policy = con@ref$wb_graph_policy, cap = con@ref$wb_graph_cache_kib)))
}
stopifnot(batches > 0L)
options(scworkbench.graph_storage_test_hook = function(event, state) {
  if (event == "manifest_scalar_batch") stop("BATCH_ACCOUNTING_INJECTED")
})
error <- tryCatch({prototype$.wb_manifest_table_identity_batched(con, "admitted", budgets = policy); NULL}, error = identity)
stopifnot(inherits(error, "error"), grepl("BATCH_ACCOUNTING_INJECTED", conditionMessage(error), fixed = TRUE),
  identical(before, list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;")[[1L]][[1L]],
    temp = DBI::dbGetQuery(con, "PRAGMA temp_store;")[[1L]][[1L]],
    policy = con@ref$wb_graph_policy, cap = con@ref$wb_graph_cache_kib)))
options(hook)
DBI::dbDisconnect(con); unlink(path)
cat("MANIFEST_BATCH_ACCOUNTING_PROTOTYPE partitions=128,4096,262144 working_memory=8388608",
  " auxiliary_cache=128KiB source_cache=SCOPED logical5000_digest=UNCHANGED",
  " tiny_partition=SCALAR_FALLBACK success_restoration=EXACT batches=", batches,
  " max_reservation_bytes=", max_reserved, " installed_candidate=UNCHANGED qualification=FALSE\n", sep = "")
