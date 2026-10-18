# ABI-v3 materialization publication and parameter-axis capabilities.

.wb_matrix_write_continuous <- function(mat, out_dir) {
  .wb_require_pkg("BPCells", "continuous matrix fragment publication")
  # Matrix() preserves structural classes such as dtCMatrix, dsCMatrix, and
  # ddiMatrix when their values happen to be triangular, symmetric, or
  # diagonal.  Those are valid fragment values, but BPCells accepts a general
  # compressed sparse matrix at this boundary.  Normalize the representation,
  # not the values or axes, so chunk shape cannot select a storage class.
  sparse <- Matrix::Matrix(mat, sparse = TRUE)
  if (!inherits(sparse, "dgCMatrix"))
    sparse <- methods::as(sparse, "generalMatrix")
  .wb_assert(inherits(sparse, "dgCMatrix"),
    "Continuous matrix fragments must normalize to dgCMatrix storage.")
  typed <- BPCells::convert_matrix_type(sparse, "double")
  BPCells::write_matrix_dir(typed, out_dir, compress = FALSE)
  .wb_bp_open_matrix_dir(out_dir)
}

.wb_operation_pack_v3_publication_map <- function(operation) {
  policies <- operation$publication_policies %||% list()
  stats::setNames(policies, vapply(policies, function(x)
    as.character(x$output)[1], character(1)))
}

.wb_operation_pack_v3_parameter_axis_map <- function(operation) {
  axes <- operation$parameter_axes %||% list()
  stats::setNames(axes, vapply(axes, function(x)
    as.character(x$name)[1], character(1)))
}

.wb_operation_pack_v3_registry_absence_identity <- function(kind, id,
                                                              state) {
  .wb_operation_pack_v2_identity_plain(
    "scworkbench.operation_pack.registry_absence.v1",
    list(kind = kind, id = id, source_state_identity = state))
}

.wb_operation_pack_v3_materialization_preimage <- function(bundle, kind, id,
                                                              state) {
  table <- if (kind == "matrix") "matrices" else "spaces"
  id_field <- if (kind == "matrix") "matrix_id" else "space_id"
  row <- DBI::dbGetQuery(bundle$con, paste0("SELECT * FROM ", table,
    " WHERE ", id_field, "=?;"), params = list(id))
  if (!nrow(row)) return(list(state = "absent",
    registry_absence_identity =
      .wb_operation_pack_v3_registry_absence_identity(kind, id, state),
    transition_source_state_identity = state))
  primitive <- if (kind == "matrix") wb_prim_matrix(id) else wb_prim_space(id)
  identity_bundle <- if (kind == "matrix")
    .wb_operation_pack_v3_matrix_identity_bundle(bundle, id) else bundle
  content <- .wb_prov_payload_identity(identity_bundle, primitive)
  payload <- if (kind == "matrix") {
    fragments <- DBI::dbGetQuery(bundle$con,
      "SELECT fragment_id,path,n_features,n_cells,feature_ids_json,cell_ids_json,source FROM matrix_fragments WHERE matrix_id=? ORDER BY created_at,rowid;",
      params = list(id))
    lapply(seq_len(nrow(fragments)), function(i) as.list(fragments[i, ,
      drop = FALSE]))
  } else {
    as.list(DBI::dbGetQuery(bundle$con,
      "SELECT * FROM space_payloads WHERE space_id=?;", params = list(id)))
  }
  lifecycle <- if (.wb_table_exists(bundle$con, "entity_lifecycle"))
    DBI::dbGetQuery(bundle$con,
      "SELECT * FROM entity_lifecycle WHERE entity_kind=? AND entity_id=? ORDER BY rowid;",
      params = list(kind, id)) else data.frame()
  provenance <- if (.wb_table_exists(bundle$con,
      "prov_run_entity_bindings"))
    DBI::dbGetQuery(bundle$con,
      "SELECT * FROM prov_run_entity_bindings WHERE entity_kind=? AND entity_id=? ORDER BY rowid;",
      params = list(kind, id)) else data.frame()
  list(state = "present",
    transition_source_state_identity = state,
    registry_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.materialization_registry.v1", as.list(row)),
    content_identity = list(scheme = content$content_identity_scheme,
      sha256 = content$content_sha256),
    payload_manifest_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.materialization_payload_manifest.v1",
      payload),
    provenance_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.materialization_provenance.v1",
      as.list(provenance)),
    lifecycle_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.materialization_lifecycle.v1",
      as.list(lifecycle)))
}

.wb_operation_pack_v3_publication_grant <- function(bundle, policy, operation,
    params, source_state_identity, inputs = list(), input_records = list(),
    base_outputs = list()) {
  if (identical(as.character(policy$policy)[1],
      "authenticated_space_2d_publication_v1"))
    return(.wb_operation_pack_v3_space2d_publication_grant(bundle, policy,
      operation, params, source_state_identity, inputs, input_records,
      base_outputs))
  output_name <- as.character(policy$output)[1]
  outputs <- stats::setNames(operation$outputs,
    vapply(operation$outputs, `[[`, character(1), "name"))
  output <- outputs[[output_name]]
  target_kind <- as.character(policy$target_kind)[1]
  target_id <- as.character(params[[as.character(
    policy$target_id_parameter)[1]]])[1]
  overwrite <- isTRUE(params[[as.character(policy$overwrite_parameter)[1]]])
  preimage <- .wb_operation_pack_v3_materialization_preimage(bundle,
    target_kind, target_id, source_state_identity)
  if (identical(preimage$state, "present") && !overwrite)
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      paste0("Publication target already exists: ", target_id,
        " (set overwrite=TRUE)."), "resolution")
  group <- as.character(output$promotion_group)[1]
  closure <- sort(vapply(Filter(function(x) identical(as.character(
    x$promotion_group)[1], group), operation$outputs), `[[`, character(1),
    "name"), method = "radix")
  grant <- list(
    schema = "scworkbench.operation_pack.materialization_publication_grant.v1",
    output = output_name, promotion_group = group,
    closure_outputs = unname(as.list(closure)), target_kind = target_kind,
    target_id = target_id,
    mode = if (identical(preimage$state, "present")) "replace" else "add",
    conflict_policy = if (identical(preimage$state, "present"))
      "replace_exact_preimage_v1" else "require_absent_v1",
    preimage = preimage)
  grant$publication_grant_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.materialization_publication_grant.v1",
    "grant excluding publication_grant_identity", grant)
  grant
}

