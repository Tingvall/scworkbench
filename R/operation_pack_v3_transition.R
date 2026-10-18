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
                                                        effective_cells = NULL,
                                                        registry_records = list()) {
  source <- as.character(policy$cell_axis$source)[1]
  if (identical(source, "session_cell_axis_read_v1")) {
    read_name <- as.character(policy$cell_axis$registry_read)[1]
    record <- registry_records[[read_name]]
    descriptor <- record$descriptor %||% list()
    cells <- as.character(effective_cells %||% character())
    observed <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", unname(as.list(cells)))
    if (!length(cells) || anyDuplicated(cells) ||
        !identical(as.character(descriptor$kind %||% "")[1],
          "session_cell_axis") ||
        !identical(observed, descriptor$cell_order_identity))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Session-cell output axis differs from its authenticated core snapshot.",
        "resolution")
    return(list(input_name = NULL, registry_read = read_name, cells = cells,
      derivation = source, descriptor = descriptor))
  }
  input_name <- as.character(policy$cell_axis$input)[1]
  value <- inputs[[input_name]]
  if (is.null(value)) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    paste0("Authenticated cell-axis input is absent: ", input_name),
    "resolution")
  available <- .wb_operation_pack_v3_distinct_first(
    .wb_operation_pack_v2_primitive_cells(value))
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

.wb_operation_pack_v3_declared_prefix_key_axis <- function(spec, params) {
  base_keys <- as.character(unlist(spec$keys, use.names = FALSE))
  parameter <- as.character(spec$prefix_parameter)[1]
  prefix <- as.character(params[[parameter]] %||% "")[1]
  keys <- paste0(prefix, base_keys)
  resolution <- list(source = "declared_keys_with_optional_prefix_v1",
    base_keys = unname(as.list(base_keys)), prefix_parameter = parameter,
    prefix_value = prefix, keys = unname(as.list(keys)))
  list(keys = keys, resolution = resolution)
}

.wb_operation_pack_v3_cardinality_grant <- function(policy, output,
                                                      inputs, params,
                                                      input_records,
                                                      effective_cells = NULL,
                                                      registry_records = list()) {
  cell_axis <- .wb_operation_pack_v3_effective_cell_axis(policy, inputs,
    effective_cells, registry_records)
  shape <- as.character(policy$shape)[1]
  input_record <- if (is.null(cell_axis$input_name)) NULL else
    input_records[[cell_axis$input_name]]
  value <- list(
    schema = "scworkbench.operation_pack.output_cardinality_grant.v1",
    output = as.character(output$name)[1], kind = as.character(output$kind)[1],
    policy = "authenticated_output_axes_v1", shape = shape,
    row_order = as.character(policy$row_order)[1],
    missing_values = as.character(policy$missing_values)[1],
    cell_axis_source = if (!is.null(cell_axis$registry_read)) list(
      source = cell_axis$derivation,
      registry_read = cell_axis$registry_read,
      descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
        cell_axis$descriptor$descriptor_identity),
      selection_identity = cell_axis$descriptor$selection_identity) else list(
        input_name = cell_axis$input_name,
        input_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
          input_record$descriptor_identity), derivation = cell_axis$derivation),
    cell_axis_count = as.integer(length(cell_axis$cells)),
    cell_axis_order_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", unname(as.list(cell_axis$cells))))
  keys <- character()
  if (shape %in% c("cell_key_cartesian",
      "bounded_grouped_cell_key_cartesian")) {
    spec <- policy$key_axis
    bounded <- identical(as.character(spec$source)[1],
      "declared_bounded_key_groups_v1")
    key_state <- if (bounded) list(keys = character(), resolution = list(
      source = "declared_bounded_key_groups_v1",
      required_keys = spec$required_keys,
      optional_groups = spec$optional_groups,
      selection_owner = spec$selection_owner,
      group_order = spec$group_order)) else if (identical(as.character(spec$source)[1],
        "resolved_parameter_feature_groups_v1"))
      .wb_operation_pack_v3_parameter_key_axis(spec, inputs, params,
        input_records) else if (identical(as.character(spec$source)[1],
          "declared_keys_with_optional_prefix_v1"))
        .wb_operation_pack_v3_declared_prefix_key_axis(spec, params) else
        .wb_operation_pack_v3_input_key_axis(spec, inputs, params,
          input_records)
    keys <- key_state$keys
    if (length(keys) && length(cell_axis$cells) >
        floor(.Machine$integer.max / length(keys)))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Authenticated output cardinality overflows the integer boundary.",
        "resolution")
    pairs <- unlist(lapply(keys, function(key) lapply(cell_axis$cells,
      function(cell) list(key = key, cell_id = cell))), recursive = FALSE)
    if (bounded) {
      required <- as.character(unlist(spec$required_keys, use.names = FALSE))
      optional <- unlist(lapply(spec$optional_groups, function(x)
        as.character(unlist(x$keys, use.names = FALSE))), use.names = FALSE)
      value$minimum_key_count <- as.integer(length(required))
      value$maximum_key_count <- as.integer(length(c(required, optional)))
      value$minimum_row_count <- as.integer(length(required) * length(cell_axis$cells))
      value$maximum_row_count <- as.integer(length(c(required, optional)) * length(cell_axis$cells))
    } else {
      value$key_axis_count <- as.integer(length(keys))
      value$key_axis <- unname(as.list(keys))
    }
    value$key_axis_resolution <- key_state$resolution
    if (!bounded) {
      value$key_axis_order_identity <- .wb_operation_pack_v2_identity_plain(
        "scworkbench.row_order.v1", unname(as.list(keys)))
      value$expected_row_count <- as.integer(length(keys) * length(cell_axis$cells))
      value$row_order_identity <- .wb_operation_pack_v2_identity_plain(
        "scworkbench.row_order.v1", pairs)
    }
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
  if (shape %in% c("cell_key_cartesian",
      "bounded_grouped_cell_key_cartesian")) {
    key <- as.character(value$key %||% character())
    expected_cells <- attr(grant, "operation_pack_v3_cells") %||%
      rep(NA_character_, as.integer(grant$cell_axis_count))
    bounded <- identical(shape, "bounded_grouped_cell_key_cartesian")
    observed_keys <- .wb_operation_pack_v3_distinct_first(key)
    selected_groups <- character()
    expected_keys <- if (bounded) {
      resolution <- grant$key_axis_resolution
      required <- as.character(unlist(resolution$required_keys,
        use.names = FALSE))
      groups <- resolution$optional_groups %||% list()
      cursor <- length(required) + 1L
      for (group in groups) {
        group_keys <- as.character(unlist(group$keys, use.names = FALSE))
        if (length(observed_keys) >= cursor &&
            identical(observed_keys[cursor:min(length(observed_keys),
              cursor + length(group_keys) - 1L)], group_keys)) {
          selected_groups <- c(selected_groups, as.character(group$name)[1])
          cursor <- cursor + length(group_keys)
        }
      }
      expected <- c(required, unlist(lapply(groups[vapply(groups,
        function(x) as.character(x$name)[1] %in% selected_groups,
        logical(1))], function(x) as.character(unlist(x$keys,
          use.names = FALSE))), use.names = FALSE))
      if (!identical(observed_keys, expected))
        .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
          "Cell-vector-family keys are not complete declared bounded groups in manifest order.",
          "audit")
      expected
    } else as.character(unlist(grant$key_axis, use.names = FALSE))
    expected_pairs <- unlist(lapply(expected_keys, function(k) lapply(expected_cells,
        function(cell) list(key = k, cell_id = cell))), recursive = FALSE)
    observed_pairs <- unname(Map(function(k, cell) list(key = k,
      cell_id = cell), key, cell_id))
    expected_row_count <- length(expected_keys) * length(expected_cells)
    if (length(key) != expected_row_count ||
        anyDuplicated(paste(key, cell_id, sep = "\034")) ||
        !identical(observed_pairs, expected_pairs))
      .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
        "Cell-vector-family rows are not the exact granted Cartesian product in key-major order.",
        "audit")
    observed_cells <- .wb_operation_pack_v3_distinct_first(cell_id)
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
    if (bounded) {
      out$observed_key_axis <- unname(as.list(observed_keys))
      out$selected_optional_groups <- unname(as.list(selected_groups))
      out$selected_optional_groups_identity <-
        .wb_operation_pack_v2_identity_plain(
          "scworkbench.operation_pack.selected_optional_groups.v1",
          out$selected_optional_groups)
    }
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

.wb_operation_pack_v3_axis_manifest <- function(axis, ids, name, stage_root) {
  ids <- as.character(ids)
  if (anyNA(ids) || any(!nzchar(ids)) || anyDuplicated(ids))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      paste0("Typed-slice ", axis, " selection is invalid."), "resolution")
  value <- list(schema =
      "scworkbench.operation_pack.typed_slice_axis_manifest.v1",
    axis = axis, count = as.integer(length(ids)), ids = unname(as.list(ids)),
    order_identity = .wb_operation_pack_v2_identity_plain(
      if (axis == "cells") "scworkbench.cell_order.v1" else
        "scworkbench.feature_order.v1", unname(as.list(ids))))
  value$manifest_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.typed_slice_axis_manifest.v1",
    "axis manifest excluding manifest_identity", value)
  relative <- paste0("typed_slice_axes/", name, "/", axis, ".json")
  path <- file.path(stage_root, relative)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  .wb_operation_pack_v3_atomic_canonical_json(value, path)
  descriptor <- list(axis = axis, count = as.integer(length(ids)),
    order_identity = value$order_identity,
    axis_manifest_identity = value$manifest_identity,
    relative_path = relative,
    payload_manifest_identity = .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.payload_manifest.v2",
      "registry read payload manifest", list(path = relative,
        size = as.numeric(file.info(path)$size),
        sha256 = .wb_operation_pack_v2_file_sha256(path))))
  list(value = value, descriptor = descriptor)
}

.wb_operation_pack_v3_atomic_canonical_json <- function(value, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- paste0(path, ".tmp-", .wb_allocate_identifier("", 12L,
    purpose = "operation-pack v3 canonical JSON publication"))
  on.exit(if (file.exists(temporary)) unlink(temporary, force = TRUE),
    add = TRUE)
  writeBin(charToRaw(.wb_operation_pack_canonical_json(value)), temporary)
  if (!file.rename(temporary, path))
    .wb_operation_pack_v3_error("PYBENCH_PUBLICATION_FAILED",
      paste0("Could not publish canonical ", basename(path), "."),
      "staging")
  invisible(path)
}

.wb_operation_pack_v3_axis_selection <- function(spec, axis, input, params,
                                                   effective_cells) {
  available <- if (axis == "cells") as.character(effective_cells %||%
    input$cell_id %||% character()) else as.character(input$feature_id %||%
      character())
  policy <- as.character(spec$policy)[1]
  if (identical(policy, "effective_input_axis_v1")) return(available)
  if (!identical(policy, "parameter_ordered_subset_v1"))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Unknown typed-slice axis selection policy.", "resolution")
  selected <- params[[as.character(spec$parameter)[1]]]
  if (!is.list(selected) && !is.character(selected))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Typed-slice selector parameter must be a flat string array.",
      "resolution")
  selected <- as.character(unlist(selected, use.names = FALSE))
  if (anyNA(selected) || any(!nzchar(selected)) || anyDuplicated(selected) ||
      length(setdiff(selected, available)))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Typed-slice selector is duplicate, empty, or outside the input axis.",
      "resolution")
  selected
}

.wb_operation_pack_v3_atomic_matrix_market <- function(values, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  temporary <- paste0(path, ".pending")
  if (file.exists(temporary)) unlink(temporary, force = TRUE)
  on.exit(unlink(temporary, force = TRUE), add = TRUE)
  if (!.wb_operation_pack_v3_matrix_market_standard(values)) {
    # Preserve historical coercion for exotic inputs, without claiming that
    # their own as.matrix methods are bounded or free of side effects.
    values <- as.matrix(values)
    storage.mode(values) <- "double"
    if (is.object(values)) {
      # An exotic as.matrix method can retain custom scalar/subset behavior.
      # Preserve the historical whole-object encoder for that unsupported case;
      # changing its dispatch to bounded block subsetting could change values.
      if (any(!is.finite(values))) .wb_operation_pack_v3_error(
        "PYBENCH_CAPABILITY_MISMATCH",
        "Typed-slice Matrix Market values must be finite.", "staging")
      indices <- which(values != 0, arr.ind = TRUE)
      if (length(indices)) indices <- indices[order(indices[, 2L], indices[, 1L]), , drop = FALSE]
      entries <- if (!nrow(indices)) character() else
        vapply(seq_len(nrow(indices)), function(i) paste(
          as.integer(indices[i, 1L]), as.integer(indices[i, 2L]),
          .wb_operation_pack_canonical_number(.wb_operation_pack_number_token(
            values[indices[i, 1L], indices[i, 2L]]))), character(1))
      lines <- c("%%MatrixMarket matrix coordinate real general",
        paste(nrow(values), ncol(values), nrow(indices)), entries)
      writeBin(charToRaw(paste0(paste(lines, collapse = "\n"), "\n")), temporary)
      if (!file.rename(temporary, path)) .wb_operation_pack_v3_error(
        "PYBENCH_CAPABILITY_MISMATCH",
        "Could not atomically stage a typed-slice private source.", "staging")
      return(invisible(path))
    }
  }
  dimensions <- dim(values)
  limit <- as.numeric(getOption("scworkbench.max_dense_materialize_mb", 256)) * 1024^2
  .wb_assert(length(limit) == 1L && is.finite(limit) && limit > 8192,
    "Private matrix staging requires a valid dense materialization budget.")
  # Conservative allowance for subsetting, dense/double coercion and fallback
  # token carriers. Native output uses a fixed 4096-byte buffer. Very tall
  # matrices use row blocks within one column, preserving column-major order.
  elements <- max(1, floor((min(limit, 32 * 1024^2) - 8192) / 64))
  rows_per_block <- max(1, min(dimensions[[1L]], elements))
  columns_per_block <- max(1, min(128L, floor(elements / rows_per_block)))
  visit <- function(emit) {
    if (!all(dimensions > 0L)) return(invisible(NULL))
    if (isS4(values)) {
      # General CSC slots are already column-major and strictly row-ordered.
      # Matrix's two-dimensional `[` allocates source-height workspaces even
      # for tiny slices; never dispatch it or normalize the whole CSC here.
      pointers <- values@p
      indices <- values@i
      payload <- if (methods::is(values, "nMatrix")) NULL else values@x
      .wb_assert(length(pointers) == dimensions[[2L]] + 1 &&
        pointers[[1L]] == 0L && !is.na(pointers[[length(pointers)]]) &&
        pointers[[length(pointers)]] >= 0L && pointers[[length(pointers)]] <= length(indices) &&
        (is.null(payload) || length(payload) == length(indices)),
        "Invalid general CSC Matrix Market source slots.")
      column <- 1
      while (column <= dimensions[[2L]]) {
        first <- as.double(pointers[[column]]) + 1
        last <- as.double(pointers[[column + 1L]])
        .wb_assert(!is.na(first) && !is.na(last) && first >= 1 &&
          last >= first - 1 && last <= length(indices),
          "Invalid general CSC Matrix Market column pointers.")
        previous <- -1L
        while (first <= last) {
          selected <- seq.int(first, min(last, first + min(8192, elements) - 1))
          rows <- indices[selected]
          .wb_assert(!anyNA(rows) && all(rows >= 0L & rows < dimensions[[1L]]) &&
            rows[[1L]] > previous && !is.unsorted(rows, strictly = TRUE),
            "Invalid general CSC Matrix Market row order.")
          previous <- rows[[length(rows)]]
          block <- matrix(if (is.null(payload)) rep(1, length(selected)) else
            as.double(payload[selected]), ncol = 1L)
          emit(block, 0L, column - 1L, rows)
          first <- first + length(selected)
        }
        column <- column + 1L
      }
      return(invisible(NULL))
    }
    for (column in seq.int(1L, dimensions[[2L]], by = columns_per_block)) {
      columns <- seq.int(column, min(dimensions[[2L]], column + columns_per_block - 1L))
      for (row in seq.int(1L, dimensions[[1L]], by = rows_per_block)) {
        rows <- seq.int(row, min(dimensions[[1L]], row + rows_per_block - 1L))
        block <- as.matrix(values[rows, columns, drop = FALSE])
        storage.mode(block) <- "double"
        emit(block, row - 1L, column - 1L, NULL)
      }
    }
  }
  count <- 0
  range_error <- NULL
  visit(function(block, row, column, indices) {
    observation <- .Call(C_scwb_matrix_market_block, NULL, block, row, column)
    if (!observation[[2L]]) .wb_operation_pack_v3_error(
      "PYBENCH_CAPABILITY_MISMATCH",
      "Typed-slice Matrix Market values must be finite.", "staging")
    # Keep the existing typed range diagnostics (including rounding into the
    # accepted exponent range), rather than replacing them with a C error.
    if (observation[[3L]] && is.null(range_error))
      for (x in block[block != 0 & abs(block) < 1e-307]) {
        error <- tryCatch({
          .wb_operation_pack_canonical_number(.wb_operation_pack_number_token(x))
          NULL
        }, error = identity)
        if (!is.null(error)) { range_error <<- error; break }
      }
    count <<- count + observation[[1L]]
  })
  if (!is.null(range_error)) stop(range_error)
  header <- paste0("%%MatrixMarket matrix coordinate real general\n",
    paste(dimensions[[1L]], dimensions[[2L]], sprintf("%.0f", count)), "\n")
  writeBin(charToRaw(header), temporary)
  native <- identical(getOption("OutDec", "."), ".") &&
    identical(Sys.localeconv()[["decimal_point"]], ".")
  visit(function(block, row, column, indices) {
    if (native && !is.null(indices))
      .Call(C_scwb_matrix_market_sparse, temporary, indices, as.double(block), column + 1L)
    else if (native) .Call(C_scwb_matrix_market_block, temporary, block, row, column)
    else {
      # Locale-sensitive historical diagnostics remain authoritative.
      coordinates <- which(block != 0, arr.ind = TRUE)
      lines <- vapply(seq_len(nrow(coordinates)), function(i) paste(
        if (is.null(indices)) row + coordinates[i, 1L] else indices[[coordinates[i, 1L]]] + 1L,
        column + coordinates[i, 2L],
        .wb_operation_pack_canonical_number(.wb_operation_pack_number_token(
          block[coordinates[i, 1L], coordinates[i, 2L]]))), character(1))
      if (length(lines)) {
        con <- file(temporary, "ab")
        tryCatch(writeBin(charToRaw(paste0(paste(lines, collapse = "\n"), "\n")), con),
          finally = close(con))
      }
    }
  })
  if (!file.rename(temporary, path)) {
    unlink(temporary, force = TRUE)
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Could not atomically stage a typed-slice private source.", "staging")
  }
  invisible(path)
}

.wb_operation_pack_v3_matrix_market_standard <- function(values) {
  if (is.matrix(values) && !is.object(values) &&
      typeof(values) %in% c("double", "integer", "logical")) return(TRUE)
  if (!isS4(values) || length(class(values)) != 1L) return(FALSE)
  name <- as.character(class(values))[[1L]]
  if (!name %in% c("dgCMatrix", "lgCMatrix", "ngCMatrix")) return(FALSE)
  definition <- methods::getClassDef(name,
    where = asNamespace("Matrix"))
  !is.null(definition) && identical(definition@package, "Matrix")
}

.wb_operation_pack_v3_matrix_market_projection <- function(values, rows, columns) {
  .wb_assert(.wb_operation_pack_v3_matrix_market_standard(values) && isS4(values) &&
    is.numeric(rows) && is.numeric(columns) &&
    !anyNA(rows) && !anyNA(columns) && !anyDuplicated(rows) && !anyDuplicated(columns) &&
    all(rows == floor(rows)) && all(columns == floor(columns)) &&
    all(rows >= 1 & rows <= nrow(values)) && all(columns >= 1 & columns <= ncol(values)),
    "Invalid general CSC private projection axes.")
  order <- order(rows, method = "radix")
  selected <- .Call(C_scwb_matrix_market_projection, values@p, values@i,
    if (methods::is(values, "nMatrix")) NULL else values@x,
    values@Dim, as.integer(rows[order] - 1L), as.integer(order - 1L),
    as.integer(columns - 1L))
  fields <- list(Class = as.character(class(values))[[1L]],
    Dim = as.integer(c(length(rows), length(columns))),
    Dimnames = list(if (is.null(rownames(values))) NULL else rownames(values)[rows],
      if (is.null(colnames(values))) NULL else colnames(values)[columns]),
    p = selected$p, i = selected$i)
  if (!is.null(selected$x)) fields$x <- selected$x
  do.call(methods::new, fields)
}

