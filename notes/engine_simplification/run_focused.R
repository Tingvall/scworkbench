args <- commandArgs(TRUE)
.libPaths(c(args[[1L]], .libPaths()))
suppressPackageStartupMessages(library(scworkbench))
source("inst/tests/contract_test_runner.R")
files <- c("test_engine_table_streaming_contract.R",
  "test_engine_owned_block_copy_contract.R", "test_engine_matrix_encoding_contract.R",
  "test_engine_matrix_selected_axis_contract.R", "test_engine_invocation_boundaries_contract.R",
  "test_engine_promotion_stage_ownership_contract.R")
files <- c(files, "test_engine_schema_observation_contract.R")
files <- c(files, "test_engine_descriptor_preimage_contract.R",
  "test_engine_canonical_preimage_contract.R", "test_engine_mixed_seal_contract.R",
  "test_engine_broker_streaming_contract.R")
if (length(args) > 1L && args[[2L]] == "lifecycle") files <- c(files,
  "test_durable_session_generation_recovery_contract.R",
  "test_durable_session_source_payload_corruption_contract.R",
  "test_durable_session_dependent_branch_contract.R",
  "test_operation_pack_v2_contract.R", "test_operation_pack_v3_contract.R",
  "test_operation_pack_v3_stage_matrix_source_binding_contract.R")
inventory <- contract_test_discover("tests", parent_env = asNamespace("scworkbench"),
  files = files)
contract_test_assert_success(contract_test_execute(inventory))