.wb_operation_pack_v3_space2d_publication_grant <- function(bundle, policy,
    operation, params, source_state_identity, inputs, input_records,
    base_outputs) {
  output_name <- as.character(policy$output)[1]
  outputs <- stats::setNames(operation$outputs, vapply(operation$outputs,
    `[[`, character(1), "name"))
  output <- outputs[[output_name]]
  target_id <- as.character(params[[as.character(
    policy$target_id_parameter)[1]]])[1]
  preimage <- .wb_operation_pack_v3_materialization_preimage(bundle,
    "space_2d", target_id, source_state_identity)
  selected <- as.character(inputs[[as.character(policy$cell_axis_input)[1]]]$
    cell_id %||% rownames(inputs[[as.character(policy$cell_axis_input)[1]]]$
      values))
  .wb_operation_pack_assert(length(selected) && !anyNA(selected) &&
      all(nzchar(selected)) && !anyDuplicated(selected),
    "PYBENCH_CAPABILITY_MISMATCH",
    "Authenticated space_2d publication has an invalid selected-cell axis.",
    phase = "resolution", class = "wb_operation_pack_v3_error")
  old_cells <- if (identical(preimage$state, "present")) {
    value <- wb_space(bundle, target_id)
    if (is.data.frame(value)) value <- .wb_as_coord_matrix(value)
    as.character(rownames(value))
  } else character()
  if (identical(preimage$state, "present")) {
    preimage$cell_order_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", unname(as.list(old_cells)))
    preimage$coordinate_dimensions <- 2L
  }
  mode_policy <- as.character(policy$mode$policy)[1]
  overwrite <- if (identical(mode_policy, "add_only_v1")) FALSE else
    isTRUE(params[[as.character(policy$mode$overwrite_parameter)[1]]])
  if (identical(mode_policy, "add_only_v1") &&
      identical(preimage$state, "present"))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      paste0("Authenticated add-only space_2d target already exists: ",
        target_id), "resolution")
  overlap <- intersect(old_cells, selected)
  if (length(overlap) && !overwrite)
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Selected-cell merge overlaps the target while overwrite is false.",
      "resolution")
  mode <- if (!length(old_cells)) "add" else if (setequal(old_cells,
    selected) && length(old_cells) == length(selected)) "full_replace" else
    "selected_cell_merge"
  recipient <- wb_cells(bundle, cell_set = "all")
  union_cells <- union(old_cells, selected)
  final_cells <- recipient[recipient %in% union_cells]
  if (!setequal(final_cells, union_cells))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Selected-cell publication contains cells outside the recipient axis.",
      "resolution")
  binding <- policy$model_binding
  binding_name <- as.character(binding$name)[1]
  if (identical(as.character(binding$source)[1], "input")) {
    model <- inputs[[binding_name]]
    model_record <- input_records[[binding_name]]
    source_model <- list(source = "input", name = binding_name,
      engine = as.character(model$engine)[1],
      model_type = as.character(model$model_type %||% model$engine)[1],
      model_linkage_identity = model_record$model_linkage_identity,
      contained_payload_identity = model_record$contained_payload_identity)
  } else {
    model_output <- outputs[[binding_name]]
    model_policy <- model_output$contained_model_policy
    source <- inputs[[as.character(model_policy$source_space_input)[1]]]
    dims <- .wb_operation_pack_v3_selected_dimensions(source, params,
      model_policy$dimensions_parameter)
    allocated <- base_outputs[[match(binding_name, vapply(base_outputs,
      `[[`, character(1), "name"))]]$allocated_id
    source_model <- list(source = "sibling_output", name = binding_name,
      allocated_id = as.character(allocated)[1],
      engine = as.character(model_policy$engine)[1],
      model_type = as.character(model_policy$model_type)[1],
      source_space_binding_identity = .wb_operation_pack_v2_identity_plain(
        "scworkbench.operation_pack.model_source_space.v1", list(
          input_name = as.character(model_policy$source_space_input)[1],
          input_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
            input_records[[as.character(model_policy$source_space_input)[1]]]$
              descriptor_identity),
          selected_dimension_count = as.integer(dims$count),
          selected_dimension_order_identity = dims$identity)))
  }
  group <- as.character(output$promotion_group)[1]
  closure <- sort(vapply(Filter(function(x) identical(as.character(
    x$promotion_group)[1], group), operation$outputs), `[[`, character(1),
    "name"), method = "radix")
  grant <- list(schema =
      "scworkbench.operation_pack.space_2d_publication_grant.v1",
    output = output_name, promotion_group = group,
    closure_outputs = unname(as.list(closure)), target_kind = "space_2d",
    target_id = target_id, mode = mode,
    conflict_policy = switch(mode, add = "require_absent_v1",
      selected_cell_merge = "merge_exact_preimage_v1",
      full_replace = "replace_exact_preimage_v1"),
    overwrite_existing_cells = overwrite,
    selected_cells = list(count = as.integer(length(selected)),
      order_identity = .wb_operation_pack_v2_identity_plain(
        "scworkbench.cell_order.v1", unname(as.list(selected))),
      membership_identity = .wb_operation_pack_v2_identity_plain(
        "scworkbench.cell_membership.v1",
        unname(as.list(sort(selected, method = "radix"))))),
    recipient_cell_axis_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", unname(as.list(recipient))),
    expected_final_cell_order_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", unname(as.list(final_cells))),
    source_model_binding = source_model, preimage = preimage)
  grant$publication_grant_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.space_2d_publication_grant.v1",
    "grant excluding publication_grant_identity", grant)
  grant
}

