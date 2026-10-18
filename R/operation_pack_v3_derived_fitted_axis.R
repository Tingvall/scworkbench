# Generic authenticated derived fitted-cell axes for ABI v3 contained models.

.wb_operation_pack_v3_dfa_policy <- function(operation) {
  outputs <- Filter(function(x) !is.null(x$derived_fitted_axis_policy),
    operation$outputs %||% list())
  if (!length(outputs)) return(NULL)
  if (length(outputs) != 1L) .wb_operation_pack_v3_error(
    "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
    "An operation may declare at most one derived fitted-cell axis.",
    "semantic_admission")
  list(output = outputs[[1L]], policy = outputs[[1L]]$
    derived_fitted_axis_policy)
}

.wb_operation_pack_v3_dfa_semantic_validate <- function(operation, inputs,
    outputs, backend) {
  selected <- .wb_operation_pack_v3_dfa_policy(operation)
  if (is.null(selected)) return(invisible(TRUE))
  policy <- selected$policy
  model <- selected$output
  sibling <- model$contained_model_sibling_closure_policy %||% NULL
  source_name <- as.character(policy$source_space_input)[1]
  source <- inputs[[source_name]]
  required <- policy$required_siblings %||% list()
  sibling_names <- vapply(required, function(x) as.character(x$name)[1],
    character(1))
  sibling_kinds <- vapply(required, function(x) as.character(x$kind)[1],
    character(1))
  coverage <- vapply(required, function(x)
    as.character(x$coverage_policy)[1], character(1))
  declared_siblings <- as.character(unlist(
    sibling$required_sibling_terminals %||% list(), use.names = FALSE))
  output_names <- names(outputs)
  valid_outputs <- length(sibling_names) > 0L && !anyDuplicated(sibling_names) &&
    all(sibling_names %in% output_names) && all(vapply(seq_along(
      sibling_names), function(i) identical(as.character(
        outputs[[sibling_names[[i]]]]$kind)[1], sibling_kinds[[i]]),
      logical(1)))
  sparse_valid <- all(coverage %in% c("exact_fitted_axis_v1",
    "per_key_source_relative_subset_v1")) && all(coverage !=
      "per_key_source_relative_subset_v1" | sibling_kinds ==
        "cell_vector_family")
  limits <- c(as.numeric(policy$maximum_selected_cells),
    as.numeric(policy$maximum_combined_id_bytes),
    as.numeric(policy$maximum_id_bytes),
    as.numeric(policy$maximum_family_keys))
  valid <- identical(as.character(backend)[1], "R") &&
    identical(as.character(policy$schema)[1],
      "scworkbench.operation_pack.derived_fitted_axis_policy.v1") &&
    identical(as.character(policy$mode)[1],
      "source_relative_subset_v1") &&
    identical(as.character(policy$declaration_discipline)[1],
      "exactly_once_before_cell_indexed_writes") &&
    identical(as.character(policy$model_output)[1],
      as.character(model$name)[1]) &&
    !is.null(source) && identical(as.character(source$kind)[1], "space") &&
    !is.null(sibling) && identical(as.character(
      sibling$source_space_input)[1], source_name) && valid_outputs &&
    identical(sibling_names, declared_siblings) && sparse_valid &&
    length(limits) == 4L && all(is.finite(limits)) && all(limits >= 1) &&
    limits[[1L]] <= 1000000 && limits[[2L]] <= 67108864 &&
    limits[[3L]] <= 1024 && limits[[4L]] <= 64
  if (!valid) .wb_operation_pack_v3_error(
    "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
    paste0("Operation '", operation$qualified_name,
      "' has an invalid derived fitted-cell axis policy."),
    "semantic_admission")
  .wb_operation_pack_v3_assert_self_identity(policy, "policy_identity",
    "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID", "semantic_admission")
  invisible(TRUE)
}

.wb_operation_pack_v3_dfa_utf8 <- function(ids, limits, label) {
  ids <- as.character(ids)
  if (!length(ids) || anyNA(ids) || any(!nzchar(ids)) || anyDuplicated(ids))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      paste0(label, " must contain unique nonempty identifiers."),
      "resolution")
  encoded <- enc2utf8(ids)
  bytes <- nchar(encoded, type = "bytes", allowNA = FALSE)
  if (length(encoded) > as.numeric(limits$maximum_selected_cells) ||
      any(bytes > as.numeric(limits$maximum_id_bytes)))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      paste0(label, " exceeds its authenticated count or identifier limit."),
      "resolution")
  list(ids = encoded, bytes = as.double(sum(as.double(bytes))))
}

.wb_operation_pack_v3_dfa_combined_bytes <- function(bytes, limit,
    label = "Derived fitted-cell identifiers",
    code = "PYBENCH_CAPABILITY_MISMATCH", phase = "resolution") {
  bytes <- as.double(bytes)
  total <- sum(bytes)
  if (!length(bytes) || any(!is.finite(bytes)) || any(bytes < 0) ||
      !is.finite(total) || total > as.double(limit))
    .wb_operation_pack_v3_error(code,
      paste0(label, " exceed the authenticated combined byte limit."), phase)
  total
}

.wb_operation_pack_v3_dfa_source_relative <- function(selected, available,
    label, code = "PYBENCH_INPUT_IDENTITY_MISMATCH", phase = "resolution") {
  positions <- match(selected, available)
  if (anyNA(positions) || anyDuplicated(positions) ||
      !identical(positions, sort(positions, method = "radix")))
    .wb_operation_pack_v3_error(code,
      paste0(label, " is not a source-relative ordered subset."), phase)
  invisible(TRUE)
}

