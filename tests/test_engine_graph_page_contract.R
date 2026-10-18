.engine_graph_page_context <- function(path = ':memory:', read_only = FALSE) {
  con <- DBI::dbConnect(RSQLite::SQLite(), path,
    flags = if (read_only) RSQLite::SQLITE_RO else RSQLite::SQLITE_RWC,
    bigint = 'integer64')
  if (!read_only) {
    DBI::dbExecute(con, paste0('CREATE TABLE IF NOT EXISTS artifact_graph_rows(',
      'artifact_id TEXT,component TEXT,row_ordinal INTEGER,record_json TEXT,',
      'PRIMARY KEY(artifact_id,component,row_ordinal));'))
    DBI::dbExecute(con, 'CREATE TABLE IF NOT EXISTS caller(value INTEGER);')
  }
  con
}

.engine_graph_page_old <- function(con, artifact_id, component, after, page, bytes,
                                   predicate = '', params = list()) {
  query <- paste0('WITH candidate AS (SELECT row_ordinal,',
    'octet_length(record_json) n FROM artifact_graph_rows ',
    'WHERE artifact_id=? AND component=? ', predicate,
    ' AND row_ordinal>=CAST(? AS INTEGER) ORDER BY row_ordinal LIMIT ?),',
    'bounded AS (SELECT *,SUM(n) OVER (ORDER BY row_ordinal) used FROM candidate) ',
    'SELECT g.row_ordinal,g.record_json FROM bounded b JOIN artifact_graph_rows g ',
    'ON g.artifact_id=? AND g.component=? AND g.row_ordinal=b.row_ordinal ',
    'WHERE b.used<=? ORDER BY g.row_ordinal;')
  DBI::dbGetQuery(con, query, params = c(list(artifact_id, component), params,
    list(after, page, artifact_id, component, bytes)))
}

.engine_graph_page_add <- function(con, ordinal, value = '{"value":"雪"}') {
  DBI::dbExecute(con, paste0('INSERT INTO artifact_graph_rows VALUES(',
    "'a','nodes',CAST(? AS INTEGER),?);"), params = list(ordinal, value))
}

test_engine_graph_page_exact_prefix_contract <- function() {
  con <- .engine_graph_page_context(); on.exit(DBI::dbDisconnect(con))
  for (ordinal in c('0', '2', '10', '9007199254740993', '9223372036854775806'))
    .engine_graph_page_add(con, ordinal)
  page <- scworkbench:::.wb_graph_page
  for (after in c('0', '1', '10', '9007199254740993', '9223372036854775807')) {
    for (bytes in c(256.5, 512L, 1048576L, 2147483648, 1e100)) {
      actual <- page(con, 'a', 'nodes', after, 512L, bytes)
      old <- .engine_graph_page_old(con, 'a', 'nodes', after, 512L, bytes)
      stopifnot(identical(as.character(actual$row_ordinal),
        as.character(old$row_ordinal[seq_len(nrow(actual))])),
        identical(actual$record_json, old$record_json[seq_len(nrow(actual))]))
      if (bytes >= 1048576L) stopifnot(identical(actual, old))
    }
  }
  # Repeated pages reconstruct exactly the same ordered records, even when the
  # separate metadata bound shortens a tiny-byte partition.
  expected <- .engine_graph_page_old(con, 'a', 'nodes', '0', 512L, 1048576L)
  pieces <- list(); after <- '0'
  repeat {
    block <- page(con, 'a', 'nodes', after, 512L, 256L)
    if (!nrow(block)) break
    pieces[[length(pieces) + 1L]] <- block
    after <- as.character(bit64::as.integer64(tail(block$row_ordinal, 1L)) + bit64::as.integer64(1))
  }
  stopifnot(identical(unlist(lapply(pieces, function(x)as.character(x$row_ordinal)),
    use.names = FALSE), as.character(expected$row_ordinal)),
    identical(unlist(lapply(pieces, `[[`, 'record_json'), use.names = FALSE), expected$record_json))
  predicate <- ' AND row_ordinal<>CAST(? AS INTEGER)'
  stopifnot(identical(page(con, 'a', 'nodes', '0', 512L, 1048576L,
    predicate, list('2')), .engine_graph_page_old(con, 'a', 'nodes', '0',
      512L, 1048576L, predicate, list('2'))))
  text <- '{"value":"雪"}'; size <- nchar(text, type = 'bytes')
  stopifnot(nrow(page(con, 'a', 'nodes', '0', 512L, size)) == 1L)
  error <- tryCatch(page(con, 'a', 'nodes', '0', 512L, size - 1L), error = identity)
  stopifnot(inherits(error, 'error'), grepl('GRAPH_RESOURCE_EXCEEDED', conditionMessage(error)))
  for (bad in c(0, -1, NA_real_, Inf, 1.5, 2147483648))
    stopifnot(inherits(tryCatch(page(con, 'a', 'nodes', '0', bad, 1000), error = identity), 'error'))
  TRUE
}

