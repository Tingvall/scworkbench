args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 4L)
devtools::load_all(args[[1L]], quiet = TRUE)
bundle_dir <- args[[2L]]
artifact_id <- args[[3L]]
descriptor_sha256 <- args[[4L]]
fingerprint <- function() {
  files <- sort(list.files(bundle_dir, recursive = TRUE, all.files = TRUE,
    full.names = TRUE, no.. = TRUE), method = "radix")
  files <- files[!file.info(files)$isdir]
  stats::setNames(vapply(files, function(path) digest::digest(file = path,
    algo = "sha256", serialize = FALSE), character(1)),
    substring(files, nchar(bundle_dir) + 2L))
}
before <- fingerprint()
bundle <- wb_open_bundle(bundle_dir, read_only = TRUE)
stopifnot(!"scwbgraphfixture::graph_to_table" %in% wb_list_ops())
missing_pack_copy <- tempfile("graph_missing_pack_")
fs::dir_copy(bundle_dir, missing_pack_copy)
writable <- wb_open_bundle(missing_pack_copy)
failed <- tryCatch(wb_session_run_op(wb_session_new(), writable,
  "scwbgraphfixture::graph_to_table", inputs = list(source = wb_ref_artifact(artifact_id, "result"))), error = identity)
wb_close_bundle(writable)
stopifnot(inherits(failed, "wb_operation_pack_unavailable"))
unlink(missing_pack_copy, recursive = TRUE)
graph <- wb_art_load(bundle, artifact_id, expected_kind = "graph")
info <- wb_art_graph_info(bundle, artifact_id)
stopifnot(identical(info$descriptor_identity$sha256, descriptor_sha256),
  identical(graph$descriptor_identity, info$descriptor_identity),
  identical(info$source_authority$status, "verified"),
  identical(info$component_counts$bindings, "1"),
  identical(vapply(wb_art_graph_slice(bundle, artifact_id, "nodes"),
    `[[`, character(1), "node_id"), c("c2", "c1")))
wb_close_bundle(bundle)
report <- wb_bundle_validation_report(bundle_dir, level = "recipient")
if (!isTRUE(report$ok)) print(report$diagnostics)
stopifnot(isTRUE(report$ok), identical(report$pre_validation_fingerprint,
  report$post_validation_fingerprint), identical(before, fingerprint()))
cat("GRAPH_RECIPIENT_PROCESS pack_free=TRUE read_only=TRUE relocated=TRUE",
  "descriptor_unchanged=TRUE sources_verified=TRUE missing_pack_rejected=TRUE recipient=PASS fingerprint_unchanged=TRUE\n")
