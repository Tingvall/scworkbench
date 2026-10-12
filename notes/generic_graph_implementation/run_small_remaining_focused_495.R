args <- commandArgs(TRUE)
stopifnot(length(args) == 1L)
.libPaths(c(args[[1L]], .libPaths()))
library(scworkbench, lib.loc = args[[1L]])
env <- new.env(parent = asNamespace("scworkbench"))
sys.source("inst/tests/contract_test_runner.R", env)
files <- c("tests/test_graph_resource_accounting_contract.R", "tests/test_graph_primitive_contract.R",
  "tests/test_graph_strict_json_unicode_contract.R", "tests/test_graph_abi4_admission_contract.R",
  "tests/test_graph_abi4_public_execution_contract.R", "tests/test_graph_scenario_roundtrip_contract.R",
  "tests/test_graph_binding_read_selection_contract.R", "tests/test_graph_sdk_authoring_contract.R",
  "tests/test_graph_abi4_retained_count_contract.R", "tests/test_graph_abi4_runtime_sidecar_contract.R",
  "tests/test_graph_abi4_broker_publication_contract.R")
for (path in files) sys.source(path, env)
selected <- setdiff(sort(ls(env, pattern = "^test_")), "test_graph_resource_import_connection_reservation_contract")
passed <- skipped <- 0L
for (name in selected) {
  cat("SMALL_REMAINING START", name, "\n"); flush.console()
  result <- env[[name]]()
  if (inherits(result, "scworkbench_contract_skip")) {
    skipped <- skipped + 1L; cat("SMALL_REMAINING SKIP", name, result$reason, "\n")
  } else {stopifnot(isTRUE(result)); passed <- passed + 1L; cat("SMALL_REMAINING PASS", name, "\n")}
  flush.console()
}
cat("SMALL_REMAINING_FOCUSED executed=", length(selected), " passed=", passed,
  " skipped=", skipped, " qualification=FALSE large_physical_stress=DEFERRED\n", sep = "")
stopifnot(skipped == 0L)
