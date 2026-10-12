# Diagnostic canonical R.serializeJSON re-encoding. All strings/arrays stream.
# Unhandled R representations are decoded only after explicit byte/carrier
# admission; exceeding that admission is a resource error, never acceptance.
prototype_metadata_canonical_hash <- function(path,budgets) {
  # General old codec for a whole representation only after carrier admission.
  if(file.info(path)$size<=budgets$partition_bytes) {
    probe <- .Call("prototype_json_lexer_file_open",path,as.numeric(budgets$token_bytes))
    count <- 0
    tryCatch(repeat {
      token <- .Call("prototype_json_lexer_next",probe);count <- count+1
      if(4*file.info(path)$size+256*count>8*budgets$partition_bytes)
        scworkbench:::.wb_graph_error("GRAPH_RESOURCE_EXCEEDED","Metadata old-codec carriers exceed admission.")
      if(token$type=="end")break
    },finally=.Call("prototype_json_lexer_close",probe))
    input <- readBin(path,"raw",n=file.info(path)$size)
    canonical <- as.character(jsonlite::serializeJSON(jsonlite::unserializeJSON(rawToChar(input)),digits=NA))
    return(list(sha256=scworkbench:::.wb_graph_token_hash(function(emit)emit(canonical),budgets),
      descriptor=NULL,partition_bytes=budgets$partition_bytes,admitted_old_codec=TRUE))
  }
  pointer <- .Call("prototype_json_lexer_file_open",path,as.numeric(budgets$token_bytes))
  on.exit(.Call("prototype_json_lexer_close",pointer),add=TRUE)
  token <- .Call("prototype_json_lexer_next",pointer)
  advance <- function() token <<- .Call("prototype_json_lexer_next",pointer)
  invalid <- function(ok) if(!isTRUE(ok))scworkbench:::.wb_graph_error(
    "GRAPH_SOURCE_PAYLOAD_INVALID","Noncanonical R metadata representation.")
  admit <- function(ok) if(!isTRUE(ok))scworkbench:::.wb_graph_error(
    "GRAPH_RESOURCE_EXCEEDED","Metadata decode/carrier exceeds admitted partition.")
  expect <- function(value,emit) {
    invalid(token$type=="punctuation" && identical(token$value,value))
    emit(value);advance()
  }
  quote_part <- function(text) {
    encoded <- as.character(jsonlite::toJSON(text,auto_unbox=TRUE))
    substr(encoded,2L,nchar(encoded)-1L)
  }
  string <- function(emit,collect=FALSE,limit=budgets$partition_bytes) {
    invalid(token$type %in% c("string_part","string_end"))
    text <- "";bytes <- 0;emit('"')
    repeat {
      part <- token$value;final <- token$type=="string_end"
      if(collect) {
        bytes <- bytes+nchar(part,type="bytes");admit(bytes<=limit)
        text <- paste0(text,part)
      }
      emit(quote_part(part));advance()
      if(final)break
      invalid(token$type %in% c("string_part","string_end"))
    }
    emit('"');text
  }
  key <- function(name,emit) {
    observed <- string(emit,TRUE,256L);invalid(identical(observed,name));expect(":",emit)
  }
  generic <- function(emit,depth) {
    admit(depth<=min(256L,floor(budgets$partition_bytes/2048)))
    if(token$type %in% c("string_part","string_end"))return(string(emit))
    if(token$type=="scalar") {
      value <- tryCatch(jsonlite::fromJSON(token$value),error=function(e)NULL)
      invalid(!is.null(value) || identical(token$value,"null"))
      emit(as.character(jsonlite::toJSON(value,auto_unbox=TRUE,null="null",digits=NA)))
      advance();return(invisible(NULL))
    }
    invalid(token$type=="punctuation" && token$value %in% c("{","["))
    object <- token$value=="{";expect(token$value,emit);end <- if(object)"}" else "]"
    first <- TRUE
    while(!(token$type=="punctuation" && token$value==end)) {
      if(!first)expect(",",emit)
      if(object){string(emit);expect(":",emit)}
      generic(emit,depth+1L);first <- FALSE
    }
    expect(end,emit)
  }
  atomic <- function(type,emit,rank) {
    if(type=="character" && token$type %in% c("string_part","string_end")) {
      string(emit);return(list(value=NULL,missing=FALSE))
    }
    if(token$type %in% c("string_part","string_end"))value <- string(function(...)NULL,TRUE)
    else {
      invalid(token$type=="scalar")
      text <- token$value;advance()
      value <- tryCatch(jsonlite::fromJSON(text),error=function(e)NULL)
      invalid(!is.null(value) || identical(text,"null"))
      if(is.null(value))value <- NA
    }
    # list_to_vec first coerces every array element to one common R type.
    value <- suppressWarnings(switch(as.character(rank),
      `3`=as.character(value),`2`=as.double(value),`1`=as.integer(value),`0`=as.logical(value)))
    value <- suppressWarnings(switch(type,character=as.character(value),
      logical=as.logical(value),integer=as.integer(value),double=as.double(value)))
    encoded <- as.character(jsonlite::serializeJSON(value,digits=NA))
    prefix <- paste0('{"type":"',type,'","attributes":{},"value":[')
    invalid(startsWith(encoded,prefix) && endsWith(encoded,']}'))
    emit(substr(encoded,nchar(prefix)+1L,nchar(encoded)-2L))
    list(value=value,missing=is.na(value))
  }
  raw_string <- function(emit) {
    invalid(token$type %in% c("string_part","string_end"))
    emit('"');carry <- "";bytes <- 0;column <- 0L
    encode <- function(text) {
      invalid(grepl('^[A-Za-z0-9+/]*={0,2}$',text))
      value <- tryCatch(jsonlite::base64_dec(text),error=function(e)NULL)
      invalid(!is.null(value))
      canonical <- gsub("\n","",jsonlite::base64_enc(value),fixed=TRUE)
      while(nchar(canonical)>0L) {
        take <- min(72L-column,nchar(canonical))
        emit(quote_part(substr(canonical,1L,take)))
        canonical <- substring(canonical,take+1L);column <<- column+take
        if(column==72L) {emit(quote_part("\n"));column <<- 0L}
      }
      bytes <<- bytes+length(value)
    }
    repeat {
      carry <- paste0(carry,gsub("[\r\n\t ]","",token$value));final <- token$type=="string_end";advance()
      if(final) {encode(carry);break}
      size <- max(0L,4L*floor((nchar(carry)-4L)/4L))
      if(size>0L) {encode(substr(carry,1L,size));carry <- substring(carry,size+1L)}
      invalid(token$type %in% c("string_part","string_end"))
    }
    emit('"');list(type="raw",length=bytes,missing=FALSE)
  }
  scratch <- tempfile("scwb_graph_identity_metadata_keys_",fileext=".sqlite")
  keys <- DBI::dbConnect(RSQLite::SQLite(),scratch,cache_size=-64)
  on.exit({DBI::dbDisconnect(keys);unlink(c(scratch,paste0(scratch,c("-wal","-journal","-shm"))))},add=TRUE)
  DBI::dbExecute(keys,"PRAGMA temp_store=FILE;")
  DBI::dbExecute(keys,"CREATE TABLE attributes(object_id INTEGER,name TEXT,PRIMARY KEY(object_id,name));")
  DBI::dbExecute(keys,"CREATE TABLE vectors(start INTEGER PRIMARY KEY,rank INTEGER);")
  source("notes/generic_graph_implementation/prototype_bounded_json_file_walk.R",local=TRUE)
  frames <- list()
  rank_callback <- function(event,path,value) {
    n <- length(frames)
    direct <- n>0L && length(path)==length(frames[[n]]$path)+2L &&
      identical(head(path,-1L),c(frames[[n]]$path,"value"))
    if(direct && frames[[n]]$type %in% c("character","integer","logical","double")) {
      rank <- if(event=="string_start")3L else if(event=="scalar") {
        x <- jsonlite::fromJSON(value)
        if(is.character(x))3L else if(is.double(x))2L else if(is.integer(x))1L else 0L
      } else if(event=="open")4L else -1L
      frames[[n]]$rank <<- max(frames[[n]]$rank,rank)
    }
    if(event=="open" && value=="object") {
      frames[[n+1L]] <<- list(path=path,type="",rank=0L,text="",
        start=.Call("prototype_json_lexer_position",rank_pointer))
    }
    if(n>0L && identical(path,c(frames[[n]]$path,"type"))) {
      if(event=="string_part") {
        frames[[n]]$text <<- paste0(frames[[n]]$text,value)
        admit(nchar(frames[[n]]$text,type="bytes")<=64L)
      }
      if(event=="string_end")frames[[n]]$type <<- frames[[n]]$text
    }
    if(event=="close" && value=="object") {
      frame <- frames[[n]]
      if(frame$type %in% c("character","integer","logical","double")) {
        DBI::dbExecute(keys,"INSERT INTO vectors VALUES(?,?);",params=list(frame$start,frame$rank))
        scworkbench:::.wb_graph_spill_admit(budgets,scratch)
      }
      frames[[n]] <<- NULL
    }
  }
  # The walker uses its own pointer; expose its exact source byte position to
  # this closure at callbacks so the two passes join without retaining paths.
  rank_walk <- prototype_json_file_walk
  body(rank_walk) <- as.call(c(as.list(body(rank_walk))[1:2],
    list(quote(assign("rank_pointer",pointer,envir=environment(rank_callback)))),as.list(body(rank_walk))[-(1:2)]))
  rank_walk(path,rank_callback,budgets)
  frames <- list()
  object_id <- 0
  object <- function(emit,depth=1L,role="") {
    admit(depth<=min(256L,floor(budgets$partition_bytes/2048)))
    start <- .Call("prototype_json_lexer_position",pointer)
    vector <- DBI::dbGetQuery(keys,"SELECT rank FROM vectors WHERE start=?;",params=list(start))
    rank <- if(nrow(vector))vector$rank[[1L]] else 0L
    object_id <<- object_id+1;id <- object_id
    expect("{",emit);key("type",emit);type <- string(emit,TRUE,64L)
    if(type=="NULL") {expect("}",emit);return(list(type=type,length=0,missing=FALSE,attribute_count=0L))}
    if(rank>3L || !type %in% c("character","logical","integer","double","list","raw")) {
      pieces <- list(paste0('{"type":',as.character(jsonlite::toJSON(type,auto_unbox=TRUE))))
      size <- nchar(pieces[[1L]],type="bytes")
      collect <- function(text) {
        size <<- size+nchar(text,type="bytes")
        admit(size<=budgets$partition_bytes && size+1024*(length(pieces)+1L)<=8*budgets$partition_bytes)
        pieces[[length(pieces)+1L]] <<- text
      }
      while(!(token$type=="punctuation" && token$value=="}")) {
        expect(",",collect);string(collect);expect(":",collect);generic(collect,depth+1L)
      }
      expect("}",collect);text <- paste0(pieces,collapse="")
      decoded <- tryCatch(jsonlite::unserializeJSON(text),error=function(e)NULL)
      canonical <- tryCatch(as.character(jsonlite::serializeJSON(decoded,digits=NA)),error=function(e)NULL)
      invalid(!is.null(canonical) && identical(canonical,text))
      prefix <- pieces[[1L]];emit(substring(canonical,nchar(prefix)+1L))
      return(list(type=type,length=length(decoded),missing=FALSE,attribute_count=length(attributes(decoded))))
    }
    expect(",",emit);key("attributes",emit);expect("{",emit)
    attrs <- list();first <- TRUE;attribute_count <- 0;attribute_order <- character()
    while(!(token$type=="punctuation" && token$value=="}")) {
      if(!first)expect(",",emit)
      name <- string(emit,TRUE);expect(":",emit)
      duplicate <- tryCatch({DBI::dbExecute(keys,"INSERT INTO attributes VALUES(?,?);",params=list(id,name));FALSE},error=function(e)TRUE)
      invalid(!duplicate);scworkbench:::.wb_graph_spill_admit(budgets,scratch)
      attribute_count <- attribute_count+1
      attribute <- object(emit,depth+1L,name)
      invalid(attribute$type!="NULL")
      if(name %in% c("names","dim","dimnames","class","comment","tsp","row.names")){attrs[[name]] <- attribute;attribute_order <- c(attribute_order,name)}
      first <- FALSE
    }
    expect("}",emit);expect(",",emit);key("value",emit)
    length <- 0;missing <- FALSE;values <- list();children <- list()
    if(type=="raw") result <- raw_string(emit)
    else {
      expect("[",emit);first <- TRUE
      while(!(token$type=="punctuation" && token$value=="]")) {
        if(!first)expect(",",emit)
        value <- if(type=="list")object(emit,depth+1L) else atomic(type,emit,rank)
        length <- length+1;missing <- missing || isTRUE(value$missing)
        if(role %in% c("dim","tsp","row.names") && type %in% c("integer","double")) {
          admit(128*length<=budgets$partition_bytes);values[[length]] <- value$value
        }
        if(role=="dimnames" && type=="list") {
          admit(1024*length<=budgets$partition_bytes);children[[length]] <- value
        }
        first <- FALSE
      }
      expect("]",emit)
      result <- list(type=type,length=length,missing=missing,values=unlist(values,use.names=FALSE),children=children)
    }
    expect("}",emit)
    result$attribute_count <- attribute_count
    if(!is.null(attrs$names))admit(attrs$names$attribute_count==0L)
    if(!is.null(attrs$names))invalid(attrs$names$type=="character" && attrs$names$length==result$length)
    for(name in c("class","comment"))if(!is.null(attrs[[name]]))
      invalid(attrs[[name]]$type=="character" && attrs[[name]]$length>0)
    if(!is.null(attrs$dim)) {
      admit(attrs$dim$attribute_count==0L &&
        (!"names" %in% attribute_order || match("dim",attribute_order)<match("names",attribute_order)) &&
        (!"dimnames" %in% attribute_order || match("dim",attribute_order)<match("dimnames",attribute_order)))
      dims <- attrs$dim$values
      invalid(attrs$dim$type=="integer" && length(dims)>0 && !anyNA(dims) &&
        all(dims>=0) && prod(dims)==result$length)
    }
    if(!is.null(attrs$dimnames)) {
      invalid(!is.null(attrs$dim) && attrs$dimnames$type=="list" && attrs$dimnames$length==attrs$dim$length)
      for(i in seq_along(attrs$dim$values)) {
        child <- attrs$dimnames$children[[i]]
        admit(child$type=="NULL" || child$attribute_count==0L)
        invalid(child$type=="NULL" || (child$type=="character" && child$length==attrs$dim$values[[i]]))
      }
    }
    if(!is.null(attrs$tsp)) {
      tsp <- attrs$tsp$values;n <- if(!is.null(attrs$dim))attrs$dim$values[[1L]] else result$length
      invalid(attrs$tsp$type=="double" && length(tsp)==3L && all(is.finite(tsp)) &&
        tsp[[3L]]>0 && abs((tsp[[2L]]-tsp[[1L]])*tsp[[3L]]+1-n)<1e-5)
    }
    DBI::dbExecute(keys,"DELETE FROM attributes WHERE object_id=?;",params=list(id))
    result
  }
  descriptor <- NULL
  sha <- scworkbench:::.wb_graph_token_hash(function(emit) {
    descriptor <<- object(emit);invalid(token$type=="end")
  },budgets)
  list(sha256=sha,descriptor=descriptor,partition_bytes=budgets$partition_bytes)
}
