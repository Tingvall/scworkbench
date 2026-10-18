# Private, invocation-owned physical adapter for core-generated Matrix Market.
# No host path, authority object, cache service or new wire representation is
# exposed to a pack. The existing grant remains the content authority.
.wb_operation_pack_v3_private_source_info <- function(stage, grant) {
  source <- grant$source_reference
  relative <- sub("^private_projection:", "typed_slice_sources/",
    paste0(source$input_reference, "/matrix.mtx"))
  if (nzchar(Sys.readlink(file.path(stage, relative))))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Typed-slice private projection must not be linked.", "staging")
  path <- tryCatch(.wb_bundle_path_require(stage, relative,
    expected_type = "file", purpose = "typed-slice private projection"),
    error = function(error) .wb_operation_pack_v3_error(
      "PYBENCH_INPUT_IDENTITY_MISMATCH", conditionMessage(error), "staging"))
  payload <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.payload_manifest.v2",
    "registry read payload manifest", list(path = relative,
      size = as.numeric(file.info(path)$size),
      sha256 = .wb_operation_pack_v2_file_sha256(path)))
  if (!identical(payload, source$private_source_payload_identity))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Typed-slice private projection bytes differ from the grant.", "staging")
  list(path = path, relative = relative, payload_identity = payload,
    features = .wb_operation_pack_v3_broker_axis_ids(stage, grant$features_axis),
    cells = .wb_operation_pack_v3_broker_axis_ids(stage, grant$cells_axis))
}

.wb_operation_pack_v3_private_projection_assert <- function(grant, info, projected) {
  source <- grant$source_reference
  projection <- list(schema =
      "scworkbench.operation_pack.typed_slice_source_projection.v1",
    original_input_content_identity = source$input_content_identity,
    features_axis_manifest_identity = grant$features_axis$axis_manifest_identity,
    cells_axis_manifest_identity = grant$cells_axis$axis_manifest_identity,
    projected_content_identity = projected,
    private_source_payload_identity = info$payload_identity)
  projection$projection_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.typed_slice_source_projection.v1",
    "projection excluding projection_identity", projection)
  if (!identical(projected, source$projected_content_identity) ||
      !identical(projection$projection_identity, source$projection_identity))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Typed-slice private projection content differs from its grant.", "staging")
  invisible(TRUE)
}

