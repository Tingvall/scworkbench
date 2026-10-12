# ABI4 adds graph descriptor/grant projections to the existing transition
# executor. Authentication stays core-owned; no graph executor is introduced.
.wb_operation_pack_v4_graph_input <- function(bundle, name, value, declaration, selected_binding_ids = list()) {
  .wb_graph_require(!is.null(value$artifact_id), "GRAPH_SOURCE_AUTHORITY_REQUIRED",
    "Graph readers currently require an independently promoted retained artifact.")
  budgets <- .wb_graph_effective_budgets(bundle$con)
  identity <- .wb_graph_retained_identities(bundle, value$artifact_id, budgets)
  .wb_graph_sources_assert(bundle, bundle$con, value$artifact_id, budgets, selected_binding_ids)
  snapshot <- DBI::dbGetQuery(bundle$con, paste0("SELECT h.snapshot_id,h.schema_version,",
    "h.head_run_ids_json,h.n_runs,h.n_artifacts,h.commit_id,h.replay_status FROM prov_heads h ",
    "JOIN artifacts a ON a.provenance_snapshot_id=h.snapshot_id WHERE a.artifact_id=? AND ",
    "COALESCE(octet_length(h.snapshot_id),0)+COALESCE(octet_length(h.head_run_ids_json),0)+",
    "COALESCE(octet_length(h.commit_id),0)+COALESCE(octet_length(h.replay_status),0)+",
    "COALESCE(octet_length(h.schema_version),0)<=? AND typeof(h.n_runs)='integer' ",
    "AND typeof(h.n_artifacts)='integer';"),
    params = list(value$artifact_id, budgets$partition_bytes))
  .wb_graph_require(nrow(snapshot) == 1L, "GRAPH_SOURCE_AUTHORITY_REQUIRED",
    "Graph input has no admitted retained source snapshot.")
  source <- .wb_operation_pack_v3_head_snapshot(snapshot)$source_snapshot_identity
  source$scope <- NULL
  .wb_graph_source_snapshot(bundle, source, budgets,
    snapshot_id = snapshot$snapshot_id[[1L]], artifact_id = value$artifact_id)
  counts <- c(list(header = "1"), stats::setNames(lapply(.wb_graph_components(),
    function(component) .wb_graph_count(bundle$con, value$artifact_id, component)),
    .wb_graph_components()))
  .wb_graph_require(declaration$binding_policy != "required" || counts$bindings != "0",
    "GRAPH_BINDINGS_REQUIRED", "This input requires authenticated associations.")
  .wb_graph_require(declaration$binding_policy != "forbidden" || counts$bindings == "0",
    "GRAPH_BINDINGS_FORBIDDEN", "This input forbids associations.")
  grant <- list(schema = "scworkbench.graph.read_grant.v1", input_name = name,
    source_artifact_id = value$artifact_id, source_snapshot_identity = source,
    content_identity = identity$content_identity, binding_identity = identity$binding_identity,
    descriptor_identity = identity$descriptor_identity, component_counts = counts,
    partition_limits = list(max_rows = as.character(budgets$partition_rows),
      max_decoded_bytes = as.character(budgets$partition_bytes)), selected_binding_ids = selected_binding_ids)
  for (binding_id in selected_binding_ids)
    .wb_operation_pack_v4_graph_binding(bundle, value$artifact_id, binding_id, budgets)
  grant$grant_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.graph_read_grant.v1", "grant excluding grant_identity", grant)
  descriptor <- list(kind = "graph", storage_profile = "graph_sqlite_v1",
    reader = "read_graph_parts", alignment = "none", content_identity = identity$content_identity,
    binding_identity = identity$binding_identity, retained_descriptor_identity = identity$descriptor_identity,
    source_snapshot_identity = source, component_counts = counts,
    graph_read_grant_identity = grant$grant_identity)
  descriptor$descriptor_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.graph_input_descriptor.v1",
    "descriptor excluding descriptor_identity", descriptor)
  out <- list(name = name, reference = paste0("graph:", value$artifact_id), descriptor = descriptor)
  attr(out, "graph_read_grant") <- grant
  out
}