.wb_operation_pack_v3_source_fragment_schedule <- function(bundle, input,
    input_record, typed_grant) {
  features <- attr(typed_grant, "operation_pack_v3_features")
  cells <- attr(typed_grant, "operation_pack_v3_cells")
  matrix_id <- as.character(input$matrix_id %||% "")[1]
  fragments <- if (nzchar(matrix_id)) DBI::dbGetQuery(bundle$con,
    "SELECT rowid AS registry_rowid,* FROM matrix_fragments WHERE matrix_id=? ORDER BY created_at,rowid;",
    params = list(matrix_id)) else data.frame()
  if (!nrow(fragments)) {
    fragments <- data.frame(fragment_id = paste0("projection:",
      typed_grant$name), path = NA_character_, source = "private_projection",
      feature_ids_json = jsonlite::toJSON(as.list(features), auto_unbox = TRUE),
      cell_ids_json = jsonlite::toJSON(as.list(cells), auto_unbox = TRUE),
      n_features = length(features), n_cells = length(cells),
      stringsAsFactors = FALSE)
  }
  source_reader <- if (nzchar(matrix_id))
    .wb_matrix_stream_reader(bundle, matrix_id, "cells") else NULL
  if (!is.null(source_reader)) on.exit(source_reader$close(), add = TRUE)
  records <- list(); cursor <- 1L
  for (i in seq_len(nrow(fragments))) {
    fragment_cells <- as.character(jsonlite::fromJSON(
      fragments$cell_ids_json[[i]]))
    keep <- fragment_cells %in% cells
    fragment_cells <- fragment_cells[keep]
    if (!length(fragment_cells)) next
    expected <- cells[seq.int(cursor, cursor + length(fragment_cells) - 1L)]
    if (!identical(fragment_cells, expected))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Source matrix fragments do not form the authenticated typed-slice cell axis.",
        "resolution")
    payload <- .wb_operation_pack_matrix_stream_identity(features,
      fragment_cells, function(columns) if (!is.null(source_reader))
        source_reader$read(features, fragment_cells[columns]) else
          input$values[match(features, as.character(input$feature_id)),
            match(fragment_cells[columns], as.character(input$cell_id)), drop = FALSE],
      min(as.integer(typed_grant$requested_chunk_size), 128L))
    tuple <- list(fragment_id = as.character(fragments$fragment_id[[i]]),
      path = as.character(fragments$path[[i]]),
      source = as.character(fragments$source[[i]]),
      n_features = as.integer(fragments$n_features[[i]]),
      n_cells = as.integer(fragments$n_cells[[i]]),
      payload_content_identity = payload)
    source_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.source_matrix_fragment.v1", tuple)
    records[[length(records) + 1L]] <- list(ordinal = as.integer(length(records) + 1L),
      source_fragment_identity = source_identity,
      cell_start = as.integer(cursor), cell_count = as.integer(length(fragment_cells)),
      cell_order_identity = .wb_operation_pack_v2_identity_plain(
        "scworkbench.cell_order.v1", unname(as.list(fragment_cells))))
    cursor <- cursor + length(fragment_cells)
  }
  if (cursor != length(cells) + 1L)
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Source fragment schedule does not cover the typed-slice cell axis.",
      "resolution")
  schedule <- list(schema =
      "scworkbench.operation_pack.source_fragment_schedule.v1",
    input_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
      input_record$descriptor_identity),
    matrix_content_identity = input_record$content_identity,
    source_fragment_manifest_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.source_fragment_manifest.v1", records),
    fragments = records)
  schedule$schedule_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.source_fragment_schedule.v1",
    "schedule excluding schedule_identity", schedule)
  schedule
}

.wb_operation_pack_v3_matrix_fragment_grant <- function(bundle, output,
    inputs, input_records, typed_grants) {
  policy <- output$fragment_policy
  input_name <- as.character(policy$source_input)[1]
  slice_name <- as.character(policy$source_typed_slice_read)[1]
  typed <- typed_grants[[slice_name]]
  schedule <- .wb_operation_pack_v3_source_fragment_schedule(bundle,
    inputs[[input_name]], input_records[[input_name]], typed)
  grant <- list(schema =
      "scworkbench.operation_pack.matrix_fragment_grant.v1",
    source_input = input_name,
    typed_slice_grant_identity = .wb_operation_pack_v3_unscoped_identity(
      typed$grant_identity),
    expected_dimensions = list(as.integer(length(attr(typed,
      "operation_pack_v3_features"))), as.integer(length(attr(typed,
      "operation_pack_v3_cells")))),
    feature_order_identity = typed$features_axis$order_identity,
    cell_order_identity = typed$cells_axis$order_identity,
    source_fragment_schedule = schedule,
    fragment_policy = policy)
  grant$grant_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.matrix_fragment_grant.v1",
    "grant excluding grant_identity", grant)
  attr(grant, "operation_pack_v3_features") <- attr(typed,
    "operation_pack_v3_features")
  attr(grant, "operation_pack_v3_cells") <- attr(typed,
    "operation_pack_v3_cells")
  grant
}

.wb_operation_pack_v3_parameter_axis_grant <- function(axis, params,
    typed_grants) {
  maximum <- axis$maximum
  typed <- typed_grants[[as.character(maximum$typed_slice_read)[1]]]
  cells <- attr(typed, "operation_pack_v3_cells")
  features <- attr(typed, "operation_pack_v3_features")
  lower <- as.integer(axis$minimum)[1]
  upper <- min(length(cells) + as.integer(maximum$cell_offset)[1],
    length(features) + as.integer(maximum$feature_offset)[1])
  value <- as.integer(params[[as.character(axis$parameter)[1]]])[1]
  if (is.na(value) || value < lower || value > upper)
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      paste0("Parameter axis '", axis$name, "' value ", value,
        " is outside authenticated bounds [", lower, ", ", upper, "]."),
      "resolution")
  prefix <- as.character(axis$labels$prefix)[1]
  labels <- paste0(prefix, seq_len(value))
  grant <- list(schema = "scworkbench.operation_pack.parameter_axis_grant.v1",
    name = as.character(axis$name)[1], parameter = as.character(axis$parameter)[1],
    value = value, minimum = lower, maximum = as.integer(upper),
    labels = unname(as.list(labels)), source = list(
      typed_slice_grant_identity = .wb_operation_pack_v3_unscoped_identity(
        typed$grant_identity), cell_axis_count = as.integer(length(cells)),
      feature_axis_count = as.integer(length(features))),
    axis_order_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.dimension_order.v1", unname(as.list(labels))))
  grant$grant_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.parameter_axis_grant.v1",
    "grant excluding grant_identity", grant)
  attr(grant, "operation_pack_v3_cells") <- cells
  attr(grant, "operation_pack_v3_features") <- features
  attr(grant, "operation_pack_v3_labels") <- labels
  grant
}

