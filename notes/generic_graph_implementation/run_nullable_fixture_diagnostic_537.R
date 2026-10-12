lib <- "/tmp/scwb-graph-final-valid-522.hxhra5_g/library"
.libPaths(c(lib,.libPaths()));library(scworkbench,lib.loc=lib)
env <- new.env(parent=asNamespace("scworkbench"))
sys.source("inst/tests/contract_test_runner.R",env)
sys.source("notes/generic_graph_implementation/nullable_fixture_diagnostic_537.R",env)
result <- tryCatch(withCallingHandlers(do.call(env$test_nullable_cell_vector_family_storage_contract,list()),
 error=function(e) {
  for(f in sys.frames()) if(exists("old_before",f,inherits=FALSE)) {
   cat("ACTUAL_MIGRATION_ATTEMPT_RESULT\n");print(get("failed",f))
   cat("OLD_FIXTURE_LEDGER\n");print(get("old_before",f)$ledger)
  }
 }),error=function(e){cat("UNCHANGED_TEST_FAILURE ",conditionMessage(e),"\n",sep="");FALSE})
cat("CORRECTED_FIXTURE_RESULT=",result,"\n",sep="")
quit(status=if(isTRUE(result))0L else 1L)
