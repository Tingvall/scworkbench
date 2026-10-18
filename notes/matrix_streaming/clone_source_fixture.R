args <- commandArgs(TRUE)
stopifnot(length(args) == 3L)
.libPaths(c(args[3L], .libPaths()))
suppressPackageStartupMessages(library(scworkbench))
source <- normalizePath(args[1L], mustWork = TRUE)
destination <- args[2L]
stopifnot(!dir.exists(destination))
lock <- wb_bundle_writer_lock_info(source)
if (isTRUE(lock$locked)) {
  stopifnot(identical(lock$owner_status, "dead"))
  print(lock)
  wb_recover_bundle_writer_lock(source, "RECOVER STALE SCWORKBENCH WRITER LOCK")
}
b <- wb_open_bundle(source, validate = FALSE)
stopifnot(identical(as.character(wb_matrices(b)$matrix_id), "counts"),
  !any(c("rna.pca", "rna.umap") %in% wb_spaces(b)$space_id))
wb_finalize_recipient_bundle(b); wb_close_bundle(b)
dir.create(destination, recursive = TRUE)
children <- list.files(source, full.names = TRUE, all.files = TRUE, no.. = TRUE)
stopifnot(all(file.copy(children, destination, recursive = TRUE)))
b <- wb_open_bundle(destination, read_only = TRUE, validate = FALSE)
stopifnot(identical(as.character(wb_matrices(b)$matrix_id), "counts"))
wb_close_bundle(b)
cat("FINALIZED_SOURCE_ONLY_FIXTURE_COPIED_NO_REINGESTION_OR_SOURCE_SPLIT\n")
