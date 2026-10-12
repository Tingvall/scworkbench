args <- commandArgs(TRUE)
stopifnot(length(args) == 1L)
.libPaths(c(file.path(args[[1L]], "library"), .libPaths()))
library(scworkbench)
prototype <- new.env(parent = asNamespace("scworkbench"))
sys.source("notes/generic_graph_implementation/prototype_object_closure_batch.R", prototype)
fixture <- readRDS("/tmp/scwb-graph-manifest-batch-lifecycle-246.rds")
path <- file.path(fixture$source_bundle, "db/app.sqlite")
before <- digest::digest(file = path, algo = "sha256", serialize = FALSE)
con <- DBI::dbConnect(RSQLite::SQLite(), path, flags = RSQLite::SQLITE_RO)
policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608", sqlite_cache_kib = 2048L,
  partition_bytes = 262144L, partition_rows = 256L, collect_bytes = 4194304L))
restore <- scworkbench:::.wb_graph_aggregate_connection_budget(list(con), policy)
expected <- jsonlite::fromJSON(DBI::dbGetQuery(con,
  "SELECT closure_identity_json FROM artifact_object_payload_meta WHERE artifact_id=?;",
  params = list(fixture$source_axis_artifact_id))$closure_identity_json[[1L]], simplifyVector = FALSE)
prefix <- "/tmp/scwb-graph-original-cell-source-closure-batch-prototype-utf8"
stopifnot(!file.exists(paste0(prefix, ".stacks")))
Rprof(paste0(prefix, ".stacks"), interval = 0.02, memory.profiling = TRUE)
batches <- 0L
options(scworkbench.graph_storage_test_hook = function(event,state) {
  if (event == "source_object_batch_fetch" && state$enabled) {
    batches <<- batches + 1L
    stopifnot(state$reservation_bytes <= state$decoded_reservation_bytes,
      state$decoded_reservation_bytes + policy$sqlite_cache_kib * 1024 + 65536 < as.numeric(policy$memory_bytes),
      state$con@ref$wb_graph_cache_kib + 128L <= 2048L)
  }
})
time <- system.time(observed <- prototype$.wb_graph_object_closure_batched(con, fixture$source_axis_artifact_id, policy))
Rprof(NULL)
saveRDS(summaryRprof(paste0(prefix, ".stacks"), memory = "both"), paste0(prefix, ".summary.rds"))
restore(); DBI::dbDisconnect(con)
stopifnot(identical(expected, observed), identical(before, digest::digest(file = path, algo = "sha256", serialize = FALSE)))
cat("ORIGINAL_CELL_SOURCE_CLOSURE_BATCH_PROTOTYPE source_axes=90000 existing_closure_identity=EXACT",
  " source_sha256=UNCHANGED elapsed=", time[["elapsed"]], " batches=", batches," qualification=FALSE installed=UNCHANGED\n", sep = "")
