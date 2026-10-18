args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L)
.libPaths(c(args[[1L]], .libPaths()))
suppressPackageStartupMessages(library(scworkbench))
# Deliberately retain the installed repaired baseline namespace. Load only the
# candidate emitter into a private namespace, without replacing installed code.
dll <- dyn.load(args[[2L]])
e <- new.env(parent = asNamespace("scworkbench"))
e$C_scwb_matrix_slice_append <- getNativeSymbolInfo(
  "scwb_matrix_slice_append", dll)$address
sys.source("R/operation_pack_matrix_stream.R", e)
sys.source("tests/test_engine_matrix_encoding_contract.R", e)
functions <- ls(e, pattern = "^test_")
for (name in functions) {
  stopifnot(isTRUE(e[[name]]()))
  cat(name, "PASS\n")
}
cat(sprintf("FOCUSED discovered=%d executed=%d passed=%d skipped=0 failed=0\n",
  length(functions), length(functions), length(functions)))
ids <- paste0("ENSG", sprintf("%011d", seq_len(31535L)))
old_axis <- system.time(for (i in seq_len(3L)) before <-
  scworkbench:::.wb_operation_pack_canonical_json(unname(as.list(ids))))[["elapsed"]] / 3
new_axis <- system.time(for (i in seq_len(30L)) after <-
  e$.wb_operation_pack_matrix_axis_json(ids))[["elapsed"]] / 30
stopifnot(identical(before, after))
cat(sprintf("AXIS old_seconds=%.6f new_seconds=%.6f speedup=%.3f sha256=%s\n",
  old_axis, new_axis, old_axis / new_axis,
  digest::digest(before, algo = "sha256", serialize = FALSE)))
set.seed(32)
values <- matrix(rpois(2000L * 2000L, .3), 2000L)
features <- paste0("f", seq_len(2000L)); cells <- paste0("c", seq_len(2000L))
for (i in seq_len(3L)) {
  old <- system.time(before <-
    scworkbench:::.wb_operation_pack_v3_matrix_slice_content(values,
      features, cells))[["elapsed"]]
  new <- system.time(after <- e$.wb_operation_pack_matrix_stream_identity(
    features, cells, function(columns) values[, columns, drop = FALSE],
    128L))[["elapsed"]]
  stopifnot(identical(before, after))
  cat(sprintf("SLICE replicate=%d old_seconds=%.6f new_seconds=%.6f speedup=%.3f sha256=%s\n",
    i, old, new, old / new, before$sha256))
}