.wb_operation_pack_v3_parameter_axis_observe <- function(value, policy,
    axis_grant) {
  kind <- as.character(value$kind)[1]
  labels <- attr(axis_grant, "operation_pack_v3_labels")
  cells <- attr(axis_grant, "operation_pack_v3_cells")
  features <- attr(axis_grant, "operation_pack_v3_features")
  fail <- function(message) .wb_operation_pack_v3_error(
    "PYBENCH_OUTPUT_INVALID", message, "audit")
  policy_name <- as.character(policy$policy)[1]
  if (identical(policy_name, "cell_by_parameter_axis_v1")) {
    x <- value$values
    if (!is.matrix(x) || !identical(rownames(x), cells) ||
        !identical(colnames(x), labels) || any(!is.finite(x)))
      fail("Space output does not match the authenticated cell-by-parameter axis.")
    observed <- list(dimensions = unname(as.list(as.integer(dim(x)))),
      cell_order_identity = .wb_operation_pack_v2_identity_plain(
        "scworkbench.cell_order.v1", unname(as.list(rownames(x)))),
      dimension_order_identity = .wb_operation_pack_v2_identity_plain(
        "scworkbench.dimension_order.v1", unname(as.list(colnames(x)))))
  } else if (identical(policy_name,
      "feature_parameter_axis_cartesian_v1")) {
    table <- value$table
    expected_feature <- rep(features, times = length(labels))
    expected_label <- rep(labels, each = length(features))
    expected_index <- rep(seq_along(labels), each = length(features))
    if (!is.data.frame(table) ||
        !identical(as.character(table[[policy$feature_field]]), expected_feature) ||
        !identical(as.character(table[[policy$axis_label_field]]), expected_label) ||
        !identical(as.integer(table[[policy$axis_index_field]]),
          as.integer(expected_index)))
      fail("Feature/parameter output is incomplete, duplicated, or out of order.")
    observed <- list(dimensions = unname(as.list(as.integer(dim(table)))),
      row_order_identity = .wb_operation_pack_v2_identity_plain(
        "scworkbench.row_order.v1", unname(Map(function(label, feature)
          list(label = label, feature_id = feature), expected_label,
          expected_feature))))
  } else if (identical(policy_name, "one_per_parameter_axis_v1")) {
    table <- value$table
    if (!is.data.frame(table) || nrow(table) != length(labels) ||
        !identical(as.character(table[[policy$axis_label_field]]), labels) ||
        !identical(as.integer(table[[policy$axis_index_field]]),
          as.integer(seq_along(labels))))
      fail("Parameter-axis table is incomplete, duplicated, or out of order.")
    observed <- list(dimensions = unname(as.list(as.integer(dim(table)))),
      row_order_identity = .wb_operation_pack_v2_identity_plain(
        "scworkbench.row_order.v1", unname(as.list(labels))))
  } else {
    table <- value$table
    if (!is.data.frame(table) || nrow(table) != 1L ||
        !identical(as.integer(table[[policy$count_field]][[1]]),
          as.integer(axis_grant$value)))
      fail("Singleton parameter echo differs from the authenticated axis.")
    observed <- list(dimensions = unname(as.list(as.integer(dim(table)))),
      echoed_value = as.integer(table[[policy$count_field]][[1]]))
  }
  observed$parameter_axis_grant_identity <-
    .wb_operation_pack_v3_unscoped_identity(axis_grant$grant_identity)
  observed
}

.wb_operation_pack_v3_fragment_manifest <- function(grant, parts) {
  features <- attr(grant, "operation_pack_v3_features")
  cells <- attr(grant, "operation_pack_v3_cells")
  manifest <- list(schema =
      "scworkbench.operation_pack.matrix_fragment_manifest.v1",
    source_fragment_schedule_identity =
      grant$source_fragment_schedule$schedule_identity,
    dimensions = list(as.integer(length(features)), as.integer(length(cells))),
    feature_order_identity = grant$feature_order_identity,
    cell_order_identity = grant$cell_order_identity,
    fragment_count = as.integer(length(parts)), fragments = unname(parts))
  manifest$fragment_manifest_identity <-
    .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.matrix_fragment_manifest.v1",
      "manifest excluding fragment_manifest_identity", manifest)
  manifest
}

