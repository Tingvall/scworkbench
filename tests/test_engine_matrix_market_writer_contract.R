.matrix_market_oracle <- function() {
  env <- new.env(parent = asNamespace("scworkbench"))
  sys.source("tests/fixtures/engine_matrix_market_fff50517_oracle.R", env)
  env$.matrix_market_frozen_oracle
}

`[.engine_matrix_market_exotic` <- function(x, i, j, ..., drop = TRUE) {
  class(x) <- c("matrix", "array")
  x[i, j, ..., drop = drop] + if (length(i) > 1L || length(j) > 1L) 100 else 1
}

.matrix_market_register_exotic <- function() {
  ns <- asNamespace("base")
  table <- get(".__S3MethodsTable__.", ns)
  key <- "[.engine_matrix_market_exotic"
  previous <- get0(key, table, inherits = FALSE)
  registerS3method("[", "engine_matrix_market_exotic", `[.engine_matrix_market_exotic`, envir = ns)
  function() {
    if (is.null(previous)) rm(list = key, envir = table)
    else assign(key, previous, envir = table)
  }
}

test_engine_matrix_market_writer_byte_contract <- function() {
  restore_exotic <- .matrix_market_register_exotic()
  on.exit(restore_exotic(), add = TRUE)
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
    standard <- scworkbench:::.wb_operation_pack_v3_matrix_market_standard(values)
    if (standard && !isS4(values)) stopifnot(all(observed$elements <= allowed),
      sum(observed$elements) == 2*length(values))
    else if (standard) stopifnot(!length(observed$elements))
    else stopifnot(observed$elements[[1L]] == length(values),
      sum(observed$elements) == 3*length(values))
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
  exotic <- matrix(c(1, 2, 0, 3), 2L)
  class(exotic) <- c("engine_matrix_market_exotic", "matrix", "array")
  old(exotic, file.path(root, "old.mtx")); write(exotic, file.path(root, "new.mtx"))
  stopifnot(identical(readBin(file.path(root, "old.mtx"), "raw", 1e6),
    readBin(file.path(root, "new.mtx"), "raw", 1e6)))
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
  restore_exotic <- .matrix_market_register_exotic()
  on.exit(restore_exotic(), add = TRUE)
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
  subset_calls <- 0L
  traced <- FALSE
  on.exit(if (traced) untrace(".subscript.2ary", where = asNamespace("Matrix")), add = TRUE)
  trace(".subscript.2ary", where = asNamespace("Matrix"),
    tracer = function() subset_calls <<- subset_calls + 1L, print = FALSE)
  traced <- TRUE
  observation <- new.env(parent = environment(grant))
  writer <- scworkbench:::.wb_operation_pack_v3_atomic_matrix_market
  observation$.wb_operation_pack_v3_atomic_matrix_market <- function(values, path) {
    observation$subsets_before_writer <- subset_calls
    observation$sparse <- isS4(values) && methods::is(values, "Matrix")
    writer(values, path)
  }
  environment(grant) <- observation
  for (matrix in list(values, Matrix::Matrix(values, sparse = TRUE), values != 0,
      Matrix::Matrix(values != 0, sparse = TRUE),
      methods::as(Matrix::Matrix(values != 0, sparse = TRUE), "nMatrix"),
      as(Matrix::Matrix(values, sparse = TRUE), "RsparseMatrix"),
      as(Matrix::Matrix(values, sparse = TRUE), "TsparseMatrix"))) {
    stage <- tempfile("projection_", tmpdir = root); dir.create(stage)
    input <- structure(list(kind = "matrix", values = matrix,
      feature_id = features, cell_id = cells,
      meta = list(label = "projection metadata", order = c(3L, 1L),
        named = c(left = "L", right = "R"))), class = "wb_primitive")
    before <- serialize(input, NULL)
    subset_calls <- 0L
    result <- grant(bundle, declaration, input, descriptor, list(chunk_size = 2L),
      cells, state, stage)
    stopifnot(identical(observation$sparse, isS4(matrix) &&
      scworkbench:::.wb_operation_pack_v3_matrix_market_standard(matrix)))
    if (isS4(matrix) && scworkbench:::.wb_operation_pack_v3_matrix_market_standard(matrix))
      stopifnot(observation$subsets_before_writer == 0L)
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
    stopifnot(identical(source$projected_content_identity, expected),
      identical(serialize(input, NULL), before))
    admitted <- tryCatch(scworkbench:::.wb_operation_pack_v3_private_source_validate(stage, result),
      error = function(error) error)
    if (is.numeric(as.matrix(matrix))) stopifnot(!inherits(admitted, "error"))
    else stopifnot(inherits(admitted, "error"),
      identical(admitted$code, "PYBENCH_INPUT_IDENTITY_MISMATCH"))
    if (isS4(matrix) && scworkbench:::.wb_operation_pack_v3_matrix_market_standard(matrix)) {
      selected_cells <- cells[c(3L, 1L)]
      selected_features <- features[c(3L, 1L)]
      selected_declaration <- declaration
      selected_declaration$selection$features <- list(
        policy = "parameter_ordered_subset_v1", parameter = "features")
      selected_stage <- tempfile("selected_", tmpdir = root); dir.create(selected_stage)
      subset_calls <- 0L
      selected <- grant(bundle, selected_declaration, input, descriptor,
        list(chunk_size = 2L, features = selected_features), selected_cells, state, selected_stage)
      stopifnot(observation$sparse, observation$subsets_before_writer == 0L,
        identical(serialize(input, NULL), before))
      selected_values <- as.matrix(matrix[c(3L, 1L), c(3L, 1L), drop = FALSE])
      .matrix_market_oracle()(selected_values, oracle)
      stopifnot(identical(readBin(file.path(selected_stage,
        "typed_slice_sources/chunks/matrix.mtx"), "raw", 1e6), readBin(oracle, "raw", 1e6)),
        identical(selected$source_reference$projected_content_identity,
          scworkbench:::.wb_operation_pack_v3_matrix_slice_content(
            selected_values, selected_features, selected_cells)))
      admitted <- tryCatch(scworkbench:::.wb_operation_pack_v3_private_source_validate(
        selected_stage, selected), error = function(error) error)
      if (is.numeric(selected_values)) stopifnot(!inherits(admitted, "error"))
      else stopifnot(inherits(admitted, "error"),
        identical(admitted$code, "PYBENCH_INPUT_IDENTITY_MISMATCH"))
    }
  }
  exotic <- values
  class(exotic) <- c("engine_matrix_market_exotic", "matrix", "array")
  input <- structure(list(kind = "matrix", values = exotic,
    feature_id = features, cell_id = cells), class = "wb_primitive")
  stage <- tempfile("exotic_", tmpdir = root); dir.create(stage)
  result <- grant(bundle, declaration, input, descriptor, list(chunk_size = 2L), cells, state, stage)
  expected <- as.matrix(exotic[seq_len(nrow(exotic)), seq_len(ncol(exotic)), drop = FALSE])
  .matrix_market_oracle()(expected, oracle)
  stopifnot(identical(readBin(file.path(stage, "typed_slice_sources/chunks/matrix.mtx"), "raw", 1e6),
    readBin(oracle, "raw", 1e6)))
  TRUE
}

