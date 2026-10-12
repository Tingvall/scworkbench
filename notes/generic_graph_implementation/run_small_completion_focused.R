args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
.libPaths(c(args[[1L]], .libPaths()))
library(scworkbench, lib.loc = args[[1L]])
stopifnot(identical(normalizePath(find.package("scworkbench")),
  normalizePath(file.path(args[[1L]], "scworkbench"))))
Sys.setenv(SCWB_GRAPH_SMALL_EVIDENCE_DIR = args[[2L]])
env <- new.env(parent = asNamespace("scworkbench"))
sys.source("inst/tests/contract_test_runner.R", env)
files <- c("tests/test_graph_small_out_of_core_contract.R",
  "tests/test_graph_resource_accounting_contract.R", "tests/test_graph_primitive_contract.R",
  "tests/test_graph_strict_json_unicode_contract.R", "tests/test_graph_abi4_admission_contract.R",
  "tests/test_graph_abi4_public_execution_contract.R", "tests/test_graph_scenario_roundtrip_contract.R",
  "tests/test_graph_binding_read_selection_contract.R", "tests/test_graph_sdk_authoring_contract.R",
  "tests/test_graph_abi4_retained_count_contract.R", "tests/test_graph_abi4_runtime_sidecar_contract.R",
  "tests/test_graph_abi4_broker_publication_contract.R")
for (path in files) sys.source(path, env)
selected <- c("test_graph_resource_import_connection_reservation_contract",
  "test_graph_small_forced_out_of_core_public_lifecycle_contract",
  setdiff(sort(ls(env, pattern = "^test_")), c(
    "test_graph_resource_import_connection_reservation_contract",
    "test_graph_small_forced_out_of_core_public_lifecycle_contract")))
passed <- skipped <- 0L
for (name in selected) {
  cat("SMALL_COMPLETION START", name, "\n"); flush.console()
  result <- env[[name]]()
  if (inherits(result, "contract_test_skip")) {
    skipped <- skipped + 1L; cat("SMALL_COMPLETION SKIP", name, paste(result, collapse = " "), "\n")
  } else {stopifnot(isTRUE(result)); passed <- passed + 1L; cat("SMALL_COMPLETION PASS", name, "\n")}
  flush.console()
}
cat("SMALL_COMPLETION_FOCUSED executed=", length(selected), " passed=", passed,
  " skipped=", skipped, " qualification=FALSE large_physical_stress=DEFERRED\n", sep = "")
stopifnot(skipped == 0L)
