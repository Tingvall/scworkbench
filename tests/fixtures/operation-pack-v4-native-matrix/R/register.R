.matrix_to_bound_graph <- function(readers, writers, params, context) {
  matrix <- readers$matrix()
  # Consume the engine projection, while binding to the complete authenticated
  # durable source. A feature subset is a mapping, not a truncated source axis.
  cells <- matrix$cell_id
  features <- head(matrix$feature_id, 1L)
  cell_nodes <- paste0("cell:", cells); feature_nodes <- paste0("feature:", features)
  nodes <- lapply(c(cell_nodes, feature_nodes), function(id) list(node_id = id))
  axes <- context$graph_source_axes$result
  cell_axis <- Filter(function(axis) axis$axis_kind == "cell", axes)[[1L]]
  feature_axis <- Filter(function(axis) axis$axis_kind == "feature", axes)[[1L]]
  cells_binding <- scworkbench::wb_graph_binding_from_source(cell_axis, "cell_source",
    lapply(seq_along(cells), function(i) list(node_id = cell_nodes[[i]], axis_id = cells[[i]])))
  features_binding <- scworkbench::wb_graph_binding_from_source(feature_axis, "feature_source",
    lapply(seq_along(features), function(i) list(node_id = feature_nodes[[i]], axis_id = features[[i]])))
  writers$write_graph("result", scworkbench::wb_prim_graph(nodes, list(), list(),
    associations = list(cells_binding, features_binding), direction_mode = "undirected"))
  list(status = "ok")
}

.read_bound_graph <- function(readers, writers, params, context) {
  graph <- scworkbench::wb_graph_collect(readers$source())
  stopifnot(length(context$graph_source_axes$result) == 2L)
  writers$write_graph("result", graph)
  list(status = "ok")
}

register_operation_pack <- function() {
  scworkbench::wb_operation_pack_register(system.file("scworkbench", "operation-pack.json",
    package = "scwbNativeGraphFixture"), list(
      `scwbnativegraphfixture::matrix_to_bound_graph` = .matrix_to_bound_graph,
      `scwbnativegraphfixture::read_bound_graph` = .read_bound_graph))
}
