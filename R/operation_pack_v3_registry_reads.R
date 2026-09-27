# Generic authenticated core snapshots added by operation-pack ABI v3.

.wb_operation_pack_v3_new_registry_declarations <- function(operation) {
  Filter(function(x) as.character(x$kind %||% "")[1] %in%
      c("session_cell_axis", "matrix_feature_annotations",
        "ordered_cell_metadata"),
    operation$registry_reads %||% list())
}

.wb_operation_pack_v3_cell_metadata_snapshot <- function(bundle, declaration,
    inputs, input_records, params, effective_cells) {
  input_name <- as.character(declaration$matrix_input)[1]
  input <- inputs[[input_name]]
  matrix_id <- as.character(input$matrix_id %||% "")[1]
  cells <- as.character(effective_cells %||% input$cell_id %||% character())
  if (!nzchar(matrix_id) || !length(cells) || length(cells) > 100000L ||
      anyNA(cells) || any(!nzchar(cells)) || anyDuplicated(cells) ||
      !identical(cells, as.character(input$cell_id)))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Ordered cell metadata requires the authenticated matrix cell axis.",
      "resolution")
  selections <- declaration$field_parameters
  fields <- list()
  for (selection in selections) {
    parameter <- as.character(selection$parameter)[1]
    role <- as.character(selection$role)[1]
    requested <- as.character(unlist(params[[parameter]] %||% character(),
      use.names = FALSE))
    if (length(requested) && (anyNA(requested) || any(!nzchar(requested)) ||
        anyDuplicated(requested)) ||
        (identical(selection$cardinality, "zero_or_one") &&
          length(requested) > 1L))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Ordered cell-metadata field selection is malformed.", "resolution")
    for (name in requested) {
      resolved <- tryCatch(.wb_metadata_resolve(bundle, name,
        allow_core = TRUE), error = function(error)
          .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
            conditionMessage(error), "resolution"))
      storage <- as.character(resolved$storage_type[[1]])
      if (identical(role, "continuous") && !storage %in%
          c("INTEGER", "REAL"))
        .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
          "Continuous metadata must have numeric durable storage.",
          "resolution")
      fields[[length(fields) + 1L]] <- list(parameter = parameter,
        name = name, field_id = as.character(resolved$field_id[[1]]),
        value_type = role, storage_type = storage)
    }
  }
  names <- vapply(fields, `[[`, character(1), "name")
  ids <- vapply(fields, `[[`, character(1), "field_id")
  if (length(fields) > 16L || anyDuplicated(names) || anyDuplicated(ids))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Ordered cell metadata exceeds its field ceiling or repeats a field.",
      "resolution")
  selected <- c(list(wb_ref_metadata_field("core:cell_id")),
    lapply(ids, wb_ref_metadata_field))
  frame <- wb_meta(bundle, cells = cells, cols = selected)
  if (!identical(as.character(frame[[1]]), cells))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Ordered metadata getter changed the authenticated cell order.",
      "resolution")
  for (i in seq_along(fields)) {
    values <- frame[[i + 1L]]
    if (identical(fields[[i]]$value_type, "continuous")) {
      values <- as.numeric(values)
      if (any(!is.finite(values[!is.na(values)])))
        .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
          "Continuous metadata contains non-finite values.", "resolution")
    } else values <- as.character(values)
    fields[[i]]$values <- unname(lapply(seq_along(values), function(j)
      if (is.na(values[[j]])) NULL else values[[j]]))
  }
  descriptor <- input_records[[input_name]]
  list(schema = "scworkbench.ordered_cell_metadata.snapshot.v1",
    matrix_input = input_name, matrix_id = matrix_id,
    input_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
      descriptor$descriptor_identity),
    input_content_identity = descriptor$content_identity,
    cell_count = as.integer(length(cells)), cell_id = unname(as.list(cells)),
    cell_order_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", unname(as.list(cells))),
    fields = unname(fields))
}

