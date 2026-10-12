# Diagnostic selective projection. Walk/validate the complete raw JSON, but
# collect only admitted reference-bearing subtrees before invoking the existing
# recursive reference semantics. Huge primitive row_order strings are ignored.
prototype_provenance_refs <- function(con,rowid,budgets) {
  targets <- list(c('parent_artifacts'),c('inputs','provenance_refs'))
  selected <- list();active <- NULL;pieces <- character();bytes <- 0;frames <- list()
  input_starts <- 0L;accept_input <- FALSE
  append <- function(text) {
    bytes <<- bytes+nchar(text,type='bytes')
    stopifnot(bytes<=budgets$partition_bytes,
      bytes+1024*(length(pieces)+1L)<=8*budgets$partition_bytes)
    pieces[[length(pieces)+1L]] <<- text
  }
  before_value <- function(path) {
    if(!length(frames))return(invisible(NULL))
    n <- length(frames);frame <- frames[[n]]
    if(!frame$first)append(',')
    if(frame$type=='object') {
      append(as.character(jsonlite::toJSON(tail(path,1L),auto_unbox=TRUE)));append(':')
    }
    frames[[n]]$first <<- FALSE
  }
  finish <- function() {
    key <- paste(active,collapse='/')
    # jsonlite accepts duplicate fields; its old $ lookup selects the first.
    if(is.null(selected[[key]]))selected[[key]] <<- paste0(pieces,collapse='')
    active <<- NULL;pieces <<- character();bytes <<- 0;frames <<- list()
  }
  callback <- function(event,path,value) {
    if(event %in% c('key_start','key_part','key_end')) {
      if(!is.null(active) && event=='key_end')stopifnot(!is.null(value))
      return(invisible(NULL))
    }
    if(identical(path,c('inputs')) && event %in% c('open','string_start','scalar')) {
      input_starts <<- input_starts+1L;accept_input <<- input_starts==1L
    }
    if(is.null(active)) {
      if(identical(path,c('inputs','provenance_refs')) && !accept_input)return(invisible(NULL))
      if(!any(vapply(targets,function(target)identical(path,target),logical(1))) ||
          !(event %in% c('open','string_start','scalar')))return(invisible(NULL))
      active <<- path
    }
    stopifnot(!anyNA(path),length(path)>=length(active),identical(head(path,length(active)),active))
    if(event %in% c('open','string_start','scalar'))before_value(path)
    if(event=='open') {append(if(value=='object')'{' else '[');frames[[length(frames)+1L]] <<- list(type=value,first=TRUE)}
    if(event=='close') {append(if(value=='object')'}' else ']');frames[[length(frames)]] <<- NULL}
    if(event=='scalar')append(value)
    if(event=='string_start')append('"')
    if(event=='string_part') {
      encoded <- as.character(jsonlite::toJSON(value,auto_unbox=TRUE))
      append(substr(encoded,2L,nchar(encoded)-1L))
    }
    if(event=='string_end')append('"')
    if(identical(path,active) && event %in% c('close','string_end','scalar'))finish()
    invisible(NULL)
  }
  prototype_json_walk(con,rowid,'provenance_json','artifacts',callback,budgets)
  stopifnot(is.null(active))
  # Preserve old JSON parsing and recursive reference order/types exactly.
  text <- paste0('{"parent_artifacts":',selected[['parent_artifacts']] %||% 'null',
    ',"inputs":{"provenance_refs":',selected[['inputs/provenance_refs']] %||% 'null','}}')
  scworkbench:::.wb_art_refs_from_prov_json(text)
}
