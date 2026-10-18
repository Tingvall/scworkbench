.engine_matrix_number_old <- function(x) {
  if (!is.finite(x)) stop("Canonical matrix values must be finite.", call. = FALSE)
  if (x == 0) return("0")
  text <- trimws(formatC(x, digits = 15L, format = "g", flag = ""))
  negative <- startsWith(text, "-")
  if (negative) text <- substring(text, 2L)
  parts <- strsplit(text, "[eE]")[[1L]]
  exponent <- if (length(parts) == 2L) as.integer(parts[[2L]]) else 0L
  coefficient <- strsplit(parts[[1L]], ".", fixed = TRUE)[[1L]]
  before <- nchar(coefficient[[1L]], type = "bytes")
  digits <- paste0(coefficient, collapse = "")
  first <- regexpr("[1-9]", digits)[[1L]]
  last <- max(gregexpr("[1-9]", digits)[[1L]])
  adjusted <- exponent + before - first
  if (adjusted < -307 || adjusted > 308)
    stop("Canonical matrix number is outside the supported exponent range.", call. = FALSE)
  significant <- substr(digits, first, last)
  paste0(if (negative) "-" else "", substr(significant, 1L, 1L),
    if (nchar(significant) > 1L) paste0(".", substring(significant, 2L)) else "",
    "e", adjusted)
}

.engine_matrix_number_records <- function(rows, columns, values, first = TRUE) {
  paste(vapply(seq_along(values), function(i) paste0(
    if (i == 1L && first) "" else ",", '{"column":', .engine_matrix_number_old(columns[[i]]),
    ',"row":', .engine_matrix_number_old(rows[[i]]), ',"value":',
    if (is.logical(values)) if (values[[i]]) "true" else "false" else
      .engine_matrix_number_old(values[[i]]), "}"), character(1)), collapse = "")
}

.engine_matrix_number_append <- function(rows, columns, values, first = TRUE, prefix = raw()) {
  path <- tempfile("matrix_token_reuse_")
  on.exit(unlink(path), add = TRUE)
  writeBin(prefix, path)
  error <- tryCatch({.Call(get("C_scwb_matrix_slice_append", asNamespace("scworkbench")),
    path, as.integer(rows), as.integer(columns), values, first); NULL}, error = identity)
  list(bytes = readBin(path, "raw", n = file.info(path)$size), error = error)
}

test_engine_matrix_number_token_reuse_bytes_and_evictions_contract <- function() {
  # Quarter-integer values have identical low/mixed slot bits, forcing repeated
  # collisions/evictions. Full uint64 keys, not the slot, determine a hit.
  collisions <- rep(seq_len(130L) + .25, 3L)
  cases <- list(rep(log1p(10000 / 123456), 1024L), collisions,
    rep(c(-.25, -.75, -1.25, .25, .75, 0, -0), 40L),
    c(1e-307, -1e-307, 1e308, -.Machine$double.xmax, 1.00000000000001,
      9.99999999999999e-7),
    as.double(c(1L, 10L, 101L, .Machine$integer.max)),
    rep(c(TRUE, FALSE), 64L))
  for (values in cases) {
    rows <- as.integer(rep(c(1, 10, 101), length.out = length(values)))
    columns <- as.integer(rep(c(1, 2, 99), length.out = length(values)))
    expected <- charToRaw(.engine_matrix_number_records(rows, columns, values))
    actual <- .engine_matrix_number_append(rows, columns, values)
    stopifnot(is.null(actual$error), identical(actual$bytes, expected),
      identical(digest::digest(actual$bytes, algo = "sha256", serialize = FALSE),
        digest::digest(expected, algo = "sha256", serialize = FALSE)))
  }
  # No table survives one append: later calls always observe changed values.
  a <- .engine_matrix_number_append(1L, 1L, 1.25)
  b <- .engine_matrix_number_append(1L, 1L, 1.75)
  stopifnot(!identical(a$bytes, b$bytes),
    identical(b$bytes, charToRaw(.engine_matrix_number_records(1L, 1L, 1.75))))
  TRUE
}

