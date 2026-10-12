args <- commandArgs(TRUE)
stopifnot(length(args) == 1L)
.libPaths(c(file.path(args[[1L]], "library"), .libPaths()))
library(scworkbench)
stopifnot(identical(normalizePath(find.package("scworkbench")),
  normalizePath(file.path(args[[1L]], "library", "scworkbench"))))
source <- "/tmp/scwb-graph-native-long-axis-90000-development/source.bundle"
path <- file.path(source, "db/app.sqlite")
manifest_path <- file.path(source, "manifest.json")
sha <- function(path) digest::digest(file = path, algo = "sha256", serialize = FALSE)
before <- c(sha(path), sha(manifest_path))
expected <- jsonlite::fromJSON(manifest_path, simplifyVector = FALSE)$current_state$tables$cells
stopifnot(expected$row_count == 90000L)
con <- DBI::dbConnect(RSQLite::SQLite(), path, flags = RSQLite::SQLITE_RO)
policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608", sqlite_cache_kib = 2048L,
  partition_bytes = 262144L, partition_rows = 256L, collect_bytes = 4194304L))
batches <- 0L
options(scworkbench.graph_storage_test_hook = function(event, state) {
  if (event == "manifest_scalar_batch") {
    batches <<- batches + 1L
    stopifnot(state$reservation_bytes <= state$decoded_reservation_bytes,
      state$fetched_carrier_bytes + state$budgets$sqlite_cache_kib * 1024 +
        state$decoded_reservation_bytes + 65536 <= as.numeric(state$budgets$memory_bytes),
      state$con@ref$wb_graph_cache_kib + 128L <= 2048L)
  }
})
timing <- system.time(observed <- scworkbench:::.wb_manifest_table_identity(con, "cells", budgets = policy))
DBI::dbDisconnect(con)
stopifnot(identical(expected, observed), identical(before, c(sha(path), sha(manifest_path))))
cat("ORIGINAL_AXIS_MANIFEST_BATCH_DIAGNOSTIC rows=90000 legacy_manifest_digest=EXACT",
  " source_and_manifest_sha256=UNCHANGED working_memory=8388608 batches=", batches,
  " elapsed=", timing[["elapsed"]], " native_dispatch=DISABLED qualification=FALSE\n", sep = "")
