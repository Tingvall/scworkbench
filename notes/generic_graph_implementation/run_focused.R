# Development-only graph inventory. Does not run the canonical package suite.
devtools::load_all(".", quiet = TRUE)
files <- c("test_graph_primitive_contract.R", "test_graph_source_authority_contract.R",
  "test_graph_strict_json_unicode_contract.R", "test_graph_abi4_admission_contract.R",
  "test_graph_binding_read_selection_contract.R", "test_graph_abi4_public_execution_contract.R",
  "test_graph_abi4_runtime_sidecar_contract.R", "test_graph_abi4_retained_count_contract.R")
tests <- new.env(parent = globalenv())
for (file in files) sys.source(file.path("tests", file), envir = tests)
names <- sort(ls(tests, pattern = "^test_"))
passed <- failed <- 0L
for (name in names) {
  error <- tryCatch({stopifnot(isTRUE(tests[[name]]())); NULL}, error = identity)
  if (is.null(error)) {passed <- passed + 1L; cat(name, "PASS\n")} else {
    failed <- failed + 1L; cat(name, "FAIL", conditionMessage(error), "\n")
  }
}
cat(sprintf("GRAPH_FOCUSED_SUMMARY discovered=%d executed=%d passed=%d skipped=0 failed=%d\n",
  length(names), length(names), passed, failed))
if (failed) quit(status = 1L)
