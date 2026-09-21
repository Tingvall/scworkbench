# ABI-v3 G7: authenticated derived cell-output axes.

.wb_operation_pack_v3_g7_id <- function(scheme, scope, value) {
  .wb_operation_pack_v2_identity_scoped(scheme, scope, value)
}

.wb_operation_pack_v3_g7_plain <- function(scheme, value) {
  .wb_operation_pack_v2_identity_plain(scheme, value)
}

.wb_operation_pack_v3_g7_declarations <- function(operation) {
  operation$derived_cell_output_axes %||% list()
}

.wb_operation_pack_v3_g7_linked_map <- function(operation) {
  declarations <- .wb_operation_pack_v3_g7_declarations(operation)
  out <- list()
  for (declaration in declarations) for (item in declaration$linked_outputs) {
    name <- as.character(item$name)[1]
    out[[name]] <- list(declaration = declaration, policy = item)
  }
  out
}

.wb_operation_pack_v3_g7_semantic_validate <- function(operation, inputs,
    outputs, properties, backend) {
  declarations <- .wb_operation_pack_v3_g7_declarations(operation)
  if (!length(declarations)) return(invisible(TRUE))
  opname <- as.character(operation$qualified_name)[1]
  fail <- function(message) .wb_operation_pack_v3_error(
    "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
    paste0("Operation '", opname, "' ", message), "semantic_admission")
  if (!identical(as.character(backend)[1], "R"))
    fail("uses the R-runtime-only derived cell-output-axis capability.")
  if (length(declarations) > 4L) fail(
    "declares more than four derived cell-output axes.")
  names_in <- vapply(declarations, function(x) as.character(x$name)[1],
    character(1))
  if (any(!nzchar(names_in)) || anyDuplicated(names_in))
    fail("has duplicate or empty derived-axis names.")
  all_linked <- character()
  for (declaration in declarations) {
    .wb_operation_pack_v3_assert_self_identity(declaration,
      "declaration_identity", "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
      "semantic_admission")
    mode <- as.character(declaration$derivation_mode)[1]
    source <- declaration$source
    source_mode <- as.character(source$mode)[1]
    linked <- declaration$linked_outputs %||% list()
    limits <- declaration$limits
    linked_names <- vapply(linked, function(x) as.character(x$name)[1],
      character(1))
    if (!mode %in% c("ordered_unique_subset_v1",
        "declared_ordered_unique_union_v1") ||
        !source_mode %in% c("static_input_axis",
          "g4_collection_member_axis") ||
        (mode == "ordered_unique_subset_v1" &&
          source_mode != "static_input_axis") ||
        (mode == "declared_ordered_unique_union_v1" &&
          source_mode != "g4_collection_member_axis") ||
        !length(linked) || length(linked) > 16L || anyDuplicated(linked_names) ||
        as.integer(limits$minimum_cells) < 1L ||
        as.integer(limits$minimum_cells) > as.integer(limits$maximum_cells) ||
        as.integer(limits$maximum_cells) > 10000000L ||
        as.integer(limits$maximum_source_axes) < 1L ||
        as.integer(limits$maximum_source_axes) > 64L ||
        (mode == "ordered_unique_subset_v1" &&
          as.integer(limits$maximum_source_axes) != 1L) ||
        as.integer(limits$maximum_source_memberships) < 1L ||
        as.integer(limits$maximum_source_memberships) > 20000000L ||
        as.integer(limits$maximum_linked_outputs) < length(linked) ||
        as.integer(limits$maximum_linked_outputs) > 16L)
      fail("has an invalid derived-axis mode, source, or resource limit.")
    projection <- as.character(source$projection)[1]
    selector <- source$family_key_selector %||% NULL
    if (!projection %in% c("cell_vector_axis_v1",
        "family_key_cell_axis_v1") ||
        identical(projection, "cell_vector_axis_v1") != is.null(selector))
      fail("has an invalid logical source-axis projection.")
    if (source_mode == "static_input_axis") {
      input <- inputs[[as.character(source$input)[1]]]
      expected_kind <- if (projection == "cell_vector_axis_v1")
        "cell_vector" else "cell_vector_family"
      if (is.null(input) || !isTRUE(input$required) ||
          !identical(as.character(input$kind)[1], expected_kind))
        fail("has an invalid required static source input.")
    } else {
      collections <- stats::setNames(operation$artifact_collection_reads %||%
        list(), vapply(operation$artifact_collection_reads %||% list(),
          function(x) as.character(x$name)[1], character(1)))
      collection <- collections[[as.character(source$collection)[1]]]
      slots <- if (is.null(collection)) list() else stats::setNames(
        collection$reference_slots, vapply(collection$reference_slots,
          function(x) as.character(x$slot)[1], character(1)))
      slot <- slots[[as.character(source$slot)[1]]]
      expected_kind <- if (projection == "cell_vector_axis_v1")
        "cell_vector" else "cell_vector_family"
      if (is.null(collection) || is.null(slot) ||
          !expected_kind %in% as.character(unlist(slot$allowed_kinds,
            use.names = FALSE)))
        fail("has an invalid retained-artifact collection source.")
    }
    groups <- character()
    for (item in linked) {
      name <- as.character(item$name)[1]
      output <- outputs[[name]]
      kind <- as.character(output$kind %||% "")[1]
      shape <- as.character(item$shape)[1]
      valid_shape <- (kind == "cell_vector" && shape == "one_per_cell" &&
          identical(as.character(item$row_order)[1],
            "sealed_cell_axis_order_v1") && is.null(item$key_axis)) ||
        (kind == "cell_vector_family" && shape %in% c(
            "cell_key_cartesian", "bounded_grouped_cell_key_cartesian") &&
          identical(as.character(item$row_order)[1],
            "key_major_then_sealed_cell_v1") && !is.null(item$key_axis))
      if (is.null(output) || !isTRUE(output$required) ||
          !identical(as.character(output$category)[1], "terminal_artifact") ||
          !kind %in% c("cell_vector", "cell_vector_family") || !valid_shape)
        fail(paste0("links an invalid output '", name, "'."))
      groups <- c(groups, as.character(output$promotion_group)[1])
    }
    if (length(unique(groups)) != 1L)
      fail("links outputs from different promotion groups.")
    all_linked <- c(all_linked, linked_names)
  }
  if (length(all_linked) > 32L || anyDuplicated(all_linked))
    fail("links an output more than once or exceeds the operation ceiling.")
  invisible(TRUE)
}