.wb_operation_pack_v3_typed_slice_grant <- function(bundle, declaration, input,
    input_record, params, effective_cells, transition_source_state_identity,
    stage_root) {
  name <- as.character(declaration$name)[1]
  cells <- .wb_operation_pack_v3_axis_selection(
    declaration$selection$cells, "cells", input, params, effective_cells)
  features <- .wb_operation_pack_v3_axis_selection(
    declaration$selection$features, "features", input, params,
    effective_cells)
  empty <- !length(cells) || !length(features)
  if (empty && identical(as.character(declaration$empty_selection_policy)[1],
      "reject")) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "Typed-slice selection is empty under reject policy.", "resolution")
  cell_axis <- .wb_operation_pack_v3_axis_manifest("cells", cells, name,
    stage_root)
  feature_axis <- .wb_operation_pack_v3_axis_manifest("features", features,
    name, stage_root)
  chunk_axis <- as.character(declaration$chunk_axis)[1]
  requested <- as.integer(params[[as.character(
    declaration$chunk_size_parameter)[1]]])[1]
  if (is.na(requested) || requested < 1L)
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Typed-slice chunk size must be positive.", "resolution")
  max_rows <- if (chunk_axis == "features") min(requested,
    length(features)) else length(features)
  max_columns <- if (chunk_axis == "cells") min(requested,
    length(cells)) else length(cells)
  product <- as.double(max_rows) * as.double(max_columns)
  if (!is.finite(product) || product > 9007199254740991)
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Typed-slice element limit overflows JSON-safe integer arithmetic.",
      "resolution")
  input_id <- .wb_operation_pack_v3_unscoped_identity(
    input_record$descriptor_identity)
  content_id <- input_record$content_identity
  matrix_id <- as.character(input$matrix_id %||% "")[1]
  value_policy <- as.character(declaration$value_policy %||% "")[1]
  if (identical(value_policy, "nonnegative_integer_v1") && nzchar(matrix_id)) {
    info <- wb_matrices(bundle)
    row <- info[as.character(info$matrix_id) == matrix_id, , drop = FALSE]
    if (nrow(row) != 1L) .wb_operation_pack_v3_error(
      "PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Count-like typed-slice input has no matrix registry row.",
      "resolution")
    layer <- tolower(as.character(row$layer[[1]] %||% ""))
    if (!identical(layer, "counts") ||
        grepl("log|norm|scale|cp10k|tfidf", tolower(matrix_id)))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Count-like typed-slice policy requires a counts layer and rejects normalized labels.",
        "resolution")
  }
  durable <- is.null(input$values) && nzchar(matrix_id) && nrow(DBI::dbGetQuery(bundle$con,
    "SELECT 1 FROM matrices WHERE matrix_id=? LIMIT 1;",
    params = list(matrix_id))) == 1L
  source <- list(schema =
      "scworkbench.operation_pack.typed_slice_source_reference.v1",
    input_name = as.character(declaration$input)[1],
    input_reference = if (durable) paste0("matrix:", matrix_id) else
      paste0("private_projection:", name),
    source_kind = if (durable) "bundle_matrix" else
      "in_memory_selected_projection")
  if (durable) {
    source$matrix_id <- matrix_id
  } else {
    selected <- input
    complete <- identical(features, as.character(input$feature_id)) &&
      identical(cells, as.character(input$cell_id))
    if (complete && .wb_operation_pack_v3_matrix_market_standard(input$values)) {
      selected$values <- input$values
    } else if (isS4(input$values) &&
        .wb_operation_pack_v3_matrix_market_standard(input$values)) {
      selected$values <- .wb_operation_pack_v3_matrix_market_projection(input$values,
        match(features, as.character(input$feature_id)),
        match(cells, as.character(input$cell_id)))
    } else {
      # Base selected objects retain their ordinary matrix contract. Unproved
      # classes retain one historical selection/coercion, not per-block work.
      selected$values <- as.matrix(input$values[
        match(features, as.character(input$feature_id)),
        match(cells, as.character(input$cell_id)), drop = FALSE])
    }
    selected$feature_id <- features
    selected$cell_id <- cells
    selected$dimensions <- as.integer(c(length(features), length(cells)))
    relative <- paste0("typed_slice_sources/", name, "/matrix.mtx")
    path <- file.path(stage_root, relative)
    .wb_operation_pack_v3_atomic_matrix_market(selected$values, path)
    source$private_source_payload_identity <-
      .wb_operation_pack_v2_identity_scoped(
        "scworkbench.operation_pack.payload_manifest.v2",
        "registry read payload manifest", list(path = relative,
          size = as.numeric(file.info(path)$size),
          sha256 = .wb_operation_pack_v2_file_sha256(path)))
    source$projected_content_identity <-
      .wb_operation_pack_v3_matrix_slice_content(selected$values,
        features, cells)
    projection <- list(schema =
        "scworkbench.operation_pack.typed_slice_source_projection.v1",
      original_input_content_identity = content_id,
      features_axis_manifest_identity =
        feature_axis$descriptor$axis_manifest_identity,
      cells_axis_manifest_identity = cell_axis$descriptor$axis_manifest_identity,
      projected_content_identity = source$projected_content_identity)
    projection$private_source_payload_identity <-
      source$private_source_payload_identity
    source$projection_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.typed_slice_source_projection.v1",
      "projection excluding projection_identity", projection)
  }
  source$input_descriptor_identity <- input_id
  source$input_content_identity <- content_id
  source$transition_source_state_identity <- transition_source_state_identity
  source$source_reference_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.typed_slice_source_reference.v1",
    "source reference excluding source_reference_identity", source)
  grant <- list(schema = "scworkbench.operation_pack.typed_slice_grant.v1",
    name = name, input_name = as.character(declaration$input)[1],
    kind = "matrix", reader = "read_typed_slices",
    input_descriptor_identity = input_id, input_content_identity = content_id,
    source_reference = source,
    supported_axes = declaration$supported_axes,
    chunk_axis = chunk_axis, cells_axis = cell_axis$descriptor,
    features_axis = feature_axis$descriptor,
    requested_chunk_size = requested,
    call_discipline = as.character(declaration$call_discipline)[1],
    empty_selection_policy = as.character(
      declaration$empty_selection_policy)[1], duplicate_policy = "reject",
    max_rows = as.integer(max_rows), max_columns = as.integer(max_columns),
    max_elements = product, max_control_bytes = 1048576L,
    max_response_bytes = 134217728L, max_outstanding_responses = 1L)
  if (nzchar(value_policy)) grant$value_policy <- value_policy
  grant$grant_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.typed_slice_grant.v1",
    "grant excluding grant_identity", grant)
  attr(grant, "operation_pack_v3_cells") <- cells
  attr(grant, "operation_pack_v3_features") <- features
  grant
}

.wb_operation_pack_v3_matrix_slice_content <- function(values, features,
                                                         cells) {
  # Bound conversion/coordinate work as well as the returned column block.
  # The canonical concatenation and global column ordinals are unchanged.
  allowance <- min(33554432, as.numeric(getOption(
    "scworkbench.max_dense_materialize_mb", 256)) * 1024^2 / 8)
  width <- max(1L, min(128L, floor(allowance / max(1, 64 * length(features)))))
  .wb_operation_pack_matrix_stream_identity(features, cells,
    function(columns) values[, columns, drop = FALSE], width)
}

.wb_operation_pack_v3_private_source_validate <- function(stage, grant,
    bounded = FALSE, return_reader = FALSE, budget = NULL, axes = NULL) {
  source <- grant$source_reference
  if (!identical(source$source_kind, "in_memory_selected_projection"))
    return(NULL)
  if (isTRUE(bounded)) {
    if (is.null(budget)) budget <-
      .wb_operation_pack_v3_broker_projection_budget(NULL)
    reader <- .wb_operation_pack_v3_private_stream_open(stage, grant, budget, axes = axes)
    if (isTRUE(return_reader)) return(reader)
    on.exit(reader$close(), add = TRUE)
    return(invisible(NULL))
  }
  # Explicit whole-object compatibility for private diagnostic/test callers.
  # Ordinary execution/revalidation requests the bounded path above.
  info <- .wb_operation_pack_v3_private_source_info(stage, grant)
  matrix <- tryCatch(methods::as(Matrix::readMM(info$path), "CsparseMatrix"),
    error = function(error) .wb_operation_pack_v3_error(
      "PYBENCH_INPUT_IDENTITY_MISMATCH",
      paste0("Typed-slice private projection is unreadable: ",
        conditionMessage(error)), "staging"))
  if (!identical(as.integer(dim(matrix)),
      as.integer(c(length(info$features), length(info$cells)))))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Typed-slice private projection dimensions differ from its axes.",
      "staging")
  projected <- .wb_operation_pack_v3_matrix_slice_content(matrix,
    info$features, info$cells)
  .wb_operation_pack_v3_private_projection_assert(grant, info, projected)
  matrix
}

.wb_operation_pack_v3_slice_result <- function(grant, ordinal, value) {
  features <- as.character(value$feature_id)
  cells <- as.character(value$cell_id)
  out <- list(schema = "scworkbench.operation_pack.typed_slice_result.v1",
    source_reference_identity = .wb_operation_pack_v3_unscoped_identity(
      grant$source_reference$source_reference_identity),
    grant_identity = .wb_operation_pack_v3_unscoped_identity(
      grant$grant_identity), ordinal = as.integer(ordinal),
    feature_count = as.integer(length(features)),
    feature_order_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.feature_order.v1", unname(as.list(features))),
    cell_count = as.integer(length(cells)),
    cell_order_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", unname(as.list(cells))),
    dimensions = list(as.integer(length(features)), as.integer(length(cells))),
    semantic_content_identity = .wb_operation_pack_v3_matrix_slice_content(
      value$values, features, cells))
  out$slice_result_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.typed_slice_result.v1",
    "slice result excluding slice_result_identity", out)
  out
}

.wb_operation_pack_v3_matrix_identity_bundle <- function(bundle, matrix_id) {
  source <- bundle$staging_source_bundle %||% NULL
  if (inherits(source, "scworkbench_bundle") &&
      nrow(DBI::dbGetQuery(source$con,
        "SELECT 1 FROM matrices WHERE matrix_id=? LIMIT 1;",
        params = list(as.character(matrix_id)[1]))) == 1L) source else bundle
}

.wb_operation_pack_v3_matrix_stage_tree_sha256 <- function(bundle, relative) {
  stage_root <- normalizePath(bundle$dir, winslash = "/", mustWork = TRUE)
  status <- .wb_path_status(stage_root, relative, expected_type = "directory",
    must_exist = TRUE, purpose = "typed-slice matrix fragment")
  .wb_assert(isTRUE(status$ok) &&
    .wb_path_inside(status$absolute, stage_root),
    "Typed-slice matrix fragment is outside its authenticated stage.")
  root <- status$absolute
  entries <- sort(as.character(fs::dir_ls(root, recurse = TRUE,
    type = "any", all = TRUE, follow = FALSE)), method = "radix")
  source <- bundle$staging_source_bundle %||% NULL
  rows <- lapply(entries, function(entry) {
    suffix <- substring(entry, nchar(root) + 2L)
    link <- Sys.readlink(entry)
    if (nzchar(link)) {
      .wb_assert(!dir.exists(entry) &&
        inherits(source, "scworkbench_bundle"),
        "Typed-slice matrix fragment contains an unauthorized link.")
      expected_relative <- file.path(relative, suffix)
      expected <- .wb_path_status(source$dir, expected_relative,
        expected_type = "file", must_exist = TRUE,
        purpose = "committed typed-slice matrix leaf")
      .wb_assert(isTRUE(expected$ok) &&
        identical(normalizePath(entry, winslash = "/", mustWork = TRUE),
          expected$absolute),
        "Typed-slice matrix fragment link differs from its committed leaf.")
    } else {
      .wb_assert(.wb_path_inside(normalizePath(entry, winslash = "/",
        mustWork = TRUE), root),
        "Typed-slice matrix fragment contains an escaped entry.")
    }
    if (dir.exists(entry)) return(NULL)
    list(path = suffix, sha256 = .wb_prov_sha256_file(entry))
  })
  .wb_prov_sha256_object(Filter(Negate(is.null), rows))
}

