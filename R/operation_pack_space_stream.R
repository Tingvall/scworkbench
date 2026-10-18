# Byte-preserving streaming of the TWO existing typed-space preimages. These
# private readers and temporary preimages never cross the pack interface.
.wb_operation_pack_space_stream_hash <- function(emit_value, prefix = "", suffix = "") {
  path <- tempfile("scwb_space_identity_")
  con <- NULL
  on.exit({if (!is.null(con)) try(close(con), silent = TRUE); unlink(path)}, add = TRUE)
  con <- file(path, "wb")
  emit <- function(value) writeBin(charToRaw(enc2utf8(value)), con)
  emit(prefix); emit_value(emit); emit(suffix); close(con)
  input <- file(path, "rb")
  tryCatch(unclass(as.character(openssl::sha256(input))), finally = close(input))
}

.wb_operation_pack_space_stream_elements <- function(plan = NULL) {
  limit <- as.double(getOption("scworkbench.max_dense_materialize_mb", 256)) * 1024^2
  if (!is.finite(limit) || limit <= 8192) stop("Typed-space identity block budget is invalid.", call. = FALSE)
  elements <- max(1L, floor((min(limit, 32*1024^2) - 8192) / 64))
  if (!is.null(plan) && is.function(plan$block_elements)) elements <- min(elements,plan$block_elements())
  elements
}

.wb_operation_pack_space_stream_rows <- function(dimensions, plan = NULL)
  max(1L, min(512L, floor(.wb_operation_pack_space_stream_elements(plan) / max(1L, dimensions))))

.wb_operation_pack_space_json_bound <- function(value) {
  if (is.null(value)) return(4)
  if (is.factor(value)) value <- as.character(value)
  if (is.character(value)) return(sum(24*as.double(nchar(value,type="bytes",allowNA=TRUE))+3,na.rm=TRUE)+4*sum(is.na(value))+2)
  if (is.atomic(value)) return(32*as.double(length(value))+2)
  if (is.list(value)) return(2+sum(vapply(value,.wb_operation_pack_space_json_bound,numeric(1)))+
    if (is.null(names(value))) length(value) else .wb_operation_pack_space_json_bound(names(value))+length(value))
  # Unsupported metadata still receives the canonical encoder's established diagnostic.
  .wb_operation_pack_canonical_json(value)
  0
}

.wb_operation_pack_space_scratch_admit <- function(bytes, plan = NULL) {
  if (!is.finite(bytes) || bytes < 0 || bytes > .wb_operation_pack_v3_broker_free_bytes(tempdir()))
    stop("Insufficient admitted disk capacity for typed-space identity scratch.", call. = FALSE)
  if (!is.null(plan) && is.function(plan$admit)) return(plan$admit(bytes))
  function() invisible(NULL)
}

.wb_operation_pack_space_semantic_identity <- function(cells, dimensions, read, plan = NULL) {
  schema <- "scworkbench.operation_pack.space_slice.content.v1"
  encode <- .wb_operation_pack_canonical_json
  restore <- .wb_operation_pack_space_scratch_admit(32 * as.double(length(cells)) * dimensions +
    2 * .wb_operation_pack_space_json_bound(cells) + 8192, plan)
  on.exit(restore(), add = TRUE)
  sha <- .wb_operation_pack_space_stream_hash(function(emit) {
    emit(paste0('{"cell_id":', .wb_operation_pack_matrix_axis_json(cells),
      ',"dimensions":', encode(list(as.integer(length(cells)), as.integer(dimensions))),
      ',"schema":', encode(schema), ',"values":['))
    first <- TRUE
    if (dimensions > .wb_operation_pack_space_stream_elements(plan)) {
      # Very wide spaces: even one complete row need not fit the guard.
      for (cell in cells) {
        emit(paste0(if (first) "[" else ",["))
        first_dimension <- TRUE
        for (start in seq.int(1L, dimensions, by = .wb_operation_pack_space_stream_elements(plan))) {
          selected_dims <- seq.int(start, min(dimensions, start + .wb_operation_pack_space_stream_elements(plan)-1L))
          block <- read(cell, selected_dims)
          if (!identical(as.integer(dim(block)), c(1L, as.integer(length(selected_dims)))) ||
              !identical(rownames(block), cell)) stop("Typed-space identity reader returned misaligned values.", call. = FALSE)
          json <- encode(unname(as.list(as.numeric(block))))
          emit(paste0(if (first_dimension) "" else ",", substr(json, 2L, nchar(json)-1L)))
          first_dimension <- FALSE
        }
        emit("]"); first <- FALSE
      }
      emit("]}"); return(invisible(NULL))
    }
    for (start in seq.int(1L, max(1L, length(cells)), by = .wb_operation_pack_space_stream_rows(dimensions,plan))) {
      if (!length(cells)) break
      end <- min(length(cells), start + .wb_operation_pack_space_stream_rows(dimensions,plan) - 1L)
      selected <- cells[seq.int(start, end)]
      block <- read(selected)
      if (!identical(as.integer(dim(block)), as.integer(c(length(selected), dimensions))) ||
          !identical(rownames(block), selected)) stop("Typed-space identity reader returned misaligned values.", call. = FALSE)
      rows <- lapply(seq_len(nrow(block)), function(i) unname(as.list(as.numeric(block[i, ]))))
      json <- encode(rows)
      emit(paste0(if (first) "" else ",", substr(json, 2L, nchar(json)-1L)))
      first <- FALSE
    }
    emit("]}")
  })
  list(scheme = schema, sha256 = sha)
}