.wb_operation_pack_v3_g7_resolve_selector <- function(selector, params,
    item = NULL, descriptor_identity) {
  mode <- as.character(selector$mode)[1]
  resolved <- switch(mode,
    literal = as.character(selector$key)[1],
    operation_parameter = as.character(params[[as.character(
      selector$parameter)[1]]] %||% "")[1],
    collection_item_field = as.character(item[[as.character(
      selector$field)[1]]] %||% "")[1],
    parameter_prefix_plus_literal_suffix = paste0(as.character(params[[
      as.character(selector$prefix_parameter)[1]]] %||% "")[1],
      as.character(selector$literal_suffix)[1]),
    "")
  if (!nzchar(resolved)) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "Derived-axis family-key selector resolved to an empty key.",
    "resolution")
  source <- switch(mode,
    literal = list(key = as.character(selector$key)[1]),
    operation_parameter = list(parameter = as.character(
      selector$parameter)[1], value = resolved),
    collection_item_field = list(field = as.character(selector$field)[1],
      value = resolved),
    parameter_prefix_plus_literal_suffix = list(prefix_parameter =
      as.character(selector$prefix_parameter)[1], prefix_value =
      as.character(params[[as.character(selector$prefix_parameter)[1]]] %||%
        "")[1], literal_suffix = as.character(selector$literal_suffix)[1]),
    list())
  value <- list(primitive_descriptor_identity =
      .wb_operation_pack_v3_unscoped_identity(descriptor_identity),
    projection = "family_key_cell_axis_v1", selector_mode = mode,
    selector_source = source, resolved_key = resolved)
  value$source_axis_selector_identity <- .wb_operation_pack_v3_g7_id(
    "scworkbench.operation_pack.derived_cell_axis_selector.v1",
    "derived cell axis selector excluding source_axis_selector_identity",
    value)
  value
}

.wb_operation_pack_v3_g7_project_cells <- function(value, projection,
    selector_record = NULL) {
  kind <- as.character(value$kind %||% "")[1]
  if (identical(projection, "cell_vector_axis_v1")) {
    if (!identical(kind, "cell_vector")) .wb_operation_pack_v3_error(
      "PYBENCH_CAPABILITY_MISMATCH",
      "Derived-axis source is not a cell_vector.", "resolution")
    cells <- as.character(value$cell_id %||% character())
  } else {
    if (!identical(kind, "cell_vector_family") || is.null(selector_record))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Derived-axis family source or selector is invalid.", "resolution")
    keys <- as.character(value$key %||% character())
    cell_id <- as.character(value$cell_id %||% character())
    cells <- cell_id[keys == selector_record$resolved_key]
  }
  if (!length(cells) || anyNA(cells) || any(!nzchar(cells)) ||
      anyDuplicated(cells)) .wb_operation_pack_v3_error(
        "PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Derived-axis logical source cells must be nonempty, unique, and ordered.",
        "resolution")
  cells
}

.wb_operation_pack_v3_g7_source_reference <- function(source, value,
    descriptor_identity, params, item = NULL, collection = NULL,
    collection_item = NULL, reference = NULL) {
  projection <- as.character(source$projection)[1]
  selector <- if (identical(projection, "family_key_cell_axis_v1"))
    .wb_operation_pack_v3_g7_resolve_selector(source$family_key_selector,
      params, item, descriptor_identity) else NULL
  cells <- .wb_operation_pack_v3_g7_project_cells(value, projection, selector)
  order_id <- .wb_operation_pack_v3_g7_plain(
    "scworkbench.cell_order.v1", unname(as.list(cells)))
  if (identical(as.character(source$mode)[1], "static_input_axis")) {
    record <- list(source_mode = "static_input_axis",
      input_name = as.character(source$input)[1],
      input_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
        descriptor_identity),
      primitive_kind = as.character(value$kind)[1], projection = projection,
      source_axis_selector_identity = if (is.null(selector)) NULL else
        .wb_operation_pack_v3_unscoped_identity(
          selector$source_axis_selector_identity),
      source_cell_count = as.integer(length(cells)),
      source_cell_order_identity = order_id)
  } else {
    record <- list(source_mode = "g4_collection_member_axis",
      collection_name = as.character(source$collection)[1],
      collection_identity = collection$collection_identity,
      resolved_ordinal = as.integer(collection_item$resolved_ordinal),
      item_identity = collection_item$item_identity,
      slot_name = as.character(source$slot)[1],
      slot_reference_identity = reference$reference_identity,
      primitive_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
        descriptor_identity),
      primitive_kind = as.character(value$kind)[1], projection = projection,
      source_axis_selector_identity = if (is.null(selector)) NULL else
        .wb_operation_pack_v3_unscoped_identity(
          selector$source_axis_selector_identity),
      source_cell_count = as.integer(length(cells)),
      source_cell_order_identity = order_id)
  }
  record$source_axis_reference_identity <- .wb_operation_pack_v3_g7_id(
    "scworkbench.operation_pack.derived_cell_source_axis_reference.v1",
    "derived cell source axis reference excluding source_axis_reference_identity",
    record)
  list(record = record, cells = cells, selector = selector)
}

