graph_small_fingerprint <- function(root) {
  files <- sort(list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE,
    no.. = TRUE), method = "radix")
  files <- files[!file.info(files)$isdir]
  stats::setNames(vapply(files, function(path) digest::digest(file = path,
    algo = "sha256", serialize = FALSE), character(1)), substring(files, nchar(root) + 2L))
}
graph_small_rows <- function(bundle, artifact, policy) {
  components <- c("nodes", "edges", "incidences", "attribute_fields", "attribute_values",
    "bindings", "binding_mappings")
  stats::setNames(lapply(components, function(component) {
    rows <- list(); offset <- 0L
    repeat {
      page <- wb_art_graph_slice(bundle, artifact, component, offset = as.character(offset),
        limit = 2L, partition_bytes = policy$partition_bytes)
      if (!length(page)) break
      stopifnot(length(page) <= 2L)
      rows <- c(rows, page); offset <- offset + length(page)
    }
    rows
  }), components)
}
graph_small_assert <- function(bundle, artifact, expected, policy) {
  info <- wb_art_graph_info(bundle, artifact, policy)
  identity <- wb_graph_identity(expected)
  for (field in c("content_identity", "binding_identity", "descriptor_identity"))
    stopifnot(identical(info[[field]], identity[[field]]))
  stopifnot(info$canonical_bytes == "22564", info$source_authority$status == "verified")
  records <- graph_small_rows(bundle, artifact, policy)
  restored <- scworkbench:::.wb_graph_records_to_primitive("mixed", records)
  canonical <- scworkbench:::.wb_operation_pack_canonical_json
  stopifnot(identical(canonical(restored), canonical(expected)),
    identical(vapply(records, length, integer(1)), c(nodes = 32L, edges = 4L,
      incidences = 39L, attribute_fields = 6L, attribute_values = 140L,
      bindings = 3L, binding_mappings = 34L)),
    length(records$bindings[[3L]]) > 0L,
    !any(vapply(records$binding_mappings, function(row) row$binding_id == "empty_features", logical(1))))
  info
}
