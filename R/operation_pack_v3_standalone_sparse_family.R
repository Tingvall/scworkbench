# Generic opt-in authority for an independent sparse cell-vector family.
# A provisional request grant cannot write. A private, exactly-once layout
# declaration creates the process-local sealed writer.

.wb_operation_pack_v3_sscf_domain <- function(suffix) paste0(
  "scworkbench.operation_pack.", suffix, ".v1")

.wb_operation_pack_v3_sscf_identity <- function(value, field, suffix, scope) {
  value[[field]] <- .wb_operation_pack_v2_identity_scoped(
    .wb_operation_pack_v3_sscf_domain(suffix), scope, value)
  value
}

.wb_operation_pack_v3_sscf_policy <- function(operation) {
  Filter(function(x) identical(as.character(x$policy %||% "")[1],
    "standalone_sparse_cell_family_v1"),
    operation$dimension_policies %||% list())
}

.wb_operation_pack_v3_sscf_semantic_validate <- function(operation, inputs,
    outputs, backend) {
  policies <- .wb_operation_pack_v3_sscf_policy(operation)
  if (!length(policies)) return(invisible(TRUE))
  fail <- function(message) .wb_operation_pack_v3_error(
    "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID", message,
    "semantic_admission")
  if (length(policies) != 1L || !identical(backend, "R"))
    fail("Standalone sparse cell-family authority is one R-only terminal per operation.")
  policy <- policies[[1L]]
  name <- as.character(policy$output %||% "")[1]
  output <- outputs[[name]]
  source <- policy$axis_source %||% list()
  source_kind <- as.character(source$source %||% "")[1]
  reads <- operation$self_linked_contained_model_reads %||% list()
  model_reads <- stats::setNames(reads, vapply(reads,
    function(x) as.character(x$name)[1], character(1)))
  source_ok <- if (identical(source_kind, "typed_space_input_v1")) {
    setequal(names(source), c("input", "source")) &&
      as.character(inputs[[as.character(source$input)[1]]]$kind %||% "")[1] %in%
        c("space", "space_2d")
  } else if (identical(source_kind, "verified_g1_model_fitted_axis_v1")) {
    setequal(names(source), c("model_read", "source")) &&
      !is.null(model_reads[[as.character(source$model_read)[1]]])
  } else FALSE
  limits <- c(axis = policy$maximum_axis_cells, keys = policy$maximum_keys,
    rows = policy$maximum_rows, id = policy$maximum_id_bytes,
    control = policy$maximum_control_bytes)
  maxima <- c(axis = 1000000, keys = 64, rows = 1000000, id = 1024,
    control = 67108864)
  valid_limits <- length(limits) == 5L && all(is.finite(as.numeric(limits))) &&
    all(as.numeric(limits) >= 1) && all(as.numeric(limits) ==
      floor(as.numeric(limits))) && all(as.numeric(limits) <= maxima)
  fields <- c("schema", "output", "policy", "axis_source", "key_order",
    "row_order", "per_key_coverage", "missing_values",
    "declaration_discipline", "maximum_axis_cells", "maximum_keys",
    "maximum_rows", "maximum_id_bytes", "maximum_control_bytes",
    "policy_identity")
  if (is.null(output) || !identical(as.character(output$kind)[1],
      "cell_vector_family") || !isTRUE(output$required) ||
      !identical(as.character(output$category)[1], "terminal_artifact") ||
      !setequal(names(policy), fields) || !source_ok || !valid_limits ||
      !identical(as.character(policy$schema)[1],
        .wb_operation_pack_v3_sscf_domain(
          "standalone_sparse_cell_family_policy")) ||
      !identical(as.character(policy$key_order)[1], "declared_verbatim_v1") ||
      !identical(as.character(policy$row_order)[1],
        "key_major_then_source_relative_cell_v1") ||
      !identical(as.character(policy$per_key_coverage)[1],
        "per_key_source_relative_subset_v1") ||
      !identical(as.character(policy$missing_values)[1], "forbidden") ||
      !identical(as.character(policy$declaration_discipline)[1],
        "exactly_once_before_write") ||
      !identical(as.character(policy$policy_identity$scheme %||% "")[1],
        policy$schema) ||
      !identical(as.character(policy$policy_identity$scope %||% "")[1],
        "policy excluding policy_identity"))
    fail("Invalid closed standalone sparse cell-family policy.")
  .wb_operation_pack_v3_assert_self_identity(policy, "policy_identity",
    "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID", "semantic_admission")
  if (!is.null(output$derived_fitted_axis_policy) ||
      !is.null(output$contained_model_sibling_closure_policy) ||
      any(vapply(outputs, function(candidate) name %in% as.character(
        unlist(candidate$contained_model_sibling_closure_policy$
          required_sibling_terminals %||% list(), use.names = FALSE)),
        logical(1))) ||
      any(vapply(operation$derived_cell_output_axes %||% list(),
        function(x) name %in% vapply(x$linked_outputs %||% list(),
          function(y) as.character(y$name)[1], character(1)), logical(1))))
    fail("Standalone sparse output conflicts with model-sibling or G7 authority.")
  invisible(TRUE)
}

