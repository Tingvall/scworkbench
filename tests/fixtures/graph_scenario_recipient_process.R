args <- commandArgs(TRUE)
stopifnot(length(args) == 3L)
devtools::load_all(args[[1L]], quiet = TRUE)
bundle_dir <- args[[2L]]
records <- readRDS(args[[3L]])
fingerprint <- function() {
  files <- sort(list.files(bundle_dir, recursive = TRUE, all.files = TRUE,
    full.names = TRUE, no.. = TRUE), method = "radix")
  files <- files[!file.info(files)$isdir]
  stats::setNames(vapply(files, function(path) digest::digest(file = path,
    algo = "sha256", serialize = FALSE), character(1)), substring(files, nchar(bundle_dir) + 2L))
}
before <- fingerprint()
stopifnot(!"graphscenariofixture::emit_scenario" %in% wb_list_ops())
bundle <- wb_open_bundle(bundle_dir, read_only = TRUE)
for (record in records) {
  reference <- wb_art_load(bundle, record$artifact_id, expected_kind = "graph")
  info <- wb_art_graph_info(bundle, record$artifact_id)
  for (field in c("content_identity", "binding_identity", "descriptor_identity")) {
    stopifnot(identical(reference[[field]], record$expected[[field]]),
      identical(info[[field]], record$expected[[field]]))
  }
  for (component in names(record$rows)) {
    observed <- list(); offset <- 0L
    repeat {
      part <- wb_art_graph_slice(bundle, record$artifact_id, component,
        as.character(offset), 2L)
      if (!length(part)) break
      observed <- c(observed, part); offset <- offset + length(part)
    }
    stopifnot(identical(scworkbench:::.wb_operation_pack_canonical_json(observed),
      scworkbench:::.wb_operation_pack_canonical_json(record$rows[[component]])))
  }
}
wb_close_bundle(bundle)
validation <- wb_bundle_validation_report(bundle_dir, level = "recipient")
if (!isTRUE(validation$ok)) print(validation$diagnostics)
stopifnot(validation$ok, identical(validation$pre_validation_fingerprint,
  validation$post_validation_fingerprint), identical(before, fingerprint()))
cat("GRAPH_SCENARIOS_RECIPIENT cases=", length(records),
  " process_replaced=TRUE relocated=TRUE pack_free=TRUE exact_components=TRUE recipient=PASS fingerprint_unchanged=TRUE\n", sep = "")
