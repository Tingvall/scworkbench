
.wb_getter_sqlite_json_walk <- function(con,rowid,column,table,callback,budgets) {
  .wb_graph_fd_metadata_reservation(budgets)
  observer <- .wb_matrix_native_byte_observer(con)
  if(is.null(observer))return(.wb_getter_memory_json_walk(con,rowid,column,table,callback,budgets))
  on.exit(observer$close(),add=TRUE)
  finished <- FALSE
  finish_snapshot <- function()if(!finished){finished <<- TRUE;observer$finish()}
  size <- observer$column(rowid,column,table)
  if(is.null(size)){finish_snapshot();return(invisible(NULL))}
  .wb_graph_require(attr(size,"wb_sqlite_type")=="text","GRAPH_SOURCE_PAYLOAD_INVALID","JSON source is not TEXT.")
  pointer <- .Call(C_scwb_graph_json_open,environment(observer$read)$pointer)
  on.exit(.Call(C_scwb_graph_json_close,pointer),add=TRUE)
  read <- function()tryCatch(.Call(C_scwb_graph_json_next,pointer),error=function(error) {
    finish_snapshot()
    if(identical(conditionMessage(error),"Invalid JSON lexical input."))
      stop(structure(list(message=conditionMessage(error),call=NULL),class=c("scwb_json_syntax","error","condition")))
    if(startsWith(conditionMessage(error),"GRAPH_RESOURCE_EXCEEDED:"))
      .wb_graph_error("GRAPH_RESOURCE_EXCEEDED",conditionMessage(error))
    stop(error)
  })
  token <- read()
  advance <- function() token <<- read()
  require <- function(ok) if(!isTRUE(ok))stop(structure(list(message="Invalid bounded JSON structure.",call=NULL),class=c("scwb_json_syntax","error","condition")))
  expect <- function(value) {require(token$type=="punctuation" && identical(token$value,value));advance()}
  maximum_depth <- max(1L,min(256L,floor(budgets$partition_bytes/2048)))
  string <- function(path,key=FALSE) {
    require(token$type %in% c("string_part","string_end"))
    value <- "";size <- 0L;known <- TRUE
    callback(if(key)"key_start" else "string_start",path,NULL)
    repeat {
      part <- token$value;final <- token$type=="string_end"
      if(key) {
        size <- size+nchar(part,type="bytes")
        if(size<=256L) value <- paste0(value,part) else known <- FALSE
        callback("key_part",path,part)
      } else callback("string_part",path,part)
      advance()
      if(final)break
      require(token$type %in% c("string_part","string_end"))
    }
    callback(if(key)"key_end" else "string_end",path,if(key && known)value else NULL)
    if(key) if(known)value else NA_character_ else invisible(NULL)
  }
  parse_value <- function(path,depth) {
    .wb_graph_require(depth<=maximum_depth,"GRAPH_RESOURCE_EXCEEDED","JSON grammar stack exceeds partition admission.")
    if(token$type %in% c("string_part","string_end"))return(string(path))
    if(token$type=="scalar") {
      require(token$value %in% c("true","false","null") ||
        grepl('^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$',token$value))
      callback("scalar",path,token$value);advance();return(invisible(NULL))
    }
    require(token$type=="punctuation" && token$value %in% c("{","["))
    type <- if(token$value=="{")"object" else "array"
    finish <- if(type=="object")"}" else "]"
    callback("open",path,type);advance()
    if(token$type=="punctuation" && token$value==finish) {
      callback("close",path,type);advance();return(invisible(NULL))
    }
    index <- 0
    repeat {
      if(type=="object") {key <- string(c(path,NA_character_),key=TRUE);expect(":")} else key <- sprintf("%.0f",index)
      parse_value(c(path,key),depth+1L)
      index <- index+1
      if(token$type=="punctuation" && token$value==finish)break
      expect(",")
    }
    callback("close",path,type);advance()
    invisible(NULL)
  }
  tryCatch({parse_value(character(),1L);require(token$type=="end")},error=function(error) {finish_snapshot();stop(error)})
  finish_snapshot()
  invisible(size)
}


