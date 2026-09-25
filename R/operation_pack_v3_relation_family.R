# Opt-in, exact-order relation-family output authority. The provisional grant
# has no writer. A single private declaration binds the effective cell axis,
# ordered keys, ordered structured pairs, and optional numeric-field presence.

.wb_operation_pack_v3_rf_domain <- function(name) paste0(
  "scworkbench.operation_pack.", name, ".v1")

.wb_operation_pack_v3_rf_id <- function(value, field, name, scope) {
  value[[field]] <- .wb_operation_pack_v2_identity_scoped(
    .wb_operation_pack_v3_rf_domain(name), scope, value)
  value
}

.wb_operation_pack_v3_rf_policy <- function(operation) Filter(
  function(x) identical(as.character(x$policy %||% "")[1],
    "sealed_relation_family_v1"), operation$dimension_policies %||% list())

.wb_operation_pack_v3_rf_semantic_validate <- function(operation, inputs,
    outputs, backend) {
  policies <- .wb_operation_pack_v3_rf_policy(operation)
  if (!length(policies)) return(invisible(TRUE))
  fail <- function(message) .wb_operation_pack_v3_error(
    "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID", message,
    "semantic_admission")
  if (length(policies) != 1L || !identical(as.character(backend)[1], "R"))
    fail("Sealed relation-family authority requires one R-backed output.")
  policy <- policies[[1L]]
  name <- as.character(policy$output %||% "")[1]
  output <- outputs[[name]]
  selector <- policy$axis_source %||% list()
  kind <- as.character(selector$source %||% "")[1]
  source_ok <- if (identical(kind, "typed_input_v1")) {
    setequal(names(selector), c("source", "input")) &&
      as.character(inputs[[as.character(selector$input)[1]]]$kind %||% "")[1] %in%
        c("space", "space_2d", "matrix")
  } else if (identical(kind, "g2_derived_fitted_axis_v1")) {
    model <- outputs[[as.character(selector$model_output %||% "")[1]]]
    setequal(names(selector), c("source", "model_output")) &&
      !is.null(model$derived_fitted_axis_policy) &&
      identical(as.character(model$promotion_group)[1],
        as.character(output$promotion_group)[1]) &&
      !name %in% vapply(model$derived_fitted_axis_policy$
        required_siblings %||% list(), function(x)
          as.character(x$name)[1], character(1))
  } else FALSE
  limits <- as.double(c(policy$maximum_axis_cells, policy$maximum_keys,
    policy$maximum_rows, policy$maximum_id_bytes,
    policy$maximum_control_bytes, policy$maximum_chunk_pairs))
  maxima <- c(1000000, 1024, 1000000, 1024, 67108864, 8192)
  fields <- c("schema", "output", "policy", "axis_source", "key_order",
    "row_order", "pair_multiplicity", "numeric_fields",
    "declaration_discipline", "maximum_axis_cells", "maximum_keys",
    "maximum_rows", "maximum_id_bytes", "maximum_control_bytes",
    "maximum_chunk_pairs", "policy_identity")
  valid_limits <- length(limits) == 6L && all(is.finite(limits)) &&
    all(limits >= 1) && all(limits == floor(limits)) &&
    all(limits <= maxima)
  if (is.null(output) || !identical(as.character(output$kind)[1],
      "relation_family") || !isTRUE(output$required) ||
      !identical(as.character(output$category)[1], "terminal_artifact") ||
      !setequal(names(policy), fields) || !source_ok || !valid_limits ||
      !identical(as.character(policy$schema)[1],
        .wb_operation_pack_v3_rf_domain("sealed_relation_family_policy")) ||
      !identical(as.character(policy$key_order)[1],
        "first_occurrence_v1") ||
      !identical(as.character(policy$row_order)[1],
        "declared_exact_v1") ||
      !identical(as.character(policy$pair_multiplicity)[1],
        "unique_key_cell_v1") ||
      !identical(as.character(policy$numeric_fields)[1],
        "declare_presence_finite_v1") ||
      !identical(as.character(policy$declaration_discipline)[1],
        "exactly_once_before_write") ||
      !identical(as.character(policy$policy_identity$scheme %||% "")[1],
        policy$schema) ||
      !identical(as.character(policy$policy_identity$scope %||% "")[1],
        "policy excluding policy_identity"))
    fail("Invalid closed sealed relation-family policy.")
  .wb_operation_pack_v3_assert_self_identity(policy, "policy_identity",
    "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID", "semantic_admission")
  if (!is.null(output$derived_fitted_axis_policy) ||
      any(vapply(operation$derived_cell_output_axes %||% list(),
        function(x) name %in% vapply(x$linked_outputs %||% list(),
          function(y) as.character(y$name)[1], character(1)), logical(1))))
    fail("Relation-family output conflicts with a second axis authority.")
  invisible(TRUE)
}

