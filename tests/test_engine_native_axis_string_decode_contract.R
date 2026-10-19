# Generic native storage decoder contracts; no method or public JSON changes.
.native_axis_decode_policy <- function(bytes = 65536L) {
  scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608", sqlite_cache_kib = 256L,
    partition_bytes = bytes, partition_rows = 128L, collect_bytes = 1048576L))
}
.native_axis_decode_fixture <- function(json, raw_json = NULL) {
  f <- new.env(parent = emptyenv()); f$root <- tempfile("native_axis_decode_")
  dir.create(f$root); f$con <- NULL
  f$close <- function() {
    if (!is.null(f$con) && DBI::dbIsValid(f$con)) DBI::dbDisconnect(f$con)
    f$con <- NULL; unlink(f$root, recursive = TRUE, force = TRUE)
  }
  ready <- FALSE; on.exit(if (!ready) f$close(), add = TRUE)
  f$con <- DBI::dbConnect(RSQLite::SQLite(), file.path(f$root, "source.sqlite"))
  DBI::dbExecute(f$con, "CREATE TABLE matrix_fragments(feature_ids_json TEXT,note TEXT)")
  if (is.null(raw_json)) DBI::dbExecute(f$con,
    "INSERT INTO matrix_fragments VALUES(?, 'unchanged')", params = list(json)) else {
    hex <- paste(sprintf("%02x", as.integer(raw_json)), collapse = "")
    DBI::dbExecute(f$con, paste0("INSERT INTO matrix_fragments VALUES(CAST(X'", hex, "' AS TEXT),'unchanged')"))
  }
  ready <- TRUE; f
}
.native_axis_decode_run <- function(f, old = FALSE, bytes = 65536L, after_value = NULL) {
  observer <- scworkbench:::.wb_matrix_native_byte_observer(f$con)
  on.exit(observer$close(), add = TRUE)
  decoder <- if (old) .native_axis_old_c826 else scworkbench:::.wb_matrix_native_axis_reader
  if (old) environment(decoder) <- asNamespace("scworkbench")
  values <- list(); requests <- numeric()
  read <- observer$read
  observer$read <- function(offset, count) { requests <<- c(requests, count); read(offset, count) }
  error <- tryCatch({
    reader <- decoder(f$con, 1L, "feature_ids_json", .native_axis_decode_policy(bytes), observer)
    repeat {
      value <- reader$next_id()
      if (is.null(value)) break
      values[[length(values) + 1L]] <- value
      if (is.function(after_value)) after_value(length(values))
      stopifnot(length(values) <= 10000L)
    }
    observer$finish(); NULL
  }, error = function(e) list(code = e$code, message = conditionMessage(e), classes = class(e)))
  list(values = values, encodings = vapply(values, Encoding, ""), error = error, requests = requests)
}
.native_axis_decode_compare <- function(json, bytes = 65536L, raw_json = NULL) {
  f <- .native_axis_decode_fixture(json, raw_json); on.exit(f$close(), add = TRUE)
  old <- .native_axis_decode_run(f, old = TRUE, bytes = bytes)
  actual <- .native_axis_decode_run(f, bytes = bytes)
  stopifnot(identical(actual, old))
  actual
}
.native_axis_decode_inventory <- function(root) {
  files <- sort(list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE, no.. = TRUE))
  files <- files[!file.info(files)$isdir]
  setNames(vapply(files, function(path) digest::digest(file = path, algo = "sha256"), ""),
    substring(files, nchar(root) + 2L))
}
.native_axis_decode_FDs <- function(root) {
  if (!dir.exists("/proc/self/fd")) return(character())
  targets <- Sys.readlink(list.files("/proc/self/fd", full.names = TRUE))
  sort(targets[!is.na(targets) & startsWith(targets, paste0(root, "/"))])
}
.native_axis_decode_swap <- function(name, wrapper) {
  ns <- asNamespace("scworkbench"); original <- get(name, ns)
  unlockBinding(name, ns); assign(name, wrapper(original), ns); lockBinding(name, ns)
  function() { unlockBinding(name, ns); assign(name, original, ns); lockBinding(name, ns) }
}

