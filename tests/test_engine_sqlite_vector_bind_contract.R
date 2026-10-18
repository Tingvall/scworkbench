.engine_db_bind_original <- function(con, table, df, chunk_size = 1000L) {
  if (is.null(df) || nrow(df) == 0) return(invisible(TRUE))
  chunk_size <- as.integer(chunk_size)
  stopifnot(chunk_size >= 1L)
  fields <- names(df)
  quote_ident <- function(x) paste0('"', gsub('"', '""', x, fixed = TRUE), '"')
  sql <- paste0("INSERT INTO ", quote_ident(table), " (", paste(vapply(fields,
    quote_ident, character(1)), collapse = ", "), ") VALUES (",
    paste(rep("?", length(fields)), collapse = ", "), ");")
  stmt <- DBI::dbSendStatement(con, sql)
  on.exit(DBI::dbClearResult(stmt), add = TRUE)
  for (i in seq_len(nrow(df))) DBI::dbBind(stmt, unname(as.list(df[i, fields, drop = FALSE])))
  invisible(TRUE)
}

.engine_db_bind_spy <- function() {
  ns <- asNamespace("DBI"); original <- get("dbBind", ns)
  state <- new.env(parent = emptyenv()); state$lengths <- integer()
  spy <- function(res, params, ...) {
    state$lengths <- c(state$lengths, if (length(params)) length(params[[1L]]) else 0L)
    original(res, params, ...)
  }
  unlockBinding("dbBind", ns); assign("dbBind", spy, ns); lockBinding("dbBind", ns)
  list(state = state, close = function() {
    unlockBinding("dbBind", ns); assign("dbBind", original, ns); lockBinding("dbBind", ns)
  })
}

.engine_db_bind_case <- function(helper, rows, schema = "id INTEGER,txt TEXT,num REAL,flag INTEGER",
    setup = character(), transaction = FALSE, chunk = 3L) {
  path <- tempfile("sqlite_vector_bind_", fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit({DBI::dbDisconnect(con); unlink(path)}, add = TRUE)
  DBI::dbExecute(con, "PRAGMA foreign_keys=ON")
  DBI::dbExecute(con, paste0("CREATE TABLE target(", schema, ")"))
  DBI::dbExecute(con, "CREATE TABLE audit(id INTEGER)")
  for (sql in setup) DBI::dbExecute(con, sql)
  if (transaction) DBI::dbBegin(con)
  warnings <- character()
  error <- withCallingHandlers(tryCatch({helper(con, "target", rows, chunk); NULL},
    error = identity), warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning")
    })
  active <- RSQLite::sqliteIsTransacting(con)
  # Hex comparisons preserve exact SQLite text/blob bytes, including NULL and
  # deliberately invalid UTF8 fixtures, without a decoder changing evidence.
  actual <- DBI::dbGetQuery(con, paste("SELECT rowid,id,num,flag,hex(txt) txt_hex,",
    "typeof(id) id_type,typeof(txt) txt_type,typeof(num) num_type,typeof(flag) flag_type",
    "FROM target ORDER BY rowid"))
  audit <- DBI::dbGetQuery(con, "SELECT rowid,id FROM audit ORDER BY rowid")
  stopifnot(length(suppressWarnings(DBI::dbListResults(con))) == 0L)
  if (active) DBI::dbRollback(con)
  after_rollback <- DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM target")$n[[1L]]
  # Faults are not swallowed/retried inside helper; caller explicitly rolls
  # back/resets, removes the faulting trigger and supplies a valid retry row.
  triggers <- DBI::dbGetQuery(con, "SELECT name FROM sqlite_schema WHERE type='trigger'")$name
  for (name in triggers) DBI::dbExecute(con, paste("DROP TRIGGER", DBI::dbQuoteIdentifier(con, name)))
  DBI::dbExecute(con, "DELETE FROM target"); DBI::dbExecute(con, "DELETE FROM audit")
  retry_warnings <- character()
  retry <- withCallingHandlers(tryCatch({helper(con, "target", rows[1L, , drop = FALSE], chunk); NULL},
    error = identity), warning = function(w) {
      retry_warnings <<- c(retry_warnings, conditionMessage(w)); invokeRestart("muffleWarning")
    })
  list(error = if (inherits(error, "error")) conditionMessage(error) else NULL,
    warnings = warnings, rows = actual, audit = audit, active = active,
    after_rollback = after_rollback,
    retry_warnings = retry_warnings,
    retry_error = if (inherits(retry, "error")) conditionMessage(retry) else NULL,
    retry_count = DBI::dbGetQuery(con, "SELECT COUNT(*) n FROM target")$n[[1L]])
}