.wb_operation_pack_v3_sscf_source <- function(bundle, policy, inputs,
    input_records, self_reads, source_state_identity) {
  axis <- policy$axis_source
  kind <- as.character(axis$source)[1]
  if (identical(kind, "typed_space_input_v1")) {
    name <- as.character(axis$input)[1]
    value <- inputs[[name]]
    cells <- as.character(value$cell_id %||% rownames(value$values))
    content <- .wb_operation_pack_v3_phase5_primitive_identity(bundle,
      value)
    source <- list(schema = .wb_operation_pack_v3_sscf_domain(
        "sparse_family_source_axis"), source_kind = kind,
      input_name = name,
      source_space_id = as.character(value$space_id)[1],
      input_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
        input_records[[name]]$descriptor_identity),
      input_content_identity = content,
      ordered_cells = unname(as.list(cells)),
      cell_order_identity = .wb_operation_pack_v2_identity_plain(
        "scworkbench.cell_order.v1", unname(as.list(cells))),
      source_state_identity = source_state_identity)
  } else {
    name <- as.character(axis$model_read)[1]
    grant <- self_reads$grants[[name]]
    linkage <- grant$model_source_linkage
    if (identical(as.character(linkage$schema %||% "")[1],
        "scworkbench.operation_pack.model_source_linkage.v3")) {
      fitted <- self_reads$values[[name]]$fitted_space
      cells <- rownames(fitted)
      evidence <- list(schema =
          "scworkbench.operation_pack.sparse_family_g1_axis_evidence.v3",
        verified_parent_snapshot_identity = linkage$parent_snapshot_identity,
        selected_axis_seal_identity = linkage$fitted_axis_seal_identity,
        selected_axis_sidecar_identity = linkage$selected_axis_evidence$
          evidence_identity)
    } else {
      current <- wb_space(bundle, linkage$source_space_id)
      cells <- rownames(current)
      evidence <- list(schema =
          "scworkbench.operation_pack.sparse_family_g1_axis_evidence.v2",
        verified_source_space_snapshot_identity = list(
          scheme = "scworkbench.space.content.v1",
          sha256 = as.character(linkage$source_snapshot_id)[1]),
        verified_full_axis_order_identity = linkage$fitted_cell_order_identity)
    }
    evidence$evidence_identity <- .wb_operation_pack_v2_identity_scoped(
      as.character(evidence$schema)[1],
      "evidence excluding evidence_identity", evidence)
    if (!length(cells) || !identical(.wb_operation_pack_v2_identity_plain(
        "scworkbench.cell_order.v1", unname(as.list(cells))),
        linkage$fitted_cell_order_identity))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Verified G1 fitted axis contradicts model linkage.", "resolution")
    model_name <- as.character(grant$input_name)[1]
    source <- list(schema = .wb_operation_pack_v3_sscf_domain(
        "sparse_family_source_axis"), source_kind = kind,
      model_read_name = name,
      model_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
        input_records[[model_name]]$descriptor_identity),
      model_content_identity = input_records[[model_name]]$content_identity,
      g1_read_grant_identity = .wb_operation_pack_v3_unscoped_identity(
        grant$grant_identity),
      model_linkage_identity = .wb_operation_pack_v3_unscoped_identity(
        linkage$linkage_identity),
      contained_tree_identity = .wb_operation_pack_v3_unscoped_identity(
        grant$tree_manifest$manifest_identity),
      axis_evidence = evidence, ordered_fitted_cells = unname(as.list(cells)),
      cell_order_identity = .wb_operation_pack_v2_identity_plain(
        "scworkbench.cell_order.v1", unname(as.list(cells))))
  }
  if (!length(cells) || anyNA(cells) || any(!nzchar(cells)) ||
      anyDuplicated(cells) || length(cells) >
        as.integer(policy$maximum_axis_cells) ||
      any(nchar(enc2utf8(cells), type = "bytes", allowNA = FALSE) >
        as.integer(policy$maximum_id_bytes)))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Sparse-family source axis exceeds its grant or is malformed.",
      "resolution")
  .wb_operation_pack_v3_sscf_identity(source, "source_axis_identity",
    "sparse_family_source_axis", "source axis excluding source_axis_identity")
}

