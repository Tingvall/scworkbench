.owned_csc_native <- function(path, x, nr = nrow(x), nc = ncol(x))
  .Call(get("C_scwb_matrix_slice_csc_append", asNamespace("scworkbench")),
    path, x, as.integer(nr), as.integer(nc))
.owned_csc_fixture <- function() {
  loadNamespace("Matrix")
  methods::new("dgCMatrix", i = as.integer(seq_len(8197L) - 1L),
    p = c(0L, 8197L, 8197L), Dim = c(8197L, 2L),
    x = rep(c(1.25, -.75, pi, 1e-307, 1e308), length.out = 8197L))
}
.owned_csc_legacy <- function() {
  env <- new.env(parent = globalenv())
  sys.source("tests/test_engine_matrix_number_token_reuse_contract.R", env)
  env$.engine_matrix_number_records
}
.owned_csc_stream <- function(file_sink = FALSE) {
  fn <- get(".wb_operation_pack_matrix_stream_identity", asNamespace("scworkbench"))
  if (file_sink) {
    env <- new.env(parent = environment(fn))
    env$.wb_operation_pack_matrix_digest_open <- function() NULL
    environment(fn) <- env
  }
  fn
}

test_engine_owned_csc_literal_bytes_and_source_purity_contract <- function() {
  x <- .owned_csc_fixture()
  x@x[1:4] <- c(NA_real_, NaN, 0, -0)
  before <- serialize(x, NULL)
  keep <- which(!is.na(x@x) & x@x != 0)
  columns <- rep.int(seq_len(ncol(x)), diff(x@p))
  expected <- charToRaw(.owned_csc_legacy()(x@i[keep] + 1L,
    as.integer(columns[keep]), x@x[keep]))
  stopifnot(length(expected) > 65536L)
  path <- tempfile("owned_csc_bytes_"); on.exit(unlink(path), add = TRUE)
  writeBin(raw(), path)
  stopifnot(isTRUE(.owned_csc_native(path, x)),
    identical(readBin(path, "raw", n = file.info(path)$size), expected),
    identical(serialize(x, NULL), before))
  # Re-reading a changed current object must not reuse a prior token/identity.
  x@x[[5L]] <- 1.75
  writeBin(raw(), path)
  stopifnot(isTRUE(.owned_csc_native(path, x)),
    !identical(readBin(path, "raw", n = file.info(path)$size), expected))
  TRUE
}

test_engine_owned_csc_complete_identity_and_callback_contract <- function() {
  x <- methods::new("dgCMatrix", i = c(0L, 2L, 1L), p = c(0L, 2L, 2L, 3L),
    x = c(1.25, -3, 1e-307), Dim = c(3L, 3L))
  features <- c("f2", "雪\\\"", "f1"); cells <- c("c10", "c1\n", "c2")
  before <- serialize(x, NULL)
  for (file_sink in c(FALSE, TRUE)) {
    stream <- .owned_csc_stream(file_sink)
    expected <- stream(features, cells, function(columns) x[, columns, drop = FALSE], 1L)
    calls <- 0L
    actual <- stream(features, cells, function(columns) {
      calls <<- calls + 1L; stop("owned literal callback should not run")
    }, 1L, .owned_csc = x)
    stopifnot(identical(actual, expected), calls == 0L)
    for (values in list(matrix(c(TRUE, FALSE, NA, TRUE), 2L),
        matrix(numeric(), 0L, 3L), matrix(numeric(), 3L, 0L),
        Matrix::Matrix(matrix(c(1, 2, 2, 3), 2L), sparse = TRUE))) {
      f <- paste0("f", seq_len(nrow(values))); cell_ids <- paste0("c", seq_len(ncol(values)))
      if (!nrow(values)) f <- character()
      if (!ncol(values)) cell_ids <- character()
      calls <- 0L
      expected <- stream(f, cell_ids, function(columns) values[, columns, drop = FALSE], 1L)
      actual <- stream(f, cell_ids, function(columns) {
        calls <<- calls + 1L; values[, columns, drop = FALSE]
      }, 1L, .owned_csc = values)
      stopifnot(identical(actual, expected), calls == ncol(values))
    }
  }
  stopifnot(identical(serialize(x, NULL), before))
  TRUE
}