.wb_operation_pack_v3_dfa_parent_snapshot <- function(bundle, source,
    dimensions, .plan = NULL) {
  space_id <- as.character(source$space_id %||% "")[1]
  if (!nzchar(space_id)) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "Derived fitted-cell source has no durable space identity.", "resolution")
  if (is.null(.plan)) {
    .plan <- tryCatch(.wb_space_payload_reader(bundle, space_id), error=identity)
    if (!inherits(.plan,"error")) on.exit(.plan$close(),add=TRUE)
  }
  if (inherits(.plan, "error") || !length(.plan$cells) ||
      anyDuplicated(.plan$cells))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Derived fitted-cell parent space is unavailable or ambiguous.",
      "resolution")
  labels <- .plan$labels
  if (!is.null(dimensions$indices)) {
    if (anyNA(dimensions$indices) ||
        any(dimensions$indices < 1L | dimensions$indices > length(labels)))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Derived fitted-cell selected dimensions are unavailable.",
        "resolution")
    dimensions$labels <- labels[dimensions$indices]
    dimensions$identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.dimension_order.v1",
      unname(as.list(dimensions$labels)))
  }
  primitive <- structure(list(kind = "space", space_id = space_id,
    values = NULL, dimensions = .plan$dimensions,
    cell_id = .plan$cells, storage_profile = "space_dense_v1",
    meta = structure(list(), names = character())), class = "wb_primitive")
  content <- .wb_operation_pack_v3_phase5_primitive_identity(bundle,
    primitive, .plan=.plan)
  registry <- .wb_space_payload_registry_row(bundle, space_id)
  payload <- list(schema_version = as.character(registry$schema_version[[1]]),
    n_cells = as.integer(registry$n_cells[[1]]),
    n_dims = as.integer(registry$n_dims[[1]]),
    cell_ids_sha256 = as.character(registry$cell_ids_sha256[[1]]),
    dim_labels = unname(as.list(labels)),
    dtype = as.character(registry$dtype[[1]]),
    endianness = as.character(registry$endianness[[1]]),
    content_identity_scheme = as.character(
      registry$content_identity_scheme[[1]]),
    content_sha256 = as.character(registry$content_sha256[[1]]))
  value <- list(schema =
      "scworkbench.operation_pack.fitted_axis_parent_snapshot.v1",
    source_space_id = space_id, full_content_identity = content,
    durable_payload_snapshot_identity =
      .wb_operation_pack_v2_identity_plain(
        "scworkbench.operation_pack.fitted_axis_parent_payload.v1", payload),
    full_cell_count = as.integer(length(.plan$cells)),
    full_cell_order_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", unname(as.list(.plan$cells))),
    selected_dimension_count = as.integer(dimensions$count),
    selected_dimension_ids = unname(as.list(dimensions$labels)),
    selected_dimension_order_identity = dimensions$identity)
  value$parent_snapshot_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.fitted_axis_parent_snapshot.v1",
    "parent snapshot excluding parent_snapshot_identity", value)
  attr(value, "operation_pack_v3_parent_cells") <- as.character(
    .plan$cells)
  value
}

.wb_operation_pack_v3_dfa_parent_assert_current <- function(bundle, parent,
    code = "PYBENCH_INPUT_IDENTITY_MISMATCH", phase = "audit") {
  plan <- tryCatch(.wb_space_payload_reader(bundle,
    parent$source_space_id), error = identity)
  if (inherits(plan, "error")) .wb_operation_pack_v3_error(code,
    "Derived fitted-cell parent space disappeared.", phase)
  on.exit(plan$close(),add=TRUE)
  labels <- plan$labels
  # Reconstruct using the retained count and identity; the dimension labels
  # themselves are authenticated by the order identity below.
  dims <- list(count = as.integer(parent$selected_dimension_count),
    labels = as.character(unlist(parent$selected_dimension_ids,
      use.names = FALSE)),
    identity = parent$selected_dimension_order_identity)
  positions <- match(dims$labels, labels)
  if (length(dims$labels) != dims$count || anyNA(positions) ||
      anyDuplicated(positions) || !identical(
        .wb_operation_pack_v2_identity_plain(
          "scworkbench.dimension_order.v1", unname(as.list(dims$labels))),
        dims$identity))
    .wb_operation_pack_v3_error(code,
      "Derived fitted-cell selected dimensions changed or disappeared.",
      phase)
  source <- wb_prim_space(parent$source_space_id)
  observed <- .wb_operation_pack_v3_dfa_parent_snapshot(bundle, source, dims,.plan=plan)
  attr(observed, "operation_pack_v3_parent_cells") <- NULL
  retained <- parent
  attr(retained, "operation_pack_v3_parent_cells") <- NULL
  if (!identical(observed, retained)) .wb_operation_pack_v3_error(code,
    "Derived fitted-cell full parent snapshot changed.", phase)
  invisible(as.character(plan$cells))
}

.wb_operation_pack_v3_dfa_prepare <- function(bundle, operation, inputs,
    input_records, params, output_records, transition_identity) {
  selected <- .wb_operation_pack_v3_dfa_policy(operation)
  if (is.null(selected)) return(list(grants = list(), values = list()))
  policy <- selected$policy
  sibling <- selected$output$contained_model_sibling_closure_policy
  source_name <- as.character(policy$source_space_input)[1]
  source <- inputs[[source_name]]
  source_plan <- (attr(inputs,"operation_pack_v3_space_plans") %||% list())[[source_name]]
  source_metadata <- .wb_operation_pack_v3_space_metadata(source,source_plan)
  parameter <- sibling$dimensions_parameter
  dimensions <- if (is.null(parameter)) {
    labels <- source_metadata$labels
    list(indices = seq_len(source_metadata$dimensions[[2L]]), labels = labels,
      count = source_metadata$dimensions[[2L]], identity =
      .wb_operation_pack_v2_identity_plain(
        "scworkbench.dimension_order.v1", unname(as.list(labels))))
  } else .wb_operation_pack_v3_selected_dimensions(source, params, parameter,
    .metadata=source_metadata)
  parent <- .wb_operation_pack_v3_dfa_parent_snapshot(bundle, source,
    dimensions,.plan=source_plan)
  dimensions$identity <- parent$selected_dimension_order_identity
  parent_cells <- attr(parent, "operation_pack_v3_parent_cells")
  attr(parent, "operation_pack_v3_parent_cells") <- NULL
  limits <- list(maximum_selected_cells = as.integer(
      policy$maximum_selected_cells), maximum_combined_id_bytes = as.numeric(
      policy$maximum_combined_id_bytes), maximum_id_bytes = as.integer(
      policy$maximum_id_bytes), maximum_family_keys = as.integer(
      policy$maximum_family_keys))
  session_checked <- .wb_operation_pack_v3_dfa_utf8(
    as.character(source$cell_id), limits, "Derived fitted-cell session axis")
  .wb_operation_pack_v3_dfa_source_relative(session_checked$ids,
    parent_cells, "Derived fitted-cell session axis")
  .wb_operation_pack_v3_dfa_combined_bytes(session_checked$bytes,
    limits$maximum_combined_id_bytes,
    "Derived fitted-cell session identifiers")
  session <- list(schema =
      "scworkbench.operation_pack.derived_fitted_session.v1",
    parent_snapshot_identity = .wb_operation_pack_v3_unscoped_identity(
      parent$parent_snapshot_identity), source_input_name = source_name,
    source_input_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
      input_records[[source_name]]$descriptor_identity),
    source_input_content_identity = input_records[[source_name]]$content_identity,
    session_cell_ids = unname(as.list(session_checked$ids)),
    session_cell_count = as.integer(length(session_checked$ids)),
    session_cell_order_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", unname(as.list(session_checked$ids))),
    selected_dimension_order_identity = dimensions$identity)
  session$session_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.derived_fitted_session.v1",
    "session projection excluding session_identity", session)
  model_name <- as.character(policy$model_output)[1]
  required <- policy$required_siblings
  base <- stats::setNames(output_records, vapply(output_records, `[[`,
    character(1), "name"))
  grant <- list(schema =
      "scworkbench.operation_pack.derived_fitted_axis_grant.v1",
    policy_identity = .wb_operation_pack_v3_unscoped_identity(
      policy$policy_identity), parent_snapshot = parent,
    session_projection = session,
    transition_identity = .wb_operation_pack_v3_unscoped_identity(
      transition_identity), model_base_grant = list(name = model_name,
      grant_identity = .wb_operation_pack_v3_unscoped_identity(
        base[[model_name]]$descriptor$grant_identity),
      engine = as.character(sibling$engine)[1],
      model_type = as.character(sibling$model_type)[1],
      primary_path = as.character(sibling$primary_path)[1],
      relative_root = paste0("outputs/", model_name, "/model_tree"),
      promotion_group = as.character(selected$output$promotion_group)[1],
      limits = list(maximum_file_count = as.integer(
        sibling$maximum_file_count), maximum_total_bytes = as.numeric(
        sibling$maximum_total_bytes))),
    sibling_base_grants = lapply(required, function(item) {
      name <- as.character(item$name)[1]
      list(name = name, kind = as.character(item$kind)[1],
        coverage_policy = as.character(item$coverage_policy)[1],
        promotion_group = as.character(
          operation$outputs[[match(name, vapply(operation$outputs, `[[`,
            character(1), "name"))]]$promotion_group)[1],
        grant_identity = .wb_operation_pack_v3_unscoped_identity(
          base[[name]]$descriptor$grant_identity))
    }), limits = limits,
    declaration_discipline = "exactly_once_before_cell_indexed_writes")
  grant$grant_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.derived_fitted_axis_grant.v1",
    "provisional grant excluding grant_identity", grant)
  list(grants = list(grant), values = list(parent_cells = parent_cells,
    session_cells = session_checked$ids, policy = policy,
    sibling_policy = sibling))
}

