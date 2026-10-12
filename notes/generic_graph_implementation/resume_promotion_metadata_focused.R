args <- commandArgs(TRUE)
stopifnot(length(args)==1L)
lib <- file.path(args[[1L]],"library")
.libPaths(c(lib,.libPaths()))
library(scworkbench,lib.loc=lib)
stopifnot(identical(normalizePath(find.package("scworkbench")),
  normalizePath(file.path(lib,"scworkbench"))))
tests <- new.env(parent=asNamespace("scworkbench"))
for(path in c("tests/test_promotion_runtime_fingerprint_metadata_contract.R",
  "tests/test_graph_abi4_public_execution_contract.R",
  "tests/test_graph_resource_accounting_contract.R"))sys.source(path,tests)
selected <- c("test_promotion_runtime_fingerprint_metadata_loadability_contract",
  "test_promotion_runtime_fingerprint_metadata_parity_contract",
  "test_promotion_runtime_fingerprint_legacy_public_commit_contract",
  "test_graph_abi4_public_r_execution_contract",
  "test_graph_resource_unstaged_public_promotion_cache_contract")
for(name in selected) {
  cat("PROMOTION_METADATA START",name,"\n");flush.console()
  stopifnot(isTRUE(tests[[name]]()))
  cat("PROMOTION_METADATA PASS",name,"\n");flush.console()
}
cat("PROMOTION_METADATA_FOCUSED executed=5 passed=5 skipped=0 qualification=FALSE\n")
