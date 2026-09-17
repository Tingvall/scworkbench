# Core-owned ABI-v3 capability construction and audit.

.wb_operation_pack_v3_policy_map <- function(operation) {
  policies <- operation$dimension_policies %||% list()
  stats::setNames(policies, vapply(policies, function(x)
    as.character(x$output)[1], character(1)))
}

.wb_operation_pack_v3_input_map <- function(operation) {
  stats::setNames(operation$inputs, vapply(operation$inputs, function(x)
    as.character(x$name)[1], character(1)))
}

.wb_operation_pack_v3_unscoped_identity <- function(identity) {
  list(scheme = as.character(identity$scheme)[1],
    sha256 = as.character(identity$sha256)[1])
}

.wb_operation_pack_v3_distinct_first <- function(x) {
  x <- as.character(x)
  x[!duplicated(x)]
}

.wb_operation_pack_v3_effective_cell_axis <- function(policy, inputs,
                                                        effective_cells = NULL) {
  input_name <- as.character(policy$cell_axis$input)[1]
  value <- inputs[[input_name]]
  if (is.null(value)) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    paste0("Authenticated cell-axis input is absent: ", input_name),
    "resolution")
  available <- .wb_operation_pack_v3_distinct_first(
    .wb_operation_pack_v2_primitive_cells(value))
  source <- as.character(policy$cell_axis$source)[1]
  cells <- if (identical(source, "effective_cells_v1")) {
    selected <- as.character(effective_cells %||% available)
    if (length(setdiff(selected, available)) || anyDuplicated(selected))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Effective cells exceed or duplicate the authenticated input axis.",
        "resolution")
    selected
  } else if (identical(source,
      "distinct_input_cells_first_occurrence_v1")) available else
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      paste0("Unknown authenticated cell-axis source: ", source),
      "resolution")
  list(input_name = input_name, cells = cells, derivation = source)
}

.wb_operation_pack_v3_string_vector <- function(value, parameter) {
  value <- unlist(value %||% character(), use.names = FALSE)
  if (!is.character(value) || anyNA(value)) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    paste0("Parameter '", parameter, "' must resolve to strings."),
    "resolution")
  as.character(value)
}

.wb_operation_pack_v3_group_values <- function(value, prefix) {
  if (is.character(value)) {
    groups <- list(value)
    names(groups) <- "module1"
    return(groups)
  }
  if (!is.list(value)) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "Feature groups must be a string vector or a list of string vectors.",
    "resolution")
  names_in <- names(value)
  fully_named <- length(value) > 0L && !is.null(names_in) &&
    length(names_in) == length(value) && all(nzchar(names_in))
  names(value) <- if (fully_named) names_in else paste0(
    if (is.null(names_in) || !any(nzchar(names_in))) "module" else prefix,
    seq_along(value))
  value
}

.wb_operation_pack_v3_parameter_key_axis <- function(spec, inputs, params,
                                                       input_records) {
  groups_parameter <- as.character(spec$groups_parameter)[1]
  matrix_input <- as.character(spec$matrix_input)[1]
  prefix_parameter <- as.character(spec$name_prefix_parameter)[1]
  prefix <- as.character(params[[prefix_parameter]] %||% "")[1]
  if (!nzchar(prefix)) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    paste0("Feature-group prefix parameter is empty: ", prefix_parameter),
    "resolution")
  groups <- .wb_operation_pack_v3_group_values(params[[groups_parameter]],
    prefix)
  if (anyNA(names(groups)) || any(!nzchar(names(groups))) ||
      anyDuplicated(names(groups))) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "Resolved feature-group keys must be unique and nonempty.", "resolution")
  features <- as.character(inputs[[matrix_input]]$feature_id %||% character())
  missing_spec <- spec$missing_feature_policy
  missing_policy <- if (identical(as.character(missing_spec$source)[1],
      "fixed_drop_v1")) "drop" else as.character(params[[as.character(
        missing_spec$parameter)[1]]])[1]
  if (!missing_policy %in% c("drop", "error"))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Resolved missing-feature policy is invalid.", "resolution")
  resolved <- lapply(seq_along(groups), function(i) {
    input <- .wb_operation_pack_v3_string_vector(groups[[i]],
      groups_parameter)
    input <- input[!duplicated(input)]
    matched <- input[input %in% features]
    missing <- input[!input %in% features]
    if (length(missing) && identical(missing_policy, "error"))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        paste0("Feature group '", names(groups)[[i]],
          "' contains missing features."), "resolution")
    list(key = names(groups)[[i]], features_input = unname(as.list(input)),
      features_matched = unname(as.list(matched)),
      features_missing = unname(as.list(missing)))
  })
  empty <- !lengths(lapply(resolved, `[[`, "features_matched"))
  if (any(empty) && identical(as.character(spec$empty_group_policy)[1],
      "error")) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "A resolved feature group is empty after exact matching.", "resolution")
  resolved <- resolved[!empty]
  if (!length(resolved) && identical(as.character(spec$zero_key_policy)[1],
      "error")) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "The authenticated key axis may not be empty.", "resolution")
  input_record <- input_records[[matrix_input]]
  resolution <- list(source = "resolved_parameter_feature_groups_v1",
    groups_parameter = groups_parameter, matrix_input = matrix_input,
    matrix_input_descriptor_identity =
      .wb_operation_pack_v3_unscoped_identity(
        input_record$descriptor_identity),
    matrix_feature_axis_identity = input_record$feature_order_identity,
    name_prefix_parameter = prefix_parameter, name_prefix_value = prefix,
    matching = "exact_feature_id_v1",
    normalization = "ordered_unique_features_v1",
    generated_names = "legacy_module_group_names_v1",
    missing_feature_policy = missing_policy,
    empty_group_policy = as.character(spec$empty_group_policy)[1],
    zero_key_policy = as.character(spec$zero_key_policy)[1], groups = resolved)
  list(keys = vapply(resolved, `[[`, character(1), "key"),
    resolution = resolution)
}

.wb_operation_pack_v3_input_key_axis <- function(spec, inputs, params,
                                                   input_records) {
  input_name <- as.character(spec$input)[1]
  value <- inputs[[input_name]]
  available <- .wb_operation_pack_v3_distinct_first(value$key %||% character())
  selector_parameter <- as.character(spec$selector_parameter %||% "")[1]
  selector <- if (nzchar(selector_parameter) && !is.null(params[[selector_parameter]]))
    .wb_operation_pack_v3_string_vector(params[[selector_parameter]],
      selector_parameter) else NULL
  if (!is.null(selector) && (anyDuplicated(selector) ||
      length(setdiff(selector, available)))) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "Key selector contains duplicates or unknown input-family keys.",
    "resolution")
  keys <- selector %||% available
  if (!length(keys) && identical(as.character(spec$zero_key_policy)[1],
      "error")) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "The authenticated key axis may not be empty.", "resolution")
  resolution <- list(source = "input_keys_with_optional_selector_v1",
    input = input_name,
    input_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
      input_records[[input_name]]$descriptor_identity),
    selector_parameter = if (nzchar(selector_parameter)) selector_parameter else NULL,
    selector_value = if (is.null(selector)) NULL else unname(as.list(selector)),
    no_selector_order = "first_occurrence_v1",
    selector_order = "normalized_parameter_order_v1",
    unknown_key_policy = "error",
    zero_key_policy = as.character(spec$zero_key_policy)[1],
    keys = unname(as.list(keys)))
  list(keys = keys, resolution = resolution)
}

.wb_operation_pack_v3_cardinality_grant <- function(policy, output,
                                                      inputs, params,
                                                      input_records,
                                                      effective_cells = NULL) {
  cell_axis <- .wb_operation_pack_v3_effective_cell_axis(policy, inputs,
    effective_cells)
  shape <- as.character(policy$shape)[1]
  input_record <- input_records[[cell_axis$input_name]]
  value <- list(
    schema = "scworkbench.operation_pack.output_cardinality_grant.v1",
    output = as.character(output$name)[1], kind = as.character(output$kind)[1],
    policy = "authenticated_output_axes_v1", shape = shape,
    row_order = as.character(policy$row_order)[1],
    missing_values = as.character(policy$missing_values)[1],
    cell_axis_source = list(input_name = cell_axis$input_name,
      input_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
        input_record$descriptor_identity),
      derivation = cell_axis$derivation),
    cell_axis_count = as.integer(length(cell_axis$cells)),
    cell_axis_order_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", unname(as.list(cell_axis$cells))))
  keys <- character()
  if (identical(shape, "cell_key_cartesian")) {
    spec <- policy$key_axis
    key_state <- if (identical(as.character(spec$source)[1],
        "resolved_parameter_feature_groups_v1"))
      .wb_operation_pack_v3_parameter_key_axis(spec, inputs, params,
        input_records) else .wb_operation_pack_v3_input_key_axis(spec, inputs,
          params, input_records)
    keys <- key_state$keys
    if (length(keys) && length(cell_axis$cells) >
        floor(.Machine$integer.max / length(keys)))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Authenticated output cardinality overflows the integer boundary.",
        "resolution")
    pairs <- unlist(lapply(keys, function(key) lapply(cell_axis$cells,
      function(cell) list(key = key, cell_id = cell))), recursive = FALSE)
    value$key_axis_count <- as.integer(length(keys))
    value$key_axis <- unname(as.list(keys))
    value$key_axis_resolution <- key_state$resolution
    value$key_axis_order_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.row_order.v1", unname(as.list(keys)))
    value$expected_row_count <- as.integer(length(keys) * length(cell_axis$cells))
    value$row_order_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.row_order.v1", pairs)
  } else {
    value$expected_row_count <- as.integer(length(cell_axis$cells))
    value$row_order_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.row_order.v1", unname(as.list(cell_axis$cells)))
  }
  value$cardinality_grant_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.output_cardinality_grant.v1",
    "grant excluding cardinality_grant_identity", value)
  attr(value, "operation_pack_v3_cells") <- cell_axis$cells
  value
}

