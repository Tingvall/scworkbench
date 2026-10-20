# Stream the EXISTING matrix_slice.content.v1 canonical preimage. This is a
# representation optimization, not a new identity scheme. read_columns is
# core-private; pack readers retain their declared bounded public interface.
.wb_operation_pack_matrix_axis_json <- function(ids) {
  if (!is.character(ids) || is.object(ids))
    return(.wb_operation_pack_canonical_json(unname(as.list(ids))))
  .wb_operation_pack_canonical_string_array(ids)
}

.wb_operation_pack_matrix_digest_open <- function() {
  loadNamespace("openssl")
  provider <- getLoadedDLLs()[["openssl"]]
  if (is.null(provider)) return(NULL)
  .Call(C_scwb_matrix_digest_open, provider[["path"]])
}

.wb_operation_pack_matrix_stream_identity <- function(features, cells,
    read_columns, chunk_size, .owned_csc = NULL) {
  sink <- .wb_operation_pack_matrix_digest_open()
  path <- con <- NULL
  on.exit({
    if (!is.null(sink)) .Call(C_scwb_matrix_digest_close, sink)
    if (!is.null(con)) try(close(con), silent = TRUE)
    if (!is.null(path)) unlink(path)
  }, add = TRUE)
  if (is.null(sink)) {
    path <- tempfile("scwb_matrix_identity_")
    con <- file(path, "wb")
  }
  emit <- function(x) {
    bytes <- charToRaw(enc2utf8(x))
    if (is.null(sink)) writeBin(bytes, con)
    else .Call(C_scwb_matrix_digest_update, sink, bytes)
  }
  encode <- .wb_operation_pack_canonical_json
  emit(paste0('{"cell_id":', .wb_operation_pack_matrix_axis_json(cells),
    ',"dimensions":', encode(list(as.integer(length(features)),
      as.integer(length(cells)))), ',"entries":['))
  if (is.null(sink)) close(con)
  first <- TRUE
  # Only the literal already-owned selected-value caller opts in. Every
  # ordinary source callback retains its existing bounded schedule. Admission
  # declines opaque/malformed carriers BEFORE appending any entry bytes.
  ordinary_width <- !is.null(.owned_csc) && typeof(chunk_size) %in% c("integer", "double") &&
    !is.object(chunk_size) && is.null(attributes(chunk_size)) && length(chunk_size) == 1L &&
    !is.na(chunk_size) && is.finite(chunk_size) && chunk_size >= 1 &&
    chunk_size <= .Machine$integer.max && chunk_size == floor(chunk_size)
  owned <- ordinary_width && (isTRUE(.Call(C_scwb_matrix_slice_csc_append,
    if (is.null(sink)) path else sink, .owned_csc,
    as.integer(length(features)), as.integer(length(cells)))) ||
    isTRUE(.Call(C_scwb_matrix_slice_dense_append,
      if (is.null(sink)) path else sink, .owned_csc,
      as.integer(length(features)), as.integer(length(cells)))))
  if (!owned) for (start in seq.int(1L, max(1L, length(cells)), by = chunk_size)) {
    if (!length(cells)) break
    end <- min(length(cells), start + chunk_size - 1L)
    matrix <- read_columns(seq.int(start, end))
    logical_values <- is.logical(matrix) || inherits(matrix, "lMatrix") ||
      inherits(matrix, "nMatrix")
    if (!identical(as.integer(dim(matrix)),
        as.integer(c(length(features), end - start + 1L))))
      stop("Matrix identity reader returned incorrect dimensions.", call. = FALSE)
    # Coercion is bounded by the selected columns, never a complete source.
    sparse <- methods::as(methods::as(Matrix::Matrix(matrix, sparse = TRUE),
      "generalMatrix"), "CsparseMatrix")
    if (!inherits(sparse, "dMatrix")) sparse <- methods::as(sparse, "dMatrix")
    columns <- rep.int(seq_len(ncol(sparse)), diff(sparse@p)) + start - 1L
    keep <- which(!is.na(sparse@x) & sparse@x != 0)
    for (offset in seq.int(1L, max(1L, length(keep)), by = 8192L)) {
      if (!length(keep)) break
      idx <- keep[seq.int(offset, min(length(keep), offset + 8191L))]
      .Call(C_scwb_matrix_slice_append, if (is.null(sink)) path else sink,
        as.integer(sparse@i[idx] + 1L), as.integer(columns[idx]),
        if (logical_values) as.logical(sparse@x[idx]) else
          as.double(sparse@x[idx]), first)
      first <- FALSE
    }
  }
  if (is.null(sink)) con <- file(path, "ab")
  emit(paste0('],"feature_id":', .wb_operation_pack_matrix_axis_json(features),
    ',"kind":"matrix","schema":"scworkbench.operation_pack.matrix_slice.content.v1"}'))
  if (is.null(sink)) {
    close(con)
    input <- file(path, "rb")
    sha <- tryCatch(unclass(as.character(openssl::sha256(input))),
      finally = close(input))
  } else sha <- .Call(C_scwb_matrix_digest_finish, sink)
  list(scheme = "scworkbench.operation_pack.matrix_slice.content.v1", sha256 = sha)
}

# Private, short-lived evidence for a trusted R invocation, not a mutable-input
# content cache. Full hashes are still recomputed at publication. A transient
# mutation restored before publication is outside this approved trust model.
.wb_operation_pack_matrix_light_guard <- function(bundle, matrix_id) {
  issuing_con <- bundle$con
  observe <- function() {
    if (!DBI::dbIsValid(issuing_con) || !identical(bundle$con@ref, issuing_con@ref))
      stop("Matrix source issuing connection changed or closed.", call. = FALSE)
    fragments <- wb_matrix_fragments(bundle, matrix_id)
    registry <- DBI::dbGetQuery(bundle$con,
      "SELECT * FROM matrices WHERE matrix_id=?;", params = list(matrix_id))
    roots <- vapply(as.character(fragments$path), function(path)
      .wb_bundle_path_require(bundle, path, expected_type = "directory",
        purpose = "trusted R matrix reader"), character(1))
    paths <- sort(unique(c(roots, unlist(lapply(roots, function(root)
      as.character(fs::dir_ls(root, recurse = TRUE, type = "any",
        all = TRUE, follow = FALSE))), use.names = FALSE))), method = "radix")
    info <- file.info(paths)
    if (anyNA(info$size)) stop("Matrix source file disappeared.", call. = FALSE)
    list(registry = registry, fragments = fragments, paths = paths,
      resolved = normalizePath(paths, winslash = "/", mustWork = TRUE),
      info = info[, c("size", "isdir", "mode", "mtime", "ctime"), drop = FALSE])
  }
  initial <- observe()
  function() {
    observed <- tryCatch(observe(), error = function(e) NULL)
    if (!identical(observed, initial)) .wb_operation_pack_v3_error(
      "PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Typed-slice source changed after authentication: trusted R registry or file evidence differs between chunks.",
      "execution")
    invisible(TRUE)
  }
}
