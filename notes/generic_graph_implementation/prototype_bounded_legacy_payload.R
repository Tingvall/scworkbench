# Diagnostic only: preserve the existing R.serializeJSON preimage, including
# physical payload order and the independently verified legacy descriptor.
prototype_legacy_cell_vector_hash <- function(con,selector,artifact_id,budgets,descriptor) {
  stopifnot(descriptor$rows>0)
  header <- DBI::dbGetQuery(con,'SELECT value_type,meta_present FROM artifact_object_payload_meta WHERE artifact_id=?;',params=list(artifact_id))
  stopifnot(nrow(header)==1L)
  # This original-source prototype admits the actual183-byte metadata before
  # collection. Arbitrary large metadata canonicalization is still unresolved.
  stopifnot(as.numeric(descriptor$metadata_bytes)<=budgets$partition_bytes)
  chunks <- DBI::dbGetQuery(con,'SELECT chunk FROM artifact_object_metadata_chunks WHERE artifact_id=? ORDER BY chunk_ordinal;',params=list(artifact_id))
  bytes <- do.call(c,chunks$chunk)
  stopifnot(length(bytes)==as.numeric(descriptor$metadata_bytes))
  metadata <- if(length(bytes))rawToChar(bytes) else ''
  if(header$meta_present[[1L]]==1L) stopifnot(identical(
    as.character(jsonlite::serializeJSON(jsonlite::unserializeJSON(metadata),digits=NA)),metadata))
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
  hash <- scworkbench:::.wb_graph_token_hash(function(emit) {
    scworkbench:::.wb_graph_native_list_start(emit,fields)
    scworkbench:::.wb_graph_native_scalar(emit,'cell_vector');emit(',')
    vector(emit,'cell_id');emit(',');vector(emit,'value');emit(',')
    scworkbench:::.wb_graph_native_scalar(emit,header$value_type[[1L]])
    if(header$meta_present[[1L]]==1L) {emit(',');emit(metadata)}
    emit(']}')
  },budgets)
  list(sha256=hash,rows=descriptor$rows,batch_rows=batch_rows,metadata_bytes=length(bytes))
}
