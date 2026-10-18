.engine_space_guard_fixture <- function() {
  root <- tempfile("engine_space_guard_")
  b <- wb_init_bundle(root)
  cells <- sprintf("cell_%03d",seq_len(128L));wb_define_cells(b,cells)
  values <- matrix(as.double(seq_len(384L)),128L,
    dimnames=list(cells,c("A","B","C")))
  wb_add_space(b,"source",values)
  list(root=root,b=b,cells=cells,values=values)
}

test_engine_space_guard_admission_frequency_contract <- function() {
  f <- .engine_space_guard_fixture();b <- f$b;plan <- NULL
  ns <- asNamespace("scworkbench")
  counter <- new.env(parent=emptyenv());counter$n <- 0L
  saved <- options(scworkbench.space_guard_schema_counter=counter)
  on.exit({if(!is.null(plan))plan$close();options(saved)
    if(DBI::dbIsValid(b$con))wb_close_bundle(b)
    unlink(f$root,recursive=TRUE)},add=TRUE)
  trace(".wb_schema_status",where=ns,print=FALSE,tracer=quote({
    .counter <- getOption("scworkbench.space_guard_schema_counter")
    .counter$n <- .counter$n+1L
  }))
  on.exit(untrace(".wb_schema_status",where=ns),add=TRUE,after=FALSE)
  for(parts in c(8L,32L)) {
    previous <- counter$n
    plan <- scworkbench:::.wb_space_payload_reader(b,"source")
    admitted <- counter$n;stopifnot(admitted > previous)
    for(index in split(seq_along(f$cells),ceiling(seq_along(f$cells)/(128L/parts)))) {
      actual <- plan$read(f$cells[index])
      stopifnot(identical(as.numeric(actual),as.numeric(f$values[index,,drop=FALSE])))
    }
    stopifnot(counter$n==admitted)
    plan$close();plan<-NULL
  }
  TRUE
}

test_engine_space_guard_binding_and_connection_contract <- function() {
  f <- .engine_space_guard_fixture();b <- f$b;plan <- NULL;other <- NULL
  on.exit({if(!is.null(plan))plan$close()
    if(!is.null(other)&&DBI::dbIsValid(other))DBI::dbDisconnect(other)
    if(DBI::dbIsValid(b$con)){if(RSQLite::sqliteIsTransacting(b$con))DBI::dbRollback(b$con);wb_close_bundle(b)}
    unlink(f$root,recursive=TRUE)},add=TRUE)
  plan <- scworkbench:::.wb_space_payload_reader(b,"source")
  expect_error <- function(code) stopifnot(inherits(try(force(code),silent=TRUE),"try-error"))
  DBI::dbBegin(b$con)
  DBI::dbExecute(b$con,"UPDATE space_payloads SET provenance_identity='changed' WHERE space_id='source';")
  expect_error(plan$read(f$cells[1L]));DBI::dbRollback(b$con)
  DBI::dbBegin(b$con);DBI::dbExecute(b$con,"DELETE FROM space_payloads;")
  expect_error(plan$read(f$cells[1L]));DBI::dbRollback(b$con)
  DBI::dbBegin(b$con);DBI::dbExecute(b$con,"DROP TABLE space_payloads;")
  expect_error(plan$read(f$cells[1L]));DBI::dbRollback(b$con)
  stopifnot(identical(as.numeric(plan$read(f$cells[1L])),as.numeric(f$values[1L,])))
  # An internal accidental bundle-handle replacement cannot inherit the plan.
  frame <- environment(plan$guard);saved_bundle <- frame$bundle
  database <- DBI::dbGetQuery(b$con,"PRAGMA database_list;")
  other <- DBI::dbConnect(RSQLite::SQLite(),database$file[database$name=="main"][[1L]])
  frame$bundle$con <- other
  expect_error(plan$read(f$cells[1L]))
  frame$bundle <- saved_bundle
  DBI::dbDisconnect(other);other<-NULL
  stopifnot(identical(as.numeric(plan$read(f$cells[1L])),as.numeric(f$values[1L,])))
  TRUE
}

test_engine_space_guard_fresh_schema_authority_contract <- function() {
  f <- .engine_space_guard_fixture();b <- f$b
  on.exit({if(DBI::dbIsValid(b$con)){if(RSQLite::sqliteIsTransacting(b$con))DBI::dbRollback(b$con);wb_close_bundle(b)}
    unlink(f$root,recursive=TRUE)},add=TRUE)
  reject <- function() {
    before <- DBI::dbGetQuery(b$con,"SELECT total_changes();")
    error <- tryCatch(scworkbench:::.wb_space_payload_reader(b,"source"),error=identity)
    if(!inherits(error,"error")){error$close();stop("Invalid schema was admitted")}
    stopifnot(identical(before,DBI::dbGetQuery(b$con,"SELECT total_changes();")))
  }
  DBI::dbBegin(b$con)
  DBI::dbExecute(b$con,"DELETE FROM bundle_schema_migrations WHERE version=(SELECT MIN(version) FROM bundle_schema_migrations);")
  reject();DBI::dbRollback(b$con)
  DBI::dbBegin(b$con);DBI::dbExecute(b$con,"DROP TABLE space_payloads;")
  reject();DBI::dbRollback(b$con)
  DBI::dbExecute(b$con,"CREATE TEMP TABLE space_payloads(space_id TEXT);")
  reject();DBI::dbExecute(b$con,"DROP TABLE temp.space_payloads;")
  plan <- scworkbench:::.wb_space_payload_reader(b,"source")
  tryCatch(stopifnot(identical(as.numeric(plan$read(f$cells[1L])),as.numeric(f$values[1L,]))),
    finally=plan$close())
  TRUE
}
