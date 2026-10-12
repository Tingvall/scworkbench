args <- commandArgs(TRUE)
stopifnot(length(args)==2L,args[[2L]] %in% c("original","projection"))
.libPaths(c(file.path(args[[1L]],"library"),.libPaths()))
library(scworkbench)
fixture <- readRDS("/tmp/scwb-graph-manifest-batch-lifecycle-246.rds")
source_path <- file.path(fixture$source_bundle,"db/app.sqlite")
before <- digest::digest(file=source_path,algo="sha256",serialize=FALSE)
# Reuse only the isolated diagnostic copy; the original source is never opened.
bundle <- wb_open_bundle("/tmp/scwb-graph-original-artifact-certificate-copy-263/source.bundle",validate=FALSE)
policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes="8388608",sqlite_cache_kib=2048L,
  partition_bytes=262144L,partition_rows=256L,collect_bytes=4194304L))
restore <- scworkbench:::.wb_graph_aggregate_connection_budget(list(bundle$con),policy)
dag <- getFromNamespace("wb_prov_bundle_dag","scworkbench")
if(args[[2L]]=="projection") {
  prototype_art_registry <- function(bundle,include_history=TRUE) {
    stopifnot(isTRUE(include_history))
    DBI::dbGetQuery(bundle$con,paste0("SELECT artifact_id,name,type,provenance_snapshot_id,",
      "source_op,created_at,lineage_status FROM artifacts ORDER BY created_at DESC;"))
  }
  substitute_calls <- function(expr) {
    if(!is.call(expr)) return(expr)
    if(identical(expr[[1L]],as.name("wb_art_list"))) expr[[1L]] <- as.name("prototype_art_registry")
    for(i in seq_along(expr)[-1L]) expr[i] <- list(substitute_calls(expr[[i]]))
    expr
  }
  body(dag) <- substitute_calls(body(dag))
  scope <- new.env(parent=environment(dag));scope$prototype_art_registry <- prototype_art_registry
  environment(dag) <- scope
}
prefix <- paste0("/tmp/scwb-graph-artifact-registry-",args[[2L]],"-277")
stopifnot(!file.exists(paste0(prefix,".allocations")))
cat("ARTIFACT_REGISTRY_BEFORE_DAG",paste(readLines("/proc/self/status")[grepl("^(VmRSS|VmHWM):",readLines("/proc/self/status"))],collapse=" "),"\n")
Rprofmem(paste0(prefix,".allocations"),threshold=1048576)
time <- system.time(result <- dag(bundle,include_snapshots=TRUE,include_registry_mutations=TRUE,include_superseded=TRUE))
Rprofmem(NULL)
sha <- digest::digest(jsonlite::serializeJSON(result,digits=NA),algo="sha256",serialize=FALSE)
saveRDS(result,paste0(prefix,".dag.rds"))
if(args[[2L]]=="projection") stopifnot(identical(result,readRDS("/tmp/scwb-graph-artifact-registry-original-272.dag.rds")))
cat("ARTIFACT_REGISTRY_PROFILE mode=",args[[2L]]," elapsed=",time[["elapsed"]]," dag_sha256=",sha,"\n",sep="")
cat(paste(readLines("/proc/self/status")[grepl("^(VmRSS|VmHWM):",readLines("/proc/self/status"))],collapse=" "),"\n")
restore();wb_close_bundle(bundle)
stopifnot(identical(before,digest::digest(file=source_path,algo="sha256",serialize=FALSE)))
cat("ARTIFACT_REGISTRY_PROFILE original_sourceDB=UNCHANGED source_axes=90000 prototype_only=TRUE qualification=FALSE\n")
