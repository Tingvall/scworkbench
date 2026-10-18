.engine_graph_aggregate_fixture <- function(n=33L,partition_bytes=8192L,partition_rows=16L,
    unicode=FALSE) {
  nodes<-list(list(node_id="node"))
  edges<-lapply(seq_len(n),function(i)list(edge_id=paste0(if(unicode)"edge_雪_" else "edge_",i),
    kind="ordinary",direction="undirected"))
  incidences<-unlist(lapply(seq_along(edges),function(i)lapply(0:1,function(j)
    list(incidence_id=paste0("inc_",i,"_",j),edge_id=edges[[i]]$edge_id,
      node_id="node",role="member",ordinal=j))),recursive=FALSE)
  graph<-wb_prim_graph(nodes,edges,incidences,direction_mode="undirected")
  stage<-scworkbench:::.wb_graph_stage_small(graph,list(partition_bytes=partition_bytes,
    partition_rows=partition_rows))
  list(graph=graph,stage=stage)
}

test_engine_graph_aggregate_bounded_batches_contract <- function() {
  f<-.engine_graph_aggregate_fixture(73L,unicode=TRUE);stage<-f$stage
  on.exit(scworkbench:::.wb_graph_stage_discard(stage),add=TRUE)
  batches<-list()
  saved<-options(scworkbench.graph_storage_test_hook=function(event,state) {
    if(event=="edge_aggregate_batch")batches[[length(batches)+1L]]<<-state
  });on.exit(options(saved),add=TRUE)
  identity<-scworkbench:::.wb_graph_sql_identities(stage$con,"staged",stage$budgets)
  stopifnot(identical(identity$content_identity,wb_graph_identity(f$graph)$content_identity),
    sum(vapply(batches,`[[`,integer(1),"rows"))==73L,
    any(vapply(batches,function(batch)batch$rows>1L,logical(1))),
    all(vapply(batches,function(batch)batch$rows<=16L &&
      batch$rows<=batch$max_rows && batch$encoded_bytes+batch$carrier_bytes<=8192,
      logical(1))))
  TRUE
}

test_engine_graph_aggregate_giant_utf8_whitespace_contract <- function() {
  f<-.engine_graph_aggregate_fixture(5L,4096L,512L,unicode=TRUE);stage<-f$stage
  on.exit(scworkbench:::.wb_graph_stage_discard(stage),add=TRUE)
  for(i in seq_along(f$graph$content$edges)) {
    text<-scworkbench:::.wb_operation_pack_canonical_json(f$graph$content$edges[[i]])
    text<-paste0(text,strrep(" ",4096L-nchar(text,type="bytes")))
    DBI::dbExecute(stage$con,"UPDATE artifact_graph_rows SET record_json=? WHERE component='edges' AND row_ordinal=?",
      params=list(text,i-1L))
  }
  batches<-list();saved<-options(scworkbench.graph_storage_test_hook=function(event,state) {
    if(event=="edge_aggregate_batch")batches[[length(batches)+1L]]<<-state
  });on.exit(options(saved),add=TRUE)
  identity<-scworkbench:::.wb_graph_sql_identities(stage$con,"staged",stage$budgets)
  stopifnot(length(batches)==5L,
    all(vapply(batches,function(batch)batch$rows==1L && batch$encoded_bytes==4096L &&
      batch$max_rows==1L,logical(1))),
    identical(identity$content_identity,wb_graph_identity(f$graph)$content_identity))
  TRUE
}

