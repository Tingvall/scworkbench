.wb_graph_native_values <- function(field) {
  missing <- vapply(field$values, is.null, logical(1))
  if (field$type == "bool") return(vapply(field$values,
    function(value) if (is.null(value)) NA else value, logical(1)))
  if (field$type %in% c("utf8", "int64_decimal_string")) return(vapply(field$values,
    function(value) if (is.null(value)) NA_character_ else value, character(1)))
  values <- vapply(field$values, function(value) {
    if (is.null(value)) return(NA_real_)
    bits <- as.raw(strtoi(substring(value, seq(1, 15, 2), seq(2, 16, 2)), 16L))
    readBin(bits, "double", n = 1L, size = 8L, endian = "little")
  }, numeric(1))
  values[missing] <- NA_real_
  values
}

.wb_graph_igraph_admit <- function(graph, materialization_bytes) {
  .wb_graph_require(requireNamespace("igraph", quietly = TRUE),
    "GRAPH_ADAPTER_UNAVAILABLE", "Install optional igraph for native conversion.")
  wb_graph_validate(graph)
  .wb_graph_require(is.numeric(materialization_bytes) && length(materialization_bytes) == 1L &&
    is.finite(materialization_bytes) && materialization_bytes > 0,
    "GRAPH_RESOURCE_POLICY_INVALID", "Invalid materialization budget.")
  encoded <- .wb_operation_pack_canonical_json(list(content = graph$content, bindings = graph$associations))
  .wb_graph_require(nchar(encoded, type = "bytes") <= materialization_bytes,
    "GRAPH_RESOURCE_EXCEEDED", "igraph materialization budget exceeded.")
  edges <- graph$content$edges
  directions <- unique(vapply(edges, `[[`, character(1), "direction"))
  .wb_graph_require(all(vapply(edges, function(edge) edge$kind == "ordinary", logical(1))) &&
    length(directions) <= 1L, "GRAPH_ADAPTER_UNSUPPORTED",
    "igraph cannot losslessly represent hyperedges or actual mixed directions.")
  for (scope in graph$content$attributes) for (field in scope)
    .wb_graph_require(!startsWith(field$name, ".scwb_"), "GRAPH_ADAPTER_COLLISION",
      "Reserved carrier attribute name.")
  invisible(TRUE)
}

#' Convert a Graph Primitive to igraph Without Loss
#' @param graph Materialized graph primitive.
#' @param materialization_bytes Smaller whole-object admission budget, in bytes.
#' @return An igraph with a versioned, path-free verified round-trip carrier.
#' @export
wb_graph_to_igraph <- function(graph, materialization_bytes = 16777216) {
  .wb_graph_igraph_admit(graph, materialization_bytes)
  content <- graph$content
  node_ids <- vapply(content$nodes, `[[`, character(1), "node_id")
  edge_ids <- vapply(content$edges, `[[`, character(1), "edge_id")
  directions <- unique(vapply(content$edges, `[[`, character(1), "direction"))
  directed <- if (length(directions)) directions[[1]] == "directed" else content$direction_mode == "directed"
  native <- igraph::make_empty_graph(n = length(node_ids), directed = directed)
  if (length(edge_ids)) {
    endpoints <- vapply(content$incidences, function(incidence) match(incidence$node_id, node_ids), integer(1))
    native <- igraph::add_edges(native, endpoints)
  }
  native <- igraph::set_vertex_attr(native, ".scwb_node_id", value = node_ids)
  native <- igraph::set_edge_attr(native, ".scwb_edge_id", value = edge_ids)
  for (scope in c("graph", "node", "edge")) for (field in content$attributes[[scope]]) {
    value <- .wb_graph_native_values(field)
    native <- switch(scope, graph = igraph::set_graph_attr(native, field$name, value[[1]]),
      node = igraph::set_vertex_attr(native, field$name, value = value),
      edge = igraph::set_edge_attr(native, field$name, value = value))
  }
  identity <- wb_graph_identity(graph)
  carrier <- list(schema = "scworkbench.graph.igraph_carrier.v1", content = content,
    bindings = graph$associations, descriptor_identity = identity$descriptor_identity)
  igraph::set_graph_attr(native, ".scwb_graph_carrier_v1",
    .wb_operation_pack_canonical_json(carrier))
}

#' Restore a Graph Primitive from a Verified igraph Carrier
#' @param x igraph previously exported by wb_graph_to_igraph.
#' @param materialization_bytes Whole-object admission budget in bytes.
#' @return Graph primitive, or explicit rejection for absent/stale/unsupported state.
#' @export
wb_graph_from_igraph <- function(x, materialization_bytes = 16777216) {
  .wb_graph_require(requireNamespace("igraph", quietly = TRUE) && inherits(x, "igraph"),
    "GRAPH_ADAPTER_UNAVAILABLE", "Expected optional igraph object.")
  encoded <- igraph::graph_attr(x, ".scwb_graph_carrier_v1")
  .wb_graph_require(.wb_graph_string(encoded, maximum = materialization_bytes, empty = FALSE),
    "GRAPH_ADAPTER_CARRIER_INVALID", "Missing/oversized carrier; no implicit ID allocation.")
  carrier <- .wb_graph_parse(encoded)
  .wb_graph_closed(carrier, c("schema", "content", "bindings", "descriptor_identity"), "igraph carrier")
  .wb_graph_require(identical(carrier$schema, "scworkbench.graph.igraph_carrier.v1"),
    "GRAPH_VERSION_UNSUPPORTED", "Unsupported carrier.")
  graph <- structure(list(kind = "graph", content = carrier$content,
    associations = carrier$bindings), class = "wb_primitive")
  .wb_graph_igraph_admit(graph, materialization_bytes)
  identity <- wb_graph_identity(graph)
  .wb_graph_require(identical(.wb_operation_pack_canonical_json(identity$descriptor_identity),
    .wb_operation_pack_canonical_json(carrier$descriptor_identity)),
    "GRAPH_ADAPTER_CARRIER_INVALID", "Carrier identity differs.")
  expected <- wb_graph_to_igraph(graph, materialization_bytes)
  .wb_graph_require(igraph::vcount(x) == igraph::vcount(expected) &&
    igraph::ecount(x) == igraph::ecount(expected) &&
    identical(igraph::is_directed(x), igraph::is_directed(expected)) &&
    identical(igraph::as_edgelist(x, names = FALSE), igraph::as_edgelist(expected, names = FALSE)),
    "GRAPH_ADAPTER_STALE", "Live topology/order disagrees with carrier.")
  for (scope in c("graph", "node", "edge")) {
    actual <- switch(scope, graph = igraph::graph_attr(x), node = igraph::vertex_attr(x),
      edge = igraph::edge_attr(x))
    reference <- switch(scope, graph = igraph::graph_attr(expected), node = igraph::vertex_attr(expected),
      edge = igraph::edge_attr(expected))
    .wb_graph_require(setequal(names(actual), names(reference)),
      "GRAPH_ADAPTER_STALE", "Live attribute fields differ.")
    for (name in names(reference)) {
      declaration <- Filter(function(field) identical(field$name, name),
        graph$content$attributes[[scope]])
      equal <- if (length(declaration) && declaration[[1]]$type == "float64_le_hex") {
        is.numeric(actual[[name]]) && identical(wb_graph_encode_finite_f64(actual[[name]]),
          wb_graph_encode_finite_f64(reference[[name]]))
      } else identical(actual[[name]], reference[[name]])
      .wb_graph_require(equal, "GRAPH_ADAPTER_STALE", paste0("Live attribute changed: ", name))
    }
  }
  graph
}
