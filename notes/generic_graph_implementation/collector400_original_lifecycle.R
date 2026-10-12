# Separate original-source development diagnostic; never final qualification.
args <- commandArgs(TRUE)
stopifnot(length(args)==4L,args[[4L]] %in% c("run","inspect"),
  as.integer(args[[3L]])==22000L)
fixture <- readRDS(args[[1L]])
.libPaths(c(fixture$core_library,.libPaths()))
library(scworkbench,lib.loc=fixture$core_library)
checkpoint <- fixture$development_checkpoint
stopifnot(identical(checkpoint$name,"collector400_original90000_2x_development"),
  fixture$source_axis_count==90000L,fixture$source_axis_utf8_bytes==18258618L,
  identical(digest::digest(file=checkpoint$source_ledger,algo="sha256"),
    checkpoint$source_ledger_sha256),
  identical(digest::digest(file=getLoadedDLLs()[["scworkbench"]][["path"]],
    algo="sha256"),checkpoint$dll_sha256),
  identical(digest::digest(file=file.path(fixture$source_bundle,"db/app.sqlite"),
    algo="sha256"),checkpoint$original_db_sha256))
report <- function(phase) {
  status <- readLines("/proc/self/status")
  cat("COLLECTOR400_ORIGINAL_LIFECYCLE",phase,
    paste(status[grepl("^(VmRSS|VmHWM):",status)],collapse=" "),"\n")
  flush.console()
}
options(scworkbench.promotion_transaction_test_hook=function(event,...) {
  if(event=="graph_component_rows")report(event)
},scworkbench.operation_pack_v2_test_hook=function(event,...) {
  if(event %in% c("before_dispatch","receipt_received","audited",
    "before_publication","published","reopened"))report(event)
})
Sys.setenv(SCWB_SCALE_EXPECTED_CORE_LIBRARY=fixture$core_library,
  SCWB_SCALE_EXPECTED_SOURCE_CLOSURE_SHA256=checkpoint$source_closure_function_sha256)
report("loaded")
source("notes/generic_graph_implementation/scale_worker.R")
stopifnot(identical(digest::digest(file=file.path(fixture$source_bundle,"db/app.sqlite"),
  algo="sha256"),checkpoint$original_db_sha256))
record <- readRDS(file.path(args[[2L]],"promoted.rds"))
stopifnot(as.numeric(record$canonical_bytes)>=1400471552)
report("terminal")
cat("COLLECTOR400_ORIGINAL_LIFECYCLE source_axes=90000 nodes=22000",
  " canonical_2x_floor=PASS qualification=FALSE mode=",args[[4L]],"\n",sep="")