.wb_getter_file_json_walk <- function(con,callback,budgets,opened=NULL) {
  .wb_graph_fd_metadata_reservation(budgets)
  pointer <- .Call(C_scwb_graph_json_file_open,con,as.numeric(budgets$token_bytes))
  on.exit(.Call(C_scwb_graph_json_close,pointer),add=TRUE)
  if(!is.null(opened))opened(pointer)
  read <- function()tryCatch(.Call(C_scwb_graph_json_next,pointer),error=function(error) {
    message <- conditionMessage(error)
    if(identical(message,"Invalid JSON lexical input."))
      stop(structure(list(message=message,call=NULL),class=c("scwb_json_syntax","error","condition")))
    code <- if(startsWith(message,"GRAPH_RESOURCE_"))sub(":.*","",message) else
      if(startsWith(message,"GRAPH_SOURCE_PAYLOAD_INVALID:"))"GRAPH_SOURCE_PAYLOAD_INVALID" else
      "GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE"
    .wb_graph_error(code,message)
  })
  token <- read()
  advance <- function() token <<- read()
  require <- function(ok) if(!isTRUE(ok))stop(structure(list(message="Invalid bounded JSON structure.",call=NULL),class=c("scwb_json_syntax","error","condition")))
  expect <- function(value) {require(token$type=="punctuation" && identical(token$value,value));advance()}
  maximum_depth <- max(1L,min(256L,floor(budgets$partition_bytes/2048)))
  string <- function(path,key=FALSE) {
    require(token$type %in% c("string_part","string_end"))
    value <- "";size <- 0L;known <- TRUE
    callback(if(key)"key_start" else "string_start",path,NULL)
    repeat {
      part <- token$value;final <- token$type=="string_end"
      if(key) {
        size <- size+nchar(part,type="bytes")
        if(size<=256L) value <- paste0(value,part) else known <- FALSE
        callback("key_part",path,part)
      } else callback("string_part",path,part)
      advance()
      if(final)break
      require(token$type %in% c("string_part","string_end"))
    }
    callback(if(key)"key_end" else "string_end",path,if(key && known)value else NULL)
    if(key) if(known)value else NA_character_ else invisible(NULL)
  }
  parse_value <- function(path,depth) {
    .wb_graph_require(depth<=maximum_depth,"GRAPH_RESOURCE_EXCEEDED","JSON grammar stack exceeds partition admission.")
    if(token$type %in% c("string_part","string_end"))return(string(path))
    if(token$type=="scalar") {
      require(token$value %in% c("true","false","null") ||
        grepl('^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$',token$value))
      callback("scalar",path,token$value);advance();return(invisible(NULL))
    }
    require(token$type=="punctuation" && token$value %in% c("{","["))
    type <- if(token$value=="{")"object" else "array"
    finish <- if(type=="object")"}" else "]"
    callback("open",path,type);advance()
    if(token$type=="punctuation" && token$value==finish) {
      callback("close",path,type);advance();return(invisible(NULL))
    }
    index <- 0
    repeat {
      if(type=="object") {key <- string(c(path,NA_character_),key=TRUE);expect(":")} else key <- sprintf("%.0f",index)
      parse_value(c(path,key),depth+1L)
      index <- index+1
      if(token$type=="punctuation" && token$value==finish)break
      expect(",")
    }
    callback("close",path,type);advance()
    invisible(NULL)
  }
  parse_value(character(),1L)
  require(token$type=="end")
  invisible(TRUE)
}

# Fileless diagnostic SQLite sources admit the entire TEXT before selection.
# They cannot bypass the physical file-backed authority required by graph sources.
.wb_getter_memory_json_walk <- function(con,rowid,column,table,callback,budgets) {
  ident <- function(x)as.character(DBI::dbQuoteIdentifier(con,x))
  from <- paste0(" FROM ",ident(table)," WHERE rowid=CAST(? AS INTEGER)")
  measure <- DBI::dbGetQuery(con,paste0("SELECT typeof(",ident(column),") type,octet_length(",ident(column),") bytes",from),params=list(rowid))
  .wb_graph_require(nrow(measure)==1L && measure$type[[1L]] %in% c("null","text"),
    "GRAPH_SOURCE_PAYLOAD_INVALID","JSON source is absent or not TEXT.")
  if(measure$type[[1L]]=="null")return(invisible(NULL))
  .wb_graph_require(measure$bytes[[1L]]<=budgets$partition_bytes,"GRAPH_RESOURCE_EXCEEDED",
    "Fileless SQLite JSON requires admitted whole TEXT decoding.")
  select <- paste0("SELECT ",ident(column)," value",from," AND typeof(",ident(column),")='text' AND octet_length(",ident(column),")<=?;")
  query <- function()DBI::dbGetQuery(con,select,params=list(rowid,budgets$partition_bytes))
  row <- query()
  .wb_graph_require(nrow(row)==1L,"GRAPH_SOURCE_PAYLOAD_INVALID","Fileless JSON changed before decoding.")
  path <- tempfile("scwb_object_meta_fileless_json_");on.exit(unlink(path),add=TRUE)
  writeBin(charToRaw(enc2utf8(row$value[[1L]])),path)
  guard <- file(path,"rb");on.exit(close(guard),add=TRUE)
  .wb_graph_spill_admit(budgets,path)
  validate <- function() {
    fresh <- query()
    .wb_graph_require(nrow(fresh)==1L && identical(fresh$value,row$value),
      "GRAPH_SOURCE_PAYLOAD_INVALID","Fileless JSON changed during observation.")
  }
  result <- tryCatch(.wb_getter_file_json_walk(path,callback,budgets),error=function(error){validate();stop(error)})
  validate();result
}
