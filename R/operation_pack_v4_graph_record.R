# Reopen is independent of pack installation and never trusts a compact seal
# in place of the actual contained partitions.
.wb_operation_pack_v4_graph_payload <- function(root, name, observation, grant,
  connections = list(), cache_slots = 1L, .immutable_seal = FALSE) {
  path <- file.path(root, "outputs", name, "payload.json")
  parts <- file.path(root, "outputs", name, "graph.parts.ndjson")
  for (target in c(path, parts)) .wb_graph_require(file.exists(target) &&
    !nzchar(Sys.readlink(target)) && !dir.exists(target), "GRAPH_PAYLOAD_INVALID", "Missing or linked graph payload.")
  .wb_graph_require(file.info(path)$size <= 16384,
    "GRAPH_RESOURCE_EXCEEDED", "Graph compact payload exceeds metadata admission.")
  raw <- readChar(path, file.info(path)$size, useBytes = TRUE)
  .wb_operation_pack_v2_assert_strict_json(raw)
  compact <- .wb_graph_parse(raw)
  .wb_graph_closed(compact, c("schema", "output_name", "parts_file", "observation"), "staged graph payload")
  .wb_graph_require(compact$schema == "scworkbench.graph.staged_payload.v1" &&
    identical(compact$output_name, name) && identical(compact$parts_file, "graph.parts.ndjson") &&
    identical(.wb_operation_pack_canonical_json(compact$observation),
      .wb_operation_pack_canonical_json(observation)), "GRAPH_SEAL_MISMATCH", "Compact graph payload disagrees with receipt.")
  .wb_graph_require(sum(file.info(c(parts, path))$size) <= as.numeric(grant$resource_budgets$max_staged_bytes),
    "GRAPH_RESOURCE_EXCEEDED", "Complete graph stage including descriptor exceeds admitted storage budget.")
  staged <- .wb_graph_import_parts(parts,
    .wb_operation_pack_v4_graph_budgets(grant$resource_budgets), expected = observation,
    connections = connections, cache_slots = cache_slots,
    .immutable_seal = .immutable_seal)
  succeeded <- FALSE
  on.exit(if (!succeeded) .wb_graph_stage_discard(staged), add = TRUE)
  # Independently enforce the manifest-issued ceilings for Python admission
  # and retained reopen; native writer checks are not publication authority.
  for (component in c("nodes", "edges", "incidences", "attribute_fields"))
    .wb_graph_require(.wb_graph_i64(.wb_graph_count(staged$con, "staged", component)) <=
      .wb_graph_i64(grant$resource_budgets[[paste0("max_", component)]]),
      "GRAPH_RESOURCE_EXCEEDED", "Actual graph payload exceeds the issued count budget.")
  succeeded <- TRUE
  staged
}