.wb_operation_pack_v3_registry_snapshot_validate <- function(snapshot, kind) {
  exact <- function(expected) is.list(snapshot) && !is.null(names(snapshot)) &&
    !anyDuplicated(names(snapshot)) && setequal(names(snapshot), expected)
  if (identical(kind, "ordered_cell_metadata")) {
    expected <- c("schema", "matrix_input", "matrix_id",
      "input_descriptor_identity", "input_content_identity", "cell_count",
      "cell_id", "cell_order_identity", "fields")
    cells <- as.character(unlist(snapshot$cell_id, use.names = FALSE))
    fields <- snapshot$fields %||% list()
    field_names <- vapply(fields, function(x) as.character(x$name %||% "")[1],
      character(1))
    ids <- vapply(fields, function(x) as.character(x$field_id %||% "")[1],
      character(1))
    fields_ok <- is.list(fields) && is.null(names(fields)) &&
      length(fields) <= 16L && !anyDuplicated(field_names) &&
      !anyDuplicated(ids) && all(vapply(fields, function(field) {
        values <- field$values %||% list()
        identical(sort(names(field), method = "radix"), sort(c(
          "parameter", "name", "field_id", "value_type", "storage_type",
          "values"), method = "radix")) &&
          is.character(field$parameter) && length(field$parameter) == 1L &&
          nzchar(field$parameter) && is.character(field$name) &&
          length(field$name) == 1L && nzchar(field$name) &&
          is.character(field$field_id) && length(field$field_id) == 1L &&
          nzchar(field$field_id) &&
          field$value_type %in% c("categorical", "continuous") &&
          field$storage_type %in% c("TEXT", "INTEGER", "REAL") &&
          (field$value_type != "continuous" ||
            field$storage_type %in% c("INTEGER", "REAL")) &&
          is.list(values) && is.null(names(values)) &&
          length(values) == length(cells) &&
          all(vapply(values, function(value) is.null(value) ||
            (length(value) == 1L && !is.na(value) &&
              if (field$value_type == "continuous")
                is.numeric(value) && is.finite(value) else
                is.character(value)), logical(1)))
      }, logical(1)))
    valid <- exact(expected) && identical(snapshot$schema,
      "scworkbench.ordered_cell_metadata.snapshot.v1") &&
      is.character(snapshot$matrix_input) &&
      length(snapshot$matrix_input) == 1L &&
      nzchar(snapshot$matrix_input) &&
      is.character(snapshot$matrix_id) && length(snapshot$matrix_id) == 1L &&
      nzchar(snapshot$matrix_id) && length(cells) > 0L &&
      length(cells) <= 100000L && !anyNA(cells) && all(nzchar(cells)) &&
      !anyDuplicated(cells) &&
      identical(as.integer(snapshot$cell_count)[1], length(cells)) &&
      identical(snapshot$cell_order_identity,
        .wb_operation_pack_v2_identity_plain("scworkbench.cell_order.v1",
          unname(as.list(cells)))) && fields_ok
  } else if (identical(kind, "session_cell_axis")) {
    expected <- c("schema", "selection_policy", "coverage_policy",
      "session_id", "run_id", "checkpoint_generation",
      "transition_source_state_identity", "cell_count", "cell_id",
      "cell_order_identity")
    cells <- as.character(unlist(snapshot$cell_id, use.names = FALSE))
    valid <- exact(expected) && identical(as.character(snapshot$schema)[1],
      "scworkbench.session_cell_axis.snapshot.v1") &&
      identical(as.character(snapshot$selection_policy)[1],
        "effective_session_cells_v1") &&
      identical(as.character(snapshot$coverage_policy)[1],
        "exact_complete_order_v1") && length(cells) > 0L &&
      !anyNA(cells) && all(nzchar(cells)) && !anyDuplicated(cells) &&
      identical(as.integer(snapshot$cell_count)[1], length(cells)) &&
      identical(snapshot$cell_order_identity,
        .wb_operation_pack_v2_identity_plain("scworkbench.cell_order.v1",
          unname(as.list(cells))))
  } else if (identical(kind, "matrix_feature_annotations")) {
    expected <- c("schema", "matrix_input", "matrix_id",
      "input_descriptor_identity", "input_content_identity", "feature_count",
      "feature_order_identity", "fields", "rows")
    fields <- as.character(unlist(snapshot$fields, use.names = FALSE))
    rows <- snapshot$rows %||% list()
    ids <- vapply(rows, function(x) as.character(x$feature_id %||% "")[1],
      character(1))
    row_ok <- all(vapply(rows, function(x) is.list(x) &&
      setequal(names(x), c("feature_id", "values")) &&
      identical(names(x$values), fields) &&
      (is.null(x$values$feature_type) ||
        (is.character(x$values$feature_type) &&
          length(x$values$feature_type) == 1L &&
          !is.na(x$values$feature_type))), logical(1)))
    valid <- exact(expected) && identical(as.character(snapshot$schema)[1],
      "scworkbench.matrix_feature_annotations.snapshot.v1") &&
      identical(fields, "feature_type") && length(ids) > 0L &&
      !anyNA(ids) && all(nzchar(ids)) && !anyDuplicated(ids) && row_ok &&
      identical(as.integer(snapshot$feature_count)[1], length(ids)) &&
      identical(snapshot$feature_order_identity,
        .wb_operation_pack_v2_identity_plain("scworkbench.feature_order.v1",
          unname(as.list(ids))))
  } else valid <- FALSE
  if (!isTRUE(valid)) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "Authenticated core registry snapshot is malformed.", "reopen")
  snapshot
}