test_engine_graph_aggregate_growth_and_cursor_cleanup_contract <- function() {
  f<-.engine_graph_aggregate_fixture();stage<-f$stage
  on.exit(scworkbench:::.wb_graph_stage_discard(stage),add=TRUE)
  rows<-DBI::dbGetQuery(stage$con,"SELECT row_ordinal,record_json FROM artifact_graph_rows WHERE component='edges' ORDER BY row_ordinal")
  for(mode in c("growth","nontext","fault")) {
    fired<-FALSE
    saved<-options(scworkbench.graph_storage_test_hook=function(event,state) {
      if(event=="edge_aggregate_ready" && mode!="fault") {
        fired<<-TRUE
        if(mode=="growth") DBI::dbExecute(state$con,
          "UPDATE artifact_graph_rows SET record_json=record_json||? WHERE component='edges'",
          params=list(strrep(" ",as.integer(state$observed_max_edge_bytes)+1L))) else
          DBI::dbExecute(state$con,"UPDATE artifact_graph_rows SET record_json=CAST(record_json AS BLOB) WHERE component='edges'")
      }
      if(event=="edge_aggregate_batch" && mode=="fault") {
        fired<<-TRUE;stop("GRAPH_AGGREGATE_BATCH_FAULT")
      }
    })
    failure<-tryCatch(scworkbench:::.wb_graph_sql_identities(stage$con,"staged",stage$budgets),error=identity)
    options(saved)
    stopifnot(fired,inherits(failure,"error"))
    if(mode!="fault")stopifnot(inherits(failure,"wb_graph_error"),
      identical(failure$code,"GRAPH_RESOURCE_EXCEEDED")) else
      stopifnot(grepl("GRAPH_AGGREGATE_BATCH_FAULT",conditionMessage(failure),fixed=TRUE))
    # An unclosed cursor would cause RSQLite's subsequent-query close warning.
    withCallingHandlers(stopifnot(DBI::dbGetQuery(stage$con,"SELECT 1 AS ok")$ok[[1L]]==1L),
      warning=function(w)stop(conditionMessage(w)))
    for(i in seq_len(nrow(rows)))DBI::dbExecute(stage$con,
      "UPDATE artifact_graph_rows SET record_json=? WHERE component='edges' AND row_ordinal=?",
      params=list(rows$record_json[[i]],rows$row_ordinal[[i]]))
  }
  stopifnot(identical(scworkbench:::.wb_graph_sql_identities(stage$con,"staged",stage$budgets)$content_identity,
    wb_graph_identity(f$graph)$content_identity))
  TRUE
}

test_engine_graph_aggregate_policy_and_eof_admission_contract <- function() {
  f<-.engine_graph_aggregate_fixture(3L,8192L,2L);stage<-f$stage
  on.exit(scworkbench:::.wb_graph_stage_discard(stage),add=TRUE)
  control<-new.env(parent=emptyenv());control$active<-FALSE;control$count<-0L
  saved_control<-options(scworkbench.graph_aggregate_admission_probe=control)
  on.exit(options(saved_control),add=TRUE)
  trace(".wb_graph_transient_admit",where=asNamespace("scworkbench"),print=FALSE,
    tracer=quote({.probe<-getOption("scworkbench.graph_aggregate_admission_probe")
      if(isTRUE(.probe$active)) {
        .probe$count<-.probe$count+1L
        if(.probe$count==4L).wb_graph_require(FALSE,"GRAPH_RESOURCE_EXCEEDED","AGGREGATE_FINAL_ADMISSION_FAULT")
      }}))
  on.exit(untrace(".wb_graph_transient_admit",where=asNamespace("scworkbench")),add=TRUE)
  batches<-list();saved<-options(scworkbench.graph_storage_test_hook=function(event,state) {
    if(event=="edge_aggregate_ready")control$active<-TRUE
    if(event=="edge_aggregate_batch")batches[[length(batches)+1L]]<<-state
  });on.exit(options(saved),add=TRUE)
  failure<-tryCatch(scworkbench:::.wb_graph_sql_identities(stage$con,"staged",stage$budgets),error=identity)
  stopifnot(inherits(failure,"wb_graph_error"),failure$code=="GRAPH_RESOURCE_EXCEEDED",
    grepl("AGGREGATE_FINAL_ADMISSION_FAULT",conditionMessage(failure),fixed=TRUE),
    identical(vapply(batches,`[[`,integer(1),"rows"),c(2L,1L)),control$count==4L)
  withCallingHandlers(stopifnot(DBI::dbGetQuery(stage$con,"SELECT 1 AS ok")$ok[[1L]]==1L),
    warning=function(w)stop(conditionMessage(w)))
  TRUE
}
