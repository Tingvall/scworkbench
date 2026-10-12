lib <- "/tmp/scwb-certified-legacy-557.hoed40gm/library"
.libPaths(c(lib,.libPaths()));library(scworkbench,lib.loc=lib)
scworkbench:::.wb_matrix_native_byte_api_initialize()
env <- new.env(parent=asNamespace("scworkbench"))
sys.source("inst/tests/contract_test_runner.R",env)
inventory <- env$contract_test_discover("tests",exclusions=character(),parent_env=env)
names <- c("test_graph_retained_cell_source_payload_contract",
 "test_graph_object_source_batch_identity_admission_restoration_contract")
selected <- lapply(names,function(name){matches <- Filter(function(record)identical(record$name,name),inventory$tests);stopifnot(length(matches)==1L);matches[[1L]]})
inventory$tests <- selected;inventory$files <- unique(vapply(selected,`[[`,character(1),"file"))
run <- env$contract_test_execute(inventory,reporter=TRUE)
saveRDS(run,"notes/generic_graph_implementation/evidence/559_graph_source_authority_focus.rds")
env$contract_test_assert_success(run)
