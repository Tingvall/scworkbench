args <- commandArgs(TRUE)
root <- args[[1L]]
.libPaths(c(file.path(root,"library"),.libPaths()))
library(scworkbench,lib.loc=file.path(root,"library"))
stopifnot(identical(normalizePath(find.package("scworkbench")),normalizePath(file.path(root,"library/scworkbench"))))
source("tests/test_graph_bounded_legacy_collector_contract.R")
functions <- ls(pattern="^test_graph_bounded_legacy_")
for(name in functions) {
  cat("COLLECTOR_TEST START ",name,"\n",sep="");flush.console()
  stopifnot(isTRUE(get(name)()))
  cat("COLLECTOR_TEST PASS ",name,"\n",sep="");flush.console()
}
cat("COLLECTOR_FOCUSED executed=",length(functions)," passed=",length(functions)," skipped=0 PASS\n",sep="")
cat("COLLECTOR_RUNTIME jsonlite=",as.character(packageVersion("jsonlite"))," DLL_SHA=",
  digest::digest(file=getLoadedDLLs()[["scworkbench"]][["path"]],algo="sha256",serialize=FALSE),"\n",sep="")
