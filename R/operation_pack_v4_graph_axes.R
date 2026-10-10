# Explicit manifest-selected source axes are authenticated by core. A pack
# cannot derive publication authority from its own binding hashes.
.wb_operation_pack_v4_graph_selection <- function(operation, input_name, params) {
  selected <- character()
  for (output in operation$outputs) for (source in output$axis_sources %||% list()) {
    if (!identical(source$input_name, input_name) ||
        source$selection_mode != "selected_graph_binding") next
    selector <- source$source_binding_selector
    id <- if (selector$kind == "fixed_binding_id_v1") selector$binding_id else params[[selector$parameter]]
    .wb_graph_require(.wb_graph_string(id), "GRAPH_BINDING_SELECTION_INVALID", "Missing exact binding selector.")
    if (!id %in% selected) selected <- c(selected, id)
  }
  unname(as.list(selected))
}

.wb_operation_pack_v4_graph_binding <- function(bundle, artifact_id, binding_id, budgets) {
  rows <- .wb_graph_page(bundle$con, artifact_id, "bindings", "0", 1L, budgets$partition_bytes,
    predicate = "AND json_extract(record_json,'$.binding_id')=?", params = list(binding_id))
  .wb_graph_require(nrow(rows) == 1L, "GRAPH_BINDING_SELECTION_INVALID", "Selected binding is absent.")
  binding <- .wb_graph_parse(rows$record_json[[1L]]); binding$binding_ordinal <- NULL
  binding
}

.wb_operation_pack_v4_graph_axis_authorities <- function(bundle, output, inputs,
    params, source_refs, transition_identity) {
  budgets <- .wb_graph_budgets()
  lapply(output$axis_sources %||% list(), function(source) {
    name <- source$input_name
    value <- inputs[[name]]
    .wb_graph_require(!is.null(value), "GRAPH_SOURCE_AUTHORITY_REQUIRED", "Declared source input is absent.")
    binding_id <- NULL
    if (source$selection_mode == "selected_graph_binding") {
      selector <- source$source_binding_selector
      binding_id <- if (selector$kind == "fixed_binding_id_v1") selector$binding_id else params[[selector$parameter]]
      .wb_graph_require(!is.null(value$artifact_id), "GRAPH_SOURCE_AUTHORITY_REQUIRED", "Binding source must be retained.")
      binding <- .wb_operation_pack_v4_graph_binding(bundle, value$artifact_id, binding_id, budgets)
      .wb_graph_require(identical(binding$axis_kind, source$axis_kind),
        "GRAPH_BINDING_SELECTION_INVALID", "Selected binding axis kind differs from declaration.")
    } else {
      ref <- .wb_operation_pack_v3_artifact_ref(source_refs[[name]])
      .wb_graph_require(!is.null(ref), "GRAPH_SOURCE_AUTHORITY_REQUIRED", "Cell-axis source must name a retained artifact.")
      header <- DBI::dbGetQuery(bundle$con, paste0("SELECT h.snapshot_id,h.schema_version,",
        "h.head_run_ids_json,h.n_runs,h.n_artifacts,h.commit_id,h.replay_status FROM prov_heads h ",
        "JOIN artifacts a ON a.provenance_snapshot_id=h.snapshot_id WHERE a.artifact_id=? AND ",
        "COALESCE(octet_length(h.head_run_ids_json),0)+COALESCE(octet_length(h.commit_id),0)+",
        "COALESCE(octet_length(h.replay_status),0)+COALESCE(octet_length(h.schema_version),0)+",
        "COALESCE(octet_length(h.snapshot_id),0)<=? AND typeof(h.n_runs)='integer' AND typeof(h.n_artifacts)='integer';"),
        params = list(ref$artifact_id, budgets$partition_bytes))
      .wb_graph_require(nrow(header) == 1L, "GRAPH_SOURCE_AUTHORITY_REQUIRED", "Retained source snapshot missing or oversized.")
      snapshot <- .wb_operation_pack_v3_head_snapshot(header)$source_snapshot_identity; snapshot$scope <- NULL
      reference <- list(kind = "retained_cell_axis", source_id = ref$artifact_id)
      axes <- .wb_graph_source_axis_hash(bundle, reference, "cell", budgets)
      binding <- list(binding_id = "source_admission", axis_kind = "cell", source_ref = reference,
        source_snapshot_identity = snapshot, axis_content_identity = axes$axis_content_identity,
        axis_order_identity = axes$axis_order_identity)
      # A filtered/reordered primitive must not claim the full retained axis.
      .wb_graph_require(identical(.wb_operation_pack_v2_identity_plain("scworkbench.cell_order.v1",
        unname(as.list(unique(as.character(value$cell_id))))), axes$axis_order_identity),
        "GRAPH_SOURCE_AUTHORITY_INVALID", "Input order/coverage differs from its complete retained source axis.")
    }
    actual <- .wb_graph_source_authorize(bundle, binding, budgets)
    authority <- c(list(schema = "scworkbench.graph.source_axis_authority.v1",
      output_name = output$name, input_name = name, source_binding_id = binding_id),
      binding[c("axis_kind", "source_ref", "source_snapshot_identity")],
      list(source_payload_closure_identity = actual$source_payload_closure_identity),
      binding[c("axis_content_identity", "axis_order_identity")],
      list(axis_count = actual$axis_count, transition_identity = transition_identity))
    authority$authority_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.graph_source_axis_authority.v1", "authority excluding authority_identity", authority)
    authority
  })
}

.wb_operation_pack_v4_graph_authorities_assert <- function(bundle, grant) {
  for (authority in grant$authorized_source_axes) {
    .wb_operation_pack_v4_scoped_assert(authority, "authority_identity",
      "scworkbench.operation_pack.graph_source_axis_authority.v1", "authority excluding authority_identity")
    binding <- c(list(binding_id = "source_admission"),
      authority[c("axis_kind", "source_ref", "source_snapshot_identity", "axis_content_identity", "axis_order_identity")])
    actual <- .wb_graph_source_authorize(bundle, binding, .wb_graph_budgets())
    for (field in c("source_payload_closure_identity", "axis_count"))
      .wb_graph_require(identical(actual[[field]], authority[[field]]),
        "GRAPH_SOURCE_AUTHORITY_INVALID", "Admitted source changed before publication.")
  }
  invisible(TRUE)
}

.wb_operation_pack_v4_graph_output_bindings_assert <- function(staged, grant) {
  .wb_graph_scan(staged$con, "staged", "bindings", function(rows) {
    for (json in rows$record_json) {
      binding <- .wb_graph_parse(json)
      matched <- Filter(function(authority) all(vapply(c("axis_kind", "source_ref",
        "source_snapshot_identity", "axis_content_identity", "axis_order_identity"),
        function(field) identical(.wb_operation_pack_canonical_json(binding[[field]]),
          .wb_operation_pack_canonical_json(authority[[field]])), logical(1))), grant$authorized_source_axes)
      .wb_graph_require(length(matched) >= 1L, "GRAPH_SOURCE_AUTHORITY_REQUIRED",
        "Output binding is not authorized by an explicit declared source axis.")
    }
  }, page = staged$budgets$partition_rows, bytes = staged$budgets$partition_bytes)
  invisible(TRUE)
}