test_engine_matrix_market_csc_slot_bounds_contract <- function() {
  root <- tempfile("matrix_market_slots_"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  write <- scworkbench:::.wb_operation_pack_v3_atomic_matrix_market
  saved <- options(scworkbench.max_dense_materialize_mb = .03)
  on.exit(options(saved), add = TRUE)
  values <- Matrix::sparseMatrix(i = c(1L, 2L, 10000000L, 6L),
    j = c(1L, 1L, 1L, 2L), x = c(1, 0, 3, -2), dims = c(10000000L, 2L))
  before <- serialize(values, NULL)
  path <- file.path(root, "tall.mtx")
  write(values, path) # Warm ordinary R code before allocation recording.
  projection <- scworkbench:::.wb_operation_pack_v3_matrix_market_projection
  projection(values, c(10000000L, 1L, 6L), c(2L, 1L))
  ns <- asNamespace("Matrix")
  traced <- character()
  on.exit(for (name in traced) untrace(name, where = ns), add = TRUE)
  for (name in c(".subscript.2ary", ".subscript.1ary")) {
    trace(name, where = ns, tracer = function()
      stop("Matrix subset dispatch is forbidden inside bounded CSC writer."), print = FALSE)
    traced <- c(traced, name)
  }
  profile <- file.path(root, "allocations")
  on.exit(Rprofmem(NULL), add = TRUE)
  Rprofmem(profile)
  write(values, path)
  projected <- projection(values, c(10000000L, 1L, 6L), c(2L, 1L))
  Rprofmem(NULL)
  sizes <- suppressWarnings(as.numeric(sub(" .*", "", readLines(profile))))
  largest <- max(c(0, sizes), na.rm = TRUE)
  stopifnot(largest <= 128*1024,
    identical(serialize(values, NULL), before),
    identical(unname(as.matrix(projected)), matrix(c(0, 0, -2, 3, 1, 0), 3L)),
    identical(readLines(path), c("%%MatrixMarket matrix coordinate real general",
      "10000000 2 3", "1 1 1e0", "10000000 1 3e0", "6 2 -2e0")))
  # Exercise many slot batches without a source-height workspace, including
  # the8192 native admission boundary and explicit zero/logical/pattern slots.
  for (kind in c("numeric", "logical", "pattern")) {
    ordinary <- matrix(rep(c(0, 1, -2), length.out = 8193L), ncol = 1L)
    sparse <- Matrix::sparseMatrix(i = seq_len(8193L), j = rep(1L, 8193L),
      x = as.double(ordinary), dims = c(10000000L, 1L))
    if (kind == "logical") { ordinary <- ordinary != 0; sparse <- sparse != 0 }
    if (kind == "pattern") {
      ordinary <- ordinary != 0
      sparse <- methods::as(sparse != 0, "nMatrix")
    }
    small <- sparse
    small@Dim <- c(8193L, 1L)
    .matrix_market_oracle()(small, file.path(root, "small.mtx"))
    expected <- readLines(file.path(root, "small.mtx"))
    expected[[2L]] <- sub("^8193 ", "10000000 ", expected[[2L]])
    for (guard in c(.03, 256)) {
      options(scworkbench.max_dense_materialize_mb = guard)
      write(sparse, path)
      stopifnot(identical(readLines(path), expected))
    }
  }
  for (name in traced) untrace(name, where = ns)
  traced <- character()
  cat("CSC_SLOT_BOUNDS max_allocation=", largest,
    " source_rows=10000000 guard_bytes=", .03*1024^2, " Matrix_subset_calls=0\n", sep = "")
  TRUE
}

test_engine_matrix_market_projection_native_admission_contract <- function() {
  p <- c(0L, 2L, 3L); i <- c(0L, 2L, 1L); x <- c(.5, -2, 3)
  args <- list(p, i, x, c(3L, 2L), c(0L, 2L), c(1L, 0L), c(1L, 0L))
  symbol <- scworkbench:::C_scwb_matrix_market_projection
  call <- function(x) do.call(.Call, c(list(symbol), x))
  result <- call(args)
  stopifnot(identical(result$p, c(0L, 0L, 2L)),
    identical(result$i, c(0L, 1L)), identical(result$x, c(-2, .5)))
  for (case in list(list(1L, c(0L, 4L)), list(1L, c(0L, NA_integer_, 3L)),
      list(2L, c(0L, -1L, 1L)), list(3L, c(1, 2)),
      list(4L, c(NA_integer_, 2L)), list(5L, c(0L, 3L)),
      list(5L, c(2L, 0L)), list(6L, c(1L, 2L)), list(6L, c(1L, 1L)),
      list(7L, c(0L, 2L)))) {
    bad <- args; bad[[case[[1L]]]] <- case[[2L]]
    stopifnot(inherits(tryCatch(call(bad), error = identity), "error"))
  }
  values <- Matrix::sparseMatrix(i = c(1L, 3L, 2L), j = c(1L, 1L, 2L),
    x = x, dims = c(3L, 2L))
  project <- scworkbench:::.wb_operation_pack_v3_matrix_market_projection
  for (axes in list(list(c(1, 1.5), 1L), list(c(1L, 1L), 1L),
      list(c(1L, 4L), 1L), list(1L, 0L), list(1L, c(1L, NA_integer_))))
    stopifnot(inherits(tryCatch(project(values, axes[[1L]], axes[[2L]]), error = identity), "error"))
  # Compact ALTREP source slots must not be forced through INTEGER()/REAL().
  # Only two selected values become ordinary output storage.
  compact <- list(c(0L, 1000000L), 0:999999L, as.double(seq_len(1000000L)),
    c(1000000L, 1L), c(0L, 999999L), c(1L, 0L), 0L)
  profile <- tempfile("matrix_projection_altrep_")
  on.exit({Rprofmem(NULL); unlink(profile)}, add = TRUE)
  Rprofmem(profile)
  compact_result <- call(compact)
  Rprofmem(NULL)
  sizes <- suppressWarnings(as.numeric(sub(" .*", "", readLines(profile))))
  largest <- max(c(0, sizes), na.rm = TRUE)
  stopifnot(largest <= 128*1024, identical(compact_result$x, c(1000000, 1)))
  cat("ALTREP_SLOT_PROJECTION max_allocation=", largest,
    " source_entries=1000000 selected_entries=2\n", sep = "")
  TRUE
}