test_engine_sqlite_vector_bind_order_types_and_positive_contract <- function() {
  rows <- data.frame(id = rep(c(2L, 1L, NA_integer_), 7L),
    txt = rep(c("ASCII\n\t\"\\", "", NA_character_), 7L),
    num = rep(c(-0, .Machine$double.xmax, NA_real_), 7L),
    flag = rep(c(TRUE, FALSE, NA), 7L))
  helper <- scworkbench:::.wb_db_append_chunked
  expected <- .engine_db_bind_case(.engine_db_bind_original, rows, chunk = 4L)
  spy <- .engine_db_bind_spy(); on.exit(spy$close(), add = TRUE, after = FALSE)
  actual <- .engine_db_bind_case(helper, rows, chunk = 4L)
  stopifnot(identical(expected, actual))
  if (as.character(getNamespaceVersion("RSQLite")) == "2.3.7" &&
      as.character(getNamespaceVersion("DBI")) == "1.2.3")
    stopifnot(any(spy$state$lengths > 1L), max(spy$state$lengths) <= 4L)
  for (tx in c(FALSE, TRUE)) stopifnot(identical(
    .engine_db_bind_case(.engine_db_bind_original, rows, transaction = tx, chunk = 1L),
    .engine_db_bind_case(helper, rows, transaction = tx, chunk = 10000L)))
  # Evaluate the actual endpoint expression with metadata-only row cardinality;
  # no giant data allocation or execution is needed to cover INTMAX arithmetic.
  endpoint <- NULL
  visit <- function(x) {
    if (!is.call(x)) return(invisible(NULL))
    if (identical(x[[1L]], as.name("<-")) && identical(x[[2L]], as.name("end")))
      endpoint <<- x[[3L]]
    if (length(x) > 1L) for (i in seq.int(2L, length(x)))
      if (!is.symbol(x[[i]]) || nzchar(as.character(x[[i]]))) visit(x[[i]])
  }
  visit(body(helper))
  stopifnot(!is.null(endpoint))
  metadata <- structure(list(), class = "data.frame",
    row.names = c(NA_integer_, -.Machine$integer.max))
  boundary <- eval(endpoint, list(df = metadata, start = .Machine$integer.max - 2L, size = 1000L))
  stopifnot(identical(boundary, as.double(.Machine$integer.max)),
    identical(boundary + 1, as.double(.Machine$integer.max) + 1))
  TRUE
}

test_engine_sqlite_vector_bind_constraint_prefix_and_transactions_contract <- function() {
  helper <- scworkbench:::.wb_db_append_chunked
  for (bad in c(2L, 3L, 4L, 7L)) for (tx in c(FALSE, TRUE)) {
    base <- data.frame(id = as.integer(seq_len(8L)), txt = rep("plain", 8L),
      num = rep(1.25, 8L), flag = rep(TRUE, 8L))
    for (kind in c("UNIQUE", "CHECK", "FK", "ABORT", "FAIL", "ROLLBACK")) {
      rows <- base; schema <- "id INTEGER,txt TEXT,num REAL,flag INTEGER"
      setup <- "CREATE TRIGGER record_insert AFTER INSERT ON target BEGIN INSERT INTO audit VALUES(NEW.id); END"
      if (kind == "UNIQUE") {
        schema <- "id INTEGER UNIQUE,txt TEXT,num REAL,flag INTEGER"; rows$id[[bad]] <- 1L
      } else if (kind == "CHECK") {
        schema <- "id INTEGER CHECK(id>0),txt TEXT,num REAL,flag INTEGER"; rows$id[[bad]] <- -1L
      } else if (kind == "FK") {
        schema <- "id INTEGER REFERENCES parent(id),txt TEXT,num REAL,flag INTEGER"
        setup <- c("CREATE TABLE parent(id INTEGER PRIMARY KEY)",
          "INSERT INTO parent VALUES(1),(2),(3),(4),(5),(6),(7),(8)", setup)
        rows$id[[bad]] <- 99L
      } else setup <- c(setup, paste0("CREATE TRIGGER reject_insert BEFORE INSERT ON target WHEN NEW.id=", bad,
        " BEGIN INSERT INTO audit VALUES(-NEW.id); SELECT RAISE(", kind, ",'bind fault'); END"))
      old <- .engine_db_bind_case(.engine_db_bind_original, rows, schema, setup, tx)
      new <- .engine_db_bind_case(helper, rows, schema, setup, tx)
      stopifnot(!is.null(old$error), identical(old, new), is.null(new$retry_error), new$retry_count == 1L)
    }
  }
  TRUE
}

test_engine_sqlite_vector_bind_extended_and_encoding_fallback_contract <- function() {
  helper <- scworkbench:::.wb_db_append_chunked
  base <- data.frame(id = c(1L, 2L), txt = c("a", "b"), num = c(1, 2), flag = c(TRUE, FALSE))
  variants <- list()
  x <- base; x$id <- factor(c("a", "b")); variants[[1L]] <- x
  x <- base; x$num <- as.Date(c(1, 2), origin = "1970-01-01"); variants[[2L]] <- x
  x <- base; x$num <- as.POSIXct(c(1, 2), origin = "1970-01-01", tz = "UTC"); variants[[3L]] <- x
  x <- base; x$id <- bit64::as.integer64(c("9007199254740993", "9007199254740994")); variants[[4L]] <- x
  x <- base; x$txt <- I(list(as.raw(c(0, 255)), NULL)); variants[[5L]] <- x
  x <- base; attr(x$num, "custom") <- "preserve"; variants[[6L]] <- x
  x <- base; x$txt <- c("\u03bb", "\u96ea"); variants[[7L]] <- x
  x <- base; x$txt <- iconv(c("caf\u00e9", "plain"), to = "latin1"); variants[[8L]] <- x
  invalid <- rawToChar(as.raw(255)); Encoding(invalid) <- "UTF-8"
  x <- base; x$txt <- c("plain", invalid); variants[[9L]] <- x
  for (rows in variants) {
    expected <- .engine_db_bind_case(.engine_db_bind_original, rows)
    spy <- .engine_db_bind_spy()
    actual <- tryCatch(.engine_db_bind_case(helper, rows), finally = spy$close())
    stopifnot(identical(expected, actual), all(spy$state$lengths == 1L))
  }
  TRUE
}

