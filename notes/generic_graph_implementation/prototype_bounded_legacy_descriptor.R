# Diagnostic only. Independently compare every streamed legacy row-order token
# and metadata byte against the physical payload; never accept a declared hash.
prototype_legacy_descriptor <- function(con,selector,artifact_id,budgets) {
  row <- DBI::dbGetQuery(con,"SELECT rowid FROM artifacts WHERE artifact_id=?;",params=list(artifact_id))
  stopifnot(nrow(row)==1L)
  header <- DBI::dbGetQuery(con,"SELECT kind,value_type,meta_present FROM artifact_object_payload_meta WHERE artifact_id=?;",params=list(artifact_id))
  stopifnot(nrow(header)==1L,header$kind=='cell_vector')
  closure <- scworkbench:::.wb_graph_object_closure(con,artifact_id,budgets)
  metadata <- scworkbench:::.wb_graph_object_metadata_hash(con,artifact_id,budgets)
  metadata_file <- tempfile('scwb_object_meta_descriptor_')
  on.exit(unlink(metadata_file),add=TRUE)
  sink <- file(metadata_file,'wb')
  on.exit(try(close(sink),silent=TRUE),add=TRUE)
  cursor <- DBI::dbSendQuery(selector,paste0('SELECT payload_ordinal,cell_id FROM artifact_labels ',
    'WHERE artifact_id=? ORDER BY payload_ordinal;'),params=list(artifact_id))
  on.exit(DBI::dbClearResult(cursor),add=TRUE)
  rows <- data.frame(); index <- 1L; count <- 0; current <- ''; fields <- list()
  row_open <- FALSE; row_array <- FALSE; descriptor <- FALSE; meta_bytes <- 0
  next_key <- function() {
    if(index>nrow(rows)) {rows <<- DBI::dbFetch(cursor,n=64L);index <<- 1L}
    stopifnot(nrow(rows)>0L,as.numeric(rows$payload_ordinal[[index]])==count)
    key <- scworkbench:::.wb_object_row_key_tokens(data.frame(cell_id=rows$cell_id[[index]],stringsAsFactors=FALSE))
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
  prototype_json_walk(con,as.character(row$rowid[[1L]]),'provenance_json','artifacts',callback,budgets)
  close(sink)
  stopifnot(descriptor,row_array,!row_open,index>nrow(rows),nrow(DBI::dbFetch(cursor,n=1L))==0L,
    fields$schema=='scworkbench.artifact.object-payload.v1',fields$kind==header$kind,
    identical(fields$value_type,header$value_type[[1L]]),identical(fields$meta_present,header$meta_present[[1L]]==1L),
    meta_bytes==as.numeric(metadata$bytes),identical(digest::digest(file=metadata_file,algo='sha256',serialize=FALSE),metadata$sha256))
  list(rows=count,metadata_bytes=meta_bytes,metadata_sha256=metadata$sha256,closure=closure)
}
