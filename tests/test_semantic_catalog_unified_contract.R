test_semantic_catalog_unified_contract <- function() {
  cat_sem <- wb_semantic_catalog()
  stopifnot(is.list(cat_sem))
  stopifnot(identical(as.character(cat_sem$schema_version), "scworkbench.semantic_catalog.v1"))
  stopifnot(is.list(cat_sem$records), length(cat_sem$records) > 100)

  ids <- vapply(cat_sem$records, function(x) as.character(x$record_id %||% ""), character(1))
  stopifnot(all(nzchar(ids)), !anyDuplicated(ids))
  stopifnot(all(c("op:trajectory_geneset_dynamics", "getter:wb_art_list", "primitive:cell_vector", "artifact_type:obs_table:trajectory_geneset_dynamics", "parameter:cell_set", "parameter:mad_multiplier") %in% ids))

  graph <- wb_semantic_compatibility_graph()
  stopifnot(is.list(graph))
  stopifnot(identical(as.character(graph$schema_version), "scworkbench.semantic_compatibility_graph.v1"))
  stopifnot(length(graph$edges) > 20)
  edge_ids <- unique(unlist(lapply(graph$edges, function(e) c(e$from, e$to)), use.names = FALSE))
  stopifnot(all(edge_ids %in% ids))
  edge_key <- vapply(graph$edges, function(e) paste(e$from, e$to, e$edge_type, sep = "|"), character(1))
  stopifnot(any(edge_key == "op:trajectory_geneset_dynamics|parameter:score_method|has_parameter_semantics"))

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

test_parameter_semantics_catalog_contract <- function() {
  cat_sem <- wb_parameter_semantics_catalog()
  stopifnot(is.list(cat_sem))
  stopifnot(identical(as.character(cat_sem$schema_version), "scworkbench.parameter_semantics_catalog.v1"))
  stopifnot(is.list(cat_sem$parameters), length(cat_sem$parameters) >= 20)
  ids <- vapply(cat_sem$parameters, function(x) as.character(x$parameter_name %||% ""), character(1))
  stopifnot(!anyDuplicated(ids))
  stopifnot(all(c("cell_set", "pseudotime_direction", "score_method", "min_amplitude", "mad_multiplier") %in% ids))
  for (p in cat_sem$parameters) {
    stopifnot(nzchar(as.character(p$parameter_name %||% "")[1]))
    stopifnot(nzchar(as.character(p$title %||% "")[1]))
    stopifnot(nzchar(as.character(p$description %||% "")[1]))
    stopifnot(length(p$guidance %||% character(0)) >= 1)
  }
  tmp_md <- tempfile("parameter_semantics_", fileext = ".md")
  tmp_json <- tempfile("parameter_semantics_", fileext = ".json")
  wb_write_parameter_semantics_reference(path_md = tmp_md, path_json = tmp_json)
  stopifnot(file.exists(tmp_md), file.exists(tmp_json))
  stopifnot(jsonlite::validate(paste(readLines(tmp_json, warn = FALSE), collapse = "\n")))
  md <- readLines(tmp_md, warn = FALSE)
  stopifnot(any(grepl("^### `cell_set`", md)))
  stopifnot(any(grepl("^### `mad_multiplier`", md)))
  TRUE
}