.wb_operation_pack_v4_graph_output <- function(output, allocated, authorities = list()) {
  grant <- list(schema = "scworkbench.graph.write_grant.v1", output_name = output$name,
    binding_policy = output$binding_policy, component_order = "graph_components_v1",
    authorized_source_axes = authorities, resource_budgets = output$resource_budgets)
  grant$grant_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.graph_write_grant.v1", "grant excluding grant_identity", grant)
  descriptor <- list(category = output$category, kind = "graph", storage_profile = "graph_sqlite_v1",
    writer = "write_graph", binding_policy = output$binding_policy,
    resource_budgets = output$resource_budgets, graph_write_grant_identity = grant$grant_identity)
  descriptor$grant_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.output_grant.v4", "descriptor excluding grant_identity", descriptor)
  out <- list(name = output$name, allocated_id = allocated, descriptor = descriptor)
  attr(out, "graph_write_grant") <- grant
  out
}

.wb_operation_pack_v4_request <- function(bundle, registration, operation,
    inputs, params, transition_id, session_id, run_id, generation, preflight,
    stage_root, effective_cells = NULL, source_refs = list()) {
  budgets <- .wb_operation_pack_v4_lowest_graph_budgets(lapply(Filter(
    function(output)identical(output$kind,"graph"),operation$outputs), `[[`, "resource_budgets"))
  restore <- .wb_operation_pack_v4_scoped_graph_budgets(bundle,budgets)
  on.exit(restore(),add=TRUE)
  request <- .wb_operation_pack_v3_request(bundle, registration, operation,
    inputs, params, transition_id, session_id, run_id, generation, preflight,
    stage_root, effective_cells, source_refs)
  for (i in seq_along(request$inputs)) {
    record <- request$inputs[[i]]
    if (record$descriptor$kind != "graph") next
    declaration <- Filter(function(x) identical(x$name, record$name), operation$inputs)[[1L]]
    request$inputs[[i]] <- .wb_operation_pack_v4_graph_input(bundle, record$name,
      inputs[[record$name]], declaration, .wb_operation_pack_v4_graph_selection(operation, record$name, params))
  }
  for (i in seq_along(request$outputs)) {
    record <- request$outputs[[i]]
    if (record$descriptor$kind != "graph") next
    declaration <- Filter(function(x) identical(x$name, record$name), operation$outputs)[[1L]]
    authorities <- .wb_operation_pack_v4_graph_axis_authorities(bundle, declaration,
      inputs, params, source_refs, request$transition$transition_identity)
    request$outputs[[i]] <- .wb_operation_pack_v4_graph_output(declaration, record$allocated_id, authorities)
  }
  reads <- lapply(Filter(function(x) identical(x$descriptor$kind, "graph"),
    request$inputs), function(x) attr(x, "graph_read_grant"))
  writes <- lapply(Filter(function(x) identical(x$descriptor$kind, "graph"),
    request$outputs), function(x) attr(x, "graph_write_grant"))
  if (length(reads)) request$graph_read_grants <- unname(reads)
  if (length(writes)) request$graph_write_grants <- unname(writes)
  capability <- request$execution_capability
  capability$reader_grants <- lapply(capability$reader_grants, function(item) {
    if (identical(item$reader, "read_graph_parts")) {
      grant <- Filter(function(x) identical(x$input_name, item$input_name), reads)[[1L]]
      item$descriptor_identity <- NULL; item$grant_identity <- grant$grant_identity
    }
    item
  })
  capability$capability_identity <- NULL
  capability$writer_grants <- lapply(capability$writer_grants, function(item) {
    output <- Filter(function(x) identical(x$name, item$output_name), request$outputs)[[1L]]
    item$grant_identity <- output$descriptor$grant_identity
    item
  })
  capability$capability_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.capability.v4", "capability excluding capability_identity", capability)
  request$execution_capability <- capability
  request$schema <- "scworkbench.operation_pack.transition_request.v4"
  request$pack_abi_version <- "4"; request$process_protocol_version <- "pybench-op-v5"
  request$request_identity <- NULL
  request$request_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.transition_request.v4", "request excluding request_identity", request)
  request
}

