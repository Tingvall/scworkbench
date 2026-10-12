# Outside-candidate prototype; no production replacement or qualification claim.
args <- commandArgs(TRUE)
stopifnot(length(args)==1L)
lib <- "/tmp/scwb-graph-forge-duplicate-sensitive-444.ps0av2oi/library"
.libPaths(c(lib,.libPaths()))
library(scworkbench,lib.loc=lib)
old <- readRDS("notes/generic_graph_implementation/evidence/471_promotion_fingerprint_only_tuple445.rds")$value
metadata_version <- function(pkg) tryCatch(
  as.character(utils::packageVersion(pkg)), error=function(error)NA_character_)
prototype <- function() list(
  scworkbench_version=as.character(utils::packageVersion("scworkbench")),
  r_version=R.version.string,
  source_revision=Sys.getenv("SCWORKBENCH_SOURCE_REVISION",unset=NA_character_),
  container_digest=Sys.getenv("SCWORKBENCH_CONTAINER_DIGEST",unset=NA_character_),
  packages=vapply(c("BPCells","Matrix","irlba","uwot","igraph"),
    metadata_version,character(1)))
before <- readLines("/proc/self/status")
loaded_before <- loadedNamespaces()
Rprofmem(paste0(args[[1L]],".allocations"),threshold=1048576)
value <- prototype()
Rprofmem(NULL)
after <- readLines("/proc/self/status")
loaded_after <- loadedNamespaces()
stopifnot(identical(value,old),identical(loaded_before,loaded_after))
saveRDS(list(value=value,legacy_value_identical=TRUE,before=before,after=after,
  namespaces_before=loaded_before,namespaces_after=loaded_after,
  qualification=FALSE),paste0(args[[1L]],".rds"))
cat("METADATA_PROTOTYPE_BEFORE",paste(before[grepl("^(VmRSS|VmHWM):",before)],collapse=" "),"\n")
cat("METADATA_PROTOTYPE_AFTER",paste(after[grepl("^(VmRSS|VmHWM):",after)],collapse=" "),"\n")
cat("METADATA_PROTOTYPE legacy_fingerprint_value_IDENTICAL=TRUE namespaces_unchanged=TRUE qualification=FALSE\n")
