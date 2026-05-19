test_contract_catalogs_semantic <- function() {
  wr <- wb_wrangler_catalog_semantic()
  stopifnot(is.list(wr))
  stopifnot(identical(as.character(wr$schema_version), "scworkbench.wrangler_catalog.semantic.v1"))
  stopifnot(is.list(wr$wranglers), length(wr$wranglers) >= 5)
  wr_ids <- vapply(wr$wranglers, function(x) as.character(x$wrangler_id %||% ""), character(1))
  stopifnot(all(nzchar(wr_ids)), !anyDuplicated(wr_ids))
  stopifnot("table:primitive_to_table" %in% wr_ids)
  stopifnot(any(grepl("^plot_mapper:", wr_ids)))

  pr <- wb_primitive_catalog_semantic()
  stopifnot(is.list(pr))
  stopifnot(identical(as.character(pr$schema_version), "scworkbench.primitive_catalog.semantic.v1"))
  prim_ids <- vapply(pr$primitives, function(x) as.character(x$primitive_kind %||% ""), character(1))
  stopifnot(all(c("matrix", "space", "cell_vector", "cell_vector_family", "feature_table", "obs_table", "model_ref", "path_2d_family", "space_path_family", "relation_family") %in% prim_ids))
  stopifnot(!anyDuplicated(prim_ids))

  ar <- wb_artifact_type_catalog_semantic()
  stopifnot(is.list(ar))
  stopifnot(identical(as.character(ar$schema_version), "scworkbench.artifact_type_catalog.semantic.v1"))
  art_ids <- vapply(ar$artifact_types, function(x) as.character(x$artifact_type %||% ""), character(1))
  stopifnot(all(nzchar(art_ids)), !anyDuplicated(art_ids))
  stopifnot(all(c("cell_vector", "obs_table:trajectory_geneset_dynamics", "obs_table:trajectory_signal_dynamics", "feature_table:de_wilcox") %in% art_ids))

  tmp <- tempfile("semantic_contract_catalogs_")
  dir.create(tmp)
  wb_write_wrangler_catalog_reference(file.path(tmp, "wr.md"), file.path(tmp, "wr.json"))
  wb_write_primitive_catalog_reference(file.path(tmp, "pr.md"), file.path(tmp, "pr.json"))
  wb_write_artifact_type_catalog_reference(file.path(tmp, "ar.md"), file.path(tmp, "ar.json"))
  for (fn in c("wr.json", "pr.json", "ar.json")) {
    txt <- paste(readLines(file.path(tmp, fn), warn = FALSE), collapse = "\n")
    stopifnot(jsonlite::validate(txt))
  }
  stopifnot(any(grepl("^### `table:primitive_to_table`", readLines(file.path(tmp, "wr.md"), warn = FALSE))))
  stopifnot(any(grepl("^### `cell_vector`", readLines(file.path(tmp, "pr.md"), warn = FALSE))))
  stopifnot(any(grepl("^### `obs_table:trajectory_geneset_dynamics`", readLines(file.path(tmp, "ar.md"), warn = FALSE))))

  TRUE
}
