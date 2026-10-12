# Private getter. Independently compare every streamed legacy row-order token
# and metadata byte against the physical payload; never accept a declared hash.
.wb_getter_legacy_object_descriptor <- function(con,selector,artifact_id,budgets) {
  row <- DBI::dbGetQuery(con,"SELECT rowid FROM artifacts WHERE artifact_id=?;",params=list(artifact_id))
  stopifnot(nrow(row)==1L)
  header <- DBI::dbGetQuery(con,"SELECT kind,value_type,meta_present FROM artifact_object_payload_meta WHERE artifact_id=?;",params=list(artifact_id))
  stopifnot(nrow(header)==1L,header$kind %in% c('cell_vector','cell_vector_family'))
  kind <- header$kind[[1L]]
  table <- if(kind=='cell_vector')'artifact_labels' else 'artifact_pseudotime'
  closure <- .wb_graph_object_closure(con,artifact_id,budgets)
  metadata <- .wb_graph_object_metadata_hash(con,artifact_id,budgets)
  metadata_file <- tempfile('scwb_object_meta_descriptor_')
  on.exit(unlink(metadata_file),add=TRUE)
  sink <- file(metadata_file,'wb')
  on.exit(try(close(sink),silent=TRUE),add=TRUE)
  cursor <- DBI::dbSendQuery(selector,paste0('SELECT payload_ordinal,cell_id',
    if(kind=='cell_vector_family')',lineage_id' else '', ' FROM ',table,' ',
    'WHERE artifact_id=? ORDER BY payload_ordinal;'),params=list(artifact_id))
  on.exit(DBI::dbClearResult(cursor),add=TRUE)
  rows <- data.frame(); index <- 1L; count <- 0; current <- ''; fields <- list()
  row_open <- FALSE; row_array <- FALSE; descriptor <- FALSE; meta_bytes <- 0
  next_key <- function() {
    if(index>nrow(rows)) {rows <<- DBI::dbFetch(cursor,n=64L);index <<- 1L}
    stopifnot(nrow(rows)>0L,as.numeric(rows$payload_ordinal[[index]])==count)
    key <- .wb_object_row_key_tokens(if(kind=='cell_vector')
      data.frame(cell_id=rows$cell_id[[index]],stringsAsFactors=FALSE) else
      data.frame(key=rows$lineage_id[[index]],cell_id=rows$cell_id[[index]],stringsAsFactors=FALSE))
    index <<- index+1L; count <<- count+1
    key[[1L]]
  }
  callback <- function(event,path,value) {
    if(anyNA(path) || !length(path) || path[[1L]]!='primitive_payload')return(invisible(NULL))
    if(length(path)==1L) {
      if(event=='open') {stopifnot(!descriptor,value=='object');descriptor <<- TRUE}
      return(invisible(NULL))
    }
    name <- path[[2L]]
    if(name=='row_order') {
      if(length(path)==2L) {
        if(event=='open') {stopifnot(!row_array,value=='array');row_array <<- TRUE}
      } else {
        stopifnot(length(path)==3L,as.numeric(path[[3L]])==count)
        if(event=='string_start') {stopifnot(!row_open);row_open <<- TRUE;current <<- ''}
        if(event=='string_part') {
          current <<- paste0(current,value)
          stopifnot(nchar(current,type='bytes')<=budgets$partition_bytes)
        }
        if(event=='string_end') {stopifnot(row_open,identical(current,next_key()));row_open <<- FALSE;current <<- ''}
        stopifnot(event %in% c('string_start','string_part','string_end'))
      }
      return(invisible(NULL))
    }
    if(name=='meta_r_json' && length(path)==2L) {
      if(event=='string_start')stopifnot(is.null(fields[[name]]))
      if(event=='string_part') {
        bytes <- charToRaw(enc2utf8(value));writeBin(bytes,sink)
        meta_bytes <<- meta_bytes+length(bytes)
        stopifnot(meta_bytes<=as.numeric(budgets$token_bytes))
      }
      if(event=='string_end')fields[[name]] <<- TRUE
      stopifnot(event %in% c('string_start','string_part','string_end'))
      return(invisible(NULL))
    }
    if(name %in% c('schema','kind','value_type','meta_present') && length(path)==2L) {
      if(event=='string_start') {stopifnot(is.null(fields[[name]]));current <<- ''}
      if(event=='string_part') {current <<- paste0(current,value);stopifnot(nchar(current,type='bytes')<=1024L)}
      if(event=='string_end') {fields[[name]] <<- current;current <<- ''}
      if(event=='scalar') {stopifnot(name=='meta_present',is.null(fields[[name]]),value %in% c('true','false'));fields[[name]] <<- value=='true'}
      stopifnot(event %in% c('string_start','string_part','string_end','scalar'))
    }
    invisible(NULL)
  }
  .wb_getter_sqlite_json_walk(con,as.character(row$rowid[[1L]]),'provenance_json','artifacts',callback,budgets)
  close(sink)
  stopifnot(descriptor,row_array,!row_open,index>nrow(rows),nrow(DBI::dbFetch(cursor,n=1L))==0L,
    fields$schema=='scworkbench.artifact.object-payload.v1',fields$kind==header$kind,
    identical(fields$value_type,header$value_type[[1L]]),identical(fields$meta_present,header$meta_present[[1L]]==1L),
    meta_bytes==as.numeric(metadata$bytes),identical(digest::digest(file=metadata_file,algo='sha256',serialize=FALSE),metadata$sha256))
  list(rows=count,metadata_bytes=meta_bytes,metadata_sha256=metadata$sha256,closure=closure)
}