.wb_operation_pack_v3_rf_strings <- function(values, limit, label,
    code = "PYBENCH_CAPABILITY_MISMATCH", phase = "execution") {
  if (!is.character(values) || anyNA(values) || any(!nzchar(values)))
    .wb_operation_pack_v3_error(code, paste0(label,
      " requires nonempty character identifiers."), phase)
  values <- enc2utf8(values)
  bytes <- as.double(nchar(values, type = "bytes", allowNA = FALSE))
  if (any(!is.finite(bytes)) || any(bytes > as.double(limit)))
    .wb_operation_pack_v3_error(code, paste0(label,
      " exceeds its raw UTF-8 identifier limit."), phase)
  values
}

.wb_operation_pack_v3_rf_bytes <- function(values) sum(vapply(values,
  function(x) as.double(nchar(.wb_operation_pack_canonical_json(x),
    type = "bytes")), numeric(1)))

.wb_operation_pack_v3_rf_typed_source <- function(bundle, policy, inputs,
    input_records, state_identity) {
  name <- as.character(policy$axis_source$input)[1]
  value <- inputs[[name]]
  cells <- as.character(value$cell_id %||% rownames(value$values))
  cells <- .wb_operation_pack_v3_rf_strings(cells,
    policy$maximum_id_bytes, "Relation source axis", phase = "resolution")
  if (!length(cells) || anyDuplicated(cells) || length(cells) >
      as.integer(policy$maximum_axis_cells) ||
      .wb_operation_pack_v3_rf_bytes(cells) >
        as.double(policy$maximum_control_bytes))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Relation source axis is duplicated or exceeds its grant.",
      "resolution")
  source <- list(schema = .wb_operation_pack_v3_rf_domain(
      "relation_source_axis"), source_kind = "typed_input_v1",
    input_name = name,
    input_kind = as.character(value$kind)[1],
    source_id = as.character(value$space_id %||% value$matrix_id)[1],
    input_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
      input_records[[name]]$descriptor_identity),
    input_content_identity = .wb_operation_pack_v3_phase5_primitive_identity(
      bundle, value), source_state_identity = state_identity,
    ordered_cells = unname(as.list(cells)),
    cell_order_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", unname(as.list(cells))))
  .wb_operation_pack_v3_rf_id(source, "source_axis_identity",
    "relation_source_axis", "source axis excluding source_axis_identity")
}

.wb_operation_pack_v3_rf_grant <- function(policy, output,
    transition_identity, source_axis = NULL, g2_grant = NULL) {
  selector <- if (!is.null(source_axis)) list(
    source = "typed_input_v1", input = source_axis$input_name,
    source_axis_identity = .wb_operation_pack_v3_unscoped_identity(
      source_axis$source_axis_identity)) else list(
    source = "g2_derived_fitted_axis_v1",
    model_output = as.character(policy$axis_source$model_output)[1],
    g2_grant_identity = .wb_operation_pack_v3_unscoped_identity(
      g2_grant$grant_identity),
    parent_snapshot_identity = .wb_operation_pack_v3_unscoped_identity(
      g2_grant$parent_snapshot$parent_snapshot_identity))
  grant <- list(schema = .wb_operation_pack_v3_rf_domain(
      "relation_provisional_grant"),
    manifest_policy_identity = .wb_operation_pack_v3_unscoped_identity(
      policy$policy_identity), source_selector = selector,
    ordinary_output_base_grant_identity =
      .wb_operation_pack_v3_unscoped_identity(
        output$descriptor$grant_identity),
    transition_identity = .wb_operation_pack_v3_unscoped_identity(
      transition_identity), output_name = output$name,
    kind = "relation_family", limits = list(
      maximum_axis_cells = as.integer(policy$maximum_axis_cells),
      maximum_keys = as.integer(policy$maximum_keys),
      maximum_rows = as.integer(policy$maximum_rows),
      maximum_id_bytes = as.integer(policy$maximum_id_bytes),
      maximum_control_bytes = as.integer(policy$maximum_control_bytes),
      maximum_chunk_pairs = as.integer(policy$maximum_chunk_pairs)))
  if (!is.null(source_axis)) grant$known_source_axis <- source_axis
  .wb_operation_pack_v3_rf_id(grant, "grant_identity",
    "relation_provisional_grant", "provisional grant excluding grant_identity")
}

