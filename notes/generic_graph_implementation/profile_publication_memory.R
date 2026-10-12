# Focused diagnosis only. This synthetic publication isolates graph work; it is
# not the full source/lifecycle fixture and cannot qualify frozen memory limits.
args <- commandArgs(TRUE)
stopifnot(length(args) == 3L)
.libPaths(c(args[[1L]], .libPaths()))
library(scworkbench)
out <- args[[2L]]; count <- as.integer(args[[3L]])
stopifnot(!file.exists(out)); dir.create(out)
policy <- list(memory_bytes = "8388608", sqlite_cache_kib = 2048L,
  partition_bytes = 262144L, partition_rows = 256L, collect_bytes = 4194304L)
report <- function(phase, collect = FALSE) {
  if (collect) gc(FALSE)
  status <- readLines("/proc/self/status")
  values <- status[grepl("^(VmRSS|VmHWM):", status)]
  cat("PROFILE_PHASE", phase, paste(values, collapse = " "), "\n")
  flush.console()
}
bundle <- wb_init_bundle(file.path(out, "bundle"))
stage <- scworkbench:::.wb_graph_stage_new("mixed", policy)
report("loaded_baseline", TRUE)
Rprofmem(file.path(out, "allocations.log"), threshold = 65536)
Rprof(file.path(out, "stacks.log"), interval = 0.02, memory.profiling = TRUE)
ids <- function(i) paste0("n", i)
for (start in seq.int(1L, count, by = 256L)) {
  index <- seq.int(start, min(count, start + 255L))
  scworkbench:::.wb_graph_append(stage, "nodes", lapply(index,
    function(i) list(node_id = ids(i))))
}
scworkbench:::.wb_graph_append(stage, "attribute_fields", list(list(scope = "node",
  field_ordinal = "0", name = "payload", type = "utf8", nullable = FALSE)))
payload <- strrep("a", 16384L)
for (i in seq_len(count)) scworkbench:::.wb_graph_append(stage, "attribute_values",
  list(list(scope = "node", field_ordinal = "0", entity_ordinal = as.character(i - 1L), value = payload)))
report("staged")
identity <- scworkbench:::.wb_graph_sql_identities(stage$con, "staged", stage$budgets)
report("sealed")
graph <- structure(list(kind = "graph", content_identity = identity$content_identity,
  binding_identity = identity$binding_identity, descriptor_identity = identity$descriptor_identity),
  class = "wb_primitive")
attr(graph, "graph_stage") <- stage
run <- wb_new_run("metadata_cell_vector", list(), list(), list(vector = graph))
batch <- 0L
options(scworkbench.promotion_transaction_test_hook = function(event, ...) {
  if (event == "graph_component_rows") {
    batch <<- batch + 1L
    if (batch %% 32L == 0L) report(paste0("publish_batch_", batch))
  }
})
promotion <- wb_promote_analysis(bundle, stats::setNames(list(run), run$run_id),
  head_run_id = run$run_id, outputs = "vector")
report("promoted")
Rprof(NULL); Rprofmem(NULL)
saveRDS(summaryRprof(file.path(out, "stacks.log"), memory = "both"),
  file.path(out, "profile_summary.rds"))
cat("PROFILE_RESULT canonical_bytes=", identity$canonical_bytes,
  " publication=PASS qualification=FALSE\n", sep = "")
scworkbench:::.wb_graph_stage_discard(stage)
wb_close_bundle(bundle)
report("closed", TRUE)
