# ABI-v3 generic, exactly-once runtime key seal for two complete cell-major
# families.  The key declaration is transient; only its authenticated receipt
# and the complete staged outputs cross the publication boundary.

.wb_operation_pack_v3_rfk_policies <- function(operation) Filter(function(x)
  identical(as.character(x$policy %||% "")[1L],
    "runtime_ordered_cell_family_v1"), operation$dimension_policies %||%
  list())

.wb_operation_pack_v3_rfk_semantic_validate <- function(operation, outputs,
    registry_reads, backend) {
  policies <- .wb_operation_pack_v3_rfk_policies(operation)
  if (!length(policies)) return(invisible(TRUE))
  names <- vapply(policies, function(x) as.character(x$output)[1L],
    character(1))
  groups <- vapply(policies, function(x) as.character(x$group)[1L],
    character(1))
  sources <- vapply(policies, function(x) as.character(x$source_read)[1L],
    character(1))
  limits <- lapply(policies, function(x) x[c("maximum_keys", "maximum_rows")])
  source <- registry_reads[[sources[[1L]]]]
  if (!identical(backend, "R") || length(policies) != 2L ||
      anyDuplicated(names) || length(unique(groups)) != 1L ||
      length(unique(sources)) != 1L ||
      !identical(limits[[1L]], limits[[2L]]) || is.null(source) ||
      !identical(as.character(source$kind)[1L],
        "genomic_matrix_source") ||
      length(outputs) != 3L ||
      sum(vapply(outputs, function(x) identical(as.character(x$kind)[1L],
        "obs_table"), logical(1))) != 1L ||
      !all(vapply(names, function(name) {
        output <- outputs[[name]]
        !is.null(output) && identical(as.character(output$kind)[1L],
          "cell_vector_family") && identical(
            as.character(output$value_kind %||% "continuous")[1L],
            "continuous") && isTRUE(output$required)
      }, logical(1))) ||
      !all(vapply(policies, function(x) identical(as.character(x$row_order)[1L],
        "cell_major_then_declared_key_v1") && identical(
          as.character(x$missing_values)[1L], "allowed"), logical(1))))
    .wb_operation_pack_v3_error("OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
      "Runtime-key authority requires two complete continuous cell-major families and one table in one R closure.",
      "semantic_admission")
  invisible(TRUE)
}

.wb_operation_pack_v3_rfk_grant <- function(operation, registry_records,
    output_records) {
  policies <- .wb_operation_pack_v3_rfk_policies(operation)
  if (!length(policies)) return(list())
  source_name <- as.character(policies[[1L]]$source_read)[1L]
  source <- registry_records[[source_name]]$descriptor
  outputs <- vapply(policies, function(x) as.character(x$output)[1L],
    character(1))
  closure <- vapply(operation$outputs, function(x) as.character(x$name)[1L],
    character(1))
  value <- list(schema = "scworkbench.operation_pack.runtime_family_key_grant.v1",
    group = as.character(policies[[1L]]$group)[1L],
    source_read = source_name,
    source_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
      source$descriptor_identity),
    source_content_identity = source$content_identity,
    matrix_consumed_identity = source$consumed_matrix_identity,
    cell_order_identity = source$cell_order_identity,
    cell_count = as.integer(source$cell_count),
    ordered_cells = source$cell_id,
    family_outputs = unname(as.list(outputs)),
    closure_outputs = unname(as.list(closure)),
    maximum_keys = as.integer(policies[[1L]]$maximum_keys),
    maximum_rows = as.integer(policies[[1L]]$maximum_rows),
    row_order = "cell_major_then_declared_key_v1")
  value$grant_identity <- .wb_operation_pack_v2_identity_scoped(value$schema,
    "grant excluding grant_identity", value)
  list(value)
}