.wb_operation_pack_space_envelope_identities <- function(name, value, plan) {
  # Encode all non-coordinate fields with the authoritative canonical encoder;
  # matrix attributes never entered that encoder's historical atomic preimage.
  envelope <- unclass(value)
  envelope$values <- NULL
  keys <- sort(c(names(envelope), "values"), method = "radix")
  if (anyDuplicated(keys)) stop("Duplicate space envelope keys.", call. = FALSE)
  encode <- .wb_operation_pack_canonical_json
  restore <- .wb_operation_pack_space_scratch_admit(72 * as.double(plan$dimensions[[1L]]) *
    plan$dimensions[[2L]] + 2 * .wb_operation_pack_space_json_bound(envelope) + 8192, plan)
  on.exit(restore(), add = TRUE)
  # One bounded selected-source pass builds numeric column-major scratch.
  # Descriptor and wrapper then consume the same bytes, not repeated HDF5
  # dimension scans. The scratch is an owned invocation file, never authority.
  path <- tempfile("scwb_space_column_major_")
  spool <- NULL
  on.exit({if (!is.null(spool)) try(close(spool), silent = TRUE); unlink(path)}, add = TRUE, after = FALSE)
  spool <- file(path, "w+b")
  dimension_chunk <- max(1L, min(128L, plan$dimensions[[2L]], .wb_operation_pack_space_stream_elements(plan)))
  row_chunk <- .wb_operation_pack_space_stream_rows(dimension_chunk,plan)
  for (start in seq.int(1L, max(1L, length(plan$cells)), by = row_chunk)) {
    if (!length(plan$cells)) break
    selected <- plan$cells[seq.int(start, min(length(plan$cells), start + row_chunk-1L))]
    for (dimension_start in seq.int(1L, max(1L, plan$dimensions[[2L]]), by = dimension_chunk)) {
      if (!plan$dimensions[[2L]]) break
      dimensions <- seq.int(dimension_start, min(plan$dimensions[[2L]], dimension_start + dimension_chunk-1L))
      block <- plan$read(selected, dimensions)
      if (!identical(rownames(block), selected) ||
          !identical(as.integer(dim(block)), c(as.integer(length(selected)), as.integer(length(dimensions)))))
        stop("Space envelope reader returned misaligned values.", call. = FALSE)
      for (j in seq_along(dimensions)) {
        seek(spool, where = (as.double(dimensions[[j]]-1L) * length(plan$cells) + start-1L) * 8,
          origin = "start", rw = "write")
        writeBin(as.double(block[, j]), spool, size = 8L, endian = "little")
      }
    }
  }
  close(spool)
  emit_envelope <- function(emit) {
    emit("{")
    for (j in seq_along(keys)) {
      key <- keys[[j]]
      emit(paste0(if (j == 1L) "" else ",", encode(key), ":"))
      if (key != "values") { emit(encode(envelope[[key]])); next }
      count <- as.double(plan$dimensions[[1L]]) * plan$dimensions[[2L]]
      if (count != 1) emit("[")
      first <- TRUE
      spool_input <- file(path, "rb")
      on.exit(close(spool_input), add = TRUE)
      for (dimension in seq_len(plan$dimensions[[2L]])) {
        for (start in seq.int(1L, max(1L, length(plan$cells)), by = .wb_operation_pack_space_stream_rows(1L,plan))) {
          if (!length(plan$cells)) break
          selected <- plan$cells[seq.int(start, min(length(plan$cells), start + .wb_operation_pack_space_stream_rows(1L,plan)-1L))]
          block <- readBin(spool_input, "double", n = length(selected), size = 8L, endian = "little")
          if (length(block) != length(selected)) stop("Truncated typed-space identity scratch.", call. = FALSE)
          json <- encode(unname(as.list(block)))
          emit(paste0(if (first) "" else ",", substr(json, 2L, nchar(json)-1L)))
          first <- FALSE
        }
      }
      if (count != 1) emit("]")
    }
    emit("}")
  }
  # Two streamed observations, not stored or pack-supplied digest authority.
  list(value_sha = .wb_operation_pack_space_stream_hash(emit_envelope),
    wrapped_sha = .wb_operation_pack_space_stream_hash(emit_envelope,
      paste0('{"input":', encode(name), ',"value":'), "}"))
}