.wb_operation_pack_v3_sscf_grant <- function(policy, source, output,
    transition_identity) {
  grant <- list(schema = .wb_operation_pack_v3_sscf_domain(
      "sparse_family_provisional_grant"),
    manifest_policy_identity = .wb_operation_pack_v3_unscoped_identity(
      policy$policy_identity),
    source_axis = source,
    source_axis_identity = .wb_operation_pack_v3_unscoped_identity(
      source$source_axis_identity),
    ordinary_output_base_grant_identity =
      .wb_operation_pack_v3_unscoped_identity(
        output$descriptor$grant_identity),
    transition_identity = .wb_operation_pack_v3_unscoped_identity(
      transition_identity), output_name = output$name, kind = "cell_vector_family",
    limits = list(maximum_axis_cells = as.integer(policy$maximum_axis_cells),
      maximum_keys = as.integer(policy$maximum_keys),
      maximum_rows = as.integer(policy$maximum_rows),
      maximum_id_bytes = as.integer(policy$maximum_id_bytes),
      maximum_control_bytes = as.integer(policy$maximum_control_bytes)))
  .wb_operation_pack_v3_sscf_identity(grant, "grant_identity",
    "sparse_family_provisional_grant", "provisional grant excluding grant_identity")
}

.wb_operation_pack_v3_sscf_cells <- function(source) as.character(unlist(
  source$ordered_cells %||% source$ordered_fitted_cells,
  use.names = FALSE))

.wb_operation_pack_v3_sscf_source_assert_current <- function(bundle, request,
    inputs, phase = "audit") {
  grants <- request$standalone_sparse_cell_family_grants %||% list()
  if (!length(grants)) return(invisible(TRUE))
  grant <- grants[[1L]]
  source <- grant$source_axis
  cells <- .wb_operation_pack_v3_sscf_cells(source)
  if (identical(as.character(source$source_kind)[1],
      "typed_space_input_v1")) {
    name <- as.character(source$input_name)[1]
    original <- inputs[[name]]
    current <- if (identical(as.character(original$kind)[1], "space_2d"))
      wb_prim_space_2d(original$space_id) else wb_prim_space(
        original$space_id)
    current <- .wb_operation_pack_v2_bind_inputs(bundle,
      stats::setNames(list(current), name), cells)[[name]]
    observed <- .wb_operation_pack_v3_phase5_primitive_identity(bundle,
      current)
    if (!identical(as.character(current$cell_id), cells) ||
        !identical(observed, source$input_content_identity))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Sparse-family typed source changed after authentication.", phase)
  } else {
    name <- as.character(source$model_read_name)[1]
    reads <- stats::setNames(request$self_linked_model_payload_grants %||%
      list(), vapply(request$self_linked_model_payload_grants %||% list(),
        function(x) as.character(x$name)[1], character(1)))
    read <- reads[[name]]
    model <- inputs[[as.character(read$input_name)[1]]]
    linkage <- read$model_source_linkage
    tree <- .wb_operation_pack_v3_model_tree_source(bundle, model,
      read$selected_model$engine, read$selected_model$model_type)
    if (!identical(tree$manifest, read$tree_manifest) ||
        !identical(tree$payload_manifest_identity,
          read$payload_manifest_identity))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Sparse-family G1 model tree changed after authentication.", phase)
    if (identical(as.character(linkage$schema %||% "")[1],
        "scworkbench.operation_pack.model_source_linkage.v3")) {
      fitted <- .wb_operation_pack_v3_dfa_reopen(bundle, model, linkage,
        tree$root, phase = phase)
      current_cells <- rownames(fitted)
    } else {
      current <- wb_prim_space(linkage$source_space_id)
      current$values <- wb_space(bundle, linkage$source_space_id)
      current$cell_id <- rownames(current$values)
      current$dimensions <- as.integer(dim(current$values))
      current$storage_profile <- "space_dense_v1"
      identity <- .wb_operation_pack_v3_phase5_primitive_identity(bundle,
        current)
      current_cells <- current$cell_id
      if (!identical(identity$sha256,
          as.character(linkage$source_snapshot_id)[1]))
        .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
          "Sparse-family G1 source space changed after authentication.",
          phase)
    }
    if (!identical(current_cells, cells))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Sparse-family G1 fitted cell order changed.", phase)
  }
  invisible(TRUE)
}