.wb_operation_pack_v3_rfk_request_audit <- function(request,
    code = "PYBENCH_CAPABILITY_MISMATCH", phase = "staging") {
  grants <- request$runtime_cell_family_key_grants %||% list()
  if (!length(grants)) return(invisible(TRUE))
  if (length(grants) != 1L) .wb_operation_pack_v3_error(code,
    "Runtime-key grants must be singular.", phase)
  grant <- grants[[1L]]
  .wb_operation_pack_v3_assert_self_identity(grant, "grant_identity",
    code, phase)
  records <- stats::setNames(request$registry_reads %||% list(),
    vapply(request$registry_reads %||% list(), `[[`, character(1), "name"))
  source <- records[[as.character(grant$source_read)[1L]]]$descriptor
  cells <- as.character(unlist(grant$ordered_cells, use.names = FALSE))
  outputs <- vapply(request$outputs, `[[`, character(1), "name")
  families <- as.character(unlist(grant$family_outputs, use.names = FALSE))
  closure <- as.character(unlist(grant$closure_outputs, use.names = FALSE))
  if (is.null(source) || !identical(as.character(source$kind)[1L],
      "genomic_matrix_source") || !identical(
        grant$source_descriptor_identity,
        .wb_operation_pack_v3_unscoped_identity(
          source$descriptor_identity)) ||
      !identical(grant$source_content_identity,
        source$content_identity) ||
      !identical(grant$matrix_consumed_identity,
        source$consumed_matrix_identity) ||
      !identical(cells, as.character(unlist(source$cell_id,
        use.names = FALSE))) ||
      !identical(grant$cell_order_identity,
        source$cell_order_identity) ||
      !identical(length(cells), as.integer(grant$cell_count)) ||
      length(families) != 2L || anyDuplicated(families) ||
      !setequal(closure, outputs) || !all(families %in% closure) ||
      as.integer(grant$maximum_keys) < 1L ||
      as.integer(grant$maximum_keys) > 10000L ||
      as.integer(grant$maximum_rows) > 10000000L)
    .wb_operation_pack_v3_error(code,
      "Runtime-family request grant disagrees with its authenticated source or complete output closure.",
      phase)
  invisible(TRUE)
}

.wb_operation_pack_v3_rfk_seal <- function(grant, cells, ordered_keys) {
  keys <- as.character(ordered_keys)
  if (!is.character(ordered_keys) || !length(keys) || anyNA(keys) ||
      any(!nzchar(keys)) || anyDuplicated(keys) ||
      any(nchar(keys, type = "bytes") > 1024L) ||
      length(keys) > as.integer(grant$maximum_keys) ||
      as.double(length(keys)) * length(cells) > grant$maximum_rows ||
      !identical(length(cells), as.integer(grant$cell_count)) ||
      !identical(.wb_operation_pack_v2_identity_plain(
        "scworkbench.cell_order.v1", unname(as.list(cells))),
        grant$cell_order_identity))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Runtime family keys are invalid, duplicated, or exceed the authenticated shape.",
      "execution")
  value <- list(schema = "scworkbench.operation_pack.runtime_family_key_seal.v1",
    grant_identity = .wb_operation_pack_v3_unscoped_identity(
      grant$grant_identity), ordered_keys = unname(as.list(keys)),
    key_order_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.runtime_family_keys.v1",
      unname(as.list(keys))),
    cell_order_identity = grant$cell_order_identity,
    cell_count = as.integer(length(cells)),
    key_count = as.integer(length(keys)),
    row_count = as.integer(length(keys) * length(cells)),
    row_order = grant$row_order)
  value$seal_identity <- .wb_operation_pack_v2_identity_scoped(value$schema,
    "seal excluding seal_identity", value)
  value
}