.wb_operation_pack_v3_dfa_seal <- function(bundle, request, cells, state,
    stage_root) {
  grants <- request$derived_fitted_axis_grants %||% list()
  if (length(grants) != 1L || !is.null(state$derived_fitted_axis))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Derived fitted-cell axis must be declared exactly once.", "execution")
  grant <- grants[[1L]]
  limits <- grant$limits
  fitted <- .wb_operation_pack_v3_dfa_utf8(cells, limits,
    "Derived fitted-cell axis")
  session <- as.character(unlist(
    grant$session_projection$session_cell_ids, use.names = FALSE))
  .wb_operation_pack_v3_dfa_source_relative(fitted$ids, session,
    "Derived fitted-cell axis", phase = "execution")
  session_bytes <- sum(as.double(nchar(enc2utf8(session), type = "bytes")))
  .wb_operation_pack_v3_dfa_combined_bytes(
    c(session_bytes, fitted$bytes), limits$maximum_combined_id_bytes,
    "Combined session and fitted identifiers", phase = "execution")
  .wb_operation_pack_v3_dfa_parent_assert_current(bundle,
    grant$parent_snapshot, phase = "execution")
  declaration <- list(schema =
      "scworkbench.operation_pack.derived_fitted_axis_declaration.v1",
    provisional_grant_identity = .wb_operation_pack_v3_unscoped_identity(
      grant$grant_identity), fitted_cell_ids = unname(as.list(fitted$ids)),
    fitted_cell_count = as.integer(length(fitted$ids)))
  declaration$declaration_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.derived_fitted_axis_declaration.v1",
    "declaration excluding declaration_identity", declaration)
  seal <- list(schema =
      "scworkbench.operation_pack.derived_fitted_axis_seal.v1",
    provisional_grant_identity = .wb_operation_pack_v3_unscoped_identity(
      grant$grant_identity), declaration_identity =
      .wb_operation_pack_v3_unscoped_identity(
        declaration$declaration_identity), parent_snapshot_identity =
      .wb_operation_pack_v3_unscoped_identity(
        grant$parent_snapshot$parent_snapshot_identity), session_identity =
      .wb_operation_pack_v3_unscoped_identity(
        grant$session_projection$session_identity),
    fitted_cell_ids = unname(as.list(fitted$ids)),
    fitted_cell_count = as.integer(length(fitted$ids)),
    fitted_cell_order_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", unname(as.list(fitted$ids))),
    relation = "source_relative_ordered_subset_v1")
  seal$seal_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.derived_fitted_axis_seal.v1",
    "seal excluding seal_identity", seal)
  model_name <- as.character(grant$model_base_grant$name)[1]
  relative <- ".scworkbench/selected-axis-v1.json"
  sidecar <- list(schema =
      "scworkbench.operation_pack.selected_axis_evidence.v1",
    parent_snapshot_identity = seal$parent_snapshot_identity,
    session_identity = seal$session_identity,
    session_cell_ids = grant$session_projection$session_cell_ids,
    fitted_cell_ids = seal$fitted_cell_ids,
    seal_identity = .wb_operation_pack_v3_unscoped_identity(
      seal$seal_identity))
  bytes <- charToRaw(.wb_operation_pack_canonical_json(sidecar))
  path <- file.path(stage_root, "outputs", model_name, "model_tree", relative)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- paste0(path, ".pending")
  con <- file(temporary, "wb"); tryCatch(writeBin(bytes, con),
    finally = close(con))
  if (!file.rename(temporary, path)) .wb_operation_pack_v3_error(
    "PYBENCH_PUBLICATION_FAILED",
    "Could not retain derived fitted-cell axis evidence.", "execution")
  evidence <- list(relative_path = relative,
    sha256 = digest::digest(bytes, algo = "sha256", serialize = FALSE),
    evidence_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.selected_axis_evidence.v1", sidecar))
  model_base <- grant$model_base_grant
  model_grant <- list(schema =
      "scworkbench.operation_pack.sealed_model_sibling_grant.v1",
    output = model_name,
    base_grant_identity = grant$model_base_grant$grant_identity,
    fitted_axis_seal_identity = .wb_operation_pack_v3_unscoped_identity(
      seal$seal_identity), engine = model_base$engine,
    model_type = model_base$model_type,
    primary_path = model_base$primary_path,
    relative_root = model_base$relative_root,
    source_space_id = grant$parent_snapshot$source_space_id,
    selected_dimension_count = grant$parent_snapshot$selected_dimension_count,
    selected_dimension_ids = grant$parent_snapshot$selected_dimension_ids,
    selected_dimension_order_identity = grant$parent_snapshot$
      selected_dimension_order_identity,
    selected_axis_evidence = evidence,
    limits = model_base$limits)
  model_grant$sealed_grant_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.sealed_model_sibling_grant.v1",
    "sealed model grant excluding sealed_grant_identity", model_grant)
  sibling_grants <- lapply(grant$sibling_base_grants, function(item) {
    value <- list(schema =
        "scworkbench.operation_pack.sealed_sibling_output_grant.v1",
      name = item$name, kind = item$kind,
      coverage_policy = item$coverage_policy,
      base_grant_identity = item$grant_identity,
      fitted_axis_seal_identity = .wb_operation_pack_v3_unscoped_identity(
        seal$seal_identity), promotion_group = item$promotion_group)
    value$sealed_grant_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.sealed_sibling_output_grant.v1",
      "sealed sibling grant excluding sealed_grant_identity", value)
    value
  })
  linkage <- list(schema =
      "scworkbench.operation_pack.model_source_linkage.v3",
    engine = model_grant$engine, model_type = model_grant$model_type,
    source_space_id = grant$parent_snapshot$source_space_id,
    parent_snapshot_identity = seal$parent_snapshot_identity,
    session_identity = seal$session_identity,
    fitted_axis_seal_identity = .wb_operation_pack_v3_unscoped_identity(
      seal$seal_identity),
    fitted_cell_order_identity = seal$fitted_cell_order_identity,
    selected_dimension_count = model_grant$selected_dimension_count,
    selected_dimension_ids = model_grant$selected_dimension_ids,
    selected_dimension_order_identity = model_grant$
      selected_dimension_order_identity,
    selected_axis_evidence = evidence)
  linkage$linkage_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.model_source_linkage.v3",
    "linkage excluding linkage_identity", linkage)
  state$derived_fitted_axis <- list(grant = grant,
    declaration = declaration, seal = seal, sidecar = sidecar,
    evidence = evidence, model_grant = model_grant,
    sibling_grants = sibling_grants, model_source_linkage = linkage,
    sibling_write_count = 0L)
  .wb_operation_pack_v2_fault("derived_fitted_axis_sealed")
  invisible(.wb_operation_pack_v3_unscoped_identity(seal$seal_identity))
}