.wb_operation_pack_v3_sscf_layout <- function(grant, output, ordered_keys,
    per_key_cells) {
  fail <- function(message, code = "PYBENCH_CAPABILITY_MISMATCH")
    .wb_operation_pack_v3_error(code, message, "execution")
  keys <- as.character(ordered_keys)
  if (!is.character(ordered_keys) || !is.list(per_key_cells) ||
      !length(keys) || length(keys) != length(per_key_cells) ||
      anyNA(keys) || any(!nzchar(keys)) || anyDuplicated(keys))
    fail("Sparse-family layout requires unique nonempty ordered keys and one cell list per key.")
  limits <- grant$limits
  if (length(keys) > as.integer(limits$maximum_keys))
    fail("Sparse-family layout exceeds its key ceiling.")
  axis <- .wb_operation_pack_v3_sscf_cells(grant$source_axis)
  rows <- sum(as.double(lengths(per_key_cells)))
  if (!is.finite(rows) || rows > as.double(limits$maximum_rows) ||
      rows > .Machine$integer.max)
    fail("Sparse-family layout exceeds its row ceiling.")
  encoded_keys <- enc2utf8(keys)
  encoded_cells <- lapply(per_key_cells, function(x) {
    if (!is.character(x) || !length(x) || anyNA(x) ||
        any(!nzchar(x)) || anyDuplicated(x))
      fail("Each sparse-family key needs a nonempty unique cell subset.",
        "PYBENCH_OUTPUT_INVALID")
    x <- enc2utf8(x)
    positions <- match(x, axis)
    if (anyNA(positions) || !identical(positions,
        sort(positions, method = "radix")))
      fail("Sparse-family cells must be a source-relative ordered subset.",
        "PYBENCH_OUTPUT_INVALID")
    x
  })
  bytes <- c(nchar(encoded_keys, type = "bytes", allowNA = FALSE),
    unlist(lapply(encoded_cells, nchar, type = "bytes",
      allowNA = FALSE), use.names = FALSE))
  if (any(bytes > as.double(limits$maximum_id_bytes)) ||
      sum(as.double(bytes)) > as.double(limits$maximum_control_bytes))
    fail("Sparse-family layout exceeds its identifier-byte ceiling.")
  pairs <- unlist(lapply(seq_along(encoded_keys), function(i) lapply(
    encoded_cells[[i]], function(cell) list(key = encoded_keys[[i]],
      cell_id = cell))), recursive = FALSE)
  declaration <- list(schema = .wb_operation_pack_v3_sscf_domain(
      "sparse_family_layout_declaration"),
    provisional_grant_identity = .wb_operation_pack_v3_unscoped_identity(
      grant$grant_identity), output_name = output,
    ordered_keys = unname(as.list(encoded_keys)),
    per_key_cells = unname(lapply(seq_along(encoded_keys), function(i)
      list(key = encoded_keys[[i]],
        cell_ids = unname(as.list(encoded_cells[[i]]))))),
    declared_row_count = as.integer(rows))
  declaration <- .wb_operation_pack_v3_sscf_identity(declaration,
    "declaration_identity", "sparse_family_layout_declaration",
    "declaration excluding declaration_identity")
  seal <- list(schema = .wb_operation_pack_v3_sscf_domain(
      "sparse_family_layout_seal"),
    provisional_grant_identity = .wb_operation_pack_v3_unscoped_identity(
      grant$grant_identity),
    declaration_identity = .wb_operation_pack_v3_unscoped_identity(
      declaration$declaration_identity),
    source_axis_identity = grant$source_axis_identity,
    ordered_keys = declaration$ordered_keys,
    per_key_cell_counts = unname(as.list(as.integer(
      lengths(encoded_cells)))),
    per_key_cell_order_identities = unname(lapply(encoded_cells,
      function(x) .wb_operation_pack_v2_identity_plain(
        "scworkbench.cell_order.v1", unname(as.list(x))))),
    key_major_pair_order_identity = .wb_operation_pack_v2_identity_plain(
      .wb_operation_pack_v3_sscf_domain("sparse_family_pair_order"), pairs),
    row_count = as.integer(rows))
  seal <- .wb_operation_pack_v3_sscf_identity(seal, "seal_identity",
    "sparse_family_layout_seal", "seal excluding seal_identity")
  writer <- list(schema = .wb_operation_pack_v3_sscf_domain(
      "sparse_family_sealed_output_grant"),
    base_grant_identity = grant$ordinary_output_base_grant_identity,
    layout_seal_identity = .wb_operation_pack_v3_unscoped_identity(
      seal$seal_identity), output_name = output, kind = "cell_vector_family",
    exact_dimensions = list(as.integer(rows), 3L),
    source_axis_identity = grant$source_axis_identity)
  writer <- .wb_operation_pack_v3_sscf_identity(writer, "grant_identity",
    "sparse_family_sealed_output_grant", "sealed output grant excluding grant_identity")
  list(declaration = declaration, seal = seal, writer = writer, pairs = pairs)
}

.wb_operation_pack_v3_sscf_assert_value <- function(value, layout,
    code = "PYBENCH_OUTPUT_INVALID", phase = "audit") {
  if (!.wb_is_primitive(value) || !identical(as.character(value$kind)[1],
      "cell_vector_family"))
    .wb_operation_pack_v3_error(code,
      "Sparse-family output is not a cell_vector_family.", phase)
  keys <- as.character(value$key %||% character())
  cells <- as.character(value$cell_id %||% character())
  values <- value$value %||% NULL
  pairs <- unname(Map(function(key, cell_id) list(key = key,
    cell_id = cell_id), keys, cells))
  observed <- .wb_operation_pack_v2_identity_plain(
    .wb_operation_pack_v3_sscf_domain("sparse_family_pair_order"), pairs)
  if (length(keys) != as.integer(layout$seal$row_count) ||
      length(cells) != length(keys) || length(values) != length(keys) ||
      anyNA(values) || !identical(observed,
        layout$seal$key_major_pair_order_identity) ||
      !identical(as.integer(.wb_operation_pack_v2_dimensions(value)),
        as.integer(unlist(layout$writer$exact_dimensions,
          use.names = FALSE))))
    .wb_operation_pack_v3_error(code,
      "Sparse-family staged key, cell, value or row order differs from its seal.",
      phase)
  invisible(TRUE)
}