.wb_operation_pack_v3_matrix_consumed_identity <- function(bundle, matrix_id,
    phase = "audit") {
  tryCatch({
    frags <- wb_matrix_fragments(bundle, matrix_id)
    .wb_assert(nrow(frags) > 0L && "path" %in% names(frags),
      "Typed-slice matrix has no registered backing fragments.")
    rows <- lapply(seq_len(nrow(frags)), function(i) {
      columns <- intersect(c("matrix_id", "storage", "n_features",
        "n_cells", "feature_ids_json", "cell_ids_json", "source",
        "description"), names(frags))
      list(fragment = as.list(frags[i, columns, drop = FALSE]),
        payload_sha256 = .wb_operation_pack_v3_matrix_stage_tree_sha256(
          bundle, as.character(frags$path[[i]])))
    })
    list(content_identity_scheme = unname(
      .wb_content_identity_schemes()[["matrix"]]),
      content_sha256 = .wb_prov_sha256_object(list(kind = "matrix",
        matrix_id = matrix_id, fragments = rows)),
      verification_status = "content_verified")
  }, error = function(error) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    paste0("Typed-slice matrix source cannot be authenticated: ",
      conditionMessage(error)), phase))
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
  g3_input_names <- vapply(Filter(function(x) identical(
    as.character(x$kind %||% "")[1], "external_state_candidate"),
    operation$inputs), function(x) as.character(x$name)[1], character(1))
  ordinary_inputs <- inputs[setdiff(names(inputs), g3_input_names)]
  g1_reads <- c(operation$contained_model_reads %||% list(),
    operation$self_linked_contained_model_reads %||% list())
  g1_model_inputs <- if (length(g1_reads)) unique(vapply(g1_reads,
    function(read) as.character(read$input)[1L], character(1))) else
      character()
  base <- .wb_operation_pack_v2_request(bundle, registration, projected,
    ordinary_inputs, params, transition_id, session_id, run_id, generation, preflight,
    stage_root, g1_model_inputs = g1_model_inputs,
    space_plans = attr(inputs, "operation_pack_v3_space_plans") %||% list())
  ancestry_inputs <- unique(vapply(operation$provenance_reads %||% list(),
    function(x) as.character(x$input)[1], character(1)))
  ancestry_inputs <- unique(c(ancestry_inputs, vapply(
    operation$producer_lineage_reads %||% list(), function(x)
      as.character(x$summary_input)[1], character(1))))
  for (i in seq_along(base$inputs)) {
    name <- as.character(base$inputs[[i]]$name)[1]
    if (name %in% ancestry_inputs &&
        !is.null(.wb_operation_pack_v3_artifact_ref(source_refs[[name]]))) {
      base$inputs[[i]]$descriptor <-
        .wb_operation_pack_v3_bind_artifact_input_descriptor(bundle,
          source_refs[[name]], inputs[[name]], base$inputs[[i]]$descriptor)
    }
  }
  typed_input_names <- unique(vapply(operation$typed_slice_reads %||% list(),
    `[[`, character(1), "input"))
  for (i in seq_along(base$inputs)) {
    name <- as.character(base$inputs[[i]]$name)[1]
    value <- inputs[[name]]
    if (name %in% typed_input_names && identical(value$kind, "matrix") &&
        is.null(value$values) && nzchar(as.character(value$matrix_id %||%
          "")[1])) {
      # Authenticate the exact stage-visible fragment bytes that typed slices
      # will consume. Unchanged committed leaves remain containment-safe links;
      # stage-only predecessor fragments remain private regular files.
      observed <- .wb_operation_pack_v3_matrix_consumed_identity(bundle,
        value$matrix_id, "resolution")
      if (!identical(as.character(observed$verification_status)[1],
          "content_verified")) .wb_operation_pack_v3_error(
        "PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Typed-slice backed source is not content verified.", "resolution")
      descriptor <- base$inputs[[i]]$descriptor
      descriptor$content_identity <- list(
        scheme = as.character(observed$content_identity_scheme)[1],
        sha256 = as.character(observed$content_sha256)[1])
      descriptor$descriptor_identity <- NULL
      descriptor$descriptor_identity <- .wb_operation_pack_v2_identity_scoped(
        "scworkbench.operation_pack.input_descriptor.v2",
        "descriptor excluding descriptor_identity", descriptor)
      base$inputs[[i]]$descriptor <- descriptor
    }
  }
  sparse_family_policy <- .wb_operation_pack_v3_sscf_policy(operation)
  relation_policy <- .wb_operation_pack_v3_rf_policy(operation)
  if (length(sparse_family_policy) && identical(
      as.character(sparse_family_policy[[1L]]$axis_source$source)[1],
      "typed_space_input_v1")) {
    source_name <- as.character(sparse_family_policy[[1L]]$axis_source$input)[1]
    source_index <- match(source_name, vapply(base$inputs, `[[`,
      character(1), "name"))
    descriptor <- base$inputs[[source_index]]$descriptor
    descriptor$content_identity <-
      .wb_operation_pack_v3_phase5_primitive_identity(bundle,
        inputs[[source_name]])
    descriptor$descriptor_identity <- NULL
    descriptor$descriptor_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.input_descriptor.v2",
      "descriptor excluding descriptor_identity", descriptor)
    base$inputs[[source_index]]$descriptor <- descriptor
  }
  if (length(relation_policy) && identical(
      as.character(relation_policy[[1L]]$axis_source$source)[1],
      "typed_input_v1")) {
    source_name <- as.character(relation_policy[[1L]]$axis_source$input)[1]
    source_index <- match(source_name, vapply(base$inputs, `[[`,
      character(1), "name"))
    descriptor <- base$inputs[[source_index]]$descriptor
    descriptor$content_identity <-
      .wb_operation_pack_v3_phase5_primitive_identity(bundle,
        inputs[[source_name]])
    descriptor$descriptor_identity <- NULL
    descriptor$descriptor_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.input_descriptor.v2",
      "descriptor excluding descriptor_identity", descriptor)
    base$inputs[[source_index]]$descriptor <- descriptor
  }
  input_records <- stats::setNames(lapply(base$inputs, `[[`, "descriptor"),
    vapply(base$inputs, `[[`, character(1), "name"))
  model_reads <- .wb_operation_pack_v3_prepare_model_reads(bundle,
    operation, inputs, input_records, params, stage_root)
  input_records <- model_reads$input_records
  self_model_reads <- .wb_operation_pack_v3_prepare_self_linked_model_reads(
    bundle, operation, inputs, input_records, stage_root)
  input_records <- self_model_reads$input_records
  for (i in seq_along(base$inputs)) {
    input_name <- as.character(base$inputs[[i]]$name)[1]
    base$inputs[[i]]$descriptor <- input_records[[input_name]]
  }
  v3_registry <- .wb_operation_pack_v3_registry_read_records(bundle,
    operation, inputs, input_records, params, stage_root, effective_cells, session_id,
    run_id, generation, base$execution_capability$source_state_identity)
  if (length(v3_registry$records)) {
    base$registry_reads <- c(base$registry_reads %||% list(),
      v3_registry$records)
    base$registry_reads <- base$registry_reads[order(vapply(
      base$registry_reads, `[[`, character(1), "name"), method = "radix")]
  }
  registry_records <- stats::setNames(base$registry_reads %||% list(),
    vapply(base$registry_reads %||% list(), `[[`, character(1), "name"))
  policies <- .wb_operation_pack_v3_policy_map(operation)
  outputs <- stats::setNames(operation$outputs,
    vapply(operation$outputs, `[[`, character(1), "name"))
  typed_slice_grants <- lapply(operation$typed_slice_reads %||% list(),
    function(declaration) {
      input_name <- as.character(declaration$input)[1]
      .wb_operation_pack_v3_typed_slice_grant(bundle, declaration,
        inputs[[input_name]], input_records[[input_name]], params,
        effective_cells, base$execution_capability$source_state_identity,
        stage_root)
    })
  typed_slice_grants <- stats::setNames(typed_slice_grants,
    vapply(typed_slice_grants, `[[`, character(1), "name"))
  typed_space_grants <- lapply(operation$typed_space_reads %||% list(),
    function(declaration) {
      input_name <- as.character(declaration$input)[1]
      .wb_operation_pack_v3_typed_space_grant(bundle, declaration,
        inputs[[input_name]], input_records[[input_name]], params,
        base$execution_capability$source_state_identity, stage_root,
        space_plan = (attr(inputs, "operation_pack_v3_space_plans") %||% list())[[input_name]])
    })
  typed_space_grants <- stats::setNames(typed_space_grants,
    vapply(typed_space_grants, `[[`, character(1), "name"))
  parameter_axis_grants <- lapply(operation$parameter_axes %||% list(),
    .wb_operation_pack_v3_parameter_axis_grant, params = params,
    typed_grants = typed_slice_grants)
  parameter_axis_grants <- stats::setNames(parameter_axis_grants,
    vapply(parameter_axis_grants, `[[`, character(1), "name"))
  artifact_collections <- .wb_operation_pack_v3_prepare_artifact_collections(
    bundle, operation, params, stage_root)
  named_axes <- .wb_operation_pack_v3_prepare_named_axis_collections(bundle,
    operation, inputs, input_records, params, stage_root)
  optional_display <- .wb_operation_pack_v3_prepare_optional_display_groups(
    bundle, operation, params, stage_root, artifact_collections)
  publication_policies <- .wb_operation_pack_v3_publication_map(operation)
  g7_linked <- .wb_operation_pack_v3_g7_linked_map(operation)
  for (i in seq_along(base$outputs)) {
    name <- as.character(base$outputs[[i]]$name)[1]
    descriptor <- base$outputs[[i]]$descriptor
    if (inherits(registration, "wb_operation_pack_registration_v4") &&
      identical(descriptor$kind, "graph")) next
    policy <- policies[[name]]
    if (!is.null(policy) && identical(as.character(policy$policy)[1],
        "standalone_sparse_cell_family_v1")) {
      descriptor$expected_dimensions <- list(0L, 3L)
      descriptor["expected_cell_order_identity"] <- list(NULL)
    }
    if (!is.null(policy) && identical(as.character(policy$policy)[1],
        "runtime_ordered_cell_family_v1")) {
      descriptor$expected_dimensions <- list(0L, 3L)
      descriptor["expected_cell_order_identity"] <- list(NULL)
      descriptor$semantic_constraints$missing_values <- "allowed"
    }
    if (!is.null(policy) && identical(as.character(policy$policy)[1],
        "sealed_relation_family_v1")) {
      descriptor$expected_dimensions <- list(0L, 3L)
      descriptor["expected_cell_order_identity"] <- list(NULL)
    }
    if (!is.null(g7_linked[[name]])) {
      descriptor$derived_cell_output_axis_policy <-
        .wb_operation_pack_v3_g7_output_policy(
          g7_linked[[name]]$declaration, g7_linked[[name]]$policy,
          inputs, params, input_records, typed_space_grants)
      descriptor$expected_dimensions <- if (identical(
        as.character(outputs[[name]]$kind)[1], "cell_vector")) list(0L) else
          if (identical(as.character(outputs[[name]]$kind)[1], "space"))
            list(0L, 0L) else list(0L, 3L)
      descriptor["expected_cell_order_identity"] <- list(NULL)
    }
    if (!is.null(policy) && identical(as.character(policy$policy)[1],
        "authenticated_output_axes_v1")) {
      grant <- .wb_operation_pack_v3_cardinality_grant(policy,
        outputs[[name]], inputs, params, input_records, effective_cells,
        registry_records)
      descriptor$cardinality_grant <- grant
      descriptor$expected_dimensions <- if (identical(grant$shape,
          "bounded_grouped_cell_key_cartesian")) list(0L, 3L) else if (
          identical(grant$shape, "cell_key_cartesian"))
        list(grant$expected_row_count, 3L) else list(grant$expected_row_count)
      granted_cells <- attr(grant, "operation_pack_v3_cells") %||%
        character()
      if (!identical(grant$shape,
          "bounded_grouped_cell_key_cartesian")) {
        output_cells <- if (identical(grant$shape,
            "cell_key_cartesian")) rep(granted_cells,
          times = as.integer(grant$key_axis_count)) else granted_cells
        descriptor$expected_cell_order_identity <-
          .wb_operation_pack_v2_identity_plain(
            "scworkbench.cell_order.v1", unname(as.list(output_cells)))
      }
    }
    if (!is.null(policy) && identical(as.character(policy$policy)[1],
        "data_dependent_family_v1")) {
      descriptor$expected_dimensions <- list(0L,
        if (identical(as.character(outputs[[name]]$kind)[1],
          "path_2d_family")) 4L else 5L)
    }
    if (!is.null(policy) && identical(as.character(policy$policy)[1],
        "authenticated_sparse_membership_v1")) {
      descriptor$sparse_membership_grant <-
        .wb_operation_pack_v3_sparse_grant(policy, outputs[[name]], params,
          typed_space_grants)
      descriptor$expected_dimensions <- if (identical(as.character(
        policy$representation)[1], "obs_table")) list(0L, 0L) else
          list(0L, 3L)
      if (identical(as.character(policy$representation)[1],
          "cell_vector_family")) descriptor$expected_cell_order_identity <-
        descriptor$sparse_membership_grant$candidate_axis_identity else
          descriptor$expected_cell_order_identity <- NULL
    }
    if (!is.null(policy) && identical(as.character(policy$policy)[1],
        "authenticated_pseudobulk_v1")) {
      descriptor$pseudobulk_grant <-
        .wb_operation_pack_v3_pseudobulk_grant(policy, outputs[[name]],
          params, typed_space_grants, typed_slice_grants)
      descriptor$expected_dimensions <- list(0L, 0L)
      descriptor$expected_feature_order_identity <-
        descriptor$pseudobulk_grant$feature_axis_identity
    }
    if (!is.null(policy) && as.character(policy$policy)[1] %in% c(
        "cell_by_parameter_axis_v1",
        "feature_parameter_axis_cartesian_v1",
        "one_per_parameter_axis_v1", "singleton_parameter_echo_v1")) {
      axis_name <- as.character(policy$dimension_axis %||%
        policy$parameter_axis)[1]
      axis <- parameter_axis_grants[[axis_name]]
      descriptor$parameter_axis_grant_identity <-
        .wb_operation_pack_v3_unscoped_identity(axis$grant_identity)
      descriptor$expected_dimensions <- switch(as.character(policy$policy)[1],
        cell_by_parameter_axis_v1 = list(as.integer(length(attr(axis,
          "operation_pack_v3_cells"))), as.integer(axis$value)),
        feature_parameter_axis_cartesian_v1 = list(as.integer(axis$value *
          length(attr(axis, "operation_pack_v3_features"))), 0L),
        one_per_parameter_axis_v1 = list(as.integer(axis$value), 0L),
        singleton_parameter_echo_v1 = list(1L, 0L))
      descriptor$expected_cell_order_identity <- if (identical(
          as.character(policy$policy)[1], "cell_by_parameter_axis_v1"))
        .wb_operation_pack_v2_identity_plain("scworkbench.cell_order.v1",
          unname(as.list(attr(axis, "operation_pack_v3_cells")))) else NULL
      descriptor$expected_dimension_order_identity <- if (identical(
          as.character(policy$policy)[1], "cell_by_parameter_axis_v1"))
        axis$axis_order_identity else NULL
    }
    publication_policy <- publication_policies[[name]]
    if (!is.null(publication_policy)) {
      publication <- .wb_operation_pack_v3_publication_grant(bundle,
        publication_policy, operation, params,
        base$execution_capability$source_state_identity, inputs,
        input_records, base$outputs)
      descriptor$publication_grant <- publication
      base$outputs[[i]]$allocated_id <- publication$target_id
    }
    if (!is.null(outputs[[name]]$contained_model_policy)) {
      descriptor$contained_model_write_grant <-
        .wb_operation_pack_v3_model_write_grant(outputs[[name]], operation,
          inputs, input_records, params, base$outputs)
      descriptor$expected_model_linkage <- list(mode = "input",
        reference_name = as.character(outputs[[name]]$
          contained_model_policy$source_space_input)[1],
        reference_identity = descriptor$contained_model_write_grant$
          source_space$input_descriptor_identity)
      descriptor$semantic_constraints <- list(
        engine = as.character(outputs[[name]]$contained_model_policy$engine)[1],
        contained = TRUE, no_symlinks = TRUE)
    }
    sibling_policy <- outputs[[name]]$
      contained_model_sibling_closure_policy %||% NULL
    if (!is.null(sibling_policy)) {
      source_name <- as.character(sibling_policy$source_space_input)[1]
      descriptor$expected_model_linkage <- list(mode = "input",
        reference_name = source_name,
        reference_identity = .wb_operation_pack_v3_unscoped_identity(
          input_records[[source_name]]$descriptor_identity))
      descriptor$semantic_constraints <- list(
        engine = as.character(sibling_policy$engine)[1],
        contained = TRUE, no_symlinks = TRUE)
    }
    matrix_policy <- outputs[[name]]$
      matrix_trained_contained_model_closure_policy %||% NULL
    if (!is.null(matrix_policy)) {
      source_name <- as.character(matrix_policy$source_matrix_input)[1]
      descriptor$expected_model_linkage <- list(mode = "input",
        reference_name = source_name,
        reference_identity = .wb_operation_pack_v3_unscoped_identity(
          input_records[[source_name]]$descriptor_identity))
      descriptor$semantic_constraints <- list(
        engine = as.character(matrix_policy$engine)[1],
        contained = TRUE, no_symlinks = TRUE)
    }
    paired_models <- Filter(function(x) identical(as.character(
      x$matrix_trained_contained_model_closure_policy$
        paired_space_output %||% "")[1], name), operation$outputs)
    if (length(paired_models) == 1L) {
      matrix_policy <- paired_models[[1L]]$
        matrix_trained_contained_model_closure_policy
      source_name <- as.character(matrix_policy$source_matrix_input)[1]
      axis_grants <- Filter(function(x) identical(as.character(x$input_name)[1],
        source_name), typed_slice_grants)
      if (length(axis_grants) != 1L) .wb_operation_pack_v3_error(
        "PYBENCH_CAPABILITY_MISMATCH",
        "Matrix-trained latent space requires one typed matrix reader.",
        "resolution")
      cells <- attr(axis_grants[[1L]], "operation_pack_v3_cells")
      latent <- as.integer(params[[as.character(
        matrix_policy$latent_dimensions_parameter)[1]]])[1]
      descriptor$expected_dimensions <- list(as.integer(length(cells)), latent)
      descriptor$expected_cell_order_identity <-
        .wb_operation_pack_v2_identity_plain("scworkbench.cell_order.v1",
          unname(as.list(cells)))
    }
    if (!is.null(outputs[[name]]$fragment_policy)) {
      descriptor$matrix_fragment_grant <-
        .wb_operation_pack_v3_matrix_fragment_grant(bundle, outputs[[name]],
          inputs, input_records, typed_slice_grants)
    }
    descriptor$grant_identity <- NULL
    descriptor$grant_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.output_grant.v3",
      "descriptor excluding grant_identity", descriptor)
    base$outputs[[i]]$descriptor <- descriptor
  }

  # The ordinary output grant is the acyclic base for an opt-in sparse
  # provisional grant.  Rehashing the descriptor after insertion binds the
  # provisional grant to the immutable request without making it a writer.
  sparse_family_grants <- list()
  if (length(sparse_family_policy)) {
    policy <- sparse_family_policy[[1L]]
    source <- .wb_operation_pack_v3_sscf_source(bundle, policy, inputs,
      input_records, self_model_reads,
      base$execution_capability$source_state_identity)
    name <- as.character(policy$output)[1]
    index <- match(name, vapply(base$outputs, `[[`, character(1), "name"))
    grant <- .wb_operation_pack_v3_sscf_grant(policy, source,
      base$outputs[[index]], base$transition$transition_identity)
    descriptor <- base$outputs[[index]]$descriptor
    descriptor$standalone_sparse_cell_family_provisional_grant <- grant
    descriptor$grant_identity <- NULL
    descriptor$grant_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.output_grant.v3",
      "descriptor excluding grant_identity", descriptor)
    base$outputs[[index]]$descriptor <- descriptor
    sparse_family_grants <- list(grant)
  }

  # Sibling-bound model grants are constructed only after every ordinary
  # output grant exists. This gives the closure a deterministic, acyclic base
  # grant for the model and ordered sibling grant identities.
  output_records <- stats::setNames(base$outputs,
    vapply(base$outputs, `[[`, character(1), "name"))
  for (i in seq_along(base$outputs)) {
    name <- as.character(base$outputs[[i]]$name)[1]
    output <- outputs[[name]]
    if ((is.null(output$contained_model_sibling_closure_policy) ||
        !is.null(output$derived_fitted_axis_policy)) &&
        is.null(output$matrix_trained_contained_model_closure_policy)) next
    descriptor <- base$outputs[[i]]$descriptor
    matrix_policy <- output$matrix_trained_contained_model_closure_policy
    sibling_grant <- if (is.null(matrix_policy))
      .wb_operation_pack_v3_model_sibling_write_grant(bundle, output,
        operation, inputs, input_records, params, output_records) else
      .wb_operation_pack_v3_matrix_model_grant(bundle, output, operation,
        inputs, input_records, params, typed_slice_grants, output_records,
        base$execution_capability$source_state_identity)
    descriptor[[if (is.null(matrix_policy))
      "contained_model_sibling_write_grant" else
      "contained_matrix_model_sibling_write_grant"]] <- sibling_grant
    descriptor$expected_model_linkage <- list(mode = "input",
      reference_name = if (is.null(matrix_policy))
        sibling_grant$source_space$input_name else
        sibling_grant$source_matrix$input_name,
      reference_identity = if (is.null(matrix_policy))
        sibling_grant$source_space$input_descriptor_identity else
        sibling_grant$source_matrix$input_descriptor_identity)
    descriptor$semantic_constraints <- list(engine = sibling_grant$engine,
      contained = TRUE, no_symlinks = TRUE)
    descriptor$grant_identity <- NULL
    descriptor$grant_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.output_grant.v3",
      "descriptor excluding grant_identity", descriptor)
    base$outputs[[i]]$descriptor <- descriptor
  }

  adoption <- .wb_operation_pack_v3_g3_prepare(bundle, operation, inputs,
    params, base, stage_root)

  output_records <- stats::setNames(base$outputs,
    vapply(base$outputs, `[[`, character(1), "name"))
  derived_fitted <- .wb_operation_pack_v3_dfa_prepare(bundle,
    operation, inputs, input_records, params, output_records,
    base$transition$transition_identity)
  derived_axes <- .wb_operation_pack_v3_g7_prepare(operation, inputs,
    input_records, params, artifact_collections, output_records,
    typed_space_grants)

  relation_grants <- list()
  if (length(relation_policy)) {
    policy <- relation_policy[[1L]]
    source <- if (identical(as.character(policy$axis_source$source)[1],
        "typed_input_v1")) .wb_operation_pack_v3_rf_typed_source(
          bundle, policy, inputs, input_records,
          base$execution_capability$source_state_identity) else NULL
    g2 <- if (is.null(source)) derived_fitted$grants[[1L]] else NULL
    name <- as.character(policy$output)[1]
    index <- match(name, vapply(base$outputs, `[[`, character(1), "name"))
    grant <- .wb_operation_pack_v3_rf_grant(policy,
      base$outputs[[index]], base$transition$transition_identity,
      source_axis = source, g2_grant = g2)
    descriptor <- base$outputs[[index]]$descriptor
    descriptor$sealed_relation_family_provisional_grant <- grant
    descriptor$grant_identity <- NULL
    descriptor$grant_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.output_grant.v3",
      "descriptor excluding grant_identity", descriptor)
    base$outputs[[index]]$descriptor <- descriptor
    relation_grants <- list(grant)
  }

  provenance <- .wb_operation_pack_v3_provenance_read_records(bundle,
    operation, inputs, source_refs, input_records, params, stage_root)
  producer_lineage <- .wb_operation_pack_v3_producer_lineage_records(bundle,
    operation, inputs, source_refs, input_records,
    base$execution_capability$source_state_identity)
  identity <- registration$identity
  op_name <- as.character(operation$qualified_name)[1]
  capability <- base$execution_capability
  capability$pack_identity <- identity$pack_identity
  capability$operation_definition_identity <-
    identity$operation_definition_identities[[op_name]]
  capability$writer_grants <- lapply(base$outputs, function(x) list(
    output_name = x$name, writer = x$descriptor$writer,
    grant_identity = x$descriptor$grant_identity))
  private_input_names <- unique(c(
    vapply(typed_slice_grants, `[[`, character(1), "input_name"),
    vapply(typed_space_grants, `[[`, character(1), "input_name"),
    vapply(model_reads$grants, `[[`, character(1), "input_name")))
  private_input_names <- unique(c(private_input_names,
    vapply(self_model_reads$grants, `[[`, character(1), "input_name")))
  capability$reader_grants <- unname(c(
    lapply(Filter(function(x) !x$name %in% private_input_names,
      base$inputs), function(x) list(input_name = x$name,
      reader = x$descriptor$reader,
      descriptor_identity = x$descriptor$descriptor_identity)),
    lapply(base$registry_reads %||% list(), function(x) list(
      registry_read_name = x$name, reader = x$descriptor$reader,
      descriptor_identity = x$descriptor$descriptor_identity)),
    lapply(provenance$records, function(x) list(
      provenance_read_name = x$name, reader = x$reader,
      descriptor_identity = x$descriptor_identity)),
    lapply(producer_lineage, function(x) list(
      producer_lineage_read_name = x$name, reader = x$reader,
      grant_identity = x$grant_identity)),
    lapply(model_reads$grants, function(x) list(
      model_payload_name = x$name, reader = x$reader,
      grant_identity = x$grant_identity)),
    lapply(self_model_reads$grants, function(x) list(
      self_linked_model_payload_name = x$name, reader = x$reader,
      grant_identity = x$grant_identity)),
    lapply(artifact_collections$grants, function(x) list(
      artifact_collection_name = x$name, reader = x$reader,
      grant_identity = x$grant_identity)),
    lapply(named_axes$grants, function(x) list(
      named_cell_axis_collection_name = x$name, reader =
        "read_named_cell_axis", grant_identity = x$grant_identity)),
    lapply(optional_display$grants, function(x) list(
      optional_display_axis_group_name = x$name,
      reader = "read_optional_display_space",
      grant_identity = x$grant_identity)),
    lapply(optional_display$grants, function(x) list(
      optional_endpoint_axis_group_name = x$name,
      reader = "read_optional_endpoint_axis",
      grant_identity = x$grant_identity)),
    lapply(typed_slice_grants, function(x) list(
      typed_slice_name = x$name, reader = x$reader,
      grant_identity = x$grant_identity)),
    lapply(typed_space_grants, function(x) list(
      typed_space_name = x$name, reader = x$reader,
      grant_identity = x$grant_identity)),
    lapply(adoption$grants, function(x) list(
      supported_external_state_adoption_name = x$name,
      reader = "read_supported_external_state",
      grant_identity = x$grant_identity))))
  if (length(typed_slice_grants)) capability$typed_slice_grant_identities <-
    unname(lapply(typed_slice_grants, function(x)
      .wb_operation_pack_v3_unscoped_identity(x$grant_identity)))
  if (length(typed_space_grants)) capability$typed_space_grant_identities <-
    unname(lapply(typed_space_grants, function(x)
      .wb_operation_pack_v3_unscoped_identity(x$grant_identity)))
  if (length(parameter_axis_grants))
    capability$parameter_axis_grant_identities <- unname(lapply(
      parameter_axis_grants, function(x)
        .wb_operation_pack_v3_unscoped_identity(x$grant_identity)))
  if (length(provenance$records)) capability$provenance_read_identities <-
    lapply(provenance$records, function(x)
      .wb_operation_pack_v3_unscoped_identity(
        x$descriptor_identity))
  if (length(producer_lineage))
    capability$producer_lineage_grant_identities <- unname(lapply(
      producer_lineage, function(x)
        .wb_operation_pack_v3_unscoped_identity(x$grant_identity)))
  if (length(model_reads$grants))
    capability$model_payload_grant_identities <- unname(lapply(
      model_reads$grants, function(x)
        .wb_operation_pack_v3_unscoped_identity(x$grant_identity)))
  if (length(self_model_reads$grants))
    capability$self_linked_model_payload_grant_identities <- unname(lapply(
      self_model_reads$grants, function(x)
        .wb_operation_pack_v3_unscoped_identity(x$grant_identity)))
  if (length(artifact_collections$grants))
    capability$artifact_collection_grant_identities <- unname(lapply(
      artifact_collections$grants, function(x)
        .wb_operation_pack_v3_unscoped_identity(x$grant_identity)))
  if (length(named_axes$grants))
    capability$named_cell_axis_collection_grant_identities <- unname(lapply(
      named_axes$grants, function(x)
        .wb_operation_pack_v3_unscoped_identity(x$grant_identity)))
  if (length(optional_display$grants))
    capability$optional_display_axis_group_grant_identities <- unname(lapply(
      optional_display$grants, function(x)
        .wb_operation_pack_v3_unscoped_identity(x$grant_identity)))
  if (length(adoption$grants))
    capability$supported_external_state_adoption_grant_identities <-
      unname(lapply(adoption$grants, function(x)
        .wb_operation_pack_v3_unscoped_identity(x$grant_identity)))
  if (length(derived_axes$grants))
    capability$derived_cell_output_axis_grant_identities <-
      unname(lapply(derived_axes$grants, function(x)
        .wb_operation_pack_v3_unscoped_identity(x$grant_identity)))
  if (length(derived_fitted$grants))
    capability$derived_fitted_axis_grant_identities <-
      unname(lapply(derived_fitted$grants, function(x)
        .wb_operation_pack_v3_unscoped_identity(x$grant_identity)))
  if (length(sparse_family_grants))
    capability$standalone_sparse_cell_family_grant_identities <-
      unname(lapply(sparse_family_grants, function(x)
        .wb_operation_pack_v3_unscoped_identity(x$grant_identity)))
  if (length(relation_grants))
    capability$sealed_relation_family_grant_identities <-
      unname(lapply(relation_grants, function(x)
        .wb_operation_pack_v3_unscoped_identity(x$grant_identity)))
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
  if (length(typed_slice_grants))
    base$typed_slice_grants <- unname(typed_slice_grants)
  if (length(typed_space_grants))
    base$typed_space_grants <- unname(typed_space_grants)
  if (length(parameter_axis_grants))
    base$parameter_axis_grants <- unname(parameter_axis_grants)
  if (length(provenance$records)) base$provenance_reads <- provenance$records
  if (length(producer_lineage))
    base$producer_lineage_grants <- unname(producer_lineage)
  if (length(model_reads$grants))
    base$model_payload_grants <- unname(model_reads$grants)
  if (length(self_model_reads$grants))
    base$self_linked_model_payload_grants <- unname(self_model_reads$grants)
  if (length(artifact_collections$grants))
    base$artifact_collection_grants <- unname(artifact_collections$grants)
  if (length(named_axes$grants))
    base$named_cell_axis_collection_grants <- unname(named_axes$grants)
  if (length(optional_display$grants))
    base$optional_display_axis_group_grants <- unname(optional_display$grants)
  if (length(adoption$grants))
    base$supported_external_state_adoption_grants <-
      unname(adoption$grants)
  if (length(derived_axes$grants))
    base$derived_cell_output_axis_grants <- unname(derived_axes$grants)
  if (length(derived_fitted$grants))
    base$derived_fitted_axis_grants <- unname(derived_fitted$grants)
  if (length(sparse_family_grants))
    base$standalone_sparse_cell_family_grants <-
      unname(sparse_family_grants)
  if (length(relation_grants))
    base$sealed_relation_family_grants <- unname(relation_grants)
  runtime_key_grants <- .wb_operation_pack_v3_rfk_grant(operation,
    registry_records, base$outputs)
  if (length(runtime_key_grants))
    base$runtime_cell_family_key_grants <- runtime_key_grants
  base$request_identity <- NULL
  base$request_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.transition_request.v3",
    "request excluding request_identity", base)
  attr(base, "operation_pack_v2_transport_inputs") <- attr(base,
    "operation_pack_v2_transport_inputs")
  attr(base, "operation_pack_v2_registry_read_values") <- attr(base,
    "operation_pack_v2_registry_read_values")
  attr(base, "operation_pack_v2_registry_read_values") <- c(
    attr(base, "operation_pack_v2_registry_read_values") %||% list(),
    v3_registry$values)
  attr(base, "operation_pack_v3_provenance_read_values") <- provenance$values
  attr(base, "operation_pack_v3_producer_lineage_values") <-
    stats::setNames(producer_lineage, vapply(producer_lineage, `[[`,
      character(1), "name"))
  attr(base, "operation_pack_v3_model_read_values") <- model_reads$values
  attr(base, "operation_pack_v3_self_linked_model_read_values") <-
    self_model_reads$values
  attr(base, "operation_pack_v3_artifact_collection_values") <-
    artifact_collections$values
  attr(base, "operation_pack_v3_artifact_collection_sources") <-
    artifact_collections$sources
  attr(base, "operation_pack_v3_named_axis_values") <- named_axes$values
  attr(base, "operation_pack_v3_named_axis_sources") <- named_axes$sources
  attr(base, "operation_pack_v3_optional_display_values") <-
    optional_display$values
  attr(base, "operation_pack_v3_optional_display_sources") <-
    optional_display$sources
  attr(base, "operation_pack_v3_external_candidate") <- adoption$candidate
  attr(base, "operation_pack_v3_derived_axis_state") <- derived_axes$state
  if (length(derived_fitted$grants)) {
    attr(base, "operation_pack_v3_dfa_parent_cells") <-
      derived_fitted$values$parent_cells
    attr(base, "operation_pack_v3_dfa_session_cells") <-
      derived_fitted$values$session_cells
    attr(base, "operation_pack_v3_dfa_sibling_policy") <-
      derived_fitted$values$sibling_policy
    attr(base, "operation_pack_v3_dfa_promotion_group") <-
      as.character(.wb_operation_pack_v3_dfa_policy(operation)$output$
        promotion_group)[1]
  }
  attr(base, "operation_pack_stage_root") <- stage_root
  attr(base, "operation_pack_v3_typed_slice_values") <-
    stats::setNames(lapply(typed_slice_grants, function(grant) list(
      cells = attr(grant, "operation_pack_v3_cells"),
      features = attr(grant, "operation_pack_v3_features"),
      input = inputs[[grant$input_name]])), vapply(typed_slice_grants, `[[`,
        character(1), "name"))
  attr(base, "operation_pack_v3_typed_space_values") <-
    stats::setNames(lapply(typed_space_grants, function(grant) list(
      cells = attr(grant, "operation_pack_v3_cells"),
      input = inputs[[grant$input_name]],
      issued_grant = grant,
      issued_input_record = Filter(function(record) identical(
        as.character(record$name)[1L], as.character(grant$input_name)[1L]), base$inputs),
      plan = (attr(inputs, "operation_pack_v3_space_plans") %||% list())[[grant$input_name]])), vapply(typed_space_grants, `[[`,
        character(1), "name"))
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
    operation, bundle = NULL, inputs = NULL, params = NULL) {
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
    if (!is.null(descriptor$sparse_membership_grant))
      .wb_operation_pack_v3_assert_self_identity(
        descriptor$sparse_membership_grant, "grant_identity",
        "PYBENCH_CAPABILITY_MISMATCH", "staging")
    if (!is.null(descriptor$pseudobulk_grant))
      .wb_operation_pack_v3_assert_self_identity(
        descriptor$pseudobulk_grant, "grant_identity",
        "PYBENCH_CAPABILITY_MISMATCH", "staging")
    if (!is.null(descriptor$contained_model_write_grant))
      .wb_operation_pack_v3_assert_self_identity(
        descriptor$contained_model_write_grant, "write_grant_identity",
        "PYBENCH_CAPABILITY_MISMATCH", "staging")
    if (!is.null(descriptor$contained_model_sibling_write_grant)) {
      .wb_operation_pack_v3_assert_model_source_linkage(
        descriptor$contained_model_sibling_write_grant$model_source_linkage,
        "PYBENCH_CAPABILITY_MISMATCH", "staging")
      .wb_operation_pack_v3_assert_self_identity(
        descriptor$contained_model_sibling_write_grant,
        "write_grant_identity", "PYBENCH_CAPABILITY_MISMATCH", "staging")
    }
    if (!is.null(descriptor$contained_matrix_model_sibling_write_grant)) {
      .wb_operation_pack_v3_assert_matrix_model_linkage(
        descriptor$contained_matrix_model_sibling_write_grant$
          model_source_linkage,
        "PYBENCH_CAPABILITY_MISMATCH", "staging")
      .wb_operation_pack_v3_assert_self_identity(
        descriptor$contained_matrix_model_sibling_write_grant,
        "write_grant_identity", "PYBENCH_CAPABILITY_MISMATCH", "staging")
    }
    .wb_operation_pack_v3_assert_self_identity(descriptor, "grant_identity",
      "PYBENCH_CAPABILITY_MISMATCH", "staging")
  }
  for (grant in request$typed_slice_grants %||% list()) {
    declaration <- Filter(function(x) identical(as.character(x$name)[1],
      as.character(grant$name)[1]), operation$typed_slice_reads %||% list())
    if (length(declaration) != 1L || !identical(
        as.character(grant$value_policy %||% "")[1],
        as.character(declaration[[1]]$value_policy %||% "")[1]))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Typed-slice value policy differs from the authenticated manifest.",
        "staging")
    .wb_operation_pack_v3_assert_self_identity(grant$source_reference,
      "source_reference_identity", "PYBENCH_CAPABILITY_MISMATCH", "staging")
    .wb_operation_pack_v3_assert_self_identity(grant,
      "grant_identity", "PYBENCH_CAPABILITY_MISMATCH", "staging")
    stage <- attr(request, "operation_pack_stage_root")
    graph_enabled <- length(request$graph_read_grants %||% list()) > 0L ||
      length(request$graph_write_grants %||% list()) > 0L
    axis_budget <- .wb_operation_pack_v3_broker_projection_budget(bundle,
      if (graph_enabled) .wb_operation_pack_v4_lowest_graph_budgets(lapply(
        request$graph_write_grants %||% list(), `[[`, "resource_budgets")) else NULL)
    admissions <- lapply(list(cells_axis = grant$cells_axis,
      features_axis = grant$features_axis), function(descriptor)
        .wb_operation_pack_v3_broker_axis_admission(stage, descriptor))
    axis_charge <- sum(vapply(admissions, `[[`, numeric(1), "estimate"))
    if (!is.finite(axis_charge) || axis_charge > axis_budget$memory)
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Combined typed axes exceed request-validation working admission.", "staging")
    axis_budget$used <- axis_charge
    admitted_axes <- list()
    for (axis in c("cells_axis", "features_axis")) {
      descriptor <- grant[[axis]]
      path <- file.path(attr(request, "operation_pack_stage_root"),
        descriptor$relative_path)
      if (!file.exists(path)) .wb_operation_pack_v3_error(
        "PYBENCH_CAPABILITY_MISMATCH",
        "Typed-slice axis manifest is absent.", "staging")
      if (.wb_operation_pack_v3_broker_axis_admission(stage,
          descriptor)$estimate > admissions[[axis]]$estimate)
        .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
          "Typed axis grew beyond its preparse admission.", "staging")
      observed <- .wb_operation_pack_v2_identity_scoped(
        "scworkbench.operation_pack.payload_manifest.v2",
        "registry read payload manifest", list(path = descriptor$relative_path,
          size = as.numeric(file.info(path)$size),
          sha256 = .wb_operation_pack_v2_file_sha256(path)))
      value <- jsonlite::read_json(path, simplifyVector = FALSE)
      raw <- readChar(path, nchars = file.info(path)$size, useBytes = TRUE)
      .wb_operation_pack_v3_assert_self_identity(value, "manifest_identity",
        "PYBENCH_CAPABILITY_MISMATCH", "staging")
      if (!setequal(names(value), c("schema", "axis", "count", "ids",
            "order_identity", "manifest_identity")) ||
          !identical(raw, .wb_operation_pack_canonical_json(value)) ||
          !identical(observed, descriptor$payload_manifest_identity) ||
          !identical(value$manifest_identity,
            descriptor$axis_manifest_identity) ||
          !identical(value$order_identity, descriptor$order_identity) ||
          length(value$ids) != admissions[[axis]]$count ||
          !identical(as.integer(value$count), as.integer(descriptor$count)))
        .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
          "Typed-slice axis manifest differs from its grant.", "staging")
      admitted_axes[[if (axis == "cells_axis") "cells" else "features"]] <-
        as.character(unlist(value$ids, use.names = FALSE))
      rm(value, raw, observed)
    }
    .wb_operation_pack_v3_private_source_validate(
      stage, grant, bounded = TRUE, budget = axis_budget, axes = admitted_axes)
  }
  for (grant in request$derived_fitted_axis_grants %||% list()) {
    .wb_operation_pack_v3_assert_self_identity(grant$parent_snapshot,
      "parent_snapshot_identity", "PYBENCH_CAPABILITY_MISMATCH", "staging")
    .wb_operation_pack_v3_assert_self_identity(grant$session_projection,
      "session_identity", "PYBENCH_CAPABILITY_MISMATCH", "staging")
    .wb_operation_pack_v3_assert_self_identity(grant,
      "grant_identity", "PYBENCH_CAPABILITY_MISMATCH", "staging")
  }
  .wb_operation_pack_v3_sscf_request_audit(request, operation, bundle,
    inputs)
  .wb_operation_pack_v3_rf_request_audit(request, operation, bundle,
    inputs)
  for (grant in request$typed_space_grants %||% list()) {
    .wb_operation_pack_v3_assert_self_identity(grant$source_reference,
      "source_reference_identity", "PYBENCH_CAPABILITY_MISMATCH", "staging")
    .wb_operation_pack_v3_assert_self_identity(grant,
      "grant_identity", "PYBENCH_CAPABILITY_MISMATCH", "staging")
    descriptor <- grant$cells_axis
    path <- file.path(attr(request, "operation_pack_stage_root"),
      descriptor$relative_path)
    admission <- .wb_operation_pack_v3_broker_axis_admission(
      attr(request, "operation_pack_stage_root"), descriptor)
    if (admission$estimate > .wb_operation_pack_v3_broker_projection_budget(bundle)$memory)
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Typed-space axis exceeds request-validation working admission.", "staging")
    value <- jsonlite::read_json(path, simplifyVector = FALSE)
    .wb_operation_pack_v3_assert_self_identity(value, "manifest_identity",
      "PYBENCH_CAPABILITY_MISMATCH", "staging")
    if (!identical(value$manifest_identity,
        descriptor$axis_manifest_identity) ||
        length(value$ids) != admission$count ||
        !identical(value$order_identity, descriptor$order_identity))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Typed-space axis manifest differs from its grant.", "staging")
  }
  for (read in request$provenance_reads %||% list())
    .wb_operation_pack_v3_assert_self_identity(read,
      "descriptor_identity", "PYBENCH_INPUT_IDENTITY_MISMATCH", "resolution")
  for (grant in request$producer_lineage_grants %||% list())
    .wb_operation_pack_v3_assert_self_identity(grant,
      "grant_identity", "PYBENCH_INPUT_IDENTITY_MISMATCH", "resolution")
  for (grant in request$model_payload_grants %||% list()) {
    .wb_operation_pack_v3_assert_self_identity(grant,
      "grant_identity", "PYBENCH_CAPABILITY_MISMATCH", "staging")
    .wb_operation_pack_v3_assert_self_identity(grant$tree_manifest,
      "manifest_identity", "PYBENCH_INPUT_IDENTITY_MISMATCH", "staging")
    .wb_operation_pack_v3_validate_model_read(
      attr(request, "operation_pack_stage_root"), grant)
  }
  for (grant in request$self_linked_model_payload_grants %||% list()) {
    .wb_operation_pack_v3_assert_model_source_linkage(
      grant$model_source_linkage, "PYBENCH_CAPABILITY_MISMATCH", "staging")
    .wb_operation_pack_v3_assert_self_identity(grant,
      "grant_identity", "PYBENCH_CAPABILITY_MISMATCH", "staging")
    .wb_operation_pack_v3_assert_self_identity(grant$tree_manifest,
      "manifest_identity", "PYBENCH_INPUT_IDENTITY_MISMATCH", "staging")
    .wb_operation_pack_v3_validate_model_read(
      attr(request, "operation_pack_stage_root"), grant)
  }
  for (grant in c(request$artifact_collection_grants %||% list(),
      request$named_cell_axis_collection_grants %||% list(),
      request$optional_display_axis_group_grants %||% list()))
    .wb_operation_pack_v3_assert_self_identity(grant, "grant_identity",
      "PYBENCH_CAPABILITY_MISMATCH", "staging")
  for (grant in request$supported_external_state_adoption_grants %||% list()) {
    .wb_operation_pack_v3_assert_self_identity(grant$source_snapshot,
      "source_snapshot_identity", "PYBENCH_INPUT_IDENTITY_MISMATCH",
      "staging")
    .wb_operation_pack_v3_assert_self_identity(grant$source_byte_evidence,
      "source_byte_evidence_identity", "PYBENCH_INPUT_IDENTITY_MISMATCH",
      "staging")
    .wb_operation_pack_v3_assert_self_identity(grant$candidate_snapshot,
      "candidate_snapshot_identity", "PYBENCH_INPUT_IDENTITY_MISMATCH",
      "staging")
    .wb_operation_pack_v3_assert_self_identity(grant$adopted_closure,
      "adopted_closure_identity", "PYBENCH_CAPABILITY_MISMATCH", "staging")
    .wb_operation_pack_v3_assert_self_identity(grant, "grant_identity",
      "PYBENCH_CAPABILITY_MISMATCH", "staging")
  }
  .wb_operation_pack_v3_g7_request_audit(request)
  .wb_operation_pack_v3_phase5_staged_payloads_assert(request,
    phase = "staging")
  .wb_operation_pack_v3_assert_self_identity(request$execution_capability,
    "capability_identity", "PYBENCH_CAPABILITY_MISMATCH", "staging")
  .wb_operation_pack_v3_assert_self_identity(request, "request_identity",
    "PYBENCH_CAPABILITY_MISMATCH", "staging")
  .wb_operation_pack_v3_rfk_request_audit(request)
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
  private_input_names <- unique(c(vapply(
    request$typed_slice_grants %||% list(), `[[`, character(1), "input_name"),
    vapply(request$typed_space_grants %||% list(), `[[`, character(1),
      "input_name"),
    vapply(request$model_payload_grants %||% list(), `[[`, character(1),
      "input_name")))
  private_input_names <- unique(c(private_input_names, vapply(
    request$self_linked_model_payload_grants %||% list(), `[[`, character(1),
      "input_name")))
  expected_readers <- c(
    lapply(Filter(function(x) !x$name %in% private_input_names,
      request$inputs), function(x) {
      if (identical(request$pack_abi_version, "4") && identical(x$descriptor$kind, "graph"))
        return(list(input_name = x$name, reader = x$descriptor$reader,
          grant_identity = x$descriptor$graph_read_grant_identity))
      list(input_name = x$name, reader = x$descriptor$reader,
        descriptor_identity = x$descriptor$descriptor_identity)
    }),
    lapply(request$registry_reads %||% list(), function(x) list(
      registry_read_name = x$name, reader = x$descriptor$reader,
      descriptor_identity = x$descriptor$descriptor_identity)),
    lapply(request$provenance_reads %||% list(), function(x) list(
      provenance_read_name = x$name, reader = x$reader,
      descriptor_identity = x$descriptor_identity)),
    lapply(request$producer_lineage_grants %||% list(), function(x) list(
      producer_lineage_read_name = x$name, reader = x$reader,
      grant_identity = x$grant_identity)),
    lapply(request$model_payload_grants %||% list(), function(x) list(
      model_payload_name = x$name, reader = x$reader,
      grant_identity = x$grant_identity)),
    lapply(request$self_linked_model_payload_grants %||% list(), function(x)
      list(self_linked_model_payload_name = x$name, reader = x$reader,
        grant_identity = x$grant_identity)),
    lapply(request$artifact_collection_grants %||% list(), function(x)
      list(artifact_collection_name = x$name, reader = x$reader,
        grant_identity = x$grant_identity)),
    lapply(request$named_cell_axis_collection_grants %||% list(), function(x)
      list(named_cell_axis_collection_name = x$name,
        reader = "read_named_cell_axis", grant_identity = x$grant_identity)),
    lapply(request$optional_display_axis_group_grants %||% list(), function(x)
      list(optional_display_axis_group_name = x$name,
        reader = "read_optional_display_space",
        grant_identity = x$grant_identity)),
    lapply(request$optional_display_axis_group_grants %||% list(), function(x)
      list(optional_endpoint_axis_group_name = x$name,
        reader = "read_optional_endpoint_axis",
        grant_identity = x$grant_identity)),
    lapply(request$typed_slice_grants %||% list(), function(x) list(
      typed_slice_name = x$name, reader = x$reader,
      grant_identity = x$grant_identity)),
    lapply(request$typed_space_grants %||% list(), function(x) list(
      typed_space_name = x$name, reader = x$reader,
      grant_identity = x$grant_identity)),
    lapply(request$supported_external_state_adoption_grants %||% list(),
      function(x) list(supported_external_state_adoption_name = x$name,
        reader = "read_supported_external_state",
        grant_identity = x$grant_identity)))
  if (!identical(expected_readers,
      request$execution_capability$reader_grants))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "V3 capability reader grants differ from request inputs.", "staging")
  expected_slices <- lapply(request$typed_slice_grants %||% list(),
    function(x) .wb_operation_pack_v3_unscoped_identity(x$grant_identity))
  expected_spaces <- lapply(request$typed_space_grants %||% list(),
    function(x) .wb_operation_pack_v3_unscoped_identity(x$grant_identity))
  expected_provenance <- lapply(request$provenance_reads %||% list(),
    function(x) .wb_operation_pack_v3_unscoped_identity(
      x$descriptor_identity))
  expected_lineage <- lapply(request$producer_lineage_grants %||% list(),
    function(x) .wb_operation_pack_v3_unscoped_identity(x$grant_identity))
  expected_models <- lapply(request$model_payload_grants %||% list(),
    function(x) .wb_operation_pack_v3_unscoped_identity(x$grant_identity))
  expected_self_models <- lapply(request$self_linked_model_payload_grants %||%
    list(), function(x) .wb_operation_pack_v3_unscoped_identity(
      x$grant_identity))
  expected_artifacts <- lapply(request$artifact_collection_grants %||% list(),
    function(x) .wb_operation_pack_v3_unscoped_identity(x$grant_identity))
  expected_axes <- lapply(request$named_cell_axis_collection_grants %||% list(),
    function(x) .wb_operation_pack_v3_unscoped_identity(x$grant_identity))
  expected_displays <- lapply(request$optional_display_axis_group_grants %||%
    list(), function(x) .wb_operation_pack_v3_unscoped_identity(
      x$grant_identity))
  expected_adoptions <- lapply(
    request$supported_external_state_adoption_grants %||% list(),
    function(x) .wb_operation_pack_v3_unscoped_identity(x$grant_identity))
  expected_fitted <- lapply(request$derived_fitted_axis_grants %||% list(),
    function(x) .wb_operation_pack_v3_unscoped_identity(x$grant_identity))
  expected_sparse_family <- lapply(
    request$standalone_sparse_cell_family_grants %||% list(),
    function(x) .wb_operation_pack_v3_unscoped_identity(x$grant_identity))
  expected_relations <- lapply(
    request$sealed_relation_family_grants %||% list(),
    function(x) .wb_operation_pack_v3_unscoped_identity(x$grant_identity))
  if (!identical(request$execution_capability$typed_slice_grant_identities %||%
        list(), expected_slices) ||
      !identical(request$execution_capability$typed_space_grant_identities %||%
        list(), expected_spaces) ||
      !identical(request$execution_capability$provenance_read_identities %||%
        list(), expected_provenance) ||
      !identical(request$execution_capability$
        producer_lineage_grant_identities %||% list(), expected_lineage) ||
      !identical(request$execution_capability$model_payload_grant_identities %||%
        list(), expected_models) ||
      !identical(request$execution_capability$
        self_linked_model_payload_grant_identities %||% list(),
        expected_self_models) ||
      !identical(request$execution_capability$
        artifact_collection_grant_identities %||% list(),
        expected_artifacts) ||
      !identical(request$execution_capability$
        named_cell_axis_collection_grant_identities %||% list(),
        expected_axes) ||
      !identical(request$execution_capability$
        optional_display_axis_group_grant_identities %||% list(),
        expected_displays) ||
      !identical(request$execution_capability$
        supported_external_state_adoption_grant_identities %||% list(),
        expected_adoptions) ||
      !identical(request$execution_capability$
        derived_fitted_axis_grant_identities %||% list(), expected_fitted) ||
      !identical(request$execution_capability$
        standalone_sparse_cell_family_grant_identities %||% list(),
        expected_sparse_family) ||
      !identical(request$execution_capability$
        sealed_relation_family_grant_identities %||% list(),
        expected_relations))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "V3 capability typed-slice or provenance closure differs from request.",
      "staging")
  if (!is.null(bundle)) .wb_operation_pack_v3_dfa_request_audit(bundle,
    request, operation, inputs, params)
  invisible(TRUE)
}

