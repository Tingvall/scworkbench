# Independent frozen projection: deliberately retain the old implementation as
# the small-fixture oracle, not as an execution path.
.wb_matrix_slice_legacy_oracle <- function(values, features, cells) {
  dense <- as.matrix(values)
  indices <- which(dense != 0, arr.ind = TRUE)
  if (length(indices)) indices <- indices[order(indices[, 2L], indices[, 1L]), , drop = FALSE]
  entries <- lapply(seq_len(nrow(indices)), function(i) list(
    row = as.integer(indices[i, 1L]), column = as.integer(indices[i, 2L]),
    value = unname(dense[indices[i, 1L], indices[i, 2L]])))
  scworkbench:::.wb_operation_pack_v2_identity_plain(
    "scworkbench.operation_pack.matrix_slice.content.v1",
    list(schema = "scworkbench.operation_pack.matrix_slice.content.v1",
      kind = "matrix", dimensions = list(as.integer(length(features)),
        as.integer(length(cells))), feature_id = unname(as.list(features)),
      cell_id = unname(as.list(cells)), entries = entries))
}

test_operation_pack_matrix_streaming_unused_lineage_contract <- function() {
  # No database handle: proves the absent capability does not scan any source.
  stopifnot(isTRUE(scworkbench:::.wb_operation_pack_v3_producer_lineage_assert_current(
    NULL, list(), list(), list(), list())))
  error <- tryCatch(scworkbench:::.wb_operation_pack_v3_producer_lineage_assert_current(
    NULL, list(producer_lineage_reads = list(list(name = "required"))),
    list(), list(), list()), error = identity)
  stopifnot(inherits(error, "error"))
  TRUE
}

test_operation_pack_matrix_streaming_identity_contract <- function() {
  set.seed(17)
  values <- matrix(c(0, -0, NA, NaN, 1, -1, 1e-307, 1e308,
    1e-7, 1e15, 0.123456789012345, -123456789012345,
    runif(93, -1e8, 1e8)), nrow = 7L)
  features <- paste0("g", 7:1, "\"é")
  cells <- paste0("c", ncol(values):1, "\\\n")
  expected <- .wb_matrix_slice_legacy_oracle(values, features, cells)
  for (chunk_size in c(1L, 2L, 7L, 128L)) {
    calls <- list()
    actual <- scworkbench:::.wb_operation_pack_matrix_stream_identity(
      features, cells, function(columns) {
        stopifnot(length(columns) <= chunk_size)
        calls[[length(calls) + 1L]] <<- columns
        values[, columns, drop = FALSE]
      }, chunk_size)
    stopifnot(identical(actual, expected),
      identical(unlist(calls, use.names = FALSE), seq_len(ncol(values))))
  }
  sparse <- Matrix::Matrix(values, sparse = TRUE)
  stopifnot(identical(scworkbench:::.wb_operation_pack_v3_matrix_slice_content(
    sparse, features, cells), expected))
  for (shape in list(c(0L, 0L), c(3L, 0L), c(0L, 3L), c(2L, 2L))) {
    zero <- matrix(0, nrow = shape[1], ncol = shape[2])
    f <- paste0("f", seq_len(shape[1])); if (!shape[1]) f <- character()
    c <- paste0("c", seq_len(shape[2])); if (!shape[2]) c <- character()
    stopifnot(identical(scworkbench:::.wb_operation_pack_v3_matrix_slice_content(zero, f, c),
      .wb_matrix_slice_legacy_oracle(zero, f, c)))
  }
  TRUE
}