.wb_operation_pack_v3_sscf_request_audit <- function(request, operation,
    bundle = NULL, inputs = NULL) {
  policies <- .wb_operation_pack_v3_sscf_policy(operation)
  grants <- request$standalone_sparse_cell_family_grants %||% list()
  if (length(policies) != length(grants))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Sparse-family provisional grant is not a bijection with policy.",
      "staging")
  if (!length(grants)) return(invisible(TRUE))
  grant <- grants[[1L]]
  source <- grant$source_axis
  .wb_operation_pack_v3_assert_self_identity(source,
    "source_axis_identity", "PYBENCH_CAPABILITY_MISMATCH", "staging")
  .wb_operation_pack_v3_assert_self_identity(grant, "grant_identity",
    "PYBENCH_CAPABILITY_MISMATCH", "staging")
  policy <- policies[[1L]]
  output_index <- match(grant$output_name,
    vapply(request$outputs, `[[`, character(1), "name"))
  if (is.na(output_index))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Sparse-family grant names no request output.", "staging")
  output <- request$outputs[[output_index]]
  descriptor <- output$descriptor
  policy_source <- policy$axis_source
  if (!identical(as.character(source$source_kind)[1],
      as.character(policy_source$source)[1]) ||
      (identical(source$source_kind, "typed_space_input_v1") &&
        !identical(as.character(source$input_name)[1],
          as.character(policy_source$input)[1])) ||
      (identical(source$source_kind,
          "verified_g1_model_fitted_axis_v1") &&
        !identical(as.character(source$model_read_name)[1],
          as.character(policy_source$model_read)[1])))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Sparse-family source branch contradicts the admitted manifest.",
      "staging")
  if (!identical(descriptor$
      standalone_sparse_cell_family_provisional_grant, grant) ||
      !identical(grant$manifest_policy_identity,
        .wb_operation_pack_v3_unscoped_identity(
          policy$policy_identity)) ||
      !identical(grant$transition_identity,
        .wb_operation_pack_v3_unscoped_identity(
          request$transition$transition_identity)) ||
      !identical(grant$kind, "cell_vector_family"))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Sparse-family grant differs from policy, output, or transition.",
      "staging")
  if (!identical(grant$source_axis_identity,
      .wb_operation_pack_v3_unscoped_identity(
        source$source_axis_identity)) ||
      !identical(grant$limits, list(
        maximum_axis_cells = as.integer(policy$maximum_axis_cells),
        maximum_keys = as.integer(policy$maximum_keys),
        maximum_rows = as.integer(policy$maximum_rows),
        maximum_id_bytes = as.integer(policy$maximum_id_bytes),
        maximum_control_bytes = as.integer(
          policy$maximum_control_bytes))) ||
      !identical(as.character(grant$output_name)[1],
        as.character(policy$output)[1]))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Sparse-family limits, source or output differ from manifest policy.",
      "staging")
  input_map <- stats::setNames(lapply(request$inputs, function(x)
    x$descriptor), vapply(request$inputs, function(x)
      as.character(x$name)[1], character(1)))
  if (identical(as.character(source$source_kind)[1],
      "typed_space_input_v1")) {
    input <- input_map[[as.character(source$input_name)[1]]]
    if (is.null(input) || !identical(source$input_descriptor_identity,
        .wb_operation_pack_v3_unscoped_identity(
          input$descriptor_identity)) ||
        !identical(source$cell_order_identity,
          input$cell_order_identity) ||
        !identical(source$source_state_identity,
          request$execution_capability$source_state_identity))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Sparse-family typed source is not bound to its request input.",
        "staging")
  } else {
    reads <- stats::setNames(request$self_linked_model_payload_grants %||%
      list(), vapply(request$self_linked_model_payload_grants %||% list(),
        function(x) as.character(x$name)[1], character(1)))
    read <- reads[[as.character(source$model_read_name)[1]]]
    input <- if (!is.null(read)) input_map[[as.character(
      read$input_name)[1]]] else NULL
    if (is.null(read) || is.null(input) ||
        !identical(source$model_descriptor_identity,
          .wb_operation_pack_v3_unscoped_identity(
            input$descriptor_identity)) ||
        !identical(source$model_content_identity,
          input$content_identity) ||
        !identical(source$g1_read_grant_identity,
          .wb_operation_pack_v3_unscoped_identity(
            read$grant_identity)) ||
        !identical(source$model_linkage_identity,
          .wb_operation_pack_v3_unscoped_identity(
            read$model_source_linkage$linkage_identity)) ||
        !identical(source$contained_tree_identity,
          .wb_operation_pack_v3_unscoped_identity(
            read$tree_manifest$manifest_identity)) ||
        !identical(source$cell_order_identity,
          read$model_source_linkage$fitted_cell_order_identity))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Sparse-family G1 source is not bound to verified model evidence.",
        "staging")
    .wb_operation_pack_v3_assert_self_identity(source$axis_evidence,
      "evidence_identity", "PYBENCH_CAPABILITY_MISMATCH", "staging")
    linkage <- read$model_source_linkage
    evidence <- source$axis_evidence
    expected_evidence <- if (identical(as.character(linkage$schema %||%
        "")[1], "scworkbench.operation_pack.model_source_linkage.v3"))
      list(schema = "scworkbench.operation_pack.sparse_family_g1_axis_evidence.v3",
        verified_parent_snapshot_identity = linkage$parent_snapshot_identity,
        selected_axis_seal_identity = linkage$fitted_axis_seal_identity,
        selected_axis_sidecar_identity = linkage$selected_axis_evidence$
          evidence_identity) else
      list(schema = "scworkbench.operation_pack.sparse_family_g1_axis_evidence.v2",
        verified_source_space_snapshot_identity = list(
          scheme = "scworkbench.space.content.v1",
          sha256 = as.character(linkage$source_snapshot_id)[1]),
        verified_full_axis_order_identity = linkage$fitted_cell_order_identity)
    expected_evidence$evidence_identity <-
      .wb_operation_pack_v2_identity_scoped(
        expected_evidence$schema,
        "evidence excluding evidence_identity", expected_evidence)
    if (!identical(evidence, expected_evidence))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Sparse-family G1 axis evidence contradicts verified linkage.",
        "staging")
  }
  base <- descriptor
  base$standalone_sparse_cell_family_provisional_grant <- NULL
  base$grant_identity <- NULL
  base_id <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.output_grant.v3",
    "descriptor excluding grant_identity", base)
  if (!identical(grant$ordinary_output_base_grant_identity,
      .wb_operation_pack_v3_unscoped_identity(base_id)) ||
      !identical(request$execution_capability$
        standalone_sparse_cell_family_grant_identities,
        list(.wb_operation_pack_v3_unscoped_identity(
          grant$grant_identity))))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Sparse-family base or capability identity is inconsistent.",
      "staging")
  if (!is.null(bundle)) .wb_operation_pack_v3_sscf_source_assert_current(
    bundle, request, inputs, "staging")
  invisible(TRUE)
}