.wb_operation_pack_v3_g7_key_axis <- function(spec, inputs, params,
    input_records) {
  source <- as.character(spec$source)[1]
  state <- if (identical(source, "resolved_parameter_feature_groups_v1"))
    .wb_operation_pack_v3_parameter_key_axis(spec, inputs, params,
      input_records) else if (identical(source,
      "declared_keys_with_optional_prefix_v1"))
        .wb_operation_pack_v3_declared_prefix_key_axis(spec, params) else if (
          identical(source, "input_keys_with_optional_selector_v1"))
        .wb_operation_pack_v3_input_key_axis(spec, inputs, params,
          input_records) else if (identical(source,
            "declared_bounded_key_groups_v1")) list(keys = character(),
              resolution = list(source = source,
                required_keys = spec$required_keys,
                optional_groups = spec$optional_groups,
                selection_owner = spec$selection_owner,
                group_order = spec$group_order)) else
          .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
            "Unknown G7 family-key axis policy.", "resolution")
  resolution <- list(declaration = spec,
    keys = unname(as.list(state$keys)), resolution = state$resolution)
  identity <- .wb_operation_pack_v3_g7_plain(
    "scworkbench.operation_pack.resolved_key_axis_policy.v1", resolution)
  list(keys = state$keys, resolution = resolution,
    identity = identity)
}

.wb_operation_pack_v3_g7_output_policy <- function(declaration, item,
    inputs, params, input_records) {
  key <- if (is.null(item$key_axis)) NULL else
    .wb_operation_pack_v3_g7_key_axis(item$key_axis, inputs, params,
      input_records)
  list(schema = "scworkbench.operation_pack.derived_cell_linked_output_policy.v1",
    manifest_declaration_identity = .wb_operation_pack_v3_unscoped_identity(
      declaration$declaration_identity), derived_axis_name = declaration$name,
    shape = item$shape, row_order = item$row_order,
    missing_values = item$missing_values,
    resolved_key_axis_policy_identity_or_null = if (is.null(key)) NULL else
      key$identity,
    resolved_key_axis = if (is.null(key)) NULL else key$resolution,
    resolved_keys = if (is.null(key)) NULL else unname(as.list(key$keys)))
}

.wb_operation_pack_v3_g7_prepare <- function(operation, inputs, input_records,
    params, artifact_collections, output_records) {
  declarations <- .wb_operation_pack_v3_g7_declarations(operation)
  if (!length(declarations)) return(list(grants = list(), state = list()))
  collection_declarations <- stats::setNames(
    operation$artifact_collection_reads %||% list(), vapply(
      operation$artifact_collection_reads %||% list(), `[[`, character(1),
      "name"))
  grants <- list(); states <- list()
  for (declaration in declarations) {
    source <- declaration$source
    mode <- as.character(declaration$derivation_mode)[1]
    references <- list(); cells <- list(); selectors <- list()
    if (identical(as.character(source$mode)[1], "static_input_axis")) {
      input_name <- as.character(source$input)[1]
      built <- .wb_operation_pack_v3_g7_source_reference(source,
        inputs[[input_name]], input_records[[input_name]]$descriptor_identity,
        params)
      references <- list(built$record); cells <- list(built$cells)
      selectors <- list(built$selector)
    } else {
      collection_name <- as.character(source$collection)[1]
      collection <- artifact_collections$grants[[collection_name]]
      values <- artifact_collections$values[[collection_name]]
      collection_declaration <- collection_declarations[[collection_name]]
      raw <- params[[as.character(collection_declaration$parameter)[1]]]
      slot_name <- as.character(source$slot)[1]
      if (length(collection$items) > as.integer(
          declaration$limits$maximum_source_axes))
        .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
          "Derived-axis source count exceeds its authenticated limit.",
          "resolution")
      for (i in seq_along(collection$items)) {
        item <- collection$items[[i]]
        reference <- Filter(function(x) identical(as.character(x$slot)[1],
          slot_name), item$references)
        if (length(reference) != 1L) .wb_operation_pack_v3_error(
          "PYBENCH_INPUT_IDENTITY_MISMATCH",
          "Derived-axis collection member lacks its exact source slot.",
          "resolution")
        value <- values[[i]][[slot_name]]
        descriptor <- .wb_operation_pack_v2_input_descriptor(slot_name,
          value, list(name = slot_name, kind = value$kind, required = TRUE,
            alignment = "none"))$descriptor
        built <- .wb_operation_pack_v3_g7_source_reference(source, value,
          descriptor$descriptor_identity, params,
          raw[[item$parameter_ordinal]], collection, item, reference[[1]])
        references[[i]] <- built$record; cells[[i]] <- built$cells
        selectors[[i]] <- built$selector
      }
    }
    memberships <- sum(lengths(cells))
    if (!length(references) || memberships > as.integer(
        declaration$limits$maximum_source_memberships))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Derived-axis source memberships exceed the authenticated limit.",
        "resolution")
    aggregate <- list(derivation_mode = mode,
      source_axis_count = as.integer(length(references)),
      source_membership_count = as.integer(memberships),
      ordered_source_axis_reference_identities = lapply(references,
        function(x) .wb_operation_pack_v3_unscoped_identity(
          x$source_axis_reference_identity)))
    aggregate$source_axis_aggregate_identity <-
      .wb_operation_pack_v3_g7_id(
        "scworkbench.operation_pack.derived_cell_source_axis_aggregate.v1",
        "derived cell source axis aggregate excluding source_axis_aggregate_identity",
        aggregate)
    closure <- lapply(declaration$linked_outputs, function(item) {
      output <- output_records[[as.character(item$name)[1]]]
      policy <- output$descriptor$derived_cell_output_axis_policy
      list(name = output$name, allocated_id = output$allocated_id,
        kind = output$descriptor$kind,
        ordinary_output_grant_identity =
          .wb_operation_pack_v3_unscoped_identity(
            output$descriptor$grant_identity), shape = policy$shape,
        row_order = policy$row_order, missing_values = policy$missing_values,
        resolved_key_axis_policy_identity_or_null =
          policy$resolved_key_axis_policy_identity_or_null,
        promotion_group = operation$outputs[[match(output$name, vapply(
          operation$outputs, `[[`, character(1), "name"))]]$promotion_group)
    })
    linked_closure <- list(manifest_declaration_identity =
        .wb_operation_pack_v3_unscoped_identity(
          declaration$declaration_identity), linked_outputs = closure,
      closure_policy = declaration$closure_policy)
    linked_closure$linked_output_closure_identity <-
      .wb_operation_pack_v3_g7_id(
        "scworkbench.operation_pack.derived_cell_linked_output_closure.v1",
        "linked output closure excluding linked_output_closure_identity",
        linked_closure)
    grant <- list(schema =
        "scworkbench.operation_pack.authenticated_derived_cell_output_axis_grant.v1",
      name = declaration$name, derivation_mode = mode,
      manifest_declaration_identity = .wb_operation_pack_v3_unscoped_identity(
        declaration$declaration_identity), source_axes = references,
      source_axis_aggregate = aggregate, linked_output_closure = linked_closure,
      limits = declaration$limits, call_discipline = declaration$call_discipline,
      closure_policy = declaration$closure_policy)
    grant$grant_identity <- .wb_operation_pack_v3_g7_id(
      grant$schema, "grant excluding grant_identity", grant)
    grants[[declaration$name]] <- grant
    states[[declaration$name]] <- list(cells = cells, selectors = selectors,
      references = references)
  }
  list(grants = grants, state = states)
}

