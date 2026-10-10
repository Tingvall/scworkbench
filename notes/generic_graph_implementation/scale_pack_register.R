# Public-only resource fixture runner. Installed in a disposable author pack;
# it receives no bundle, SQL, filesystem path, grant-hashing or state authority.
.scale_cell <- function(index) {
  if (index == 1L) "cell_2" else if (index == 2L) "cell_10" else
    if (index == 3L) "cell_1" else paste0("cell_", index + 100L, "_", strrep("a", 192L))
}

.seed_axis <- function(readers, writers, params, context) {
  vector <- readers$metadata()
  binding <- scworkbench::wb_graph_binding_from_source(
    context$graph_source_axes$result[[1L]], "annotations", list())
  # Named empty mapping retains authority to the complete original vector;
  # graph nodes are never fabricated as a competing source cell axis.
  writers$write_graph("result", scworkbench::wb_prim_graph(list(), list(), list(),
    associations = list(binding), direction_mode = "undirected"))
  writers$write_terminal_primitive("summary", scworkbench::wb_prim_obs_table(
    data.frame(nodes = as.character(length(vector$cell_id)), stringsAsFactors = FALSE),
    table_type = "graph_summary"))
  list(status = "ok")
}

.stream_graph <- function(readers, writers, params, context) {
  source <- readers$source()
  repeat {part <- source$next_part(); if (is.null(part)) break}
  count <- as.integer(params$nodes)
  stopifnot(count >= 0L, as.numeric(context$graph_source_axes$result[[1L]]$axis_count) >= count)
  writer <- writers$open_graph("result", list(
    schema = "scworkbench.graph.content.v1", direction_mode = "undirected"))
  parts <- function(total, rows, make, component) {
    if (total) for (start in seq.int(1L, total, by = rows)) {
      writer$write_part(component, lapply(seq.int(start, min(total, start + rows - 1L)), make))
      if (params$fault == component && start + rows > total)
        stop("GRAPH_SCALE injected late application failure")
      if ((start - 1L) %% (rows * 64L) == 0L) gc(FALSE, full = FALSE)
    }
  }
  parts(count, 128L, function(i) list(node_id = .scale_cell(i)), "nodes")
  # Last node is isolated; repeated participation adds a distinct incidence ID.
  incidence_count <- if (count >= 3L) count else 0L
  if (incidence_count) writer$write_part("edges",
    list(list(edge_id = "huge", kind = "hyper", direction = "undirected")))
  parts(incidence_count, 128L, function(i) list(incidence_id = paste0("i", i),
    edge_id = "huge", node_id = .scale_cell(if (i == incidence_count) 1L else i),
    role = "member", ordinal = as.numeric(i - 1L)), "incidences")
  writer$write_part("attribute_fields", list(
    list(scope = "node", field_ordinal = "0", name = "payload", type = "utf8", nullable = FALSE),
    list(scope = "node", field_ordinal = "1", name = "selected", type = "bool", nullable = FALSE),
    list(scope = "incidence", field_ordinal = "0", name = "weight", type = "float64_le_hex", nullable = TRUE)))
  blob <- paste(rep("g", 65536L), collapse = "")
  # Three maximum-size scalars fit the fixed 256 KiB decoded partition.
  parts(count, 3L, function(i) list(scope = "node", field_ordinal = "0",
    entity_ordinal = as.character(i - 1L), value = blob), "attribute_values")
  parts(count, 128L, function(i) list(scope = "node", field_ordinal = "1",
    entity_ordinal = as.character(i - 1L), value = i %% 2L == 0L), "attribute_values")
  parts(incidence_count, 128L, function(i) list(scope = "incidence", field_ordinal = "0",
    entity_ordinal = as.character(i - 1L), value = if (i %% 2L) NULL else "0000000000000080"),
    "attribute_values")
  binding <- scworkbench::wb_graph_binding_from_source(
    context$graph_source_axes$result[[1L]], "scale", list())
  binding$mapping <- NULL
  binding$binding_ordinal <- "0"
  writer$write_part("bindings", list(binding))
  parts(count, 128L, function(i) list(binding_id = "scale", mapping_ordinal = as.character(i - 1L),
    node_id = .scale_cell(i), axis_id = .scale_cell(i)), "binding_mappings")
  writer$finish()
  writers$write_terminal_primitive("summary", scworkbench::wb_prim_obs_table(
    data.frame(nodes = as.character(count), stringsAsFactors = FALSE), table_type = "graph_summary"))
  list(status = "ok")
}

register_operation_pack <- function() {
  scworkbench::wb_operation_pack_register(system.file("scworkbench",
    "operation-pack.json", package = "scwbGraphScaleFixture"),
    list(`graphscalefixt::stream_graph` = .stream_graph, `graphscalefixt::seed_axis` = .seed_axis))
}
