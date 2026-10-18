# Stream the EXISTING matrix_slice.content.v1 canonical preimage. This is a
# representation optimization, not a new identity scheme. read_columns is
# core-private; pack readers retain their declared bounded public interface.
.wb_operation_pack_matrix_stream_identity <- function(features, cells,
    read_columns, chunk_size) {
  path <- tempfile("scwb_matrix_identity_")
  con <- file(path, "wb")
  on.exit({try(close(con), silent = TRUE); unlink(path)}, add = TRUE)
  emit <- function(x) writeBin(charToRaw(enc2utf8(x)), con)
  encode <- .wb_operation_pack_canonical_json
  emit(paste0('{"cell_id":', encode(unname(as.list(cells))),
    ',"dimensions":', encode(list(as.integer(length(features)),
      as.integer(length(cells)))), ',"entries":['))
  first <- TRUE
  for (start in seq.int(1L, max(1L, length(cells)), by = chunk_size)) {
    if (!length(cells)) break
    end <- min(length(cells), start + chunk_size - 1L)
    matrix <- read_columns(seq.int(start, end))
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
      records <- .Call(C_scwb_matrix_slice_entries,
        as.integer(sparse@i[idx] + 1L), as.integer(columns[idx]),
        as.double(sparse@x[idx]))
      emit(paste0(if (first) "" else ",", paste(records, collapse = ",")))
      first <- FALSE
    }
  }
  emit(paste0('],"feature_id":', encode(unname(as.list(features))),
    ',"kind":"matrix","schema":"scworkbench.operation_pack.matrix_slice.content.v1"}'))
  close(con)
  input <- file(path, "rb")
  sha <- tryCatch(unclass(as.character(openssl::sha256(input))),
    finally = close(input))
  list(scheme = "scworkbench.operation_pack.matrix_slice.content.v1", sha256 = sha)
}

# Private, short-lived evidence for a trusted R invocation, not a mutable-input
# content cache. Full hashes are still recomputed at publication. A transient
# mutation restored before publication is outside this approved trust model.
.wb_operation_pack_matrix_light_guard <- function(bundle, matrix_id) {
  observe <- function() {
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