.wb_operation_pack_v4_graph_record_assert <- function(request, receipt, path, load_payloads = FALSE,
  connections = list()) {
  reads <- request$graph_read_grants %||% list()
  usage <- receipt$graph_read_usage %||% list()
  .wb_graph_require(identical(vapply(reads, `[[`, character(1), "input_name"),
    vapply(usage, `[[`, character(1), "input_name")), "GRAPH_READER_INCOMPLETE", "Retained graph read closure differs.")
  for (i in seq_along(reads)) {
    grant <- reads[[i]]; observation <- usage[[i]]
    .wb_operation_pack_v4_scoped_assert(grant, "grant_identity",
      "scworkbench.operation_pack.graph_read_grant.v1", "grant excluding grant_identity")
    .wb_graph_require(isTRUE(observation$complete), "GRAPH_READER_INCOMPLETE", "Retained graph read was incomplete.")
    for (field in c("grant_identity", "content_identity", "binding_identity", "descriptor_identity", "selected_binding_ids"))
      .wb_graph_require(identical(.wb_operation_pack_canonical_json(observation[[field]]),
        .wb_operation_pack_canonical_json(grant[[field]])), "GRAPH_GRANT_INVALID", "Retained graph read usage differs from grant.")
    for (component in c("header", .wb_graph_components()))
      .wb_graph_require(identical(observation$component_observations[[component]]$rows, grant$component_counts[[component]]),
        "GRAPH_READER_INCOMPLETE", "Retained graph read count differs from complete source closure.")
  }
  grants <- request$graph_write_grants %||% list()
  seals <- receipt$graph_write_observations %||% list()
  .wb_graph_require(identical(vapply(grants, `[[`, character(1), "output_name"),
    vapply(seals, `[[`, character(1), "output_name")), "GRAPH_OUTPUT_CLOSURE_INVALID", "Retained graph output seal closure differs.")
  for (i in seq_along(grants)) {
    grant <- grants[[i]]; seal <- seals[[i]]
    .wb_operation_pack_v4_scoped_assert(grant, "grant_identity",
      "scworkbench.operation_pack.graph_write_grant.v1", "grant excluding grant_identity")
    .wb_operation_pack_v4_scoped_assert(seal, "sealed_output_identity",
      "scworkbench.graph.sealed_output.v1", "seal excluding sealed_output_identity")
    .wb_graph_require(identical(grant$grant_identity, seal$grant_identity) && isTRUE(seal$complete),
      "GRAPH_SEAL_MISMATCH", "Retained graph seal is foreign or incomplete.")
    output <- Filter(function(x) identical(x$name, grant$output_name), receipt$outputs)
    allocation <- Filter(function(x) identical(x$name, grant$output_name), request$outputs)
    .wb_graph_require(length(output) == 1L && length(allocation) == 1L &&
      identical(output[[1L]]$allocated_id, allocation[[1L]]$allocated_id),
      "GRAPH_OUTPUT_CLOSURE_INVALID", "Retained graph output allocation differs.")
    .wb_operation_pack_v4_scoped_assert(allocation[[1L]]$descriptor, "grant_identity",
      "scworkbench.operation_pack.output_grant.v4", "descriptor excluding grant_identity")
    .wb_graph_require(identical(allocation[[1L]]$descriptor$graph_write_grant_identity, grant$grant_identity),
      "GRAPH_GRANT_INVALID", "Retained graph output descriptor refers to a foreign writer grant.")
    descriptor <- output[[1L]]$descriptor
    .wb_operation_pack_v4_scoped_assert(descriptor, "observed_descriptor_identity",
      "scworkbench.operation_pack.observed_output_descriptor.v4", "descriptor excluding observed_descriptor_identity")
    for (field in c("content_identity", "binding_identity", "component_counts", "sealed_output_identity"))
      .wb_graph_require(identical(.wb_operation_pack_canonical_json(descriptor[[field]]),
        .wb_operation_pack_canonical_json(seal[[field]])), "GRAPH_SEAL_MISMATCH", "Retained graph descriptor differs from seal.")
    .wb_graph_require(identical(descriptor$retained_descriptor_identity, seal$descriptor_identity),
      "GRAPH_SEAL_MISMATCH", "Retained graph root differs from seal.")
    if (load_payloads) {
      staged <- .wb_operation_pack_v4_graph_payload(path, grant$output_name, seal, grant,
        connections = connections, cache_slots = length(grants))
      on.exit(.wb_graph_stage_discard(staged), add = TRUE)
      .wb_operation_pack_v4_graph_output_bindings_assert(staged, grant)
      .wb_graph_stage_discard(staged)
    }
  }
  invisible(TRUE)
}

.wb_operation_pack_v4_graph_output_value <- function(path, item, receipt, request,
  connections = list(), cache_slots = length(request$graph_write_grants),
  .validated_handoff = NULL) {
  name <- item$name
  grant <- Filter(function(x) identical(x$output_name, name), request$graph_write_grants)[[1L]]
  seal <- Filter(function(x) identical(x$output_name, name), receipt$graph_write_observations)[[1L]]
  staged <- if (is.null(.validated_handoff))
    .wb_operation_pack_v4_graph_payload(path, name, seal, grant,
      connections = connections, cache_slots = cache_slots) else
    .wb_operation_pack_v4_graph_handoff_accept(.validated_handoff, path,
      item, receipt, request, connections)
  value <- structure(list(kind = "graph", content_identity = staged$seal$content_identity,
    binding_identity = staged$seal$binding_identity, descriptor_identity = staged$seal$descriptor_identity),
    class = "wb_primitive")
  attr(value, "graph_stage") <- staged
  value
}
