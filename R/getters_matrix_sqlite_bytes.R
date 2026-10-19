# Private, bounded observation of existing matrix-fragment TEXT. SQLite's
# incremental I/O accepts TEXT directly; no CAST, substr or json_each preimage.
.wb_matrix_native_byte_api_initialize <- function() {
  if (isTRUE(.Call(C_scwb_graph_bytes_api_ready))) return(invisible(TRUE))
  # An isolated in-memory connection avoids disturbing a caller's live cursor.
  # It uses the same RSQLite engine and closes before source observation begins.
  initializer <- DBI::dbConnect(RSQLite::SQLite(), ":memory:",
    loadable.extensions = TRUE, default.extensions = FALSE, cache_size = -64L,
    synchronous = NULL)
  on.exit(DBI::dbDisconnect(initializer), add = TRUE)
  DBI::dbExecute(initializer, "PRAGMA temp_store=FILE;")
  path <- getLoadedDLLs()[["scworkbench"]][["path"]]
  tryCatch(DBI::dbGetQuery(initializer, "SELECT load_extension(?,?);",
    params = list(path, "sqlite3_scwbgraphbytes_init")), error = function(error)
      .wb_graph_error("GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE",
        paste0("RSQLite native byte API initialization failed: ", conditionMessage(error))))
  .wb_graph_require(isTRUE(.Call(C_scwb_graph_bytes_api_ready)),
    "GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE", "RSQLite native byte API was not initialized.")
  version <- DBI::dbGetQuery(initializer, "SELECT sqlite_version() version;")$version[[1L]]
  .wb_graph_require(identical(.Call(C_scwb_graph_bytes_api_version), version),
    "GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE", "Native byte API differs from the owning RSQLite engine.")
  invisible(TRUE)
}

.wb_matrix_native_byte_observer <- function(con) {
  .wb_matrix_native_byte_api_initialize()
  databases <- DBI::dbGetQuery(con, "PRAGMA database_list;")
  path <- databases$file[databases$name == "main"][[1L]]
  if (!nzchar(path)) return(NULL)
  call <- function(symbol, ...) tryCatch(.Call(symbol, ...), error = function(error) {
    message <- conditionMessage(error)
    code <- if (startsWith(message, "GRAPH_RESOURCE_")) sub(":.*", "", message) else
      "GRAPH_SOURCE_PAYLOAD_INVALID"
    .wb_graph_error(code, message)
  })
  pointer <- call(C_scwb_graph_bytes_open, path)
  list(column = function(rowid, column, table = "matrix_fragments") call(C_scwb_graph_bytes_column,
      pointer, as.character(rowid), column, table),
    read = function(offset, count) call(C_scwb_graph_bytes_read, pointer, offset, count),
    numeric = function(rowid, column, table, type, maximum) call(C_scwb_graph_bytes_numeric,
      pointer, as.character(rowid), column, table, type, maximum),
    finish = function() call(C_scwb_graph_bytes_finish, pointer),
    close = function() call(C_scwb_graph_bytes_close, pointer))
}

