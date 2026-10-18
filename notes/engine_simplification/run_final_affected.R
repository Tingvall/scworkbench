# Actual installed namespace, not source monkeypatching. The supervisor creates
# a fresh ordinary golden data fixture separately and retains that setup log.
args <- commandArgs(TRUE); stopifnot(length(args) == 2L)
library <- normalizePath(args[[1L]], mustWork = TRUE)
baseline <- normalizePath(args[[2L]], mustWork = TRUE)
.libPaths(c(library, .libPaths()))
suppressPackageStartupMessages(library(scworkbench))
stopifnot(identical(normalizePath(find.package("scworkbench"), mustWork = TRUE),
  normalizePath(file.path(library, "scworkbench"), mustWork = TRUE)))
Sys.setenv(SCWB_CONTRACT_INSTALLED_LIBRARY = library,
  SCWORKBENCH_TEST_INSTALLED = "1")
source("inst/tests/contract_test_runner.R")
files <- sort(list.files("tests", pattern = "^test_engine_.*[.]R$"))
files <- unique(c(files,
  "test_operation_pack_test_peer_pin_contract.R",
  "test_cell_vector_durable_identity_roundtrip_contract.R",
  "test_derived_cell_set_lifecycle_contract.R",
  "test_foundation_hardening_1to5.R",
  "test_graph_legacy_metadata_expansion_admission_contract.R",
  "test_durable_session_subprocess_recovery_contract.R",
  "test_durable_session_generation_recovery_contract.R",
  "test_durable_session_source_payload_corruption_contract.R",
  "test_durable_session_dependent_branch_contract.R",
  "test_operation_pack_v1_contract.R",
  "test_operation_pack_v2_contract.R", "test_operation_pack_v3_contract.R",
  "test_operation_pack_v3_stage_matrix_source_binding_contract.R",
  "test_operation_pack_v3_matrix_model_boundary_contract.R",
  "test_operation_pack_v3_derived_fitted_axis_contract.R",
  "test_phase8_no_pack_core_surface_contract.R",
  "test_graph_primitive_contract.R"))
stopifnot(all(file.exists(file.path("tests", files))))
inventory <- contract_test_discover("tests", parent_env = asNamespace("scworkbench"),
  files = files)
run <- contract_test_execute(inventory, baseline_bundle_dir = baseline, reporter = TRUE)
contract_test_assert_success(run)
cat("FINAL_AFFECTED_ACTUALLY_INSTALLED_NAMESPACE_PASS\n")