test_engine_graph_page_positive_finite_bytes_contract <- function() {
  con <- .engine_graph_page_context(); on.exit(DBI::dbDisconnect(con))
  .engine_graph_page_add(con, '0', '{}')
  page <- scworkbench:::.wb_graph_page
  for (bytes in c(2, 2.5, 4.5, 2147483648, 1e100))
    stopifnot(identical(page(con, 'a', 'nodes', '0', 512L, bytes),
      .engine_graph_page_old(con, 'a', 'nodes', '0', 512L, bytes)))
  for (bytes in c(.5, 1.5)) {
    error <- tryCatch(page(con, 'a', 'nodes', '0', 512L, bytes), error = identity)
    stopifnot(inherits(error, 'error'), grepl('GRAPH_RESOURCE_EXCEEDED', conditionMessage(error)))
  }
  for (bytes in c(0, -1, NA_real_, Inf))
    stopifnot(inherits(tryCatch(page(con, 'a', 'nodes', '0', 512L, bytes), error = identity), 'error'))
  TRUE
}

test_engine_graph_page_snapshot_and_unwind_contract <- function() {
  path <- tempfile(fileext = '.sqlite')
  con <- .engine_graph_page_context(path); writer <- .engine_graph_page_context(path)
  on.exit({DBI::dbDisconnect(writer); DBI::dbDisconnect(con); unlink(c(path, paste0(path, c('-wal', '-shm'))))})
  DBI::dbGetQuery(con, 'PRAGMA journal_mode=WAL;')
  .engine_graph_page_add(con, '0', '{"value":"old"}')
  page <- scworkbench:::.wb_graph_page
  state <- new.env(parent = emptyenv()); state$writer <- writer; state$calls <- 0L
  state$mode <- 'write'; options(scworkbench.graph_page_probe = state)
  on.exit(options(scworkbench.graph_page_probe = NULL), add = TRUE)
  trace('dbGetQuery', where = asNamespace('DBI'), print = FALSE,
    exit = quote({
      probe <- getOption('scworkbench.graph_page_probe')
      if (!is.null(probe) && is.character(statement) &&
          startsWith(statement, 'SELECT row_ordinal,octet_length')) {
        probe$calls <- probe$calls + 1L
        if (probe$mode == 'error') stop('injected after header')
        if (probe$mode == 'write') DBI::dbExecute(probe$writer,
          "UPDATE artifact_graph_rows SET record_json='{\"value\":\"new\"}' WHERE row_ordinal=0;")
      }
    }))
  on.exit(untrace('dbGetQuery', where = asNamespace('DBI')), add = TRUE)
  actual <- page(con, 'a', 'nodes', '0', 512L, 1048576L)
  stopifnot(identical(actual$record_json, '{"value":"old"}'), state$calls == 1L,
    identical(DBI::dbGetQuery(con, 'SELECT record_json FROM artifact_graph_rows')$record_json,
      '{"value":"new"}'))
  DBI::dbBegin(con); DBI::dbExecute(con, 'INSERT INTO caller VALUES(7);')
  state$mode <- 'none'; page(con, 'a', 'nodes', '0', 512L, 1048576L)
  state$mode <- 'error'
  error <- tryCatch(page(con, 'a', 'nodes', '0', 512L, 1048576L), error = identity)
  stopifnot(inherits(error, 'error'), grepl('injected after header', conditionMessage(error)),
    identical(DBI::dbGetQuery(con, 'SELECT value FROM caller')$value, 7L))
  state$mode <- 'none'; page(con, 'a', 'nodes', '0', 512L, 1048576L)
  DBI::dbRollback(con)
  stopifnot(nrow(DBI::dbGetQuery(con, 'SELECT * FROM caller')) == 0L)
  # Own savepoint must also be unwound when no outer transaction exists.
  state$mode <- 'error'; try(page(con, 'a', 'nodes', '0', 512L, 1048576L), silent = TRUE)
  DBI::dbBegin(con); DBI::dbRollback(con)
  TRUE
}

