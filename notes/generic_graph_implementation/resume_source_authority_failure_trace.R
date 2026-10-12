args <- commandArgs(TRUE)
.libPaths(c(file.path(args[[1L]],"library"),.libPaths()))
library(scworkbench,lib.loc=file.path(args[[1L]],"library"))
options(error=function(){traceback(15L);q(status=1L)})
trace(".wb_graph_budgets",where=asNamespace("scworkbench"),tracer=quote({
 if("storage_bytes" %in% names(overrides) && !isTRUE(.wb_graph_int64(overrides$storage_bytes))) {
   cat("INVALID_STORAGE_OVERRIDE\n");str(overrides);print(sys.calls())
 }
}),print=FALSE)
source("tests/test_graph_source_authority_contract.R")
stopifnot(isTRUE(test_graph_retained_cell_source_payload_contract()))