.wb_operation_pack_v3_dfa_family_coverage <- function(value, fitted,
    policy, maximum_keys) {
  keys <- as.character(value$key %||% character())
  cells <- as.character(value$cell_id %||% character())
  if (!length(keys) || length(keys) != length(cells) || anyNA(keys) ||
      any(!nzchar(keys)) || anyNA(cells) || any(!nzchar(cells)) ||
      anyDuplicated(paste(keys, cells, sep = "\034")))
    .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
      "Derived fitted-axis family has invalid or duplicate key/cell pairs.",
      "audit")
  observed_keys <- keys[!duplicated(keys)]
  if (!length(observed_keys) || length(observed_keys) > maximum_keys)
    .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
      "Derived fitted-axis family key count exceeds its closed limit.",
      "audit")
  per_key <- lapply(observed_keys, function(key) {
    selected <- cells[keys == key]
    .wb_operation_pack_v3_dfa_source_relative(selected, fitted,
      paste0("Derived fitted-axis family key '", key, "'"),
      code = "PYBENCH_OUTPUT_INVALID", phase = "audit")
    if (identical(policy, "exact_fitted_axis_v1") &&
        !identical(selected, fitted)) .wb_operation_pack_v3_error(
          "PYBENCH_OUTPUT_INVALID",
          "Exact derived fitted-axis family coverage is incomplete.",
          "audit")
    list(key = key, cell_count = as.integer(length(selected)),
      cell_order_identity = .wb_operation_pack_v2_identity_plain(
        "scworkbench.cell_order.v1", unname(as.list(selected))))
  })
  list(keys = observed_keys, per_key = per_key)
}

.wb_operation_pack_v3_dfa_observe_sibling <- function(value, grant, seal,
    maximum_keys) {
  fitted <- as.character(unlist(seal$fitted_cell_ids, use.names = FALSE))
  kind <- as.character(grant$kind)[1]
  policy <- as.character(grant$coverage_policy)[1]
  coverage <- if (identical(kind, "cell_vector_family")) {
    .wb_operation_pack_v3_dfa_family_coverage(value, fitted, policy,
      maximum_keys)
  } else {
    cells <- .wb_operation_pack_v2_primitive_cells(value)
    if (!identical(cells, fitted)) .wb_operation_pack_v3_error(
      "PYBENCH_OUTPUT_INVALID",
      "Derived fitted-axis sibling differs from the sealed fitted axis.",
      "audit")
    list(keys = list(), per_key = list())
  }
  observed <- list(schema =
      "scworkbench.operation_pack.observed_sealed_sibling_coverage.v1",
    sealed_sibling_grant_identity = .wb_operation_pack_v3_unscoped_identity(
      grant$sealed_grant_identity), output_name = grant$name,
    kind = kind, coverage_policy = policy,
    fitted_axis_seal_identity = .wb_operation_pack_v3_unscoped_identity(
      seal$seal_identity), observed_keys = unname(as.list(coverage$keys)),
    per_key_coverage = coverage$per_key, coverage_status = "validated")
  observed$observation_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.observed_sealed_sibling_coverage.v1",
    "coverage observation excluding observation_identity", observed)
  observed
}

.wb_operation_pack_v3_dfa_adapter <- function(base, request, bundle,
    stage_root) {
  if (!length(request$derived_fitted_axis_grants %||% list())) return(base)
  state <- base$state
  state$derived_fitted_axis <- NULL
  base$writers$declare_derived_fitted_axis <- function(cells) {
    if (isTRUE(state$used) || length(state$writes))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Derived fitted-cell axis must be sealed before output writes.",
        "execution")
    .wb_operation_pack_v3_dfa_seal(bundle, request, cells, state,
      stage_root)
  }
  original <- base$writers$write_terminal_primitive
  base$writers$write_terminal_primitive <- function(name, value,
      semantic_metadata = list()) {
    name <- as.character(name)[1]
    grant <- state$derived_fitted_axis
    siblings <- if (is.null(grant)) character() else vapply(
      grant$sibling_grants, `[[`, character(1), "name")
    declared <- vapply(request$derived_fitted_axis_grants[[1L]]$
      sibling_base_grants, `[[`, character(1), "name")
    if (name %in% declared && is.null(grant))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Cell-indexed sibling write preceded fitted-axis sealing.",
        "execution")
    if (name %in% siblings) {
      sibling_grant <- grant$sibling_grants[[match(name, siblings)]]
      .wb_operation_pack_v3_dfa_observe_sibling(value, sibling_grant,
        grant$seal, grant$grant$limits$maximum_family_keys)
    }
    result <- original(name, value, semantic_metadata)
    if (name %in% siblings) {
      state$derived_fitted_axis$sibling_write_count <-
        state$derived_fitted_axis$sibling_write_count + 1L
      if (state$derived_fitted_axis$sibling_write_count == 1L)
        .wb_operation_pack_v2_fault("derived_fitted_axis_first_sibling")
    }
    result
  }
  base
}

.wb_operation_pack_v3_dfa_model_grant <- function(state, output) {
  derived <- state$derived_fitted_axis %||% NULL
  if (is.null(derived) || !identical(as.character(
      derived$model_grant$output)[1], as.character(output)[1])) return(NULL)
  grant <- derived$model_grant
  grant$model_source_linkage <- derived$model_source_linkage
  grant
}

.wb_operation_pack_v3_dfa_parent_current <- function(bundle, request,
    phase = "audit") {
  for (grant in request$derived_fitted_axis_grants %||% list())
    .wb_operation_pack_v3_dfa_parent_assert_current(bundle,
      grant$parent_snapshot, phase = phase)
  invisible(TRUE)
}