.wb_operation_pack_v3_rf_axis <- function(grant, request,
    derived_state = NULL, receipt = NULL) {
  selector <- grant$source_selector
  if (identical(selector$source, "typed_input_v1")) {
    source <- grant$known_source_axis
    cells <- as.character(unlist(source$ordered_cells,
      use.names = FALSE))
    if (is.null(source) || !identical(selector$input,
        source$input_name) || !identical(
          selector$source_axis_identity,
          .wb_operation_pack_v3_unscoped_identity(
            source$source_axis_identity)) ||
        !identical(source$cell_order_identity,
          .wb_operation_pack_v2_identity_plain(
            "scworkbench.cell_order.v1", unname(as.list(cells)))))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Relation known source axis contradicts its selector.",
        "execution")
    return(grant$known_source_axis)
  }
  g2 <- request$derived_fitted_axis_grants %||% list()
  if (length(g2) != 1L || !identical(selector$g2_grant_identity,
      .wb_operation_pack_v3_unscoped_identity(g2[[1L]]$grant_identity)) ||
      !identical(selector$parent_snapshot_identity,
        .wb_operation_pack_v3_unscoped_identity(
          g2[[1L]]$parent_snapshot$parent_snapshot_identity)))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Relation source selector contradicts the authenticated G2 grant.",
      "execution")
  observations <- receipt$derived_fitted_axis_observations %||% list()
  seal <- if (!is.null(derived_state)) derived_state$seal else
    if (length(observations) == 1L) observations[[1L]]$seal else NULL
  if (is.null(seal) || !identical(seal$provisional_grant_identity,
      selector$g2_grant_identity))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Relation writer requires a sealed G2 fitted axis.", "execution")
  cells <- as.character(unlist(seal$fitted_cell_ids, use.names = FALSE))
  cells <- .wb_operation_pack_v3_rf_strings(cells,
    grant$limits$maximum_id_bytes, "Sealed G2 fitted axis")
  if (!length(cells) || anyDuplicated(cells) || length(cells) >
      as.integer(grant$limits$maximum_axis_cells) ||
      !identical(seal$fitted_cell_order_identity,
        .wb_operation_pack_v2_identity_plain("scworkbench.cell_order.v1",
          unname(as.list(cells)))))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Sealed G2 fitted axis contradicts relation source bounds.",
      "execution")
  source <- list(schema = .wb_operation_pack_v3_rf_domain(
      "relation_source_axis"), source_kind =
      "g2_derived_fitted_axis_v1", model_output = selector$model_output,
    g2_grant_identity = selector$g2_grant_identity,
    parent_snapshot_identity = selector$parent_snapshot_identity,
    fitted_axis_seal_identity = .wb_operation_pack_v3_unscoped_identity(
      seal$seal_identity), ordered_cells = unname(as.list(cells)),
    cell_order_identity = seal$fitted_cell_order_identity)
  .wb_operation_pack_v3_rf_id(source, "source_axis_identity",
    "relation_source_axis", "source axis excluding source_axis_identity")
}