test_engine_matrix_number_token_reuse_complete_identity_contract <- function() {
  old_seed <- get0(".Random.seed", globalenv(), inherits = FALSE)
  on.exit(if (is.null(old_seed)) {
    if (exists(".Random.seed", globalenv(), inherits = FALSE)) rm(".Random.seed", envir = globalenv())
  } else assign(".Random.seed", old_seed, globalenv()), add = TRUE)
  set.seed(719L)
  cases <- list(matrix(rep(c(0, log1p(10000 / 123456), log1p(20000 / 123456)),
    length.out = 323L), 17L), matrix(runif(323L, -100, 100), 17L))
  stream <- get(".wb_operation_pack_matrix_stream_identity", asNamespace("scworkbench"))
  for (values in cases) {
    features <- paste0("f", seq_len(nrow(values))); cells <- paste0("c", seq_len(ncol(values)))
    at <- which(values != 0, arr.ind = TRUE)
    entries <- .engine_matrix_number_records(at[, 1L], at[, 2L], as.double(values[at]))
    # Independent frozen row/column/entry framing; no engine canonical helper
    # or native formatter participates in this full-preimage oracle.
    preimage <- paste0('{"cell_id":', jsonlite::toJSON(cells),
      ',"dimensions":[', .engine_matrix_number_old(nrow(values)), ",",
      .engine_matrix_number_old(ncol(values)), '],"entries":[', entries,
      '],"feature_id":', jsonlite::toJSON(features),
      ',"kind":"matrix","schema":"scworkbench.operation_pack.matrix_slice.content.v1"}')
    expected <- digest::digest(preimage, algo = "sha256", serialize = FALSE)
    for (chunk in c(1L, 3L, 128L)) {
      actual <- stream(features, cells, function(columns) values[, columns, drop = FALSE], chunk)
      stopifnot(identical(actual$sha256, expected),
        actual$scheme == "scworkbench.operation_pack.matrix_slice.content.v1")
    }
  }
  TRUE
}

test_engine_matrix_number_token_reuse_error_and_prefix_contract <- function() {
  for (bad in c(NA_real_, NaN, Inf, -Inf, .Machine$double.xmin, 5e-324)) {
    for (position in c(1L, 3001L)) {
      values <- rep(1.25, 3001L); values[[position]] <- bad
      rows <- rep(1L, length(values)); columns <- rep(1L, length(values))
      actual <- .engine_matrix_number_append(rows, columns, values, prefix = charToRaw("prefix"))
      expected_error <- tryCatch(.engine_matrix_number_old(bad), error = identity)
      # Frozen append buffering: only complete previously flushed64KiB batches
      # survive a later formatter error; the current native buffer is discarded.
      flushed <- "prefix"; buffer <- ""
      if (position > 1L) for (i in seq_len(position - 1L)) {
        record <- .engine_matrix_number_records(1L, 1L, values[[i]], first = i == 1L)
        if (nchar(buffer, type = "bytes") + nchar(record, type = "bytes") > 65536L) {
          flushed <- paste0(flushed, buffer); buffer <- ""
        }
        buffer <- paste0(buffer, record)
      }
      stopifnot(inherits(actual$error, "error"), inherits(expected_error, "error"),
        identical(conditionMessage(actual$error), conditionMessage(expected_error)),
        identical(actual$bytes, charToRaw(flushed)))
      retry <- .engine_matrix_number_append(1L, 1L, 1.25)
      stopifnot(is.null(retry$error), identical(retry$bytes,
        charToRaw(.engine_matrix_number_records(1L, 1L, 1.25))))
    }
  }
  invalid <- .engine_matrix_number_append(1L, 1L, 1L)
  stopifnot(inherits(invalid$error, "error"),
    identical(conditionMessage(invalid$error), "Invalid matrix identity append vectors."))
  TRUE
}