.wb_operation_pack_v3_rfk_assert_value <- function(value, seal, cells,
    code = "PYBENCH_OUTPUT_INVALID", phase = "execution") {
  keys <- as.character(unlist(seal$ordered_keys, use.names = FALSE))
  expected_cells <- rep(cells, each = length(keys))
  expected_keys <- rep(keys, times = length(cells))
  issues <- c(if (!.wb_is_primitive(value)) "primitive",
    if (!identical(value$kind, "cell_vector_family")) "kind",
    if (!identical(value$value_type, "continuous")) "value_type",
    if (!identical(as.character(value$cell_id), expected_cells))
      "cell_order",
    if (!identical(as.character(value$key), expected_keys)) "key_order",
    if (length(value$value) != length(expected_cells)) "row_count",
    if (any(is.nan(value$value) | is.infinite(value$value)))
      "nonfinite_values")
  if (length(issues))
    .wb_operation_pack_v3_error(code,
      paste0("Complete cell-major family differs from its ordered runtime-key seal: ",
        paste(issues, collapse = ", "), "."),
      phase)
  invisible(TRUE)
}

.wb_operation_pack_v3_rfk_adapter <- function(base, request, bundle) {
  grants <- request$runtime_cell_family_key_grants %||% list()
  if (!length(grants)) return(base)
  grant <- grants[[1L]]
  state <- base$state
  state$runtime_family_key_attempted <- FALSE
  state$runtime_family_key_seal <- NULL
  source <- request$registry_reads[[match(grant$source_read,
    vapply(request$registry_reads, `[[`, character(1), "name"))]]
  cells <- as.character(unlist(grant$ordered_cells, use.names = FALSE))
  base$writers$declare_runtime_cell_family_keys <- function(ordered_keys) {
    if (isTRUE(state$runtime_family_key_attempted) || isTRUE(state$used) ||
        length(state$writes))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Runtime family keys must be declared exactly once before any write.",
        "execution")
    state$runtime_family_key_attempted <- TRUE
    if (!identical(source$descriptor$descriptor_identity,
        grant$source_descriptor_identity) && !identical(
          .wb_operation_pack_v3_unscoped_identity(
            source$descriptor$descriptor_identity),
          grant$source_descriptor_identity))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Runtime key source descriptor differs from grant.", "execution")
    seal <- .wb_operation_pack_v3_rfk_seal(grant, cells, ordered_keys)
    state$runtime_family_key_seal <- seal
    invisible(.wb_operation_pack_v2_deep_copy(seal))
  }
  original <- base$writers$write_terminal_primitive
  base$writers$write_terminal_primitive <- function(name, value,
      semantic_metadata = list()) {
    name <- as.character(name)[1L]
    family <- as.character(unlist(grant$family_outputs,
      use.names = FALSE))
    if (name %in% family) {
      seal <- state$runtime_family_key_seal
      if (is.null(seal)) .wb_operation_pack_v3_error(
        "PYBENCH_CAPABILITY_MISMATCH",
        "Runtime family writer was requested before its key declaration.",
        "execution")
      .wb_operation_pack_v3_rfk_assert_value(value, seal, cells)
    }
    original(name, value, semantic_metadata)
  }
  base
}

.wb_operation_pack_v3_rfk_observation <- function(request, state, receipt) {
  grants <- request$runtime_cell_family_key_grants %||% list()
  if (!length(grants)) return(list())
  grant <- grants[[1L]]
  seal <- state$runtime_family_key_seal
  if (is.null(seal)) .wb_operation_pack_v3_error(
    "PYBENCH_RECEIPT_MISMATCH", "Runtime key seal is absent.", "receipt")
  observed <- stats::setNames(receipt$outputs,
    vapply(receipt$outputs, `[[`, character(1), "name"))
  closure_names <- as.character(unlist(grant$closure_outputs,
    use.names = FALSE))
  if (!setequal(closure_names, names(observed))) .wb_operation_pack_v3_error(
    "PYBENCH_RECEIPT_MISMATCH", "Runtime key output closure is incomplete.",
    "receipt")
  closure <- lapply(closure_names, function(name) list(name = name,
    observed_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
      observed[[name]]$descriptor$observed_descriptor_identity),
    content_identity = observed[[name]]$descriptor$content_identity,
    payload_manifest_identity = observed[[name]]$descriptor$
      payload_manifest_identity))
  value <- list(schema = "scworkbench.operation_pack.runtime_family_keys_observation.v1",
    grant_identity = .wb_operation_pack_v3_unscoped_identity(
      grant$grant_identity), seal = seal, closure = unname(closure),
    status = "passed")
  value$observation_identity <- .wb_operation_pack_v2_identity_scoped(
    value$schema, "observation excluding observation_identity", value)
  list(value)
}