#' Declare a derived cell-output axis
#'
#' Constructs the closed transient declaration consumed by the ABI-v3 G7
#' capability. The declaration carries values only; core validates and seals
#' the authoritative axis before any linked output is admitted.
#'
#' @param grant One authenticated derived-axis grant supplied in the runner
#'   context.
#' @param final_cell_ids Ordered unique final cell identifiers.
#' @param member_selections For union mode, one selection per authenticated
#'   source axis in resolved ordinal order. Each element may be a character
#'   vector or a record containing `selected_cell_ids`.
#' @return A closed transient declaration record.
#' @export
wb_derived_cell_output_axis_declaration <- function(grant, final_cell_ids,
    member_selections = NULL) {
  .wb_operation_pack_assert(is.list(grant) && identical(
    as.character(grant$schema %||% "")[1],
    "scworkbench.operation_pack.authenticated_derived_cell_output_axis_grant.v1"),
    "OPERATION_PACK_DERIVED_AXIS_DECLARATION_INVALID",
    "grant must be an authenticated derived cell-output-axis grant.")
  final <- as.character(final_cell_ids)
  mode <- as.character(grant$derivation_mode)[1]
  members <- NULL
  if (identical(mode, "declared_ordered_unique_union_v1")) {
    .wb_operation_pack_assert(is.list(member_selections),
      "OPERATION_PACK_DERIVED_AXIS_DECLARATION_INVALID",
      "Union declarations require ordered member selections.")
    members <- lapply(seq_along(member_selections), function(i) {
      value <- member_selections[[i]]
      selected <- if (is.list(value) && !is.null(value$selected_cell_ids))
        value$selected_cell_ids else value
      reference <- grant$source_axes[[i]] %||% list()
      list(source_axis_reference_identity =
          .wb_operation_pack_v3_unscoped_identity(
            reference$source_axis_reference_identity),
        resolved_ordinal = as.integer(reference$resolved_ordinal),
        selected_cell_ids = unname(as.list(as.character(selected))))
    })
  }
  value <- list(schema =
      "scworkbench.operation_pack.derived_cell_output_axis_declaration.v1",
    grant_identity = .wb_operation_pack_v3_unscoped_identity(
      grant$grant_identity), derivation_mode = mode,
    member_selections = members,
    final_cell_ids = unname(as.list(final)))
  if (identical(mode, "ordered_unique_subset_v1"))
    value$member_selections <- NULL
  value$pack_declaration_identity <- .wb_operation_pack_v3_g7_id(
    value$schema,
    "derived cell output axis declaration excluding pack_declaration_identity",
    value)
  value
}

.wb_operation_pack_v3_g7_ordered_subset <- function(selected, source,
    allow_empty = FALSE) {
  selected <- as.character(selected); source <- as.character(source)
  (allow_empty || length(selected) > 0L) && !anyNA(selected) &&
    !any(!nzchar(selected)) && !anyDuplicated(selected) &&
    !length(setdiff(selected, source)) &&
    identical(selected, source[source %in% selected])
}

