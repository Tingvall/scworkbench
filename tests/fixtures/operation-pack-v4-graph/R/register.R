.matrix_to_graph <- function(readers, writers, params, context) {
  matrix <- readers$matrix()
  nodes <- lapply(matrix$cell_id, function(id) list(node_id = id))
  writers$write_graph("result", scworkbench::wb_prim_graph(nodes, list(),
    list(), direction_mode = "undirected"))
  list(status = "ok")
}

.graph_and_metadata <- function(readers, writers, params, context) {
  graph <- scworkbench::wb_graph_collect(readers$source())
  metadata <- readers$metadata()
  writers$write_graph("result", graph)
  writers$write_terminal_primitive("summary", scworkbench::wb_prim_obs_table(
    data.frame(value = nrow(metadata$table)), table_type = "graph_summary"))
  list(status = "ok")
}

.graph_to_table <- function(readers, writers, params, context) {
  graph <- scworkbench::wb_graph_collect(readers$source())
  writers$write_terminal_primitive("summary", scworkbench::wb_prim_obs_table(
    data.frame(value = length(graph$content$nodes)), table_type = "graph_summary"))
  list(status = "ok")
}

.graph_and_cell_metadata <- function(readers, writers, params, context) {
  graph <- scworkbench::wb_graph_collect(readers$source())
  vector <- readers$metadata()
  cells <- vapply(graph$content$nodes, `[[`, character(1), "node_id")
  stopifnot(identical(cells, vector$cell_id))
  axis <- context$graph_source_axes$result[[1L]]
  mapping <- lapply(cells, function(id) list(node_id = id, axis_id = id))
  binding <- scworkbench::wb_graph_binding_from_source(axis, "metadata", mapping)
  writers$write_graph("result", scworkbench::wb_prim_graph(graph$content$nodes,
    graph$content$edges, graph$content$incidences, associations = list(binding),
    node_attributes = list(list(name = "annotation", type = "utf8", nullable = FALSE,
      values = as.list(vector$value))), direction_mode = graph$content$direction_mode))
  writers$write_terminal_primitive("summary", scworkbench::wb_prim_obs_table(
    data.frame(value = length(vector$value)), table_type = "graph_summary"))
  list(status = "ok")
}

register_operation_pack <- function() {
  scworkbench::wb_operation_pack_register(system.file("scworkbench",
    "operation-pack.json", package = "scwbGraphFixture"), list(
      `scwbgraphfixture::matrix_to_graph` = .matrix_to_graph,
      `scwbgraphfixture::graph_and_metadata` = .graph_and_metadata,
      `scwbgraphfixture::graph_to_table` = .graph_to_table,
      `scwbgraphfixture::graph_and_cell_metadata` = .graph_and_cell_metadata))
}
