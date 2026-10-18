args <- commandArgs(TRUE)
.libPaths(c(args[1L], .libPaths()))
suppressPackageStartupMessages(library(scworkbench))
source("inst/tests/contract_test_runner.R")
inventory <- contract_test_discover("tests", parent_env = asNamespace("scworkbench"),
  files = c("test_operation_pack_matrix_streaming_contract.R",
    "test_operation_pack_v3_contract.R",
    "test_operation_pack_v3_stage_matrix_source_binding_contract.R"))
selected <- c("test_operation_pack_matrix_streaming_alignment_contract",
  "test_operation_pack_matrix_streaming_unused_lineage_contract",
  "test_operation_pack_matrix_streaming_identity_contract",
  "test_operation_pack_matrix_streaming_numeric_contract",
  "test_operation_pack_matrix_streaming_reader_plan_contract",
  "test_operation_pack_v3_stage_matrix_between_reads_and_publication_contract",
  "test_operation_pack_v3_stage_matrix_committed_and_predecessor_contract",
  "test_operation_pack_v3_stage_matrix_payload_and_checksum_rejection_contract",
  "test_operation_pack_v3_stage_matrix_registry_and_broker_contract",
  "test_operation_pack_v3_stage_only_predecessor_typed_read_contract",
  "test_operation_pack_v3_durable_reopen_committed_matrix_source_contract",
  "test_operation_pack_v3_identity_fixture_contract",
  "test_operation_pack_v3_typed_slice_getter_contract",
  "test_operation_pack_v3_in_memory_typed_slice_source_contract",
  "test_operation_pack_v3_chunk_replay_and_rollback_contract")
names <- vapply(inventory$tests, `[[`, character(1), "name")
stopifnot(all(selected %in% names))
cat("DISCOVERY available_in_selected_files=", length(names),
  " selected=", length(selected), " (not package-wide discovery)\n", sep = "")
inventory$tests <- inventory$tests[match(selected, names)]
run <- contract_test_execute(inventory)
contract_test_assert_success(run)
stopifnot(run$summary[["passed"]] == 15L, run$summary[["skipped"]] == 0L)