.wb_operation_pack_v3_g7_seal <- function(request, declarations) {
  grants <- request$derived_cell_output_axis_grants %||% list()
  states <- attr(request, "operation_pack_v3_derived_axis_state") %||% list()
  declarations <- declarations %||% list()
  if (length(grants) != length(declarations)) .wb_operation_pack_v3_error(
    "PYBENCH_OUTPUT_INVALID",
    "Derived-axis declarations are not an exact bijection with grants.",
    "audit")
  sealed <- list()
  for (i in seq_along(grants)) {
    grant <- grants[[i]]; candidate <- declarations[[i]]
    .wb_operation_pack_v3_assert_self_identity(candidate,
      "pack_declaration_identity", "PYBENCH_OUTPUT_INVALID", "audit")
    mode <- as.character(grant$derivation_mode)[1]
    if (!identical(candidate$grant_identity,
        .wb_operation_pack_v3_unscoped_identity(grant$grant_identity)) ||
        !identical(as.character(candidate$derivation_mode)[1], mode))
      .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
        "Derived-axis declaration substitutes a grant or derivation mode.",
        "audit")
    private <- states[[as.character(grant$name)[1]]]
    final <- as.character(unlist(candidate$final_cell_ids,
      use.names = FALSE))
    minimum <- as.integer(grant$limits$minimum_cells)
    maximum <- as.integer(grant$limits$maximum_cells)
    if (length(final) < minimum || length(final) > maximum || anyNA(final) ||
        any(!nzchar(final)) || anyDuplicated(final))
      .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
        "Derived final axis violates uniqueness, validity, or bounds.", "audit")
    final_order <- .wb_operation_pack_v3_g7_plain(
      "scworkbench.cell_order.v1", unname(as.list(final)))
    if (identical(mode, "ordered_unique_subset_v1")) {
      if (!is.null(candidate$member_selections) ||
          !.wb_operation_pack_v3_g7_ordered_subset(final,
            private$cells[[1]])) .wb_operation_pack_v3_error(
              "PYBENCH_OUTPUT_INVALID",
              "Derived subset is foreign, duplicate, empty, or reordered.",
              "audit")
      evidence <- list(source_ordered_subset_status = "passed",
        selected_count = as.integer(length(final)))
      selected_orders <- list(final_order)
      aggregate_selected <- length(final); overlap <- 0L
    } else {
      members <- candidate$member_selections %||% list()
      if (length(members) != length(private$cells))
        .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
          "Union declaration has missing or extra member selections.", "audit")
      selected <- list(); selected_orders <- list()
      for (j in seq_along(members)) {
        member <- members[[j]]; reference <- grant$source_axes[[j]]
        ids <- as.character(unlist(member$selected_cell_ids,
          use.names = FALSE))
        if (!identical(member$source_axis_reference_identity,
              .wb_operation_pack_v3_unscoped_identity(
                reference$source_axis_reference_identity)) ||
            !identical(as.integer(member$resolved_ordinal),
              as.integer(reference$resolved_ordinal)) ||
            !.wb_operation_pack_v3_g7_ordered_subset(ids,
              private$cells[[j]], allow_empty = TRUE))
          .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
            "Union member selection is foreign, duplicate, reordered, or cross-bound.",
            "audit")
        selected[[j]] <- ids
        selected_orders[[j]] <- .wb_operation_pack_v3_g7_plain(
          "scworkbench.cell_order.v1", unname(as.list(ids)))
      }
      flat <- unlist(selected, use.names = FALSE)
      membership <- unique(flat)
      if (!length(flat) || !setequal(final, membership))
        .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
          "Declared final axis is not the exact selected union membership.",
          "audit")
      aggregate_selected <- length(flat); overlap <- length(flat) - length(membership)
      evidence <- list(member_subset_status = "passed",
        union_membership_equality_status = "passed",
        distinct_selected_membership_count = as.integer(length(membership)),
        aggregate_selected_count = as.integer(aggregate_selected),
        overlap_collapse_count = as.integer(overlap))
    }
    derivation <- c(list(pack_declaration_identity =
        .wb_operation_pack_v3_unscoped_identity(
          candidate$pack_declaration_identity),
      grant_identity = .wb_operation_pack_v3_unscoped_identity(
        grant$grant_identity), derivation_mode = mode,
      selected_axis_order_identities = selected_orders,
      final_cell_count = as.integer(length(final)),
      final_cell_order_identity = final_order), evidence)
    derivation$derivation_identity <- .wb_operation_pack_v3_g7_id(
      "scworkbench.operation_pack.derived_cell_axis_derivation.v1",
      "derived cell axis derivation excluding derivation_identity", derivation)
    seal <- list(schema =
        "scworkbench.operation_pack.sealed_derived_cell_axis.v1",
      grant_identity = .wb_operation_pack_v3_unscoped_identity(
        grant$grant_identity), pack_declaration_identity =
        .wb_operation_pack_v3_unscoped_identity(
          candidate$pack_declaration_identity),
      derivation_identity = .wb_operation_pack_v3_unscoped_identity(
        derivation$derivation_identity),
      source_axis_aggregate_identity = .wb_operation_pack_v3_unscoped_identity(
        grant$source_axis_aggregate$source_axis_aggregate_identity),
      linked_output_closure_identity = .wb_operation_pack_v3_unscoped_identity(
        grant$linked_output_closure$linked_output_closure_identity),
      final_cell_count = as.integer(length(final)),
      final_cell_order_identity = final_order, status = "sealed")
    seal$sealed_axis_identity <- .wb_operation_pack_v3_g7_id(
      seal$schema, "sealed axis excluding sealed_axis_identity", seal)
    sealed[[as.character(grant$name)[1]]] <- list(grant = grant,
      declaration = candidate, derivation = derivation, seal = seal,
      cells = final, aggregate_selected_count = as.integer(aggregate_selected),
      overlap_collapse_count = as.integer(overlap))
  }
  sealed
}