.wb_operation_pack_v3_registry_snapshot_identities <- function(snapshot, kind) {
  snapshot <- .wb_operation_pack_v3_registry_snapshot_validate(snapshot, kind)
  if (identical(kind, "ordered_cell_metadata")) {
    content <- .wb_operation_pack_v2_identity_scoped(snapshot$schema,
      "canonical ordered cell metadata", snapshot)
    source <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.ordered_cell_metadata.source.v1",
      "ordered cell metadata source", list(matrix_id = snapshot$matrix_id,
        cell_order_identity = snapshot$cell_order_identity,
        fields = snapshot$fields))
  } else if (identical(kind, "session_cell_axis")) {
    content <- .wb_operation_pack_v2_identity_scoped(snapshot$schema,
      "canonical session cell-axis snapshot", snapshot)
    source <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.session_cell_axis.source.v1",
      "session cell-axis source state", list(session_id = snapshot$session_id,
        run_id = snapshot$run_id,
        checkpoint_generation = snapshot$checkpoint_generation,
        transition_source_state_identity =
          snapshot$transition_source_state_identity,
        cell_order_identity = snapshot$cell_order_identity))
  } else {
    content <- .wb_operation_pack_v2_identity_scoped(snapshot$schema,
      "canonical matrix feature annotations", snapshot)
    source <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.matrix_feature_annotations.source.v1",
      "ordered matrix feature annotations", list(matrix_id = snapshot$matrix_id,
        fields = snapshot$fields, rows = snapshot$rows))
  }
  list(content = content, source = source)
}

.wb_operation_pack_v3_session_axis_snapshot <- function(declaration,
    effective_cells, session_id, run_id, generation, source_state_identity) {
  cells <- as.character(effective_cells %||% character())
  if (!length(cells) || anyNA(cells) || any(!nzchar(cells)) ||
      anyDuplicated(cells)) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "The effective session-cell axis is empty, duplicated, or invalid.",
    "resolution")
  list(
    schema = "scworkbench.session_cell_axis.snapshot.v1",
    selection_policy = as.character(declaration$selection_policy)[1],
    coverage_policy = as.character(declaration$coverage_policy)[1],
    session_id = as.character(session_id)[1], run_id = as.character(run_id)[1],
    checkpoint_generation = as.character(generation)[1],
    transition_source_state_identity = source_state_identity,
    cell_count = as.integer(length(cells)), cell_id = unname(as.list(cells)),
    cell_order_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", unname(as.list(cells))))
}

.wb_operation_pack_v3_feature_annotation_snapshot <- function(bundle,
    declaration, inputs, input_records) {
  input_name <- as.character(declaration$matrix_input)[1]
  value <- inputs[[input_name]]
  matrix_id <- as.character(value$matrix_id %||% "")[1]
  if (!nzchar(matrix_id)) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "Matrix feature annotations require a durable matrix identifier.",
    "resolution")
  info <- tryCatch(wb_features(bundle, matrix_id),
    error = function(error) .wb_operation_pack_v3_error(
        "PYBENCH_INPUT_IDENTITY_MISMATCH", conditionMessage(error),
        "resolution"))
  fields <- as.character(unlist(declaration$fields, use.names = FALSE))
  ids <- as.character(info$feature_id)
  if (!length(ids) || anyNA(ids) || any(!nzchar(ids)) || anyDuplicated(ids) ||
      !identical(fields, "feature_type")) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "Matrix feature annotations or feature order are invalid.", "resolution")
  rows <- lapply(seq_along(ids), function(i) {
    feature_type <- info$feature_type[[i]]
    list(feature_id = ids[[i]], values = list(feature_type =
      if (length(feature_type) && !is.na(feature_type))
        as.character(feature_type)[1] else NULL))
  })
  input_record <- input_records[[input_name]]
  list(
    schema = "scworkbench.matrix_feature_annotations.snapshot.v1",
    matrix_input = input_name, matrix_id = matrix_id,
    input_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
      input_record$descriptor_identity),
    input_content_identity = input_record$content_identity,
    feature_count = as.integer(length(ids)),
    feature_order_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.feature_order.v1", unname(as.list(ids))),
    fields = unname(as.list(fields)), rows = unname(rows))
}