.wb_operation_pack_v4_sources_assert_current <- function(bundle, request) {
  budgets <- .wb_operation_pack_v4_lowest_graph_budgets(lapply(
    request$graph_write_grants %||% list(), `[[`, "resource_budgets"))
  restore <- .wb_operation_pack_v4_scoped_graph_budgets(bundle,budgets)
  on.exit(restore(),add=TRUE)
  budgets <- .wb_graph_effective_budgets(bundle$con,budgets)
  for (grant in request$graph_write_grants %||% list())
    .wb_operation_pack_v4_graph_authorities_assert(bundle, grant)
  for (grant in request$graph_read_grants %||% list()) {
    read_budgets <- budgets
    read_budgets$partition_rows <- min(read_budgets$partition_rows,as.numeric(grant$partition_limits$max_rows))
    read_budgets$partition_bytes <- min(read_budgets$partition_bytes,as.numeric(grant$partition_limits$max_decoded_bytes))
    .wb_graph_source_snapshot(bundle, grant$source_snapshot_identity, read_budgets,
      artifact_id = grant$source_artifact_id)
    actual <- .wb_graph_retained_identities(bundle, grant$source_artifact_id,read_budgets)
    for (field in c("content_identity", "binding_identity", "descriptor_identity"))
      .wb_graph_require(identical(actual[[field]], grant[[field]]),
        "GRAPH_SOURCE_AUTHORITY_INVALID", "Graph source changed after grant issuance.")
    .wb_graph_sources_assert(bundle, bundle$con, grant$source_artifact_id, read_budgets, grant$selected_binding_ids)
  }
  invisible(TRUE)
}

.wb_operation_pack_v4_request_audit <- function(request, registration, operation,
    bundle, inputs, params) {
  budgets <- .wb_operation_pack_v4_lowest_graph_budgets(lapply(Filter(
    function(output)identical(output$kind,"graph"),operation$outputs), `[[`, "resource_budgets"))
  restore <- .wb_operation_pack_v4_scoped_graph_budgets(bundle,budgets)
  on.exit(restore(),add=TRUE)
  .wb_operation_pack_v4_schema_assert(request, "request", "PYBENCH_CAPABILITY_MISMATCH")
  .wb_operation_pack_v3_request_audit(request, registration, operation, bundle, inputs, params)
  read_names <- vapply(request$graph_read_grants %||% list(), `[[`, character(1), "input_name")
  graph_inputs <- Filter(function(x) identical(x$descriptor$kind, "graph"), request$inputs)
  .wb_graph_require(identical(read_names, vapply(graph_inputs, `[[`, character(1), "name")),
    "GRAPH_GRANT_INVALID", "Graph read grant closure differs from named graph inputs.")
  for (i in seq_along(graph_inputs)) {
    record <- graph_inputs[[i]]; grant <- request$graph_read_grants[[i]]
    actual <- .wb_operation_pack_v4_graph_input(bundle, record$name, inputs[[record$name]],
      Filter(function(x) identical(x$name, record$name), operation$inputs)[[1L]],
      .wb_operation_pack_v4_graph_selection(operation, record$name, params))
    .wb_graph_require(identical(.wb_operation_pack_canonical_json(record),
      .wb_operation_pack_canonical_json(actual)) &&
      identical(.wb_operation_pack_canonical_json(grant),
        .wb_operation_pack_canonical_json(attr(actual, "graph_read_grant"))),
      "GRAPH_GRANT_INVALID", "Graph grant differs from actual independently retained input.")
  }
  graph_outputs <- Filter(function(x) identical(x$descriptor$kind, "graph"), request$outputs)
  .wb_graph_require(identical(vapply(request$graph_write_grants %||% list(), `[[`,
    character(1), "output_name"), vapply(graph_outputs, `[[`, character(1), "name")),
    "GRAPH_GRANT_INVALID", "Graph write grant closure differs from named outputs.")
  for (i in seq_along(graph_outputs)) {
    record <- graph_outputs[[i]]
    declaration <- Filter(function(x) identical(x$name, record$name), operation$outputs)[[1L]]
    authorities <- .wb_operation_pack_v4_graph_axis_authorities(bundle, declaration, inputs,
      params, attr(inputs, "operation_pack_v3_source_refs") %||% list(), request$transition$transition_identity)
    actual <- .wb_operation_pack_v4_graph_output(declaration, record$allocated_id, authorities)
    .wb_graph_require(identical(.wb_operation_pack_canonical_json(record),
      .wb_operation_pack_canonical_json(actual)) &&
      identical(.wb_operation_pack_canonical_json(request$graph_write_grants[[i]]),
        .wb_operation_pack_canonical_json(attr(actual, "graph_write_grant"))),
      "GRAPH_GRANT_INVALID", "Graph write grant differs from the authenticated manifest.")
  }
  invisible(TRUE)
}