.wb_operation_pack_v3_dfa_request_audit <- function(bundle, request,
    operation, inputs = NULL, params = NULL) {
  selected <- .wb_operation_pack_v3_dfa_policy(operation)
  grants <- request$derived_fitted_axis_grants %||% list()
  capability_ids <- request$execution_capability$
    derived_fitted_axis_grant_identities %||% list()
  if (is.null(selected)) {
    if (length(grants) || length(capability_ids))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Unexpected derived fitted-axis authority is present.", "staging")
    return(invisible(TRUE))
  }
  if (length(grants) != 1L || length(capability_ids) != 1L)
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Derived fitted-axis authority is not exactly one grant.", "staging")
  grant <- grants[[1L]]; policy <- selected$policy
  if (!is.null(inputs) && !is.null(params)) {
    declarations <- stats::setNames(operation$inputs, vapply(
      operation$inputs, `[[`, character(1), "name"))
    recomputed_records <- stats::setNames(lapply(names(declarations),
      function(name) .wb_operation_pack_v2_input_descriptor(name,
        inputs[[name]], declarations[[name]])$descriptor),
      names(declarations))
    actual_records <- stats::setNames(lapply(request$inputs, `[[`,
      "descriptor"), vapply(request$inputs, `[[`, character(1), "name"))
    source_fields <- c("kind", "storage_profile", "reader", "dimensions",
      "alignment", "content_identity", "cell_order_identity")
    source_name <- as.character(selected$policy$source_space_input)[1]
    source_checks <- vapply(source_fields, function(field) identical(
      actual_records[[source_name]][[field]],
      recomputed_records[[source_name]][[field]]), logical(1))
    if (!all(source_checks))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        paste0("Derived fitted-axis source descriptor differs from resolved ",
          "input fields: ", paste(source_fields[!source_checks],
            collapse = ", "), "."),
        "staging")
    requested_outputs <- stats::setNames(request$outputs,
      vapply(request$outputs, `[[`, character(1), "name"))
    rebuilt <- .wb_operation_pack_v3_dfa_prepare(bundle, operation,
      inputs, actual_records, params, requested_outputs,
      request$transition$transition_identity)$grants
    if (!identical(rebuilt, grants)) .wb_operation_pack_v3_error(
      "PYBENCH_CAPABILITY_MISMATCH",
      paste0("Derived fitted-axis request differs from the exact durable ",
        "source, resolved input, parameters, limits, or output grants: ",
        paste(utils::head(all.equal(rebuilt, grants, check.attributes = FALSE),
          3L), collapse = "; "), "."),
      "staging")
  }
  inputs <- stats::setNames(request$inputs,
    vapply(request$inputs, `[[`, character(1), "name"))
  outputs <- stats::setNames(request$outputs,
    vapply(request$outputs, `[[`, character(1), "name"))
  source_name <- as.character(policy$source_space_input)[1]
  source <- inputs[[source_name]]$descriptor
  siblings <- policy$required_siblings
  expected_limits <- list(maximum_selected_cells = as.integer(
      policy$maximum_selected_cells), maximum_combined_id_bytes = as.numeric(
      policy$maximum_combined_id_bytes), maximum_id_bytes = as.integer(
      policy$maximum_id_bytes), maximum_family_keys = as.integer(
      policy$maximum_family_keys))
  expected_siblings <- lapply(siblings, function(item) {
    name <- as.character(item$name)[1]
    list(name = name, kind = as.character(item$kind)[1],
      coverage_policy = as.character(item$coverage_policy)[1],
      promotion_group = as.character(operation$outputs[[match(name,
        vapply(operation$outputs, `[[`, character(1), "name"))]]$
          promotion_group)[1],
      grant_identity = .wb_operation_pack_v3_unscoped_identity(
        outputs[[name]]$descriptor$grant_identity))
  })
  expected_model_base <- list(name = as.character(policy$model_output)[1],
    grant_identity = .wb_operation_pack_v3_unscoped_identity(
      outputs[[as.character(policy$model_output)[1]]]$descriptor$
        grant_identity), engine = as.character(selected$output$
      contained_model_sibling_closure_policy$engine)[1],
    model_type = as.character(selected$output$
      contained_model_sibling_closure_policy$model_type)[1],
    primary_path = as.character(selected$output$
      contained_model_sibling_closure_policy$primary_path)[1],
    relative_root = paste0("outputs/", as.character(policy$model_output)[1],
      "/model_tree"), promotion_group = as.character(selected$output$
      promotion_group)[1], limits = list(maximum_file_count = as.integer(
        selected$output$contained_model_sibling_closure_policy$
          maximum_file_count), maximum_total_bytes = as.numeric(
        selected$output$contained_model_sibling_closure_policy$
          maximum_total_bytes)))
  session <- grant$session_projection
  session_cells <- as.character(unlist(session$session_cell_ids,
    use.names = FALSE))
  expected_session_order <- .wb_operation_pack_v2_identity_plain(
    "scworkbench.cell_order.v1", unname(as.list(session_cells)))
  parent_dimensions <- as.character(unlist(
    grant$parent_snapshot$selected_dimension_ids, use.names = FALSE))
  checks <- c(policy_identity = identical(grant$policy_identity,
      .wb_operation_pack_v3_unscoped_identity(policy$policy_identity)) &&
    TRUE,
    transition_identity = identical(grant$transition_identity,
      .wb_operation_pack_v3_unscoped_identity(
        request$transition$transition_identity)),
    model_base_grant = identical(grant$model_base_grant,
      expected_model_base),
    sibling_base_grants = identical(grant$sibling_base_grants,
      expected_siblings),
    limits = identical(grant$limits, expected_limits),
    capability_identity = identical(capability_ids[[1L]],
      .wb_operation_pack_v3_unscoped_identity(grant$grant_identity)),
    session_parent = identical(session$parent_snapshot_identity,
      .wb_operation_pack_v3_unscoped_identity(
        grant$parent_snapshot$parent_snapshot_identity)),
    source_name = identical(session$source_input_name, source_name),
    source_descriptor = identical(session$source_input_descriptor_identity,
      .wb_operation_pack_v3_unscoped_identity(source$descriptor_identity)),
    source_content = identical(session$source_input_content_identity,
      source$content_identity),
    session_count = identical(as.integer(session$session_cell_count),
      as.integer(length(session_cells))),
    session_order = identical(session$session_cell_order_identity,
      expected_session_order),
    dimension_order_binding = identical(
      session$selected_dimension_order_identity,
      grant$parent_snapshot$selected_dimension_order_identity),
    dimension_count = identical(as.integer(
      grant$parent_snapshot$selected_dimension_count),
      as.integer(length(parent_dimensions))),
    dimension_identity = identical(.wb_operation_pack_v2_identity_plain(
      "scworkbench.dimension_order.v1", unname(as.list(parent_dimensions))),
      grant$parent_snapshot$selected_dimension_order_identity))
  if (!all(checks)) .wb_operation_pack_v3_error(
    "PYBENCH_CAPABILITY_MISMATCH",
    paste0("Derived fitted-axis request authority contradicts authenticated ",
      "request state: ", paste(names(checks)[!checks], collapse = ", "), "."),
    "staging")
  .wb_operation_pack_v3_dfa_parent_assert_current(bundle,
    grant$parent_snapshot, "PYBENCH_INPUT_IDENTITY_MISMATCH", "staging")
  invisible(TRUE)
}