.wb_operation_pack_v3_registry_read_records <- function(bundle, operation,
    inputs, input_records, params, stage_root, effective_cells, session_id, run_id,
    generation, source_state_identity) {
  declarations <- .wb_operation_pack_v3_new_registry_declarations(operation)
  if (!length(declarations)) return(list(records = list(), values = list()))
  records <- vector("list", length(declarations)); values <- list()
  for (i in seq_along(declarations)) {
    declaration <- declarations[[i]]
    name <- as.character(declaration$name)[1]
    kind <- as.character(declaration$kind)[1]
    snapshot <- if (identical(kind, "session_cell_axis"))
      .wb_operation_pack_v3_session_axis_snapshot(declaration,
        effective_cells, session_id, run_id, generation,
        source_state_identity) else if (identical(kind,
          "ordered_cell_metadata"))
      .wb_operation_pack_v3_cell_metadata_snapshot(bundle, declaration,
        inputs, input_records, params, effective_cells) else
      .wb_operation_pack_v3_feature_annotation_snapshot(bundle, declaration,
        inputs, input_records)
    value_dir <- file.path(stage_root, "registry_reads", name)
    dir.create(value_dir, recursive = TRUE, showWarnings = FALSE)
    payload <- file.path(value_dir, "payload.json")
    .wb_operation_pack_v3_atomic_canonical_json(snapshot, payload)
    payload_manifest <- list(path = paste0("registry_reads/", name,
        "/payload.json"), size = as.numeric(file.info(payload)$size),
      sha256 = .wb_operation_pack_v2_file_sha256(payload))
    if (identical(kind, "session_cell_axis")) {
      selection_identity <- .wb_operation_pack_v2_identity_scoped(
        "scworkbench.session_cell_axis.selection.v1",
        "ordered effective-session selection", list(
          selection_policy = snapshot$selection_policy,
          coverage_policy = snapshot$coverage_policy,
          cell_id = snapshot$cell_id))
      content_identity <- .wb_operation_pack_v2_identity_scoped(
        snapshot$schema, "canonical session cell-axis snapshot", snapshot)
      source_identity <- .wb_operation_pack_v2_identity_scoped(
        "scworkbench.session_cell_axis.source.v1",
        "session cell-axis source state", list(session_id = snapshot$session_id,
          run_id = snapshot$run_id,
          checkpoint_generation = snapshot$checkpoint_generation,
          transition_source_state_identity =
            snapshot$transition_source_state_identity,
          cell_order_identity = snapshot$cell_order_identity))
      ancestry_identity <- .wb_operation_pack_v2_identity_scoped(
        "scworkbench.provenance.ancestry.v1", "session cell-axis ancestry",
        list(source_identity = source_identity,
          selection_identity = selection_identity))
      descriptor <- list(category = declaration$category, kind = kind,
        reader = declaration$reader,
        selection_policy = declaration$selection_policy,
        coverage_policy = declaration$coverage_policy,
        session_id = snapshot$session_id, run_id = snapshot$run_id,
        checkpoint_generation = snapshot$checkpoint_generation,
        transition_source_state_identity = source_state_identity,
        dimensions = list(snapshot$cell_count),
        cell_order_identity = snapshot$cell_order_identity,
        selection_identity = selection_identity,
        content_identity = content_identity, source_identity = source_identity,
        ancestry_identity = ancestry_identity)
    } else if (identical(kind, "ordered_cell_metadata")) {
      identities <- .wb_operation_pack_v3_registry_snapshot_identities(
        snapshot, kind)
      source_identity <- identities$source
      content_identity <- identities$content
      input_name <- as.character(declaration$matrix_input)[1]
      ancestry_identity <- .wb_operation_pack_v2_identity_scoped(
        "scworkbench.provenance.ancestry.v1",
        "ordered cell metadata ancestry", list(
          input_descriptor_identity = snapshot$input_descriptor_identity,
          input_content_identity = snapshot$input_content_identity,
          source_identity = source_identity))
      descriptor <- list(category = declaration$category, kind = kind,
        reader = declaration$reader, matrix_input = input_name,
        matrix_id = snapshot$matrix_id,
        field_parameters = declaration$field_parameters,
        fields = lapply(snapshot$fields, function(field)
          field[c("parameter", "name", "field_id", "value_type",
            "storage_type")]),
        row_order = declaration$row_order,
        missing_value_policy = declaration$missing_value_policy,
        dimensions = list(snapshot$cell_count,
          as.integer(length(snapshot$fields))),
        cell_order_identity = snapshot$cell_order_identity,
        input_descriptor_identity = snapshot$input_descriptor_identity,
        input_content_identity = snapshot$input_content_identity,
        content_identity = content_identity, source_identity = source_identity,
        ancestry_identity = ancestry_identity)
    } else {
      input_name <- as.character(declaration$matrix_input)[1]
      source_identity <- .wb_operation_pack_v2_identity_scoped(
        "scworkbench.matrix_feature_annotations.source.v1",
        "ordered matrix feature annotations", list(
          matrix_id = snapshot$matrix_id, fields = snapshot$fields,
          rows = snapshot$rows))
      content_identity <- .wb_operation_pack_v2_identity_scoped(
        snapshot$schema, "canonical matrix feature annotations", snapshot)
      ancestry_identity <- .wb_operation_pack_v2_identity_scoped(
        "scworkbench.provenance.ancestry.v1",
        "matrix feature annotation ancestry", list(
          input_descriptor_identity = snapshot$input_descriptor_identity,
          input_content_identity = snapshot$input_content_identity,
          source_identity = source_identity))
      descriptor <- list(category = declaration$category, kind = kind,
        reader = declaration$reader, matrix_input = input_name,
        fields = snapshot$fields, row_order = declaration$row_order,
        missing_annotation_policy = declaration$missing_annotation_policy,
        matrix_id = snapshot$matrix_id,
        dimensions = list(snapshot$feature_count, as.integer(length(snapshot$fields))),
        input_descriptor_identity = snapshot$input_descriptor_identity,
        input_content_identity = snapshot$input_content_identity,
        feature_order_identity = snapshot$feature_order_identity,
        content_identity = content_identity, source_identity = source_identity,
        ancestry_identity = ancestry_identity)
    }
    descriptor$payload_manifest_identity <-
      .wb_operation_pack_v2_identity_scoped(
        "scworkbench.operation_pack.payload_manifest.v2",
        "registry read payload manifest", payload_manifest)
    descriptor$descriptor_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.registry_read_descriptor.v3",
      "descriptor excluding descriptor_identity", descriptor)
    records[[i]] <- list(name = name, descriptor = descriptor)
    values[[name]] <- snapshot
  }
  order_index <- order(vapply(records, `[[`, character(1), "name"),
    method = "radix")
  ordered <- records[order_index]
  list(records = ordered,
    values = values[vapply(ordered, `[[`, character(1), "name")])
}