# Private getter: preserve the existing R.serializeJSON preimage, including
# physical payload order and the independently verified legacy descriptor.
.wb_getter_legacy_cell_vector_hash <- function(con,selector,artifact_id,budgets,descriptor) {
  header <- DBI::dbGetQuery(con,'SELECT value_type,meta_present FROM artifact_object_payload_meta WHERE artifact_id=?;',params=list(artifact_id))
  stopifnot(nrow(header)==1L)
  count <- DBI::dbGetQuery(selector,'SELECT COUNT(*) n,MAX(octet_length(cell_id)+octet_length(label)) bytes FROM artifact_labels WHERE artifact_id=?;',params=list(artifact_id))
  stopifnot(count$n[[1L]]==descriptor$rows)
  maximum_bytes <- if(is.na(count$bytes[[1L]]))0 else count$bytes[[1L]]
  batch_rows <- max(1L,min(64L,budgets$partition_rows,floor(budgets$partition_bytes/(6*maximum_bytes+2048))))
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
  .wb_getter_physical_metadata_stream(con,artifact_id,budgets,descriptor,function(metadata_path) {
  hash <- .wb_graph_token_hash(function(emit) {
    .wb_graph_native_list_start(emit,fields)
    .wb_graph_native_scalar(emit,'cell_vector');emit(',')
    vector(emit,'cell_id');emit(',');vector(emit,'value');emit(',')
    .wb_graph_native_scalar(emit,header$value_type[[1L]])
    if(header$meta_present[[1L]]==1L) {emit(',');.wb_getter_metadata_canonical_hash(metadata_path,budgets,external_emit=emit)}
    emit(']}')
  },budgets)
  list(sha256=hash,rows=descriptor$rows,batch_rows=batch_rows,metadata_bytes=as.numeric(descriptor$metadata_bytes))
  })
}

