.matrix_to_graph <- function(readers, writers, params, context) {
  # This deliberately small reference materializes the admitted matrix.
  # For large matrices declare typed_slice_reads and consume its exact schedule.
  matrix <- readers$matrix()
  writer <- writers$open_graph("result", list(
    schema = "scworkbench.graph.content.v1", direction_mode = "undirected"))
  for (ids in scworkbench::wb_partition_axis(matrix$cell_id, 128L))
    writer$write_part("nodes", lapply(ids, function(id) list(node_id = id)))
  writer$finish()
  list(status = "ok")
}

.graph_to_table <- function(readers, writers, params, context) {
  reader <- readers$source()
  # Fully consume every component without collecting topology or attributes.
  repeat {
    part <- reader$next_part()
    if (is.null(part)) break
  }
  writers$write_terminal_primitive("summary", scworkbench::wb_prim_obs_table(
    data.frame(nodes = reader$header$component_counts$nodes,
      stringsAsFactors = FALSE), table_type = "graph_summary"))
  list(status = "ok")
}

.graph_and_cell_metadata <- function(readers, writers, params, context) {
  # The convenience collector enforces its materialization budget. It is not
  # the large-graph authoring path demonstrated by open_graph/next_part above.
  graph <- scworkbench::wb_graph_collect(readers$source())
  vector <- readers$metadata()
  cells <- vapply(graph$content$nodes, `[[`, character(1), "node_id")
  stopifnot(identical(cells, vector$cell_id))
  binding <- scworkbench::wb_graph_binding_from_source(
    context$graph_source_axes$result[[1L]], "annotations",
    lapply(cells, function(id) list(node_id = id, axis_id = id)))
  writers$write_graph("result", scworkbench::wb_prim_graph(
    graph$content$nodes, graph$content$edges, graph$content$incidences,
    graph_attributes = graph$content$attributes$graph,
    edge_attributes = graph$content$attributes$edge,
    incidence_attributes = graph$content$attributes$incidence,
    associations = list(binding), node_attributes = c(graph$content$attributes$node,
      list(list(name = "annotation", type = "utf8", nullable = FALSE, values = as.list(vector$value)))),
    direction_mode = graph$content$direction_mode))
  writers$write_terminal_primitive("summary", scworkbench::wb_prim_obs_table(
    data.frame(nodes = as.character(length(cells)), stringsAsFactors = FALSE),
    table_type = "graph_summary"))
  list(status = "ok")
}

register_operation_pack <- function() {
  scworkbench::wb_operation_pack_register(system.file("scworkbench",
    "operation-pack.json", package = "@PACKAGE@"), list(
      `@NAMESPACE@::matrix_to_graph` = .matrix_to_graph,
      `@NAMESPACE@::graph_to_table` = .graph_to_table,
      `@NAMESPACE@::graph_and_cell_metadata` = .graph_and_cell_metadata))
}