test_operation_pack_matrix_streaming_reader_plan_contract <- function() {
  root <- tempfile("scwb_stream_plan_")
  bundle <- wb_init_bundle(root)
  on.exit({try(wb_close_bundle(bundle), silent = TRUE)
    unlink(root, recursive = TRUE)}, add = TRUE)
  cells <- c("c2", "c10", "c1", "zero", "c4")
  features <- c("f3", "f1", "f2", "f4")
  values <- matrix(c(1, 2, 0, 5, 3, 0, 6, 7, 0, 8, 4, 1, 0, 0, 0, 0,
    10, 3, 2, 5), 4L, dimnames = list(features, cells))
  wb_define_cells(bundle, cells)
  wb_attach_matrix(bundle, "RNA", values, feature_type = "gene")
  for (axis in c("cells", "features")) {
    plan <- scworkbench:::.wb_matrix_stream_reader(bundle, "RNA", axis)
    stopifnot(dir.exists(plan$root))
    for (ids in wb_partition_axis(if (axis == "cells") cells else features, 2L)) {
      f <- if (axis == "features") ids else features
      c <- if (axis == "cells") ids else cells
      stopifnot(identical(as.matrix(plan$read(f, c)), values[f, c, drop = FALSE]))
    }
    # Independent calls preserve the declared selection order too.
    stopifnot(identical(as.matrix(plan$read(rev(features), rev(cells))),
      values[rev(features), rev(cells), drop = FALSE]))
    plan$close()
    stopifnot(!dir.exists(plan$root))
  }
  TRUE
}

test_operation_pack_matrix_streaming_numeric_contract <- function() {
  set.seed(19)
  values <- c(runif(500), -runif(500), 10^seq(-307, 308, length.out = 1000),
    1.00000000000001, 9.99999999999999, 999999999999999)
  m <- matrix(values, nrow = 1L)
  cells <- paste0("c", seq_along(values))
  stopifnot(identical(scworkbench:::.wb_operation_pack_v3_matrix_slice_content(m, "g", cells),
    .wb_matrix_slice_legacy_oracle(m, "g", cells)))
  stopifnot(inherits(try(scworkbench:::.wb_operation_pack_v3_matrix_slice_content(
    matrix(.Machine$double.xmin), "g", "c"), silent = TRUE), "try-error"),
    inherits(try(.wb_matrix_slice_legacy_oracle(matrix(.Machine$double.xmin),
      "g", "c"), silent = TRUE), "try-error"))
  TRUE
}

test_operation_pack_matrix_streaming_alignment_contract <- function() {
  root <- tempfile("scwb_stream_alignment_")
  bundle <- wb_init_bundle(root)
  on.exit({try(wb_close_bundle(bundle), silent = TRUE)
    unlink(root, recursive = TRUE)}, add = TRUE)
  cells <- c("cell_2", "cell_10", "cell_1", "zero")
  features <- c("gene_2", "gene_10", "gene_1")
  values <- matrix(c(1, 3, 0, 10, 20, 2, 7, 1, 1, 0, 0, 0), 3L,
    dimnames = list(features, cells))
  wb_define_cells(bundle, rev(cells))
  wb_attach_matrix(bundle, "RNA", values, feature_type = "gene")
  physical <- wb_matrix(bundle, "RNA")
  stopifnot(isS4(physical), !methods::is(physical, "S4"),
    inherits(scworkbench:::.wb_as_sparse(physical), "Matrix"))
  requested_features <- rev(features)
  requested_cells <- c("zero", "cell_10", "cell_2", "cell_1")
  actual <- wb_slice(bundle, "RNA", requested_features, requested_cells)
  expected <- values[requested_features, requested_cells, drop = FALSE]
  stopifnot(identical(dimnames(actual), dimnames(expected)),
    identical(as.matrix(actual), expected),
    identical(as.numeric(Matrix::colSums(actual)), as.numeric(colSums(expected))),
    identical(sum(actual), sum(values)))
  # Equal totals do not imply equal positional columns. Prove alignment, not
  # just attributes: a deliberate permutation has unequal positional sums.
  stopifnot(!identical(as.numeric(colSums(values)),
    as.numeric(Matrix::colSums(actual))))
  guard <- scworkbench:::.wb_operation_pack_matrix_light_guard(bundle, "RNA")
  stopifnot(isTRUE(guard()))
  DBI::dbExecute(bundle$con, "UPDATE matrix_fragments SET description='changed' WHERE matrix_id='RNA';")
  error <- tryCatch(guard(), error = identity)
  stopifnot(inherits(error, "error"), identical(error$code,
    "PYBENCH_INPUT_IDENTITY_MISMATCH"))
  TRUE
}