.wb_operation_pack_v3_typed_slice_grant_assert_current <- function(bundle,
    grant, phase = "audit") {
  source <- grant$source_reference
  current_state <- .wb_operation_pack_v2_identity_plain(
    "scworkbench.scientific_state.v1",
    .wb_operation_pack_registry_snapshot(bundle))
  observed <- .wb_operation_pack_v3_matrix_consumed_identity(bundle,
    source$matrix_id, phase)
  identity <- list(scheme = as.character(
    observed$content_identity_scheme)[1], sha256 = as.character(
      observed$content_sha256)[1])
  if (!identical(current_state, source$transition_source_state_identity) ||
      !identical(identity, source$input_content_identity) ||
      !identical(identity, grant$input_content_identity))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      paste0("Typed-slice source changed after authentication for '",
        grant$name, "'."), phase)
  invisible(TRUE)
}

.wb_operation_pack_v3_typed_slice_sources_assert_current <- function(bundle,
    request, .authenticated_native_spaces = character()) {
  stage <- attr(request, "operation_pack_stage_root")
  graph_enabled <- length(request$graph_read_grants %||% list()) > 0L ||
    length(request$graph_write_grants %||% list()) > 0L
  private_budget <- .wb_operation_pack_v3_broker_projection_budget(bundle,
    if (graph_enabled) .wb_operation_pack_v4_lowest_graph_budgets(lapply(
      request$graph_write_grants %||% list(), `[[`, "resource_budgets")) else NULL)
  for (grant in Filter(function(x) identical(
      x$source_reference$source_kind, "in_memory_selected_projection"),
      request$typed_slice_grants %||% list()))
    .wb_operation_pack_v3_private_source_validate(stage, grant, bounded = TRUE,
      budget = private_budget)
  durable <- Filter(function(x) identical(
    x$source_reference$source_kind, "bundle_matrix"),
    request$typed_slice_grants %||% list())
  spaces <- request$typed_space_grants %||% list()
  if (!length(durable) && !length(spaces)) return(invisible(TRUE))
  # Authenticate the exact stage-visible bytes, including stage-only
  # predecessors, against both the source reference and grant identity.
  for (grant in durable)
    .wb_operation_pack_v3_typed_slice_grant_assert_current(bundle, grant)
  for (grant in spaces) {
    if (as.character(grant$name)[1L] %in% .authenticated_native_spaces) next
    source <- grant$source_reference
    cells <- attr(grant, "operation_pack_v3_cells") %||% character()
    identity <- tryCatch(.wb_operation_pack_v3_space_source_content(bundle,
      source$space_id, cells), error = function(e) NULL)
    if (is.null(identity) ||
        !identical(identity, source$selected_content_identity))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        paste0("Typed-space source changed after authentication for '",
          grant$name, "'."), "audit")
  }
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
                                           producer_lineage_reads = list(),
                                           typed_slice_usage = list(),
                                           typed_space_usage = list(),
                                           model_payload_reads = list(),
                                           self_linked_model_payload_reads = list(),
                                           artifact_collection_usage = list(),
                                           named_cell_axis_collection_usage = list(),
                                           optional_display_axis_group_usage = list(),
                                           supported_external_state_adoption_state = NULL,
                                           supported_external_state_adoption_attestations = list(),
                                           derived_cell_output_axis_declarations = list(),
                                           derived_fitted_axis_state = NULL,
                                           standalone_sparse_cell_family_state = NULL,
                                           sealed_relation_family_state = NULL) {
  hook <- getOption("scworkbench.operation_pack_v3_output_test_hook", NULL)
  if (is.function(hook)) {
    replacement <- hook(writes = writes, request = request,
      operation = operation)
    if (!is.null(replacement)) writes <- replacement
  }
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
  base_request$typed_slice_grants <- NULL
  base_request$typed_space_grants <- NULL
  base_request$provenance_reads <- NULL
  base_request$producer_lineage_grants <- NULL
  base_request$self_linked_model_payload_grants <- NULL
  base_request$artifact_collection_grants <- NULL
  base_request$named_cell_axis_collection_grants <- NULL
  base_request$optional_display_axis_group_grants <- NULL
  base_request$supported_external_state_adoption_grants <- NULL
  base_request$derived_cell_output_axis_grants <- NULL
  base_request$derived_fitted_axis_grants <- NULL
  base_request$standalone_sparse_cell_family_grants <- NULL
  base_request$sealed_relation_family_grants <- NULL
  base_request$runtime_cell_family_key_grants <- NULL
  for (i in seq_along(base_request$outputs)) {
    base_request$outputs[[i]]$descriptor$cardinality_grant <- NULL
    base_request$outputs[[i]]$descriptor$sparse_membership_grant <- NULL
    base_request$outputs[[i]]$descriptor$pseudobulk_grant <- NULL
    base_request$outputs[[i]]$descriptor$derived_cell_output_axis_policy <- NULL
    base_request$outputs[[i]]$descriptor$
      standalone_sparse_cell_family_provisional_grant <- NULL
    base_request$outputs[[i]]$descriptor$
      sealed_relation_family_provisional_grant <- NULL
    base_request$outputs[[i]]$descriptor$grant_identity$scheme <-
      "scworkbench.operation_pack.output_grant.v2"
  }
  sealed_axes <- .wb_operation_pack_v3_g7_seal(request,
    derived_cell_output_axis_declarations)
  if (length(sealed_axes)) for (state in sealed_axes) {
    for (linked in state$grant$linked_output_closure$linked_outputs) {
      name <- as.character(linked$name)[1]
      index <- match(name, vapply(base_request$outputs, `[[`, character(1),
        "name"))
      request_index <- match(name, vapply(request$outputs, `[[`,
        character(1), "name"))
      cardinality <- .wb_operation_pack_v3_g7_sealed_cardinality(
        request$outputs[[request_index]], state)
      base_request$outputs[[index]]$descriptor$expected_dimensions <-
        cardinality$expected_dimensions
      value_cells <- .wb_operation_pack_v2_primitive_cells(
        writes[[name]]$value)
      base_request$outputs[[index]]$descriptor$expected_cell_order_identity <-
        .wb_operation_pack_v2_identity_plain("scworkbench.cell_order.v1",
          unname(as.list(value_cells)))
    }
  }
  fitted_state <- derived_fitted_axis_state$derived_fitted_axis %||% NULL
  if (length(request$derived_fitted_axis_grants %||% list())) {
    if (is.null(fitted_state)) .wb_operation_pack_v3_error(
      "PYBENCH_RECEIPT_MISMATCH",
      "Derived fitted-cell axis was not declared and sealed.", "receipt")
    fitted <- as.character(unlist(fitted_state$seal$fitted_cell_ids,
      use.names = FALSE))
    for (sealed in fitted_state$sibling_grants) {
      index <- match(as.character(sealed$name)[1], vapply(
        base_request$outputs, `[[`, character(1), "name"))
      base_request$outputs[[index]]$descriptor$expected_dimensions <-
        unname(as.list(.wb_operation_pack_v2_dimensions(
          writes[[sealed$name]]$value, sealed$kind)))
      base_request$outputs[[index]]$descriptor$expected_cell_order_identity <-
        .wb_operation_pack_v2_identity_plain("scworkbench.cell_order.v1",
          unname(as.list(.wb_operation_pack_v2_primitive_cells(
            writes[[sealed$name]]$value))))
    }
  }
  sparse_layout <- standalone_sparse_cell_family_state$
    standalone_sparse_cell_family %||% NULL
  sparse_grants <- request$standalone_sparse_cell_family_grants %||% list()
  if (length(sparse_grants)) {
    if (is.null(sparse_layout))
      .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
        "Sparse-family output has no sealed layout.", "receipt")
    sparse_name <- as.character(sparse_grants[[1L]]$output_name)[1]
    index <- match(sparse_name, vapply(base_request$outputs, `[[`,
      character(1), "name"))
    base_request$outputs[[index]]$descriptor$expected_dimensions <-
      sparse_layout$writer$exact_dimensions
    base_request$outputs[[index]]$descriptor$
      expected_cell_order_identity <- .wb_operation_pack_v2_identity_plain(
        "scworkbench.cell_order.v1", unname(as.list(vapply(
          sparse_layout$pairs, function(x) as.character(x$cell_id)[1],
          character(1)))))
  }
  relation_layout <- sealed_relation_family_state$
    sealed_relation_family %||% NULL
  relation_grants <- request$sealed_relation_family_grants %||% list()
  if (length(relation_grants)) {
    if (is.null(relation_layout)) .wb_operation_pack_v3_error(
      "PYBENCH_RECEIPT_MISMATCH",
      "Relation output has no sealed row declaration.", "receipt")
    name <- as.character(relation_grants[[1L]]$output_name)[1]
    index <- match(name, vapply(base_request$outputs, `[[`,
      character(1), "name"))
    base_request$outputs[[index]]$descriptor$expected_dimensions <-
      relation_layout$writer$exact_dimensions
    base_request$outputs[[index]]$descriptor$
      expected_cell_order_identity <- .wb_operation_pack_v2_identity_plain(
        "scworkbench.cell_order.v1", unname(as.list(vapply(
          relation_layout$declaration$ordered_pairs,
          function(x) as.character(x$cell_id)[1], character(1)))))
  }
  receipt <- .wb_operation_pack_v2_receipt(base_request, registration,
    projected, writes, preflight, registry_reads)
  grants <- stats::setNames(request$outputs,
    vapply(request$outputs, `[[`, character(1), "name"))
  policies <- .wb_operation_pack_v3_policy_map(operation)
  axis_grants <- stats::setNames(request$parameter_axis_grants %||% list(),
    vapply(request$parameter_axis_grants %||% list(), function(x)
      as.character(x$name)[1], character(1)))
  observed <- c(receipt$outputs %||% list(),
    receipt$registry_requests %||% list())
  sparse_observations <- list()
  for (i in seq_along(observed)) {
    name <- as.character(observed[[i]]$name)[1]
    descriptor <- observed[[i]]$descriptor
    descriptor$grant_identity <- grants[[name]]$descriptor$grant_identity
    cardinality <- grants[[name]]$descriptor$cardinality_grant %||% NULL
    if (!is.null(cardinality)) {
      registry_records <- stats::setNames(request$registry_reads %||% list(),
        vapply(request$registry_reads %||% list(), `[[`, character(1), "name"))
      cells <- .wb_operation_pack_v3_effective_cell_axis(policies[[name]],
        inputs, registry_records = registry_records,
        effective_cells = attr(cardinality, "operation_pack_v3_cells"))$cells
      attr(cardinality, "operation_pack_v3_cells") <- cells
      descriptor$observed_cardinality <-
        .wb_operation_pack_v3_observe_cardinality(writes[[name]]$value,
          cardinality)
      descriptor$dimensions <- unname(as.list(
        .wb_operation_pack_v2_dimensions(writes[[name]]$value,
          as.character(descriptor$kind)[1])))
    }
    sparse_grant <- grants[[name]]$descriptor$sparse_membership_grant %||%
      NULL
    if (!is.null(sparse_grant)) {
      query_name <- as.character(sparse_grant$output)[1]
      policy <- policies[[query_name]]
      space_map <- stats::setNames(request$typed_space_grants %||% list(),
        vapply(request$typed_space_grants %||% list(), `[[`, character(1),
          "name"))
      attr(sparse_grant, "operation_pack_v3_query_cells") <- attr(
        space_map[[as.character(policy$query_space_read)[1]]],
        "operation_pack_v3_cells")
      attr(sparse_grant, "operation_pack_v3_candidate_cells") <- attr(
        space_map[[as.character(policy$candidate_space_read)[1]]],
        "operation_pack_v3_cells")
      sparse_observations[[name]] <-
        .wb_operation_pack_v3_sparse_ledger(writes[[name]]$value,
          sparse_grant)
      descriptor$observed_sparse_membership <- sparse_observations[[name]]
      descriptor$dimensions <- unname(as.list(
        .wb_operation_pack_v2_dimensions(writes[[name]]$value,
          as.character(descriptor$kind)[1])))
    }
    policy <- policies[[name]]
    if (!is.null(policy) && as.character(policy$policy)[1] %in% c(
        "cell_by_parameter_axis_v1",
        "feature_parameter_axis_cartesian_v1",
        "one_per_parameter_axis_v1", "singleton_parameter_echo_v1")) {
      axis_name <- as.character(policy$dimension_axis %||%
        policy$parameter_axis)[1]
      descriptor$observed_parameter_axis <-
        .wb_operation_pack_v3_parameter_axis_observe(
          writes[[name]]$value, policy, axis_grants[[axis_name]])
      descriptor$dimensions <- descriptor$observed_parameter_axis$dimensions
    }
    fragment_manifest <- writes[[name]]$value$fragment_manifest %||% NULL
    if (!is.null(fragment_manifest)) {
      descriptor$matrix_fragment_manifest <- fragment_manifest
      descriptor$matrix_fragment_manifest_identity <-
        .wb_operation_pack_v3_unscoped_identity(
          fragment_manifest$fragment_manifest_identity)
      descriptor$content_identity <-
        .wb_operation_pack_v2_identity_plain(
          "scworkbench.matrix.content.v1", list(
            dimensions = fragment_manifest$dimensions,
            feature_order_identity = fragment_manifest$feature_order_identity,
            cell_order_identity = fragment_manifest$cell_order_identity,
            fragment_content_identities = lapply(
              fragment_manifest$fragments, `[[`, "content_identity")))
      descriptor$payload_manifest_identity <-
        .wb_operation_pack_v2_identity_plain(
          "scworkbench.operation_pack.payload_manifest.v2", list(
            fragment_manifest_identity =
              fragment_manifest$fragment_manifest_identity,
            fragment_payload_identities = lapply(
              fragment_manifest$fragments, `[[`,
              "payload_manifest_identity")))
    }
    model_tree <- writes[[name]]$tree_manifest %||% NULL
    if (!is.null(model_tree)) {
      write_grant <- grants[[name]]$descriptor$contained_model_write_grant %||%
        grants[[name]]$descriptor$contained_model_sibling_write_grant %||%
        grants[[name]]$descriptor$
          contained_matrix_model_sibling_write_grant %||%
        if (!is.null(fitted_state) && identical(as.character(
          fitted_state$model_grant$output)[1], name))
          fitted_state$model_grant else NULL
      sibling_closure <- as.character(write_grant$schema)[1] %in% c(
        "scworkbench.operation_pack.contained_model_sibling_write_grant.v1",
        "scworkbench.operation_pack.contained_matrix_model_sibling_write_grant.v1",
        "scworkbench.operation_pack.sealed_model_sibling_grant.v1")
      linkage <- if (sibling_closure)
        writes[[name]]$value$model_source_linkage else
          writes[[name]]$value$model_linkage
      descriptor$content_identity <- .wb_operation_pack_v2_identity_plain(
        "scworkbench.model_ref.content.v1", list(
          engine = model_tree$engine, model_type = model_tree$model_type,
          linkage_identity = .wb_operation_pack_v3_unscoped_identity(
            linkage$linkage_identity),
          tree_manifest_identity = .wb_operation_pack_v3_unscoped_identity(
            model_tree$manifest_identity)))
      descriptor$payload_manifest_identity <-
        .wb_operation_pack_v3_model_payload_identity(model_tree)
      descriptor$model_linkage <- grants[[name]]$descriptor$
        expected_model_linkage
      descriptor$model_linkage_identity <-
        .wb_operation_pack_v3_unscoped_identity(
          linkage$linkage_identity)
      descriptor$contained_payload <- list(contained = TRUE,
        no_symlinks = TRUE,
        payload_tree_identity = .wb_operation_pack_v2_identity_plain(
          "scworkbench.operation_pack.contained_payload.v2",
          .wb_operation_pack_v3_unscoped_identity(
            model_tree$manifest_identity)))
      if (!sibling_closure) descriptor$contained_model_tree <- list(
          engine = model_tree$engine, model_type = model_tree$model_type,
          primary_path = model_tree$primary_path,
          file_count = model_tree$file_count,
          total_size = model_tree$total_size,
          tree_manifest_identity = .wb_operation_pack_v3_unscoped_identity(
            model_tree$manifest_identity),
          payload_manifest_identity = descriptor$payload_manifest_identity,
          source_space_binding_identity = .wb_operation_pack_v2_identity_plain(
            "scworkbench.operation_pack.model_source_space.v1",
            write_grant$source_space),
          paired_space_observed_descriptor_identity = list(
            scheme = "scworkbench.operation_pack.observed_output.v3",
            sha256 = paste(rep("0", 64L), collapse = "")),
          status = "validated_not_published")
    }
    descriptor$observed_descriptor_identity <- NULL
    observed_scheme <- if (identical(as.character(descriptor$category)[1],
        "core_registry_request")) {
      "scworkbench.operation_pack.observed_registry_request.v2"
    } else {
      "scworkbench.operation_pack.observed_output.v3"
    }
    descriptor$observed_descriptor_identity <-
      .wb_operation_pack_v2_identity_scoped(observed_scheme,
        "descriptor excluding observed_descriptor_identity", descriptor)
    observed[[i]]$descriptor <- descriptor
  }
  if (length(sparse_observations)) {
    for (name in names(sparse_observations)) {
      partner <- as.character(grants[[name]]$descriptor$
        sparse_membership_grant$partner_output)[1]
      if (is.null(sparse_observations[[partner]]) ||
          !identical(sparse_observations[[name]]$edge_ledger_identity,
            sparse_observations[[partner]]$edge_ledger_identity) ||
          !identical(sparse_observations[[name]]$edge_ledger,
            sparse_observations[[partner]]$edge_ledger))
        .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
          "Sparse membership outputs do not expose the same edge ledger.",
          "audit")
    }
  }
  for (i in seq_along(observed)) {
    name <- as.character(observed[[i]]$name)[1]
    grant <- grants[[name]]$descriptor$pseudobulk_grant %||% NULL
    if (is.null(grant)) next
    membership <- sparse_observations[[as.character(
      grant$membership_output)[1]]]
    if (is.null(membership)) .wb_operation_pack_v3_error(
      "PYBENCH_OUTPUT_INVALID",
      "Pseudobulk output has no validated membership companion.", "audit")
    observed[[i]]$descriptor$observed_pseudobulk <-
      .wb_operation_pack_v3_pseudobulk_observe(writes[[name]]$value,
        grant, membership)
    observed[[i]]$descriptor$observed_descriptor_identity <- NULL
    observed[[i]]$descriptor$observed_descriptor_identity <-
      .wb_operation_pack_v2_identity_scoped(
        "scworkbench.operation_pack.observed_output.v3",
        "descriptor excluding observed_descriptor_identity",
        observed[[i]]$descriptor)
  }
  # Close the model/embedding observation only after both descriptors exist,
  # avoiding a sibling grant or observation hash cycle.
  observed_names <- vapply(observed, `[[`, character(1), "name")
  for (i in seq_along(observed)) {
    output_name <- observed_names[[i]]
    declaration <- operation$outputs[[match(output_name, vapply(
      operation$outputs, `[[`, character(1), "name"))]]
    sibling_policy <- declaration$contained_model_sibling_closure_policy %||%
      NULL
    matrix_policy <- declaration$
      matrix_trained_contained_model_closure_policy %||% NULL
    if (!is.null(matrix_policy)) {
      grant <- grants[[output_name]]$descriptor$
        contained_matrix_model_sibling_write_grant
      model_tree <- writes[[output_name]]$tree_manifest
      sibling_names <- as.character(unlist(
        matrix_policy$required_sibling_terminals, use.names = FALSE))
      siblings <- lapply(sibling_names, function(name)
        observed[[match(name, observed_names)]])
      if (is.null(model_tree) || any(vapply(siblings, is.null, logical(1))))
        .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
          "Matrix-trained model closure is incomplete.", "audit")
      for (j in seq_along(siblings)) {
        expected_axis <- grant$required_sibling_terminals[[j]]$
          expected_cell_order_identity_if_cell_indexed
        actual_axis <- siblings[[j]]$descriptor$cell_order_identity %||% NULL
        if (!is.null(expected_axis) && !identical(expected_axis, actual_axis))
          .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
            "Matrix-trained latent space axis differs from fitted cells.",
            "audit")
      }
      paired <- siblings[[1L]]$descriptor
      if (!identical(as.integer(unlist(paired$dimensions,
          use.names = FALSE)), as.integer(unlist(grant$
          paired_space_output$expected_dimensions, use.names = FALSE))))
        .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
          "Matrix-trained latent dimensions differ from the grant.", "audit")
      tree <- list(schema =
          "scworkbench.operation_pack.matrix_model_sibling_closure_observation.v1",
        write_grant_identity = .wb_operation_pack_v3_unscoped_identity(
          grant$write_grant_identity), tree_manifest = model_tree,
        tree_manifest_identity = .wb_operation_pack_v3_unscoped_identity(
          model_tree$manifest_identity),
        payload_manifest_identity =
          .wb_operation_pack_v3_model_payload_identity(model_tree),
        model_source_linkage_identity =
          .wb_operation_pack_v3_unscoped_identity(
            grant$model_source_linkage$linkage_identity),
        paired_fitted_space_id = grant$model_source_linkage$
          paired_fitted_space_id,
        paired_space_content_identity = paired$content_identity,
        ordered_sibling_observed_descriptor_identities = lapply(siblings,
          function(x) .wb_operation_pack_v3_unscoped_identity(
            x$descriptor$observed_descriptor_identity)),
        model_sibling_closure_identity = grant$model_sibling_closure_identity,
        loadability_status = "contained_tree_authenticated")
      tree$observation_identity <- .wb_operation_pack_v2_identity_scoped(
        tree$schema, "observation excluding observation_identity", tree)
      observed[[i]]$descriptor$contained_matrix_model_sibling_tree <- tree
      observed[[i]]$descriptor$observed_descriptor_identity <- NULL
      observed[[i]]$descriptor$observed_descriptor_identity <-
        .wb_operation_pack_v2_identity_scoped(
          "scworkbench.operation_pack.observed_output.v3",
          "descriptor excluding observed_descriptor_identity",
          observed[[i]]$descriptor)
      next
    }
    if (!is.null(sibling_policy) &&
        is.null(declaration$derived_fitted_axis_policy)) {
      grant <- grants[[output_name]]$descriptor$
        contained_model_sibling_write_grant
      model_tree <- writes[[output_name]]$tree_manifest
      sibling_names <- as.character(unlist(
        sibling_policy$required_sibling_terminals, use.names = FALSE))
      sibling_observed <- lapply(sibling_names, function(name)
        observed[[match(name, observed_names)]])
      if (any(vapply(sibling_observed, is.null, logical(1))))
        .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
          "Sibling-bound model closure is incomplete.", "audit")
      for (j in seq_along(sibling_observed)) {
        expected_axis <- grant$required_sibling_terminals[[j]]$
          expected_cell_order_identity_if_cell_indexed
        actual_axis <- sibling_observed[[j]]$descriptor$
          cell_order_identity %||% NULL
        if (!is.null(expected_axis) && !identical(expected_axis, actual_axis))
          .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
            "Sibling-bound output cell axis differs from the fitted axis.",
            "audit")
      }
      tree <- list(schema =
          "scworkbench.operation_pack.contained_model_sibling_tree_observation.v1",
        write_grant_identity = .wb_operation_pack_v3_unscoped_identity(
          grant$write_grant_identity), tree_manifest = model_tree,
        tree_manifest_identity = .wb_operation_pack_v3_unscoped_identity(
          model_tree$manifest_identity),
        payload_manifest_identity =
          .wb_operation_pack_v3_model_payload_identity(model_tree),
        model_source_linkage_identity =
          .wb_operation_pack_v3_unscoped_identity(
            grant$model_source_linkage$linkage_identity),
        ordered_sibling_observed_descriptor_identities = lapply(
          sibling_observed, function(x) .wb_operation_pack_v3_unscoped_identity(
            x$descriptor$observed_descriptor_identity)),
        model_sibling_closure_identity = grant$model_sibling_closure_identity,
        loadability_status = "contained_tree_authenticated")
      tree$observation_identity <- .wb_operation_pack_v2_identity_scoped(
        tree$schema, "observation excluding observation_identity", tree)
      observed[[i]]$descriptor$contained_model_sibling_tree <- tree
      observed[[i]]$descriptor$observed_descriptor_identity <- NULL
      observed[[i]]$descriptor$observed_descriptor_identity <-
        .wb_operation_pack_v2_identity_scoped(
          "scworkbench.operation_pack.observed_output.v3",
          "descriptor excluding observed_descriptor_identity",
          observed[[i]]$descriptor)
      next
    }
    tree <- observed[[i]]$descriptor$contained_model_tree %||% NULL
    if (is.null(tree)) next
    paired_name <- as.character(declaration$contained_model_policy$
      paired_space_output)[1]
    paired <- observed[[match(paired_name, observed_names)]]$descriptor
    tree$paired_space_observed_descriptor_identity <-
      .wb_operation_pack_v3_unscoped_identity(
        paired$observed_descriptor_identity)
    tree$observation_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.contained_model_tree_observation.v1",
      "observation excluding observation_identity", tree)
    observed[[i]]$descriptor$contained_model_tree <- tree
    observed[[i]]$descriptor$observed_descriptor_identity <- NULL
    observed[[i]]$descriptor$observed_descriptor_identity <-
      .wb_operation_pack_v2_identity_scoped(
        "scworkbench.operation_pack.observed_output.v3",
        "descriptor excluding observed_descriptor_identity",
        observed[[i]]$descriptor)
  }
  g7_applied <- .wb_operation_pack_v3_g7_apply_outputs(request, observed,
    writes, sealed_axes)
  observed <- g7_applied$observed
  fitted_observations <- .wb_operation_pack_v3_dfa_observation(request,
    derived_fitted_axis_state, observed, writes)
  if (length(fitted_observations)) {
    fitted <- fitted_observations[[1L]]
    model_name <- as.character(fitted_state$model_grant$output)[1]
    model_index <- match(model_name, vapply(observed, `[[`, character(1),
      "name"))
    tree <- writes[[model_name]]$tree_manifest
    tree_observation <- list(schema =
        "scworkbench.operation_pack.derived_fitted_model_tree_observation.v1",
      sealed_model_grant_identity = .wb_operation_pack_v3_unscoped_identity(
        fitted_state$model_grant$sealed_grant_identity),
      tree_manifest = tree,
      tree_manifest_identity = .wb_operation_pack_v3_unscoped_identity(
        tree$manifest_identity), payload_manifest_identity =
        .wb_operation_pack_v3_model_payload_identity(tree),
      model_source_linkage_identity = .wb_operation_pack_v3_unscoped_identity(
        fitted_state$model_source_linkage$linkage_identity),
      status = "complete")
    tree_observation$observation_identity <-
      .wb_operation_pack_v2_identity_scoped(tree_observation$schema,
        "observation excluding observation_identity", tree_observation)
    observed[[model_index]]$descriptor$contained_model_sibling_tree <-
      tree_observation
    observed[[model_index]]$descriptor$observed_descriptor_identity <- NULL
    observed[[model_index]]$descriptor$observed_descriptor_identity <-
      .wb_operation_pack_v2_identity_scoped(
        "scworkbench.operation_pack.observed_output.v3",
        "descriptor excluding observed_descriptor_identity",
        observed[[model_index]]$descriptor)
    fitted_observations <- .wb_operation_pack_v3_dfa_observation(request,
      derived_fitted_axis_state, observed, writes)
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
  if (length(provenance_reads)) receipt$provenance_reads <- provenance_reads
  if (length(producer_lineage_reads))
    receipt$producer_lineage_reads <- producer_lineage_reads
  if (length(typed_slice_usage)) receipt$typed_slice_usage <- typed_slice_usage
  if (length(typed_space_usage)) receipt$typed_space_usage <- typed_space_usage
  if (length(model_payload_reads))
    receipt$model_payload_reads <- model_payload_reads
  if (length(self_linked_model_payload_reads))
    receipt$self_linked_model_payload_reads <- self_linked_model_payload_reads
  if (length(artifact_collection_usage))
    receipt$artifact_collection_usage <- artifact_collection_usage
  if (length(named_cell_axis_collection_usage))
    receipt$named_cell_axis_collection_usage <- named_cell_axis_collection_usage
  if (length(optional_display_axis_group_usage))
    receipt$optional_display_axis_group_usage <- optional_display_axis_group_usage
  adoption_observations <- .wb_operation_pack_v3_g3_observations(request,
    receipt, supported_external_state_adoption_state,
    supported_external_state_adoption_attestations)
  if (length(adoption_observations))
    receipt$supported_external_state_adoption_observations <-
      adoption_observations
  if (length(g7_applied$observations))
    receipt$derived_cell_output_axis_observations <-
      g7_applied$observations
  if (length(fitted_observations))
    receipt$derived_fitted_axis_observations <- fitted_observations
  sparse_family_observations <- .wb_operation_pack_v3_sscf_observation(
    request, standalone_sparse_cell_family_state, receipt$outputs, writes)
  if (length(sparse_family_observations))
    receipt$sparse_cell_family_observations <-
      sparse_family_observations
  relation_observations <- .wb_operation_pack_v3_rf_observation(
    request, sealed_relation_family_state, receipt$outputs, writes)
  if (length(relation_observations))
    receipt$sealed_relation_family_observations <- relation_observations
  runtime_key_observations <- .wb_operation_pack_v3_rfk_observation(
    request, standalone_sparse_cell_family_state, receipt)
  if (length(runtime_key_observations))
    receipt$runtime_cell_family_key_observations <-
      runtime_key_observations
  publication_observations <- lapply(Filter(function(x)
    !is.null(x$descriptor$publication_grant), request$outputs), function(grant) {
      output <- observed[[match(grant$name, vapply(observed, `[[`,
        character(1), "name"))]]
      closure <- as.character(unlist(grant$descriptor$publication_grant$
        closure_outputs, use.names = FALSE))
      closure_records <- lapply(sort(closure, method = "radix"), function(name) {
        item <- observed[[match(name, vapply(observed, `[[`, character(1),
          "name"))]]
        list(name = name, observed_descriptor_identity =
          .wb_operation_pack_v3_unscoped_identity(
            item$descriptor$observed_descriptor_identity))
      })
      preimage <- grant$descriptor$publication_grant$preimage
      preimage_identity <- .wb_operation_pack_v2_identity_plain(
        "scworkbench.operation_pack.materialization_preimage.v1", preimage)
      space2d <- identical(grant$descriptor$publication_grant$schema,
        "scworkbench.operation_pack.space_2d_publication_grant.v1")
      value <- if (space2d) list(schema =
          "scworkbench.operation_pack.observed_space_2d_publication.v1",
        publication_grant_identity =
          .wb_operation_pack_v3_unscoped_identity(grant$descriptor$
            publication_grant$publication_grant_identity),
        mode = grant$descriptor$publication_grant$mode,
        preimage_identity = preimage_identity,
        source_model_binding_identity =
          .wb_operation_pack_v2_identity_plain(
            "scworkbench.operation_pack.model_binding.v1",
            grant$descriptor$publication_grant$source_model_binding),
        candidate_observed_descriptor_identity =
          .wb_operation_pack_v3_unscoped_identity(
            output$descriptor$observed_descriptor_identity),
        selected_cell_order_identity = grant$descriptor$publication_grant$
          selected_cells$order_identity,
        expected_final_cell_order_identity = grant$descriptor$
          publication_grant$expected_final_cell_order_identity,
        closure_output_identities = closure_records,
        status = "validated_not_published") else list(schema =
          "scworkbench.operation_pack.observed_materialization_publication.v1",
        publication_grant_identity =
          .wb_operation_pack_v3_unscoped_identity(grant$descriptor$
            publication_grant$publication_grant_identity),
        mode = grant$descriptor$publication_grant$mode,
        preimage_identity = preimage_identity,
        output_observed_descriptor_identity =
          .wb_operation_pack_v3_unscoped_identity(
            output$descriptor$observed_descriptor_identity),
        closure_output_identities = closure_records,
        status = "validated_not_published")
      observation_scheme <- if (space2d)
        "scworkbench.operation_pack.observed_space_2d_publication.v1" else
        "scworkbench.operation_pack.observed_materialization_publication.v1"
      value$observation_identity <- .wb_operation_pack_v2_identity_scoped(
        observation_scheme, "observation excluding observation_identity",
        value)
      value
    })
  if (length(publication_observations))
    receipt$publication_observations <- publication_observations
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
    if (!is.null(grant$sparse_membership_grant)) {
      .wb_operation_pack_v3_assert_self_identity(
        item$descriptor$observed_sparse_membership,
        "observation_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
      if (!identical(item$descriptor$observed_sparse_membership$grant_identity,
          .wb_operation_pack_v3_unscoped_identity(
            grant$sparse_membership_grant$grant_identity)))
        .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
          "Sparse-membership observation refers to the wrong grant.",
          "receipt")
    }
    if (!is.null(grant$pseudobulk_grant)) {
      .wb_operation_pack_v3_assert_self_identity(
        item$descriptor$observed_pseudobulk, "observation_identity",
        "PYBENCH_RECEIPT_MISMATCH", "receipt")
    }
    if (!is.null(grant$contained_matrix_model_sibling_write_grant)) {
      write_grant <- grant$contained_matrix_model_sibling_write_grant
      tree <- item$descriptor$contained_matrix_model_sibling_tree
      .wb_operation_pack_v3_assert_matrix_model_linkage(
        write_grant$model_source_linkage, "PYBENCH_RECEIPT_MISMATCH",
        "receipt")
      .wb_operation_pack_v3_assert_self_identity(write_grant,
        "write_grant_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
      .wb_operation_pack_v3_assert_self_identity(tree,
        "observation_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
      siblings <- lapply(write_grant$required_sibling_terminals,
        function(x) observed[[match(x$name, vapply(observed, `[[`,
          character(1), "name"))]])
      if (any(vapply(siblings, is.null, logical(1))))
        .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
          "Matrix-trained model receipt omits a sibling.", "receipt")
      expected <- lapply(siblings, function(x)
        .wb_operation_pack_v3_unscoped_identity(
          x$descriptor$observed_descriptor_identity))
      paired <- siblings[[1L]]$descriptor
      if (!identical(tree$write_grant_identity,
          .wb_operation_pack_v3_unscoped_identity(
            write_grant$write_grant_identity)) ||
          !identical(tree$model_source_linkage_identity,
            .wb_operation_pack_v3_unscoped_identity(
              write_grant$model_source_linkage$linkage_identity)) ||
          !identical(tree$paired_fitted_space_id,
            write_grant$model_source_linkage$paired_fitted_space_id) ||
          !identical(tree$paired_fitted_space_id,
            write_grant$paired_space_output$allocated_id) ||
          !identical(tree$paired_space_content_identity,
            paired$content_identity) ||
          !identical(tree$ordered_sibling_observed_descriptor_identities,
            expected) ||
          !identical(tree$model_sibling_closure_identity,
            write_grant$model_sibling_closure_identity) ||
          !identical(tree$loadability_status,
            "contained_tree_authenticated"))
        .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
          "Matrix-trained model receipt differs from complete closure.",
          "receipt")
    }
    if (!is.null(grant$parameter_axis_grant_identity) &&
        !identical(item$descriptor$observed_parameter_axis$
          parameter_axis_grant_identity,
          grant$parameter_axis_grant_identity))
      .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
        "Observed output refers to the wrong parameter-axis grant.",
        "receipt")
    if (!is.null(grant$matrix_fragment_grant)) {
      .wb_operation_pack_v3_assert_self_identity(
        item$descriptor$matrix_fragment_manifest,
        "fragment_manifest_identity", "PYBENCH_RECEIPT_MISMATCH",
        "receipt")
      if (!identical(item$descriptor$matrix_fragment_manifest$
          source_fragment_schedule_identity,
          grant$matrix_fragment_grant$source_fragment_schedule$
            schedule_identity))
        .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
          "Matrix fragment receipt refers to the wrong source schedule.",
          "receipt")
    }
    if (!is.null(grant$contained_model_write_grant)) {
      .wb_operation_pack_v3_assert_self_identity(
        grant$contained_model_write_grant, "write_grant_identity",
        "PYBENCH_RECEIPT_MISMATCH", "receipt")
      .wb_operation_pack_v3_assert_self_identity(
        item$descriptor$contained_model_tree, "observation_identity",
        "PYBENCH_RECEIPT_MISMATCH", "receipt")
    }
    if (!is.null(grant$contained_model_sibling_write_grant)) {
      write_grant <- grant$contained_model_sibling_write_grant
      tree <- item$descriptor$contained_model_sibling_tree
      .wb_operation_pack_v3_assert_self_identity(write_grant,
        "write_grant_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
      .wb_operation_pack_v3_assert_self_identity(tree,
        "observation_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
      expected <- lapply(write_grant$required_sibling_terminals,
        function(x) {
          sibling <- observed[[match(x$name, vapply(observed, `[[`,
            character(1), "name"))]]
          .wb_operation_pack_v3_unscoped_identity(
            sibling$descriptor$observed_descriptor_identity)
        })
      if (!identical(tree$write_grant_identity,
          .wb_operation_pack_v3_unscoped_identity(
            write_grant$write_grant_identity)) ||
          !identical(tree$model_source_linkage_identity,
            .wb_operation_pack_v3_unscoped_identity(
              write_grant$model_source_linkage$linkage_identity)) ||
          !identical(tree$model_sibling_closure_identity,
            write_grant$model_sibling_closure_identity) ||
          !identical(tree$ordered_sibling_observed_descriptor_identities,
            expected) || !identical(tree$loadability_status,
              "contained_tree_authenticated"))
        .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
          "Sibling-bound model tree observation differs from its exact closure.",
          "receipt")
    }
  }
  .wb_operation_pack_v3_g7_receipt_audit(receipt, request)
  publication_grants <- Filter(function(x)
    !is.null(x$descriptor$publication_grant), request$outputs)
  observations <- receipt$publication_observations %||% list()
  if (length(publication_grants) != length(observations))
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "Publication observations are not a bijection with grants.",
      "receipt")
  for (observation in observations) {
    .wb_operation_pack_v3_assert_self_identity(observation,
      "observation_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
    if (!identical(as.character(observation$status)[1],
        "validated_not_published"))
      .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
        "Pack receipt may not claim durable publication.", "receipt")
  }
  adoption_grants <- request$supported_external_state_adoption_grants %||%
    list()
  adoption_observations <- receipt$
    supported_external_state_adoption_observations %||% list()
  if (length(adoption_grants) != length(adoption_observations))
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "External-state adoption observations are not a bijection with grants.",
      "receipt")
  for (i in seq_along(adoption_observations)) {
    grant <- adoption_grants[[i]]; observation <- adoption_observations[[i]]
    .wb_operation_pack_v3_assert_self_identity(observation,
      "observation_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
    if (!identical(observation$grant_identity,
        .wb_operation_pack_v3_unscoped_identity(grant$grant_identity)) ||
        !identical(observation$source_byte_evidence,
          grant$source_byte_evidence) ||
        !identical(observation$candidate_tree_manifest_identity,
          grant$candidate_snapshot$tree_manifest_identity) ||
        !identical(observation$candidate_payload_manifest_identity,
          grant$candidate_snapshot$payload_manifest_identity) ||
        !identical(observation$adopted_model_tree_manifest_identity,
          grant$candidate_snapshot$tree_manifest_identity) ||
        !identical(observation$adopted_model_payload_manifest_identity,
          grant$candidate_snapshot$payload_manifest_identity) ||
        !isTRUE(observation$pack_source_association_attestation) ||
        !isTRUE(observation$pack_no_refit_attestation))
      .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
        "External-state adoption observation differs from its exact grant.",
        "receipt")
  }
  fitted_grants <- request$derived_fitted_axis_grants %||% list()
  fitted_observations <- receipt$derived_fitted_axis_observations %||% list()
  if (length(fitted_grants) != length(fitted_observations))
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "Derived fitted-axis observations are not a bijection with grants.",
      "receipt")
  for (i in seq_along(fitted_observations)) {
    grant <- fitted_grants[[i]]
    observation <- fitted_observations[[i]]
    .wb_operation_pack_v3_assert_self_identity(observation,
      "observation_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
    .wb_operation_pack_v3_assert_self_identity(observation$seal,
      "seal_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
    .wb_operation_pack_v3_assert_model_source_linkage_v3(
      observation$model_source_linkage, "PYBENCH_RECEIPT_MISMATCH",
      "receipt")
    for (coverage in observation$sibling_coverage_observations)
      .wb_operation_pack_v3_assert_self_identity(coverage,
        "observation_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
    expected_names <- vapply(grant$sibling_base_grants, `[[`, character(1),
      "name")
    observed_names <- vapply(observation$sibling_coverage_observations,
      `[[`, character(1), "output_name")
    if (!identical(observation$provisional_grant_identity,
          .wb_operation_pack_v3_unscoped_identity(grant$grant_identity)) ||
        !identical(observation$seal$parent_snapshot_identity,
          .wb_operation_pack_v3_unscoped_identity(
            grant$parent_snapshot$parent_snapshot_identity)) ||
        !identical(observation$seal$session_identity,
          .wb_operation_pack_v3_unscoped_identity(
            grant$session_projection$session_identity)) ||
        !identical(expected_names, observed_names) ||
        !identical(observation$closure_status, "complete"))
      .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
        "Derived fitted-axis observation contradicts its provisional grant.",
        "receipt")
  }
  .wb_operation_pack_v3_dfa_receipt_audit(receipt, request, operation)
  slice_grants <- request$typed_slice_grants %||% list()
  usages <- receipt$typed_slice_usage %||% list()
  if (length(slice_grants) != length(usages))
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "Typed-slice usage is not a bijection with grants.", "receipt")
  for (i in seq_along(usages)) {
    usage <- usages[[i]]
    grant <- slice_grants[[i]]
    .wb_operation_pack_v3_assert_self_identity(usage,
      "usage_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
    if (!identical(usage$grant_identity,
        .wb_operation_pack_v3_unscoped_identity(grant$grant_identity)) ||
        !identical(as.integer(usage$call_count),
          as.integer(length(usage$calls))))
      .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
        "Typed-slice usage differs from its exact grant.", "receipt")
    for (call in usage$calls) {
      .wb_operation_pack_v3_assert_self_identity(call,
        "call_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
      result <- call
      result$schema <- "scworkbench.operation_pack.typed_slice_result.v1"
      result$source_reference_identity <-
        .wb_operation_pack_v3_unscoped_identity(
          grant$source_reference$source_reference_identity)
      result$call_identity <- NULL
      .wb_operation_pack_v3_assert_self_identity(result,
        "slice_result_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
    }
  }
  space_grants <- request$typed_space_grants %||% list()
  space_usages <- receipt$typed_space_usage %||% list()
  if (length(space_grants) != length(space_usages))
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "Typed-space usage is not a bijection with grants.", "receipt")
  for (i in seq_along(space_usages)) {
    usage <- space_usages[[i]]; grant <- space_grants[[i]]
    .wb_operation_pack_v3_assert_self_identity(usage,
      "usage_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
    if (!identical(usage$grant_identity,
        .wb_operation_pack_v3_unscoped_identity(grant$grant_identity)) ||
        !identical(as.integer(usage$call_count),
          as.integer(length(usage$calls))))
      .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
        "Typed-space usage differs from its exact grant.", "receipt")
    for (call in usage$calls)
      .wb_operation_pack_v3_assert_self_identity(call, "call_identity",
        "PYBENCH_RECEIPT_MISMATCH", "receipt")
  }
  for (read in receipt$provenance_reads %||% list())
    .wb_operation_pack_v3_assert_self_identity(read,
      "observed_descriptor_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
  .wb_operation_pack_v3_producer_lineage_receipt_audit(receipt, request)
  model_grants <- request$model_payload_grants %||% list()
  model_reads <- receipt$model_payload_reads %||% list()
  if (length(model_grants) != length(model_reads))
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "Contained-model read observations are not a bijection with grants.",
      "receipt")
  for (i in seq_along(model_reads)) {
    .wb_operation_pack_v3_assert_self_identity(model_reads[[i]],
      "observation_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
    if (!identical(model_reads[[i]]$grant_identity,
        .wb_operation_pack_v3_unscoped_identity(
          model_grants[[i]]$grant_identity)) ||
        !identical(as.integer(model_reads[[i]]$use_count), 1L) ||
        !identical(as.character(model_reads[[i]]$integrity_status)[1],
          "unchanged")) .wb_operation_pack_v3_error(
            "PYBENCH_RECEIPT_MISMATCH",
            "Contained-model read observation differs from its grant.",
            "receipt")
  }
  .wb_operation_pack_v3_phase5_receipt_audit(receipt, request)
  .wb_operation_pack_v3_sscf_receipt_audit(receipt, request,
    stage_root = attr(request, "operation_pack_stage_root"))
  .wb_operation_pack_v3_rf_receipt_audit(receipt, request,
    stage_root = attr(request, "operation_pack_stage_root"))
  .wb_operation_pack_v3_rfk_receipt_audit(receipt, request,
    stage_root = attr(request, "operation_pack_stage_root"))
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
                                                    load_payloads = FALSE,
                                                    graph_connections = list()) {
  fail <- function(code, output = NULL) list(ok = FALSE, code = code,
    output = output)
  checked <- tryCatch({
    schema_assert <- if (identical(request$pack_abi_version, "4"))
      .wb_operation_pack_v4_schema_assert else .wb_operation_pack_v3_schema_assert
    schema_assert(request, "request",
      "PYBENCH_REOPEN_VALIDATION_FAILED")
    schema_assert(receipt, "receipt",
      "PYBENCH_REOPEN_VALIDATION_FAILED")
    if (identical(request$pack_abi_version, "4"))
      .wb_operation_pack_v4_graph_record_assert(request, receipt, path, load_payloads,
        connections = graph_connections)
    .wb_operation_pack_v3_assert_self_identity(request, "request_identity",
      "PYBENCH_REOPEN_VALIDATION_FAILED", "reopen")
    .wb_operation_pack_v3_assert_self_identity(receipt, "receipt_identity",
      "PYBENCH_REOPEN_VALIDATION_FAILED", "reopen")
    .wb_operation_pack_v3_assert_self_identity(request$execution_capability,
      "capability_identity", "PYBENCH_REOPEN_VALIDATION_FAILED", "reopen")
    for (input in request$inputs) .wb_operation_pack_v3_assert_self_identity(
      input$descriptor, "descriptor_identity",
      "PYBENCH_REOPEN_VALIDATION_FAILED", "reopen")
    .wb_operation_pack_v3_g7_request_audit(request)
    .wb_operation_pack_v3_rfk_request_audit(request,
      "PYBENCH_REOPEN_VALIDATION_FAILED", "reopen")
    .wb_operation_pack_v3_g7_receipt_audit(receipt, request)
    .wb_operation_pack_v3_sscf_retained_binding_audit(request)
    attr(request, "operation_pack_stage_root") <- path
    .wb_operation_pack_v3_dfa_receipt_audit(receipt, request)
    .wb_operation_pack_v3_sscf_receipt_audit(receipt, request,
      stage_root = if (isTRUE(load_payloads)) path else NULL,
      code = "PYBENCH_REOPEN_VALIDATION_FAILED", phase = "reopen")
    .wb_operation_pack_v3_rf_receipt_audit(receipt, request,
      stage_root = if (isTRUE(load_payloads)) path else NULL,
      code = "PYBENCH_REOPEN_VALIDATION_FAILED", phase = "reopen")
    .wb_operation_pack_v3_rfk_receipt_audit(receipt, request,
      stage_root = if (isTRUE(load_payloads)) path else NULL,
      code = "PYBENCH_REOPEN_VALIDATION_FAILED", phase = "reopen")
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
    if (identical(request$pack_abi_version, "4") && identical(grant$kind, "graph")) next
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
      matrix_grant <- grant$contained_matrix_model_sibling_write_grant %||%
        NULL
      if (!is.null(matrix_grant)) {
        .wb_operation_pack_v3_assert_matrix_model_linkage(
          matrix_grant$model_source_linkage,
          "PYBENCH_REOPEN_VALIDATION_FAILED", "reopen")
        .wb_operation_pack_v3_assert_self_identity(matrix_grant,
          "write_grant_identity", "PYBENCH_REOPEN_VALIDATION_FAILED",
          "reopen")
        tree <- observed$contained_matrix_model_sibling_tree
        .wb_operation_pack_v3_assert_self_identity(tree,
          "observation_identity", "PYBENCH_REOPEN_VALIDATION_FAILED",
          "reopen")
        siblings <- lapply(matrix_grant$required_sibling_terminals,
          function(x) observation_map[[x$name]]$descriptor)
        stopifnot(length(siblings) == length(
          matrix_grant$required_sibling_terminals),
          !any(vapply(siblings, is.null, logical(1))),
          identical(tree$write_grant_identity,
            .wb_operation_pack_v3_unscoped_identity(
              matrix_grant$write_grant_identity)),
          identical(tree$model_source_linkage_identity,
            .wb_operation_pack_v3_unscoped_identity(
              matrix_grant$model_source_linkage$linkage_identity)),
          identical(tree$paired_fitted_space_id,
            matrix_grant$model_source_linkage$paired_fitted_space_id),
          identical(tree$paired_fitted_space_id,
            matrix_grant$paired_space_output$allocated_id),
          identical(tree$paired_space_content_identity,
            siblings[[1L]]$content_identity),
          identical(tree$ordered_sibling_observed_descriptor_identities,
            lapply(siblings, function(x)
              .wb_operation_pack_v3_unscoped_identity(
                x$observed_descriptor_identity))),
          identical(tree$model_sibling_closure_identity,
            matrix_grant$model_sibling_closure_identity))
      }
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

  slice_grants <- request$typed_slice_grants %||% list()
  usages <- receipt$typed_slice_usage %||% list()
  if (length(slice_grants) != length(usages))
    return(fail("v3_typed_slice_bijection_mismatch"))
  for (i in seq_along(slice_grants)) {
    grant <- slice_grants[[i]]; usage <- usages[[i]]
    valid <- tryCatch({
      .wb_operation_pack_v3_assert_self_identity(grant$source_reference,
        "source_reference_identity", "PYBENCH_REOPEN_VALIDATION_FAILED",
        "reopen")
      .wb_operation_pack_v3_assert_self_identity(grant, "grant_identity",
        "PYBENCH_REOPEN_VALIDATION_FAILED", "reopen")
      .wb_operation_pack_v3_assert_self_identity(usage, "usage_identity",
        "PYBENCH_REOPEN_VALIDATION_FAILED", "reopen")
      for (call in usage$calls) {
        .wb_operation_pack_v3_assert_self_identity(call, "call_identity",
          "PYBENCH_REOPEN_VALIDATION_FAILED", "reopen")
        result <- call
        result$schema <- "scworkbench.operation_pack.typed_slice_result.v1"
        result$source_reference_identity <-
          .wb_operation_pack_v3_unscoped_identity(
            grant$source_reference$source_reference_identity)
        result$call_identity <- NULL
        .wb_operation_pack_v3_assert_self_identity(result,
          "slice_result_identity", "PYBENCH_REOPEN_VALIDATION_FAILED",
          "reopen")
      }
      identical(usage$request_identity,
          .wb_operation_pack_v3_unscoped_identity(
            request$request_identity)) &&
        identical(usage$capability_identity,
          .wb_operation_pack_v3_unscoped_identity(
            request$execution_capability$capability_identity)) &&
        identical(usage$operation_definition_identity,
          .wb_operation_pack_v3_unscoped_identity(
            request$operation_authentication$operation_definition_identity)) &&
        identical(usage$grant_identity,
          .wb_operation_pack_v3_unscoped_identity(grant$grant_identity)) &&
        identical(as.integer(usage$call_count),
          as.integer(length(usage$calls)))
    }, error = function(error) FALSE)
    if (!isTRUE(valid)) return(fail("v3_typed_slice_evidence_mismatch"))
    for (axis in c("cells_axis", "features_axis")) {
      descriptor <- grant[[axis]]
      payload <- file.path(path, descriptor$relative_path)
      if (!file.exists(payload)) return(fail(
        "v3_typed_slice_axis_manifest_missing", grant$name))
      observed_manifest <- .wb_operation_pack_v2_identity_scoped(
        "scworkbench.operation_pack.payload_manifest.v2",
        "registry read payload manifest", list(path = descriptor$relative_path,
          size = as.numeric(file.info(payload)$size),
          sha256 = .wb_operation_pack_v2_file_sha256(payload)))
      if (!identical(observed_manifest, descriptor$payload_manifest_identity))
        return(fail("v3_typed_slice_axis_manifest_mismatch", grant$name))
    }
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
        size = as.numeric(file.info(payload)$size),
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
  provenance_output_identity <- list(scheme = .wb_operation_pack_v3_scalar_db(
    output$content_identity_scheme), sha256 = .wb_operation_pack_v3_scalar_db(
      output$content_sha256))
  if (!nzchar(provenance_output_identity$scheme) ||
      !grepl("^[0-9a-f]{64}$", provenance_output_identity$sha256))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Artifact producer output has an invalid durable identity.",
      "resolution")
  # The provenance output identity authenticates the durable artifact record,
  # whereas the reader grant authenticates the rehydrated typed primitive.
  # The ancestry snapshot's content fields bind the latter so independently
  # authored runtimes compare like-for-like scientific content identities.
  stored_content <- input_record$content_identity
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
        size = as.numeric(file.info(path)$size),
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
  .wb_operation_pack_v3_sscf_retained_assert_current(bundle, request, path)
  .wb_operation_pack_v3_rf_retained_assert_current(bundle, request, path)
  .wb_operation_pack_v3_producer_lineage_retained_assert_current(bundle,
    request)
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

# Only fresh typed-reader blocks use this handoff. Ordinary R atomic values
# and lists already have copy-on-modify isolation; serializing their numerical
# arrays adds two block-sized copies without strengthening that isolation.
# Keep the existing fallback for mutable references or nonordinary objects.
.wb_operation_pack_v3_deliver_owned_block <- function(value) {
  plain <- function(x) {
    if (is.object(x) || isS4(x)) return(FALSE)
    type <- typeof(x)
    if (!type %in% c("NULL", "logical", "integer", "double", "complex",
        "character", "raw", "list")) return(FALSE)
    if (type == "list" && !all(vapply(x, plain, logical(1)))) return(FALSE)
    attrs <- attributes(x)
    is.null(attrs) || all(vapply(attrs, plain, logical(1)))
  }
  values <- value$values
  if (inherits(value, "wb_primitive") &&
      identical(class(value), "wb_primitive") &&
      value$kind %in% c("matrix", "space") && is.matrix(values) &&
      typeof(values) %in% c("double", "integer", "logical") &&
      plain(unclass(value))) return(value)
  .wb_operation_pack_v2_deep_copy(value)
}

.wb_operation_pack_v3_capability_adapter <- function(request, operation,
    inputs, stage_root, bundle = NULL, registry_read_values = list(),
    provenance_read_values = list(), producer_lineage_values = list()) {
  g3_inputs <- vapply(operation$supported_external_state_adoptions %||%
    list(), function(x) as.character(x$state_input)[1], character(1))
  base <- .wb_operation_pack_v2_capability_adapter(request, operation,
    inputs[setdiff(names(inputs), g3_inputs)], stage_root, bundle = bundle,
    registry_read_values = registry_read_values)
  base <- .wb_operation_pack_v3_fragment_writers(base, request, operation,
    stage_root)
  base <- .wb_operation_pack_v3_dfa_adapter(base, request, bundle,
    stage_root)
  base <- .wb_operation_pack_v3_model_adapters(base, request, operation,
    stage_root)
  base <- .wb_operation_pack_v3_g3_adapter(base, request, stage_root)
  base <- .wb_operation_pack_v3_sscf_adapter(base, request, bundle, inputs)
  base <- .wb_operation_pack_v3_rf_adapter(base, request, bundle, inputs)
  base <- .wb_operation_pack_v3_rfk_adapter(base, request, bundle)
  state <- base$state
  typed_input_names <- unique(vapply(request$typed_slice_grants %||% list(),
    `[[`, character(1), "input_name"))
  typed_input_names <- unique(c(typed_input_names, vapply(
    request$typed_space_grants %||% list(), `[[`, character(1),
    "input_name")))
  base$readers <- base$readers[setdiff(names(base$readers), typed_input_names)]
  state$typed_slice_calls <- stats::setNames(vector("list", length(
    request$typed_slice_grants %||% list())), vapply(
      request$typed_slice_grants %||% list(), `[[`, character(1), "name"))
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
  lineage_readers <- stats::setNames(lapply(names(producer_lineage_values),
    function(name) {
      force(name)
      function(...) {
        if (isTRUE(state$used) || length(list(...)) || any(vapply(
            state$reader_calls, function(x) identical(as.character(
              x$category %||% "")[1], "producer_lineage_read") &&
              identical(as.character(x$name %||% "")[1], name),
            logical(1))))
          .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
            "Producer-lineage readers are private, no-argument and single-use.",
            "execution")
        state$reader_calls[[length(state$reader_calls) + 1L]] <- list(
          category = "producer_lineage_read", name = name)
        .wb_operation_pack_v2_deep_copy(producer_lineage_values[[name]])
      }
    }), names(producer_lineage_values))
  base$readers <- c(base$readers, lineage_readers)
  slice_values <- attr(request, "operation_pack_v3_typed_slice_values") %||%
    list()
  state$matrix_reader_plans <- list()
  base$close_matrix_readers <- function() {
    for (plan in state$matrix_reader_plans) plan$close()
    invisible(TRUE)
  }
  typed_slice_readers <- stats::setNames(lapply(
    request$typed_slice_grants %||% list(), function(grant) {
      name <- as.character(grant$name)[1]
      force(name); force(grant)
      # Trusted in-process R: full byte authentication remains at dispatch and
      # publication. Between chunks inspect registry/file evidence, not all
      # matrix bytes. Python's supervised broker retains its existing policy.
      source_check <- if (!is.null(bundle) && identical(
          grant$source_reference$source_kind, "bundle_matrix"))
        .wb_operation_pack_matrix_light_guard(bundle,
          grant$source_reference$matrix_id) else NULL
      function(features = NULL, cells = NULL) {
      if (isTRUE(state$used)) .wb_operation_pack_v3_error(
        "PYBENCH_CAPABILITY_MISMATCH",
        "Capability has already been consumed.", "execution")
      source <- slice_values[[name]]
      allowed_features <- as.character(source$features)
      allowed_cells <- as.character(source$cells)
      if (is.null(features) || is.null(cells))
        .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
          "Typed-slice calls require explicit feature and cell vectors.",
          "execution")
      features <- if (is.null(features)) allowed_features else
        as.character(features)
      cells <- if (is.null(cells)) allowed_cells else as.character(cells)
      if (!length(features) || !length(cells))
        .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
          "Each typed-slice call requires two nonempty explicit axes.",
          "execution")
      valid_axis <- function(selected, allowed) !anyNA(selected) &&
        !any(!nzchar(selected)) && !anyDuplicated(selected) &&
        !length(setdiff(selected, allowed)) && identical(selected,
          allowed[match(selected, allowed)])
      if (!valid_axis(features, allowed_features) ||
          !valid_axis(cells, allowed_cells)) .wb_operation_pack_v3_error(
        "PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Typed-slice selection is duplicate, unknown, or out of order.",
        "execution")
      if (length(features) > as.integer(grant$max_rows) ||
          length(cells) > as.integer(grant$max_columns) ||
          as.double(length(features)) * as.double(length(cells)) >
            as.double(grant$max_elements)) .wb_operation_pack_v3_error(
        "PYBENCH_CAPABILITY_MISMATCH",
        "Typed-slice request exceeds its authenticated resource limits.",
        "execution")
      prior <- state$typed_slice_calls[[name]] %||% list()
      chunk_axis <- as.character(grant$chunk_axis)[1]
      chunk_values <- if (chunk_axis == "cells") cells else features
      nonchunk_values <- if (chunk_axis == "cells") features else cells
      allowed_chunk <- if (chunk_axis == "cells") allowed_cells else
        allowed_features
      allowed_nonchunk <- if (chunk_axis == "cells") allowed_features else
        allowed_cells
      if (identical(grant$call_discipline,
          "ordered_partition_exactly_once")) {
        consumed <- sum(vapply(prior, function(x) if (chunk_axis == "cells")
          x$result$cell_count else x$result$feature_count, integer(1)))
        expected <- if (length(chunk_values)) allowed_chunk[seq.int(
          consumed + 1L, consumed + length(chunk_values))] else character()
        if (!identical(nonchunk_values, allowed_nonchunk) ||
            !identical(chunk_values, expected) ||
            length(chunk_values) > as.integer(grant$requested_chunk_size))
          .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
            "Typed-slice calls violate ordered exactly-once partitioning.",
            "execution")
      } else {
        supported <- as.character(unlist(grant$supported_axes,
          use.names = FALSE))
        if (!(chunk_axis %in% supported) ||
            (!(if (chunk_axis == "cells") "features" else "cells") %in%
              supported && !identical(nonchunk_values, allowed_nonchunk)))
          .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
            "Independent typed-slice call exceeds its supported axes.",
            "execution")
      }
      input <- source$input
      values <- if (identical(grant$source_reference$source_kind,
          "bundle_matrix")) {
        if (is.null(bundle)) .wb_operation_pack_v3_error(
          "PYBENCH_INPUT_IDENTITY_MISMATCH",
          "Typed-slice bundle source has no core binding.", "execution")
        source_check()
        plan <- state$matrix_reader_plans[[name]]
        if (is.null(plan)) {
          plan <- .wb_matrix_stream_reader(bundle,
            grant$source_reference$matrix_id, grant$chunk_axis,
            features = allowed_features, cells = allowed_cells)
          state$matrix_reader_plans[[name]] <- plan
        }
        value <- as.matrix(plan$read(features, cells))
        source_check()
        value
      } else input$values[match(features, as.character(input$feature_id)),
        match(cells, as.character(input$cell_id)), drop = FALSE]
      values <- as.matrix(values)
      if (identical(as.character(grant$value_policy %||% "")[1],
          "nonnegative_integer_v1") &&
          (any(!is.finite(values)) || any(values < 0) ||
            any(abs(values - round(values)) > 1e-8)))
        .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
          "Typed matrix slice violates its nonnegative integer policy.",
          "execution")
      dimnames(values) <- list(features, cells)
      value <- structure(list(kind = "matrix",
        matrix_id = input$matrix_id %||% NULL, values = values,
        dimensions = as.integer(c(length(features), length(cells))),
        feature_id = features, cell_id = cells,
        storage_profile = "matrix_ordinary_v1", meta = input$meta %||% list()),
        class = "wb_primitive")
      result <- .wb_operation_pack_v3_slice_result(grant,
        length(prior) + 1L, value)
      state$typed_slice_calls[[name]][[length(prior) + 1L]] <- list(
        result = result, chunk_values = chunk_values)
      # Internal fault seam for checking source revalidation between reads.
      # Neither the stage bundle nor a state-authority handle reaches the pack.
      test_hook <- getOption(
        "scworkbench.operation_pack_v3_typed_slice_test_hook", NULL)
      if (is.function(test_hook))
        test_hook(name = name, read_index = length(prior) + 1L)
      state$reader_calls[[length(state$reader_calls) + 1L]] <- list(
        category = "typed_slice", name = name,
        slice_result_identity = result$slice_result_identity)
      .wb_operation_pack_v3_deliver_owned_block(value)
    }
  }), vapply(request$typed_slice_grants %||% list(), `[[`, character(1),
    "name"))
  base$readers <- c(base$readers, typed_slice_readers)
  base <- .wb_operation_pack_v3_add_typed_space_readers(base, request)
  .wb_operation_pack_v3_add_phase5_readers(base, request)
}