.wb_operation_pack_v3_fragment_writers <- function(base, request, operation,
    stage_root) {
  grants <- stats::setNames(request$outputs, vapply(request$outputs, `[[`,
    character(1), "name"))
  declarations <- stats::setNames(operation$outputs,
    vapply(operation$outputs, `[[`, character(1), "name"))
  fragment_outputs <- names(Filter(function(x)
    !is.null(x$descriptor$matrix_fragment_grant), grants))
  if (!length(fragment_outputs)) return(base)
  handles <- new.env(parent = emptyenv())
  open <- function(output) {
    output <- as.character(output)[1]
    grant_record <- grants[[output]]
    fragment_grant <- grant_record$descriptor$matrix_fragment_grant
    if (is.null(fragment_grant) || !output %in% fragment_outputs)
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        paste0("No staged matrix-fragment grant for output '", output,
          "'."), "execution")
    if (!is.null(handles[[output]]) || !is.null(base$state$writes[[output]]))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        paste0("Matrix-fragment writer already opened for '", output,
          "'."), "execution")
    state <- new.env(parent = emptyenv())
    state$parts <- list(); state$cursor <- 1L; state$finished <- FALSE
    state$source_part_counts <- integer(length(
      fragment_grant$source_fragment_schedule$fragments))
    features <- attr(fragment_grant, "operation_pack_v3_features")
    cells <- attr(fragment_grant, "operation_pack_v3_cells")
    schedule <- fragment_grant$source_fragment_schedule$fragments
    write_fragment <- function(source_fragment_ordinal, values, feature_ids,
        cell_ids) {
      if (isTRUE(state$finished)) .wb_operation_pack_v3_error(
        "PYBENCH_CAPABILITY_MISMATCH", "Fragment writer is closed.",
        "execution")
      ordinal <- as.integer(source_fragment_ordinal)[1]
      feature_ids <- as.character(feature_ids)
      cell_ids <- as.character(cell_ids)
      matrix <- as.matrix(values); storage.mode(matrix) <- "double"
      if (is.na(ordinal) || ordinal < 1L || ordinal > length(schedule) ||
          !identical(feature_ids, features) || !length(cell_ids) ||
          !identical(as.integer(dim(matrix)), as.integer(c(length(features),
            length(cell_ids)))) || any(!is.finite(matrix)) ||
          !identical(cell_ids, cells[seq.int(state$cursor,
            state$cursor + length(cell_ids) - 1L)]))
        .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
          "Matrix fragment has invalid parent, axes, dimensions, order, or values.",
          "audit")
      parent <- schedule[[ordinal]]
      parent_start <- as.integer(parent$cell_start)
      parent_end <- parent_start + as.integer(parent$cell_count) - 1L
      part_end <- state$cursor + length(cell_ids) - 1L
      if (state$cursor < parent_start || part_end > parent_end)
        .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
          "Matrix fragment crosses an authenticated source-fragment boundary.",
          "audit")
      hook <- getOption("scworkbench.operation_pack_v3_fragment_test_hook",
        NULL)
      part_ordinal <- length(state$parts) + 1L
      if (is.function(hook)) hook(event = "before_fragment_write",
        output = output, fragment_ordinal = part_ordinal)
      relative <- file.path("outputs", output, "fragments",
        sprintf("part_%06d", part_ordinal))
      path <- file.path(stage_root, relative)
      dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
      dimnames(matrix) <- list(features, cell_ids)
      persisted <- tryCatch(.wb_matrix_write_continuous(matrix, path),
        error = function(error) {
          if (dir.exists(path)) unlink(path, recursive = TRUE, force = TRUE)
          stop(error)
        })
      if (!identical(rownames(persisted), features) ||
          !identical(colnames(persisted), cell_ids)) {
        unlink(path, recursive = TRUE, force = TRUE)
        .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
          "Persisted matrix fragment axes differ from its typed payload.",
          "audit")
      }
      state$source_part_counts[[ordinal]] <-
        state$source_part_counts[[ordinal]] + 1L
      part <- list(ordinal = as.integer(part_ordinal),
        source_fragment_ordinal = ordinal,
        source_fragment_identity = parent$source_fragment_identity,
        part_ordinal = as.integer(state$source_part_counts[[ordinal]]),
        cell_start = as.integer(state$cursor),
        cell_count = as.integer(length(cell_ids)),
        dimensions = list(as.integer(length(features)),
          as.integer(length(cell_ids))),
        feature_order_identity = fragment_grant$feature_order_identity,
        cell_order_identity = .wb_operation_pack_v2_identity_plain(
          "scworkbench.cell_order.v1", unname(as.list(cell_ids))),
        content_identity = .wb_operation_pack_v3_matrix_slice_content(
          matrix, features, cell_ids),
        payload_manifest_identity = .wb_operation_pack_v2_identity_scoped(
          "scworkbench.operation_pack.payload_manifest.v2",
          "matrix fragment payload tree", list(path = relative,
            sha256 = .wb_prov_file_tree_sha256(path))))
      state$parts[[part_ordinal]] <- part
      state$cursor <- part_end + 1L
      if (is.function(hook)) hook(event = "after_fragment_write",
        output = output, fragment_ordinal = part_ordinal)
      invisible(part)
    }
    finish <- function(semantic_metadata = list()) {
      if (isTRUE(state$finished) || state$cursor != length(cells) + 1L ||
          length(state$parts) < as.integer(fragment_grant$fragment_policy$
            minimum_fragment_count))
        .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
          "Matrix fragment manifest is incomplete or already closed.",
          "audit")
      manifest <- .wb_operation_pack_v3_fragment_manifest(fragment_grant,
        state$parts)
      target <- grant_record$descriptor$publication_grant$target_id
      value <- structure(list(kind = "matrix", matrix_id = target,
        dimensions = as.integer(c(length(features), length(cells))),
        feature_id = features, cell_id = cells,
        storage_profile = declarations[[output]]$storage_profile,
        fragment_manifest = manifest,
        publication_grant = grant_record$descriptor$publication_grant,
        meta = semantic_metadata %||% list()), class = "wb_primitive")
      output_dir <- file.path(stage_root, "outputs", output)
      payload <- file.path(output_dir, "payload.rds")
      saveRDS(value, payload, version = 3L, compress = FALSE)
      base$state$writes[[output]] <- list(value = value, payload = payload,
        semantic_metadata = semantic_metadata %||% list(),
        writer = "write_matrix")
      state$finished <- TRUE
      invisible(list(name = output,
        allocated_id = grant_record$allocated_id,
        grant_identity = grant_record$descriptor$grant_identity))
    }
    handle <- list(write_fragment = write_fragment, finish = finish,
      source_fragments = lapply(schedule, function(x) list(
        ordinal = as.integer(x$ordinal),
        cell_start = as.integer(x$cell_start),
        cell_count = as.integer(x$cell_count))))
    handles[[output]] <- handle
    handle
  }
  base$writers$open_matrix_fragments <- open
  base
}

.wb_operation_pack_v3_delete_matrix_registry <- function(con, matrix_id) {
  ids <- as.character(DBI::dbGetQuery(con,
    "SELECT fragment_id FROM matrix_fragments WHERE matrix_id=?;",
    params = list(matrix_id))$fragment_id)
  if (length(ids)) {
    clause <- paste(rep("?", length(ids)), collapse = ",")
    DBI::dbExecute(con, paste0("DELETE FROM matrix_fragment_features WHERE fragment_id IN (",
      clause, ");"), params = as.list(ids))
    DBI::dbExecute(con, paste0("DELETE FROM matrix_fragment_cells WHERE fragment_id IN (",
      clause, ");"), params = as.list(ids))
  }
  DBI::dbExecute(con, "DELETE FROM matrix_fragments WHERE matrix_id=?;",
    params = list(matrix_id))
  DBI::dbExecute(con, "DELETE FROM features WHERE matrix_id=?;",
    params = list(matrix_id))
  DBI::dbExecute(con, "DELETE FROM matrices WHERE matrix_id=?;",
    params = list(matrix_id))
  invisible(TRUE)
}

