.owned_dense_native <- function(path, x, nr = nrow(x), nc = ncol(x))
  .Call(get("C_scwb_matrix_slice_dense_append", asNamespace("scworkbench")),
    path, x, as.integer(nr), as.integer(nc))
.owned_dense_fixture <- function() {
  x <- matrix(0, 8201L, 5L)
  x[, 1L] <- rep(c(1.25, -.75, pi, 1e-307, 1e308), length.out = nrow(x))
  x[1:4, 1L] <- c(NA_real_, NaN, 0, -0)
  x[, 3L] <- NA_real_; x[, 4L] <- seq_len(nrow(x)) * sqrt(2) / nrow(x)
  x[8201L, 5L] <- -2.25
  x
}
.owned_dense_stream <- function(file_sink = FALSE) {
  fn <- get(".wb_operation_pack_matrix_stream_identity", asNamespace("scworkbench"))
  if (file_sink) {
    env <- new.env(parent = environment(fn))
    env$.wb_operation_pack_matrix_digest_open <- function() NULL
    environment(fn) <- env
  }
  fn
}
.owned_dense_legacy <- function() {
  env <- new.env(parent = globalenv())
  sys.source("tests/test_engine_matrix_number_token_reuse_contract.R", env)
  env$.engine_matrix_number_records
}

test_engine_owned_dense_literal_preimage_and_mutation_contract <- function() {
  x <- .owned_dense_fixture(); before <- serialize(x, NULL)
  keep <- which(!is.na(x) & x != 0, arr.ind = TRUE)
  expected <- charToRaw(.owned_dense_legacy()(as.integer(keep[, 1L]),
    as.integer(keep[, 2L]), x[keep]))
  stopifnot(length(expected) > 65536L)
  path <- tempfile("owned_dense_bytes_"); on.exit(unlink(path), add = TRUE)
  writeBin(raw(), path)
  stopifnot(isTRUE(.owned_dense_native(path, x)),
    identical(readBin(path, "raw", n = file.info(path)$size), expected),
    identical(serialize(x, NULL), before))
  x[5L, 1L] <- 1.75; writeBin(raw(), path)
  stopifnot(isTRUE(.owned_dense_native(path, x)),
    !identical(readBin(path, "raw", n = file.info(path)$size), expected))
  TRUE
}

test_engine_owned_dense_complete_identity_and_callback_contract <- function() {
  x <- .owned_dense_fixture(); before <- serialize(x, NULL)
  features <- paste0("雪\\\"_f", seq_len(nrow(x)))
  cells <- c("c10", "c1\n", "c2", "c0", "c3")
  for (file_sink in c(FALSE, TRUE)) {
    stream <- .owned_dense_stream(file_sink)
    expected <- stream(features, cells, function(columns) x[, columns, drop = FALSE], 2L)
    calls <- 0L
    actual <- stream(features, cells, function(columns) {
      calls <<- calls + 1L; stop("owned dense callback should not run")
    }, 2L, .owned_csc = x)
    stopifnot(identical(actual, expected), calls == 0L)
    literal <- get(".wb_operation_pack_v3_matrix_slice_content", asNamespace("scworkbench"))
    env <- new.env(parent = environment(literal))
    env$.wb_operation_pack_matrix_stream_identity <- stream
    environment(literal) <- env
    stopifnot(identical(literal(x, features, cells), expected))
    # Entirely filtered matrices still terminate and retain complete framing.
    for (blank in list(matrix(0, 3L, 4L), matrix(NA_real_, 3L, 4L))) {
      old <- stream(letters[1:3], LETTERS[1:4], function(columns)
        blank[, columns, drop = FALSE], 2L)
      stopifnot(identical(stream(letters[1:3], LETTERS[1:4], function(columns)
        stop("filtered owned callback"), 2L, .owned_csc = blank), old))
    }
  }
  stopifnot(identical(serialize(x, NULL), before))
  TRUE
}