# Literal c8261467da806217a4d8b991c02b07f190d2681a original function; ONLY
# its symbol is renamed. Runtime helpers/admissions/observer remain genuine.
.native_axis_old_c826 <- function(con, rowid, column, budgets, observer) {
  reader <- .wb_matrix_native_text_reader(con, rowid, column, budgets, observer)
  .wb_graph_require(!reader$is_null, "GRAPH_SOURCE_PAYLOAD_INVALID", "Matrix axis JSON is null.")
  buffer <- ""; eof <- FALSE; state <- "start"
  fill <- function() {
    value <- reader$next_chunk()
    if (is.null(value)) eof <<- TRUE else buffer <<- paste0(buffer, value)
  }
  trim <- function() {
    repeat {
      buffer <<- sub("^[ \\t\\r\\n]*", "", buffer, perl = TRUE)
      if (nzchar(buffer) || eof) break
      fill()
    }
  }
  fail <- function() .wb_graph_error("GRAPH_SOURCE_PAYLOAD_INVALID", "Malformed matrix axis JSON array.")
  next_id <- function() {
    if (state == "done") return(NULL)
    trim()
    if (state == "start") {
      if (!startsWith(buffer, "[")) fail()
      buffer <<- substring(buffer, 2L); state <<- "first"; trim()
    }
    if (state == "delimiter") {
      if (startsWith(buffer, ",")) {
        buffer <<- substring(buffer, 2L); state <<- "value"; trim()
      } else if (!startsWith(buffer, "]")) fail()
    }
    if (startsWith(buffer, "]") && state %in% c("first", "delimiter")) {
      buffer <<- substring(buffer, 2L)
      repeat { trim(); if (nzchar(buffer)) fail(); if (eof) break }
      state <<- "done"; return(NULL)
    }
    repeat {
      if (!startsWith(buffer, '"')) fail()
      match <- regexpr('^"(?:[^"\\\\]|\\\\.)*"', buffer, perl = TRUE)
      if (match[[1L]] == 1L) break
      .wb_graph_require(nchar(buffer, type = "bytes") <= 1540L,
        "GRAPH_RESOURCE_EXCEEDED", "Matrix axis scalar exceeds encoded admission.")
      if (eof) fail()
      fill()
    }
    length <- attr(match, "match.length")[[1L]]
    token <- substr(buffer, 1L, length)
    .wb_graph_require(nchar(token, type = "bytes") <= 1540L,
      "GRAPH_RESOURCE_EXCEEDED", "Matrix axis scalar exceeds encoded admission.")
    value <- tryCatch({.wb_operation_pack_v2_assert_strict_json(token); .wb_graph_parse(token)}, error = function(error)
      .wb_graph_error("GRAPH_SOURCE_PAYLOAD_INVALID", conditionMessage(error)))
    .wb_graph_require(.wb_graph_string(value), "GRAPH_SOURCE_PAYLOAD_INVALID", "Invalid matrix axis ID.")
    buffer <<- substring(buffer, length + 1L); state <<- "delimiter"
    value
  }
  list(next_id = next_id)
}

test_engine_native_axis_plain_unicode_and_actual_parser_calls_contract <- function() {
  ids <- c("cell_2", "NA", "null", "TRUE", "0", "-0", "1e-3", "001", "id:/value", " apostrophe' ",
    intToUtf8(127L), intToUtf8(128L), intToUtf8(159L), "é", "東京", intToUtf8(0x2028), intToUtf8(0xfeff))
  json <- paste0("[", paste0('"', ids, '"', collapse = ","), "]")
  for (bytes in c(128L, 65536L, 131072L)) {
    result <- .native_axis_decode_compare(json, bytes)
    stopifnot(is.null(result$error), identical(unlist(result$values, use.names = FALSE), ids),
      max(result$requests) <= max(4L, min(4096L, floor(bytes / 32))))
  }
  f <- .native_axis_decode_fixture(json); on.exit(f$close(), add = TRUE)
  counts <- new.env(parent = emptyenv()); undos <- list()
  on.exit(for (undo in rev(undos)) undo(), add = TRUE, after = FALSE)
  names <- c(".wb_operation_pack_v2_assert_strict_json", ".wb_graph_parse", ".wb_operation_pack_parse_canonical_json")
  for (name in names) {
    counts[[name]] <- 0L
    undos[[length(undos) + 1L]] <- .native_axis_decode_swap(name, local({
      label <- name
      function(original) function(...) { counts[[label]] <- counts[[label]] + 1L; original(...) }
    }))
  }
  actual <- .native_axis_decode_run(f)
  stopifnot(is.null(actual$error), all(vapply(names, function(name) counts[[name]], 0L) == 0L))
  old <- .native_axis_decode_run(f, old = TRUE)
  stopifnot(identical(actual, old), all(vapply(names, function(name) counts[[name]], 0L) == length(ids)))
  TRUE
}