.wb_operation_pack_v3_private_stream_open <- function(stage, grant, budget) {
  info <- .wb_operation_pack_v3_private_source_info(stage, grant)
  guard <- .wb_operation_pack_v3_broker_projection_guard(stage, grant)
  input <- file(info$path, "rt")
  header <- tryCatch(readLines(input, n = 2L, warn = FALSE), finally = close(input))
  dimensions <- if (length(header) == 2L) strsplit(header[[2L]], " ", fixed = TRUE)[[1L]] else character()
  if (length(header) != 2L ||
      !identical(header[[1L]], "%%MatrixMarket matrix coordinate real general") ||
      length(dimensions) != 3L || any(!grepl("^(0|[1-9][0-9]*)$", dimensions)))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Private source is not the authenticated core-generated Matrix Market format.", "staging")
  dimensions <- suppressWarnings(as.double(dimensions))
  if (any(!is.finite(dimensions)) || any(dimensions > 2147483647) ||
      !identical(dimensions[1:2], as.double(c(length(info$features), length(info$cells)))))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Private source dimensions/count exceed the existing matrix representation.", "staging")
  nnz <- dimensions[[3L]]
  axis_count <- length(info$features) + length(info$cells)
  axis_bytes <- sum(nchar(c(info$features, info$cells), type = "bytes"))
  # Includes axis/guard envelopes and the native matrix loader's fixed buffers.
  metadata <- 128 * axis_count + 4 * axis_bytes + 65536
  retained <- metadata + 1048576
  cache_estimate <- 128 * nnz + 4 * file.info(info$path)$size + metadata
  remaining <- budget$memory - budget$used
  if (!is.finite(remaining) || metadata > remaining)
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Private source axes and bounded reader workspace exceed working-memory admission.", "execution")
  matrix <- NULL; columns <- NULL; indexed <- NULL; root <- NULL
  spill_guard <- NULL; charged <- 0; disk_charge <- 0; closed <- FALSE
  close <- function() {
    if (!closed) {
      matrix <<- NULL; columns <<- NULL; indexed <<- NULL
      if (!is.null(root)) unlink(root, recursive = TRUE)
      budget$used <- max(0, budget$used - charged)
      budget$disk <- max(0, budget$disk - disk_charge)
      charged <<- 0; disk_charge <<- 0; closed <<- TRUE
    }
    invisible(TRUE)
  }
  ready <- FALSE
  on.exit(if (!ready) close(), add = TRUE)
  if (cache_estimate <= budget$limit - budget$used) {
    charged <- cache_estimate; budget$used <- budget$used + charged
    matrix <- tryCatch(methods::as(Matrix::readMM(info$path), "CsparseMatrix"),
      error = function(error) .wb_operation_pack_v3_error(
        "PYBENCH_INPUT_IDENTITY_MISMATCH", conditionMessage(error), "staging"))
    projected <- .wb_operation_pack_v3_matrix_slice_content(matrix, info$features, info$cells)
    .wb_operation_pack_v3_private_projection_assert(grant, info, projected)
    mode <- "cached_projection"
  } else {
    if (retained + 1048576 > remaining)
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "No bounded private-source sorting workspace remains.", "execution")
    # BPCells' double external sorter keeps at most two live compressed rounds;
    # source-derived reservation and supported-build assumptions are documented
    # in the accompanying bound ledger. Count the row-index build too.
    peak <- 128 * nnz + 64 * axis_count + 4 * axis_bytes + 1048576
    if (!is.finite(peak) || peak > 2^53 ||
        .wb_operation_pack_v3_broker_free_bytes(tempdir()) < peak + budget$disk)
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Insufficient capacity for the bounded private-source adapter.", "execution")
    if (!is.null(budget$policy)) {
      usage <- .wb_graph_transient_usage(budgets = budget$policy)
      if (usage$owned_spill_bytes + budget$disk + peak +
          .wb_graph_session_copy_reservation(budget$policy) > as.numeric(budget$policy$token_bytes))
        .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
          "Private source adapter exceeds the shared graph scratch admission.", "execution")
    }
    charged <- retained; budget$used <- budget$used + charged
    disk_charge <- peak; budget$disk <- budget$disk + peak
    workspace <- budget$memory - budget$used
    sort_bytes <- floor(min(16777216, workspace / 8) / 16) * 16
    load_bytes <- floor(min(1048576, sort_bytes / 16) / 512) * 512
    if (load_bytes < 512 || sort_bytes < 8 * load_bytes)
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "No bounded Matrix Market sorting workspace remains.", "execution")
    root <- tempfile("scwb_broker_projection_"); dir.create(root)
    columns <- tryCatch(BPCells::import_matrix_market(info$path,
      # Names use authenticated external axes. BPCells stores names as lines;
      # omitting them here preserves IDs containing literal newlines/CR too.
      outdir = file.path(root, "columns"), row_names = NULL,
      col_names = NULL, row_major = FALSE, tmpdir = root,
      load_bytes = as.integer(load_bytes), sort_bytes = as.integer(sort_bytes)),
      error = function(error) .wb_operation_pack_v3_error(
        "PYBENCH_INPUT_IDENTITY_MISMATCH", conditionMessage(error), "staging"))
    if (!identical(as.integer(dim(columns)), as.integer(dimensions[1:2])))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Streamed private source dimensions differ from its axes.", "staging")
    width <- max(1L, min(128L, floor(workspace / max(1, 128 * length(info$features)))))
    projected <- .wb_operation_pack_matrix_stream_identity(info$features, info$cells,
      function(indices) .wb_as_sparse(columns[, indices, drop = FALSE]), width)
    .wb_operation_pack_v3_private_projection_assert(grant, info, projected)
    indexed <- if (identical(grant$chunk_axis, "features"))
      BPCells::transpose_storage_order(columns, outdir = file.path(root, "rows"),
        tmpdir = root, load_bytes = as.integer(load_bytes), sort_bytes = as.integer(sort_bytes)) else columns
    columns <- NULL
    if (identical(grant$chunk_axis, "features")) unlink(file.path(root, "columns"), recursive = TRUE)
    paths <- as.character(fs::dir_ls(root, recurse = TRUE, type = "file", all = TRUE))
    actual <- sum(file.info(paths)$size)
    if (!is.finite(actual) || actual > peak)
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Private source adapter exceeded its admitted disk bound.", "execution")
    spill_guard <- .wb_operation_pack_v3_broker_spill_guard(root)
    mode <- "spilled_projection"
  }
  guard()
  read <- function(features, cells) {
    tryCatch({
      if (closed) .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Private source reader has already closed.", "execution")
      rows <- match(features, info$features); cols <- match(cells, info$cells)
      if (anyNA(rows) || anyNA(cols) || anyDuplicated(rows) || anyDuplicated(cols))
        .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
          "Private source selection differs from its admitted axes.", "execution")
      guard(); if (!is.null(spill_guard)) spill_guard()
      values <- if (is.null(matrix)) .wb_as_sparse(indexed[rows, cols, drop = FALSE]) else matrix[rows, cols, drop = FALSE]
      guard(); if (!is.null(spill_guard)) spill_guard()
      values
    }, error = function(error) { close(); stop(error) })
  }
  ready <- TRUE
  list(read = read, close = close, mode = mode, spill_root = root)
}