test_engine_sqlite_vector_bind_resource_and_cleanup_fallback_contract <- function() {
  helper <- scworkbench:::.wb_db_append_chunked
  rows <- data.frame(id = rep(1L, 5L), txt = rep(strrep("x", 10000L), 5L),
    num = rep(1.25, 5L), flag = rep(TRUE, 5L))
  for (guard in list(.001, "unknown", NA_real_, list(256), Inf,
      setNames(256, "unknown"), bit64::as.integer64(256))) {
    options_before <- options(scworkbench.max_dense_materialize_mb = guard)
    expected <- .engine_db_bind_case(.engine_db_bind_original, rows)
    spy <- .engine_db_bind_spy()
    actual <- tryCatch(.engine_db_bind_case(helper, rows), finally = {
      spy$close(); options(options_before)
    })
    stopifnot(identical(expected, actual), all(spy$state$lengths == 1L))
  }
  methods <- paste0(c("is.numeric.", "is.finite.", "Ops."), "engine_memory_guard_probe")
  had_method <- vapply(methods, exists, logical(1), envir = globalenv(), inherits = FALSE)
  previous <- lapply(methods, function(name) get0(name, globalenv(), inherits = FALSE))
  on.exit(for (i in seq_along(methods)) {
    if (!had_method[[i]]) {
      if (exists(methods[[i]], globalenv(), inherits = FALSE)) rm(list = methods[[i]], envir = globalenv())
    } else assign(methods[[i]], previous[[i]], globalenv())
  }, add = TRUE)
  called <- FALSE
  probe <- function(...) {called <<- TRUE; warning("unexpected guard dispatch"); stop("GUARD_METHOD_MUST_NOT_RUN")}
  for (name in methods) assign(name, probe, globalenv())
  old_probe_option <- options(scworkbench.max_dense_materialize_mb =
    structure(256, class = "engine_memory_guard_probe"))
  spy <- .engine_db_bind_spy()
  actual <- tryCatch(.engine_db_bind_case(helper, rows), finally = {
    spy$close(); options(old_probe_option)
  })
  stopifnot(!called, all(spy$state$lengths == 1L),
    identical(actual, .engine_db_bind_case(.engine_db_bind_original, rows)))
  # Admission must consider string bytes as well as row/column cardinality.
  long <- rows; long$txt <- rep(strrep("x", 100000L), 5L)
  old_option <- options(scworkbench.max_dense_materialize_mb = 4)
  on.exit(options(old_option), add = TRUE)
  expected <- .engine_db_bind_case(.engine_db_bind_original, long)
  spy <- .engine_db_bind_spy()
  actual <- tryCatch(.engine_db_bind_case(helper, long), finally = spy$close())
  stopifnot(identical(expected, actual), all(spy$state$lengths == 1L))
  # Same original rowwise behavior when a wide dataframe's carrier alone
  # exceeds the existing allowance; no new resource rejection is introduced.
  wide <- rows
  for (j in seq_len(128L)) wide[[paste0("v", j)]] <- rep(j, 5L)
  schema <- paste("id INTEGER,txt TEXT,num REAL,flag INTEGER,",
    paste(paste0("v", seq_len(128L), " INTEGER"), collapse = ","))
  options(scworkbench.max_dense_materialize_mb = .5)
  expected <- .engine_db_bind_case(.engine_db_bind_original, wide, schema)
  spy <- .engine_db_bind_spy()
  actual <- tryCatch(.engine_db_bind_case(helper, wide, schema), finally = spy$close())
  stopifnot(identical(expected, actual), all(spy$state$lengths == 1L))
  options(old_option)
  # Active graph admission is deliberately not widened by this ordinary path.
  path <- tempfile("sqlite_graph_bind_"); con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit({DBI::dbDisconnect(con); unlink(path)}, add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE target(id INTEGER,txt TEXT,num REAL,flag INTEGER)")
  con@ref$wb_graph_policy <- list(memory_bytes = "8388608")
  spy <- .engine_db_bind_spy(); on.exit(spy$close(), add = TRUE, after = FALSE)
  helper(con, "target", rows)
  stopifnot(all(spy$state$lengths == 1L), DBI::dbGetQuery(con,
    "SELECT COUNT(*) n FROM target")$n[[1L]] == 5L)
  con@ref$wb_graph_policy <- NULL
  TRUE
}
