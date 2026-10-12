# Focused development reproduction with original complete source and a small
# graph. Profiling changes measurements; this cannot count as qualification.
args <- commandArgs(TRUE)
stopifnot(length(args) == 4L, args[[4L]] == "run", as.integer(args[[3L]]) <= 512L)
fixture <- readRDS(args[[1L]])
.libPaths(c(fixture$core_library, .libPaths()))
library(scworkbench)
prefix <- Sys.getenv("SCWB_GRAPH_PROFILE_PREFIX")
stopifnot(nzchar(prefix), !file.exists(paste0(prefix, ".allocations")))
report <- function(phase) {
  status <- readLines("/proc/self/status")
  cat("ORIGINAL_SOURCE_PROFILE", phase,
    paste(status[grepl("^(VmRSS|VmHWM):", status)], collapse = " "), "\n")
  flush.console()
}
options(scworkbench.promotion_transaction_test_hook = function(event, ...) {
  if (event == "graph_component_rows") report(event)
}, scworkbench.operation_pack_v2_test_hook = function(event, ...) {
  if (event %in% c("before_dispatch", "receipt_received", "audited", "before_publication", "published", "reopened"))
    report(event)
})
Rprof(paste0(prefix, ".stacks"), interval = 0.05, memory.profiling = TRUE)
Rprofmem(paste0(prefix, ".allocations"), threshold = 1048576)
report("loaded")
source("notes/generic_graph_implementation/scale_worker.R")
Rprof(NULL); Rprofmem(NULL)
saveRDS(summaryRprof(paste0(prefix, ".stacks"), memory = "both"), paste0(prefix, ".summary.rds"))
report("terminal")
cat("ORIGINAL_SOURCE_PROFILE qualification=FALSE recipient=NOT_RUN graph_nodes=", args[[3L]], "\n", sep = "")
