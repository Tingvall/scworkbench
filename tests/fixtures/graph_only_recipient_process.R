args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 5L)
if (file.exists(file.path(args[[1L]], "Meta", "package.rds"))) {
  .libPaths(c(dirname(args[[1L]]), .libPaths()))
  library(scworkbench)
} else devtools::load_all(args[[1L]], quiet = TRUE)
root <- args[[2L]]; artifact <- args[[3L]]
fingerprint <- function() {
  files <- sort(list.files(root, recursive = TRUE, full.names = TRUE,
    all.files = TRUE, no.. = TRUE), method = "radix")
  files <- files[!file.info(files)$isdir]
  stats::setNames(vapply(files, function(file) digest::digest(file = file,
    algo = "sha256", serialize = FALSE), character(1)), substring(files, nchar(root) + 2L))
}
before <- fingerprint()
bundle <- wb_open_bundle(root, read_only = TRUE)
stopifnot(!"graphonlyfixture::emit_graph" %in% wb_list_ops(),
  length(wb_cells(bundle, "all")) == 0L, nrow(wb_matrices(bundle)) == 0L)
info <- wb_art_graph_info(bundle, artifact)
stopifnot(info$source_authority$status == "verified", info$component_counts$bindings == "0",
  info$content_identity$sha256 == args[[4L]], info$descriptor_identity$sha256 == args[[5L]],
  identical(vapply(wb_art_graph_slice(bundle, artifact, "nodes"), `[[`, character(1), "node_id"),
    c("HEL", "ARN", "TLL")))
wb_close_bundle(bundle)
report <- wb_bundle_validation_report(root, level = "recipient")
if (!report$ok) print(report$diagnostics)
stopifnot(report$ok, identical(report$pre_validation_fingerprint, report$post_validation_fingerprint),
  identical(before, fingerprint()))
cat("GRAPH_ONLY_RECIPIENT cells=0 matrices=0 nodes=3 bindings=0 pack_free=TRUE read_only=TRUE recipient=PASS filesystem_pure=TRUE\n")
