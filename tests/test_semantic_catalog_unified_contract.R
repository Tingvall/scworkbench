test_semantic_catalog_unified_contract <- function() {
  cat_sem <- wb_semantic_catalog()
  stopifnot(is.list(cat_sem))
  stopifnot(identical(as.character(cat_sem$schema_version), "scworkbench.semantic_catalog.v1"))
  stopifnot(is.list(cat_sem$records), length(cat_sem$records) > 100)

  ids <- vapply(cat_sem$records, function(x) as.character(x$record_id %||% ""), character(1))
  stopifnot(all(nzchar(ids)), !anyDuplicated(ids))
  stopifnot(all(c("op:trajectory_geneset_dynamics", "getter:wb_art_list", "primitive:cell_vector", "artifact_type:obs_table:trajectory_geneset_dynamics", "parameter:cell_set", "parameter:mad_multiplier", "recipe:trajectory_geneset_dynamics_discovery") %in% ids))

  graph <- wb_semantic_compatibility_graph()
  stopifnot(is.list(graph))
  stopifnot(identical(as.character(graph$schema_version), "scworkbench.semantic_compatibility_graph.v1"))
  stopifnot(length(graph$edges) > 20)
  edge_ids <- unique(unlist(lapply(graph$edges, function(e) c(e$from, e$to)), use.names = FALSE))
  stopifnot(all(edge_ids %in% ids))
  edge_key <- vapply(graph$edges, function(e) paste(e$from, e$to, e$edge_type, sep = "|"), character(1))
  stopifnot(any(edge_key == "op:trajectory_geneset_dynamics|parameter:score_method|has_parameter_semantics"))
  stopifnot(any(edge_key == "recipe:trajectory_geneset_dynamics_discovery|op:trajectory_geneset_dynamics|uses"))

  audit <- wb_semantic_catalog_audit()
  stopifnot(is.list(audit))
  stopifnot(identical(as.character(audit$schema_version), "scworkbench.semantic_catalog_audit.v1"))
  stopifnot(isTRUE(audit$ok))
  stopifnot(length(audit$missing_ops) == 0)
  stopifnot(length(audit$missing_plot_mappers) == 0)
  stopifnot(length(audit$missing_promoter_primitives) == 0)
  stopifnot(length(audit$missing_primitive_constructor_exports) == 0)
  stopifnot(length(audit$missing_constructor_primitives) == 0)
  stopifnot(length(audit$missing_cataloged_getter_exports) == 0)
  stopifnot(length(audit$missing_semantic_function_exports) == 0)
  stopifnot(length(audit$missing_known_table_types) == 0)
  stopifnot(as.integer(audit$known_table_type_count) >= 40)

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

  tmp_refresh <- tempfile("semantic_refresh_")
  audit2 <- wb_refresh_semantic_catalogs(docs_dir = tmp_refresh)
  stopifnot(isTRUE(audit2$ok))
  stopifnot(length(audit2$json_validated) == 11)
  stopifnot(all(file.exists(audit2$json_validated)))
  stopifnot(is.data.frame(audit2$graph_views))
  stopifnot(any(grepl("semantic_graph_full[.]dot$", audit2$graph_views$file)))

  TRUE
}

test_semantic_graph_views_contract <- function() {
  tbl <- wb_semantic_graph_tables()
  stopifnot(is.list(tbl), is.data.frame(tbl$nodes), is.data.frame(tbl$edges))
  stopifnot(nrow(tbl$nodes) > 100, nrow(tbl$edges) > 20)
  stopifnot(all(c("record_id", "record_type", "title", "description") %in% names(tbl$nodes)))
  stopifnot(all(c("from", "to", "edge_type", "label") %in% names(tbl$edges)))

  op_tbl <- wb_semantic_graph_tables(
    record_types = c("op", "primitive"),
    edge_types = c("consumed_by", "produces")
  )
  stopifnot(any(op_tbl$nodes$record_id == "op:trajectory_geneset_dynamics"))
  stopifnot(any(op_tbl$nodes$record_id == "primitive:obs_table"))
  stopifnot(all(op_tbl$edges$edge_type %in% c("consumed_by", "produces")))

  dot <- wb_semantic_graph_dot(
    node_regex = "trajectory_geneset_dynamics",
    include_neighbors = TRUE,
    title = "Trajectory Dynamics"
  )
  stopifnot(is.character(dot), length(dot) == 1)
  stopifnot(grepl("^digraph scworkbench_semantic_graph", dot))
  stopifnot(grepl("trajectory_geneset_dynamics", dot))

  tmp <- tempfile("semantic_graph_views_")
  manifest <- wb_write_semantic_graph_views(out_dir = tmp)
  stopifnot(is.data.frame(manifest), nrow(manifest) >= 8)
  stopifnot(file.exists(file.path(tmp, "semantic_graph_nodes.csv")))
  stopifnot(file.exists(file.path(tmp, "semantic_graph_edges.csv")))
  stopifnot(file.exists(file.path(tmp, "semantic_graph_full.dot")))
  stopifnot(file.exists(file.path(tmp, "semantic_graph_full.svg")))
  stopifnot(file.exists(file.path(tmp, "semantic_graph_artifact_plotting.dot")))
  stopifnot(file.exists(file.path(tmp, "semantic_graph_artifact_plotting.svg")))
  full_dot <- readLines(file.path(tmp, "semantic_graph_full.dot"), warn = FALSE)
  stopifnot(any(grepl("Full Semantic Compatibility Graph", full_dot)))
  full_svg <- readLines(file.path(tmp, "semantic_graph_full.svg"), warn = FALSE)
  stopifnot(any(grepl("<svg", full_svg, fixed = TRUE)))

  TRUE
}

test_recipe_semantics_catalog_contract <- function() {
  cat_sem <- wb_recipe_semantics_catalog()
  stopifnot(is.list(cat_sem))
  stopifnot(identical(as.character(cat_sem$schema_version), "scworkbench.recipe_semantics_catalog.v1"))
  stopifnot(is.list(cat_sem$recipes), length(cat_sem$recipes) >= 6)
  ids <- vapply(cat_sem$recipes, function(x) as.character(x$recipe_id %||% ""), character(1))
  stopifnot(!anyDuplicated(ids))
  stopifnot(all(c("trajectory_geneset_dynamics_discovery", "inspect_promoted_artifact", "plot_ucell_on_umap") %in% ids))
  for (r in cat_sem$recipes) {
    stopifnot(nzchar(as.character(r$recipe_id %||% "")[1]))
    stopifnot(nzchar(as.character(r$title %||% "")[1]))
    stopifnot(nzchar(as.character(r$description %||% "")[1]))
    stopifnot(length(r$steps %||% character(0)) >= 1)
    stopifnot(length(r$uses %||% character(0)) >= 1)
  }
  tmp_md <- tempfile("recipe_semantics_", fileext = ".md")
  tmp_json <- tempfile("recipe_semantics_", fileext = ".json")
  wb_write_recipe_semantics_reference(path_md = tmp_md, path_json = tmp_json)
  stopifnot(file.exists(tmp_md), file.exists(tmp_json))
  stopifnot(jsonlite::validate(paste(readLines(tmp_json, warn = FALSE), collapse = "\n")))
  md <- readLines(tmp_md, warn = FALSE)
  stopifnot(any(grepl("^### `trajectory_geneset_dynamics_discovery`", md)))
  stopifnot(any(grepl("^### `plot_ucell_on_umap`", md)))
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