test_engine_native_axis_escaped_fallback_and_error_order_contract <- function() {
  escaped <- c('"line\\nfeed"', '"tab\\tvalue"', '"return\\rvalue"', '"back\\bvalue"',
    '"form\\fvalue"', '"quote\\\"value"', '"slash\\\\value"', '"solidus\\/value"',
    '"\\u0061"', '"\\u00e9"', '"\\uD83E\\uDDEC"', '"\\u2028"', '"\\ufeff"')
  json <- paste0("[", paste(escaped, collapse = ","), "]")
  actual <- .native_axis_decode_compare(json, 128L)
  stopifnot(is.null(actual$error), length(actual$values) == length(escaped))
  f <- .native_axis_decode_fixture(json); on.exit(f$close(), add = TRUE)
  calls <- 0L
  undo <- .native_axis_decode_swap(".wb_operation_pack_v2_assert_strict_json", function(original)
    function(...) { calls <<- calls + 1L; original(...) })
  on.exit(undo(), add = TRUE, after = FALSE)
  stopifnot(is.null(.native_axis_decode_run(f)$error), calls == length(escaped))
  invalid <- c("{}", '"not_array"', "null", '["good",42]', '["good",null]', '["good",true]',
    '["good",]', '["good" "later"]', '["good"] junk', '["good","bad\\q"]',
    '["good","\\uD800"]', '["good","\\uDC00"]', '["good","\\u0000"]',
    '["good","unterminated]', paste0('["good","raw', "\n", 'control"]'), '[""]')
  for (json in invalid) {
    failed <- .native_axis_decode_compare(json, 128L)
    stopifnot(!is.null(failed$error))
  }
  # Existing IDs are returned in order before a later invalid scalar; no suffix
  # reparse/partial-success substitution is allowed.
  failed <- .native_axis_decode_compare('["first","second",42]', 128L)
  stopifnot(identical(unlist(failed$values, use.names = FALSE), c("first", "second")), !is.null(failed$error))
  raw_invalid <- list(c(charToRaw('["ok","'), as.raw(0x80), charToRaw('"]')),
    c(charToRaw('["ok","a'), as.raw(0), charToRaw('b"]')))
  for (bytes in raw_invalid) stopifnot(!is.null(.native_axis_decode_compare("unused", 128L, bytes)$error))
  TRUE
}

test_engine_native_axis_scalar_and_chunk_boundary_contract <- function() {
  scalar <- paste(rep("x", 256L), collapse = "")
  good <- .native_axis_decode_compare(paste0('["', scalar, '"]'), 128L)
  stopifnot(is.null(good$error), identical(good$values, list(scalar)))
  too_long <- .native_axis_decode_compare(paste0('["', scalar, 'x"]'), 128L)
  stopifnot(!is.null(too_long$error), grepl("Invalid matrix axis ID", too_long$error$message, fixed = TRUE))
  escaped256 <- paste(rep("\\u0061", 256L), collapse = "")
  good <- .native_axis_decode_compare(paste0('["', escaped256, '"]'), 128L)
  stopifnot(is.null(good$error), nchar(good$values[[1L]], type = "bytes") == 256L)
  for (encoded_size in c(1540L, 1541L)) {
    token <- paste0('"', paste(rep("\\u0061", 255L), collapse = ""),
      paste(rep("x", encoded_size - 1532L), collapse = ""), '"')
    stopifnot(nchar(token, type = "bytes") == encoded_size)
    error <- .native_axis_decode_compare(paste0("[", token, "]"), 128L)$error
    stopifnot(!is.null(error), grepl(if (encoded_size == 1540L) "Invalid matrix axis ID" else
      "encoded admission", error$message, fixed = TRUE))
  }
  #1023three-byte tokens put the next UTF8 scalar across the real4096byte read.
  prefix <- paste(rep('"p"', 1023L), collapse = ",")
  for (last in c(paste0('"', intToUtf8(0x1f9ec), '"'), '"\\uD83E\\uDDEC"')) {
    json <- paste0("[", prefix, ",", last, "]")
    value <- .native_axis_decode_compare(json, 131072L)
    stopifnot(is.null(value$error), length(value$values) == 1024L,
      identical(value$values[[1024L]], intToUtf8(0x1f9ec)), any(value$requests == 4096L),
      max(value$requests) == 4096L)
  }
  stopifnot(identical(.native_axis_decode_compare("[]")$values, list()),
    !is.null(.native_axis_decode_compare('["ok"]', 127L)$error))
  TRUE
}