.wb_operation_pack_v3_retire_materialization_binding <- function(con, kind,
                                                                  id) {
  # An authenticated replace reuses the public materialization name. Remove
  # the name-to-content binding being replaced inside the same promotion
  # transaction; immutable occurrence evidence remains in prov_run_outputs
  # and its materialization payload. The new terminal promotion installs one
  # current binding for the replacement content before commit.
  if (.wb_table_exists(con, "prov_run_entity_bindings"))
    DBI::dbExecute(con, paste0(
      "DELETE FROM prov_run_entity_bindings ",
      "WHERE entity_kind=? AND entity_id=?;"), params = list(kind, id))
  if (.wb_table_exists(con, "entity_lifecycle"))
    DBI::dbExecute(con, paste0(
      "DELETE FROM entity_lifecycle ",
      "WHERE entity_kind=? AND entity_id=?;"), params = list(kind, id))
  invisible(TRUE)
}

.wb_operation_pack_v3_register_matrix_output <- function(bundle, result,
    output, value, grant) {
  matrix_id <- as.character(grant$target_id)[1]
  source_input <- as.character(result$request$outputs[[match(output,
    vapply(result$request$outputs, `[[`, character(1), "name"))]]$descriptor$
      matrix_fragment_grant$source_input)[1]
  input_record <- result$request$inputs[[match(source_input,
    vapply(result$request$inputs, `[[`, character(1), "name"))]]
  typed <- Filter(function(x) identical(as.character(x$input_name)[1],
    source_input), result$request$typed_slice_grants %||% list())
  if (length(typed) != 1L)
    .wb_operation_pack_v3_error("PYBENCH_PUBLICATION_FAILED",
      "Matrix publication cannot resolve one authenticated source matrix.",
      "publication")
  source_id <- as.character(typed[[1]]$source_reference$matrix_id)[1]
  source_info <- wb_matrix_info(bundle, source_id)
  manifest <- value$fragment_manifest
  source <- as.character(value$meta$source %||% "operation_pack_v3")[1]
  description <- as.character(value$meta$description %||% paste0(
    "Operation-pack materialization from ", source_id))[1]
  paths <- vapply(manifest$fragments, function(x) file.path(
    .wb_path_relative_to_root(result$path, bundle$dir),
    "outputs", output, "fragments", sprintf("part_%06d",
      as.integer(x$ordinal))), character(1))
  DBI::dbWithTransaction(bundle$con, {
    current <- .wb_operation_pack_v3_materialization_preimage(bundle,
      "matrix", matrix_id, result$request$execution_capability$
        source_state_identity)
    if (!identical(.wb_operation_pack_canonical_json(current),
        .wb_operation_pack_canonical_json(grant$preimage)))
      .wb_operation_pack_v3_error("PYBENCH_PUBLICATION_FAILED",
        "Matrix publication preimage changed before registry publication.",
        "publication")
    if (identical(grant$mode, "replace"))
      .wb_operation_pack_v3_delete_matrix_registry(bundle$con, matrix_id)
    DBI::dbAppendTable(bundle$con, "matrices", data.frame(
      matrix_id = matrix_id,
      layer = paste0("log1p_cp", result$request$params$scale_factor),
      feature_type = as.character(source_info$feature_type[[1]] %||% "feature"),
      n_features = length(value$feature_id), n_cells = length(value$cell_id),
      storage = "bpcells", path = paths[[1]],
      description = description,
      stringsAsFactors = FALSE))
    source_features <- DBI::dbGetQuery(bundle$con,
      "SELECT * FROM features WHERE matrix_id=? ORDER BY rowid;",
      params = list(source_id))
    source_features <- source_features[match(value$feature_id,
      source_features$feature_id), , drop = FALSE]
    source_features$matrix_id <- matrix_id
    .wb_db_append_chunked(bundle$con, "features", source_features)
    for (i in seq_along(manifest$fragments)) {
      part <- manifest$fragments[[i]]
      start <- as.integer(part$cell_start)
      ids <- value$cell_id[seq.int(start,
        start + as.integer(part$cell_count) - 1L)]
      wb_register_matrix_fragment(bundle$con, matrix_id, paths[[i]],
        value$feature_id, ids, source = source,
        description = description)
    }
  })
  invisible(TRUE)
}