.wb_operation_pack_v3_rf_layout <- function(grant, source, output,
    ordered_keys, row_chunks, numeric_fields) {
  fail <- function(message, code = "PYBENCH_CAPABILITY_MISMATCH")
    .wb_operation_pack_v3_error(code, message, "execution")
  limits <- grant$limits
  keys <- .wb_operation_pack_v3_rf_strings(ordered_keys,
    limits$maximum_id_bytes, "Relation keys")
  if (!length(keys) || anyDuplicated(keys) || length(keys) >
      as.integer(limits$maximum_keys))
    fail("Relation key axis must be nonempty, unique and bounded.")
  if (!is.list(row_chunks) || !length(row_chunks) ||
      !identical(names(numeric_fields), c("weight", "value", "distance")) ||
      !is.logical(numeric_fields) || anyNA(numeric_fields))
    fail("Relation declaration requires row chunks and exact numeric-field presence.")
  axis <- as.character(unlist(source$ordered_cells, use.names = FALSE))
  budget <- .wb_operation_pack_v3_rf_bytes(axis) +
    .wb_operation_pack_v3_rf_bytes(keys)
  if (budget > as.double(limits$maximum_control_bytes))
    fail("Relation source/key axis exceeds encoded identifier budget.")
  seen <- new.env(hash = TRUE, parent = emptyenv())
  axis_set <- new.env(hash = TRUE, parent = emptyenv())
  for (cell in axis) assign(cell, TRUE, envir = axis_set)
  key_set <- new.env(hash = TRUE, parent = emptyenv())
  for (key in keys) assign(key, TRUE, envir = key_set)
  rows <- list(); row_count <- 0L; first_keys <- character()
  first_key_set <- new.env(hash = TRUE, parent = emptyenv())
  for (chunk in row_chunks) {
    if (!is.list(chunk) || !length(chunk) ||
        length(chunk) > as.integer(limits$maximum_chunk_pairs))
      fail("Relation declaration chunk is empty or exceeds its pair ceiling.")
    if (as.double(row_count) + as.double(length(chunk)) >
        as.double(limits$maximum_rows))
      fail("Relation declaration exceeds its row ceiling.")
    for (pair in chunk) {
      if (!is.list(pair) || !setequal(names(pair), c("key", "cell_id")))
        fail("Relation rows require structured key/cell_id pairs.")
      key <- .wb_operation_pack_v3_rf_strings(pair$key,
        limits$maximum_id_bytes, "Relation row key")
      cell <- .wb_operation_pack_v3_rf_strings(pair$cell_id,
        limits$maximum_id_bytes, "Relation row cell")
      if (length(key) != 1L || length(cell) != 1L ||
          !exists(key, envir = key_set, inherits = FALSE) ||
          !exists(cell, envir = axis_set, inherits = FALSE))
        fail("Relation row has an undeclared key or foreign cell.",
          "PYBENCH_OUTPUT_INVALID")
      budget <- budget + .wb_operation_pack_v3_rf_bytes(key) +
        .wb_operation_pack_v3_rf_bytes(cell)
      if (budget > as.double(limits$maximum_control_bytes))
        fail("Relation declaration exceeds encoded identifier budget.")
      token <- .wb_operation_pack_canonical_json(list(key = key,
        cell_id = cell))
      if (exists(token, envir = seen, inherits = FALSE))
        fail("Relation declaration repeats a key/cell_id pair.",
          "PYBENCH_OUTPUT_INVALID")
      assign(token, TRUE, envir = seen)
      row_count <- row_count + 1L
      rows[[row_count]] <- list(key = key, cell_id = cell)
      if (!exists(key, envir = first_key_set, inherits = FALSE)) {
        assign(key, TRUE, envir = first_key_set)
        first_keys <- c(first_keys, key)
      }
    }
  }
  if (!row_count || !identical(first_keys, keys) ||
      as.double(row_count) > as.double(length(axis)) *
        as.double(length(keys)))
    fail("Relation rows do not cover their key axis or exceed unique-pair capacity.")
  declaration <- list(schema = .wb_operation_pack_v3_rf_domain(
      "relation_row_declaration"),
    provisional_grant_identity = .wb_operation_pack_v3_unscoped_identity(
      grant$grant_identity), output_name = output,
    ordered_keys = unname(as.list(keys)), ordered_pairs = unname(rows),
    declared_row_count = as.integer(row_count),
    numeric_fields = as.list(numeric_fields))
  declaration <- .wb_operation_pack_v3_rf_id(declaration,
    "declaration_identity", "relation_row_declaration",
    "declaration excluding declaration_identity")
  seal <- list(schema = .wb_operation_pack_v3_rf_domain(
      "relation_row_seal"),
    provisional_grant_identity = .wb_operation_pack_v3_unscoped_identity(
      grant$grant_identity),
    declaration_identity = .wb_operation_pack_v3_unscoped_identity(
      declaration$declaration_identity), source_axis = source,
    source_axis_identity = .wb_operation_pack_v3_unscoped_identity(
      source$source_axis_identity), ordered_key_axis_identity =
      .wb_operation_pack_v2_identity_plain(
        .wb_operation_pack_v3_rf_domain("relation_key_order"),
        unname(as.list(keys))),
    ordered_pair_axis_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.row_order.v1", unname(rows)),
    numeric_fields = as.list(numeric_fields), row_count = as.integer(row_count))
  seal <- .wb_operation_pack_v3_rf_id(seal, "seal_identity",
    "relation_row_seal", "seal excluding seal_identity")
  writer <- list(schema = .wb_operation_pack_v3_rf_domain(
      "relation_sealed_output_grant"), output_name = output,
    base_grant_identity = grant$ordinary_output_base_grant_identity,
    relation_seal_identity = .wb_operation_pack_v3_unscoped_identity(
      seal$seal_identity), exact_dimensions = list(as.integer(row_count), 3L),
    source_axis_identity = seal$source_axis_identity)
  writer <- .wb_operation_pack_v3_rf_id(writer, "grant_identity",
    "relation_sealed_output_grant",
    "sealed output grant excluding grant_identity")
  list(declaration = declaration, seal = seal, writer = writer)
}