.wb_operation_pack_v3_missing_count <- function(x) {
  if (is.list(x)) return(sum(vapply(x, is.null, logical(1))))
  sum(is.na(x))
}

.wb_operation_pack_v3_observe_cardinality <- function(value, grant) {
  shape <- as.character(grant$shape)[1]
  cell_id <- as.character(value$cell_id %||% character())
  missing <- .wb_operation_pack_v3_missing_count(value$value %||% list())
  if (identical(grant$missing_values, "forbidden") && missing > 0L)
    .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
      "Authenticated output contains forbidden missing values.", "audit")
  if (anyNA(cell_id) || any(!nzchar(cell_id))) .wb_operation_pack_v3_error(
    "PYBENCH_OUTPUT_INVALID", "Authenticated output has invalid cell IDs.",
    "audit")
  if (identical(shape, "cell_key_cartesian")) {
    key <- as.character(value$key %||% character())
    expected_cells <- attr(grant, "operation_pack_v3_cells") %||%
      rep(NA_character_, as.integer(grant$cell_axis_count))
    expected_pairs <- unlist(lapply(as.character(unlist(grant$key_axis,
      use.names = FALSE)), function(k) lapply(expected_cells,
        function(cell) list(key = k, cell_id = cell))), recursive = FALSE)
    observed_pairs <- unname(Map(function(k, cell) list(key = k,
      cell_id = cell), key, cell_id))
    if (length(key) != as.integer(grant$expected_row_count) ||
        anyDuplicated(paste(key, cell_id, sep = "\034")) ||
        !identical(observed_pairs, expected_pairs))
      .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
        "Cell-vector-family rows are not the exact granted Cartesian product in key-major order.",
        "audit")
    observed_cells <- .wb_operation_pack_v3_distinct_first(cell_id)
    observed_keys <- .wb_operation_pack_v3_distinct_first(key)
    out <- list(
      schema = "scworkbench.operation_pack.observed_output_cardinality.v1",
      cardinality_grant_identity = grant$cardinality_grant_identity,
      shape = shape, observed_row_count = as.integer(length(key)),
      observed_cell_axis_count = as.integer(length(observed_cells)),
      observed_cell_axis_order_identity = .wb_operation_pack_v2_identity_plain(
        "scworkbench.cell_order.v1", unname(as.list(observed_cells))),
      observed_key_axis_count = as.integer(length(observed_keys)),
      observed_key_axis_order_identity = .wb_operation_pack_v2_identity_plain(
        "scworkbench.row_order.v1", unname(as.list(observed_keys))),
      observed_row_order_identity = .wb_operation_pack_v2_identity_plain(
        "scworkbench.row_order.v1", observed_pairs),
      missing_count = as.integer(missing), semantic_validation = "passed")
  } else {
    expected_cells <- attr(grant, "operation_pack_v3_cells") %||%
      rep(NA_character_, as.integer(grant$cell_axis_count))
    if (length(cell_id) != as.integer(grant$expected_row_count) ||
        anyDuplicated(cell_id) || !identical(cell_id, expected_cells))
      .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
        "Cell vector is not one row per granted distinct cell in order.",
        "audit")
    out <- list(
      schema = "scworkbench.operation_pack.observed_output_cardinality.v1",
      cardinality_grant_identity = grant$cardinality_grant_identity,
      shape = shape, observed_row_count = as.integer(length(cell_id)),
      observed_cell_axis_count = as.integer(length(cell_id)),
      observed_cell_axis_order_identity = .wb_operation_pack_v2_identity_plain(
        "scworkbench.cell_order.v1", unname(as.list(cell_id))),
      observed_row_order_identity = .wb_operation_pack_v2_identity_plain(
        "scworkbench.row_order.v1", unname(as.list(cell_id))),
      missing_count = as.integer(missing), semantic_validation = "passed")
  }
  out$observed_cardinality_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.observed_output_cardinality.v1",
    "observation excluding observed_cardinality_identity", out)
  out
}

.wb_operation_pack_v3_finalizer_definition <- function(chunk) {
  value <- list(
    schema = "scworkbench.operation_pack.summary_finalizer_definition.v1",
    interface = as.character(chunk$summary$interface)[1],
    callable = as.character(chunk$summary$callable)[1],
    isolation = as.character(chunk$summary$isolation)[1],
    merged_input = as.character(chunk$fragment_output)[1],
    summary_output = as.character(chunk$summary_output)[1],
    metadata_sources = chunk$summary$metadata_sources %||% list())
  value$finalizer_definition_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.summary_finalizer_definition.v1",
    "definition excluding finalizer_definition_identity", value)
  value
}

.wb_operation_pack_v3_fragment_grant <- function(grant, input_record,
                                                   index, start, cells) {
  keys <- as.character(unlist(grant$key_axis, use.names = FALSE))
  pairs <- unlist(lapply(keys, function(key) lapply(cells,
    function(cell) list(key = key, cell_id = cell))), recursive = FALSE)
  value <- list(
    schema = "scworkbench.operation_pack.chunk_fragment_grant.v1",
    fragment_output = grant$output,
    parent_cardinality_grant_identity = grant$cardinality_grant_identity,
    input_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
      input_record$descriptor_identity),
    batch_index = as.integer(index), batch_start = as.integer(start),
    batch_length = as.integer(length(cells)),
    batch_cell_order_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", unname(as.list(cells))),
    key_axis_count = as.integer(length(keys)), key_axis = unname(as.list(keys)),
    key_axis_order_identity = grant$key_axis_order_identity,
    expected_row_count = as.integer(length(keys) * length(cells)),
    row_order_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.row_order.v1", pairs), missing_values = grant$missing_values)
  value$fragment_grant_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.chunk_fragment_grant.v1",
    "grant excluding fragment_grant_identity", value)
  attr(value, "operation_pack_v3_cells") <- cells
  value
}

.wb_operation_pack_v3_chunk_schedule <- function(chunk, params, grant,
                                                  input_record) {
  cells <- attr(grant, "operation_pack_v3_cells") %||% character()
  requested <- params[[as.character(chunk$size_parameter)[1]]]
  requested <- if (is.null(requested)) NULL else as.integer(requested)[1]
  if (!is.null(requested) && (is.na(requested) || requested < 1L))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Cell chunk size must be positive or null.", "resolution")
  effective <- if (!length(cells)) 0L else if (is.null(requested))
    length(cells) else min(requested, length(cells))
  starts <- if (!length(cells)) integer() else seq.int(1L, length(cells),
    by = effective)
  batches <- lapply(seq_along(starts), function(i) {
    start <- starts[[i]]
    slice <- cells[start:min(length(cells), start + effective - 1L)]
    fragment <- .wb_operation_pack_v3_fragment_grant(grant, input_record,
      i, start, slice)
    list(index = as.integer(i), start = as.integer(start),
      length = as.integer(length(slice)),
      cell_order_identity = fragment$batch_cell_order_identity,
      fragment_grant = fragment)
  })
  value <- list(
    schema = "scworkbench.operation_pack.cell_chunk_schedule.v1",
    input_name = as.character(chunk$input)[1],
    input_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
      input_record$descriptor_identity),
    axis = "cells", axis_count = as.integer(length(cells)),
    axis_order_identity = grant$cell_axis_order_identity,
    requested_chunk_size = requested,
    effective_chunk_size = as.integer(effective), batches = batches,
    merge_policy = "row_bind_cell_vector_family_v1",
    fragment_output = as.character(chunk$fragment_output)[1],
    summary_output = as.character(chunk$summary_output)[1],
    summary_finalizer_definition = .wb_operation_pack_v3_finalizer_definition(chunk))
  value$schedule_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.cell_chunk_schedule.v1",
    "schedule excluding schedule_identity", value)
  value
}

.wb_operation_pack_v3_observe_fragment <- function(value, grant, index) {
  cardinality <- list(
    schema = "scworkbench.operation_pack.output_cardinality_grant.v1",
    output = grant$fragment_output, kind = "cell_vector_family",
    policy = "authenticated_output_axes_v1", shape = "cell_key_cartesian",
    row_order = "key_major_then_cell_v1", missing_values = grant$missing_values,
    cell_axis_count = grant$batch_length,
    cell_axis_order_identity = grant$batch_cell_order_identity,
    key_axis_count = grant$key_axis_count, key_axis = grant$key_axis,
    key_axis_order_identity = grant$key_axis_order_identity,
    expected_row_count = grant$expected_row_count,
    row_order_identity = grant$row_order_identity,
    cardinality_grant_identity = grant$parent_cardinality_grant_identity)
  attr(cardinality, "operation_pack_v3_cells") <-
    attr(grant, "operation_pack_v3_cells")
  observed <- .wb_operation_pack_v3_observe_cardinality(value, cardinality)
  out <- list(
    schema = "scworkbench.operation_pack.observed_chunk_fragment.v1",
    index = as.integer(index),
    fragment_grant_identity = grant$fragment_grant_identity,
    observed_row_count = observed$observed_row_count,
    observed_cell_order_identity = observed$observed_cell_axis_order_identity,
    observed_key_order_identity = observed$observed_key_axis_order_identity,
    observed_row_order_identity = observed$observed_row_order_identity,
    missing_count = observed$missing_count,
    descriptor_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.fragment_descriptor.v1",
      list(index = as.integer(index), grant = grant$fragment_grant_identity)),
    content_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_vector_family.content.v1", unclass(value)),
    semantic_validation = "passed")
  out$observed_fragment_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.observed_chunk_fragment.v1",
    "observation excluding observed_fragment_identity", out)
  out
}

