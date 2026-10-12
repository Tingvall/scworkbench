lib <- "/tmp/scwb-final-585.ki8nvr4e/library"
.libPaths(c(lib,.libPaths()));library(scworkbench,lib.loc=lib)
e <- new.env(parent=asNamespace("scworkbench"))
sys.source("inst/tests/contract_test_runner.R",e)
sys.source("notes/generic_graph_implementation/evidence/609_typed_coverage_public_promotion_diagnostic_test.R",e)
stopifnot(isTRUE(do.call(e$test_typed_effective_cell_coverage_contract,list())))
cat("TYPED_COVERAGE_PUBLIC_PROMOTION_ORIGINAL_ASSERTIONS PASS\n")
