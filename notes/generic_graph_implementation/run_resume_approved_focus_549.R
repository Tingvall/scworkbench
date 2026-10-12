lib <- "/tmp/scwb-resume-baseline-548.31n69v9t/library"
.libPaths(c(lib,.libPaths()));library(scworkbench,lib.loc=lib)
stopifnot(identical(normalizePath(find.package("scworkbench")),normalizePath(file.path(lib,"scworkbench"))))
scworkbench:::.wb_matrix_native_byte_api_initialize()
namespace <- asNamespace("scworkbench"); registry <- get(".wb_operation_pack_registry",namespace)
env <- new.env(parent=namespace)
sys.source("inst/tests/contract_test_runner.R",env)
# Nested discovery fixtures use the canonical runner's global helper convention.
for(binding in ls(env,all.names=TRUE))assign(binding,get(binding,env,inherits=FALSE),globalenv())
inventory <- env$contract_test_discover("tests",exclusions=character(),parent_env=env)
names <- c("test_operation_docs_single_source_contract","test_operation_pack_sdk_catalog_coverage",
 "test_operation_pack_sdk_manifest_negatives","test_operation_pack_sdk_scaffold_safety",
 "test_operation_pack_v2_feature_set_registry_fail_closed_contract",
 "test_graph_resource_aggregate_cache_and_nested_policy_contract",
 "test_mixed_legacy_new_provenance_identity_contract","test_contract_runner_discovery_contract")
selected <- lapply(names,function(name){matches <- Filter(function(record)identical(record$name,name),inventory$tests);stopifnot(length(matches)==1L);matches[[1]]})
inventory$tests <- selected;inventory$files <- unique(vapply(selected,`[[`,character(1),"file"))
cat("FOCUSED_RESUME exact_installed_source=537 namespace_path=",getNamespaceInfo(namespace,"path")," selected=",length(selected),"\n",sep="")
run <- env$contract_test_execute(inventory,reporter=TRUE)
saveRDS(run,"notes/generic_graph_implementation/evidence/549_resume_approved_focus.rds")
stopifnot(identical(namespace,asNamespace("scworkbench")),identical(registry,get(".wb_operation_pack_registry",asNamespace("scworkbench"))))
cat("PINNED_NAMESPACE_AND_REGISTRY_UNCHANGED=TRUE\n")
env$contract_test_assert_success(run)