.wb_operation_pack_v3_merge_fragments <- function(fragments, schedule) {
  batches <- schedule$batches
  if (length(fragments) != length(batches) || !identical(sort(as.integer(
      names(fragments))), seq_along(batches)))
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "Chunk fragments are not a bijection with the schedule.", "receipt")
  observations <- lapply(seq_along(batches), function(i)
    .wb_operation_pack_v3_observe_fragment(fragments[[as.character(i)]],
      batches[[i]]$fragment_grant, i))
  keys <- as.character(unlist(batches[[1]]$fragment_grant$key_axis %||%
    list(), use.names = FALSE))
  rows <- unlist(lapply(keys, function(key) lapply(seq_along(batches),
    function(i) {
      fragment <- fragments[[as.character(i)]]
      keep <- as.character(fragment$key) == key
      list(key = as.character(fragment$key[keep]),
        cell_id = as.character(fragment$cell_id[keep]),
        value = fragment$value[keep])
    })), recursive = FALSE)
  merged <- wb_prim_cell_vector_family(
    key = unlist(lapply(rows, `[[`, "key"), use.names = FALSE),
    cell_id = unlist(lapply(rows, `[[`, "cell_id"), use.names = FALSE),
    value = unlist(lapply(rows, `[[`, "value"), use.names = FALSE),
    meta = fragments[[1]]$meta %||% list())
  list(value = merged, observations = observations)
}

.wb_operation_pack_v3_request <- function(bundle, registration, operation,
                                            inputs, params, transition_id,
                                            session_id, run_id, generation,
                                            preflight, stage_root,
                                            effective_cells = NULL,
                                            source_refs = list()) {
  projected <- .wb_operation_pack_v3_v2_projection(list(
    schema_version = "scworkbench.operation_pack.v3",
    pack_abi_version = "3", identity_scheme =
      .wb_operation_pack_identity_scheme(), namespace =
      registration$manifest$namespace, package = registration$manifest$package,
    backend = registration$manifest$backend,
    compatibility = registration$manifest$compatibility,
    entry_point = registration$manifest$entry_point,
    operations = list(operation)))$operations[[1]]
  base <- .wb_operation_pack_v2_request(bundle, registration, projected,
    inputs, params, transition_id, session_id, run_id, generation, preflight,
    stage_root)
  ancestry_inputs <- unique(vapply(operation$provenance_reads %||% list(),
    function(x) as.character(x$input)[1], character(1)))
  for (i in seq_along(base$inputs)) {
    name <- as.character(base$inputs[[i]]$name)[1]
    if (name %in% ancestry_inputs &&
        !is.null(.wb_operation_pack_v3_artifact_ref(source_refs[[name]]))) {
      base$inputs[[i]]$descriptor <-
        .wb_operation_pack_v3_bind_artifact_input_descriptor(bundle,
          source_refs[[name]], inputs[[name]], base$inputs[[i]]$descriptor)
    }
  }
  input_records <- stats::setNames(lapply(base$inputs, `[[`, "descriptor"),
    vapply(base$inputs, `[[`, character(1), "name"))
  policies <- .wb_operation_pack_v3_policy_map(operation)
  outputs <- stats::setNames(operation$outputs,
    vapply(operation$outputs, `[[`, character(1), "name"))
  for (i in seq_along(base$outputs)) {
    name <- as.character(base$outputs[[i]]$name)[1]
    descriptor <- base$outputs[[i]]$descriptor
    policy <- policies[[name]]
    if (!is.null(policy) && identical(as.character(policy$policy)[1],
        "authenticated_output_axes_v1")) {
      grant <- .wb_operation_pack_v3_cardinality_grant(policy,
        outputs[[name]], inputs, params, input_records, effective_cells)
      descriptor$cardinality_grant <- grant
      descriptor$expected_dimensions <- if (identical(grant$shape,
          "cell_key_cartesian")) list(grant$expected_row_count, 3L) else
        list(grant$expected_row_count)
      granted_cells <- attr(grant, "operation_pack_v3_cells") %||%
        character()
      output_cells <- if (identical(grant$shape,
          "cell_key_cartesian")) rep(granted_cells,
        times = as.integer(grant$key_axis_count)) else granted_cells
      descriptor$expected_cell_order_identity <-
        .wb_operation_pack_v2_identity_plain(
          "scworkbench.cell_order.v1", unname(as.list(output_cells)))
    }
    descriptor$grant_identity <- NULL
    descriptor$grant_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.output_grant.v3",
      "descriptor excluding grant_identity", descriptor)
    base$outputs[[i]]$descriptor <- descriptor
  }

  schedules <- list()
  chunk <- operation$chunking %||% NULL
  if (identical(as.character(chunk$axis %||% "")[1], "cells")) {
    output_name <- as.character(chunk$fragment_output)[1]
    output_record <- base$outputs[[match(output_name,
      vapply(base$outputs, `[[`, character(1), "name"))]]
    grant <- output_record$descriptor$cardinality_grant
    cells <- .wb_operation_pack_v3_effective_cell_axis(policies[[output_name]],
      inputs, effective_cells)$cells
    attr(grant, "operation_pack_v3_cells") <- cells
    input_record <- input_records[[as.character(chunk$input)[1]]]
    schedules <- list(.wb_operation_pack_v3_chunk_schedule(chunk, params,
      grant, input_record))
  }

  provenance <- .wb_operation_pack_v3_provenance_read_records(bundle,
    operation, inputs, source_refs, input_records, params, stage_root)
  identity <- registration$identity
  op_name <- as.character(operation$qualified_name)[1]
  capability <- base$execution_capability
  capability$pack_identity <- identity$pack_identity
  capability$operation_definition_identity <-
    identity$operation_definition_identities[[op_name]]
  capability$writer_grants <- lapply(base$outputs, function(x) list(
    output_name = x$name, writer = x$descriptor$writer,
    grant_identity = x$descriptor$grant_identity))
  capability$reader_grants <- c(
    lapply(base$inputs, function(x) list(input_name = x$name,
      reader = x$descriptor$reader,
      descriptor_identity = x$descriptor$descriptor_identity)),
    lapply(base$registry_reads %||% list(), function(x) list(
      registry_read_name = x$name, reader = x$descriptor$reader,
      descriptor_identity = x$descriptor$descriptor_identity)),
    lapply(provenance$records, function(x) list(
      provenance_read_name = x$name, reader = x$reader,
      descriptor_identity = x$descriptor_identity)))
  if (length(schedules)) capability$chunk_schedule_identities <-
    lapply(schedules, function(x) .wb_operation_pack_v3_unscoped_identity(
      x$schedule_identity))
  if (length(provenance$records)) capability$provenance_read_identities <-
    lapply(provenance$records, function(x)
      .wb_operation_pack_v3_unscoped_identity(
        x$descriptor_identity))
  capability$capability_identity <- NULL
  capability$capability_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.capability.v3",
    "capability excluding capability_identity", capability)

  base$schema <- "scworkbench.operation_pack.transition_request.v3"
  base$process_protocol_version <- "pybench-op-v4"
  base$pack_abi_version <- "3"
  base$operation_authentication <- list(name = op_name,
    pack_identity = identity$pack_identity,
    manifest_identity = identity$manifest_identity,
    manifest_source_identity = identity$manifest_source_identity,
    distribution_identity = identity$distribution_identity,
    operation_definition_identity =
      identity$operation_definition_identities[[op_name]],
    entry_point = list(value = identity$entry_point,
      identity = identity$entry_point_identity))
  base$execution_capability <- capability
  if (length(schedules)) base$chunk_schedules <- schedules
  if (length(provenance$records)) base$provenance_reads <- provenance$records
  base$request_identity <- NULL
  base$request_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.transition_request.v3",
    "request excluding request_identity", base)
  attr(base, "operation_pack_v2_transport_inputs") <- attr(base,
    "operation_pack_v2_transport_inputs")
  attr(base, "operation_pack_v2_registry_read_values") <- attr(base,
    "operation_pack_v2_registry_read_values")
  attr(base, "operation_pack_v3_provenance_read_values") <- provenance$values
  base
}

.wb_operation_pack_v3_schema_assert <- function(value,
    kind = c("request", "receipt"), code) {
  kind <- match.arg(kind)
  schema <- .wb_operation_pack_v2_read_schema(
    .wb_operation_pack_v3_transition_schema(kind))
  result <- .wb_json_schema_validate_2020(value, schema)
  if (!isTRUE(result$ok)) .wb_operation_pack_v3_error(code,
    paste0("V3 ", kind, " failed Draft 2020-12 validation at ",
      result$path, ": ", result$message),
    if (kind == "request") "staging" else "receipt",
    instance_path = result$path)
  invisible(TRUE)
}

