args <- commandArgs(TRUE)
stopifnot(length(args)==1L)
.libPaths(c(file.path(args[[1L]],"library"),.libPaths()))
library(scworkbench)
stopifnot(identical(normalizePath(find.package("scworkbench")),normalizePath(file.path(args[[1L]],"library","scworkbench"))))
`%||%` <- getFromNamespace("%||%","scworkbench")
contract_test_skip <- function(reason) stop(paste("UNEXPECTED_SKIP",reason))
tests <- new.env(parent=globalenv())
for(file in c("test_graph_source_snapshot_scope_contract.R","test_graph_matrix_source_selection_contract.R",
  "test_graph_abi4_public_execution_contract.R")) sys.source(file.path("tests",file),tests)
names <- c("test_graph_source_snapshot_unrelated_head_scope_contract",
  "test_graph_matrix_native_existing_source_authority_contract",
  "test_graph_matrix_existing_producer_selection_contract",
  "test_graph_matrix_promotion_first_precheck_contract","test_graph_abi4_public_r_execution_contract")
for(name in names) {stopifnot(isTRUE(tests[[name]]()));cat(name,"PASS\n")}
cat("SOURCE_SNAPSHOT_SCOPE_FOCUSED executed=5 passed=5 skipped=0 native_dispatch=DISABLED qualification=FALSE\n")
