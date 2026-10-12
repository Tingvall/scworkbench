args <- commandArgs(TRUE)
.libPaths(c(file.path(args[[1L]],"library"),.libPaths()))
library(scworkbench)
tests <- new.env(parent=asNamespace("scworkbench"))
Sys.setenv(R_LIBS=paste(.libPaths(),collapse=.Platform$path.sep))
Sys.setenv(SCWB_CONTRACT_INSTALLED_LIBRARY=normalizePath(file.path(args[[1L]],"library")))
sys.source("inst/tests/contract_test_runner.R",tests)
tests$contract_test_skip <- function(reason)stop(paste("UNEXPECTED_SKIP",reason))
files <- c("test_durable_session_generation_recovery_contract.R",
  "test_durable_session_source_payload_corruption_contract.R",
  "test_durable_session_subprocess_recovery_contract.R",
  "test_operation_pack_v3_durable_model_tree_contract.R",
  "test_operation_pack_v3_matrix_model_boundary_contract.R")
for(file in files)sys.source(file.path("tests",file),tests)
names <- c("test_durable_session_generation_recovery_contract",
  "test_durable_session_source_payload_corruption_contract",
  "test_durable_session_subprocess_recovery_contract",
  "test_operation_pack_v3_durable_model_tree_contract",
  "test_operation_pack_v3_matrix_model_protocol_fixture_contract",
  "test_operation_pack_v3_matrix_model_boundary_lifecycle_contract",
  "test_operation_pack_v3_matrix_model_boundary_rollback_contract",
  "test_operation_pack_v3_matrix_model_source_reopen_authentication_contract")
for(name in names){stopifnot(isTRUE(tests[[name]]()));cat(name,"PASS\n");flush.console()}
cat("TRANSITION_COPY_REGRESSION_FOCUSED executed=8 passed=8 skipped=0 qualification=FALSE\n")
