lib <- "/tmp/scwb-graph-final-valid-522.hxhra5_g/library"
.libPaths(c(lib,.libPaths()));library(scworkbench,lib.loc=lib)
env <- new.env(parent=asNamespace("scworkbench"))
sys.source("tests/test_graph_resource_accounting_contract.R",env)
result <- tryCatch(withCallingHandlers(env$test_graph_resource_aggregate_cache_and_nested_policy_contract(),
 error=function(e) {
   for(f in sys.frames()) if(exists("branches",f,inherits=FALSE)) {
     cat("DIAGNOSTIC observed branches:");dput(get("branches",f))
     cat("DIAGNOSTIC actual cache:");dput(get("cache",f)())
     cat("DIAGNOSTIC admitted cache:");dput(get("admitted",f))
   }
 }),error=function(e){cat("UNCHANGED_TEST_FAILURE ",conditionMessage(e),"\n",sep="");FALSE})
cat("UNCHANGED_TEST_RESULT=",result,"\n",sep="")
quit(status=if(isTRUE(result))0L else 1L)
