
prototype_json_walk <- function(con,rowid,column,table,callback,budgets) {
  observer <- scworkbench:::.wb_matrix_native_byte_observer(con)
  on.exit(observer$close(),add=TRUE)
  finished <- FALSE
  finish_snapshot <- function()if(!finished){finished <<- TRUE;observer$finish()}
  size <- observer$column(rowid,column,table)
  stopifnot(!is.null(size),attr(size,"wb_sqlite_type")=="text")
  pointer <- .Call("prototype_json_lexer_open",environment(observer$read)$pointer)
  on.exit(.Call("prototype_json_lexer_close",pointer),add=TRUE)
  read <- function()tryCatch(.Call("prototype_json_lexer_next",pointer),error=function(error) {
    finish_snapshot()
    if(identical(conditionMessage(error),"Invalid JSON lexical input."))
      stop(structure(list(message=conditionMessage(error),call=NULL),class=c("scwb_json_syntax","error","condition")))
    if(startsWith(conditionMessage(error),"GRAPH_RESOURCE_EXCEEDED:"))
      scworkbench:::.wb_graph_error("GRAPH_RESOURCE_EXCEEDED",conditionMessage(error))
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
    scworkbench:::.wb_graph_require(depth<=maximum_depth,"GRAPH_RESOURCE_EXCEEDED","JSON grammar stack exceeds partition admission.")
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