.wb_operation_pack_v3_rf_assert_value <- function(value, layout,
    code = "PYBENCH_OUTPUT_INVALID", phase = "audit") {
  fail <- function(message) .wb_operation_pack_v3_error(code, message, phase)
  if (!.wb_is_primitive(value) || !identical(as.character(value$kind)[1],
      "relation_family")) fail("Sealed relation output is not a relation_family.")
  n <- as.integer(layout$seal$row_count)
  keys <- value$key; cells <- value$cell_id
  if (!is.character(keys) || !is.character(cells) ||
      length(keys) != n || length(cells) != n)
    fail("Sealed relation output has incorrect row count or types.")
  pairs <- unname(Map(function(key, cell_id) list(key = key,
    cell_id = cell_id), keys, cells))
  if (!identical(.wb_operation_pack_v2_identity_plain(
      "scworkbench.row_order.v1", pairs),
      layout$seal$ordered_pair_axis_identity))
    fail("Sealed relation output changed ordered key/cell_id pairs.")
  for (field in c("weight", "value", "distance")) {
    present <- isTRUE(layout$seal$numeric_fields[[field]])
    observed <- !is.null(value[[field]])
    if (!identical(present, observed))
      fail("Sealed relation output changed numeric-field presence.")
    if (present && (!is.numeric(value[[field]]) ||
        length(value[[field]]) != n || any(!is.finite(value[[field]]))))
      fail("Sealed relation numeric values must be complete and finite.")
  }
  invisible(TRUE)
}

.wb_operation_pack_v3_rf_adapter <- function(base, request, bundle,
    inputs) {
  grants <- request$sealed_relation_family_grants %||% list()
  if (!length(grants)) return(base)
  grant <- grants[[1L]]; state <- base$state
  state$sealed_relation_family <- NULL
  state$sealed_relation_family_declare_attempted <- FALSE
  state$sealed_relation_family_write_attempted <- FALSE
  name <- as.character(grant$output_name)[1]
  base$writers$declare_relation_family_rows <- function(output,
      ordered_keys, row_chunks, numeric_fields) {
    if (isTRUE(state$sealed_relation_family_declare_attempted))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Relation declaration authority was already attempted.", "execution")
    state$sealed_relation_family_declare_attempted <- TRUE
    if (isTRUE(state$used) || !identical(as.character(output)[1], name) ||
        !is.null(state$writes[[name]]) ||
        isTRUE(state$sealed_relation_family_write_attempted))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Relation rows must be declared exactly once before write.",
        "execution")
    .wb_operation_pack_v3_rf_source_assert_current(bundle, request,
      inputs, "execution")
    axis <- .wb_operation_pack_v3_rf_axis(grant, request,
      state$derived_fitted_axis %||% NULL)
    layout <- .wb_operation_pack_v3_rf_layout(grant, axis, name,
      ordered_keys, row_chunks, numeric_fields)
    .wb_operation_pack_v2_fault("relation_family_sealed", output = name)
    state$sealed_relation_family <- layout
    invisible(.wb_operation_pack_v2_deep_copy(layout$writer))
  }
  original <- base$writers$write_terminal_primitive
  base$writers$write_terminal_primitive <- function(name, value,
      semantic_metadata = list()) {
    if (identical(as.character(name)[1],
        as.character(grant$output_name)[1])) {
      layout <- state$sealed_relation_family
      if (isTRUE(state$sealed_relation_family_write_attempted) ||
          is.null(layout) || !is.null(state$writes[[name]])) {
        state$sealed_relation_family_write_attempted <- TRUE
        .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
          "Relation output has no unused sealed writer.", "execution")
      }
      state$sealed_relation_family_write_attempted <- TRUE
      .wb_operation_pack_v3_rf_assert_value(value, layout,
        phase = "execution")
      .wb_operation_pack_v3_rf_source_assert_current(bundle, request,
        inputs, "execution")
    }
    original(name, value, semantic_metadata)
  }
  base
}

.wb_operation_pack_v3_rf_source_assert_current <- function(bundle,
    request, inputs, phase = "audit") {
  grants <- request$sealed_relation_family_grants %||% list()
  if (!length(grants)) return(invisible(TRUE))
  grant <- grants[[1L]]
  if (identical(grant$source_selector$source, "typed_input_v1")) {
    source <- grant$known_source_axis
    name <- as.character(source$input_name)[1]
    original <- inputs[[name]]
    cells <- as.character(unlist(source$ordered_cells, use.names = FALSE))
    current <- switch(as.character(original$kind)[1],
      space = wb_prim_space(original$space_id),
      space_2d = wb_prim_space_2d(original$space_id),
      matrix = wb_prim_matrix(original$matrix_id))
    current <- .wb_operation_pack_v2_bind_inputs(bundle,
      stats::setNames(list(current), name), cells)[[name]]
    identity <- .wb_operation_pack_v3_phase5_primitive_identity(bundle,
      current)
    if (!identical(as.character(current$cell_id), cells) ||
        !identical(identity, source$input_content_identity))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Relation typed source changed after authentication.", phase)
  } else {
    g2 <- request$derived_fitted_axis_grants[[1L]]
    .wb_operation_pack_v3_dfa_parent_assert_current(bundle,
      g2$parent_snapshot, phase = phase)
  }
  invisible(TRUE)
}