.wb_matrix_native_text_reader <- function(con, rowid, column, budgets, observer = NULL,
                                         table = "matrix_fragments", allow_blob = FALSE) {
  chunk_bytes <- max(4L, min(4096L, floor(budgets$partition_bytes / 32)))
  .wb_graph_require(budgets$partition_bytes >= 128L, "GRAPH_RESOURCE_EXCEEDED",
    "Native text decoder requires an admitted UTF-8 scalar buffer.")
  if (is.null(observer)) {
    # Only small in-memory diagnostic fixtures use this route. It cannot
    # claim large-source support: admit whole SQLite decoding BEFORE selection.
    size <- DBI::dbGetQuery(con, paste0("SELECT typeof(", column,
      ") type,octet_length(", column, ") bytes FROM matrix_fragments WHERE rowid=?;"),
      params = list(rowid))
    .wb_graph_require(nrow(size) == 1L && size$type[[1L]] %in% c("null", "text"),
      "GRAPH_SOURCE_PAYLOAD_INVALID", "Native column is absent or not text.")
    if (size$type[[1L]] == "null") return(list(is_null = TRUE, next_chunk = function() NULL))
    .wb_graph_require(size$bytes[[1L]] <= budgets$partition_bytes,
      "GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE", "Large in-memory matrix TEXT has no incremental file reader.")
    value <- DBI::dbGetQuery(con, paste0("SELECT ", column,
      " value FROM matrix_fragments WHERE rowid=?;"), params = list(rowid))$value[[1L]]
    remaining <- charToRaw(enc2utf8(value))
    read <- function() {
      if (!length(remaining)) return(raw())
      n <- min(length(remaining), chunk_bytes)
      part <- remaining[seq_len(n)]
      remaining <<- if (n == length(remaining)) raw() else remaining[-seq_len(n)]
      part
    }
  } else {
    size <- observer$column(rowid, column, table)
    if (is.null(size)) return(list(is_null = TRUE, next_chunk = function() NULL))
    .wb_graph_require(attr(size, "wb_sqlite_type") %in%
      if (allow_blob) c("text", "blob") else "text",
      "GRAPH_SOURCE_PAYLOAD_INVALID", "Expected native TEXT storage.")
    size <- as.integer(size)
    offset <- 0
    read <- function() {
      n <- min(chunk_bytes, size - offset)
      if (!n) return(raw())
      part <- observer$read(offset, n)
      offset <<- offset + n
      part
    }
  }
  pending <- raw()
  next_chunk <- function() {
    repeat {
      part <- read()
      value <- c(pending, part); pending <<- raw()
      if (!length(value)) return(NULL)
      # Preserve a split UTF-8 codepoint across bounded byte reads. The final
      # iconv check rejects overlong sequences, surrogates and invalid continuations.
      end <- length(value)
      lead <- end
      while (lead > 1L && as.integer(value[[lead]]) >= 128L &&
          as.integer(value[[lead]]) <= 191L) lead <- lead - 1L
      byte <- as.integer(value[[lead]])
      width <- if (byte >= 240L && byte <= 244L) 4L else
        if (byte >= 224L && byte <= 239L) 3L else if (byte >= 194L && byte <= 223L) 2L else 1L
      if (end - lead + 1L < width) {
        .wb_graph_require(length(part) > 0L, "GRAPH_SOURCE_PAYLOAD_INVALID", "Truncated native UTF-8 sequence.")
        pending <<- value[seq.int(lead, end)]
        value <- if (lead == 1L) raw() else value[seq_len(lead - 1L)]
      }
      if (!length(value)) next
      .wb_graph_require(!any(value == as.raw(0)), "GRAPH_SOURCE_PAYLOAD_INVALID", "Native TEXT contains NUL.")
      text <- rawToChar(value)
      .wb_graph_require(!is.na(iconv(text, from = "UTF-8", to = "UTF-8")),
        "GRAPH_SOURCE_PAYLOAD_INVALID", "Native TEXT is not valid UTF-8.")
      Encoding(text) <- "UTF-8"
      return(text)
    }
  }
  list(is_null = FALSE, next_chunk = next_chunk)
}

# Consume only an array of admitted string IDs, retaining original order.
# Whole-array JSON parsers (including SQLite json_each) allocate source axes.
.wb_matrix_native_axis_reader <- function(con, rowid, column, budgets, observer) {
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
    # The existing lexer has isolated one COMPLETE quoted token, and its
    # bounded native reader has already checked UTF-8/no NUL. With neither
    # escapes nor raw JSON controls, decoding is exactly removal of the two
    # quotes; general object grammar and numeric decoration add no authority.
    # Every other token retains the exact old strict decoder and diagnostics.
    plain <- !grepl("\\", token, fixed = TRUE) &&
      !grepl("[\\x00-\\x1F]", token, perl = TRUE, useBytes = TRUE)
    value <- if (plain) substr(token, 2L, nchar(token) - 1L) else
      tryCatch({.wb_operation_pack_v2_assert_strict_json(token); .wb_graph_parse(token)}, error = function(error)
        .wb_graph_error("GRAPH_SOURCE_PAYLOAD_INVALID", conditionMessage(error)))
    .wb_graph_require(.wb_graph_string(value), "GRAPH_SOURCE_PAYLOAD_INVALID", "Invalid matrix axis ID.")
    buffer <<- substring(buffer, length + 1L); state <<- "delimiter"
    value
  }
  list(next_id = next_id)
}
