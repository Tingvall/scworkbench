# New frozen246 development diagnostic, not a restart of234 or qualification.
args <- commandArgs(TRUE)
stopifnot(length(args) == 4L, args[[4L]] %in% c("run", "inspect"), as.integer(args[[3L]]) <= 512L)
fixture <- readRDS(args[[1L]])
.libPaths(c(fixture$core_library, .libPaths()))
library(scworkbench)
stopifnot(identical(fixture$development_checkpoint$name, "246_manifest_small_batch_diagnostic"),
  identical(digest::digest(paste(deparse(body(getFromNamespace(".wb_manifest_table_identity", "scworkbench"))),
    collapse = "\n"), algo = "sha256", serialize = FALSE), fixture$development_checkpoint$manifest_function_sha256),
  identical(digest::digest(file = file.path(fixture$source_bundle, "db/app.sqlite"), algo = "sha256", serialize = FALSE),
    fixture$development_checkpoint$original_db_sha256))
report <- function(phase) {
  status <- readLines("/proc/self/status")
  cat("MANIFEST_BATCH_SMALL_LIFECYCLE", phase, paste(status[grepl("^(VmRSS|VmHWM):", status)], collapse = " "), "\n")
  flush.console()
}
options(scworkbench.promotion_transaction_test_hook = function(event, ...) {
  if (event == "graph_component_rows") report(event)
}, scworkbench.operation_pack_v2_test_hook = function(event, ...) {
  if (event %in% c("before_dispatch", "receipt_received", "audited", "before_publication", "published", "reopened")) report(event)
})
report("loaded")
source("notes/generic_graph_implementation/scale_worker.R")
stopifnot(identical(digest::digest(file = file.path(fixture$source_bundle, "db/app.sqlite"), algo = "sha256", serialize = FALSE),
  fixture$development_checkpoint$original_db_sha256))
report("terminal")
cat("MANIFEST_BATCH_SMALL_LIFECYCLE qualification=FALSE native_matrix_dispatch=DISABLED source_axes=90000\n")