.wb_operation_pack_v3_rf_request_audit <- function(request, operation,
    bundle = NULL, inputs = NULL) {
  policies <- .wb_operation_pack_v3_rf_policy(operation)
  grants <- request$sealed_relation_family_grants %||% list()
  if (length(policies) != length(grants))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Relation provisional grant does not match manifest policy.",
      "staging")
  if (!length(grants)) return(invisible(TRUE))
  grant <- grants[[1L]]; policy <- policies[[1L]]
  .wb_operation_pack_v3_assert_self_identity(grant, "grant_identity",
    "PYBENCH_CAPABILITY_MISMATCH", "staging")
  if (!is.null(grant$known_source_axis))
    .wb_operation_pack_v3_assert_self_identity(grant$known_source_axis,
      "source_axis_identity", "PYBENCH_CAPABILITY_MISMATCH", "staging")
  output <- request$outputs[[match(grant$output_name, vapply(
    request$outputs, `[[`, character(1), "name"))]]
  if (is.null(output))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Relation output is absent from request.", "staging")
  descriptor <- output$descriptor
  base_descriptor <- descriptor
  base_descriptor$sealed_relation_family_provisional_grant <- NULL
  base_descriptor$grant_identity <- NULL
  base_descriptor$grant_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.output_grant.v3",
    "descriptor excluding grant_identity", base_descriptor)
  expected_output <- list(name = output$name,
    descriptor = base_descriptor)
  source <- NULL; g2 <- NULL
  if (identical(as.character(policy$axis_source$source)[1],
      "typed_input_v1")) {
    records <- stats::setNames(lapply(request$inputs, `[[`, "descriptor"),
      vapply(request$inputs, function(x) as.character(x$name)[1],
        character(1)))
    source <- .wb_operation_pack_v3_rf_typed_source(bundle, policy,
      inputs, records, request$execution_capability$source_state_identity)
  } else {
    g2 <- (request$derived_fitted_axis_grants %||% list())[[1L]]
  }
  expected <- .wb_operation_pack_v3_rf_grant(policy, expected_output,
    request$transition$transition_identity, source_axis = source,
    g2_grant = g2)
  same <- function(a, b) identical(.wb_operation_pack_canonical_json(a),
    .wb_operation_pack_canonical_json(b))
  if (!same(expected, grant) || !identical(output$descriptor$
      sealed_relation_family_provisional_grant, grant) ||
      !identical(grant$manifest_policy_identity,
        .wb_operation_pack_v3_unscoped_identity(policy$policy_identity)) ||
      !identical(grant$transition_identity,
        .wb_operation_pack_v3_unscoped_identity(
          request$transition$transition_identity)) ||
      !identical(grant$output_name, policy$output) ||
      !identical(grant$source_selector$source,
        policy$axis_source$source) ||
      !identical(request$execution_capability$
        sealed_relation_family_grant_identities,
        list(.wb_operation_pack_v3_unscoped_identity(
          grant$grant_identity))))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Relation grant, output, source or capability identity differs.",
      "staging")
  if (!is.null(bundle)) .wb_operation_pack_v3_rf_source_assert_current(
    bundle, request, inputs, "staging")
  invisible(TRUE)
}

.wb_operation_pack_v3_rf_observation <- function(request, state,
    observed, writes) {
  grants <- request$sealed_relation_family_grants %||% list()
  if (!length(grants)) return(list())
  grant <- grants[[1L]]; name <- as.character(grant$output_name)[1]
  layout <- state$sealed_relation_family %||% NULL
  output <- observed[[match(name, vapply(observed, function(x)
    as.character(x$name)[1], character(1)))]]
  write <- writes[[name]]
  if (is.null(layout) || is.null(output) || is.null(write))
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "Relation declaration, staged output, or receipt is absent.",
      "receipt")
  .wb_operation_pack_v3_rf_assert_value(write$value, layout)
  value <- list(schema = .wb_operation_pack_v3_rf_domain(
      "observed_relation_family"),
    provisional_grant_identity = .wb_operation_pack_v3_unscoped_identity(
      grant$grant_identity), declaration = layout$declaration,
    seal = layout$seal, sealed_writer_grant = layout$writer,
    observed_key_axis_identity = layout$seal$ordered_key_axis_identity,
    observed_pair_axis_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.row_order.v1", unname(Map(function(key, cell_id)
        list(key = key, cell_id = cell_id),
        write$value$key, write$value$cell_id))),
    observed_row_count = as.integer(length(write$value$key)),
    observed_numeric_fields = layout$seal$numeric_fields,
    output_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
      output$descriptor$observed_descriptor_identity),
    output_content_identity = output$descriptor$content_identity,
    payload_manifest_identity = output$descriptor$payload_manifest_identity,
    validation_status = "passed")
  value <- .wb_operation_pack_v3_rf_id(value, "observation_identity",
    "observed_relation_family", "observation excluding observation_identity")
  list(value)
}