.wb_operation_pack_v3_request_audit <- function(request, registration,
                                                 operation) {
  .wb_operation_pack_v2_assert_self_identity(request$transition,
    "transition_identity", "PYBENCH_CAPABILITY_MISMATCH", "staging")
  for (input in request$inputs) .wb_operation_pack_v2_assert_self_identity(
    input$descriptor, "descriptor_identity",
    "PYBENCH_INPUT_IDENTITY_MISMATCH", "resolution")
  for (output in request$outputs) {
    descriptor <- output$descriptor
    if (!is.null(descriptor$cardinality_grant))
      .wb_operation_pack_v3_assert_self_identity(
        descriptor$cardinality_grant, "cardinality_grant_identity",
        "PYBENCH_CAPABILITY_MISMATCH", "staging")
    .wb_operation_pack_v3_assert_self_identity(descriptor, "grant_identity",
      "PYBENCH_CAPABILITY_MISMATCH", "staging")
  }
  for (schedule in request$chunk_schedules %||% list()) {
    for (batch in schedule$batches) .wb_operation_pack_v3_assert_self_identity(
      batch$fragment_grant, "fragment_grant_identity",
      "PYBENCH_CAPABILITY_MISMATCH", "staging")
    .wb_operation_pack_v3_assert_self_identity(
      schedule$summary_finalizer_definition,
      "finalizer_definition_identity", "PYBENCH_CAPABILITY_MISMATCH",
      "staging")
    .wb_operation_pack_v3_assert_self_identity(schedule,
      "schedule_identity", "PYBENCH_CAPABILITY_MISMATCH", "staging")
  }
  for (read in request$provenance_reads %||% list())
    .wb_operation_pack_v3_assert_self_identity(read,
      "descriptor_identity", "PYBENCH_INPUT_IDENTITY_MISMATCH", "resolution")
  .wb_operation_pack_v3_assert_self_identity(request$execution_capability,
    "capability_identity", "PYBENCH_CAPABILITY_MISMATCH", "staging")
  .wb_operation_pack_v3_assert_self_identity(request, "request_identity",
    "PYBENCH_CAPABILITY_MISMATCH", "staging")
  identity <- registration$identity
  op_name <- as.character(operation$qualified_name)[1]
  if (!identical(request$operation_authentication$pack_identity,
      identity$pack_identity) || !identical(
      request$operation_authentication$operation_definition_identity,
      identity$operation_definition_identities[[op_name]]))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "V3 request authentication differs from the activated pack.",
      "staging")
  expected_writers <- lapply(request$outputs, function(x) list(
    output_name = x$name, writer = x$descriptor$writer,
    grant_identity = x$descriptor$grant_identity))
  if (!identical(expected_writers,
      request$execution_capability$writer_grants))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "V3 capability writer grants differ from request outputs.", "staging")
  expected_readers <- c(
    lapply(request$inputs, function(x) list(input_name = x$name,
      reader = x$descriptor$reader,
      descriptor_identity = x$descriptor$descriptor_identity)),
    lapply(request$registry_reads %||% list(), function(x) list(
      registry_read_name = x$name, reader = x$descriptor$reader,
      descriptor_identity = x$descriptor$descriptor_identity)),
    lapply(request$provenance_reads %||% list(), function(x) list(
      provenance_read_name = x$name, reader = x$reader,
      descriptor_identity = x$descriptor_identity)))
  if (!identical(expected_readers,
      request$execution_capability$reader_grants))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "V3 capability reader grants differ from request inputs.", "staging")
  expected_schedules <- lapply(request$chunk_schedules %||% list(),
    function(x) .wb_operation_pack_v3_unscoped_identity(
      x$schedule_identity))
  expected_provenance <- lapply(request$provenance_reads %||% list(),
    function(x) .wb_operation_pack_v3_unscoped_identity(
      x$descriptor_identity))
  if (!identical(request$execution_capability$chunk_schedule_identities %||%
        list(), expected_schedules) ||
      !identical(request$execution_capability$provenance_read_identities %||%
        list(), expected_provenance))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "V3 capability schedule or provenance closure differs from request.",
      "staging")
  invisible(TRUE)
}

.wb_operation_pack_v3_runtime_attestation <- function(registration, op_name,
                                                       preflight) {
  value <- .wb_operation_pack_v2_runtime_attestation(registration, op_name,
    preflight)
  value$schema <- "scworkbench.operation_pack.runtime.v3"
  value$runtime_identity <- NULL
  value$runtime_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.runtime.v3",
    "runtime attestation excluding runtime_identity", value)
  value
}

.wb_operation_pack_v3_receipt <- function(request, registration, operation,
                                           writes, preflight, inputs,
                                           registry_reads = list(),
                                           provenance_reads = list(),
                                           chunk_executions = list(),
                                           chunk_state = NULL) {
  projected <- .wb_operation_pack_v3_v2_projection(list(
    schema_version = "scworkbench.operation_pack.v3",
    pack_abi_version = "3", identity_scheme =
      .wb_operation_pack_identity_scheme(), namespace =
      registration$manifest$namespace, package = registration$manifest$package,
    backend = registration$manifest$backend,
    compatibility = registration$manifest$compatibility,
    entry_point = registration$manifest$entry_point,
    operations = list(operation)))$operations[[1]]
  base_request <- request
  base_request$schema <- "scworkbench.operation_pack.transition_request.v2"
  base_request$process_protocol_version <- "pybench-op-v3"
  base_request$pack_abi_version <- "2"
  base_request$chunk_schedules <- NULL
  base_request$provenance_reads <- NULL
  for (i in seq_along(base_request$outputs)) {
    base_request$outputs[[i]]$descriptor$cardinality_grant <- NULL
    base_request$outputs[[i]]$descriptor$grant_identity$scheme <-
      "scworkbench.operation_pack.output_grant.v2"
  }
  receipt <- .wb_operation_pack_v2_receipt(base_request, registration,
    projected, writes, preflight, registry_reads)
  grants <- stats::setNames(request$outputs,
    vapply(request$outputs, `[[`, character(1), "name"))
  policies <- .wb_operation_pack_v3_policy_map(operation)
  observed <- c(receipt$outputs %||% list(),
    receipt$registry_requests %||% list())
  for (i in seq_along(observed)) {
    name <- as.character(observed[[i]]$name)[1]
    descriptor <- observed[[i]]$descriptor
    descriptor$grant_identity <- grants[[name]]$descriptor$grant_identity
    cardinality <- grants[[name]]$descriptor$cardinality_grant %||% NULL
    if (!is.null(cardinality)) {
      cells <- .wb_operation_pack_v3_effective_cell_axis(policies[[name]],
        inputs)$cells
      attr(cardinality, "operation_pack_v3_cells") <- cells
      descriptor$observed_cardinality <-
        .wb_operation_pack_v3_observe_cardinality(writes[[name]]$value,
          cardinality)
      descriptor$dimensions <- unname(as.list(
        .wb_operation_pack_v2_dimensions(writes[[name]]$value,
          as.character(descriptor$kind)[1])))
    }
    descriptor$observed_descriptor_identity <- NULL
    descriptor$observed_descriptor_identity <-
      .wb_operation_pack_v2_identity_scoped(
        "scworkbench.operation_pack.observed_output.v3",
        "descriptor excluding observed_descriptor_identity", descriptor)
    observed[[i]]$descriptor <- descriptor
  }
  output_names <- vapply(receipt$outputs %||% list(), `[[`, character(1),
    "name")
  receipt$outputs <- observed[vapply(observed, function(x)
    as.character(x$name)[1] %in% output_names, logical(1))]
  receipt$registry_requests <- observed[!vapply(observed, function(x)
    as.character(x$name)[1] %in% output_names, logical(1))]
  receipt$schema <- "scworkbench.operation_pack.transition_receipt.v3"
  receipt$process_protocol_version <- "pybench-op-v4"
  receipt$pack_abi_version <- "3"
  receipt$request_identity <- request$request_identity
  receipt$capability_identity <- request$execution_capability$capability_identity
  receipt$runtime_attestation <- .wb_operation_pack_v3_runtime_attestation(
    registration, operation$qualified_name, preflight)
  if (!is.null(chunk_state)) {
    output_map <- stats::setNames(observed,
      vapply(observed, `[[`, character(1), "name"))
    fragment <- output_map[[chunk_state$schedule$fragment_output]]$descriptor
    summary <- output_map[[chunk_state$schedule$summary_output]]$descriptor
    invocation <- chunk_state$invocation
    execution <- list(
      schema = "scworkbench.operation_pack.cell_chunk_observation.v1",
      request_identity = .wb_operation_pack_v3_unscoped_identity(
        request$request_identity),
      capability_identity = .wb_operation_pack_v3_unscoped_identity(
        request$execution_capability$capability_identity),
      operation_definition_identity = .wb_operation_pack_v3_unscoped_identity(
        request$operation_authentication$operation_definition_identity),
      schedule_identity = .wb_operation_pack_v3_unscoped_identity(
        chunk_state$schedule$schedule_identity),
      observed_chunks = chunk_state$observations,
      merged_family_descriptor_identity =
        .wb_operation_pack_v3_unscoped_identity(
          fragment$observed_descriptor_identity),
      merged_family_content_identity = fragment$content_identity,
      finalizer_definition_identity =
        .wb_operation_pack_v3_unscoped_identity(chunk_state$schedule$
          summary_finalizer_definition$finalizer_definition_identity),
      finalizer_metadata_identity = .wb_operation_pack_v3_unscoped_identity(
        chunk_state$metadata$finalizer_metadata_identity),
      finalizer_invocation_identity =
        .wb_operation_pack_v3_unscoped_identity(
          invocation$finalizer_invocation_identity),
      summary_source_identity = fragment$content_identity,
      summary_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
        summary$observed_descriptor_identity),
      summary_content_identity = summary$content_identity)
    execution$chunk_execution_identity <-
      .wb_operation_pack_v2_identity_scoped(
        "scworkbench.operation_pack.cell_chunk_observation.v1",
        "observation excluding chunk_execution_identity", execution)
    chunk_executions <- list(execution)
  }
  if (length(provenance_reads)) receipt$provenance_reads <- provenance_reads
  if (length(chunk_executions)) receipt$chunk_executions <- chunk_executions
  receipt$receipt_identity <- NULL
  receipt$receipt_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.transition_receipt.v3",
    "receipt excluding receipt_identity", receipt)
  receipt
}

