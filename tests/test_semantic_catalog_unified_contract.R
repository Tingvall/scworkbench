test_semantic_catalog_unified_contract <- function() {
  cat_sem <- wb_semantic_catalog()
  stopifnot(is.list(cat_sem))
  stopifnot(identical(as.character(cat_sem$schema_version), "scworkbench.semantic_catalog.v1"))
  stopifnot(is.list(cat_sem$records), length(cat_sem$records) > 100)

  ids <- vapply(cat_sem$records, function(x) as.character(x$record_id %||% ""), character(1))
  stopifnot(all(nzchar(ids)), !anyDuplicated(ids))
  stopifnot(all(c("op:trajectory_geneset_dynamics", "getter:wb_art_list", "primitive:cell_vector", "artifact_type:obs_table:trajectory_geneset_dynamics") %in% ids))

  graph <- wb_semantic_compatibility_graph()
  stopifnot(is.list(graph))
  stopifnot(identical(as.character(graph$schema_version), "scworkbench.semantic_compatibility_graph.v1"))
  stopifnot(length(graph$edges) > 20)
  edge_ids <- unique(unlist(lapply(graph$edges, function(e) c(e$from, e$to)), use.names = FALSE))
  stopifnot(all(edge_ids %in% ids))

  audit <- wb_semantic_catalog_audit()
  stopifnot(is.list(audit))
  stopifnot(identical(as.character(audit$schema_version), "scworkbench.semantic_catalog_audit.v1"))
  stopifnot(isTRUE(audit$ok))

  tmp <- tempfile("semantic_catalog_")
  dir.create(tmp)
  wb_write_semantic_catalog_reference(
    path_md = file.path(tmp, "semantic.md"),
    path_json = file.path(tmp, "semantic.json"),
    path_graph = file.path(tmp, "graph.json"),
    path_audit = file.path(tmp, "audit.json")
  )
  for (fn in c("semantic.json", "graph.json", "audit.json")) {
    txt <- paste(readLines(file.path(tmp, fn), warn = FALSE), collapse = "\n")
    stopifnot(jsonlite::validate(txt))
  }
  md <- readLines(file.path(tmp, "semantic.md"), warn = FALSE)
  stopifnot(any(grepl("^### `op:trajectory_geneset_dynamics`", md)))

  TRUE
}