.wb_operation_pack_v3_g7_sealed_cardinality <- function(output, sealed) {
  policy <- output$descriptor$derived_cell_output_axis_policy
  cells <- sealed$cells; shape <- as.character(policy$shape)[1]
  keys <- as.character(unlist(policy$resolved_keys %||% list(),
    use.names = FALSE))
  bounded <- identical(shape, "bounded_grouped_cell_key_cartesian")
  grant <- list(schema =
      "scworkbench.operation_pack.sealed_output_cardinality_grant.v1",
    ordinary_output_grant_identity = .wb_operation_pack_v3_unscoped_identity(
      output$descriptor$grant_identity),
    manifest_declaration_identity = sealed$grant$manifest_declaration_identity,
    pack_declaration_identity = .wb_operation_pack_v3_unscoped_identity(
      sealed$declaration$pack_declaration_identity),
    derived_axis_grant_identity = .wb_operation_pack_v3_unscoped_identity(
      sealed$grant$grant_identity),
    sealed_axis_identity = .wb_operation_pack_v3_unscoped_identity(
      sealed$seal$sealed_axis_identity), output = output$name,
    kind = output$descriptor$kind, shape = shape,
    row_order = policy$row_order, missing_values = policy$missing_values,
    resolved_key_axis_policy_identity_or_null =
      policy$resolved_key_axis_policy_identity_or_null,
    cell_axis_count = as.integer(length(cells)),
    cell_axis_order_identity = sealed$seal$final_cell_order_identity)
  if (shape == "one_per_cell") {
    grant$expected_dimensions <- list(as.integer(length(cells)))
    grant$expected_row_count <- as.integer(length(cells))
    grant$row_order_identity <- .wb_operation_pack_v3_g7_plain(
      "scworkbench.row_order.v1", unname(as.list(cells)))
  } else if (bounded) {
    resolution <- policy$resolved_key_axis$resolution
    required <- as.character(unlist(resolution$required_keys,
      use.names = FALSE)); optional <- unlist(lapply(
        resolution$optional_groups, function(x) as.character(unlist(x$keys,
          use.names = FALSE))), use.names = FALSE)
    grant$minimum_key_count <- as.integer(length(required))
    grant$maximum_key_count <- as.integer(length(c(required, optional)))
    grant$minimum_row_count <- as.integer(length(required) * length(cells))
    grant$maximum_row_count <- as.integer(length(c(required, optional)) *
      length(cells))
    grant$expected_dimensions <- list(0L, 3L)
    grant$key_axis_resolution <- policy$resolved_key_axis
  } else {
    pairs <- unlist(lapply(keys, function(key) lapply(cells,
      function(cell) list(key = key, cell_id = cell))), recursive = FALSE)
    grant$key_axis_count <- as.integer(length(keys))
    grant$key_axis <- unname(as.list(keys))
    grant$key_axis_resolution <- policy$resolved_key_axis
    grant$key_axis_order_identity <- .wb_operation_pack_v3_g7_plain(
      "scworkbench.row_order.v1", unname(as.list(keys)))
    grant$expected_row_count <- as.integer(length(cells) * length(keys))
    grant$expected_dimensions <- list(grant$expected_row_count, 3L)
    grant$row_order_identity <- .wb_operation_pack_v3_g7_plain(
      "scworkbench.row_order.v1", pairs)
  }
  grant$sealed_cardinality_grant_identity <- .wb_operation_pack_v3_g7_id(
    grant$schema, "grant excluding sealed_cardinality_grant_identity", grant)
  attr(grant, "operation_pack_v3_cells") <- cells
  grant
}

.wb_operation_pack_v3_g7_observe_cardinality <- function(value, grant) {
  ordinary <- grant
  ordinary$schema <- "scworkbench.operation_pack.output_cardinality_grant.v1"
  ordinary$cardinality_grant_identity <- grant$
    sealed_cardinality_grant_identity
  observed <- .wb_operation_pack_v3_observe_cardinality(value, ordinary)
  observed$schema <-
    "scworkbench.operation_pack.observed_sealed_output_cardinality.v1"
  observed$sealed_cardinality_grant_identity <-
    observed$cardinality_grant_identity
  observed$cardinality_grant_identity <- NULL
  observed$sealed_axis_identity <- grant$sealed_axis_identity
  observed$observed_cardinality_identity <- NULL
  observed$observed_sealed_cardinality_identity <-
    .wb_operation_pack_v3_g7_id(observed$schema,
      "observation excluding observed_sealed_cardinality_identity", observed)
  observed
}

.wb_operation_pack_v3_g7_apply_outputs <- function(request, observed, writes,
    sealed) {
  if (!length(sealed)) return(list(observed = observed, observations = list()))
  observed_names <- vapply(observed, `[[`, character(1), "name")
  request_outputs <- stats::setNames(request$outputs, vapply(request$outputs,
    `[[`, character(1), "name"))
  observations <- list()
  for (axis_name in names(sealed)) {
    state <- sealed[[axis_name]]; linked <- state$grant$linked_output_closure$
      linked_outputs
    linked_receipts <- list()
    for (j in seq_along(linked)) {
      name <- as.character(linked[[j]]$name)[1]
      index <- match(name, observed_names)
      if (is.na(index) || is.null(writes[[name]]))
        .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
          "A sealed derived axis is missing a linked output.", "audit")
      sealed_grant <- .wb_operation_pack_v3_g7_sealed_cardinality(
        request_outputs[[name]], state)
      cardinality <- .wb_operation_pack_v3_g7_observe_cardinality(
        writes[[name]]$value, sealed_grant)
      descriptor <- observed[[index]]$descriptor
      descriptor$sealed_axis_identity <-
        .wb_operation_pack_v3_unscoped_identity(
          state$seal$sealed_axis_identity)
      descriptor$sealed_output_cardinality_grant <- sealed_grant
      descriptor$observed_sealed_output_cardinality <- cardinality
      descriptor$dimensions <- unname(as.list(
        .wb_operation_pack_v2_dimensions(writes[[name]]$value,
          descriptor$kind)))
      descriptor$observed_descriptor_identity <- NULL
      descriptor$observed_descriptor_identity <- .wb_operation_pack_v3_g7_id(
        "scworkbench.operation_pack.observed_output.v3",
        "descriptor excluding observed_descriptor_identity", descriptor)
      observed[[index]]$descriptor <- descriptor
      linked_receipts[[j]] <- list(name = name,
        ordinary_output_grant_identity = linked[[j]]$
          ordinary_output_grant_identity,
        sealed_cardinality_observation_identity =
          .wb_operation_pack_v3_unscoped_identity(
            cardinality$observed_sealed_cardinality_identity),
        observed_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
          descriptor$observed_descriptor_identity),
        content_identity = descriptor$content_identity,
        observed_sealed_cell_axis_identity = descriptor$sealed_axis_identity)
    }
    observation <- list(schema =
        "scworkbench.operation_pack.derived_cell_output_axis_observation.v1",
      grant_identity = .wb_operation_pack_v3_unscoped_identity(
        state$grant$grant_identity), source_axis_aggregate_identity =
        .wb_operation_pack_v3_unscoped_identity(state$grant$
          source_axis_aggregate$source_axis_aggregate_identity),
      pack_declaration_identity = .wb_operation_pack_v3_unscoped_identity(
        state$declaration$pack_declaration_identity),
      derivation_identity = .wb_operation_pack_v3_unscoped_identity(
        state$derivation$derivation_identity),
      sealed_axis_identity = .wb_operation_pack_v3_unscoped_identity(
        state$seal$sealed_axis_identity), declaration_count = 1L,
      seal_status = "sealed", derivation_mode = state$grant$derivation_mode,
      source_axis_count = state$grant$source_axis_aggregate$source_axis_count,
      source_membership_count =
        state$grant$source_axis_aggregate$source_membership_count,
      aggregate_selected_count = state$aggregate_selected_count,
      overlap_collapse_count = state$overlap_collapse_count,
      final_cell_count = state$seal$final_cell_count,
      final_cell_order_identity = state$seal$final_cell_order_identity,
      linked_output_closure_identity = .wb_operation_pack_v3_unscoped_identity(
        state$grant$linked_output_closure$linked_output_closure_identity),
      linked_outputs = linked_receipts,
      exact_linked_output_coverage = "passed",
      semantic_validation = "passed")
    observation$observation_identity <- .wb_operation_pack_v3_g7_id(
      observation$schema, "observation excluding observation_identity",
      observation)
    observations[[axis_name]] <- observation
  }
  list(observed = observed, observations = unname(observations))
}

