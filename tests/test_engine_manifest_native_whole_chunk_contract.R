.engine_manifest_whole_policy <- function() scworkbench:::.wb_graph_budgets(list(
  memory_bytes = "8388608", sqlite_cache_kib = 2048L, partition_bytes = 262144L,
  partition_rows = 2L, collect_bytes = 4194304L))

test_engine_manifest_native_whole_opaque_policy_old_dispatch_contract <- function() {
  path <- tempfile("manifest_whole_opaque_", fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit({DBI::dbDisconnect(con); unlink(path)}, add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE entries(id INTEGER,label TEXT);")
  DBI::dbAppendTable(con, "entries", data.frame(id = seq_len(5000L), label = rep("x", 5000L)))
  actual <- scworkbench:::.wb_manifest_table_identity
  legacy <- actual
  local <- new.env(parent = environment(legacy))
  # Disable only the optional backend as an existing supported fallback.
  # All actual SQL/resources/old-small/scalar code remains the real function;
  # the probe stops at its FIRST scalar hook, before either C serializer.
  local$getNamespaceVersion <- function(package) "0.0.0"
  environment(legacy) <- local
  methods <- c("as.double.manifest_whole_opaque_token", "Ops.manifest_whole_opaque_partition")
  previous <- lapply(methods, function(name) if (exists(name, globalenv(), inherits = FALSE))
    list(present = TRUE, value = get(name, globalenv(), inherits = FALSE)) else list(present = FALSE))
  on.exit(for (i in seq_along(methods)) if (previous[[i]]$present)
    assign(methods[[i]], previous[[i]]$value, globalenv()) else rm(list = methods[[i]], envir = globalenv()), add = TRUE)
  calls <- 0L
  assign(methods[[1L]], function(x, ...) {calls <<- calls + 1L; as.double(unclass(x))}, globalenv())
  assign(methods[[2L]], function(e1, e2) {
    calls <<- calls + 1L
    do.call(.Generic, if (missing(e2)) list(unclass(e1)) else list(unclass(e1), unclass(e2)))
  }, globalenv())
  token <- structure("8589934592", class = "manifest_whole_opaque_token")
  partition <- structure(262144, class = "manifest_whole_opaque_partition")
  stopifnot(as.numeric(token) == 8589934592, partition + 1 == 262145, calls == 2L)
  old <- getOption("scworkbench.graph_storage_test_hook")
  on.exit(options(scworkbench.graph_storage_test_hook = old), add = TRUE)
  observe_first_scalar <- function(fn, policy) {
    captured <- NULL; whole <- 0L
    options(scworkbench.graph_storage_test_hook = function(event, state) {
      if (event == "manifest_projection_decoded") calls <<- 0L
      if (event == "manifest_native_json" && state$scope == "whole") whole <<- whole + 1L
      if (event == "manifest_scalar_batch") {
        captured <<- calls
        stop("OPAQUE_LEGACY_SCALAR_BOUNDARY")
      }
    })
    failure <- tryCatch(fn(con, "entries", budgets = policy), error = identity)
    stopifnot(inherits(failure, "error"), grepl("OPAQUE_LEGACY_SCALAR_BOUNDARY", conditionMessage(failure), fixed = TRUE),
      !is.null(captured), whole == 0L)
    captured
  }
  for (field in c("token_bytes", "partition_bytes")) {
    policy <- .engine_manifest_whole_policy()
    policy[[field]] <- if (field == "token_bytes") token else partition
    expected <- observe_first_scalar(legacy, policy)
    observed <- observe_first_scalar(actual, policy)
    stopifnot(identical(observed, expected)) # No EXTRA optional-path dispatch.
  }
  options(scworkbench.graph_storage_test_hook = old)
  stopifnot(identical(scworkbench:::.wb_manifest_table_identity_materialized(con, "entries"), actual(con, "entries")))
  TRUE
}

test_engine_manifest_native_whole_original_integer_boundaries_contract <- function() {
  path <- tempfile("manifest_native_whole_", fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit({DBI::dbDisconnect(con); unlink(path)}, add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE entries(id INTEGER,label TEXT);")
  policy <- .engine_manifest_whole_policy()
  known <- identical(as.character(getRversion()), "4.4.1") &&
    identical(as.character(getNamespaceVersion("jsonlite")), "1.8.8")
  whole_hits <- 0L; chunks <- integer(); reference_chunks <- list()
  old <- options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "manifest_native_whole_chunk") {
      whole_hits <<- whole_hits + 1L
      stopifnot(state$rows <= 5000L, state$budgets$partition_rows == 2L,
        state$carrier_bytes == 4096 + 576 * 2 + state$rows * (16 * 2 + 32 + 128),
        state$reservation_bytes == state$carrier_bytes + 8 * state$encoded_bytes,
        state$reservation_bytes <= 8 * state$budgets$partition_bytes,
        state$actual_bytes <= state$encoded_bytes)
      frames <- Filter(function(frame) exists("whole", frame, inherits = FALSE), sys.frames())
      stopifnot(length(frames) > 0L)
      actual <- get("whole", frames[[length(frames)]], inherits = FALSE)
      expected <- reference_chunks[[length(chunks) + 1L]]
      stopifnot(identical(charToRaw(actual), charToRaw(expected)), identical(Encoding(actual), Encoding(expected)))
    }
    if (event == "manifest_chunk") chunks <<- c(chunks, state$rows)
  })
  on.exit(options(old), add = TRUE)
  for (count in c(0L, 1L, 4999L, 5000L, 5001L, 10020L)) {
    DBI::dbExecute(con, "DELETE FROM entries;")
    rows <- data.frame(id = seq_len(count), label = rep(c("x", "", NA_character_), length.out = count))
    if (count) DBI::dbAppendTable(con, "entries", rows)
    reference_chunks <- if (!count) list() else lapply(split(seq_len(count),
      (seq_len(count) - 1L) %/% 5000L), function(indices) as.character(jsonlite::toJSON(rows[indices, , drop = FALSE],
        dataframe = "rows", auto_unbox = TRUE, null = "null", na = "null")))
    chunks <- integer()
    file_before <- digest::digest(file = path, algo = "sha256")
    expected <- scworkbench:::.wb_manifest_table_identity_materialized(con, "entries")
    stopifnot(identical(expected, scworkbench:::.wb_manifest_table_identity(con, "entries", budgets = policy)),
      identical(chunks, if (!count) integer() else as.integer(
        c(rep(5000L, count %/% 5000L), if (count %% 5000L) count %% 5000L else integer()))),
      identical(file_before, digest::digest(file = path, algo = "sha256")))
  }
  if (known) stopifnot(whole_hits > 0L) else stopifnot(whole_hits == 0L)
  # A private caller's larger logical fold is preserved, never silently split.
  chunks <- integer(); before_hits <- whole_hits
  expected <- scworkbench:::.wb_manifest_table_identity_materialized(con, "entries", 10020L)
  stopifnot(identical(expected, scworkbench:::.wb_manifest_table_identity(con, "entries", 10020L)),
    identical(chunks, 10020L), whole_hits == before_hits)
  TRUE
}

test_engine_manifest_native_whole_deferred_and_unsupported_contract <- function() {
  path <- tempfile("manifest_native_whole_deferred_", fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit({DBI::dbDisconnect(con); unlink(path)}, add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE entries(id INTEGER,label TEXT);")
  DBI::dbAppendTable(con, "entries", data.frame(id = seq_len(5000L), label = rep("x", 5000L)))
  attempts <- hits <- 0L
  old <- options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "manifest_native_json" && state$scope == "whole") {
      attempts <<- attempts + 1L
      if (state$mode == "native") hits <<- hits + 1L
    }
  })
  on.exit(options(old), add = TRUE)
  for (position in c(1L, 2500L, 5000L)) {
    DBI::dbExecute(con, "UPDATE entries SET label=? WHERE rowid=?;", params = list(strrep("x", 257L), position))
    before <- attempts
    expected <- scworkbench:::.wb_manifest_table_identity_materialized(con, "entries")
    stopifnot(identical(expected, scworkbench:::.wb_manifest_table_identity(con, "entries")), attempts == before)
    DBI::dbExecute(con, "UPDATE entries SET label='x' WHERE rowid=?;", params = list(position))
  }
  for (value in list("é", "quote\"", "late\n", as.raw(c(0, 255)))) {
    DBI::dbExecute(con, "UPDATE entries SET label=? WHERE rowid=5000;",
      params = list(if (is.raw(value)) list(value) else value))
    before_hits <- hits
    expected <- suppressWarnings(scworkbench:::.wb_manifest_table_identity_materialized(con, "entries"))
    stopifnot(identical(expected, suppressWarnings(scworkbench:::.wb_manifest_table_identity(con, "entries"))),
      hits == before_hits)
    DBI::dbExecute(con, "UPDATE entries SET label='x' WHERE rowid=5000;")
  }
  DBI::dbExecute(con, "UPDATE entries SET id=1.5 WHERE rowid=5000;")
  before_hits <- hits
  stopifnot(identical(suppressWarnings(scworkbench:::.wb_manifest_table_identity_materialized(con, "entries")),
    suppressWarnings(scworkbench:::.wb_manifest_table_identity(con, "entries"))), hits == before_hits)
  TRUE
}

