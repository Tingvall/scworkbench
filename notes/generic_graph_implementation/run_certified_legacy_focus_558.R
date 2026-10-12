lib <- "/tmp/scwb-certified-legacy-557.hoed40gm/library"
.libPaths(c(lib,.libPaths()));library(scworkbench,lib.loc=lib)
scworkbench:::.wb_matrix_native_byte_api_initialize()
env <- new.env(parent=asNamespace("scworkbench"))
sys.source("inst/tests/contract_test_runner.R",env)
inventory <- env$contract_test_discover("tests",exclusions=character(),parent_env=env)
names <- c("test_graph_authentic_legacy_object_content_load_contract",
 "test_graph_object_proof_removal_content_and_authority_contract",
 "test_graph_sql_transaction_roundtrip_contract","test_graph_typed_missing_values_contract",
 "test_nullable_cell_vector_family_storage_contract","test_operation_docs_single_source_contract",
 "test_operation_pack_sdk_catalog_coverage")
selected <- lapply(names,function(name){matches <- Filter(function(record)identical(record$name,name),inventory$tests);stopifnot(length(matches)==1L);matches[[1L]]})
inventory$tests <- selected;inventory$files <- unique(vapply(selected,`[[`,character(1),"file"))
run <- env$contract_test_execute(inventory,reporter=TRUE)
saveRDS(run,"notes/generic_graph_implementation/evidence/558_certified_legacy_focus.rds")
env$contract_test_assert_success(run)
