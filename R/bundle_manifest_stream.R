# Preserve registry-table.v1: same row order, jsonlite formatting, SQL-query
# type promotion, logical 5000-row chunks and previous/rows_sha256 framing.
# Only physical reads and JSON emission change. Large TEXT/BLOB is never fetched
# through RSQLite or sent to jsonlite as a whole column/cell/chunk.
.wb_manifest_observation_resources <- function(con, budgets) {
  restore <- .wb_graph_aggregate_connection_budget(list(con), budgets)
  observer <- NULL; windows <- NULL; ready <- FALSE
  close <- function() {
    # Each resource unwinds independently even if an earlier close reports an
    # error; never strand the caller's cache/policy reservation on that path.
    on.exit(restore(), add = TRUE)
    on.exit(if (!is.null(observer)) observer$close(), add = TRUE, after = FALSE)
    if (!is.null(windows) && DBI::dbIsValid(windows)) DBI::dbDisconnect(windows)
  }
  on.exit(if (!ready) close(), add = TRUE)
  observer <- .wb_matrix_native_byte_observer(con)
  if (is.null(observer)) return(NULL)
  windows <- .wb_sqlite_aux_read_connect(con,
    bigint = con@bigint, extended_types = con@extended_types)
  DBI::dbExecute(windows, "PRAGMA cache_size=-64;")
  DBI::dbExecute(windows, "PRAGMA temp_store=FILE;")
  # Small in-memory chunks create no token spill, but the snapshot still owns
  # aggregate FD/scratch/session-copy admission at both lifecycle boundaries.
  .wb_graph_spill_admit(budgets)
  finish <- observer$finish
  observer$finish <- function() {
    .wb_graph_spill_admit(budgets)
    finish()
  }
  attr(observer, "wb_manifest_spill_boundaries") <- TRUE
  ready <- TRUE
  list(observer = observer, windows = windows, close = close)
}

.wb_manifest_small_chunk_bound <- function(rows, storage_types, key_tokens, budgets) {
  nr <- nrow(rows); nc <- ncol(rows)
  # Reject dimensions before creating any row-sized escaping/type vectors.
  carrier <- 4096 + 1024 * nc + 256 * nr * nc + 128 * nr
  if (!nr || !nc || !is.finite(carrier) || carrier > 8 * budgets$partition_bytes) return(NULL)
  if (any(vapply(storage_types, function(types)
      any(types %in% c("text_deferred", "blob_deferred")), logical(1)))) return(NULL)
  encoded <- 2 + max(0, nr - 1) + nr * (2 + max(0, nc - 1) +
    sum(nchar(key_tokens, type = "bytes") + 1))
  for (column in rows) {
    # Only actual SQLite scalar columns or its documented extended types.
    # Unknown/list/custom columns retain the existing streaming route.
    if (!is.atomic(column) || !typeof(column) %in% c("integer", "double", "logical", "character") ||
        (is.object(column) && !inherits(column, c("Date", "POSIXct", "difftime", "integer64"))))
      return(NULL)
    if (is.character(column)) {
      bytes <- nchar(column, type = "bytes")
      encoded <- encoded + sum(ifelse(is.na(bytes), 4, 6 * bytes + 2))
    } else {
      # Generous bound for jsonlite's finite/nonfinite/NA, signed int64 and
      # DATE/TIME/TIMESTAMP scalar representations; options/types stay unchanged.
      encoded <- encoded + sum(ifelse(is.na(column), 4, 512))
    }
    if (!is.finite(encoded) || carrier + 8 * encoded > 8 * budgets$partition_bytes ||
        encoded > as.numeric(budgets$token_bytes)) return(NULL)
  }
  # Cover the selected dataframe/type vectors, sanitizer/serializer carriers,
  # scalar lists, bounds and hash intermediates separately from fetched rows.
  reservation <- carrier + 8 * encoded
  if (!is.finite(reservation) || reservation > 8 * budgets$partition_bytes ||
      encoded > as.numeric(budgets$token_bytes)) return(NULL)
  list(carrier_bytes = carrier, encoded_bytes = encoded,
    reservation_bytes = reservation)
}

