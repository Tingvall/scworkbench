args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
.libPaths(c(args[[1L]], .libPaths()))
library(scworkbench, lib.loc = args[[1L]])
Sys.setenv(SCWB_GRAPH_SMALL_EVIDENCE_DIR = args[[2L]])
cat("SMALL_RUNTIME_BASELINE loaded_core=TRUE ", paste(readLines("/proc/self/status")[grepl("^Vm(RSS|HWM):", readLines("/proc/self/status"))], collapse = " "), " working_policy_separate=TRUE\n", sep = "")
env <- new.env(parent = asNamespace("scworkbench"))
for (path in c("tests/test_graph_resource_accounting_contract.R", "tests/test_graph_small_out_of_core_contract.R")) sys.source(path, env)
selected <- c("test_graph_resource_unrelated_descriptor_slot_contract",
  "test_graph_resource_owned_inode_metadata_overflow_contract",
  "test_graph_resource_owned_spill_alias_and_fd_metadata_admission_contract",
  "test_graph_resource_import_connection_reservation_contract",
  "test_graph_small_forced_out_of_core_public_lifecycle_contract")
for (name in selected) {
  cat("SMALL_AFFECTED START", name, "\n"); flush.console()
  stopifnot(isTRUE(env[[name]]()))
  cat("SMALL_AFFECTED PASS", name, "\n"); flush.console()
}
cat("SMALL_CONTEXT_AFFECTED executed=5 passed=5 skipped=0 qualification=FALSE\n")