.wb_operation_pack_v3_typed_slice_usage <- function(adapter, request) {
  lapply(request$typed_slice_grants %||% list(), function(grant) {
    records <- adapter$state$typed_slice_calls[[grant$name]] %||% list()
    chunk_axis <- as.character(grant$chunk_axis)[1]
    selected <- unlist(lapply(records, `[[`, "chunk_values"),
      use.names = FALSE)
    allowed <- attr(grant, paste0("operation_pack_v3_", chunk_axis)) %||%
      character()
    zero_axis <- !length(attr(grant, "operation_pack_v3_cells") %||%
        character()) || !length(attr(grant,
          "operation_pack_v3_features") %||% character())
    if (zero_axis && length(records))
      .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
        "A zero-axis typed-slice grant must make no calls.", "receipt")
    if (!zero_axis && identical(grant$call_discipline,
        "ordered_partition_exactly_once") && !identical(selected, allowed))
      .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
        "Typed-slice execution did not cover its ordered axis exactly once.",
        "receipt")
    calls <- lapply(records, function(record) {
      call <- record$result
      call$schema <- "scworkbench.operation_pack.observed_typed_slice_call.v1"
      call$source_reference_identity <- NULL
      call$call_identity <- .wb_operation_pack_v2_identity_scoped(
        "scworkbench.operation_pack.observed_typed_slice_call.v1",
        "call excluding call_identity", call)
      call
    })
    usage <- list(schema =
        "scworkbench.operation_pack.typed_slice_usage.v1",
      request_identity = .wb_operation_pack_v3_unscoped_identity(
        request$request_identity),
      capability_identity = .wb_operation_pack_v3_unscoped_identity(
        request$execution_capability$capability_identity),
      operation_definition_identity = .wb_operation_pack_v3_unscoped_identity(
        request$operation_authentication$operation_definition_identity),
      grant_identity = .wb_operation_pack_v3_unscoped_identity(
        grant$grant_identity),
      requested_chunk_size = as.integer(grant$requested_chunk_size),
      calls = calls, call_count = as.integer(length(calls)),
      concatenated_chunk_axis_order_identity =
        .wb_operation_pack_v2_identity_plain(
          if (chunk_axis == "cells") "scworkbench.cell_order.v1" else
            "scworkbench.feature_order.v1", unname(as.list(selected))),
      unique_chunk_axis_count = as.integer(length(unique(selected))),
      duplicate_chunk_axis_count = as.integer(length(selected) -
        length(unique(selected))),
      coverage_status = if (zero_axis) "empty" else if (identical(
        grant$call_discipline, "ordered_partition_exactly_once")) "exact" else
        "independent")
    usage$usage_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.typed_slice_usage.v1",
      "usage excluding usage_identity", usage)
    usage
  })
}

