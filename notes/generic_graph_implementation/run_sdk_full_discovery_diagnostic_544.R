lib <- "/tmp/scwb-graph-final-valid-522.hxhra5_g/library"
.libPaths(c(lib,.libPaths()));library(scworkbench,lib.loc=lib)
cat("INSTALLED_CORE ",find.package("scworkbench"),"\n",sep="")
for(f in c("capabilities.json","capabilities-v4.json","capabilities.schema.json")) {
 p <- system.file("sdk","operation-packs",f,package="scworkbench")
 cat("ASSET ",f," path=",p," exists=",file.exists(p),"\n",sep="")
}
env <- new.env(parent=asNamespace("scworkbench"))
sys.source("inst/tests/contract_test_runner.R",env)
inventory <- env$contract_test_discover("tests",exclusions=character(),parent_env=env)
cat("DISCOVERY_ALL count=",length(inventory$tests),"\n",sep="")
record <- Filter(function(x)x$name=="test_operation_pack_sdk_catalog_coverage",inventory$tests)[[1]]
result <- tryCatch(withCallingHandlers(do.call(record$fn,list()),error=function(e){
 for(f in sys.frames()) if(exists("path",f,inherits=FALSE)) {cat("ERROR_FRAME_PATH ");dput(get("path",f))}
}),error=function(e){cat("UNCHANGED_FAILURE ",conditionMessage(e),"\n",sep="");FALSE})
cat("UNCHANGED_RESULT=",result,"\n",sep="")
quit(status=if(isTRUE(result))0L else 1L)