.wb_operation_pack_v3_rf_receipt_audit <- function(receipt, request,
    stage_root = NULL, code = "PYBENCH_RECEIPT_MISMATCH",
    phase = "receipt") {
  grants <- request$sealed_relation_family_grants %||% list()
  observations <- receipt$sealed_relation_family_observations %||% list()
  if (length(grants) != length(observations))
    .wb_operation_pack_v3_error(code,
      "Relation receipt observation is not a bijection with its grant.",
      phase)
  if (!length(grants)) return(invisible(TRUE))
  grant <- grants[[1L]]; item <- observations[[1L]]
  .wb_operation_pack_v3_assert_self_identity(grant,
    "grant_identity", code, phase)
  if (!is.null(grant$known_source_axis))
    .wb_operation_pack_v3_assert_self_identity(grant$known_source_axis,
      "source_axis_identity", code, phase)
  for (part in list(c("declaration", "declaration_identity"),
      c("seal", "seal_identity"),
      c("sealed_writer_grant", "grant_identity")))
    .wb_operation_pack_v3_assert_self_identity(item[[part[[1L]]]],
      part[[2L]], code, phase)
  .wb_operation_pack_v3_assert_self_identity(item,
    "observation_identity", code, phase)
  source <- .wb_operation_pack_v3_rf_axis(grant, request,
    receipt = receipt)
  rows <- item$declaration$ordered_pairs
  chunks <- split(rows, ceiling(seq_along(rows) /
    as.integer(grant$limits$maximum_chunk_pairs)))
  declared_fields <- item$declaration$numeric_fields
  fields <- c(weight = isTRUE(declared_fields$weight),
    value = isTRUE(declared_fields$value),
    distance = isTRUE(declared_fields$distance))
  rebuilt <- tryCatch(.wb_operation_pack_v3_rf_layout(grant, source,
    grant$output_name,
    as.character(unlist(item$declaration$ordered_keys,
      use.names = FALSE)),
    chunks, fields), error = function(error)
      .wb_operation_pack_v3_error(code,
        "Relation receipt declaration is not a valid sealed layout.",
        phase))
  same <- function(a,b) identical(.wb_operation_pack_canonical_json(a),
    .wb_operation_pack_canonical_json(b))
  if (!same(rebuilt$declaration, item$declaration) ||
      !same(rebuilt$seal, item$seal) ||
      !same(rebuilt$writer, item$sealed_writer_grant))
    .wb_operation_pack_v3_error(code,
      "Relation receipt seal does not reconstruct from authenticated source.",
      phase)
  output <- receipt$outputs[[match(grant$output_name,
    vapply(receipt$outputs, function(x) as.character(x$name)[1],
      character(1)))]]
  if (is.null(output) || !identical(item$output_descriptor_identity,
      .wb_operation_pack_v3_unscoped_identity(
        output$descriptor$observed_descriptor_identity)) ||
      !identical(item$output_content_identity,
        output$descriptor$content_identity) ||
      !identical(item$payload_manifest_identity,
        output$descriptor$payload_manifest_identity) ||
      !identical(item$observed_key_axis_identity,
        rebuilt$seal$ordered_key_axis_identity) ||
      !identical(item$observed_pair_axis_identity,
        rebuilt$seal$ordered_pair_axis_identity) ||
      !identical(as.integer(item$observed_row_count),
        as.integer(rebuilt$seal$row_count)) ||
      !same(item$observed_numeric_fields,
        rebuilt$seal$numeric_fields) ||
      !identical(item$validation_status, "passed"))
    .wb_operation_pack_v3_error(code,
      "Relation receipt contradicts its sealed rows or staged output.",
      phase)
  if (!is.null(stage_root)) {
    payload <- file.path(stage_root, "outputs", grant$output_name,
      "payload.rds")
    value <- tryCatch(readRDS(payload), error = identity)
    if (inherits(value, "error"))
      .wb_operation_pack_v3_error(code,
        "Relation staged payload is unreadable.", phase)
    .wb_operation_pack_v3_rf_assert_value(value, rebuilt,
      code = code, phase = phase)
    content <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.relation_family.content.v1", unclass(value))
    payload_id <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.payload_manifest.v2", list(
        path = paste0("outputs/", grant$output_name, "/payload.rds"),
        size = as.numeric(file.info(payload)$size),
        sha256 = .wb_operation_pack_v2_file_sha256(payload)))
    if (!identical(content, item$output_content_identity) ||
        !identical(payload_id, item$payload_manifest_identity))
      .wb_operation_pack_v3_error(code,
        "Relation staged content or payload differs from receipt.", phase)
  }
  invisible(TRUE)
}