.wb_operation_pack_v3_runner <- function(op_name, abi = "3") {
  force(op_name); force(abi)
  function(bundle, resolved, effective_cells, inputs, ...) {
    binding <- bundle$pybench_session_binding %||% list()
    source_refs <- inputs[names(resolved)]
    operation <- .wb_operation_pack_registry$operations[[op_name]]$definition[[
      if (abi == "4") "v4_definition" else "v3_definition"]]
    adoption_declaration <- .wb_operation_pack_v3_g3_declaration(operation)
    adoption_candidate <- if (is.null(adoption_declaration)) NULL else
      resolved[[as.character(adoption_declaration$state_input)[1]]]
    if (!is.null(adoption_candidate)) on.exit(
      .wb_operation_pack_v3_external_candidate_discard(adoption_candidate),
      add = TRUE)
    # A contained model carries its fitted input-space identity. A manifest may
    # declare that linked space as an optional convenience input; derive only
    # that typed primitive when the caller omitted it.
    for (declaration in operation$contained_model_reads %||% list()) {
      source_name <- as.character(declaration$source_space_input)[1]
      model_name <- as.character(declaration$input)[1]
      if (is.null(resolved[[source_name]]) && !is.null(resolved[[model_name]])) {
        source_id <- as.character(resolved[[model_name]]$in_space_id %||%
          "")[1]
        if (!nzchar(source_id)) .wb_operation_pack_v3_error(
          "PYBENCH_INPUT_IDENTITY_MISMATCH",
          "Contained model does not identify its fitted input space.",
          "resolution")
        resolved[[source_name]] <- wb_prim_space(source_id)
        inputs[[source_name]] <- source_id
      }
    }
    typed_inputs <- unique(vapply(operation$typed_slice_reads %||% list(),
      `[[`, character(1), "input"))
    typed_space_inputs <- unique(vapply(operation$typed_space_reads %||%
      list(), `[[`, character(1), "input"))
    record <- .wb_operation_pack_registry$operations[[op_name]]
    registration <- .wb_operation_pack_registry$packs[[record$namespace]]$registration
    native_r <- identical(as.character(registration$identity$backend)[1], "R")
    space_plans <- list()
    graph_present <- identical(abi,"4") && (any(vapply(operation$inputs,
      function(x) identical(x$kind,"graph"),logical(1))) || any(vapply(operation$outputs,
      function(x) identical(x$kind,"graph"),logical(1))))
    graph_policy <- if (graph_present) .wb_operation_pack_v4_lowest_graph_budgets(lapply(
      Filter(function(x) identical(x$kind,"graph"),operation$outputs),`[[`,"resource_budgets")) else NULL
    space_budget <- .wb_operation_pack_v3_broker_projection_budget(bundle,graph_policy)
    on.exit(for (plan in space_plans) plan$close(), add = TRUE)
    bound <- stats::setNames(lapply(names(resolved), function(name) {
      value <- resolved[[name]]
      if (abi == "4" && identical(value$kind, "graph")) return(value)
      if (name %in% typed_space_inputs && identical(value$kind, "space")) {
        out <- .wb_operation_pack_v2_deep_copy(value)
        # Fresh core-created map only: ordinary incoming primitive attributes
        # cannot supply a plan or descriptor digest. Python transport stays
        # on its established materialized path.
        if (native_r && identical(.Platform$OS.type, "unix") && is.null(value$values) &&
            .wb_space_payload_exists(bundle,value$space_id)) {
          plan <- .wb_space_payload_reader(bundle, value$space_id, .budget=space_budget)
          if (!length(plan$cells) || anyDuplicated(plan$cells))
            .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
              "Typed-space input has no unique durable cell axis.", "resolution")
          out$cell_id <- plan$cells
          out$dimensions <- plan$dimensions
          out$storage_profile <- "space_dense_v1"
          space_plans[[name]] <<- plan
          return(out)
        }
        coordinates <- value$values
        if (is.null(coordinates)) coordinates <- wb_space(bundle,
          as.character(value$space_id)[1])
        coordinates <- .wb_operation_pack_v3_space_matrix(coordinates)
        if (!nrow(coordinates) || is.null(rownames(coordinates)) ||
            anyDuplicated(rownames(coordinates)))
          .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
            "Typed-space input has no unique durable cell axis.",
            "resolution")
        out$values <- coordinates
        out$cell_id <- rownames(coordinates)
        out$dimensions <- as.integer(dim(coordinates))
        out$storage_profile <- "space_dense_v1"
        return(out)
      }
      if (!name %in% typed_inputs || !identical(value$kind, "matrix"))
        return(.wb_operation_pack_v2_bind_inputs(
            bundle, stats::setNames(list(value), name),
            effective_cells)[[name]])
      out <- .wb_operation_pack_v2_deep_copy(value)
      if (!is.null(value$values)) {
        cells <- as.character(value$cell_id %||% colnames(value$values))
        input_cells <- as.character(value$cell_id)
        input_features <- as.character(value$feature_id)
        indices <- match(cells, input_cells)
        if (anyNA(indices)) .wb_operation_pack_v3_error(
          "PYBENCH_INPUT_IDENTITY_MISMATCH",
          "In-memory typed-slice input does not cover effective cells.",
          "resolution")
        out$values <- value$values[, indices, drop = FALSE]
        out$cell_id <- cells
        out$feature_id <- input_features
        out$dimensions <- as.integer(c(length(input_features),
          length(cells)))
        out$storage_profile <- "matrix_ordinary_v1"
        return(out)
      }
      available <- wb_cells_with_matrix(bundle, value$matrix_id)
      out$cell_id <- as.character(available)
      out$feature_id <- wb_feature_ids(bundle, value$matrix_id)
      out$dimensions <- as.integer(c(length(out$feature_id),
        length(out$cell_id)))
      out$storage_profile <- "matrix_backed_chunked_v1"
      out
    }), names(resolved))
    attr(bound, "operation_pack_v3_source_refs") <- source_refs
    attr(bound, "operation_pack_v4_matrix_source_selections") <-
      attr(resolved, "operation_pack_v4_matrix_source_selections", exact = TRUE)
    all_inputs <- inputs
    params <- inputs[setdiff(names(inputs), c(names(resolved),
      names(.wb_op_engine_input_specs())))]
    mutation_context <- .wb_current_mutation_context(bundle$con, bundle$dir)
    .wb_operation_pack_assert(!is.null(mutation_context) &&
        identical(as.character(mutation_context$route)[1],
          "session_execution") && nzchar(as.character(
            mutation_context$run_id %||% "")[1]),
      "PYBENCH_CAPABILITY_MISMATCH",
      "ABI v3 execution requires a preallocated session run.",
      phase = "execution", class = "wb_operation_pack_v3_error")
    attr(bound, "operation_pack_v3_space_plans") <- space_plans
    if (length(space_plans) && !is.null(space_budget$policy)) {
      restore_space_policy <- .wb_operation_pack_v3_broker_graph_reservation(bundle,
        space_budget,space_budget$policy)
      on.exit(restore_space_policy(),add=TRUE)
    }
    params <- .wb_operation_pack_v2_bind_parameters(bundle, operation,
      params, bound, effective_cells)
    params <- .wb_operation_pack_v3_bind_cell_selectors(bundle, operation,
      params)
    result <- .wb_operation_pack_v2_execute(bundle, op_name, bound,
      params = params, session_id = binding$session_id %||% NULL,
      run_id = as.character(mutation_context$run_id)[1],
      checkpoint_generation = binding$checkpoint_generation %||% "ephemeral",
      effective_cells = effective_cells)
    returned_params <- .wb_operation_pack_v2_retained_parameters(operation,
      all_inputs, params, bound, result$outputs)
    if (length(result$receipt$
        supported_external_state_adoption_observations %||% list()))
      returned_params$supported_external_state_adoption <- result$receipt$
        supported_external_state_adoption_observations[[1L]]
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
