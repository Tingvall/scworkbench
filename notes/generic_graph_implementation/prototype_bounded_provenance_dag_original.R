args <- commandArgs(TRUE)
stopifnot(length(args)==1L)
args <- c(args,"projection")
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
`%||%` <- getFromNamespace("%||%","scworkbench")
scworkbench:::.wb_matrix_native_byte_api_initialize()
dyn.load('/tmp/scwb-bounded-json-lexer-prototype-291.so')
initializer <- DBI::dbConnect(RSQLite::SQLite(),':memory:',default.extensions=FALSE)
DBI::dbGetQuery(initializer,'SELECT load_extension(?,?);',params=list(
  '/tmp/scwb-bounded-json-lexer-prototype-291.so','sqlite3_scwbjsonprototype_init'))
DBI::dbDisconnect(initializer)
source('notes/generic_graph_implementation/prototype_bounded_json_walk.R')
source('notes/generic_graph_implementation/prototype_bounded_provenance_refs.R')
prototype_dependency_edges <- function(bundle) {
  arts <- DBI::dbGetQuery(bundle$con,"SELECT artifact_id,CAST(rowid AS TEXT) AS source_rowid,length(provenance_json) AS provenance_length FROM artifacts ORDER BY created_at DESC;")
  out <- list()
  for(i in seq_len(nrow(arts))) {
    if(is.na(arts$provenance_length[i]) || arts$provenance_length[i]==0)next
    parents <- prototype_provenance_refs(bundle$con,arts$source_rowid[i],policy)
    for(parent in parents)out[[length(out)+1L]] <- data.frame(parent_artifact_id=parent,
      child_artifact_id=as.character(arts$artifact_id[i]),stringsAsFactors=FALSE)
  }
  if(!length(out))return(data.frame(parent_artifact_id=character(),child_artifact_id=character(),stringsAsFactors=FALSE))
  unique(do.call(rbind,out))
}
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
    if(identical(expr[[1L]],as.name(".wb_art_dependency_edges"))) expr[[1L]] <- as.name("prototype_dependency_edges")
    for(i in seq_along(expr)[-1L]) expr[i] <- list(substitute_calls(expr[[i]]))
    expr
  }
  body(dag) <- substitute_calls(body(dag))
  scope <- new.env(parent=environment(dag));scope$prototype_art_registry <- prototype_art_registry;scope$prototype_dependency_edges <- prototype_dependency_edges
  environment(dag) <- scope
}
prefix <- "/tmp/scwb-graph-artifact-registry-bounded-refs-345"
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