test_engine_native_axis_actual_wal_mutation_and_failure_cleanup_contract <- function() {
  f <- .native_axis_decode_fixture('["first","second","third"]'); on.exit(f$close(), add = TRUE)
  DBI::dbGetQuery(f$con, "PRAGMA journal_mode=WAL")
  writer <- DBI::dbConnect(RSQLite::SQLite(), file.path(f$root, "source.sqlite"))
  on.exit(if (DBI::dbIsValid(writer)) DBI::dbDisconnect(writer), add = TRUE, after = FALSE)
  for (old in c(TRUE, FALSE)) {
    changed <- FALSE
    result <- .native_axis_decode_run(f, old = old, after_value = function(index) {
      if (!changed) {
        stopifnot(DBI::dbExecute(writer, "UPDATE matrix_fragments SET note=? WHERE rowid=1", params = list(paste0("changed-", old))) == 1L)
        changed <<- TRUE
      }
    })
    stopifnot(changed, !is.null(result$error), grepl("GRAPH_SOURCE_PAYLOAD_INVALID", result$error$message, fixed = TRUE))
  }
  stopifnot(is.null(.native_axis_decode_run(f)$error))
  DBI::dbDisconnect(writer)
  # Dedicated DELETE-mode malformed source proves repeated failure closes its
  # genuine native observer without changing SQL or any source filesystem byte.
  g <- .native_axis_decode_fixture('["ok",]'); on.exit(g$close(), add = TRUE)
  .native_axis_decode_run(g)
  before_sql <- DBI::dbGetQuery(g$con, "SELECT rowid,* FROM matrix_fragments")
  before <- .native_axis_decode_inventory(g$root); fds <- .native_axis_decode_FDs(g$root)
  for (i in seq_len(8L)) stopifnot(!is.null(.native_axis_decode_run(g, old = i %% 2L == 0L)$error))
  stopifnot(identical(before_sql, DBI::dbGetQuery(g$con, "SELECT rowid,* FROM matrix_fragments")),
    identical(before, .native_axis_decode_inventory(g$root)), identical(fds, .native_axis_decode_FDs(g$root)))
  TRUE
}

test_engine_native_axis_public_getter_identity_and_readonly_purity_contract <- function() {
  required <- c("Matrix", "BPCells")
  if (!all(vapply(required, requireNamespace, logical(1), quietly = TRUE)))
    return(contract_test_skip("Matrix and BPCells are required for actual bounded getter parity"))
  root <- tempfile("native_axis_getter_"); b <- NULL
  on.exit({if (!is.null(b) && DBI::dbIsValid(b$con)) wb_close_bundle(b); unlink(root, recursive = TRUE)}, add = TRUE)
  features <- c("gene_2", "NA", "null", "gène", "東京")
  cells <- c("cell_2", "cell_10", "cell_1", "细胞")
  expected <- matrix(as.double(seq_len(20L)), 5L, 4L, dimnames = list(features, cells))
  b <- wb_init_bundle(root); wb_define_cells(b, cells)
  wb_attach_matrix(b, "counts", Matrix::Matrix(expected, sparse = TRUE))
  stopifnot(wb_finalize_recipient_bundle(b)$ready); wb_close_bundle(b); b <- NULL
  b <- wb_open_bundle(root, read_only = TRUE, validate = FALSE)
  state <- scworkbench:::.wb_manifest_registry_snapshot(b$con)
  wb_matrix_read_features(b, "counts", features, cells)
  before <- .native_axis_decode_inventory(root); fds <- .native_axis_decode_FDs(root)
  stopifnot(isTRUE(scworkbench:::.wb_matrix_bounded_source_verify(b, "counts", .native_axis_decode_policy())))
  actual <- wb_matrix_read_features(b, "counts", features, cells)
  stopifnot(identical(dimnames(actual), dimnames(expected)), identical(as.matrix(actual), expected), isTRUE(b$read_only))
  actual_identity <- scworkbench:::.wb_operation_pack_v3_matrix_slice_content(actual, features, cells)
  reference_identity <- scworkbench:::.wb_operation_pack_v3_matrix_slice_content(expected, features, cells)
  stopifnot(identical(actual_identity, reference_identity), identical(before, .native_axis_decode_inventory(root)),
    identical(state, scworkbench:::.wb_manifest_registry_snapshot(b$con)), identical(fds, .native_axis_decode_FDs(root)))
  TRUE
}