.wb_operation_pack_v3_publish_materializations <- function(bundle, result) {
  grants <- stats::setNames(result$request$outputs,
    vapply(result$request$outputs, `[[`, character(1), "name"))
  fitted_observations <- stats::setNames(
    result$receipt$derived_fitted_axis_observations %||% list(),
    vapply(result$receipt$derived_fitted_axis_observations %||% list(),
      function(x) as.character(x$model_output)[1], character(1)))
  # The core alone publishes a matrix-trained fitted latent space from its
  # audited staged primitive; the pack never receives registry authority.
  for (model_name in names(grants)) {
    matrix_grant <- grants[[model_name]]$descriptor$
      contained_matrix_model_sibling_write_grant %||% NULL
    if (is.null(matrix_grant)) next
    paired <- as.character(matrix_grant$paired_space_output$name)[1]
    target <- as.character(matrix_grant$paired_space_output$allocated_id)[1]
    value <- result$outputs[[paired]]
    if (is.null(value) || !identical(as.character(value$space_id)[1], target) ||
        nrow(DBI::dbGetQuery(bundle$con,
          "SELECT 1 FROM spaces WHERE space_id=? LIMIT 1;",
          params = list(target))) != 0L)
      .wb_operation_pack_v3_error("PYBENCH_PUBLICATION_FAILED",
        "Matrix-trained fitted space is absent or its immutable ID collides.",
        "publication")
    wb_add_space(bundle, target, value$values,
      description = paste0("Matrix-trained latent space ", target),
      source = "operation_pack_v3_matrix_model", overwrite = FALSE)
  }
  # Bind a closed model tree to its private transition record before any
  # registry publication. The returned primitive is the only value exposed to
  # session promotion; the pack never receives this bundle-relative path.
  for (name in names(result$outputs)) {
    write_grant <- grants[[name]]$descriptor$contained_model_write_grant %||%
      grants[[name]]$descriptor$contained_model_sibling_write_grant %||%
      grants[[name]]$descriptor$
        contained_matrix_model_sibling_write_grant %||% NULL
    fitted <- fitted_observations[[name]] %||% NULL
    if (is.null(write_grant) && !is.null(fitted)) {
      receipt_item <- result$receipt$outputs[[match(name, vapply(
        result$receipt$outputs, `[[`, character(1), "name"))]]
      manifest <- receipt_item$descriptor$contained_model_sibling_tree$
        tree_manifest
      write_grant <- list(relative_root = paste0("outputs/", name,
          "/model_tree"), engine = manifest$engine,
        model_type = manifest$model_type, primary_path = manifest$primary_path,
        limits = list(maximum_file_count = manifest$file_count,
          maximum_total_bytes = manifest$total_size))
    }
    if (is.null(write_grant)) next
    root_rel <- .wb_path_relative_to_root(result$path, bundle$dir)
    if (is.null(root_rel)) .wb_operation_pack_v3_error(
      "PYBENCH_PUBLICATION_FAILED",
      "Contained model transition is outside the session bundle.",
      "publication")
    tree_root <- file.path(result$path, write_grant$relative_root)
    tree <- .wb_operation_pack_v3_model_tree_manifest(tree_root,
      write_grant$engine, write_grant$model_type, write_grant$primary_path,
      write_grant$limits$maximum_file_count,
      write_grant$limits$maximum_total_bytes,
      code = "PYBENCH_PUBLICATION_FAILED", phase = "publication")
    observed <- result$receipt$outputs[[match(name, vapply(
      result$receipt$outputs, `[[`, character(1), "name"))]]$descriptor
    tree_observation <- observed$contained_model_tree %||%
      observed$contained_model_sibling_tree %||%
      observed$contained_matrix_model_sibling_tree
    if (!identical(.wb_operation_pack_v3_unscoped_identity(
        tree$manifest_identity), tree_observation$tree_manifest_identity) ||
        !identical(
            .wb_operation_pack_v3_model_payload_identity(tree),
            observed$payload_manifest_identity))
      .wb_operation_pack_v3_error("PYBENCH_PUBLICATION_FAILED",
        "Published contained model tree differs from its audited receipt.",
        "publication")
    durable_root <- file.path(root_rel, write_grant$relative_root)
    result$outputs[[name]]$model_path <- durable_root
    result$outputs[[name]]$model_tree_root <- durable_root
    result$outputs[[name]]$model_primary_path <- tree$primary_path
    result$outputs[[name]]$model_tree_manifest <- tree
    result$outputs[[name]]$model_payload_manifest_identity <-
      observed$payload_manifest_identity
    sibling_grant <- grants[[name]]$descriptor$
      contained_model_sibling_write_grant %||% NULL
    matrix_grant <- grants[[name]]$descriptor$
      contained_matrix_model_sibling_write_grant %||% NULL
    if (!is.null(matrix_grant)) {
      result$outputs[[name]]$model_source_linkage <-
        matrix_grant$model_source_linkage
      paired_space_id <- as.character(
        matrix_grant$paired_space_output$allocated_id)[1]
      result$outputs[[name]]$model_space_id <- paired_space_id
      result$outputs[[name]]$in_space_id <- paired_space_id
    }
    if (!is.null(sibling_grant)) {
      source_space_id <- as.character(
        sibling_grant$model_source_linkage$source_space_id)[1]
      result$outputs[[name]]$model_source_linkage <-
        sibling_grant$model_source_linkage
      if (!nzchar(as.character(result$outputs[[name]]$model_space_id %||%
          "")[1])) result$outputs[[name]]$model_space_id <- source_space_id
      if (!nzchar(as.character(result$outputs[[name]]$in_space_id %||%
          "")[1])) result$outputs[[name]]$in_space_id <- source_space_id
    } else if (!is.null(fitted)) {
      source_space_id <- as.character(
        fitted$model_source_linkage$source_space_id)[1]
      result$outputs[[name]]$model_source_linkage <-
        fitted$model_source_linkage
      if (!nzchar(as.character(result$outputs[[name]]$model_space_id %||%
          "")[1])) result$outputs[[name]]$model_space_id <- source_space_id
      if (!nzchar(as.character(result$outputs[[name]]$in_space_id %||%
          "")[1])) result$outputs[[name]]$in_space_id <- source_space_id
    }
  }
  for (name in names(result$outputs)) {
    publication <- grants[[name]]$descriptor$publication_grant %||% NULL
    if (is.null(publication)) next
    value <- result$outputs[[name]]
    value$publication_grant <- publication
    if (identical(publication$schema,
        "scworkbench.operation_pack.space_2d_publication_grant.v1") &&
        !identical(publication$mode, "add"))
      value$promotion_mode <- "merge_space_2d"
    result$outputs[[name]] <- value
    if (identical(publication$schema,
        "scworkbench.operation_pack.space_2d_publication_grant.v1")) {
      .wb_operation_pack_v3_publish_space2d(bundle, result, name, value,
        publication)
    } else if (identical(publication$target_kind, "matrix")) {
      .wb_operation_pack_v3_register_matrix_output(bundle, result, name,
        value, publication)
    } else {
      current <- .wb_operation_pack_v3_materialization_preimage(bundle,
        "space", publication$target_id,
        result$request$execution_capability$source_state_identity)
      if (!identical(.wb_operation_pack_canonical_json(current),
          .wb_operation_pack_canonical_json(publication$preimage)))
        .wb_operation_pack_v3_error("PYBENCH_PUBLICATION_FAILED",
          "Space publication preimage changed before registry publication.",
          "publication")
      if (identical(publication$mode, "replace"))
        .wb_operation_pack_v3_retire_materialization_binding(bundle$con,
          "space", publication$target_id)
      wb_add_space(bundle, publication$target_id, value$values,
        description = paste0("Operation-pack space ", publication$target_id),
        source = "operation_pack_v3",
        overwrite = identical(publication$mode, "replace"))
    }
  }
  result
}

