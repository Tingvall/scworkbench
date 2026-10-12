# Select existing producer evidence for the actual resolved matrix. This does
# not create a certificate, adopt pending session state, or select a bundle's
# unrelated later provenance head.
.wb_graph_matrix_retained_selector <- function(bundle, matrix_id, budgets,
                                                producer_ref = NULL) {
  .wb_graph_require(.wb_graph_string(matrix_id), "GRAPH_SOURCE_AUTHORITY_REQUIRED",
    "Graph matrix source requires an exact resolved matrix ID.")
  .wb_assert_observational_schema(bundle,
    c("prov_run_outputs", "prov_run_entity_bindings", "prov_runs", "prov_heads"),
    "promoted matrix graph source")
  con <- bundle$con
  budgets <- .wb_graph_effective_budgets(con, budgets)
  restore <- .wb_graph_scoped_connection_budget(con, budgets)
  on.exit(restore(), add = TRUE)
  query <- .wb_graph_matrix_producer_query()
  params <- list(matrix_id)
  if (!is.null(producer_ref)) {
    .wb_graph_require(identical(producer_ref$ref_type, "run") &&
      .wb_graph_string(producer_ref$run_id) && .wb_graph_string(producer_ref$output),
      "GRAPH_SOURCE_AUTHORITY_REQUIRED", "Matrix producer reference is invalid.")
    query <- paste0(query, "AND o.run_id=? AND o.output_name=? ")
    params <- c(params, list(producer_ref$run_id, producer_ref$output))
  }
  # Repeated snapshots may retain the same producer. Distinct producers are
  # ambiguous unless the actual resolved session reference selects one.
  producer_count <- DBI::dbGetQuery(con, paste0("SELECT COUNT(*) n FROM ",
    "(SELECT o.run_id,o.output_name ", query, "GROUP BY o.run_id,o.output_name);"), params = params)$n[[1L]]
  .wb_graph_require(producer_count == 1L, "GRAPH_SOURCE_AUTHORITY_REQUIRED",
    "Promote the matrix producer before graph binding; an exact independently retained producer is required.")
  fields <- c("o.snapshot_id", "o.run_id", "o.output_name")
  charge <- paste0("COALESCE(octet_length(", fields, "),0)", collapse = "+")
  stats <- DBI::dbGetQuery(con, paste0("SELECT MAX(", charge, ") bytes ", query), params = params)
  .wb_graph_require(!is.na(stats$bytes[[1L]]) && stats$bytes[[1L]] <= budgets$partition_bytes,
    "GRAPH_RESOURCE_EXCEEDED", "Retained matrix source selectors exceed admission.")
  # The earliest independently retained snapshot of that producer is stable
  # when unrelated later heads are added. Full issuer verification follows.
  row <- DBI::dbGetQuery(con, paste0("SELECT o.snapshot_id,o.run_id,o.output_name ", query,
    "AND ", charge, "<=? ORDER BY o.rowid LIMIT 1;"),
    params = c(params, list(budgets$partition_bytes)))
  .wb_graph_require(nrow(row) == 1L, "GRAPH_SOURCE_AUTHORITY_REQUIRED",
    "Exact retained matrix producer disappeared during admission.")
  list(snapshot_id = row$snapshot_id[[1L]], run_id = row$run_id[[1L]],
    output_name = row$output_name[[1L]], matrix_id = matrix_id)
}

.wb_graph_matrix_retained_snapshot <- function(bundle, selection, budgets) {
  con <- bundle$con
  budgets <- .wb_graph_effective_budgets(con, budgets)
  restore <- .wb_graph_aggregate_connection_budget(list(con), budgets)
  on.exit(restore(), add = TRUE)
  header <- DBI::dbGetQuery(con, paste0("SELECT snapshot_id,schema_version,",
    "head_run_ids_json,n_runs,n_artifacts,commit_id,replay_status FROM prov_heads ",
    "WHERE snapshot_id=? AND COALESCE(octet_length(head_run_ids_json),0)+",
    "COALESCE(octet_length(commit_id),0)+COALESCE(octet_length(replay_status),0)+",
    "COALESCE(octet_length(schema_version),0)+COALESCE(octet_length(snapshot_id),0)<=? ",
    "AND typeof(n_runs)='integer' AND typeof(n_artifacts)='integer';"),
    params = list(selection$snapshot_id, budgets$partition_bytes))
  .wb_graph_require(nrow(header) == 1L, "GRAPH_SOURCE_AUTHORITY_REQUIRED",
    "Exact retained matrix producer snapshot is absent or exceeds admission.")
  identity <- .wb_operation_pack_v3_head_snapshot(header)$source_snapshot_identity
  identity$scope <- NULL
  .wb_graph_require(identical(.wb_graph_source_snapshot(bundle, identity, budgets,
    snapshot_id = selection$snapshot_id,
    source_ref = list(kind = "matrix", source_id = selection$matrix_id)),
    selection$snapshot_id), "GRAPH_SOURCE_AUTHORITY_INVALID",
    "Matrix producer snapshot identity does not resolve uniquely.")
  producer <- .wb_graph_matrix_producer(bundle, selection$matrix_id,
    selection$snapshot_id, budgets)
  .wb_graph_require(identical(producer$run_id, selection$run_id) &&
    identical(producer$output_name, selection$output_name), "GRAPH_SOURCE_AUTHORITY_INVALID",
    "Matrix source selection differs from the independently retained producer.")
  list(source_snapshot_identity = identity,
    source_payload_closure_identity = producer[c("scheme", "sha256")])
}