.wb_operation_pack_v3_receipt_audit <- function(receipt, request,
                                                 registration, operation,
                                                 preflight) {
  .wb_operation_pack_v3_assert_self_identity(receipt, "receipt_identity",
    "PYBENCH_RECEIPT_MISMATCH", "receipt")
  if (!identical(receipt$request_identity, request$request_identity) ||
      !identical(receipt$capability_identity,
        request$execution_capability$capability_identity))
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "V3 receipt is not bound to the exact request and capability.",
      "receipt")
  grants <- stats::setNames(request$outputs,
    vapply(request$outputs, `[[`, character(1), "name"))
  observed <- c(receipt$outputs %||% list(),
    receipt$registry_requests %||% list())
  if (!setequal(names(grants), vapply(observed, `[[`, character(1), "name")) ||
      length(grants) != length(observed))
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "V3 receipt output closure differs from grants.", "receipt")
  for (item in observed) {
    .wb_operation_pack_v3_assert_self_identity(item$descriptor,
      "observed_descriptor_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
    grant <- grants[[as.character(item$name)[1]]]$descriptor
    if (!identical(item$descriptor$grant_identity, grant$grant_identity))
      .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
        "Observed output refers to the wrong v3 grant.", "receipt")
    if (!is.null(grant$cardinality_grant)) {
      .wb_operation_pack_v3_assert_self_identity(
        item$descriptor$observed_cardinality,
        "observed_cardinality_identity", "PYBENCH_RECEIPT_MISMATCH",
        "receipt")
      if (!identical(item$descriptor$observed_cardinality$
          cardinality_grant_identity,
          grant$cardinality_grant$cardinality_grant_identity))
        .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
          "Observed cardinality refers to the wrong grant.", "receipt")
    }
  }
  for (execution in receipt$chunk_executions %||% list())
    .wb_operation_pack_v3_assert_self_identity(execution,
      "chunk_execution_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
  for (read in receipt$provenance_reads %||% list())
    .wb_operation_pack_v3_assert_self_identity(read,
      "observed_descriptor_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
  .wb_operation_pack_v3_assert_self_identity(receipt$mutation_manifest,
    "mutation_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
  .wb_operation_pack_v3_assert_self_identity(receipt$runtime_attestation,
    "runtime_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
  expected_runtime <- .wb_operation_pack_v3_runtime_attestation(registration,
    operation$qualified_name, preflight)
  if (!identical(.wb_operation_pack_canonical_json(
        receipt$runtime_attestation),
      .wb_operation_pack_canonical_json(expected_runtime)))
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "V3 runtime attestation differs from the audited execution.", "receipt")
  invisible(TRUE)
}

.wb_operation_pack_v3_record_validate <- function(request, receipt, path,
                                                    load_payloads = FALSE) {
  fail <- function(code, output = NULL) list(ok = FALSE, code = code,
    output = output)
  checked <- tryCatch({
    .wb_operation_pack_v3_schema_assert(request, "request",
      "PYBENCH_REOPEN_VALIDATION_FAILED")
    .wb_operation_pack_v3_schema_assert(receipt, "receipt",
      "PYBENCH_REOPEN_VALIDATION_FAILED")
    .wb_operation_pack_v3_assert_self_identity(request, "request_identity",
      "PYBENCH_REOPEN_VALIDATION_FAILED", "reopen")
    .wb_operation_pack_v3_assert_self_identity(receipt, "receipt_identity",
      "PYBENCH_REOPEN_VALIDATION_FAILED", "reopen")
    .wb_operation_pack_v3_assert_self_identity(request$execution_capability,
      "capability_identity", "PYBENCH_REOPEN_VALIDATION_FAILED", "reopen")
    for (input in request$inputs) .wb_operation_pack_v3_assert_self_identity(
      input$descriptor, "descriptor_identity",
      "PYBENCH_REOPEN_VALIDATION_FAILED", "reopen")
    TRUE
  }, error = function(error) FALSE)
  if (!isTRUE(checked)) return(fail("v3_request_receipt_invalid"))
  if (!identical(receipt$request_identity, request$request_identity) ||
      !identical(receipt$capability_identity,
        request$execution_capability$capability_identity))
    return(fail("v3_request_receipt_binding_mismatch"))

  grants <- stats::setNames(request$outputs, vapply(request$outputs, `[[`,
    character(1), "name"))
  observations <- c(receipt$outputs %||% list(),
    receipt$registry_requests %||% list())
  observation_names <- vapply(observations, `[[`, character(1), "name")
  if (anyDuplicated(observation_names) || !identical(sort(names(grants),
      method = "radix"), sort(observation_names, method = "radix")))
    return(fail("v3_output_bijection_mismatch"))
  observation_map <- stats::setNames(observations, observation_names)
  for (name in names(grants)) {
    grant <- grants[[name]]$descriptor
    observed <- observation_map[[name]]$descriptor
    valid <- tryCatch({
      if (!is.null(grant$cardinality_grant))
        .wb_operation_pack_v3_assert_self_identity(grant$cardinality_grant,
          "cardinality_grant_identity",
          "PYBENCH_REOPEN_VALIDATION_FAILED", "reopen")
      .wb_operation_pack_v3_assert_self_identity(grant, "grant_identity",
        "PYBENCH_REOPEN_VALIDATION_FAILED", "reopen")
      .wb_operation_pack_v3_assert_self_identity(observed,
        "observed_descriptor_identity",
        "PYBENCH_REOPEN_VALIDATION_FAILED", "reopen")
      if (!is.null(grant$cardinality_grant)) {
        .wb_operation_pack_v3_assert_self_identity(
          observed$observed_cardinality,
          "observed_cardinality_identity",
          "PYBENCH_REOPEN_VALIDATION_FAILED", "reopen")
        stopifnot(identical(observed$observed_cardinality$
          cardinality_grant_identity,
          grant$cardinality_grant$cardinality_grant_identity))
      }
      identical(observed$grant_identity, grant$grant_identity)
    }, error = function(error) FALSE)
    if (!isTRUE(valid)) return(fail("v3_output_grant_mismatch", name))
  }

  schedules <- request$chunk_schedules %||% list()
  executions <- receipt$chunk_executions %||% list()
  if (length(schedules) != length(executions))
    return(fail("v3_chunk_bijection_mismatch"))
  for (i in seq_along(schedules)) {
    schedule <- schedules[[i]]; execution <- executions[[i]]
    valid <- tryCatch({
      for (batch in schedule$batches)
        .wb_operation_pack_v3_assert_self_identity(batch$fragment_grant,
          "fragment_grant_identity", "PYBENCH_REOPEN_VALIDATION_FAILED",
          "reopen")
      .wb_operation_pack_v3_assert_self_identity(
        schedule$summary_finalizer_definition,
        "finalizer_definition_identity",
        "PYBENCH_REOPEN_VALIDATION_FAILED", "reopen")
      .wb_operation_pack_v3_assert_self_identity(schedule,
        "schedule_identity", "PYBENCH_REOPEN_VALIDATION_FAILED", "reopen")
      .wb_operation_pack_v3_assert_self_identity(execution,
        "chunk_execution_identity", "PYBENCH_REOPEN_VALIDATION_FAILED",
        "reopen")
      for (fragment in execution$observed_chunks)
        .wb_operation_pack_v3_assert_self_identity(fragment,
          "observed_fragment_identity", "PYBENCH_REOPEN_VALIDATION_FAILED",
          "reopen")
      expected_fragments <- vapply(schedule$batches, function(x)
        x$fragment_grant$fragment_grant_identity$sha256, character(1))
      observed_fragments <- vapply(execution$observed_chunks, function(x)
        x$fragment_grant_identity$sha256, character(1))
      fragment_output <- observation_map[[schedule$fragment_output]]$descriptor
      summary_output <- observation_map[[schedule$summary_output]]$descriptor
      identical(execution$schedule_identity,
        .wb_operation_pack_v3_unscoped_identity(
          schedule$schedule_identity)) &&
        identical(execution$request_identity,
          .wb_operation_pack_v3_unscoped_identity(
            request$request_identity)) &&
        identical(execution$capability_identity,
          .wb_operation_pack_v3_unscoped_identity(
            request$execution_capability$capability_identity)) &&
        identical(expected_fragments, observed_fragments) &&
        identical(execution$merged_family_descriptor_identity,
          .wb_operation_pack_v3_unscoped_identity(
            fragment_output$observed_descriptor_identity)) &&
        identical(execution$merged_family_content_identity,
          fragment_output$content_identity) &&
        identical(execution$summary_descriptor_identity,
          .wb_operation_pack_v3_unscoped_identity(
            summary_output$observed_descriptor_identity)) &&
        identical(execution$summary_content_identity,
          summary_output$content_identity) &&
        identical(execution$summary_source_identity,
          fragment_output$content_identity)
    }, error = function(error) FALSE)
    if (!isTRUE(valid)) return(fail("v3_chunk_evidence_mismatch"))
  }

  reads <- request$provenance_reads %||% list()
  observed_reads <- receipt$provenance_reads %||% list()
  read_names <- vapply(reads, `[[`, character(1), "name")
  observed_names <- vapply(observed_reads, `[[`, character(1), "name")
  if (anyDuplicated(read_names) || anyDuplicated(observed_names) ||
      !identical(read_names, observed_names))
    return(fail("v3_provenance_read_bijection_mismatch"))
  for (i in seq_along(reads)) {
    read <- reads[[i]]; observed <- observed_reads[[i]]
    name <- as.character(read$name)[1]
    valid <- tryCatch({
      .wb_operation_pack_v3_assert_self_identity(read,
        "descriptor_identity", "PYBENCH_REOPEN_VALIDATION_FAILED",
        "reopen")
      .wb_operation_pack_v3_assert_self_identity(observed,
        "observed_descriptor_identity",
        "PYBENCH_REOPEN_VALIDATION_FAILED", "reopen")
      identical(as.integer(observed$use_count)[1], 1L) &&
        identical(observed$descriptor_identity,
          .wb_operation_pack_v3_unscoped_identity(
            read$descriptor_identity)) &&
        identical(observed$snapshot_identity,
          .wb_operation_pack_v3_unscoped_identity(
            read$snapshot_identity)) &&
        identical(observed$payload_manifest_identity,
          read$payload_manifest_identity)
    }, error = function(error) FALSE)
    if (!isTRUE(valid)) return(fail(
      "v3_provenance_read_descriptor_mismatch", name))
    payload <- file.path(path, "provenance_reads", name, "payload.json")
    if (!file.exists(payload)) return(fail(
      "v3_provenance_read_payload_missing", name))
    manifest <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.payload_manifest.v2",
      list(path = paste0("provenance_reads/", name, "/payload.json"),
        sha256 = .wb_operation_pack_v2_file_sha256(payload)))
    if (!identical(manifest, read$payload_manifest_identity))
      return(fail("v3_provenance_read_payload_identity_mismatch", name))
    if (isTRUE(load_payloads)) {
      payload_value <- tryCatch({
        raw <- readChar(payload, nchars = file.info(payload)$size,
          useBytes = TRUE)
        .wb_operation_pack_v2_assert_strict_json(raw)
        .wb_operation_pack_parse_canonical_json(raw)
      }, error = identity)
      if (inherits(payload_value, "error")) return(fail(
        "v3_provenance_read_payload_unreadable", name))
      valid_payload <- tryCatch({
        .wb_operation_pack_v3_assert_self_identity(payload_value,
          "snapshot_identity", "PYBENCH_REOPEN_VALIDATION_FAILED",
          "reopen")
        identical(payload_value$snapshot_identity,
          read$snapshot_identity) &&
          identical(payload_value$input_descriptor_identity,
            read$input_descriptor_identity)
      }, error = function(error) FALSE)
      if (!isTRUE(valid_payload)) return(fail(
        "v3_provenance_read_payload_invalid", name))
    }
  }
  list(ok = TRUE)
}

.wb_operation_pack_v3_artifact_ref <- function(ref) {
  if (is.list(ref) && nzchar(as.character(ref$artifact_id %||% "")[1]))
    return(list(artifact_id = as.character(ref$artifact_id)[1],
      output = as.character(ref$output %||% "")[1]))
  if (is.list(ref) && identical(as.character(ref$ref_type %||% "")[1],
      "artifact")) return(list(artifact_id = as.character(ref$artifact_id)[1],
    output = as.character(ref$output %||% "")[1]))
  if (is.list(ref) && identical(as.character(ref$type %||% "")[1],
      "artifact")) return(list(artifact_id = as.character(ref$value)[1],
    output = as.character(ref$output %||% "")[1]))
  if (is.character(ref) && length(ref) == 1L && nzchar(ref))
    return(list(artifact_id = as.character(ref)[1], output = ""))
  NULL
}

.wb_operation_pack_v3_bind_artifact_input_descriptor <- function(bundle, ref,
    value, descriptor) {
  ref <- .wb_operation_pack_v3_artifact_ref(ref)
  if (is.null(ref)) return(descriptor)
  artifact <- DBI::dbGetQuery(bundle$con,
    "SELECT provenance_snapshot_id FROM artifacts WHERE artifact_id=?;",
    params = list(ref$artifact_id))
  if (nrow(artifact) != 1L) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "Artifact-backed input is absent or ambiguous.", "resolution")
  snapshot_id <- .wb_operation_pack_v3_scalar_db(
    artifact$provenance_snapshot_id)
  output <- DBI::dbGetQuery(bundle$con, paste0(
    "SELECT content_identity_scheme,content_sha256,verification_status ",
    "FROM prov_run_outputs WHERE snapshot_id=? AND artifact_id=?;"),
    params = list(snapshot_id, ref$artifact_id))
  if (nrow(output) != 1L || !identical(as.character(
      output$verification_status[[1]]), "content_verified"))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Artifact-backed input lacks one content-verified producer output.",
      "resolution")
  stored <- list(scheme = .wb_operation_pack_v3_scalar_db(
    output$content_identity_scheme), sha256 = .wb_operation_pack_v3_scalar_db(
      output$content_sha256))
  source_value <- tryCatch(wb_art_load(bundle, ref$artifact_id,
    expected_kind = as.character(value$kind)[1]), error = identity)
  observed <- if (inherits(source_value, "error")) source_value else
    tryCatch(.wb_prov_payload_identity(bundle, source_value), error = identity)
  if (inherits(observed, "error") ||
      !identical(as.character(observed$verification_status)[1],
        "content_verified") ||
      !identical(stored, list(
        scheme = as.character(observed$content_identity_scheme)[1],
        sha256 = as.character(observed$content_sha256)[1])))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Artifact-backed input does not match its durable producer identity.",
      "resolution")
  cells <- .wb_operation_pack_v3_distinct_first(
    .wb_operation_pack_v2_primitive_cells(value))
  projected <- tryCatch(.wb_operation_pack_v2_bind_inputs(bundle,
    list(source = source_value), cells)$source, error = identity)
  if (inherits(projected, "error") ||
      !identical(unclass(projected), unclass(value)))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Bound input is not the authenticated projection of its artifact source.",
      "resolution")
  descriptor
}

