args <- commandArgs(TRUE)
stopifnot(length(args)==1L)
.libPaths(c(file.path(args[[1L]],"library"),.libPaths()))
library(scworkbench)
stopifnot(identical(normalizePath(find.package("scworkbench")),normalizePath(file.path(args[[1L]],"library","scworkbench"))))
`%||%` <- getFromNamespace("%||%","scworkbench")
contract_test_skip <- function(reason) stop(paste("UNEXPECTED_SKIP",reason))
tests <- new.env(parent=globalenv())
for(file in c("test_graph_matrix_source_selection_contract.R","test_graph_native_matrix_public_promotion_first_contract.R")) sys.source(file.path("tests",file),tests)
for(name in c("test_graph_matrix_native_existing_source_authority_contract",
  "test_graph_matrix_existing_producer_selection_contract",
  "test_graph_matrix_promotion_first_precheck_contract",
  "test_graph_native_matrix_public_promotion_first_lifecycle_contract")) {
  stopifnot(isTRUE(tests[[name]]()));cat(name,"PASS\n")
}
cat("NATIVE_MATRIX_PUBLIC_FOCUSED executed=4 passed=4 skipped=0 qualification=FALSE\n")
