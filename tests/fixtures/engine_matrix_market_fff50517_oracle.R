.matrix_market_frozen_oracle <- function(values, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- paste0(path, ".pending")
  if (file.exists(temporary)) unlink(temporary, force = TRUE)
  dense <- as.matrix(values)
  storage.mode(dense) <- "double"
  if (any(!is.finite(dense))) .wb_operation_pack_v3_error(
    "PYBENCH_CAPABILITY_MISMATCH",
    "Typed-slice Matrix Market values must be finite.", "staging")
  indices <- which(dense != 0, arr.ind = TRUE)
  if (length(indices)) indices <- indices[order(indices[, 2L],
    indices[, 1L]), , drop = FALSE]
  entries <- if (!nrow(indices)) character() else
    vapply(seq_len(nrow(indices)), function(i) paste(
      as.integer(indices[i, 1L]), as.integer(indices[i, 2L]),
      .wb_operation_pack_canonical_number(.wb_operation_pack_number_token(
        dense[indices[i, 1L], indices[i, 2L]]))), character(1))
  lines <- c("%%MatrixMarket matrix coordinate real general",
    paste(nrow(dense), ncol(dense), nrow(indices)), entries)
  writeBin(charToRaw(paste0(paste(lines, collapse = "\n"), "\n")),
    temporary)
  if (!file.rename(temporary, path)) {
    unlink(temporary, force = TRUE)
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Could not atomically stage a typed-slice private source.", "staging")
  }
  invisible(path)
}