.wb_operation_pack_v3_assert_model_source_linkage_v3 <- function(value,
    code = "PYBENCH_INPUT_IDENTITY_MISMATCH", phase = "resolution") {
  required <- c("schema", "engine", "model_type", "source_space_id",
    "parent_snapshot_identity", "session_identity",
    "fitted_axis_seal_identity", "fitted_cell_order_identity",
    "selected_dimension_count", "selected_dimension_ids",
    "selected_dimension_order_identity",
    "selected_axis_evidence", "linkage_identity")
  if (!is.list(value) || !setequal(names(value), required) ||
      !identical(as.character(value$schema)[1],
        "scworkbench.operation_pack.model_source_linkage.v3") ||
      !identical(as.character(value$linkage_identity$scheme %||% "")[1],
        "scworkbench.operation_pack.model_source_linkage.v3") ||
      !identical(as.character(value$linkage_identity$scope %||% "")[1],
        "linkage excluding linkage_identity"))
    .wb_operation_pack_v3_error(code,
      "Contained model has no complete durable source linkage v3.", phase)
  .wb_operation_pack_v3_assert_self_identity(value, "linkage_identity",
    code, phase)
  invisible(TRUE)
}

.wb_operation_pack_v3_dfa_reopen <- function(bundle, model, linkage,
    tree_root, code = "PYBENCH_INPUT_IDENTITY_MISMATCH",
    phase = "resolution") {
  .wb_operation_pack_v3_assert_model_source_linkage_v3(linkage, code, phase)
  path <- file.path(tree_root,
    as.character(linkage$selected_axis_evidence$relative_path)[1])
  if (!file.exists(path) || dir.exists(path)) .wb_operation_pack_v3_error(
    code, "Derived fitted-axis evidence sidecar is absent.", phase)
  bytes <- readBin(path, "raw", n = file.info(path)$size)
  sha <- digest::digest(bytes, algo = "sha256", serialize = FALSE)
  sidecar <- tryCatch(.wb_operation_pack_parse_canonical_json(rawToChar(bytes)),
    error = identity)
  sidecar_fields <- c("schema", "parent_snapshot_identity",
    "session_identity", "session_cell_ids", "fitted_cell_ids",
    "seal_identity")
  if (inherits(sidecar, "error") || !is.list(sidecar) ||
      !setequal(names(sidecar), sidecar_fields) ||
      !identical(as.character(sidecar$schema %||% "")[1],
        "scworkbench.operation_pack.selected_axis_evidence.v1") ||
      !identical(rawToChar(bytes),
        .wb_operation_pack_canonical_json(sidecar)) ||
      !identical(sha, linkage$selected_axis_evidence$sha256) ||
      !identical(.wb_operation_pack_v2_identity_plain(
        "scworkbench.operation_pack.selected_axis_evidence.v1", sidecar),
        linkage$selected_axis_evidence$evidence_identity))
    .wb_operation_pack_v3_error(code,
      "Derived fitted-axis evidence sidecar changed.", phase)
  parent_id <- sidecar$parent_snapshot_identity
  if (!identical(parent_id, linkage$parent_snapshot_identity) ||
      !identical(sidecar$session_identity, linkage$session_identity) ||
      !identical(sidecar$seal_identity,
        linkage$fitted_axis_seal_identity))
    .wb_operation_pack_v3_error(code,
      "Derived fitted-axis evidence contradicts model linkage.", phase)
  plan <- tryCatch(.wb_space_payload_reader(bundle,
    linkage$source_space_id), error = identity)
  if (inherits(plan, "error")) .wb_operation_pack_v3_error(code,
    "Derived fitted-axis parent space disappeared.", phase)
  on.exit(plan$close(),add=TRUE)
  session <- as.character(unlist(sidecar$session_cell_ids,
    use.names = FALSE))
  fitted <- as.character(unlist(sidecar$fitted_cell_ids,
    use.names = FALSE))
  if (!length(session) || !length(fitted) || anyNA(session) ||
      anyNA(fitted) || any(!nzchar(session)) || any(!nzchar(fitted)) ||
      anyDuplicated(session) || anyDuplicated(fitted))
    .wb_operation_pack_v3_error(code,
      "Retained fitted-axis evidence contains an invalid cell axis.", phase)
  .wb_operation_pack_v3_dfa_source_relative(session, plan$cells,
    "Retained fitted session axis", code, phase)
  .wb_operation_pack_v3_dfa_source_relative(fitted, session,
    "Retained fitted axis", code, phase)
  current_source <- wb_prim_space(linkage$source_space_id)
  current_source$cell_id <- plan$cells
  current_source$dimensions <- plan$dimensions
  current_source$storage_profile <- "space_dense_v1"
  current_parent <- .wb_operation_pack_v3_dfa_parent_snapshot(bundle,
    current_source, list(count = as.integer(
      linkage$selected_dimension_count), labels = as.character(unlist(
        linkage$selected_dimension_ids, use.names = FALSE)), identity =
      linkage$selected_dimension_order_identity),.plan=plan)
  if (!identical(.wb_operation_pack_v3_unscoped_identity(
      current_parent$parent_snapshot_identity), parent_id))
    .wb_operation_pack_v3_error(code,
      "Derived fitted-axis parent snapshot changed.", phase)
  observed <- .wb_operation_pack_v2_identity_plain(
    "scworkbench.cell_order.v1", unname(as.list(fitted)))
  if (!identical(observed, linkage$fitted_cell_order_identity))
    .wb_operation_pack_v3_error(code,
      "Retained fitted-axis order differs from model linkage.", phase)
  dimension_ids <- as.character(unlist(linkage$selected_dimension_ids,
    use.names = FALSE))
  dimension_positions <- match(dimension_ids, plan$labels)
  if (length(dimension_ids) != as.integer(linkage$selected_dimension_count) ||
      anyNA(dimension_positions) || anyDuplicated(dimension_positions) ||
      !identical(.wb_operation_pack_v2_identity_plain(
        "scworkbench.dimension_order.v1", unname(as.list(dimension_ids))),
        linkage$selected_dimension_order_identity))
    .wb_operation_pack_v3_error(code,
      "Retained fitted-axis dimensions differ from model linkage.", phase)
  # This existing no-argument model reader returns one materialized fitted
  # primitive, not a newly introduced chunk API. Admit that response before
  # decoding and read only its selected cells/dimensions.
  restore <- plan$admit(0,as.double(length(fitted))*length(dimension_positions),
    .bytes_per_element=64)
  on.exit(restore(),add=TRUE,after=FALSE)
  values <- plan$read(fitted,dimension_positions)
  attr(values,"scworkbench_payload_read") <- NULL
  values
}