.wb_operation_pack_v3_rf_retained_assert_current <- function(bundle,
    request, path) {
  grants <- request$sealed_relation_family_grants %||% list()
  if (!length(grants)) return(invisible(TRUE))
  grant <- grants[[1L]]
  .wb_operation_pack_v3_assert_self_identity(grant,
    "grant_identity", "PYBENCH_REOPEN_VALIDATION_FAILED", "recipient")
  if (identical(grant$source_selector$source, "typed_input_v1")) {
    source <- grant$known_source_axis
    .wb_operation_pack_v3_assert_self_identity(source,
      "source_axis_identity", "PYBENCH_REOPEN_VALIDATION_FAILED",
      "recipient")
    .wb_operation_pack_v3_rf_axis(grant, request)
    cells <- as.character(unlist(source$ordered_cells, use.names = FALSE))
    input <- request$inputs[[match(source$input_name,
      vapply(request$inputs, function(x) as.character(x$name)[1],
        character(1)))]]
    kind <- as.character(input$descriptor$kind)[1]
    source_id <- as.character(source$source_id)[1]
    value <- switch(kind,
      space = wb_prim_space(source_id),
      space_2d = wb_prim_space_2d(source_id),
      matrix = wb_prim_matrix(source_id))
    if (is.null(value)) .wb_operation_pack_v3_error(
      "PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Retained relation typed source cannot be reopened.", "recipient")
    value <- .wb_operation_pack_v2_bind_inputs(bundle,
      list(source = value), cells)[[1L]]
    if (!identical(as.character(value$cell_id), cells) ||
        !identical(.wb_operation_pack_v3_phase5_primitive_identity(
          bundle, value), source$input_content_identity))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Retained relation typed source changed.", "recipient")
  } else {
    g2 <- request$derived_fitted_axis_grants[[1L]]
    .wb_operation_pack_v3_dfa_parent_assert_current(bundle,
      g2$parent_snapshot, phase = "recipient")
  }
  invisible(TRUE)
}

.wb_operation_pack_v3_rf_promoted_assert <- function(bundle,
    staging_bundle, run, output_name, artifact_id) {
  transition <- run$operation_pack_transition %||% NULL
  if (is.null(transition)) return(invisible(TRUE))
  root <- file.path(.wb_operation_pack_v2_store(staging_bundle),
    as.character(transition$transition_id)[1])
  request <- tryCatch(jsonlite::read_json(file.path(root,
    "request.json"), simplifyVector = FALSE), error = identity)
  receipt <- tryCatch(jsonlite::read_json(file.path(root,
    "receipt.json"), simplifyVector = FALSE), error = identity)
  if (inherits(request, "error") || inherits(receipt, "error"))
    .wb_operation_pack_v3_error("PYBENCH_REOPEN_VALIDATION_FAILED",
      "Relation promotion lacks its retained request or receipt.",
      "publication")
  grants <- request$sealed_relation_family_grants %||% list()
  if (!length(grants)) return(invisible(TRUE))
  if (length(grants) != 1L || !identical(grants[[1L]]$output_name,
      output_name) || !isTRUE(.wb_operation_pack_v3_record_validate(
        request, receipt, root, load_payloads = TRUE)$ok))
    .wb_operation_pack_v3_error("PYBENCH_REOPEN_VALIDATION_FAILED",
      "Relation promotion differs from its retained seal.", "publication")
  grant <- grants[[1L]]
  source <- .wb_operation_pack_v3_rf_axis(grant, request,
    receipt = receipt)
  declaration <- receipt$sealed_relation_family_observations[[1L]]$
    declaration
  rows <- declaration$ordered_pairs
  chunks <- split(rows, ceiling(seq_along(rows) /
    as.integer(grant$limits$maximum_chunk_pairs)))
  fields <- c(weight = isTRUE(declaration$numeric_fields$weight),
    value = isTRUE(declaration$numeric_fields$value),
    distance = isTRUE(declaration$numeric_fields$distance))
  layout <- .wb_operation_pack_v3_rf_layout(grant, source,
    output_name, as.character(unlist(declaration$ordered_keys,
      use.names = FALSE)), chunks, fields)
  value <- tryCatch(wb_art_load(bundle, artifact_id,
    expected_kind = "relation_family"), error = identity)
  if (inherits(value, "error"))
    .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
      "Promoted relation artifact cannot be reopened.", "publication")
  .wb_operation_pack_v3_rf_assert_value(value, layout,
    phase = "publication")
  observed <- .wb_operation_pack_v2_identity_plain(
    "scworkbench.relation_family.content.v1", unclass(value))
  expected <- receipt$sealed_relation_family_observations[[1L]]$
    output_content_identity
  if (!identical(observed, expected))
    .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
      "Promoted relation content differs from the sealed payload.",
      "publication")
  invisible(TRUE)
}