.wb_operation_pack_v3_g7_request_audit <- function(request) {
  grants <- request$derived_cell_output_axis_grants %||% list()
  for (grant in grants) {
    for (source in grant$source_axes)
      .wb_operation_pack_v3_assert_self_identity(source,
        "source_axis_reference_identity", "PYBENCH_CAPABILITY_MISMATCH",
        "staging")
    .wb_operation_pack_v3_assert_self_identity(grant$source_axis_aggregate,
      "source_axis_aggregate_identity", "PYBENCH_CAPABILITY_MISMATCH",
      "staging")
    .wb_operation_pack_v3_assert_self_identity(grant$linked_output_closure,
      "linked_output_closure_identity", "PYBENCH_CAPABILITY_MISMATCH",
      "staging")
    .wb_operation_pack_v3_assert_self_identity(grant, "grant_identity",
      "PYBENCH_CAPABILITY_MISMATCH", "staging")
  }
  expected <- lapply(grants, function(x)
    .wb_operation_pack_v3_unscoped_identity(x$grant_identity))
  if (!identical(request$execution_capability$
      derived_cell_output_axis_grant_identities %||% list(), expected))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Derived-axis capability closure differs from request grants.",
      "staging")
  invisible(TRUE)
}

.wb_operation_pack_v3_g7_receipt_audit <- function(receipt, request) {
  grants <- request$derived_cell_output_axis_grants %||% list()
  observations <- receipt$derived_cell_output_axis_observations %||% list()
  if (length(grants) != length(observations)) .wb_operation_pack_v3_error(
    "PYBENCH_RECEIPT_MISMATCH",
    "Derived-axis observations are not a bijection with grants.", "receipt")
  observed <- stats::setNames(c(receipt$outputs %||% list(),
    receipt$registry_requests %||% list()), vapply(c(receipt$outputs %||%
      list(), receipt$registry_requests %||% list()), `[[`, character(1),
      "name"))
  for (i in seq_along(grants)) {
    grant <- grants[[i]]; observation <- observations[[i]]
    .wb_operation_pack_v3_assert_self_identity(observation,
      "observation_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
    linked <- grant$linked_output_closure$linked_outputs
    source <- grant$source_axis_aggregate
    expected_seal <- list(schema =
        "scworkbench.operation_pack.sealed_derived_cell_axis.v1",
      grant_identity = .wb_operation_pack_v3_unscoped_identity(
        grant$grant_identity),
      pack_declaration_identity = observation$pack_declaration_identity,
      derivation_identity = observation$derivation_identity,
      source_axis_aggregate_identity =
        .wb_operation_pack_v3_unscoped_identity(
          source$source_axis_aggregate_identity),
      linked_output_closure_identity =
        .wb_operation_pack_v3_unscoped_identity(
          grant$linked_output_closure$linked_output_closure_identity),
      final_cell_count = observation$final_cell_count,
      final_cell_order_identity = observation$final_cell_order_identity,
      status = "sealed")
    expected_seal$sealed_axis_identity <- .wb_operation_pack_v3_g7_id(
      expected_seal$schema, "sealed axis excluding sealed_axis_identity",
      expected_seal)
    counts_consistent <- if (identical(grant$derivation_mode,
        "ordered_unique_subset_v1"))
      identical(observation$aggregate_selected_count,
        observation$final_cell_count) &&
        identical(observation$overlap_collapse_count, 0L) else
      observation$aggregate_selected_count -
        observation$overlap_collapse_count ==
          observation$final_cell_count
    if (!identical(observation$grant_identity,
        .wb_operation_pack_v3_unscoped_identity(grant$grant_identity)) ||
        !identical(observation$source_axis_aggregate_identity,
          expected_seal$source_axis_aggregate_identity) ||
        !identical(observation$derivation_mode, grant$derivation_mode) ||
        !identical(observation$source_axis_count,
          source$source_axis_count) ||
        !identical(observation$source_membership_count,
          source$source_membership_count) ||
        observation$aggregate_selected_count >
          source$source_membership_count || !isTRUE(counts_consistent) ||
        !identical(observation$sealed_axis_identity,
          .wb_operation_pack_v3_unscoped_identity(
            expected_seal$sealed_axis_identity)) ||
        !identical(observation$declaration_count, 1L) ||
        !identical(observation$seal_status, "sealed") ||
        !identical(observation$exact_linked_output_coverage, "passed") ||
        !identical(observation$semantic_validation, "passed") ||
        !identical(observation$linked_output_closure_identity,
          .wb_operation_pack_v3_unscoped_identity(grant$
            linked_output_closure$linked_output_closure_identity)) ||
        !identical(vapply(observation$linked_outputs, `[[`, character(1),
          "name"), vapply(linked, `[[`, character(1), "name")))
      .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
        "Derived-axis receipt closure differs from its exact grant.",
        "receipt")
    linked_by_name <- stats::setNames(linked, vapply(linked, `[[`,
      character(1), "name"))
    for (item in observation$linked_outputs) {
      expected_link <- linked_by_name[[item$name]]
      if (is.null(expected_link) || is.null(observed[[item$name]]))
        .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
          "A linked derived-axis receipt output is absent.", "receipt")
      descriptor <- observed[[item$name]]$descriptor
      .wb_operation_pack_v3_assert_self_identity(
        descriptor$sealed_output_cardinality_grant,
        "sealed_cardinality_grant_identity", "PYBENCH_RECEIPT_MISMATCH",
        "receipt")
      .wb_operation_pack_v3_assert_self_identity(
        descriptor$observed_sealed_output_cardinality,
        "observed_sealed_cardinality_identity", "PYBENCH_RECEIPT_MISMATCH",
        "receipt")
      sealed_grant <- descriptor$sealed_output_cardinality_grant
      cardinality <- descriptor$observed_sealed_output_cardinality
      bindings <- c(
        receipt_grant = identical(item$ordinary_output_grant_identity,
          expected_link$ordinary_output_grant_identity),
        sealed_grant = identical(sealed_grant$ordinary_output_grant_identity,
          expected_link$ordinary_output_grant_identity),
        derived_grant = identical(sealed_grant$derived_axis_grant_identity,
          .wb_operation_pack_v3_unscoped_identity(grant$grant_identity)),
        declaration = identical(sealed_grant$pack_declaration_identity,
          observation$pack_declaration_identity),
        manifest_declaration = identical(
          sealed_grant$manifest_declaration_identity,
          grant$manifest_declaration_identity),
        seal = identical(sealed_grant$sealed_axis_identity,
          observation$sealed_axis_identity),
        sealed_count = identical(sealed_grant$cell_axis_count,
          observation$final_cell_count),
        sealed_order = identical(sealed_grant$cell_axis_order_identity,
          observation$final_cell_order_identity),
        output_name = identical(sealed_grant$output, item$name),
        output_kind = identical(sealed_grant$kind, expected_link$kind),
        output_shape = identical(sealed_grant$shape,
          expected_link$shape),
        output_row_order = identical(sealed_grant$row_order,
          expected_link$row_order),
        output_missing_values = identical(sealed_grant$missing_values,
          expected_link$missing_values),
        output_key_axis = identical(
          sealed_grant$resolved_key_axis_policy_identity_or_null,
          expected_link$resolved_key_axis_policy_identity_or_null),
        cardinality_grant = identical(
          cardinality$sealed_cardinality_grant_identity,
          sealed_grant$sealed_cardinality_grant_identity),
        cardinality_seal = identical(cardinality$sealed_axis_identity,
          observation$sealed_axis_identity),
        observed_count = identical(cardinality$observed_cell_axis_count,
          observation$final_cell_count),
        observed_order = identical(
          cardinality$observed_cell_axis_order_identity,
          observation$final_cell_order_identity),
        observed_shape = identical(cardinality$shape,
          sealed_grant$shape),
        observed_status = identical(cardinality$semantic_validation,
          "passed"),
        cardinality_observation = identical(
          item$sealed_cardinality_observation_identity,
          .wb_operation_pack_v3_unscoped_identity(
            cardinality$observed_sealed_cardinality_identity)),
        descriptor = identical(item$observed_descriptor_identity,
          .wb_operation_pack_v3_unscoped_identity(
            descriptor$observed_descriptor_identity)),
        content = identical(item$content_identity,
          descriptor$content_identity),
        descriptor_seal = identical(item$observed_sealed_cell_axis_identity,
          descriptor$sealed_axis_identity))
      if (!all(bindings)) .wb_operation_pack_v3_error(
              "PYBENCH_RECEIPT_MISMATCH",
              paste0("Linked derived-axis output differs from its receipt ",
                "binding: ", paste(names(bindings)[!bindings],
                  collapse = ", "), "."),
              "receipt")
    }
  }
  invisible(TRUE)
}