.wb_operation_pack_v4_receipt <- function(request, registration, operation, writes,
    preflight, inputs, ..., graph_read_usage = list()) {
  if (!length(graph_read_usage)) graph_read_usage <- attr(inputs, "operation_pack_v4_graph_read_usage") %||% list()
  ordinary <- Filter(function(x) !identical(x$descriptor$kind, "graph"), request$outputs)
  graph_grants <- Filter(function(x) identical(x$descriptor$kind, "graph"), request$outputs)
  expected <- vapply(request$outputs, `[[`, character(1), "name")
  .wb_graph_require(setequal(names(writes), expected) && length(writes) == length(expected),
    "GRAPH_OUTPUT_CLOSURE_INVALID", "Mixed output closure is incomplete or contains undeclared output.")
  projected <- request; projected$outputs <- ordinary
  receipt <- .wb_operation_pack_v3_receipt(projected, registration, operation,
    writes[vapply(ordinary, `[[`, character(1), "name")], preflight, inputs, ...)
  sealed <- lapply(graph_grants, function(grant) {
    observation <- writes[[grant$name]]$graph_observation
    .wb_graph_require(!is.null(observation), "GRAPH_OUTPUT_CLOSURE_INVALID", "Missing graph writer seal.")
    descriptor <- list(kind = "graph", storage_profile = "graph_sqlite_v1", writer = "write_graph",
      content_identity = observation$content_identity, binding_identity = observation$binding_identity,
      retained_descriptor_identity = observation$descriptor_identity,
      component_counts = observation$component_counts, sealed_output_identity = observation$sealed_output_identity)
    descriptor$observed_descriptor_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.observed_output_descriptor.v4",
      "descriptor excluding observed_descriptor_identity", descriptor)
    list(name = grant$name, allocated_id = grant$allocated_id, descriptor = descriptor)
  })
  receipt$outputs <- c(receipt$outputs, sealed)
  receipt$outputs <- receipt$outputs[order(vapply(receipt$outputs, `[[`, character(1), "name"), method = "radix")]
  if (length(graph_grants)) receipt$graph_write_observations <- unname(lapply(graph_grants,
    function(grant) writes[[grant$name]]$graph_observation))
  if (length(graph_read_usage)) receipt$graph_read_usage <- unname(graph_read_usage)
  paths <- sort(unlist(lapply(expected, function(name) if (!is.null(writes[[name]]$graph_observation))
    paste0("outputs/", name, c("/graph.parts.ndjson", "/payload.json")) else
      paste0("outputs/", name, "/payload.rds")), use.names = FALSE), method = "radix")
  root <- attr(request, "operation_pack_stage_root")
  entries <- lapply(paths, function(path) list(path = path,
    sha256 = .wb_operation_pack_v2_file_sha256(file.path(root, path))))
  mutation <- list(entries_identity = .wb_operation_pack_v2_identity_plain(
    "scworkbench.operation_pack.mutation_entries.v2", entries),
    entry_count = length(entries), unexpected_entries = 0L)
  mutation$mutation_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.mutation_manifest.v2", "mutation manifest excluding mutation_identity", mutation)
  receipt$mutation_manifest <- mutation
  receipt$schema <- "scworkbench.operation_pack.transition_receipt.v4"
  receipt$process_protocol_version <- "pybench-op-v5"; receipt$pack_abi_version <- "4"
  receipt$receipt_identity <- NULL
  receipt$receipt_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.transition_receipt.v4", "receipt excluding receipt_identity", receipt)
  receipt
}

