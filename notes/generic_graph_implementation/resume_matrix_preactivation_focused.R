args <- commandArgs(TRUE)
stopifnot(length(args) == 1L)
.libPaths(c(file.path(args[[1L]], "library"), .libPaths()))
library(scworkbench)
stopifnot(identical(normalizePath(find.package("scworkbench")),
  normalizePath(file.path(args[[1L]], "library", "scworkbench"))))
`%||%` <- getFromNamespace("%||%", "scworkbench")
contract_test_skip <- function(reason) stop(paste("UNEXPECTED_SKIP", reason))
tests <- new.env(parent = globalenv())
for (file in c("test_graph_native_matrix_real_g2_source_contract.R",
    "test_graph_matrix_source_selection_contract.R", "test_graph_native_matrix_identity_contract.R",
    "test_graph_resource_accounting_contract.R")) sys.source(file.path("tests", file), tests)
names <- c("test_graph_native_matrix_real_promoted_g2_source_contract",
  "test_graph_matrix_native_existing_source_authority_contract",
  "test_graph_matrix_existing_producer_selection_contract",
  "test_graph_matrix_promotion_first_precheck_contract",
  "test_graph_native_matrix_physical_and_membership_verification_contract",
  "test_graph_native_matrix_overlapping_fragment_getter_parity_contract",
  "test_graph_resource_unstaged_direct_transaction_restoration_contract",
  "test_graph_source_connection_budget_purity_contract")
failures <- 0L
for (name in names) {
  error <- tryCatch({stopifnot(isTRUE(tests[[name]]())); NULL}, error = identity)
  if (is.null(error)) cat(name, "PASS\n") else {
    failures <- failures + 1L
    cat(name, "FAIL", conditionMessage(error), "\n")
  }
}
cat("MATRIX_PREACTIVATION_FOCUSED discovered=", length(names), " executed=", length(names),
  " passed=", length(names) - failures, " failed=", failures, " skipped=0 native_dispatch=DISABLED\n", sep = "")
if (failures) quit(status = 1L)
