args <- commandArgs(TRUE)
stopifnot(length(args) == 1L)
.libPaths(c(file.path(args[[1L]], "library"), .libPaths()))
library(scworkbench)
prototype <- new.env(parent = asNamespace("scworkbench"))
sys.source("notes/generic_graph_implementation/prototype_manifest_small_batch.R", prototype)
text <- paste(readLines("tests/test_manifest_stream_identity_contract.R"), collapse = "\n")
text <- gsub("scworkbench:::.wb_manifest_table_identity(",
  ".wb_manifest_table_identity_batched(", text, fixed = TRUE)
tests <- new.env(parent = prototype)
eval(parse(text = text), tests)
names <- sort(ls(tests, pattern = "^test_"))
for (name in names) {
  stopifnot(isTRUE(tests[[name]]()))
  cat(name, "PROTOTYPE_PASS\n")
}
path <- tempfile("manifest_batch_throughput_", fileext = ".sqlite")
con <- DBI::dbConnect(RSQLite::SQLite(), path)
DBI::dbExecute(con, "CREATE TABLE admitted(cell_id TEXT,score REAL,annotation TEXT,discard INTEGER);")
DBI::dbAppendTable(con, "admitted", data.frame(cell_id = paste0("cell_", seq_len(5001L), "_", strrep("x", 192L)),
  score = seq_len(5001L) / 13, annotation = NA_character_, discard = NA_integer_))
policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608", sqlite_cache_kib = 2048L,
  partition_bytes = 262144L, partition_rows = 256L, collect_bytes = 4194304L))
old <- scworkbench:::.wb_manifest_table_identity_materialized(con, "admitted")
scalar_time <- system.time(scalar <- scworkbench:::.wb_manifest_table_identity(con, "admitted", budgets = policy))
batched_time <- system.time(batched <- prototype$.wb_manifest_table_identity_batched(con, "admitted", budgets = policy))
stopifnot(identical(old, scalar), identical(old, batched))
cat("MANIFEST_BATCH_PROTOTYPE rows=5001 legacy_digest=UNCHANGED scalar_elapsed=", scalar_time[["elapsed"]],
  " batched_elapsed=", batched_time[["elapsed"]], " working_memory=8388608 logical_chunk=5000",
  " huge_fields=INCREMENTAL installed_candidate=UNCHANGED qualification=FALSE\n", sep = "")
DBI::dbDisconnect(con); unlink(path)