.wb_operation_pack_v3_g7_sources_assert_current <- function(operation,
    inputs, params, request) {
  grants <- request$derived_cell_output_axis_grants %||% list()
  if (!length(grants)) return(invisible(TRUE))
  states <- attr(request, "operation_pack_v3_derived_axis_state") %||% list()
  declarations <- stats::setNames(.wb_operation_pack_v3_g7_declarations(
    operation), vapply(.wb_operation_pack_v3_g7_declarations(operation),
      `[[`, character(1), "name"))
  for (grant in grants) {
    declaration <- declarations[[as.character(grant$name)[1]]]
    source <- declaration$source
    if (identical(as.character(source$mode)[1], "static_input_axis")) {
      input_name <- as.character(source$input)[1]
      value <- inputs[[input_name]]
      definitions <- stats::setNames(operation$inputs, vapply(
        operation$inputs, `[[`, character(1), "name"))
      descriptor <- .wb_operation_pack_v2_input_descriptor(input_name, value,
        definitions[[input_name]])$descriptor
      if (!identical(.wb_operation_pack_v3_unscoped_identity(
          descriptor$descriptor_identity), grant$source_axes[[1L]]$
            input_descriptor_identity))
        .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
          "Derived-axis source descriptor changed after authentication.",
          "audit")
      selector <- if (identical(as.character(source$projection)[1],
          "family_key_cell_axis_v1"))
        .wb_operation_pack_v3_g7_resolve_selector(
          source$family_key_selector, params, descriptor_identity =
            grant$source_axes[[1L]]$input_descriptor_identity) else NULL
      stored_selector <- states[[grant$name]]$selectors[[1]]
      if (!identical(if (is.null(selector)) NULL else
          selector$source_axis_selector_identity,
          if (is.null(stored_selector)) NULL else
            stored_selector$source_axis_selector_identity))
        .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
          "Derived-axis selector changed after authentication.", "audit")
      cells <- .wb_operation_pack_v3_g7_project_cells(value,
        as.character(source$projection)[1],
        selector)
      if (!identical(cells, states[[grant$name]]$cells[[1]]))
        .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
          "Derived-axis source changed after authentication.", "audit")
    }
  }
  invisible(TRUE)
}
