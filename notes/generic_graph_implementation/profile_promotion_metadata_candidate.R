# Exact installed metadata inventory allocation diagnostic; not qualification.
args <- commandArgs(TRUE)
stopifnot(length(args)==2L)
lib <- file.path(args[[1L]],"library")
.libPaths(c(lib,.libPaths()))
library(scworkbench,lib.loc=lib)
stopifnot(identical(normalizePath(find.package("scworkbench")),
  normalizePath(file.path(lib,"scworkbench"))))
reference <- new.env(parent=baseenv())
sys.source("R/promotion_transitive.R",envir=reference)
for(name in c(".wb_promotion_package_version",".wb_promotion_runtime_fingerprint")) {
  actual <- getFromNamespace(name,"scworkbench")
  stopifnot(identical(body(actual),body(reference[[name]])),
    identical(formals(actual),formals(reference[[name]])))
}
before <- readLines("/proc/self/status")
loaded_before <- loadedNamespaces()
Rprofmem(paste0(args[[2L]],".allocations"),threshold=1048576)
value <- scworkbench:::.wb_promotion_runtime_fingerprint()
Rprofmem(NULL)
after <- readLines("/proc/self/status")
loaded_after <- loadedNamespaces()
old <- readRDS("notes/generic_graph_implementation/evidence/471_promotion_fingerprint_only_tuple445.rds")$value
stopifnot(identical(value,old),identical(loaded_before,loaded_after))
saveRDS(list(value=value,before=before,after=after,namespaces_before=loaded_before,
  namespaces_after=loaded_after,legacy_value_identical=TRUE,qualification=FALSE),
  paste0(args[[2L]],".rds"))
cat("INSTALLED_METADATA_BEFORE",paste(before[grepl("^(VmRSS|VmHWM):",before)],collapse=" "),"\n")
cat("INSTALLED_METADATA_AFTER",paste(after[grepl("^(VmRSS|VmHWM):",after)],collapse=" "),"\n")
cat("INSTALLED_METADATA legacy_fingerprint_IDENTICAL=TRUE namespace_unchanged=TRUE qualification=FALSE\n")