.wb_operation_pack_v3_dfa_observation <- function(request, state, observed,
    writes) {
  derived <- state$derived_fitted_axis %||% NULL
  grants <- request$derived_fitted_axis_grants %||% list()
  if (!length(grants)) return(list())
  if (is.null(derived) || length(grants) != 1L)
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "Derived fitted-cell axis was not sealed exactly once.", "receipt")
  names_observed <- vapply(observed, `[[`, character(1), "name")
  coverage <- lapply(derived$sibling_grants, function(grant) {
    name <- as.character(grant$name)[1]
    item <- observed[[match(name, names_observed)]]
    if (is.null(item) || is.null(writes[[name]]))
      .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
        "Derived fitted-axis sibling closure is incomplete.", "receipt")
    value <- .wb_operation_pack_v3_dfa_observe_sibling(
      writes[[name]]$value, grant, derived$seal,
      derived$grant$limits$maximum_family_keys)
    value$output_observed_descriptor_identity <-
      .wb_operation_pack_v3_unscoped_identity(
        item$descriptor$observed_descriptor_identity)
    value$output_content_identity <- item$descriptor$content_identity
    value$observation_identity <- NULL
    value$observation_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.observed_sealed_sibling_coverage.v1",
      "coverage observation excluding observation_identity", value)
    value
  })
  model_name <- as.character(derived$model_grant$output)[1]
  model <- observed[[match(model_name, names_observed)]]
  tree <- writes[[model_name]]$tree_manifest
  sidecar_path <- file.path(writes[[model_name]]$tree_root,
    derived$evidence$relative_path)
  sidecar_bytes <- if (file.exists(sidecar_path)) readBin(sidecar_path,
    "raw", n = file.info(sidecar_path)$size) else raw()
  sidecar_value <- tryCatch(.wb_operation_pack_parse_canonical_json(
    rawToChar(sidecar_bytes)), error = identity)
  if (!length(sidecar_bytes) || inherits(sidecar_value, "error") ||
      !identical(rawToChar(sidecar_bytes),
        .wb_operation_pack_canonical_json(sidecar_value)) ||
      !identical(digest::digest(sidecar_bytes, algo = "sha256",
        serialize = FALSE), derived$evidence$sha256) ||
      !identical(.wb_operation_pack_v2_identity_plain(
        "scworkbench.operation_pack.selected_axis_evidence.v1",
        sidecar_value), derived$evidence$evidence_identity))
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "Derived fitted-axis evidence changed before receipt construction.",
      "receipt")
  value <- list(schema =
      "scworkbench.operation_pack.observed_derived_fitted_axis.v1",
    provisional_grant_identity = .wb_operation_pack_v3_unscoped_identity(
      derived$grant$grant_identity),
    model_output = model_name,
    declaration_identity = .wb_operation_pack_v3_unscoped_identity(
      derived$declaration$declaration_identity),
    seal = derived$seal,
    sealed_model_grant = derived$model_grant,
    sealed_sibling_grants = derived$sibling_grants,
    selected_axis_evidence = derived$evidence,
    model_source_linkage = derived$model_source_linkage,
    model_tree_manifest_identity = .wb_operation_pack_v3_unscoped_identity(
      tree$manifest_identity), model_payload_manifest_identity =
      .wb_operation_pack_v3_model_payload_identity(tree),
    model_observed_descriptor_identity =
      .wb_operation_pack_v3_unscoped_identity(
        model$descriptor$observed_descriptor_identity),
    sibling_coverage_observations = coverage,
    closure_status = "complete")
  value$observation_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.observed_derived_fitted_axis.v1",
    "observation excluding observation_identity", value)
  list(value)
}