.wb_operation_pack_v3_rfk_receipt_audit <- function(receipt, request,
    stage_root = NULL, code = "PYBENCH_RECEIPT_MISMATCH",
    phase = "receipt") {
  grants <- request$runtime_cell_family_key_grants %||% list()
  observed <- receipt$runtime_cell_family_key_observations %||% list()
  if (length(grants) != length(observed))
    .wb_operation_pack_v3_error(code,
      "Runtime-family receipt observation count differs from grants.", phase)
  if (!length(grants)) return(invisible(TRUE))
  grant <- grants[[1L]]; observation <- observed[[1L]]
  .wb_operation_pack_v3_assert_self_identity(grant, "grant_identity",
    code, phase)
  .wb_operation_pack_v3_assert_self_identity(observation$seal,
    "seal_identity", code, phase)
  .wb_operation_pack_v3_assert_self_identity(observation,
    "observation_identity", code, phase)
  outputs <- stats::setNames(receipt$outputs, vapply(receipt$outputs,
    `[[`, character(1), "name"))
  closure_names <- as.character(unlist(grant$closure_outputs,
    use.names = FALSE))
  if (!setequal(names(outputs), closure_names) ||
      anyDuplicated(names(outputs))) .wb_operation_pack_v3_error(code,
    "Runtime-family receipt omitted or duplicated a required terminal.", phase)
  cells <- as.character(unlist(grant$ordered_cells, use.names = FALSE))
  keys <- as.character(unlist(observation$seal$ordered_keys,
    use.names = FALSE))
  expected_seal <- tryCatch(.wb_operation_pack_v3_rfk_seal(grant,
    cells, keys), error = identity)
  if (inherits(expected_seal, "error") ||
      !identical(observation$seal, expected_seal))
    .wb_operation_pack_v3_error(code,
      "Runtime-family receipt seal disagrees with the original grant and declared axes.",
      phase)
  closure <- lapply(closure_names, function(name) list(name = name,
    observed_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
      outputs[[name]]$descriptor$observed_descriptor_identity),
    content_identity = outputs[[name]]$descriptor$content_identity,
    payload_manifest_identity = outputs[[name]]$descriptor$
      payload_manifest_identity))
  if (!identical(observation$closure, unname(closure)) ||
      !identical(observation$grant_identity,
        .wb_operation_pack_v3_unscoped_identity(grant$grant_identity)) ||
      !identical(observation$seal$grant_identity,
        observation$grant_identity) ||
      !identical(observation$seal$cell_order_identity,
        grant$cell_order_identity))
    .wb_operation_pack_v3_error(code,
      "Runtime-family receipt closure or seal binding differs.", phase)
  if (!is.null(stage_root)) for (name in as.character(unlist(
      grant$family_outputs, use.names = FALSE))) {
    path <- file.path(stage_root, "outputs", name, "payload.rds")
    value <- tryCatch(readRDS(path), error = identity)
    if (inherits(value, "error")) .wb_operation_pack_v3_error(code,
      "Runtime-family staged payload is unreadable.", phase)
    cells <- as.character(unlist(grant$ordered_cells, use.names = FALSE))
    .wb_operation_pack_v3_rfk_assert_value(value, observation$seal,
      cells, code, phase)
  }
  invisible(TRUE)
}
