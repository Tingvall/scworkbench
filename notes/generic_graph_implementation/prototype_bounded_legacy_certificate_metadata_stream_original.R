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
dyn.load('/tmp/scwb-json-typed-366.so')
initializer <- DBI::dbConnect(RSQLite::SQLite(),':memory:',default.extensions=FALSE)
DBI::dbGetQuery(initializer,'SELECT load_extension(?,?);',params=list(
  '/tmp/scwb-json-typed-366.so','sqlite3_scwbjsonprototype_init'))
DBI::dbDisconnect(initializer)
source('notes/generic_graph_implementation/prototype_bounded_json_walk_typed_once.R')
source('notes/generic_graph_implementation/prototype_bounded_provenance_refs_typed.R')
source('notes/generic_graph_implementation/prototype_bounded_legacy_descriptor.R')
source('notes/generic_graph_implementation/prototype_bounded_metadata_array_context.R')
source('notes/generic_graph_implementation/prototype_bounded_physical_metadata_closed.R')
source('notes/generic_graph_implementation/prototype_bounded_legacy_payload_metadata_stream.R')
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
prototype_artifact_identity <- function(bundle,id) {
  stopifnot(identical(id,fixture$source_axis_artifact_id))
  database <- DBI::dbGetQuery(bundle$con,"PRAGMA database_list;")
  path <- database$file[database$name=="main"][[1L]]
  selector <- DBI::dbConnect(RSQLite::SQLite(),path,flags=RSQLite::SQLITE_RO,cache_size=-64)
  on.exit(DBI::dbDisconnect(selector),add=TRUE)
  DBI::dbExecute(selector,"PRAGMA temp_store=FILE;")
  descriptor <- prototype_legacy_descriptor(bundle$con,selector,id,policy)
  payload <- prototype_legacy_cell_vector_stream_hash(bundle$con,selector,id,policy,descriptor)
  stopifnot(descriptor$rows==90000,payload$metadata_bytes==183)
  list(content_sha256=payload$sha256,
    content_identity_scheme=unname(scworkbench:::.wb_content_identity_schemes()[["object"]]))
}
identity <- getFromNamespace(".wb_certificate_identity","scworkbench")
replace_identity <- function(expr) {
  if(!is.call(expr))return(expr)
  if(identical(expr[[1L]],as.name(".wb_prov_payload_identity")) &&
     length(expr)==3L && is.call(expr[[3L]]) && identical(expr[[3L]][[1L]],as.name("wb_art_load")))
    return(quote(prototype_artifact_identity(bundle,id)))
  for(i in seq_along(expr)[-1L])expr[i] <- list(replace_identity(expr[[i]]))
  expr
}
body(identity) <- replace_identity(body(identity))
identity_scope <- new.env(parent=environment(identity))
identity_scope$prototype_artifact_identity <- prototype_artifact_identity
environment(identity) <- identity_scope
certificate_fun <- getFromNamespace("wb_entity_certificate","scworkbench")
certificate_scope <- new.env(parent=environment(certificate_fun))
certificate_scope$wb_prov_bundle_dag <- dag
certificate_scope$.wb_certificate_identity <- identity
environment(certificate_fun) <- certificate_scope
prefix <- "/tmp/scwb-graph-artifact-certificate-bounded-369"
stopifnot(!file.exists(paste0(prefix,".allocations")))
report <- function(phase) {
  status <- readLines("/proc/self/status")
  cat("BOUNDED_FULL_CERTIFICATE",phase,paste(status[grepl("^(VmRSS|VmHWM):",status)],collapse=" "),"\n")
  flush.console()
}
report("before")
Rprofmem(paste0(prefix,".allocations"),threshold=1048576)
time <- system.time(result <- certificate_fun(bundle,"artifact",fixture$source_axis_artifact_id))
Rprofmem(NULL)
expected <- readRDS("/tmp/scwb-graph-original-artifact-certificate-263.certificate.rds")
saveRDS(result,paste0(prefix,".certificate.rds"))
stopifnot(identical(result,expected))
report("after")
cat("BOUNDED_FULL_CERTIFICATE exact_saved269_object=TRUE source_rows=90000 metadata_bytes=183 content_sha256=",
  result$identity$content_sha256," elapsed=",time[["elapsed"]]," prototype_only=TRUE qualification=FALSE PASS\n",sep="")
restore();wb_close_bundle(bundle)
stopifnot(identical(before,digest::digest(file=source_path,algo="sha256",serialize=FALSE)))
cat("BOUNDED_FULL_CERTIFICATE original_sourceDB=UNCHANGED PASS\n")
