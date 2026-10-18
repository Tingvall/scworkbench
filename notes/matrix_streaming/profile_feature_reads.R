args <- commandArgs(TRUE)
.libPaths(c(args[2], .libPaths()))
suppressPackageStartupMessages(library(scworkbench))
source("tests/test_operation_pack_matrix_streaming_contract.R")
b <- wb_open_bundle(file.path(args[1], "xenopus.bundle"), validate = FALSE, read_only = TRUE)
cells <- wb_cells_with_matrix(b, "counts")
features <- wb_features(b, "counts")$feature_id
io <- function() {
  lines <- readLines("/proc/self/io")
  as.numeric(sub("rchar: *", "", grep("^rchar:", lines, value = TRUE)))
}
measure <- function(label, code) {
  before <- io(); start <- proc.time(); result <- force(code)
  cat(label, "elapsed", (proc.time() - start)[["elapsed"]],
    "rchar", io() - before, "\n"); flush.console(); result
}
blocks <- list(features[1:256], features[257:512])
old <- lapply(seq_along(blocks), function(i) measure(paste0("getter_feature_block_", i),
  wb_slice(b, "counts", blocks[[i]], cells)))
plan <- measure("reader_plan_row_major_index", scworkbench:::.wb_matrix_stream_reader(b, "counts", "features"))
for (i in seq_along(blocks)) {
  new <- measure(paste0("indexed_feature_block_", i), plan$read(blocks[[i]], cells))
  stopifnot(identical(as.matrix(new), as.matrix(old[[i]])))
}
print(system2("du", c("-s", shQuote(plan$root)), stdout = TRUE))
plan$close(); stopifnot(!dir.exists(plan$root))
small <- wb_slice(b, "counts", features, cells[1:8])
old_hash <- measure("legacy_semantic_identity_full_features_8_cells",
  .wb_matrix_slice_legacy_oracle(small, features, cells[1:8]))
new_hash <- measure("stream_semantic_identity_full_features_8_cells",
  scworkbench:::.wb_operation_pack_v3_matrix_slice_content(small, features, cells[1:8]))
stopifnot(identical(old_hash, new_hash))
cat("IDENTITIES_IDENTICAL", old_hash$sha256, "\n")
wb_close_bundle(b)