test_engine_owned_csc_decline_before_emission_contract <- function() {
  x <- methods::new("dgCMatrix", i = c(0L, 2L), p = c(0L, 2L),
    x = c(1.25, -3), Dim = c(3L, 1L))
  cases <- replicate(8L, x, simplify = FALSE)
  attr(cases[[1L]], "unknown") <- TRUE
  cases[[2L]]@p <- c(1L, 2L)
  cases[[3L]]@p <- c(0L, 3L)
  cases[[4L]]@i <- c(2L, 0L)
  cases[[5L]]@i <- c(0L, 0L)
  cases[[6L]]@i <- c(0L, NA_integer_)
  cases[[7L]]@x <- c(1.25)
  cases[[8L]]@factors <- list(opaque = new.env())
  path <- tempfile("owned_csc_decline_"); on.exit(unlink(path), add = TRUE)
  prefix <- charToRaw("prefix"); writeBin(prefix, path)
  for (value in cases) {
    stopifnot(identical(.owned_csc_native(path, value), FALSE),
      identical(readBin(path, "raw", n = file.info(path)$size), prefix))
    # Rejected carrier never reaches native indexing. Its original callback
    # path is still available; do not ask legacy Matrix code to index malformed
    # slots in order to prove the new admission is memory-safe.
    calls <- 0L
    stream <- .owned_csc_stream()
    actual <- stream(paste0("f", 1:3), "c", function(columns) {
      calls <<- calls + 1L; matrix(1:3, 3L, 1L)
    }, 1L, .owned_csc = value)
    stopifnot(calls == 1L, is.list(actual))
  }
  stopifnot(identical(.owned_csc_native(path, x, nr = 2L), FALSE))
  TRUE
}

test_engine_owned_csc_errors_cleanup_and_retry_contract <- function() {
  source <- .owned_csc_fixture()
  for (bad in c(Inf, -Inf, .Machine$double.xmin, 5e-324)) {
    x <- source; x@x[[4001L]] <- bad
    before <- serialize(x, NULL)
    for (file_sink in c(FALSE, TRUE)) {
      stream <- .owned_csc_stream(file_sink)
      observe <- function(owned) tryCatch(stream(paste0("f", seq_len(nrow(x))),
        c("c1", "c2"), function(columns) x[, columns, drop = FALSE], 16L,
        .owned_csc = if (owned) x else NULL), error = conditionMessage)
      old <- observe(FALSE); actual <- observe(TRUE)
      stopifnot(is.character(old), identical(old, actual),
        identical(serialize(x, NULL), before))
      retry <- stream(paste0("f", seq_len(nrow(source))), c("c1", "c2"),
        function(columns) source[, columns, drop = FALSE], 16L, .owned_csc = source)
      stopifnot(is.list(retry), grepl("^[a-f0-9]{64}$", retry$sha256))
    }
  }
  # Simulated interruption at the new native-entry boundary proves the outer
  # owner still releases its admitted SHA; actual asynchronous C delivery is a
  # separately scoped qualification, not claimed by this test.
  stream <- .owned_csc_stream()
  env <- new.env(parent = environment(stream)); pointer <- NULL
  open <- get(".wb_operation_pack_matrix_digest_open", asNamespace("scworkbench"))
  env$.wb_operation_pack_matrix_digest_open <- function() {pointer <<- open(); pointer}
  native <- get("C_scwb_matrix_slice_csc_append", asNamespace("scworkbench"))
  env$.Call <- function(name, ...) {
    if (identical(name, native)) stop(structure(list(message = "owned CSC simulated interrupt", call = NULL),
      class = c("interrupt", "condition")))
    base::.Call(name, ...)
  }
  environment(stream) <- env
  result <- tryCatch(stream(paste0("f", seq_len(nrow(source))), c("c1", "c2"),
    function(columns) stop("callback replay"), 16L, .owned_csc = source), interrupt = identity)
  stopifnot(inherits(result, "interrupt"))
  if (!is.null(pointer)) stopifnot(inherits(tryCatch(.Call(
    get("C_scwb_matrix_digest_update", asNamespace("scworkbench")), pointer, raw()),
    error = identity), "error"))
  TRUE
}