.wb_operation_pack_v3_scalar_db <- function(x, nullable = FALSE) {
  value <- if (length(x)) as.character(x[[1]]) else NA_character_
  if (is.na(value) || !nzchar(value)) {
    if (nullable) return(NULL)
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Required provenance field is empty.", "resolution")
  }
  value
}

.wb_operation_pack_v3_head_snapshot <- function(row) {
  heads <- tryCatch(jsonlite::fromJSON(as.character(
    row$head_run_ids_json[[1]]), simplifyVector = FALSE), error = identity)
  if (inherits(heads, "error") || !is.list(heads) ||
      any(!vapply(heads, is.character, logical(1))))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Producer provenance head has invalid ordered run IDs.", "resolution")
  value <- list(snapshot_id = .wb_operation_pack_v3_scalar_db(row$snapshot_id),
    schema_version = .wb_operation_pack_v3_scalar_db(row$schema_version),
    head_run_ids = unname(heads), n_runs = as.integer(row$n_runs[[1]]),
    n_artifacts = as.integer(row$n_artifacts[[1]]),
    commit_id = .wb_operation_pack_v3_scalar_db(row$commit_id, TRUE),
    replay_status = .wb_operation_pack_v3_scalar_db(row$replay_status, TRUE))
  if (is.na(value$n_runs) || value$n_runs < 0L || is.na(value$n_artifacts) ||
      value$n_artifacts < 0L) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "Producer provenance head counts are invalid.", "resolution")
  value$source_snapshot_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.provenance.snapshot_head.v1",
    "snapshot head excluding source_snapshot_identity", value)
  value
}

.wb_operation_pack_v3_lifecycle_snapshot <- function(con, artifact_id) {
  life <- DBI::dbGetQuery(con,
    "SELECT * FROM entity_lifecycle WHERE entity_kind='artifact' AND entity_id=?;",
    params = list(artifact_id))
  if (nrow(life) != 1L) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "Artifact ancestry requires one durable lifecycle row.", "resolution")
  edges <- DBI::dbGetQuery(con, paste0(
    "SELECT successor_kind,successor_id,predecessor_kind,predecessor_id,relationship_type ",
    "FROM entity_supersessions WHERE (successor_kind='artifact' AND successor_id=?) ",
    "OR (predecessor_kind='artifact' AND predecessor_id=?);"),
    params = list(artifact_id, artifact_id))
  edge_values <- lapply(seq_len(nrow(edges)), function(i) list(
    successor_kind = as.character(edges$successor_kind[[i]]),
    successor_id = as.character(edges$successor_id[[i]]),
    predecessor_kind = as.character(edges$predecessor_kind[[i]]),
    predecessor_id = as.character(edges$predecessor_id[[i]]),
    relationship_type = as.character(edges$relationship_type[[i]])))
  edge_key <- function(x) paste(unlist(x, use.names = FALSE), collapse = "\034")
  incoming <- Filter(function(x) identical(x$successor_kind, "artifact") &&
    identical(x$successor_id, artifact_id), edge_values)
  outgoing <- Filter(function(x) identical(x$predecessor_kind, "artifact") &&
    identical(x$predecessor_id, artifact_id), edge_values)
  incoming <- incoming[order(vapply(incoming, edge_key, character(1)),
    method = "radix")]
  outgoing <- outgoing[order(vapply(outgoing, edge_key, character(1)),
    method = "radix")]
  tombstone <- DBI::dbGetQuery(con, paste0(
    "SELECT tombstone_state FROM entity_tombstones ",
    "WHERE entity_kind='artifact' AND entity_id=?;"), params = list(artifact_id))
  if (nrow(tombstone) > 1L) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "Artifact has ambiguous tombstone evidence.", "resolution")
  result <- list(state = as.character(life$lifecycle_state[[1]]),
    identity = list(scheme = .wb_operation_pack_v3_scalar_db(
      life$identity_scheme), sha256 = .wb_operation_pack_v3_scalar_db(
        life$identity_hash)),
    provenance_bound = as.integer(life$provenance_bound[[1]]),
    incoming_supersedes = unname(incoming),
    outgoing_superseded_by = unname(outgoing),
    tombstone_state = if (nrow(tombstone)) as.character(
      tombstone$tombstone_state[[1]]) else NULL)
  if (!identical(result$state, "current") ||
      !identical(result$provenance_bound, 1L) || length(outgoing) ||
      !is.null(result$tombstone_state) ||
      !grepl("^[0-9a-f]{64}$", result$identity$sha256))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Artifact ancestry requires a current provenance-bound nonsuperseded source.",
      "resolution")
  result
}