.wb_operation_pack_v3_sscf_adapter <- function(base, request, bundle,
    inputs) {
  grants <- request$standalone_sparse_cell_family_grants %||% list()
  if (!length(grants)) return(base)
  state <- base$state
  state$standalone_sparse_cell_family <- NULL
  state$standalone_sparse_cell_family_write_attempted <- FALSE
  grant <- grants[[1L]]
  name <- as.character(grant$output_name)[1]
  base$writers$declare_sparse_cell_family_layout <- function(output,
      ordered_keys, per_key_cells) {
    output <- as.character(output)[1]
    if (isTRUE(state$used) || !identical(output, name) ||
        !is.null(state$standalone_sparse_cell_family) ||
        isTRUE(state$standalone_sparse_cell_family_write_attempted) ||
        !is.null(state$writes[[name]]))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Sparse-family layout must be declared exactly once before its write.",
        "execution")
    .wb_operation_pack_v3_sscf_source_assert_current(bundle, request,
      inputs, "execution")
    layout <- .wb_operation_pack_v3_sscf_layout(grant, output,
      ordered_keys, per_key_cells)
    state$standalone_sparse_cell_family <- layout
    .wb_operation_pack_v2_fault("sparse_cell_family_sealed",
      output = output)
    invisible(.wb_operation_pack_v2_deep_copy(layout$writer))
  }
  original <- base$writers$write_terminal_primitive
  base$writers$write_terminal_primitive <- function(name, value,
      semantic_metadata = list()) {
    name <- as.character(name)[1]
    if (identical(name, as.character(grant$output_name)[1])) {
      layout <- state$standalone_sparse_cell_family
      if (isTRUE(state$standalone_sparse_cell_family_write_attempted) ||
          is.null(layout) || !is.null(state$writes[[name]])) {
        state$standalone_sparse_cell_family_write_attempted <- TRUE
        .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
          "Sparse-family terminal has no unused sealed writer authority.",
          "execution")
      }
      state$standalone_sparse_cell_family_write_attempted <- TRUE
      .wb_operation_pack_v3_sscf_assert_value(value, layout,
        phase = "execution")
      .wb_operation_pack_v3_sscf_source_assert_current(bundle, request,
        inputs, "execution")
    }
    original(name, value, semantic_metadata)
  }
  base
}

