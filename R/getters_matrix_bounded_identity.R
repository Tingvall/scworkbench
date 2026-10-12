# Private physical-storage observation for native graph source verification.
# BPCells open_matrix_dir eagerly loads both names vectors. Its directory format
# instead permits bounded observations of the same shape and newline names.
# No physical path, SQL or storage authority crosses the pack boundary.
.wb_matrix_bounded_line_reader <- function(path, budgets, maximum = 256L) {
  input <- file(path, "rb")
  pending <- raw(); eof <- FALSE; retired <- FALSE
  close_reader <- function() {
    if (!retired) { close(input); retired <<- TRUE }
    invisible(NULL)
  }
  next_line <- function() {
    repeat {
      newline <- which(pending == as.raw(10L))
      if (length(newline)) {
        end <- newline[[1L]]
        line <- if (end == 1L) raw() else pending[seq_len(end - 1L)]
        pending <<- if (end == length(pending)) raw() else pending[seq.int(end + 1L, length(pending))]
        break
      }
      .wb_graph_require(length(pending) <= maximum + 1L, "GRAPH_RESOURCE_EXCEEDED",
        "Matrix storage axis line exceeds bounded admission before decoding.")
      if (eof) {
        if (!length(pending)) return(NULL)
        line <- pending; pending <<- raw(); break
      }
      chunk <- readBin(input, "raw", n = min(65536L, budgets$partition_bytes))
      eof <<- !length(chunk)
      pending <<- c(pending, chunk)
    }
    # BPCells binaryfile.cpp readLines() removes one trailing CR, including at EOF.
    if (length(line) && utils::tail(line, 1L) == as.raw(13L)) line <- head(line, -1L)
    .wb_graph_require(length(line) <= maximum && !any(line == as.raw(0)),
      "GRAPH_SOURCE_PAYLOAD_INVALID", "Matrix storage axis contains oversized/NUL names.")
    value <- rawToChar(line)
    .wb_graph_require(!is.na(iconv(value, from = "UTF-8", to = "UTF-8")),
      "GRAPH_SOURCE_PAYLOAD_INVALID", "Matrix storage axis is not valid UTF-8.")
    Encoding(value) <- "UTF-8"
    value
  }
  list(next_line = next_line, close = close_reader)
}

.wb_matrix_bounded_storage_header <- function(root, budgets) {
  shape_path <- file.path(root, "shape")
  .wb_graph_require(file.exists(shape_path) && file.info(shape_path)$size == 16,
    "GRAPH_SOURCE_PAYLOAD_INVALID", "BPCells shape has an invalid length.")
  input <- file(shape_path, "rb")
  shape <- tryCatch(readBin(input, "raw", n = 16L), finally = close(input))
  magic <- rawToChar(shape[1:8])
  .wb_graph_require(magic %in% c("UINT32v1", "TNIU1v23"),
    "GRAPH_SOURCE_PAYLOAD_INVALID", "Unknown BPCells UINT32 shape encoding.")
  order <- if (magic == "UINT32v1") "little" else "big"
  # Decode unsigned u32 without signed overflow. R doubles represent all u32.
  decode <- function(bytes) sum(as.numeric(bytes) * 256^(if (order == "little") 0:3 else 3:0))
  dims <- c(decode(shape[9:12]), decode(shape[13:16]))
  reader <- .wb_matrix_bounded_line_reader(file.path(root, "storage_order"), budgets, 64L)
  storage <- tryCatch({value <- reader$next_line()
    .wb_graph_require(!is.null(value) && value %in% c("row", "col") && is.null(reader$next_line()),
      "GRAPH_SOURCE_PAYLOAD_INVALID", "BPCells storage order is invalid.")
    value}, finally = reader$close())
  reader <- .wb_matrix_bounded_line_reader(file.path(root, "version"), budgets, 128L)
  version <- tryCatch({value <- reader$next_line()
    .wb_graph_require(!is.null(value) && grepl("^(unpacked|packed)-(uint|float|double)-matrix-v[12]$", value) &&
      is.null(reader$next_line()), "GRAPH_SOURCE_PAYLOAD_INVALID", "Unsupported BPCells matrix version.")
    value}, finally = reader$close())
  pointer_path <- file.path(root, "idxptr")
  major_count <- if (storage == "row") dims[[1L]] else dims[[2L]]
  .wb_graph_require(file.exists(pointer_path) &&
    file.info(pointer_path)$size == 8 + 8 * (major_count + 1),
    "GRAPH_SOURCE_PAYLOAD_INVALID", "BPCells pointer axis disagrees with physical shape.")
  input <- file(pointer_path, "rb")
  pointer_magic <- tryCatch(rawToChar(readBin(input, "raw", n = 8L)), finally = close(input))
  .wb_graph_require(pointer_magic %in% c("UINT64v1", "TNIU1v46"),
    "GRAPH_SOURCE_PAYLOAD_INVALID", "Unknown BPCells UINT64 pointer encoding.")
  # BPCells StoredMatrix first swaps names for physical row-major iteration;
  # dims_matrix_reader_builder swaps them back for the logical R view. Files
  # therefore retain logical row/column names irrespective of storage order.
  list(dimensions = dims, feature_names = file.path(root, "row_names"),
    cell_names = file.path(root, "col_names"),
    storage_order = storage, version = version)
}
