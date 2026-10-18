.matrix_market_oracle <- function() {
  env <- new.env(parent = asNamespace("scworkbench"))
  sys.source("tests/fixtures/engine_matrix_market_fff50517_oracle.R", env)
  env$.matrix_market_frozen_oracle
}

test_engine_matrix_market_writer_byte_contract <- function() {
  root <- tempfile("matrix_market_bytes_"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  old <- .matrix_market_oracle()
  write <- scworkbench:::.wb_operation_pack_v3_atomic_matrix_market
  observed <- new.env(parent = environment(write))
  observed$elements <- numeric()
  observed$as.matrix <- function(x, ...) {
    observed$elements <- c(observed$elements, length(x))
    base::as.matrix(x, ...)
  }
  environment(write) <- observed
  saved <- options(scworkbench.max_dense_materialize_mb = .03)
  on.exit(options(saved), add = TRUE)
  # Force multiple column blocks and, separately, single-column row blocks.
  cases <- list(matrix(numeric(), 0L, 3L), matrix(numeric(), 3L, 0L),
    matrix(0, 3L, 4L), matrix(c(-0, 0, 1, -1, 1/3, -1/7,
      1e-307, -1e-307, 1e308, -1e308, 1.00000000000001e-307,
      1.000000000000005, 999999999999999, 999999999999999.5), 2L),
    matrix(rep(c(TRUE, FALSE), 30L), 3L),
    matrix(as.integer(c(0, 1, -1, .Machine$integer.max)), 2L),
    matrix(rep(c(-1, 0, .125), length.out = 17L * 139L), 17L),
    matrix(rep(c(0, 7), length.out = 1001L * 2L), 1001L))
  sparse <- Matrix::sparseMatrix(i = c(5L, 1L, 4L, 2L),
    j = c(2L, 1L, 1L, 2L), x = c(.25, -1, 0, 7), dims = c(5L, 3L))
  cases <- c(cases, list(sparse, as(sparse, "RsparseMatrix"),
    as(sparse, "TsparseMatrix"), sparse != 0,
    methods::as(sparse != 0, "nMatrix"), Matrix::Diagonal(17L),
    Matrix::triu(Matrix::Matrix(matrix(seq_len(49L), 7L), sparse = TRUE)),
    Matrix::forceSymmetric(Matrix::Matrix(matrix(seq_len(49L), 7L), sparse = TRUE))))
  exponents <- 10^seq.int(-307L, 308L)
  edges <- c(exponents, exponents*(1-2*.Machine$double.eps),
    exponents*(1+2*.Machine$double.eps), 1.234567890123445,
    1.234567890123455, -1.234567890123445, -1.234567890123455)
  cases <- c(cases, list(matrix(edges, ncol = 1L)))
  for (values in cases) {
    observed$elements <- numeric()
    before <- serialize(values, NULL)
    old(values, file.path(root, "old.mtx"))
    write(values, file.path(root, "new.mtx"))
    bytes <- function(name) readBin(file.path(root, name), "raw", n = 1e7)
    stopifnot(identical(bytes("old.mtx"), bytes("new.mtx")),
      identical(serialize(values, NULL), before),
      !file.exists(file.path(root, "new.mtx.pending")))
    allowed <- max(1, floor((.03*1024^2-8192)/64))
    stopifnot(all(observed$elements <= allowed),
      sum(observed$elements) == 2*length(values))
  }
  # Preserve historical whole-coercion semantics for unsupported ordinary types.
  for (values in list(matrix(c("0", "1.25", "-4", "0"), 2L),
      matrix(c(1+2i, 0+0i), 2L), matrix(as.raw(c(0, 1, 255, 0)), 2L),
      data.frame(x = c(1, 0), y = c(0, 2)))) {
    suppressWarnings(old(values, file.path(root, "old.mtx")))
    suppressWarnings(write(values, file.path(root, "new.mtx")))
    stopifnot(identical(readBin(file.path(root, "old.mtx"), "raw", 1e6),
      readBin(file.path(root, "new.mtx"), "raw", 1e6)))
  }
  TRUE
}

test_engine_matrix_market_writer_failure_contract <- function() {
  root <- tempfile("matrix_market_fail_"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  path <- file.path(root, "output.mtx")
  old <- .matrix_market_oracle()
  write <- scworkbench:::.wb_operation_pack_v3_atomic_matrix_market
  saved <- options(scworkbench.max_dense_materialize_mb = .03)
  on.exit(options(saved), add = TRUE)
  for (values in list(matrix(NA_real_, 1L), matrix(NaN, 1L),
      matrix(Inf, 1L), matrix(-Inf, 1L), matrix(1e-308, 1L),
      matrix(-1e-308, 1L), matrix(9.99999999999999e-308, 1L),
      matrix(c(1e-308, rep(1, 999L), NA_real_), ncol = 1L),
      matrix("not numeric", 1L))) {
    writeBin(charToRaw("previous destination\n"), path)
    expected <- suppressWarnings(tryCatch(old(values, file.path(root, "oracle.mtx")), error = identity))
    actual <- suppressWarnings(tryCatch(write(values, path), error = identity))
    stopifnot(inherits(expected, "error"), inherits(actual, "error"),
      identical(class(expected), class(actual)),
      identical(conditionMessage(expected), conditionMessage(actual)),
      identical(readLines(path), "previous destination"),
      !file.exists(paste0(path, ".pending")))
  }
  destination <- file.path(root, "occupied"); dir.create(destination)
  writeLines("do not replace", file.path(destination, "keep"))
  failed <- suppressWarnings(try(write(matrix(1, 1L), destination), silent = TRUE))
  stopifnot(inherits(failed, "try-error"),
    identical(readLines(file.path(destination, "keep")), "do not replace"),
    !file.exists(paste0(destination, ".pending")))
  outdec <- options(OutDec = ",")
  expected <- tryCatch(old(matrix(1.25, 1L), file.path(root, "locale.mtx")), error = identity)
  actual <- tryCatch(write(matrix(1.25, 1L), path), error = identity)
  options(outdec)
  stopifnot(inherits(expected, "error"), inherits(actual, "error"),
    identical(class(actual), class(expected)),
    identical(conditionMessage(actual), conditionMessage(expected)),
    identical(readLines(path), "previous destination"),
    !file.exists(paste0(path, ".pending")))
  write(matrix(.25, 1L), path)
  stopifnot(identical(readLines(path)[[3L]], "1 1 2.5e-1"))
  TRUE
}

test_engine_matrix_market_private_grant_contract <- function() {
  root <- tempfile("matrix_market_grant_"); dir.create(root)
  bundle <- wb_init_bundle(file.path(root, "source.bundle"))
  on.exit({wb_close_bundle(bundle); unlink(root, recursive = TRUE)}, add = TRUE)
  cells <- c("c2", "c10", "c1", "c8")
  features <- c("f3", "f1", "f2")
  wb_define_cells(bundle, cells)
  values <- matrix(c(0, 1, 2, -1, 0, .5, 8, 0, 3, 0, 0, 4), 3L,
    dimnames = list(features, cells))
  declaration <- list(name = "chunks", input = "matrix", supported_axes = list("cells", "features"),
    chunk_axis = "cells", chunk_size_parameter = "chunk_size",
    call_discipline = "ordered_partition_exactly_once", empty_selection_policy = "reject",
    selection = list(cells = list(policy = "effective_input_axis_v1"),
      features = list(policy = "effective_input_axis_v1")))
  state <- list(scheme = "fixture", sha256 = paste(rep("a", 64L), collapse = ""))
  descriptor <- list(descriptor_identity = state, content_identity = state)
  grant <- scworkbench:::.wb_operation_pack_v3_typed_slice_grant
  observation <- new.env(parent = environment(grant))
  writer <- scworkbench:::.wb_operation_pack_v3_atomic_matrix_market
  observation$.wb_operation_pack_v3_atomic_matrix_market <- function(values, path) {
    observation$sparse <- isS4(values) && methods::is(values, "Matrix")
    writer(values, path)
  }
  environment(grant) <- observation
  for (matrix in list(values, Matrix::Matrix(values, sparse = TRUE), values != 0,
      Matrix::Matrix(values != 0, sparse = TRUE))) {
    stage <- tempfile("projection_", tmpdir = root); dir.create(stage)
    input <- structure(list(kind = "matrix", values = matrix,
      feature_id = features, cell_id = cells), class = "wb_primitive")
    result <- grant(bundle, declaration, input, descriptor, list(chunk_size = 2L),
      cells, state, stage)
    stopifnot(identical(observation$sparse, isS4(matrix) && methods::is(matrix, "Matrix")))
    source <- result$source_reference
    # Descriptor shape is checked below against the same physical source.
    path <- file.path(stage, "typed_slice_sources/chunks/matrix.mtx")
    oracle <- file.path(root, "oracle.mtx")
    .matrix_market_oracle()(matrix, oracle)
    stopifnot(identical(readBin(path, "raw", 1e6), readBin(oracle, "raw", 1e6)))
    # The original grant coerced once before projected identity; retain exact
    # scalar logical/numeric distinction, axes and identity preimage.
    expected <- scworkbench:::.wb_operation_pack_v3_matrix_slice_content(
      as.matrix(matrix), features, cells)
    stopifnot(identical(source$projected_content_identity, expected))
  }
  TRUE
}