.wb_operation_pack_v3_publish_space2d <- function(bundle, result, output,
    value, grant) {
  target <- as.character(grant$target_id)[1]
  candidate <- value$values
  if (!is.matrix(candidate) || ncol(candidate) != 2L ||
      any(!is.finite(candidate)) || is.null(rownames(candidate)) ||
      anyDuplicated(rownames(candidate)) ||
      !identical(.wb_operation_pack_v2_identity_plain(
        "scworkbench.cell_order.v1", unname(as.list(rownames(candidate)))),
        grant$selected_cells$order_identity))
    .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
      "space_2d candidate has wrong dimensions, values, or selected-cell order.",
      "audit")
  current <- .wb_operation_pack_v3_materialization_preimage(bundle,
    "space_2d", target,
    result$request$execution_capability$source_state_identity)
  if (identical(current$state, "present")) {
    old <- wb_space(bundle, target)
    if (is.data.frame(old)) old <- .wb_as_coord_matrix(old)
    current$cell_order_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", unname(as.list(rownames(old))))
    current$coordinate_dimensions <- 2L
  } else old <- NULL
  if (!identical(.wb_operation_pack_canonical_json(current),
      .wb_operation_pack_canonical_json(grant$preimage)))
    .wb_operation_pack_v3_error("PYBENCH_PUBLICATION_FAILED",
      "space_2d publication preimage changed before locked publication.",
      "publication")
  final <- if (is.null(old)) candidate else {
    dimnames(candidate)[[2L]] <- colnames(old)
    by_cell <- rbind(old[!rownames(old) %in% rownames(candidate), ,
      drop = FALSE], candidate)
    recipient <- wb_cells(bundle, cell_set = "all")
    final_cells <- recipient[recipient %in% rownames(by_cell)]
    by_cell[match(final_cells, rownames(by_cell)), , drop = FALSE]
  }
  observed_final <- .wb_operation_pack_v2_identity_plain(
    "scworkbench.cell_order.v1", unname(as.list(rownames(final))))
  if (!identical(observed_final, grant$expected_final_cell_order_identity))
    .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
      "space_2d merged cell order differs from its authenticated grant.",
      "audit")
  sibling <- if (identical(grant$source_model_binding$source,
      "sibling_output")) as.character(grant$source_model_binding$name)[1] else
    NULL
  collector <- new.env(parent = emptyenv()); collector$new <- character()
  collector$retire <- character()
  old_option <- getOption("scworkbench.space_payload_transaction_collector",
    NULL)
  options(scworkbench.space_payload_transaction_collector = collector)
  on.exit(options(scworkbench.space_payload_transaction_collector =
    old_option), add = TRUE)
  ok <- FALSE
  tryCatch(DBI::dbWithTransaction(bundle$con, {
    .wb_space_payload_write(bundle, target, final,
      source = "operation_pack_v3",
      description = paste0("Operation-pack space ", target),
      overwrite = !is.null(old), provenance_identity =
        grant$publication_grant_identity$sha256,
      authenticated_replace = !is.null(old))
    if (!is.null(sibling)) {
      model <- result$outputs[[sibling]]
      observed_source_binding <- .wb_operation_pack_v2_identity_plain(
        "scworkbench.operation_pack.model_source_space.v1", list(
          input_name = result$request$outputs[[match(sibling, vapply(
            result$request$outputs, `[[`, character(1), "name"))]]$descriptor$
              contained_model_write_grant$source_space$input_name,
          input_descriptor_identity = result$request$outputs[[match(sibling,
            vapply(result$request$outputs, `[[`, character(1), "name"))]]$
              descriptor$contained_model_write_grant$source_space$
                input_descriptor_identity,
          selected_dimension_count = result$request$outputs[[match(sibling,
            vapply(result$request$outputs, `[[`, character(1), "name"))]]$
              descriptor$contained_model_write_grant$source_space$
                selected_dimension_count,
          selected_dimension_order_identity = result$request$outputs[[match(
            sibling, vapply(result$request$outputs, `[[`, character(1),
              "name"))]]$descriptor$contained_model_write_grant$source_space$
                selected_dimension_order_identity))
      if (is.null(model) || !identical(observed_source_binding,
          grant$source_model_binding$source_space_binding_identity))
        .wb_operation_pack_v3_error("PYBENCH_PUBLICATION_FAILED",
          "Paired model output is missing or has incompatible linkage.",
          "publication")
      .wb_ensure_space_models_table(bundle$con)
      DBI::dbExecute(bundle$con, paste0(
        "INSERT INTO space_models(space_id,model_type,source_space_id,",
        "dims_json,cell_set,uwot_args_json,seed,model_path,created_at,provenance_json) ",
        "VALUES(?,?,?,?,?,?,?,?,?,?);"), params = list(target,
          as.character(model$model_type)[1],
          as.character(model$in_space_id)[1],
          jsonlite::toJSON(as.list(result$request$params$dims),
            auto_unbox = TRUE), "authenticated_selection",
          jsonlite::toJSON(result$request$params, auto_unbox = TRUE,
            null = "null", digits = NA),
          as.integer(result$request$params$seed %||% NA_integer_),
          file.path(as.character(model$model_tree_root %||%
            model$model_path)[1], as.character(model$model_primary_path %||%
              "")[1]),
          format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
          jsonlite::toJSON(list(model_linkage = model$model_linkage,
            payload_manifest_identity =
              model$model_payload_manifest_identity), auto_unbox = TRUE,
            null = "null", digits = NA)))
    }
  }), error = function(error) {
    for (path in collector$new) if (file.exists(path)) unlink(path,
      force = TRUE)
    if (inherits(error, "wb_operation_pack_v3_error")) stop(error)
    .wb_operation_pack_v3_error("PYBENCH_PUBLICATION_FAILED",
      paste0("Atomic space_2d/model publication failed: ",
        conditionMessage(error)), "publication")
  })
  ok <- TRUE
  if (ok) for (path in collector$retire) if (file.exists(path)) unlink(path,
    force = TRUE)
  invisible(TRUE)
}