test_engine_graph_page_readonly_and_plan_contract <- function() {
  path <- tempfile(fileext = '.sqlite'); con <- .engine_graph_page_context(path)
  .engine_graph_page_add(con, '0'); DBI::dbDisconnect(con)
  before <- digest::digest(file = path, algo = 'sha256')
  con <- .engine_graph_page_context(path, TRUE)
  on.exit({DBI::dbDisconnect(con); unlink(path)})
  stopifnot(nrow(scworkbench:::.wb_graph_page(con, 'a', 'nodes', '0', 512L, 1048576L)) == 1L)
  for (query in c(paste0('SELECT row_ordinal,octet_length(record_json) n FROM artifact_graph_rows ',
      "WHERE artifact_id='a' AND component='nodes' AND row_ordinal>=CAST('0' AS INTEGER) ORDER BY row_ordinal LIMIT 512"),
      paste0('SELECT row_ordinal,record_json FROM artifact_graph_rows ',
        "WHERE artifact_id='a' AND component='nodes' AND row_ordinal>=CAST('0' AS INTEGER) ",
        "AND row_ordinal<=CAST('0' AS INTEGER) ORDER BY row_ordinal"))) {
    plan <- DBI::dbGetQuery(con, paste('EXPLAIN QUERY PLAN', query))$detail
    stopifnot(any(grepl('SEARCH.*INDEX', plan)), !any(grepl('TEMP|SORT|SCAN ', plan)))
  }
  stopifnot(identical(before, digest::digest(file = path, algo = 'sha256')),
    !file.exists(paste0(path, '-wal')), !file.exists(paste0(path, '-shm')))
  TRUE
}

test_engine_graph_page_header_bounds_and_corruption_contract <- function() {
  con <- .engine_graph_page_context(); on.exit(DBI::dbDisconnect(con))
  DBI::dbWriteTable(con, 'artifact_graph_rows', data.frame(artifact_id = 'a',
    component = 'nodes', row_ordinal = seq_len(17000L) - 1L, record_json = '{}'), append = TRUE)
  state <- new.env(parent = emptyenv()); state$con <- con; state$headers <- list()
  state$payload_queries <- 0L; state$mode <- 'observe'
  options(scworkbench.graph_page_bound_probe = state)
  on.exit(options(scworkbench.graph_page_bound_probe = NULL), add = TRUE)
  trace('dbGetQuery', where = asNamespace('DBI'), print = FALSE,
    exit = quote({
      probe <- getOption('scworkbench.graph_page_bound_probe')
      if (!is.null(probe) && startsWith(statement, 'SELECT row_ordinal,octet_length')) {
        probe$headers[[length(probe$headers) + 1L]] <- returnValue()
        if (probe$mode == 'delete') DBI::dbExecute(probe$con,
          "DELETE FROM artifact_graph_rows WHERE row_ordinal=0;")
        if (probe$mode == 'length') DBI::dbExecute(probe$con,
          "UPDATE artifact_graph_rows SET record_json='{\"changed\":true}' WHERE row_ordinal=0;")
      }
      if (!is.null(probe) && startsWith(statement, 'SELECT row_ordinal,record_json'))
        probe$payload_queries <- probe$payload_queries + 1L
    }))
  on.exit(untrace('dbGetQuery', where = asNamespace('DBI')), add = TRUE)
  page <- scworkbench:::.wb_graph_page
  for (bytes in c(2L, 256L, 1048576L, 4194304L)) {
    actual <- page(con, 'a', 'nodes', '0', 2147483647, bytes)
    header <- tail(state$headers, 1L)[[1L]]
    stopifnot(nrow(header) <= min(2147483647, max(1, floor(bytes / 256)), 16384),
      nrow(actual) == nrow(header), all(actual$record_json == '{}'),
      as.numeric(object.size(list(header = header, lengths = as.numeric(header$n),
        ordinals = as.character(header$row_ordinal)))) <= bytes + 65536)
  }
  count <- state$payload_queries
  stopifnot(nrow(page(con, 'missing', 'nodes', '0', 512L, 1048576L)) == 0L,
    identical(state$payload_queries, count))
  for (mode in c('delete', 'length')) {
    state$mode <- mode
    error <- tryCatch(page(con, 'a', 'nodes', '0', 512L, 1048576L), error = identity)
    stopifnot(inherits(error, 'error'), grepl('GRAPH_SOURCE_PAYLOAD_INVALID', conditionMessage(error)),
      identical(DBI::dbGetQuery(con,
        'SELECT record_json FROM artifact_graph_rows WHERE row_ordinal=0')$record_json, '{}'))
  }
  TRUE
}
