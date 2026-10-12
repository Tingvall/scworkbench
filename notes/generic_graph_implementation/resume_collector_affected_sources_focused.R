args <- commandArgs(TRUE)
.libPaths(c(file.path(args[[1L]],"library"),.libPaths()))
library(scworkbench,lib.loc=file.path(args[[1L]],"library"))
tests <- new.env(parent=asNamespace("scworkbench"))
sys.source("inst/tests/contract_test_runner.R",tests)
tests$contract_test_skip <- function(reason)stop(paste("UNEXPECTED_SKIP",reason))
for(file in c("test_graph_source_authority_contract.R","test_graph_object_source_batch_contract.R",
  "test_graph_source_snapshot_scope_contract.R","composite/phase4c/test_generic_entity_certificate_contract.R"))
  sys.source(file.path("tests",file),tests)
names <- c("test_graph_retained_cell_source_payload_contract",
 "test_graph_object_source_batch_identity_admission_restoration_contract",
 "test_graph_source_snapshot_unrelated_head_scope_contract",
 "test_generic_entity_certificate_contract","test_generic_entity_certificate_corruption_contract")
for(name in names) {cat("START",name,"\n");flush.console();stopifnot(isTRUE(tests[[name]]()));cat(name,"PASS\n");flush.console()}
cat("COLLECTOR_AFFECTED_SOURCE_FOCUSED executed=5 passed=5 skipped=0 qualification=FALSE PASS\n")