.wb_operation_pack_v3_artifact_ancestry <- function(bundle, declaration,
                                                     input_record, ref,
                                                     params = list()) {
  ref <- .wb_operation_pack_v3_artifact_ref(ref)
  if (is.null(ref)) return(NULL)
  artifact_id <- ref$artifact_id
  con <- bundle$con
  artifact <- DBI::dbGetQuery(con,
    "SELECT * FROM artifacts WHERE artifact_id=?;", params = list(artifact_id))
  if (nrow(artifact) != 1L) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "Artifact ancestry source is absent or ambiguous.", "resolution")
  snapshot_id <- .wb_operation_pack_v3_scalar_db(
    artifact$provenance_snapshot_id)
  output <- DBI::dbGetQuery(con, paste0(
    "SELECT * FROM prov_run_outputs WHERE snapshot_id=? AND artifact_id=?;"),
    params = list(snapshot_id, artifact_id))
  if (nrow(output) != 1L) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "Artifact producer output is absent or ambiguous in its recorded snapshot.",
    "resolution")
  if (!identical(as.character(output$verification_status[[1]]),
      "content_verified")) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "Artifact producer output is not content-verified.", "resolution")
  stored_content <- list(scheme = .wb_operation_pack_v3_scalar_db(
    output$content_identity_scheme), sha256 = .wb_operation_pack_v3_scalar_db(
      output$content_sha256))
  run_id <- .wb_operation_pack_v3_scalar_db(output$run_id)
  run <- DBI::dbGetQuery(con,
    "SELECT * FROM prov_runs WHERE snapshot_id=? AND run_id=?;",
    params = list(snapshot_id, run_id))
  if (nrow(run) != 1L) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "Artifact producer run is absent or ambiguous.", "resolution")
  head <- DBI::dbGetQuery(con,
    "SELECT * FROM prov_heads WHERE snapshot_id=?;", params = list(snapshot_id))
  if (nrow(head) != 1L) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "Artifact producer head is absent or ambiguous.", "resolution")
  source_snapshot <- .wb_operation_pack_v3_head_snapshot(head)
  if (!run_id %in% as.character(unlist(source_snapshot$head_run_ids,
      use.names = FALSE)) && !nrow(DBI::dbGetQuery(con,
      "SELECT 1 FROM prov_runs WHERE snapshot_id=? AND run_id=?;",
      params = list(snapshot_id, run_id))))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Artifact producer run is not present in the producer snapshot.",
      "resolution")
  lifecycle <- .wb_operation_pack_v3_lifecycle_snapshot(con, artifact_id)
  value <- list(schema = "scworkbench.artifact_ancestry.snapshot.v1",
    attestation_name = as.character(declaration$name)[1],
    input_name = as.character(declaration$input)[1],
    input_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
      input_record$descriptor_identity),
    reference_kind = "promoted_artifact", artifact_id = artifact_id,
    artifact_type = as.character(artifact$type[[1]]),
    artifact_lineage_status = .wb_operation_pack_v3_scalar_db(
      artifact$lineage_status, TRUE), artifact_content_identity = stored_content,
    source_run_id = run_id,
    source_run_identity = list(scheme = .wb_operation_pack_v3_scalar_db(
      run$run_hash_scheme), sha256 = .wb_operation_pack_v3_scalar_db(run$run_hash)),
    source_snapshot_id = snapshot_id, source_snapshot = source_snapshot,
    source_output_name = .wb_operation_pack_v3_scalar_db(output$output_name),
    source_output_content_identity = stored_content, lifecycle = lifecycle)
  assertions <- declaration$parameter_assertions %||% list()
  expected <- list(artifact_id = artifact_id, run_id = run_id,
    snapshot_id = snapshot_id)
  for (field in names(assertions)) {
    parameter <- as.character(assertions[[field]])[1]
    supplied <- as.character(params[[parameter]] %||% "")[1]
    if (nzchar(supplied) && !identical(supplied, expected[[field]]))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        paste0("Artifact ancestry parameter assertion differs: ", field),
        "resolution")
  }
  value$snapshot_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.artifact_ancestry.snapshot.v1",
    "snapshot excluding snapshot_identity", value)
  value
}

.wb_operation_pack_v3_provenance_read_records <- function(bundle, operation,
    inputs, source_refs, input_records, params, stage_root) {
  records <- list(); values <- list()
  for (declaration in operation$provenance_reads %||% list()) {
    input_name <- as.character(declaration$input)[1]
    value <- .wb_operation_pack_v3_artifact_ancestry(bundle, declaration,
      input_records[[input_name]], source_refs[[input_name]], params)
    if (is.null(value)) next
    name <- as.character(declaration$name)[1]
    relative <- paste0("provenance_reads/", name, "/payload.json")
    path <- file.path(stage_root, relative)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    .wb_operation_pack_v2_atomic_json(value, path)
    manifest <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.payload_manifest.v2",
      list(path = relative,
        sha256 = .wb_operation_pack_v2_file_sha256(path)))
    descriptor <- list(
      schema = "scworkbench.operation_pack.provenance_read_descriptor.v1",
      name = name, category = "authenticated_core_provenance_snapshot",
      kind = "artifact_ancestry", reader = "read_artifact_ancestry",
      input_name = input_name,
      input_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
        input_records[[input_name]]$descriptor_identity),
      lifecycle_policy = "require_current",
      snapshot_identity = value$snapshot_identity,
      payload_manifest_identity = manifest)
    descriptor$descriptor_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.provenance_read_descriptor.v1",
      "descriptor excluding descriptor_identity", descriptor)
    records[[length(records) + 1L]] <- descriptor
    values[[name]] <- value
  }
  list(records = records, values = values)
}

.wb_operation_pack_v3_provenance_reads_assert_current <- function(bundle,
    operation, inputs, source_refs, request, params) {
  records <- request$provenance_reads %||% list()
  record_map <- stats::setNames(records, vapply(records, function(x)
    as.character(x$name)[1], character(1)))
  input_map <- stats::setNames(lapply(request$inputs, `[[`, "descriptor"),
    vapply(request$inputs, `[[`, character(1), "name"))
  expected_names <- character()
  for (declaration in operation$provenance_reads %||% list()) {
    input_name <- as.character(declaration$input)[1]
    ref <- .wb_operation_pack_v3_artifact_ref(source_refs[[input_name]])
    if (is.null(ref)) next
    name <- as.character(declaration$name)[1]
    expected_names <- c(expected_names, name)
    retained <- record_map[[name]]
    if (is.null(retained)) .wb_operation_pack_v3_error(
      "PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Artifact ancestry grant disappeared before publication.", "audit")
    rebound <- .wb_operation_pack_v3_bind_artifact_input_descriptor(bundle,
      ref, inputs[[input_name]], input_map[[input_name]])
    if (!identical(rebound$descriptor_identity,
        input_map[[input_name]]$descriptor_identity))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Artifact-backed input descriptor changed before publication.",
        "audit")
    observed <- .wb_operation_pack_v3_artifact_ancestry(bundle, declaration,
      rebound, ref, params)
    if (!identical(observed$snapshot_identity,
        retained$snapshot_identity))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        paste0("Artifact ancestry changed before publication for '", name,
          "' (expected ", retained$snapshot_identity$sha256,
          ", observed ", observed$snapshot_identity$sha256, ")."), "audit")
  }
  if (!identical(sort(names(record_map), method = "radix"),
      sort(expected_names, method = "radix")))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Artifact ancestry grants are not a bijection with declared sources.",
      "audit")
  invisible(TRUE)
}

.wb_operation_pack_v3_retained_provenance_assert_current <- function(bundle,
    request, path) {
  for (descriptor in request$provenance_reads %||% list()) {
    name <- as.character(descriptor$name)[1]
    payload <- file.path(path, "provenance_reads", name, "payload.json")
    if (!file.exists(payload)) .wb_operation_pack_v3_error(
      "PYBENCH_INPUT_IDENTITY_MISMATCH",
      paste0("Retained artifact ancestry payload is absent: ", name),
      "recipient")
    value <- tryCatch(jsonlite::read_json(payload, simplifyVector = FALSE),
      error = identity)
    if (inherits(value, "error")) .wb_operation_pack_v3_error(
      "PYBENCH_INPUT_IDENTITY_MISMATCH",
      paste0("Retained artifact ancestry payload is unreadable: ", name),
      "recipient")
    input_map <- stats::setNames(lapply(request$inputs, `[[`, "descriptor"),
      vapply(request$inputs, `[[`, character(1), "name"))
    input_name <- as.character(descriptor$input_name)[1]
    declaration <- list(name = name, input = input_name,
      parameter_assertions = list())
    observed <- .wb_operation_pack_v3_artifact_ancestry(bundle, declaration,
      input_map[[input_name]], value$artifact_id, list())
    if (!identical(observed$snapshot_identity,
        descriptor$snapshot_identity) ||
        !identical(observed$snapshot_identity, value$snapshot_identity))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        paste0("Retained artifact ancestry is no longer current: ", name),
        "recipient")
  }
  invisible(TRUE)
}

.wb_operation_pack_v3_provenance_observations <- function(request,
                                                           reader_calls) {
  lapply(request$provenance_reads %||% list(), function(item) {
    name <- as.character(item$name)[1]
    uses <- sum(vapply(reader_calls, function(x) identical(
      as.character(x$category %||% "")[1], "provenance_read") &&
      identical(as.character(x$name %||% "")[1], name), logical(1)))
    if (uses != 1L) .wb_operation_pack_v3_error(
      "PYBENCH_CAPABILITY_MISMATCH",
      paste0("Artifact ancestry reader '", name,
        "' must be consumed exactly once."), "execution")
    descriptor <- item
    value <- list(
      schema = "scworkbench.operation_pack.observed_provenance_read.v1",
      name = name, descriptor_identity =
        .wb_operation_pack_v3_unscoped_identity(
          descriptor$descriptor_identity),
      snapshot_identity = .wb_operation_pack_v3_unscoped_identity(
        descriptor$snapshot_identity),
      payload_manifest_identity = descriptor$payload_manifest_identity,
      use_count = 1L)
    value$observed_descriptor_identity <-
      .wb_operation_pack_v2_identity_scoped(
        "scworkbench.operation_pack.observed_provenance_read.v1",
        "observation excluding observed_descriptor_identity", value)
    value
  })
}

