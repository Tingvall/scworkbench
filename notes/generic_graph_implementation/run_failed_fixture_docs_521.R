args <- commandArgs(TRUE);stopifnot(length(args)==2L)
.libPaths(c(args[[1L]],.libPaths()));library(scworkbench,lib.loc=args[[1L]])
setwd(args[[2L]])
env <- new.env(parent=asNamespace("scworkbench"));sys.source("inst/tests/contract_test_runner.R",env)
files <- c("test_central_schema_foreign_key_closure_contract.R","test_central_schema_migration_foreign_keys_contract.R",
 "test_generated_document_revision_contract.R","test_historical_nullable_schema_layout_contract.R",
 "test_schema_catalog_durable_membership_contract.R")
inventory <- env$contract_test_discover("tests",exclusions=character(),parent_env=env,files=files)
run <- env$contract_test_execute(inventory,reporter=TRUE)
saveRDS(run,"/tmp/scwb-graph-final-corrected-515.qnyb2b4t/fixture_doc_focus_521.rds")
env$contract_test_assert_success(run);stopifnot(all(run$results$status=="passed"))
cat("FIXTURE_DOC_FOCUS PASS zero skips\n")
