#' Collect a Complete Graph Reader Within a Smaller Memory Budget
#' @param parts Invocation-scoped graph reader with header and next_part callback.
#' @param materialization_bytes Maximum canonical record bytes collected.
#' @return Materialized graph primitive. Oversized graphs remain valid for streaming.
#' @export
wb_graph_collect <- function(parts, materialization_bytes = 16777216) {
  .wb_graph_require(is.list(parts) && is.list(parts$header) &&
    is.function(parts$next_part), "GRAPH_READER_REQUIRED", "Expected issued graph reader.")
  .wb_graph_require(is.numeric(materialization_bytes) && length(materialization_bytes) == 1L &&
    is.finite(materialization_bytes) && materialization_bytes > 0,
    "GRAPH_RESOURCE_POLICY_INVALID", "Invalid collection budget.")
  components <- c("header", .wb_graph_components())
  records <- stats::setNames(rep(list(list()), length(components)), components)
  bytes <- 0; counts <- stats::setNames(rep("0", length(records)), names(records))
  last_component <- 1L
  repeat {
    part <- parts$next_part()
    if (is.null(part)) break
    .wb_graph_closed(part, c("schema", "component", "first_ordinal", "row_count",
      "rows", "partition_identity"), "graph partition")
    .wb_graph_require(identical(part$schema, "scworkbench.graph.component_partition.v1"),
      "GRAPH_VERSION_UNSUPPORTED", "Unknown graph partition schema.")
    .wb_graph_identity_assert(part$partition_identity, "scworkbench.graph.partition.v1")
    preimage <- part; preimage$partition_identity <- NULL
    .wb_graph_require(identical(part$partition_identity,
      .wb_graph_identity("scworkbench.graph.partition.v1", preimage)),
      "GRAPH_CONTENT_IDENTITY_MISMATCH", "Altered graph partition.")
    index <- match(part$component, names(records))
    .wb_graph_require(!is.na(index) && index >= last_component &&
      identical(part$first_ordinal, counts[[part$component]]) &&
      is.list(part$rows) && length(part$rows) > 0 &&
      identical(part$row_count, as.character(length(part$rows))),
      "GRAPH_PART_ORDER_INVALID", "Incomplete, repeated or reordered graph reader.")
    for (row in part$rows) {
      if (part$component == "header") {
        .wb_graph_closed(row, c("schema", "direction_mode"), "graph header")
        .wb_graph_require(identical(row$schema, "scworkbench.graph.content.v1") &&
          identical(row$direction_mode, parts$header$direction_mode) &&
          counts[["header"]] == "0" && length(part$rows) == 1L,
          "GRAPH_PART_ORDER_INVALID", "Repeated or inconsistent graph header.")
      } else .wb_graph_row_validate(part$component, row)
      bytes <- bytes + nchar(.wb_operation_pack_canonical_json(row), type = "bytes")
      .wb_graph_require(bytes <= materialization_bytes,
        "GRAPH_RESOURCE_EXCEEDED", "Whole-graph materialization budget exceeded.")
      records[[part$component]][[length(records[[part$component]]) + 1L]] <- row
    }
    counts[[part$component]] <- .wb_graph_add_count(counts[[part$component]], length(part$rows))
    last_component <- index
  }
  .wb_graph_require(identical(as.list(counts), parts$header$component_counts),
    "GRAPH_READER_INCOMPLETE", "Reader did not provide the complete declared closure.")
  graph <- .wb_graph_records_to_primitive(parts$header$direction_mode, records)
  observed <- wb_graph_identity(graph)
  for (field in c("content_identity", "binding_identity", "descriptor_identity"))
    .wb_graph_require(identical(observed[[field]], parts$header[[field]]),
      "GRAPH_CONTENT_IDENTITY_MISMATCH", "Collected reader disagrees with issued descriptor.")
  graph
}

.wb_graph_records_to_primitive <- function(direction_mode, records) {
  attrs <- stats::setNames(rep(list(list()), 4L), c("graph", "node", "edge", "incidence"))
  for (field in records$attribute_fields) {
    values <- Filter(function(row) identical(row$scope, field$scope) &&
      row$field_ordinal == field$field_ordinal, records$attribute_values)
    attrs[[field$scope]][[length(attrs[[field$scope]]) + 1L]] <-
      list(name = field$name, type = field$type, nullable = field$nullable,
        values = lapply(values, `[[`, "value"))
  }
  bindings <- lapply(records$bindings, function(binding) {
    pairs <- Filter(function(row) identical(row$binding_id, binding$binding_id), records$binding_mappings)
    binding$binding_ordinal <- NULL
    binding$mapping <- lapply(pairs, function(pair) pair[c("node_id", "axis_id")])
    binding
  })
  wb_prim_graph(records$nodes, records$edges, records$incidences,
    attrs$graph, attrs$node, attrs$edge, attrs$incidence, associations = bindings,
    direction_mode = direction_mode)
}

#' Add a Typed Node Attribute to a Materialized Graph
#' @param graph Graph primitive.
#' @param name Unique node-field name.
#' @param type Graph scalar type.
#' @param values Ordered list aligned exactly to declared graph nodes.
#' @param nullable Whether explicit null is admitted.
#' @return New graph primitive. No retained graph is mutated.
#' @export
wb_graph_with_node_attribute <- function(graph, name, type, values, nullable = FALSE) {
  wb_graph_validate(graph)
  graph$content$attributes$node[[length(graph$content$attributes$node) + 1L]] <-
    list(name = name, type = type, nullable = nullable, values = values)
  wb_graph_validate(graph)
  graph
}

#' Declare a Graph Binding From an Issued Source-Axis Projection
#' @param axis Path-free source projection from context$graph_source_axes.
#' @param binding_id Unique graph-local binding ID.
#' @param mapping Ordered node_id/axis_id pairs, injective within this binding.
#' @return A binding value. It grants no authority; core independently checks it
#'   against the issued source and the actual graph before publication.
#' @export
wb_graph_binding_from_source <- function(axis, binding_id, mapping) {
  .wb_graph_closed(axis, c("input_name", "source_binding_id", "axis_kind", "source_ref",
    "source_snapshot_identity", "axis_content_identity", "axis_order_identity", "axis_count"), "source-axis projection")
  .wb_graph_i64(axis$axis_count)
  binding <- c(list(binding_id = binding_id), axis[c("axis_kind", "source_ref",
    "source_snapshot_identity", "axis_content_identity", "axis_order_identity")])
  .wb_graph_binding_header_validate(binding)
  binding$mapping <- .wb_graph_records(mapping)
  .wb_graph_require(length(binding$mapping) <= .wb_graph_i64(axis$axis_count),
    "GRAPH_BINDINGS_INVALID", "Mapping exceeds the issued source axis.")
  binding
}

.wb_operation_pack_v4_graph_source_context <- function(request) {
  fields <- c("input_name", "source_binding_id", "axis_kind", "source_ref",
    "source_snapshot_identity", "axis_content_identity", "axis_order_identity", "axis_count")
  grants <- request$graph_write_grants %||% list()
  stats::setNames(lapply(grants, function(grant) lapply(grant$authorized_source_axes,
    function(axis) .wb_operation_pack_v2_deep_copy(axis[fields]))),
    vapply(grants, `[[`, character(1), "output_name"))
}