test_engine_manifest_native_whole_resources_fault_mutation_contract <- function() {
  path <- tempfile("manifest_native_whole_fault_", fileext = ".sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbExecute(con, "PRAGMA journal_mode=WAL;")
  writer <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit({DBI::dbDisconnect(writer); DBI::dbDisconnect(con); unlink(paste0(path, c("", "-wal", "-shm")))}, add = TRUE)
  DBI::dbExecute(con, "CREATE TABLE entries(id INTEGER,label TEXT);")
  DBI::dbAppendTable(con, "entries", data.frame(id = seq_len(5000L), label = rep("x", 5000L)))
  before <- list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;"), temp = DBI::dbGetQuery(con, "PRAGMA temp_store;"),
    policy = con@ref$wb_graph_policy, reservation = con@ref$wb_graph_cache_kib)
  expected <- scworkbench:::.wb_manifest_table_identity_materialized(con, "entries")
  known <- identical(as.character(getRversion()), "4.4.1") &&
    identical(as.character(getNamespaceVersion("jsonlite")), "1.8.8")
  old <- options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "manifest_native_whole_chunk") stop("WHOLE_NATIVE_FAULT")
  })
  on.exit(options(old), add = TRUE)
  if (known) {
    failure <- tryCatch(scworkbench:::.wb_manifest_table_identity(con, "entries"), error = identity)
    stopifnot(inherits(failure, "error"), grepl("WHOLE_NATIVE_FAULT", conditionMessage(failure), fixed = TRUE))
    options(scworkbench.graph_storage_test_hook = function(event, state) {
      if (event == "manifest_native_whole_chunk") DBI::dbExecute(writer, "UPDATE entries SET label='changed' WHERE rowid=5000;")
    })
    failure <- tryCatch(scworkbench:::.wb_manifest_table_identity(con, "entries"), error = identity)
    stopifnot(inherits(failure, "wb_graph_error"), grepl("changed", conditionMessage(failure)))
    DBI::dbExecute(writer, "UPDATE entries SET label='x' WHERE rowid=5000;")
  }
  options(old)
  tiny <- .engine_manifest_whole_policy(); tiny$token_bytes <- "1"
  stopifnot(inherits(tryCatch(scworkbench:::.wb_manifest_table_identity(con, "entries", budgets = tiny),
    error = identity), "wb_graph_error"))
  external <- scworkbench:::.wb_matrix_native_byte_observer(con)
  stopifnot(!is.null(external), is.null(attr(external, "wb_manifest_spill_boundaries", exact = TRUE)))
  external_closed <- FALSE
  on.exit(if (!external_closed) external$close(), add = TRUE, after = FALSE)
  whole_events <- 0L
  options(scworkbench.graph_storage_test_hook = function(event, state) {
    if (event == "manifest_native_json" && state$scope == "whole") whole_events <<- whole_events + 1L
  })
  stopifnot(identical(expected, scworkbench:::.wb_manifest_table_identity(con, "entries", observer = external)), whole_events == 0L)
  external$finish(); external$close(); external_closed <- TRUE
  options(old)
  stopifnot(identical(expected, scworkbench:::.wb_manifest_table_identity(con, "entries")),
    identical(before, list(cache = DBI::dbGetQuery(con, "PRAGMA cache_size;"), temp = DBI::dbGetQuery(con, "PRAGMA temp_store;"),
      policy = con@ref$wb_graph_policy, reservation = con@ref$wb_graph_cache_kib)))
  TRUE
}