# Private getter: preserve the existing R.serializeJSON preimage, including
# physical payload order and the independently verified legacy descriptor.
.wb_getter_legacy_cell_family_hash <- function(con,selector,artifact_id,budgets,descriptor) {
  header <- DBI::dbGetQuery(con,'SELECT value_type,meta_present FROM artifact_object_payload_meta WHERE artifact_id=?;',params=list(artifact_id))
  stopifnot(nrow(header)==1L)
  count <- DBI::dbGetQuery(selector,'SELECT COUNT(*) n,MAX(octet_length(cell_id)+octet_length(lineage_id)) bytes FROM artifact_pseudotime WHERE artifact_id=?;',params=list(artifact_id))
  stopifnot(count$n[[1L]]==descriptor$rows)
  maximum_bytes <- if(is.na(count$bytes[[1L]]))0 else count$bytes[[1L]]
  batch_rows <- max(1L,min(64L,budgets$partition_rows,floor(budgets$partition_bytes/(6*maximum_bytes+2048))))
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
  .wb_getter_physical_metadata_stream(con,artifact_id,budgets,descriptor,function(metadata_path) {
  hash <- .wb_graph_token_hash(function(emit) {
    .wb_graph_native_list_start(emit,fields)
    .wb_graph_native_scalar(emit,'cell_vector_family');emit(',')
    vector(emit,'key');emit(',');vector(emit,'cell_id');emit(',');vector(emit,'value');emit(',')
    .wb_graph_native_scalar(emit,header$value_type[[1L]])
    if(header$meta_present[[1L]]==1L) {emit(',');.wb_getter_metadata_canonical_hash(metadata_path,budgets,external_emit=emit)}
    emit(']}')
  },budgets)
  list(sha256=hash,rows=descriptor$rows,batch_rows=batch_rows,metadata_bytes=as.numeric(descriptor$metadata_bytes))
  })
}


# Recompute the existing legacy getter preimage under the active graph policy.
# No declared content digest, new anchor, or alternative identity is accepted.
.wb_getter_legacy_object_identity_work <- function(bundle,id,budgets=.wb_graph_effective_budgets(bundle$con)) {
  con <- bundle$con
  budgets <- .wb_graph_effective_budgets(con,budgets)
  kind <- DBI::dbGetQuery(con,"SELECT m.kind,a.type FROM artifact_object_payload_meta m JOIN artifacts a ON a.artifact_id=m.artifact_id WHERE m.artifact_id=?;",params=list(id))
  .wb_graph_require(nrow(kind)==1L && identical(kind$kind,kind$type),"GRAPH_SOURCE_PAYLOAD_INVALID","Artifact and physical payload kinds disagree.")
  database <- DBI::dbGetQuery(con,"PRAGMA database_list;")
  path <- database$file[database$name=="main"][[1L]]
  .wb_graph_require(nzchar(path),"GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE",
    "Bounded legacy descriptor verification requires file-backed source storage.")
  selector <- DBI::dbConnect(RSQLite::SQLite(),path,flags=RSQLite::SQLITE_RO,cache_size=-64)
  on.exit(if(!is.null(selector))DBI::dbDisconnect(selector),add=TRUE)
  DBI::dbExecute(selector,"PRAGMA temp_store=FILE;")
  descriptor <- .wb_getter_legacy_object_descriptor(con,selector,id,budgets)
  DBI::dbDisconnect(selector);selector <- NULL
  .wb_graph_storage_fault("legacy_object_payload_start",list(con=con,budgets=budgets,selector_closed=TRUE))
  getter <- if(kind$kind[[1L]]=="cell_vector") .wb_getter_legacy_cell_vector_hash else .wb_getter_legacy_cell_family_hash
  # The selector is gone: main-con rows + native64 + metadata-keys64 reuse the
  # existing128KiB auxiliary reservation; no third64KiB cache can coexist.
  payload <- getter(con,con,id,budgets,descriptor)
  list(content_sha256=payload$sha256,
    content_identity_scheme=unname(.wb_content_identity_schemes()[["object"]]))
}

.wb_getter_legacy_object_identity <- function(bundle,id,budgets=.wb_graph_effective_budgets(bundle$con)) {
  tryCatch(.wb_getter_legacy_object_identity_work(bundle,id,budgets),error=function(error) {
    if(!is.null(error$code))stop(error)
    .wb_graph_error("GRAPH_SOURCE_PAYLOAD_INVALID",conditionMessage(error))
  })
}
