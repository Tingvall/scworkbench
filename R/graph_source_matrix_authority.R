# Reuse only existing producer, snapshot and native fragment-tree.v2 evidence.
# Staging retains only the existing explicit source handle and independently verifies its own bytes.
.wb_graph_native_matrix_source_authorize <- function(bundle, binding, budgets) {
  .wb_graph_binding_header_validate(binding)
  .wb_graph_require(identical(binding$source_ref$kind, "matrix"),
    "GRAPH_SOURCE_AUTHORITY_INVALID", "Native matrix authority requires a matrix source.")
  budgets <- .wb_graph_effective_budgets(bundle$con, budgets)
  durable <- bundle$staging_source_bundle %||% bundle
  restore <- .wb_graph_aggregate_connection_budget(list(bundle$con, durable$con), budgets)
  on.exit(restore(), add = TRUE)
  if (!identical(bundle$con, durable$con)) {
    actual <- .wb_graph_native_matrix_source_authorize(durable, binding, budgets)
    matrix_id <- binding$source_ref$source_id
    .wb_matrix_bounded_source_verify(bundle, matrix_id, budgets)
    payload <- .wb_graph_native_matrix_identity(bundle, matrix_id, budgets)
    axes <- .wb_graph_source_axis_hash(bundle, binding$source_ref, binding$axis_kind, budgets)
    .wb_graph_require(identical(payload, actual$source_payload_closure_identity) &&
      all(vapply(c("axis_content_identity", "axis_order_identity", "axis_count"),
        function(field) identical(axes[[field]], actual[[field]]), logical(1))),
      "GRAPH_SOURCE_AUTHORITY_INVALID", "Staged matrix differs from its exact durable source.")
    return(actual)
  }
  snapshot <- .wb_graph_source_snapshot(bundle, binding$source_snapshot_identity, budgets,
    source_ref = binding$source_ref)
  matrix_id <- binding$source_ref$source_id
  producer <- .wb_graph_matrix_producer(bundle, matrix_id, snapshot, budgets)
  .wb_matrix_bounded_source_verify(bundle, matrix_id, budgets)
  payload <- .wb_graph_native_matrix_identity(bundle, matrix_id, budgets)
  .wb_graph_require(identical(payload, producer[c("scheme", "sha256")]),
    "GRAPH_SOURCE_AUTHORITY_INVALID", "Actual native matrix payload differs from its exact retained producer.")
  axes <- .wb_graph_source_axis_hash(bundle, binding$source_ref, binding$axis_kind, budgets)
  for (field in c("axis_content_identity", "axis_order_identity"))
    .wb_graph_require(identical(axes[[field]], binding[[field]]),
      "GRAPH_SOURCE_AUTHORITY_INVALID", paste0("Actual matrix source disagrees at ", field))
  c(axes, list(source_payload_closure_identity = payload, source_snapshot_id = snapshot))
}
