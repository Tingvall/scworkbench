lib <- "/tmp/scwb-final-585.ki8nvr4e/library"
.libPaths(c(lib,.libPaths()));library(scworkbench,lib.loc=lib)
scworkbench:::.wb_matrix_native_byte_api_initialize()
Sys.setenv(SCWORKBENCH_TEST_INSTALLED="1",R_LIBS=lib,SCWB_CONTRACT_INSTALLED_LIBRARY=lib,SCWORKBENCH_PYBENCH_PYTHON="/tmp/scwb-final-python-588/bin/python",SCWORKBENCH_PYTHON_PACK_MANIFEST="/tmp/scwb-final-python-588/lib/python3.11/site-packages/scwbpython/operation-pack.json",SCWORKBENCH_PHASE3B_PYBENCH_ROOT="/tmp/scwb-phase3b-peer-590",SCWORKBENCH_PHASE3B_PYTHON_PACK_MANIFEST="/tmp/scwb-phase3b-python-590/lib/python3.11/site-packages/scwbpyv3reference/operation-pack.json")

env <- new.env(parent=asNamespace("scworkbench"))
sys.source("inst/tests/contract_test_runner.R",env)
inventory <- env$contract_test_discover("tests",exclusions=character(),parent_env=env)
names <- c("test_operation_pack_v1_cross_language_lifecycle_contract","test_operation_pack_v1_python_fault_confinement_contract")
selected <- lapply(names,function(name){matches <- Filter(function(record)identical(record$name,name),inventory$tests);stopifnot(length(matches)==1L);matches[[1L]]})
inventory$tests <- selected;inventory$files <- unique(vapply(selected,`[[`,character(1),"file"))
run <- env$contract_test_execute(inventory,reporter=TRUE)
saveRDS(run,"notes/generic_graph_implementation/evidence/593_configured_historical_python_focus.rds")
env$contract_test_assert_success(run)