.wb_operation_pack_v3_dfa_receipt_audit <- function(receipt, request,
    operation = NULL) {
  grants <- request$derived_fitted_axis_grants %||% list()
  observations <- receipt$derived_fitted_axis_observations %||% list()
  if (!length(grants)) {
    if (length(observations))
      .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
        paste0("Derived fitted-axis receipt observations are present without ",
          "an authenticated request grant."), "receipt")
    return(invisible(TRUE))
  }
  if (length(grants) != 1L || length(observations) != 1L)
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "Derived fitted-axis receipt closure is not exactly one.", "receipt")
  grant <- grants[[1L]]; actual <- observations[[1L]]
  fitted <- as.character(unlist(actual$seal$fitted_cell_ids,
    use.names = FALSE))
  declaration <- list(schema =
      "scworkbench.operation_pack.derived_fitted_axis_declaration.v1",
    provisional_grant_identity = .wb_operation_pack_v3_unscoped_identity(
      grant$grant_identity), fitted_cell_ids = unname(as.list(fitted)),
    fitted_cell_count = as.integer(length(fitted)))
  declaration$declaration_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.derived_fitted_axis_declaration.v1",
    "declaration excluding declaration_identity", declaration)
  expected_seal <- list(schema =
      "scworkbench.operation_pack.derived_fitted_axis_seal.v1",
    provisional_grant_identity = .wb_operation_pack_v3_unscoped_identity(
      grant$grant_identity), declaration_identity =
      .wb_operation_pack_v3_unscoped_identity(
        declaration$declaration_identity), parent_snapshot_identity =
      .wb_operation_pack_v3_unscoped_identity(
        grant$parent_snapshot$parent_snapshot_identity), session_identity =
      .wb_operation_pack_v3_unscoped_identity(
        grant$session_projection$session_identity),
    fitted_cell_ids = unname(as.list(fitted)),
    fitted_cell_count = as.integer(length(fitted)),
    fitted_cell_order_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", unname(as.list(fitted))),
    relation = "source_relative_ordered_subset_v1")
  expected_seal$seal_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.derived_fitted_axis_seal.v1",
    "seal excluding seal_identity", expected_seal)
  session_cells <- as.character(unlist(
    grant$session_projection$session_cell_ids, use.names = FALSE))
  .wb_operation_pack_v3_dfa_source_relative(fitted, session_cells,
    "Receipt fitted axis", "PYBENCH_RECEIPT_MISMATCH", "receipt")
  if (!identical(actual$declaration_identity,
        .wb_operation_pack_v3_unscoped_identity(
          declaration$declaration_identity)) ||
      !identical(actual$seal, expected_seal))
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "Derived fitted-axis declaration or seal is contradictory.", "receipt")
  model_name <- as.character(grant$model_base_grant$name)[1]
  model_base <- grant$model_base_grant
  evidence <- actual$selected_axis_evidence
  model_grant <- list(schema =
      "scworkbench.operation_pack.sealed_model_sibling_grant.v1",
    output = model_name, base_grant_identity =
      grant$model_base_grant$grant_identity,
    fitted_axis_seal_identity = .wb_operation_pack_v3_unscoped_identity(
      expected_seal$seal_identity), engine = model_base$engine,
    model_type = model_base$model_type,
    primary_path = model_base$primary_path,
    relative_root = model_base$relative_root,
    source_space_id = grant$parent_snapshot$source_space_id,
    selected_dimension_count = grant$parent_snapshot$selected_dimension_count,
    selected_dimension_ids = grant$parent_snapshot$selected_dimension_ids,
    selected_dimension_order_identity = grant$parent_snapshot$
      selected_dimension_order_identity, selected_axis_evidence = evidence,
    limits = model_base$limits)
  model_grant$sealed_grant_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.sealed_model_sibling_grant.v1",
    "sealed model grant excluding sealed_grant_identity", model_grant)
  sibling_grants <- lapply(grant$sibling_base_grants, function(item) {
    value <- list(schema =
        "scworkbench.operation_pack.sealed_sibling_output_grant.v1",
      name = item$name, kind = item$kind,
      coverage_policy = item$coverage_policy,
      base_grant_identity = item$grant_identity,
      fitted_axis_seal_identity = .wb_operation_pack_v3_unscoped_identity(
        expected_seal$seal_identity), promotion_group = item$promotion_group)
    value$sealed_grant_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.sealed_sibling_output_grant.v1",
      "sealed sibling grant excluding sealed_grant_identity", value)
    value
  })
  if (!identical(actual$sealed_model_grant, model_grant) ||
      !identical(actual$sealed_sibling_grants, sibling_grants))
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "Derived fitted-axis sealed output grants are contradictory.",
      "receipt")
  expected_linkage <- list(schema =
      "scworkbench.operation_pack.model_source_linkage.v3",
    engine = model_grant$engine, model_type = model_grant$model_type,
    source_space_id = model_grant$source_space_id,
    parent_snapshot_identity = expected_seal$parent_snapshot_identity,
    session_identity = expected_seal$session_identity,
    fitted_axis_seal_identity = .wb_operation_pack_v3_unscoped_identity(
      expected_seal$seal_identity), fitted_cell_order_identity =
      expected_seal$fitted_cell_order_identity,
    selected_dimension_count = model_grant$selected_dimension_count,
    selected_dimension_ids = model_grant$selected_dimension_ids,
    selected_dimension_order_identity = model_grant$
      selected_dimension_order_identity, selected_axis_evidence = evidence)
  expected_linkage$linkage_identity <-
    .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.model_source_linkage.v3",
      "linkage excluding linkage_identity", expected_linkage)
  if (!identical(actual$model_source_linkage, expected_linkage))
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "Derived fitted-axis model linkage is contradictory.", "receipt")
  observed <- c(receipt$outputs %||% list(),
    receipt$registry_requests %||% list())
  observed_names <- vapply(observed, `[[`, character(1), "name")
  stage <- attr(request, "operation_pack_stage_root")
  write_names <- c(model_name, vapply(sibling_grants, `[[`, character(1),
    "name"))
  writes <- stats::setNames(lapply(write_names, function(name) {
    payload <- file.path(stage, "outputs", name, "payload.rds")
    if (!file.exists(payload)) .wb_operation_pack_v3_error(
      "PYBENCH_RECEIPT_MISMATCH",
      "Derived fitted-axis receipt payload is absent.", "receipt")
    list(value = readRDS(payload), payload = payload,
      semantic_metadata = list())
  }), write_names)
  tree_root <- file.path(stage, model_grant$relative_root)
  tree <- .wb_operation_pack_v3_model_tree_manifest(tree_root,
    model_grant$engine, model_grant$model_type, model_grant$primary_path,
    model_grant$limits$maximum_file_count,
    model_grant$limits$maximum_total_bytes,
    "PYBENCH_RECEIPT_MISMATCH", "receipt")
  writes[[model_name]]$tree_manifest <- tree
  writes[[model_name]]$tree_root <- tree_root
  if (!identical(writes[[model_name]]$value$model_source_linkage,
      expected_linkage)) .wb_operation_pack_v3_error(
    "PYBENCH_RECEIPT_MISMATCH",
    "Derived fitted-axis model payload substitutes its linkage.", "receipt")
  model_index <- match(model_name, observed_names)
  model_descriptor <- observed[[model_index]]$descriptor
  expected_content <- .wb_operation_pack_v2_identity_plain(
    "scworkbench.model_ref.content.v1", list(engine = tree$engine,
      model_type = tree$model_type, linkage_identity =
      .wb_operation_pack_v3_unscoped_identity(
        expected_linkage$linkage_identity), tree_manifest_identity =
      .wb_operation_pack_v3_unscoped_identity(tree$manifest_identity)))
  expected_payload <- .wb_operation_pack_v3_model_payload_identity(tree)
  expected_tree <- list(schema =
      "scworkbench.operation_pack.derived_fitted_model_tree_observation.v1",
    sealed_model_grant_identity = .wb_operation_pack_v3_unscoped_identity(
      model_grant$sealed_grant_identity), tree_manifest = tree,
    tree_manifest_identity = .wb_operation_pack_v3_unscoped_identity(
      tree$manifest_identity), payload_manifest_identity = expected_payload,
    model_source_linkage_identity = .wb_operation_pack_v3_unscoped_identity(
      expected_linkage$linkage_identity), status = "complete")
  expected_tree$observation_identity <- .wb_operation_pack_v2_identity_scoped(
    expected_tree$schema, "observation excluding observation_identity",
    expected_tree)
  if (!identical(model_descriptor$content_identity, expected_content) ||
      !identical(model_descriptor$payload_manifest_identity,
        expected_payload) || !identical(model_descriptor$
          model_linkage_identity, .wb_operation_pack_v3_unscoped_identity(
            expected_linkage$linkage_identity)) ||
      !identical(model_descriptor$contained_model_sibling_tree,
        expected_tree))
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "Derived fitted-axis model observation differs from staged bytes.",
      "receipt")
  for (sealed in sibling_grants) {
    name <- as.character(sealed$name)[1]
    descriptor <- observed[[match(name, observed_names)]]$descriptor
    expected_content <- .wb_operation_pack_v2_identity_plain(
      paste0("scworkbench.", sealed$kind, ".content.v1"),
      unclass(writes[[name]]$value))
    expected_payload <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.payload_manifest.v2", list(
        path = paste0("outputs/", name, "/payload.rds"),
        size = as.numeric(file.info(writes[[name]]$payload)$size),
        sha256 = .wb_operation_pack_v2_file_sha256(writes[[name]]$payload)))
    if (!identical(descriptor$content_identity, expected_content) ||
        !identical(descriptor$payload_manifest_identity, expected_payload))
      .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
        "Derived fitted-axis sibling observation differs from staged bytes.",
        "receipt")
  }
  state <- new.env(parent = emptyenv())
  state$derived_fitted_axis <- list(grant = grant,
    declaration = declaration, seal = expected_seal,
    evidence = evidence, model_grant = model_grant,
    sibling_grants = sibling_grants, model_source_linkage = expected_linkage)
  expected <- .wb_operation_pack_v3_dfa_observation(request, state,
    observed, writes)
  if (!identical(expected, observations))
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "Derived fitted-axis receipt observation is not the exact staged closure.",
      "receipt")
  .wb_operation_pack_v2_fault("derived_fitted_axis_receipt_audited")
  invisible(TRUE)
}