.wb_operation_pack_v4_receipt_audit <- function(receipt, request, registration,
    operation, preflight, graph_read_usage = NULL) {
  .wb_operation_pack_v4_schema_assert(receipt, "receipt", "PYBENCH_RECEIPT_MISMATCH")
  .wb_operation_pack_v4_scoped_assert(receipt, "receipt_identity",
    "scworkbench.operation_pack.transition_receipt.v4", "receipt excluding receipt_identity")
  expected <- vapply(request$outputs, `[[`, character(1), "name")
  observed <- c(receipt$outputs %||% list(), receipt$registry_requests %||% list())
  .wb_graph_require(setequal(expected, vapply(observed, `[[`, character(1), "name")) &&
    length(expected) == length(observed), "GRAPH_OUTPUT_CLOSURE_INVALID", "Mixed receipt output closure differs.")
  read_grants <- request$graph_read_grants %||% list()
  read_usage <- receipt$graph_read_usage %||% list()
  .wb_graph_require(identical(vapply(read_grants, `[[`, character(1), "input_name"),
    vapply(read_usage, `[[`, character(1), "input_name")), "GRAPH_READER_INCOMPLETE", "Missing/reordered graph read usage.")
  .wb_graph_require(!is.null(graph_read_usage) || !length(read_grants),
    "GRAPH_READER_INCOMPLETE", "Graph read usage requires independent core observations.")
  if (length(read_grants)) .wb_graph_require(identical(.wb_operation_pack_canonical_json(read_usage),
    .wb_operation_pack_canonical_json(graph_read_usage)), "GRAPH_READER_INCOMPLETE", "Pack read usage disagrees with the core.")
  writes <- request$graph_write_grants %||% list()
  seals <- receipt$graph_write_observations %||% list()
  .wb_graph_require(identical(vapply(writes, `[[`, character(1), "output_name"),
    vapply(seals, `[[`, character(1), "output_name")), "GRAPH_OUTPUT_CLOSURE_INVALID", "Graph seal closure differs.")
  for (i in seq_along(writes)) {
    grant <- writes[[i]]; seal <- seals[[i]]
    .wb_operation_pack_v4_scoped_assert(seal, "sealed_output_identity",
      "scworkbench.graph.sealed_output.v1", "seal excluding sealed_output_identity")
    .wb_graph_require(isTRUE(seal$complete) && identical(grant$grant_identity, seal$grant_identity),
      "GRAPH_SEAL_MISMATCH", "Graph seal disagrees with its write grant.")
    item <- Filter(function(x) identical(x$name, grant$output_name), observed)[[1L]]
    output <- Filter(function(x) identical(x$name, grant$output_name), request$outputs)[[1L]]
    .wb_graph_require(identical(item$allocated_id, output$allocated_id),
      "GRAPH_SEAL_MISMATCH", "Graph allocation differs from its grant.")
    .wb_operation_pack_v4_scoped_assert(item$descriptor, "observed_descriptor_identity",
      "scworkbench.operation_pack.observed_output_descriptor.v4", "descriptor excluding observed_descriptor_identity")
    for (field in c("content_identity", "binding_identity", "component_counts", "sealed_output_identity"))
      .wb_graph_require(identical(.wb_operation_pack_canonical_json(item$descriptor[[field]]),
        .wb_operation_pack_canonical_json(seal[[field]])), "GRAPH_SEAL_MISMATCH", "Observed graph descriptor differs from seal.")
    .wb_graph_require(identical(item$descriptor$retained_descriptor_identity, seal$descriptor_identity),
      "GRAPH_SEAL_MISMATCH", "Retained descriptor differs from output seal.")
  }
  # Existing checks still authenticate every ordinary grant and observation.
  ordinary_request <- request
  ordinary_request$outputs <- Filter(function(x) !identical(x$descriptor$kind, "graph"), request$outputs)
  ordinary_receipt <- receipt
  ordinary_receipt$outputs <- Filter(function(x) !identical(x$descriptor$kind, "graph"), receipt$outputs)
  ordinary_receipt$receipt_identity <- NULL
  ordinary_receipt$receipt_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.transition_receipt.v4", "receipt excluding receipt_identity", ordinary_receipt)
  .wb_operation_pack_v3_receipt_audit(ordinary_receipt, ordinary_request,
    registration, operation, preflight)
  invisible(TRUE)
}