.wb_operation_pack_v3_registry_reads_assert_current <- function(bundle,
    operation, inputs, params, request, effective_cells, session_id, run_id,
    generation) {
  projected <- .wb_operation_pack_v3_v2_projection(list(
    schema_version = "scworkbench.operation_pack.v3", pack_abi_version = "3",
    compatibility = list(pack_abi = list(minimum = "3", maximum = "3"),
      process_protocol = list(minimum = "pybench-op-v4", maximum = "pybench-op-v4")),
    operations = list(operation)))$operations[[1]]
  .wb_operation_pack_v2_registry_reads_assert_current(bundle, projected,
    inputs, params, request$registry_reads %||% list())
  declarations <- .wb_operation_pack_v3_new_registry_declarations(operation)
  if (!length(declarations)) return(invisible(TRUE))
  records <- stats::setNames(request$registry_reads,
    vapply(request$registry_reads, `[[`, character(1), "name"))
  input_records <- stats::setNames(lapply(request$inputs, `[[`, "descriptor"),
    vapply(request$inputs, `[[`, character(1), "name"))
  source_state <- request$execution_capability$source_state_identity
  for (declaration in declarations) {
    name <- as.character(declaration$name)[1]
    kind <- as.character(declaration$kind)[1]
    snapshot <- if (identical(kind, "session_cell_axis"))
      .wb_operation_pack_v3_session_axis_snapshot(declaration,
        effective_cells, session_id, run_id, generation, source_state) else
      if (identical(kind, "ordered_cell_metadata"))
        .wb_operation_pack_v3_cell_metadata_snapshot(bundle, declaration,
          inputs, input_records, params, effective_cells) else
      .wb_operation_pack_v3_feature_annotation_snapshot(bundle, declaration,
        inputs, input_records)
    identities <- .wb_operation_pack_v3_registry_snapshot_identities(
      snapshot, kind)
    observed_content <- identities$content
    observed_source <- identities$source
    expected <- records[[name]]$descriptor
    if (!identical(observed_content, expected$content_identity) ||
        !identical(observed_source, expected$source_identity))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        paste0("Authenticated core snapshot changed after preflight for '",
          name, "'."), "dispatch")
  }
  invisible(TRUE)
}
