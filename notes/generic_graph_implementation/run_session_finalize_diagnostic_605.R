lib <- "/tmp/scwb-final-585.ki8nvr4e/library"
.libPaths(c(lib,.libPaths()));library(scworkbench,lib.loc=lib)
e <- new.env(parent=asNamespace("scworkbench"))
sys.source("inst/tests/contract_test_runner.R",e)
sys.source("notes/generic_graph_implementation/evidence/605_session_finalize_diagnostic_test.R",e)
stopifnot(isTRUE(e$test_session_inspection_and_ingest_integrity_contract()))
cat("SESSION_PUBLIC_FINALIZE_ORIGINAL_ASSERTIONS PASS\n")
