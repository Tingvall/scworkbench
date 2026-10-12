args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 4L)
if (file.exists(file.path(args[[1L]], "Meta", "package.rds"))) {
  .libPaths(c(dirname(args[[1L]]), .libPaths()))
  library(scworkbench)
} else devtools::load_all(args[[1L]], quiet = TRUE)
root <- args[[2L]]; artifact <- args[[3L]]; descriptor <- args[[4L]]
fingerprint <- function() {
  files <- sort(list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE,
    no.. = TRUE), method = "radix")
  files <- files[!file.info(files)$isdir]
  stats::setNames(vapply(files, function(path) digest::digest(file = path,
    algo = "sha256", serialize = FALSE), character(1)), substring(files, nchar(root) + 2L))
}
before <- fingerprint()
bundle <- wb_open_bundle(root, read_only = TRUE)
stopifnot(!any(c("scwbnativegraphfixture::matrix_to_bound_graph", "scwbnativegraphfixture::read_bound_graph",
  "scwbrna::matrix_log_normalize") %in% wb_list_ops()))
policy <- list(memory_bytes = "8388608", sqlite_cache_kib = 2048L,
  partition_bytes = 262144L, partition_rows = 256L, collect_bytes = 4194304L)
info <- wb_art_graph_info(bundle, artifact, policy)
stopifnot(info$source_authority$status == "verified", info$descriptor_identity$sha256 == descriptor,
  info$component_counts$bindings == "2", info$component_counts$binding_mappings == "3",
  identical(vapply(wb_art_graph_slice(bundle, artifact, "nodes"), `[[`, character(1), "node_id"),
    c("cell:c2", "cell:c1", "feature:g2")))
bindings <- wb_art_graph_slice(bundle, artifact, "bindings")
stopifnot(all(vapply(bindings, function(binding) binding$source_ref$kind == "matrix" &&
  binding$source_ref$source_id == "RNA_log", logical(1))))
wb_close_bundle(bundle)
report <- wb_bundle_validation_report(root, level = "recipient")
if (!report$ok) print(report$diagnostics)
stopifnot(report$ok, identical(report$pre_validation_fingerprint, report$post_validation_fingerprint),
  identical(before, fingerprint()))
cat("GRAPH_NATIVE_RECIPIENT pack_free=TRUE read_only=TRUE relocated=TRUE native_source_verified=TRUE",
  " descriptor_unchanged=TRUE selected_mappings_preserved=TRUE recipient=PASS fingerprint_unchanged=TRUE\n")
