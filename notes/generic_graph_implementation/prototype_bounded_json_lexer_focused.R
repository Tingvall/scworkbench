args <- commandArgs(TRUE)
.libPaths(c(file.path(args[[1L]],"library"),.libPaths()))
library(scworkbench)
stopifnot(exists("C_scwb_graph_bytes_api_ready",asNamespace("scworkbench")))
scworkbench:::.wb_matrix_native_byte_api_initialize()
dyn.load("/tmp/scwb-bounded-json-lexer-prototype-291.so")
initializer <- DBI::dbConnect(RSQLite::SQLite(),":memory:",default.extensions=FALSE)
DBI::dbGetQuery(initializer,"SELECT load_extension(?,?);",params=list(
  "/tmp/scwb-bounded-json-lexer-prototype-291.so","sqlite3_scwbjsonprototype_init"))
DBI::dbDisconnect(initializer)
path <- tempfile(fileext=".sqlite");con <- DBI::dbConnect(RSQLite::SQLite(),path)
on.exit <- NULL
DBI::dbExecute(con,"CREATE TABLE payload(value TEXT);")
DBI::dbExecute(con,"INSERT INTO payload VALUES('');")
lex <- function(text=NULL,sql=NULL) {
  if(is.null(sql)) DBI::dbExecute(con,"UPDATE payload SET value=?;",params=list(text)) else DBI::dbExecute(con,sql)
  observer <- scworkbench:::.wb_matrix_native_byte_observer(con)
  on.exit(observer$close(),add=TRUE)
  observer$column("1","value","payload")
  pointer <- .Call("prototype_json_lexer_open",environment(observer$read)$pointer)
  result <- list()
  repeat {
    token <- .Call("prototype_json_lexer_next",pointer)
    stopifnot(nchar(token$value,type="bytes")<=4096L)
    result[[length(result)+1L]] <- token
    if(token$type=="end")break
  }
  observer$finish()
  result
}
for (text in c('""','"é🙂\\n\\t\\b\\f\\r\\/\\\\\\""','"\\uD83D\\uDE42"',
  as.character(jsonlite::toJSON(strrep("é🙂\n",5000L),auto_unbox=TRUE)))) {
  parts <- lex(text)
  actual <- paste(vapply(Filter(function(x)x$type %in% c("string_part","string_end"),parts),`[[`,character(1),"value"),collapse="")
  stopifnot(identical(enc2utf8(actual),enc2utf8(jsonlite::fromJSON(text))),tail(parts,1L)[[1L]]$type=="end")
}
for(text in c('"\\uD800"','"\\uDC00"','"\\uD800\\u0041"','"\\u0000"','"bad\\x"','"unterminated','"literal\nline"')) {
  error <- tryCatch(lex(text),error=identity);stopifnot(inherits(error,"error"))
}
for(hex in c("22ff22","22c08022","22eda08022","22f490808022","220022")) {
  error <- tryCatch(lex(sql=paste0("UPDATE payload SET value=CAST(x'",hex,"' AS TEXT);")),error=identity)
  stopifnot(inherits(error,"error"))
}
DBI::dbDisconnect(con);unlink(c(path,paste0(path,"-wal"),paste0(path,"-shm")))
cat("BOUNDED_JSON_LEXER_PROTOTYPE utf8_escape_split_empty_positive=4 malformed_unicode_nul_utf8_negative=12 buffer_max_bytes=4096 prototype_only=TRUE PASS\n")