test_engine_owned_dense_decline_and_deferred_contract <- function() {
  path <- tempfile("owned_dense_decline_"); on.exit(unlink(path), add = TRUE)
  prefix <- charToRaw("prefix"); writeBin(prefix, path)
  x <- matrix(rep(c(1.25, 0, -3), 4L), 3L)
  attributed <- x; attr(attributed, "note") <- "opaque"
  classed <- x; class(classed) <- c("ownedDenseOpaque", "matrix", "array")
  named_axes <- x; dimnames(named_axes) <- list(rows = letters[1:3], columns = LETTERS[1:4])
  cases <- list(attributed, classed, named_axes, matrix(1:12, 3L),
    matrix(rep(c(TRUE, FALSE, NA), 4L), 3L), matrix(1+1i, 3L, 4L),
    matrix(numeric(), 0L, 4L), matrix(numeric(), 3L, 0L),
    Matrix::Matrix(x, sparse = FALSE))
  for (value in cases) stopifnot(identical(.owned_dense_native(path, value), FALSE),
    identical(readBin(path, "raw", n = file.info(path)$size), prefix))
  stopifnot(identical(.owned_dense_native(path, x, nr = 2L), FALSE))
  for (value in cases[1:5]) {
    stream <- .owned_dense_stream(); calls <- 0L
    old <- stream(letters[1:3], LETTERS[1:4], function(columns)
      value[, columns, drop = FALSE], 2L)
    actual <- stream(letters[1:3], LETTERS[1:4], function(columns) {
      calls <<- calls + 1L; value[, columns, drop = FALSE]
    }, 2L, .owned_csc = value)
    stopifnot(identical(old, actual), calls == 2L)
  }
  # R's dim<- (also attr/attributes/structure/matrix) materializes a REAL
  # sequence. A test-only DLL attaches dimensions to its freshly created
  # carrier directly; it never modifies the installed core or a source value.
  fixture_root <- tempfile("owned_dense_altrep_fixture_"); dir.create(fixture_root)
  fixture_source <- normalizePath("tests/fixtures/engine_dense_fixture.c", mustWork = TRUE)
  stopifnot(file.copy(fixture_source, file.path(fixture_root, "engine_dense_fixture.c")))
  fixture_dll <- NULL
  on.exit({if (!is.null(fixture_dll)) dyn.unload(fixture_dll[["path"]]);
    unlink(fixture_root, recursive = TRUE)}, add = TRUE)
  previous <- setwd(fixture_root)
  built <- tryCatch(system2(file.path(R.home("bin"), "R"),
    c("CMD", "SHLIB", "engine_dense_fixture.c"), stdout = TRUE, stderr = TRUE),
    finally = setwd(previous))
  cat(built, sep = "\n")
  stopifnot(is.null(attr(built, "status")) || attr(built, "status") == 0L)
  fixture_dll <- dyn.load(file.path(fixture_root, paste0("engine_dense_fixture", .Platform$dynlib.ext)))
  create <- getNativeSymbolInfo("dense_deferred", PACKAGE = fixture_dll)
  flag <- getNativeSymbolInfo("is_deferred", PACKAGE = fixture_dll)
  end <- as.integer(Sys.getpid() %% 7L + 30L)
  deferred <- .Call(create, end)
  compact <- function(x) any(grepl("compact|deferred", capture.output(.Internal(inspect(x)))))
  stopifnot(isTRUE(.Call(flag, deferred)), is.matrix(deferred), typeof(deferred) == "double",
    compact(deferred), identical(.owned_dense_native(path, deferred), FALSE),
    isTRUE(.Call(flag, deferred)), compact(deferred),
    identical(readBin(path, "raw", n = file.info(path)$size), prefix))
  twin <- matrix(0, end, 1L); twin[, 1L] <- seq_len(end)
  stopifnot(identical(twin, deferred), isTRUE(.owned_dense_native(path, twin)))
  cat("OWNED_DENSE_ACTUAL_ALTREP_DECLINE TRUE\n")
  TRUE
}

test_engine_owned_dense_errors_unwind_and_retry_contract <- function() {
  source <- .owned_dense_fixture(); features <- paste0("f", seq_len(nrow(source)))
  cells <- paste0("c", seq_len(ncol(source)))
  for (file_sink in c(FALSE, TRUE)) {
    stream <- .owned_dense_stream(file_sink)
    for (width in c(NA_real_, 0, -1, Inf, .5)) {
      observe <- function(owned) tryCatch(stream(features, cells, function(columns)
        source[, columns, drop = FALSE], width, .owned_csc = if (owned) source else NULL),
        error = conditionMessage)
      stopifnot(identical(observe(FALSE), observe(TRUE)))
    }
    for (bad in c(Inf, -Inf, .Machine$double.xmin, 5e-324)) {
      x <- source; x[8000L, 4L] <- bad; before <- serialize(x, NULL)
      observe <- function(owned) tryCatch(stream(features, cells, function(columns)
        x[, columns, drop = FALSE], 2L, .owned_csc = if (owned) x else NULL),
        error = conditionMessage)
      old <- observe(FALSE); actual <- observe(TRUE)
      stopifnot(is.character(old), identical(old, actual), identical(serialize(x, NULL), before))
    }
    retry <- stream(features, cells, function(columns) stop("retry callback"), 2L, .owned_csc = source)
    stopifnot(is.list(retry), grepl("^[a-f0-9]{64}$", retry$sha256))
  }
  path <- tempfile("owned_dense_native_error_"); on.exit(unlink(path), add = TRUE)
  x <- source; x[8000L, 4L] <- Inf; writeBin(raw(), path)
  failure <- tryCatch(.owned_dense_native(path, x), error = identity)
  stopifnot(inherits(failure, "error"), file.info(path)$size > 65536L)
  if (dir.exists("/proc/self/fd")) stopifnot(!normalizePath(path) %in%
    Sys.readlink(list.files("/proc/self/fd", full.names = TRUE)))
  writeBin(raw(), path); stopifnot(isTRUE(.owned_dense_native(path, source)))
  TRUE
}
