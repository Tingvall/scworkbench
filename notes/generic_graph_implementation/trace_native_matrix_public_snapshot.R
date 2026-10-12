args <- commandArgs(TRUE)
.libPaths(c(file.path(args[[1L]],"library"),.libPaths()))
library(scworkbench)
`%||%` <- getFromNamespace("%||%","scworkbench")
options(error=function(){traceback(40L);quit(save="no",status=1L)})
trace(".wb_graph_source_snapshot",where=asNamespace("scworkbench"),print=FALSE,
  tracer=quote(cat("SNAPSHOT_TRACE bundle=",bundle$dir," durable=",bundle$staging_source_bundle$dir %||% "NONE",
    " source=",source_ref$source_id %||% artifact_id %||% "NONE"," snapshot=",snapshot_id %||% "NONE","\n",sep="")))
options(scworkbench.operation_pack_v2_test_hook=function(event,...){cat("PUBLIC_PHASE",event,"\n");flush.console()})
sys.source("tests/test_graph_native_matrix_public_promotion_first_contract.R",globalenv())
trace(".wb_graph_native_matrix_source_authorize",where=asNamespace("scworkbench"),print=FALSE,
  tracer=quote(cat("NATIVE_AUTH_TRACE bundle=",bundle$dir," durable=",bundle$staging_source_bundle$dir %||% "NONE","\n",sep="")))
trace("wb_session_promote_current",where=asNamespace("scworkbench"),print=FALSE,
  exit=quote({
    if(DBI::dbIsValid(bundle$con)) {
      fragments <- wb_matrix_fragments(bundle,"RNA_log")
      cat("PROMOTION_EXIT source=",bundle$dir," paths=",paste(fragments$path,collapse="|"),
        " exists=",paste(file.exists(file.path(bundle$dir,fragments$path)),collapse="|"),"\n",sep="")
    }
  }))
trace("wb_art_graph_info",where=asNamespace("scworkbench"),print=FALSE,
  tracer=quote(cat("GRAPH_INFO_TRACE bundle=",bundle$dir," artifact=",artifact_id,"\n",sep="")))
original_promote <- getFromNamespace("wb_session_promote_current","scworkbench")
wb_session_promote_current <- function(bundle,session,...) {
  result <- original_promote(bundle,session,...)
  fragments <- wb_matrix_fragments(bundle,"RNA_log")
  cat("PUBLIC_PROMOTION_RETURN source=",bundle$dir," paths=",paste(fragments$path,collapse="|"),
    " exists=",paste(file.exists(file.path(bundle$dir,fragments$path)),collapse="|"),"\n",sep="")
  result
}
original_info <- getFromNamespace("wb_art_graph_info","scworkbench")
wb_art_graph_info <- function(bundle,artifact_id,...) {
  cat("PUBLIC_GRAPH_INFO bundle=",bundle$dir," artifact=",artifact_id,"\n",sep="")
  original_info(bundle,artifact_id,...)
}
withCallingHandlers(stopifnot(isTRUE(test_graph_native_matrix_public_promotion_first_lifecycle_contract())),
  error=function(error){
    if(grepl("locking protocol",conditionMessage(error),fixed=TRUE)) {
      cat("LOCKING_PROTOCOL_STACK\n")
      for(call in tail(sys.calls(),24L))cat(paste(deparse(call),collapse=" "),"\n")
      str(error)
    }
  })
