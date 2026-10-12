# Focused development evidence against a fresh isolated installed candidate.
args <- commandArgs(TRUE)
stopifnot(length(args) == 1L)
.libPaths(c(file.path(args[[1L]], "library"), .libPaths()))
library(scworkbench)
stopifnot(identical(normalizePath(find.package("scworkbench")),
  normalizePath(file.path(args[[1L]], "library", "scworkbench"))))
`%||%` <- getFromNamespace("%||%", "scworkbench")
contract_test_skip <- function(reason) stop(paste("UNEXPECTED_SKIP", reason))
files <- c("test_graph_native_matrix_identity_contract.R",
  "test_graph_matrix_source_selection_contract.R",
  "test_graph_native_matrix_producer_contract.R", "test_manifest_stream_identity_contract.R",
  "test_graph_resource_accounting_contract.R", "test_graph_abi4_public_execution_contract.R",
  "test_graph_no_axis_public_contract.R")
tests <- new.env(parent = globalenv())
for (file in files) sys.source(file.path("tests", file), tests)
pattern <- Sys.getenv("SCWB_GRAPH_FOCUSED_PATTERN", "^test_")
names <- sort(ls(tests, pattern = pattern))
stopifnot(length(names) > 0L)
failures <- 0L
for (name in names) {
  error <- tryCatch({stopifnot(isTRUE(tests[[name]]())); NULL}, error = identity)
  if (is.null(error)) cat(name, "PASS\n") else {
    failures <- failures + 1L
    cat(name, "FAIL", conditionMessage(error), "\n")
  }
}
cat("RESUME_BUDGET_FOCUSED discovered=", length(names), " executed=", length(names),
  " passed=", length(names) - failures, " failed=", failures, " skipped=0\n", sep = "")
if (failures) quit(status = 1L)