.wb_operation_pack_v3_sscf_observation <- function(request, state,
    observed, writes) {
  grants <- request$standalone_sparse_cell_family_grants %||% list()
  if (!length(grants)) return(list())
  grant <- grants[[1L]]
  name <- as.character(grant$output_name)[1]
  layout <- state$standalone_sparse_cell_family %||% NULL
  output <- observed[[match(name, vapply(observed, function(x)
    as.character(x$name)[1], character(1)))]]
  write <- writes[[name]]
  if (is.null(layout) || is.null(output) || is.null(write))
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "Sparse-family declaration, staged output, or receipt is absent.",
      "receipt")
  .wb_operation_pack_v3_sscf_assert_value(write$value, layout)
  keys <- as.character(write$value$key)
  cells <- as.character(write$value$cell_id)
  unique_keys <- unique(keys)
  per_key <- lapply(unique_keys, function(key) cells[keys == key])
  pair_identity <- .wb_operation_pack_v2_identity_plain(
    .wb_operation_pack_v3_sscf_domain("sparse_family_pair_order"),
    unname(Map(function(key, cell_id)
      list(key = key, cell_id = cell_id), keys, cells)))
  result <- list(schema = .wb_operation_pack_v3_sscf_domain(
      "observed_sparse_cell_family"),
    provisional_grant_identity = .wb_operation_pack_v3_unscoped_identity(
      grant$grant_identity),
    declaration = layout$declaration, seal = layout$seal,
    sealed_writer_grant = layout$writer,
    observed_keys = unname(as.list(unique_keys)),
    per_key_cell_counts = unname(as.list(as.integer(lengths(per_key)))),
    per_key_cell_order_identities = unname(lapply(per_key,
      function(x) .wb_operation_pack_v2_identity_plain(
        "scworkbench.cell_order.v1", unname(as.list(x))))),
    observed_pair_order_identity = pair_identity,
    observed_row_count = as.integer(length(keys)),
    observed_dimensions = unname(as.list(as.integer(
      .wb_operation_pack_v2_dimensions(write$value)))),
    output_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
      output$descriptor$observed_descriptor_identity),
    output_content_identity = output$descriptor$content_identity,
    payload_manifest_identity = output$descriptor$payload_manifest_identity,
    validation_status = "passed")
  if (!identical(result$observed_keys, layout$seal$ordered_keys) ||
      !identical(result$per_key_cell_counts,
        layout$seal$per_key_cell_counts) ||
      !identical(result$per_key_cell_order_identities,
        layout$seal$per_key_cell_order_identities) ||
      !identical(result$observed_pair_order_identity,
        layout$seal$key_major_pair_order_identity))
    .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
      "Sparse-family staged rows disagree with the sealed layout.",
      "audit")
  result <- .wb_operation_pack_v3_sscf_identity(result,
    "observation_identity", "observed_sparse_cell_family",
    "observation excluding observation_identity")
  list(result)
}