.wb_operation_pack_v3_capability_adapter <- function(request, operation,
    inputs, stage_root, bundle = NULL, registry_read_values = list(),
    provenance_read_values = list()) {
  base <- .wb_operation_pack_v2_capability_adapter(request, operation, inputs,
    stage_root, bundle = bundle, registry_read_values = registry_read_values)
  state <- base$state
  state$fragments <- list()
  provenance_readers <- stats::setNames(lapply(names(provenance_read_values),
    function(name) {
      force(name)
      function(...) {
        if (isTRUE(state$used) || length(list(...)))
          .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
            "Provenance readers are private, no-argument and single-use.",
            "execution")
        prior <- Filter(function(x) identical(x$category %||% "",
          "provenance_read") && identical(as.character(x$name)[1], name),
          state$reader_calls)
        if (length(prior)) .wb_operation_pack_v3_error(
          "PYBENCH_CAPABILITY_MISMATCH",
          paste0("Provenance reader '", name,
            "' was consumed more than once."), "execution")
        state$reader_calls[[length(state$reader_calls) + 1L]] <- list(
          category = "provenance_read", name = name)
        .wb_operation_pack_v2_deep_copy(provenance_read_values[[name]])
      }
    }), names(provenance_read_values))
  base$readers <- c(base$readers, provenance_readers)
  schedules <- request$chunk_schedules %||% list()
  schedule <- if (length(schedules)) schedules[[1]] else NULL
  fragment_output <- as.character(schedule$fragment_output %||% "")[1]
  summary_output <- as.character(schedule$summary_output %||% "")[1]
  original_terminal <- base$writers$write_terminal_primitive
  if (!is.null(schedule)) {
    base$writers$write_terminal_primitive <- function(name, value,
        semantic_metadata = list()) {
      if (as.character(name)[1] %in% c(fragment_output, summary_output))
        .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
          "Chunk terminals are adapter-owned; use write_chunk and the declared finalizer.",
          "execution")
      original_terminal(name, value, semantic_metadata)
    }
    base$writers$write_chunk <- function(name, index, value) {
      if (isTRUE(state$used)) .wb_operation_pack_v3_error(
        "PYBENCH_CAPABILITY_MISMATCH",
        "Capability has already been consumed.", "execution")
      name <- as.character(name)[1]; index <- as.integer(index)[1]
      if (!identical(name, fragment_output) || is.na(index) || index < 1L ||
          index > length(schedule$batches)) .wb_operation_pack_v3_error(
        "PYBENCH_CAPABILITY_MISMATCH",
        "Chunk writer name or batch index is outside the schedule.",
        "execution")
      key <- as.character(index)
      if (!is.null(state$fragments[[key]])) .wb_operation_pack_v3_error(
        "PYBENCH_RECEIPT_MISMATCH",
        "A scheduled chunk fragment was written more than once.", "receipt")
      .wb_assert_kind(value, "cell_vector_family",
        where = " for ABI v3 chunk fragment")
      observation <- .wb_operation_pack_v3_observe_fragment(value,
        schedule$batches[[index]]$fragment_grant, index)
      state$fragments[[key]] <- .wb_operation_pack_v2_deep_copy(value)
      invisible(list(name = name, index = index,
        fragment_grant_identity = schedule$batches[[index]]$
          fragment_grant$fragment_grant_identity,
        observed_fragment_identity = observation$observed_fragment_identity))
    }
  }
  base$v3 <- list(schedule = schedule, original_terminal = original_terminal,
    fragment_output = fragment_output, summary_output = summary_output)
  base
}

.wb_operation_pack_v3_finalizer_metadata <- function(definition, request,
                                                       params, source_refs) {
  outputs <- stats::setNames(request$outputs,
    vapply(request$outputs, `[[`, character(1), "name"))
  inputs <- stats::setNames(request$inputs,
    vapply(request$inputs, `[[`, character(1), "name"))
  values <- lapply(definition$metadata_sources, function(source) {
    kind <- as.character(source$source)[1]
    value <- switch(kind,
      resolved_key_axis = outputs[[as.character(source$output)[1]]]$
        descriptor$cardinality_grant$key_axis_resolution,
      normalized_parameter = params[[as.character(source$parameter)[1]]],
      input_reference = source_refs[[as.character(source$input)[1]]],
      input_descriptor = inputs[[as.character(source$input)[1]]]$descriptor,
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        paste0("Unknown finalizer metadata source: ", kind), "execution"))
    list(name = as.character(source$name)[1],
      value = .wb_operation_pack_v2_deep_copy(value))
  })
  metadata <- list(
    schema = "scworkbench.operation_pack.summary_finalizer_metadata.v1",
    finalizer_definition_identity =
      definition$finalizer_definition_identity, values = values)
  metadata$finalizer_metadata_identity <-
    .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.summary_finalizer_metadata.v1",
      "metadata excluding finalizer_metadata_identity", metadata)
  metadata
}

.wb_operation_pack_v3_fresh_finalizer <- function(registration, callable) {
  if (!identical(as.character(registration$identity$backend)[1], "R"))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "R finalizer resolution was requested for a non-R pack.", "execution")
  fresh <- .wb_operation_pack_v3_invoke(
    as.character(registration$manifest$package$name)[1],
    lib.loc = dirname(registration$installed_path))
  finalizer <- fresh$finalizers[[as.character(callable)[1]]]
  if (!is.function(finalizer) || !identical(names(formals(finalizer)),
      c("merged_family", "metadata")))
    .wb_operation_pack_v3_error("OPERATION_PACK_ENTRY_POINT_INVALID",
      "V3 pure finalizer must have formals merged_family, metadata.",
      "authentication")
  finalizer
}

.wb_operation_pack_v3_finalize_adapter <- function(adapter, request,
    registration, params, source_refs = list()) {
  schedule <- adapter$v3$schedule
  if (is.null(schedule)) return(NULL)
  fragments <- adapter$state$fragments
  if (length(fragments) != length(schedule$batches))
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "Not every scheduled chunk produced one fragment.", "receipt")
  merged <- .wb_operation_pack_v3_merge_fragments(fragments, schedule)
  definition <- schedule$summary_finalizer_definition
  metadata <- .wb_operation_pack_v3_finalizer_metadata(definition, request,
    params, source_refs)
  finalizer <- .wb_operation_pack_v3_fresh_finalizer(registration,
    definition$callable)
  summary <- tryCatch(finalizer(
    merged_family = .wb_operation_pack_v2_deep_copy(merged$value),
    metadata = .wb_operation_pack_v2_deep_copy(metadata)), error = identity)
  if (inherits(summary, "error")) .wb_operation_pack_v3_error(
    "PYBENCH_PROCESS_FAILED",
    paste0("Fresh ABI v3 summary finalizer failed: ",
      conditionMessage(summary)), "execution")
  .wb_assert_kind(summary, "obs_table", where = " for ABI v3 summary finalizer")
  adapter$v3$original_terminal(schedule$fragment_output, merged$value)
  adapter$v3$original_terminal(schedule$summary_output, summary)
  merged_identity <- .wb_operation_pack_v2_identity_plain(
    "scworkbench.cell_vector_family.content.v1", unclass(merged$value))
  summary_identity <- .wb_operation_pack_v2_identity_plain(
    "scworkbench.obs_table.content.v1", unclass(summary))
  invocation <- list(
    schema = "scworkbench.operation_pack.summary_finalizer_invocation.v1",
    finalizer_definition_identity = definition$finalizer_definition_identity,
    merged_family_content_identity = merged_identity,
    finalizer_metadata_identity = metadata$finalizer_metadata_identity,
    summary_content_identity = summary_identity)
  invocation$finalizer_invocation_identity <-
    .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.summary_finalizer_invocation.v1",
      "invocation excluding finalizer_invocation_identity", invocation)
  list(schedule = schedule, observations = merged$observations,
    merged = merged$value, summary = summary,
    metadata = metadata, invocation = invocation)
}

.wb_operation_pack_v3_runner <- function(op_name) {
  force(op_name)
  function(bundle, resolved, effective_cells, inputs, ...) {
    binding <- bundle$pybench_session_binding %||% list()
    source_refs <- inputs[names(resolved)]
    bound <- .wb_operation_pack_v2_bind_inputs(bundle, resolved,
      effective_cells)
    attr(bound, "operation_pack_v3_source_refs") <- source_refs
    all_inputs <- inputs
    params <- inputs[setdiff(names(inputs), c(names(resolved),
      names(.wb_op_engine_input_specs())))]
    definition <- .wb_operation_pack_registry$operations[[op_name]]$definition
    operation <- definition$v3_definition
    mutation_context <- .wb_current_mutation_context(bundle$con, bundle$dir)
    .wb_operation_pack_assert(!is.null(mutation_context) &&
        identical(as.character(mutation_context$route)[1],
          "session_execution") && nzchar(as.character(
            mutation_context$run_id %||% "")[1]),
      "PYBENCH_CAPABILITY_MISMATCH",
      "ABI v3 execution requires a preallocated session run.",
      phase = "execution", class = "wb_operation_pack_v3_error")
    params <- .wb_operation_pack_v2_bind_parameters(bundle, operation,
      params, bound, effective_cells)
    result <- .wb_operation_pack_v2_execute(bundle, op_name, bound,
      params = params, session_id = binding$session_id %||% NULL,
      run_id = as.character(mutation_context$run_id)[1],
      checkpoint_generation = binding$checkpoint_generation %||% "ephemeral",
      effective_cells = effective_cells)
    returned_params <- .wb_operation_pack_v2_retained_parameters(operation,
      all_inputs, params, bound, result$outputs)
    if (!is.null(result$reader_observation)) {
      observation <- result$reader_observation
      returned_params$chunking <- list(
        enabled = observation$observed_call_count > 1L,
        axis = observation$axis,
        chunk_size = observation$requested_chunk_size,
        n_chunks = observation$observed_call_count,
        requested_chunk_size = observation$requested_chunk_size,
        observed_call_count = observation$observed_call_count,
        observed_batch_sizes = observation$observed_batch_sizes,
        observed_batches = observation$observed_batches)
    }
    registry_requests <- tryCatch(
      .wb_operation_pack_v2_stage_registry_requests(bundle, result),
      error = function(error) {
        if (dir.exists(result$path)) unlink(result$path, recursive = TRUE,
          force = TRUE)
        stop(error)
      })
    list(outputs = result$outputs, params = returned_params,
      operation_pack_runtime = result$receipt$runtime_attestation,
      operation_pack_transition = list(transition_id = result$transition_id,
        receipt_identity = result$receipt$receipt_identity),
      operation_pack_registry_requests = registry_requests)
  }
}
