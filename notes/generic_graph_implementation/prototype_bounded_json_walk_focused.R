args <- commandArgs(TRUE)
.libPaths(c(file.path(args[[1L]],"library"),.libPaths()))
library(scworkbench)
scworkbench:::.wb_matrix_native_byte_api_initialize()
dyn.load("/tmp/scwb-bounded-json-lexer-prototype-291.so")
initializer <- DBI::dbConnect(RSQLite::SQLite(),":memory:",default.extensions=FALSE)
DBI::dbGetQuery(initializer,"SELECT load_extension(?,?);",params=list(
  "/tmp/scwb-bounded-json-lexer-prototype-291.so","sqlite3_scwbjsonprototype_init"))
DBI::dbDisconnect(initializer)
source("notes/generic_graph_implementation/prototype_bounded_json_walk.R")
path <- tempfile(fileext=".sqlite");con <- DBI::dbConnect(RSQLite::SQLite(),path)
DBI::dbExecute(con,"CREATE TABLE payload(value TEXT);");DBI::dbExecute(con,"INSERT INTO payload VALUES('');")
policy <- scworkbench:::.wb_graph_budgets(list(memory_bytes="8388608",sqlite_cache_kib=2048L,
  partition_bytes=262144L,partition_rows=256L,collect_bytes=4194304L))
walk <- function(text) {
  DBI::dbExecute(con,"UPDATE payload SET value=?;",params=list(text))
  leaves <- list();strings <- list();max_bytes <- 0L
  callback <- function(event,path,value) {
    if(anyNA(path))return(invisible(NULL))
    key <- paste(path,collapse="/")
    if(event=="string_start")strings[[key]] <<- ""
    if(event=="string_part") {strings[[key]] <<- paste0(strings[[key]],value);max_bytes <<- max(max_bytes,nchar(value,type="bytes"))}
    if(event=="string_end")leaves[[key]] <<- strings[[key]]
    if(event=="scalar")leaves[key] <<- list(jsonlite::fromJSON(value))
  }
  prototype_json_walk(con,"1","value","payload",callback,policy)
  list(leaves=leaves,max_bytes=max_bytes)
}
for(text in c('null','true','0','-2.25','1e-10','{}','[]',
  '{"a":["é🙂",null,false,2.25],"b":{"c":"quote\\""}}',
  as.character(jsonlite::toJSON(list(x=strrep("é🙂\n",5000L)),auto_unbox=TRUE)))) {
  observed <- walk(text)
  expected <- list()
  collect <- function(value,path=character()) {
    if(is.list(value) && length(value)) {
      keys <- if(is.null(names(value)))as.character(seq_along(value)-1L) else names(value)
      for(i in seq_along(value))collect(value[[i]],c(path,keys[[i]]))
    } else if(!is.list(value) || is.null(value)) expected[paste(path,collapse="/")] <<- list(value)
  }
  collect(jsonlite::fromJSON(text,simplifyVector=FALSE))
  stopifnot(identical(observed$leaves,expected),observed$max_bytes<=4096L)
}
for(text in c('{"x":1,}','["a" "b"]','{} true','[1,]','[+1]','[01]','[1.]','[1e]','[.1]','[-]','[true:false]','{"x":}')) {
  error <- tryCatch(walk(text),error=identity);stopifnot(inherits(error,"error"))
}
DBI::dbDisconnect(con);unlink(c(path,paste0(path,"-wal"),paste0(path,"-shm")))
cat("BOUNDED_JSON_WALK_PROTOTYPE small_jsonlite_leaf_differential=9 invalid_structure_number=12 PASS prototype_only=TRUE\n")