.wb_operation_pack_v3_sscf_receipt_audit <- function(receipt, request,
    stage_root = NULL, code = "PYBENCH_RECEIPT_MISMATCH",
    phase = "receipt") {
  grants <- request$standalone_sparse_cell_family_grants %||% list()
  observations <- receipt$sparse_cell_family_observations %||% list()
  if (length(grants) != length(observations))
    .wb_operation_pack_v3_error(code,
      "Sparse-family receipt observations are not a bijection with grants.",
      phase)
  if (!length(grants)) return(invisible(TRUE))
  grant <- grants[[1L]]
  item <- observations[[1L]]
  for (pair in list(c("declaration", "declaration_identity"),
      c("seal", "seal_identity"),
      c("sealed_writer_grant", "grant_identity")))
    .wb_operation_pack_v3_assert_self_identity(item[[pair[[1L]]]],
      pair[[2L]], code, phase)
  .wb_operation_pack_v3_assert_self_identity(item,
    "observation_identity", code, phase)
  .wb_operation_pack_v3_assert_self_identity(grant$source_axis,
    "source_axis_identity", code, phase)
  .wb_operation_pack_v3_assert_self_identity(grant,
    "grant_identity", code, phase)
  if (!identical(item$provisional_grant_identity,
      .wb_operation_pack_v3_unscoped_identity(grant$grant_identity)))
    .wb_operation_pack_v3_error(code,
      "Sparse-family receipt references the wrong provisional grant.",
      phase)
  rebuilt <- .wb_operation_pack_v3_sscf_layout(grant,
    as.character(grant$output_name)[1],
    as.character(unlist(item$declaration$ordered_keys, use.names = FALSE)),
    lapply(item$declaration$per_key_cells,
      function(x) as.character(unlist(x$cell_ids, use.names = FALSE))))
  same_json <- function(a, b) identical(
    .wb_operation_pack_canonical_json(a),
    .wb_operation_pack_canonical_json(b))
  if (!same_json(rebuilt$declaration, item$declaration) ||
      !same_json(rebuilt$seal, item$seal) ||
      !same_json(rebuilt$writer, item$sealed_writer_grant))
    .wb_operation_pack_v3_error(code,
      "Sparse-family receipt layout does not reconstruct from its source grant.",
      phase)
  outputs <- receipt$outputs %||% list()
  output <- outputs[[match(grant$output_name, vapply(outputs,
    function(x) as.character(x$name)[1], character(1)))]]
  if (is.null(output) || !identical(item$output_descriptor_identity,
      .wb_operation_pack_v3_unscoped_identity(
        output$descriptor$observed_descriptor_identity)) ||
      !identical(item$output_content_identity,
        output$descriptor$content_identity) ||
      !identical(item$payload_manifest_identity,
        output$descriptor$payload_manifest_identity) ||
      !identical(item$observed_keys, item$seal$ordered_keys) ||
      !identical(item$per_key_cell_counts,
        item$seal$per_key_cell_counts) ||
      !identical(item$per_key_cell_order_identities,
        item$seal$per_key_cell_order_identities) ||
      !identical(item$observed_pair_order_identity,
        item$seal$key_major_pair_order_identity) ||
      !identical(as.integer(item$observed_row_count),
        as.integer(item$seal$row_count)) ||
      !identical(item$observed_dimensions,
        item$sealed_writer_grant$exact_dimensions) ||
      !identical(item$validation_status, "passed"))
    .wb_operation_pack_v3_error(code,
      "Sparse-family receipt contradicts its sealed rows or staged output.",
      phase)
  if (!is.null(stage_root)) {
    payload <- file.path(stage_root, "outputs", grant$output_name,
      "payload.rds")
    value <- tryCatch(readRDS(payload), error = identity)
    if (inherits(value, "error"))
      .wb_operation_pack_v3_error(code,
        "Sparse-family retained payload is unreadable.", phase)
    .wb_operation_pack_v3_sscf_assert_value(value, rebuilt,
      code = code, phase = phase)
    observed_content <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_vector_family.content.v1", unclass(value))
    observed_payload <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.payload_manifest.v2",
      list(path = paste0("outputs/", grant$output_name, "/payload.rds"),
        size = as.numeric(file.info(payload)$size),
        sha256 = .wb_operation_pack_v2_file_sha256(payload)))
    if (!identical(observed_content, item$output_content_identity) ||
        !identical(observed_payload, item$payload_manifest_identity))
      .wb_operation_pack_v3_error(code,
        "Sparse-family retained content or payload differs from receipt.",
        phase)
  }
  invisible(TRUE)
}

.wb_operation_pack_v3_sscf_retained_assert_current <- function(bundle,
    request, record_path) {
  grants <- request$standalone_sparse_cell_family_grants %||% list()
  if (!length(grants)) return(invisible(TRUE))
  source <- grants[[1L]]$source_axis
  cells <- .wb_operation_pack_v3_sscf_cells(source)
  if (identical(as.character(source$source_kind)[1],
      "typed_space_input_v1")) {
    id <- as.character(source$source_space_id)[1]
    input <- request$inputs[[match(source$input_name,
      vapply(request$inputs, function(x) as.character(x$name)[1],
        character(1)))]]
    kind <- as.character(input$descriptor$kind)[1]
    current <- if (identical(kind, "space_2d")) wb_prim_space_2d(id)
      else wb_prim_space(id)
    current <- .wb_operation_pack_v2_bind_inputs(bundle,
      list(source = current), cells)[[1L]]
    observed <- .wb_operation_pack_v3_phase5_primitive_identity(bundle,
      current)
    if (!identical(as.character(current$cell_id), cells) ||
        !identical(observed, source$input_content_identity))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Retained sparse-family typed source is no longer verifiable.",
        "recipient")
  } else {
    reads <- request$self_linked_model_payload_grants %||% list()
    read <- reads[[match(source$model_read_name, vapply(reads,
      function(x) as.character(x$name)[1], character(1)))]]
    stage_root <- record_path
    .wb_operation_pack_v3_validate_model_read(stage_root, read)
    linkage <- read$model_source_linkage
    if (identical(as.character(linkage$schema %||% "")[1],
        "scworkbench.operation_pack.model_source_linkage.v3")) {
      fitted <- .wb_operation_pack_v3_dfa_reopen(bundle, NULL, linkage,
        file.path(stage_root, read$relative_root),
        phase = "recipient")
      current_cells <- rownames(fitted)
    } else {
      current <- wb_prim_space(linkage$source_space_id)
      current$values <- wb_space(bundle, linkage$source_space_id)
      current$cell_id <- rownames(current$values)
      current$dimensions <- as.integer(dim(current$values))
      current$storage_profile <- "space_dense_v1"
      identity <- .wb_operation_pack_v3_phase5_primitive_identity(bundle,
        current)
      current_cells <- current$cell_id
      if (!identical(identity$sha256,
          as.character(linkage$source_snapshot_id)[1]))
        .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
          "Retained sparse-family G1 full-axis source changed.",
          "recipient")
    }
    if (!identical(current_cells, cells))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Retained sparse-family G1 fitted axis changed.", "recipient")
  }
  invisible(TRUE)
}
