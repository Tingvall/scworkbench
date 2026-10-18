args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 1L)
.libPaths(c(args[[1L]], .libPaths()))
suppressPackageStartupMessages(library(scworkbench))
e <- new.env(parent = asNamespace("scworkbench"))
sys.source("R/operation_pack_typed_slice_broker.R", e)
sys.source("tests/test_engine_broker_streaming_contract.R", e)
functions <- ls(e, pattern = "^test_")
for (name in functions) {
  cat("RUN", name, "\n")
  stopifnot(isTRUE(e[[name]]()))
  cat("PASS", name, "\n")
}
cat(sprintf("BROKER_FOCUSED discovered=%d executed=%d passed=%d skipped=0 failed=0\n",
  length(functions), length(functions), length(functions)))
