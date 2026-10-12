test_native_sqlite_byte_same_engine_contract <- function() {
  path <- tempfile(fileext=".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(),path,loadable.extensions=FALSE,default.extensions=FALSE)
  on.exit({if(DBI::dbIsValid(con))DBI::dbDisconnect(con);unlink(c(path,paste0(path,"-wal"),paste0(path,"-shm")))},add=TRUE)
  DBI::dbGetQuery(con,"PRAGMA journal_mode=WAL;")
  DBI::dbExecute(con,"CREATE TABLE payload(value TEXT);")
  DBI::dbExecute(con,"INSERT INTO payload VALUES('one'),('two');")
  cursor <- DBI::dbSendQuery(con,"SELECT value FROM payload ORDER BY rowid;")
  stopifnot(identical(DBI::dbFetch(cursor,n=1L)$value,"one"))
  scworkbench:::.wb_matrix_native_byte_api_initialize()
  stopifnot(identical(DBI::dbFetch(cursor,n=1L)$value,"two"));DBI::dbClearResult(cursor)
  stopifnot(!con@loadable.extensions,
    identical(.Call(get("C_scwb_graph_bytes_api_version",asNamespace("scworkbench"))),
      DBI::dbGetQuery(con,"SELECT sqlite_version() version;")$version[[1L]]))
  denied <- tryCatch(DBI::dbGetQuery(con,"SELECT load_extension('caller-must-remain-disabled');"),error=identity)
  stopifnot(inherits(denied,"error"),grepl("not authorized",conditionMessage(denied),fixed=TRUE))
  DBI::dbExecute(con,"CREATE TABLE publication(value TEXT);")
  DBI::dbExecute(con,"PRAGMA cache_size=-8;")
  DBI::dbBegin(con)
  DBI::dbExecute(con,paste0("INSERT INTO publication WITH RECURSIVE seq(n) AS(VALUES(1) UNION ALL ",
    "SELECT n+1 FROM seq WHERE n<400) SELECT printf('%01024d',n) FROM seq;"))
  for(iteration in seq_len(12L)) {
    observer <- scworkbench:::.wb_matrix_native_byte_observer(con)
    stopifnot(identical(observer$column("1","value","payload"),structure(3L,wb_sqlite_type="text")),
      identical(rawToChar(observer$read(0L,3L)),"one"))
    observer$finish();observer$close()
  }
  DBI::dbCommit(con)
  stopifnot(DBI::dbGetQuery(con,"SELECT COUNT(*) n FROM publication;")$n[[1L]]==400L)
  DBI::dbBegin(con);DBI::dbExecute(con,"INSERT INTO publication VALUES('rolled-back');");DBI::dbRollback(con)
  stopifnot(DBI::dbGetQuery(con,"SELECT COUNT(*) n FROM publication;")$n[[1L]]==400L)
  observer <- scworkbench:::.wb_matrix_native_byte_observer(con)
  observer$column("1","value","payload");stopifnot(rawToChar(observer$read(0L,3L))=="one")
  DBI::dbExecute(con,"UPDATE payload SET value='changed' WHERE rowid=1;")
  changed <- tryCatch(observer$finish(),error=identity);observer$close()
  stopifnot(inherits(changed,"wb_graph_error"),changed$code=="GRAPH_SOURCE_PAYLOAD_INVALID")
  # A closed observer cannot be reused, including after the error above.
  closed <- tryCatch(observer$read(0L,1L),error=identity)
  stopifnot(inherits(closed,"wb_graph_error"))
  DBI::dbDisconnect(con)
  con <- DBI::dbConnect(RSQLite::SQLite(),path,flags=RSQLite::SQLITE_RO,
    loadable.extensions=FALSE,default.extensions=FALSE)
  stopifnot(DBI::dbGetQuery(con,"PRAGMA integrity_check;")[[1L]][[1L]]=="ok")
  TRUE
}