.wb_manifest_table_identity <- function(con, table, chunk_size = 5000L,
                                       observer = NULL, budgets = list(), windows = NULL) {
  budgets <- .wb_graph_effective_budgets(con, budgets)
  if (RSQLite::sqliteIsTransacting(con) || con@dbname %in% c("", ":memory:")) {
    .wb_graph_require(is.null(con@ref$wb_graph_policy), "GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE",
      "Bounded manifest observation requires committed file-backed state.")
    return(.wb_manifest_table_identity_materialized(con, table, chunk_size))
  }
  owned <- is.null(observer)
  if (owned) {
    resources <- .wb_manifest_observation_resources(con, budgets)
    if (is.null(resources)) return(.wb_manifest_table_identity_materialized(con, table, chunk_size))
    on.exit(resources$close(), add = TRUE)
    observer <- resources$observer
    windows <- resources$windows
  }
  fields <- DBI::dbGetQuery(con, paste0("PRAGMA table_info(", DBI::dbQuoteIdentifier(con, table), ");"))
  # Expressions lose SQLite declared-type metadata. Capture only empty
  # prototypes so extended DATE/TIME/TIMESTAMP classes retain their original
  # jsonlite representation without reading any source values.
  prototypes <- if (isTRUE(con@extended_types)) DBI::dbGetQuery(con,
    paste0("SELECT * FROM ", DBI::dbQuoteIdentifier(con, table), " WHERE 0;")) else NULL
  header <- list(schema = "scworkbench.manifest.registry-table.v1", table = table,
    columns = fields[, intersect(c("name", "type", "notnull", "pk"), names(fields)), drop = FALSE])
  state <- .wb_prov_sha256_object(header)
  count <- DBI::dbGetQuery(con, paste0("SELECT COUNT(*) n FROM ",
    DBI::dbQuoteIdentifier(con, table), ";"))$n[[1L]]
  rows_admitted <- min(as.numeric(count), chunk_size)
  .wb_graph_require(rows_admitted * (24 * nrow(fields) + 32) +
    budgets$sqlite_cache_kib * 1024 + 8 * budgets$partition_bytes + 65536 <=
      as.numeric(budgets$memory_bytes), "GRAPH_RESOURCE_EXCEEDED",
    "Manifest projected type carriers exceed working-memory admission.")
  if (!count) {
    if (owned) observer$finish()
    return(list(row_count = 0L, content_sha256 = state))
  }
  quoted <- as.character(DBI::dbQuoteIdentifier(con, fields$name))
  projected <- vapply(quoted, function(column) paste0("CASE typeof(", column,
    ") WHEN 'text' THEN CASE WHEN octet_length(", column, ")<=256 THEN ", column,
    " ELSE '' END WHEN 'blob' THEN zeroblob(0) ELSE ", column, " END"), character(1))
  types <- paste0("CASE WHEN typeof(", quoted, ")='text' AND octet_length(", quoted,
    ")>256 THEN 'text_deferred' WHEN typeof(", quoted,
    ")='blob' THEN 'blob_deferred' ELSE typeof(", quoted, ") END")
  if (is.null(windows)) {
    windows <- .wb_sqlite_aux_read_connect(con,
      bigint = con@bigint, extended_types = con@extended_types)
    on.exit(DBI::dbDisconnect(windows), add = TRUE)
    DBI::dbExecute(windows, "PRAGMA cache_size=-64;")
    DBI::dbExecute(windows, "PRAGMA temp_store=FILE;")
  }
  text_charge <- paste(vapply(quoted, function(column) paste0("CASE WHEN typeof(", column,
    ")='text' AND octet_length(", column, ")<=256 THEN octet_length(", column,
    ")+64 ELSE 0 END"), character(1)), collapse = "+")
  # Projection substitutes only variable-width carriers, preserving every
  # storage type and original numeric value. One live cursor preserves RSQLite's
  # late type promotion across fetch boundaries exactly as the original query.
  query <- DBI::dbSendQuery(con, paste0("SELECT rowid,", paste(c(projected,
    types), collapse = ","), " FROM ",
    DBI::dbQuoteIdentifier(con, table), " ORDER BY rowid;"))
  on.exit(if (!is.null(query)) DBI::dbClearResult(query), add = TRUE)
  n <- 0L
  key_tokens <- vapply(fields$name, function(name)
    as.character(jsonlite::toJSON(name, auto_unbox = TRUE)), character(1))
  scalar_token <- function(rows, i, j) {
    row <- rows[i, j, drop = FALSE]; names(row) <- fields$name[[j]]
    json <- as.character(jsonlite::toJSON(.wb_json_sanitize(row), dataframe = "rows",
      auto_unbox = TRUE, null = "null", na = "null"))
    prefix <- paste0("[{", key_tokens[[j]], ":")
    .wb_graph_require(startsWith(json, prefix) && endsWith(json, "}]"),
      "GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE", "Unsupported manifest scalar framing.")
    substr(json, nchar(prefix) + 1L, nchar(json) - 2L)
  }
  emit_text <- function(rowid, column, emit) {
    reader <- .wb_matrix_native_text_reader(con, rowid, column, budgets, observer, table,
      allow_blob = TRUE)
    emit('"')
    repeat {
      chunk <- reader$next_chunk()
      if (is.null(chunk)) break
      escaped <- as.character(jsonlite::toJSON(chunk, auto_unbox = TRUE))
      emit(substr(escaped, 2L, nchar(escaped) - 1L))
    }
    emit('"')
  }
  emit_blob <- function(size, emit) {
    emit('"'); offset <- 0
    line_chars <- 0L
    chunk_size <- max(3L, 3L * floor(min(4095L, budgets$partition_bytes / 8) / 3L))
    repeat {
      bytes <- min(chunk_size, as.numeric(size) - offset)
      if (!bytes) break
      encoded <- as.character(openssl::base64_encode(observer$read(offset, bytes)))
      # jsonlite's raw-vector encoder inserts a newline every 72 base64
      # characters, including a final complete line. Preserve those escaped
      # newlines across independent incremental byte chunks.
      position <- 1L
      while (position <= nchar(encoded)) {
        width <- min(72L - line_chars, nchar(encoded) - position + 1L)
        emit(substr(encoded, position, position + width - 1L))
        position <- position + width; line_chars <- line_chars + width
        if (line_chars == 72L) {emit("\\n"); line_chars <- 0L}
      }
      offset <- offset + bytes
    }
    emit('"')
  }
  after <- NULL
  repeat {
    if (n == count) break
    admission <- DBI::dbGetQuery(windows, paste0("SELECT COUNT(*) n,COALESCE(SUM(charge),0) bytes FROM ",
      "(SELECT ", text_charge, " charge FROM ", DBI::dbQuoteIdentifier(con, table),
      if (is.null(after)) "" else " WHERE rowid>?", " ORDER BY rowid LIMIT ?);"),
      params = c(if (is.null(after)) list() else list(after), list(as.integer(chunk_size))))
    .wb_graph_require(as.numeric(admission$n[[1L]]) * (24 * nrow(fields) + 32) +
      as.numeric(admission$bytes[[1L]]) + budgets$sqlite_cache_kib * 1024 +
      8 * budgets$partition_bytes + 65536 <= as.numeric(budgets$memory_bytes),
      "GRAPH_RESOURCE_EXCEEDED", "Manifest scalar/type carriers exceed admission before decoding.")
    batch <- DBI::dbFetch(query, n = as.integer(chunk_size))
    .wb_graph_require(nrow(batch) > 0L, "GRAPH_SOURCE_PAYLOAD_INVALID",
      "Manifest cursor ended before its admitted row count.")
    .wb_graph_require(nrow(batch) == min(chunk_size, count - n),
      "GRAPH_SOURCE_PAYLOAD_INVALID",
      "Manifest logical chunk did not match its admitted row count.")
    n <- n + nrow(batch)
    .wb_graph_require(n <= count, "GRAPH_SOURCE_PAYLOAD_INVALID",
      "Manifest cursor exceeded its admitted row count.")
    after <- bit64::as.integer64(utils::tail(batch[[1L]], 1L))
    rows <- batch[seq.int(2L, nrow(fields) + 1L)]
    names(rows) <- fields$name
    if (!is.null(prototypes)) for (j in seq_len(nrow(fields))) {
      if (inherits(prototypes[[j]], c("Date", "POSIXct", "difftime"))) {
        rows[[j]] <- as.numeric(rows[[j]])
        attributes(rows[[j]]) <- attributes(prototypes[[j]])
      }
    }
    small <- if (isTRUE(attr(observer, "wb_manifest_spill_boundaries", exact = TRUE)))
      .wb_manifest_small_chunk_bound(rows,
        batch[seq.int(nrow(fields) + 2L, 2L * nrow(fields) + 1L)], key_tokens, budgets) else NULL
    if (!is.null(small)) {
      .wb_graph_storage_fault("manifest_small_chunk", c(list(con = con, table = table,
        budgets = budgets, rows = nrow(batch), decoded_reservation_bytes = 8 * budgets$partition_bytes,
        fetched_carrier_bytes = as.numeric(admission$n[[1L]]) * (24 * nrow(fields) + 32) +
          as.numeric(admission$bytes[[1L]])), small))
      json <- enc2utf8(as.character(jsonlite::toJSON(.wb_json_sanitize(rows),
        dataframe = "rows", auto_unbox = TRUE, null = "null", na = "null")))
      .wb_graph_require(nchar(json, type = "bytes") <= small$encoded_bytes &&
        nchar(json, type = "bytes") <= as.numeric(budgets$token_bytes),
        "GRAPH_RESOURCE_EXCEEDED", "Manifest small chunk exceeded pre-admitted encoded size.")
      sha <- digest::digest(json, algo = "sha256", serialize = FALSE)
    } else sha <- .wb_graph_token_hash(function(emit) {
      emit("[")
      i <- 1L
      key_charge <- 2 + sum(nchar(key_tokens, type = "bytes") + 2L) + max(0L, nrow(fields) - 1L)
      while (i <= nrow(batch)) {
        if (i > 1L) emit(",")
        # Only already admitted scalar carriers enter this fast path. Huge
        # fields retain the existing incremental byte-reader path unchanged.
        first_deferred <- any(vapply(seq_len(nrow(fields)), function(j)
          batch[[nrow(fields) + 1L + j]][[i]] %in% c("text_deferred", "blob_deferred"), logical(1)))
        candidate_limit <- min(512L, budgets$partition_rows, nrow(batch) - i + 1L)
        if (!first_deferred && 4096 + 576 * nrow(fields) +
          64 * candidate_limit <= 8 * budgets$partition_bytes) {
          candidate <- seq.int(i, i + candidate_limit - 1L)
          eligible <- rep(TRUE, length(candidate))
          charge <- rep(key_charge, length(candidate))
          for (j in seq_len(nrow(fields))) {
            eligible <- eligible & !batch[[nrow(fields) + 1L + j]][candidate] %in%
              c("text_deferred", "blob_deferred")
            scalar_charge <- if (is.character(rows[[j]])) {
              bytes <- nchar(rows[[j]][candidate], type = "bytes")
              ifelse(is.na(bytes), 4, 6 * bytes + 2)
            } else if (is.integer(rows[[j]]) && !is.object(rows[[j]]) &&
                is.null(attributes(rows[[j]]))) {
              # Ordinary SQLite int32: sign + at most ten decimal digits.
              # Extended integer64/date/time and doubles keep the old bound.
              ifelse(is.na(rows[[j]][candidate]), 4, 16)
            } else if (is.list(rows[[j]])) rep(512, length(candidate)) else
              ifelse(is.na(rows[[j]][candidate]), 4, 512)
            charge <- charge + scalar_charge
          }
          # Worst-case JSON escaping (six bytes per source byte), numeric,
          # date/time and small coerced raw-vector representations are charged
          # before serializing. The output/copies fit within the existing
          # eight-partition reservation. No logical hash chunk is changed.
          admissible <- cumprod(eligible) == 1L & cumsum(charge) <= budgets$partition_bytes / 2
          take <- sum(admissible)
          # Bound the selected dataframe/list/type carriers plus row indices,
          # eligibility/charge vectors and serializer intermediates separately
          # from the live fetched batch (which was admitted above).
          while (take > 0L) {
            carrier_bytes <- 4096 + 512 * nrow(fields) + 16 * take * nrow(fields) +
              32 * take + 64 * length(candidate) + 64 * nrow(fields)
            encoded_bytes <- sum(charge[seq_len(take)]) + 2L
            batch_reservation <- carrier_bytes + 8 * encoded_bytes
            if (batch_reservation <= 8 * budgets$partition_bytes) break
            take <- take - 1L
          }
          if (take > 0L) {
            selected <- candidate[seq_len(take)]
            .wb_graph_storage_fault("manifest_scalar_batch", list(con = con, table = table,
              budgets = budgets, rows = take, carrier_bytes = carrier_bytes,
              encoded_bytes = encoded_bytes, reservation_bytes = batch_reservation,
              decoded_reservation_bytes = 8 * budgets$partition_bytes,
              fetched_carrier_bytes = as.numeric(admission$n[[1L]]) * (24 * nrow(fields) + 32) +
                as.numeric(admission$bytes[[1L]])))
            json <- as.character(jsonlite::toJSON(.wb_json_sanitize(rows[selected, , drop = FALSE]),
              dataframe = "rows", auto_unbox = TRUE, null = "null", na = "null"))
            .wb_graph_require(nchar(json, type = "bytes") <= sum(charge[seq_len(take)]) + 2L,
              "GRAPH_RESOURCE_EXCEEDED", "Manifest scalar batch exceeded pre-admitted encoded size.")
            emit(substr(json, 2L, nchar(json) - 1L))
            i <- i + take
            next
          }
        }
        emit("{")
        for (j in seq_len(nrow(fields))) {
          if (j > 1L) emit(",")
          emit(key_tokens[[j]]); emit(":")
          kind <- batch[[nrow(fields) + 1L + j]][[i]]
          if (kind %in% c("text_deferred", "blob_deferred") && is.character(rows[[j]])) {
            emit_text(batch[[1L]][[i]], fields$name[[j]], emit)
          } else if (kind %in% c("text_deferred", "blob_deferred") && is.list(rows[[j]])) {
            size <- observer$column(batch[[1L]][[i]], fields$name[[j]], table)
            emit_blob(size, emit)
          } else if (kind %in% c("text_deferred", "blob_deferred")) {
            size <- observer$column(batch[[1L]][[i]], fields$name[[j]], table)
            class <- if (inherits(rows[[j]], c("Date", "POSIXct", "difftime"))) "numeric" else
              if (inherits(rows[[j]], "integer64")) "integer64" else
              if (is.integer(rows[[j]])) "integer" else if (is.numeric(rows[[j]])) "numeric" else "unsupported"
            value <- observer$numeric(batch[[1L]][[i]], fields$name[[j]], table,
              class, budgets$partition_bytes)
            if (class == "integer64") value <- bit64::as.integer64(value)
            rows[i, j] <- value
            emit(scalar_token(rows, i, j))
          } else emit(scalar_token(rows, i, j))
        }
        emit("}")
        i <- i + 1L
      }
      emit("]")
    }, budgets)
    state <- .wb_prov_sha256_object(list(previous = state, rows_sha256 = sha))
    .wb_graph_storage_fault("manifest_chunk", list(con = con, table = table,
      rows = nrow(batch), after = as.character(after), budgets = budgets))
  }
  .wb_graph_require(n == count, "GRAPH_SOURCE_PAYLOAD_INVALID",
    "Manifest cursor did not cover its admitted row count.")
  DBI::dbClearResult(query)
  query <- NULL
  if (owned) {
    observer$finish()
  }
  list(row_count = as.integer(n), content_sha256 = state)
}
