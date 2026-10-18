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
  for(mode in c("growth","nontext","fault","drop")) {
    fired<-FALSE
    saved<-options(scworkbench.graph_storage_test_hook=function(event,state) {
      if(event=="edge_aggregate_ready" && mode!="fault") {
        fired<<-TRUE
        if(mode=="drop") DBI::dbExecute(state$con,
          "DELETE FROM artifact_graph_rows WHERE component='edges'") else if(mode=="growth") DBI::dbExecute(state$con,
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
      identical(failure$code,if(mode=="drop")"GRAPH_INCIDENCE_DANGLING" else "GRAPH_RESOURCE_EXCEEDED")) else
      stopifnot(grepl("GRAPH_AGGREGATE_BATCH_FAULT",conditionMessage(failure),fixed=TRUE))
    # An unclosed cursor would cause RSQLite's subsequent-query close warning.
    withCallingHandlers(stopifnot(DBI::dbGetQuery(stage$con,"SELECT 1 AS ok")$ok[[1L]]==1L),
      warning=function(w)stop(conditionMessage(w)))
    if(mode=="drop") DBI::dbAppendTable(stage$con,"artifact_graph_rows",data.frame(
      artifact_id="staged",component="edges",row_ordinal=rows$row_ordinal,
      record_json=rows$record_json,stringsAsFactors=FALSE)) else
      for(i in seq_len(nrow(rows)))DBI::dbExecute(stage$con,
        "UPDATE artifact_graph_rows SET record_json=? WHERE component='edges' AND row_ordinal=?",
        params=list(rows$record_json[[i]],rows$row_ordinal[[i]]))
  }
  stopifnot(identical(scworkbench:::.wb_graph_sql_identities(stage$con,"staged",stage$budgets)$content_identity,
    wb_graph_identity(f$graph)$content_identity))
  TRUE
}

test_engine_graph_aggregate_empty_mixed_and_caller_transaction_contract <- function() {
  empty<-wb_prim_graph(list(),list(),list(),direction_mode="mixed")
  nodes<-lapply(c("n1","n2","n3"),function(id)list(node_id=id))
  edges<-list(list(edge_id="a",kind="ordinary",direction="directed"),
    list(edge_id="long_雪_network",kind="hyper",direction="undirected"),
    list(edge_id="c",kind="hyper",direction="directed"),
    list(edge_id="self",kind="ordinary",direction="undirected"))
  incidences<-list();add<-function(edge,participants,roles) {
    for(j in seq_along(participants))incidences[[length(incidences)+1L]]<<-list(
      incidence_id=paste0("i",length(incidences)),edge_id=edge,node_id=participants[[j]],
      role=roles[[j]],ordinal=j-1L)
  }
  add("a",c("n1","n2"),c("tail","head"))
  add("long_雪_network",c("n1","n3","n1"),rep("member",3L))
  add("c",c("n1","n2","n3"),c("tail","tail","head"))
  add("self",c("n1","n1"),c("member","member"))
  mixed<-wb_prim_graph(nodes,edges,incidences,direction_mode="mixed")
  for(graph in list(empty,mixed)) local({
    stage<-scworkbench:::.wb_graph_stage_small(graph,list(partition_bytes=8192L,partition_rows=2L))
    on.exit(scworkbench:::.wb_graph_stage_discard(stage),add=TRUE)
    DBI::dbGetQuery(stage$con,"PRAGMA journal_mode=WAL;")
    DBI::dbBegin(stage$con)
    DBI::dbExecute(stage$con,"SAVEPOINT aggregate_caller;")
    before<-DBI::dbGetQuery(stage$con,"SELECT total_changes();")
    actual<-scworkbench:::.wb_graph_sql_identities(stage$con,"staged",stage$budgets)
    stopifnot(identical(actual$content_identity,wb_graph_identity(graph)$content_identity),
      isTRUE(RSQLite::sqliteIsTransacting(stage$con)),
      identical(before,DBI::dbGetQuery(stage$con,"SELECT total_changes();")))
    DBI::dbExecute(stage$con,"ROLLBACK TO aggregate_caller;")
    DBI::dbExecute(stage$con,"RELEASE aggregate_caller;")
    DBI::dbRollback(stage$con)
    if(length(graph$content$edges)) {
      DBI::dbExecute(stage$con,paste0("UPDATE artifact_graph_rows SET record_json=",
        "json_set(record_json,'$.role','member') WHERE component='incidences' AND row_ordinal=1;"))
      failure<-tryCatch(scworkbench:::.wb_graph_sql_identities(stage$con,"staged",stage$budgets),error=identity)
      stopifnot(inherits(failure,"wb_graph_error"),failure$code=="GRAPH_ARITY_INVALID")
    }
  })
  TRUE
}

test_engine_graph_aggregate_policy_and_eof_admission_contract <- function() {
  f<-.engine_graph_aggregate_fixture(3L,8192L,2L);stage<-f$stage
  on.exit(scworkbench:::.wb_graph_stage_discard(stage),add=TRUE)
  # Inject an invalid private observation into a local function copy, not a
  # pack-supplied bound or a new production override. Guard must precede fetch.
  faulty<-scworkbench:::.wb_graph_validate_sql
  rewrite<-function(expr) {
    if(identical(expr,quote(max_edge_bytes <- 0)))return(quote(max_edge_bytes <- NA_real_))
    if(!is.call(expr))return(expr)
    as.call(lapply(as.list(expr),rewrite))
  }
  body(faulty)<-rewrite(body(faulty))
  invalid<-tryCatch(faulty(stage$con,"staged",stage$budgets),error=identity)
  stopifnot(inherits(invalid,"wb_graph_error"),invalid$code=="GRAPH_RESOURCE_EXCEEDED",
    grepl("Invalid graph aggregate byte-bound observation",conditionMessage(invalid),fixed=TRUE))
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
