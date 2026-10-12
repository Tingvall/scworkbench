# Diagnostic only: preserve the existing R.serializeJSON preimage, including
# physical payload order and the independently verified legacy descriptor.
prototype_legacy_cell_vector_stream_hash <- function(con,selector,artifact_id,budgets,descriptor) {
  stopifnot(descriptor$rows>0)
  header <- DBI::dbGetQuery(con,'SELECT value_type,meta_present FROM artifact_object_payload_meta WHERE artifact_id=?;',params=list(artifact_id))
  stopifnot(nrow(header)==1L)
  count <- DBI::dbGetQuery(selector,'SELECT COUNT(*) n,MAX(octet_length(cell_id)+octet_length(label)) bytes FROM artifact_labels WHERE artifact_id=?;',params=list(artifact_id))
  stopifnot(count$n[[1L]]==descriptor$rows)
  batch_rows <- max(1L,min(64L,floor(budgets$partition_bytes/(6*count$bytes[[1L]]+2048))))
  fields <- c('kind','cell_id','value','value_type',if(header$meta_present[[1L]]==1L)'meta')
  prefix <- '{"type":"character","attributes":{},"value":['
  vector <- function(emit,field) {
    cursor <- DBI::dbSendQuery(selector,'SELECT cell_id,label,value_num FROM artifact_labels WHERE artifact_id=? ORDER BY payload_ordinal;',params=list(artifact_id))
    on.exit(DBI::dbClearResult(cursor),add=TRUE)
    emit(prefix);first <- TRUE;observed <- 0
    repeat {
      rows <- DBI::dbFetch(cursor,n=batch_rows)
      if(!nrow(rows))break
      values <- if(field=='cell_id')rows$cell_id else if(header$value_type[[1L]]=='continuous') {
        value <- as.numeric(rows$value_num)
        bad <- is.na(value) & !is.na(rows$label) & nzchar(rows$label)
        if(any(bad))value[bad] <- suppressWarnings(as.numeric(rows$label[bad]))
        as.character(value)
      } else as.character(rows$label)
      encoded <- enc2utf8(jsonlite::serializeJSON(values,digits=NA))
      stopifnot(startsWith(encoded,prefix),endsWith(encoded,']}'),nchar(encoded,type='bytes')<=budgets$partition_bytes)
      if(!first)emit(',')
      emit(substr(encoded,nchar(prefix)+1L,nchar(encoded)-2L))
      first <- FALSE;observed <- observed+nrow(rows)
    }
    emit(']}');stopifnot(observed==descriptor$rows)
  }
  prototype_physical_metadata_stream(con,artifact_id,budgets,descriptor,function(metadata_path) {
  hash <- scworkbench:::.wb_graph_token_hash(function(emit) {
    scworkbench:::.wb_graph_native_list_start(emit,fields)
    scworkbench:::.wb_graph_native_scalar(emit,'cell_vector');emit(',')
    vector(emit,'cell_id');emit(',');vector(emit,'value');emit(',')
    scworkbench:::.wb_graph_native_scalar(emit,header$value_type[[1L]])
    if(header$meta_present[[1L]]==1L) {emit(',');prototype_metadata_canonical_hash(metadata_path,budgets,external_emit=emit)}
    emit(']}')
  },budgets)
  list(sha256=hash,rows=descriptor$rows,batch_rows=batch_rows,metadata_bytes=as.numeric(descriptor$metadata_bytes))
  })
}

# Diagnostic only: preserve the existing R.serializeJSON preimage, including
# physical payload order and the independently verified legacy descriptor.
prototype_legacy_cell_family_stream_hash <- function(con,selector,artifact_id,budgets,descriptor) {
  stopifnot(descriptor$rows>0)
  header <- DBI::dbGetQuery(con,'SELECT value_type,meta_present FROM artifact_object_payload_meta WHERE artifact_id=?;',params=list(artifact_id))
  stopifnot(nrow(header)==1L)
  count <- DBI::dbGetQuery(selector,'SELECT COUNT(*) n,MAX(octet_length(cell_id)+octet_length(lineage_id)) bytes FROM artifact_pseudotime WHERE artifact_id=?;',params=list(artifact_id))
  stopifnot(count$n[[1L]]==descriptor$rows)
  batch_rows <- max(1L,min(64L,floor(budgets$partition_bytes/(6*count$bytes[[1L]]+2048))))
  fields <- c('kind','key','cell_id','value','value_type','meta')
  stopifnot(header$meta_present[[1L]]==1L)
  prefix <- '{"type":"character","attributes":{},"value":['
  vector <- function(emit,field) {
    cursor <- DBI::dbSendQuery(selector,'SELECT cell_id,lineage_id,pseudotime FROM artifact_pseudotime WHERE artifact_id=? ORDER BY payload_ordinal;',params=list(artifact_id))
    on.exit(DBI::dbClearResult(cursor),add=TRUE)
prefix <- if(field=='value')'{"type":"double","attributes":{},"value":[' else '{"type":"character","attributes":{},"value":['
    emit(prefix);first <- TRUE;observed <- 0
    repeat {
      rows <- DBI::dbFetch(cursor,n=batch_rows)
      if(!nrow(rows))break
      values <- switch(field,cell_id=as.character(rows$cell_id),key=as.character(rows$lineage_id),value=as.numeric(rows$pseudotime))
      encoded <- enc2utf8(jsonlite::serializeJSON(values,digits=NA))
      stopifnot(startsWith(encoded,prefix),endsWith(encoded,']}'),nchar(encoded,type='bytes')<=budgets$partition_bytes)
      if(!first)emit(',')
      emit(substr(encoded,nchar(prefix)+1L,nchar(encoded)-2L))
      first <- FALSE;observed <- observed+nrow(rows)
    }
    emit(']}');stopifnot(observed==descriptor$rows)
  }
  prototype_physical_metadata_stream(con,artifact_id,budgets,descriptor,function(metadata_path) {
  hash <- scworkbench:::.wb_graph_token_hash(function(emit) {
    scworkbench:::.wb_graph_native_list_start(emit,fields)
    scworkbench:::.wb_graph_native_scalar(emit,'cell_vector_family');emit(',')
    vector(emit,'key');emit(',');vector(emit,'cell_id');emit(',');vector(emit,'value');emit(',')
    scworkbench:::.wb_graph_native_scalar(emit,header$value_type[[1L]])
    if(header$meta_present[[1L]]==1L) {emit(',');prototype_metadata_canonical_hash(metadata_path,budgets,external_emit=emit)}
    emit(']}')
  },budgets)
  list(sha256=hash,rows=descriptor$rows,batch_rows=batch_rows,metadata_bytes=as.numeric(descriptor$metadata_bytes))
  })
}
