# Phase 5 additive ABI-v3 generic capabilities.

.wb_operation_pack_v3_phase5_fail <- function(message,
    phase = "semantic_admission",
    code = "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID") {
  .wb_operation_pack_v3_error(code, message, phase)
}

.wb_operation_pack_v3_phase5_names_unique <- function(values, label) {
  values <- as.character(values)
  if (length(values) && (anyNA(values) || any(!nzchar(values)) ||
      anyDuplicated(values))) .wb_operation_pack_v3_phase5_fail(
        paste0(label, " must be unique and nonempty."))
  invisible(values)
}

.wb_operation_pack_v3_phase5_semantic_validate <- function(operation,
    inputs, outputs, properties) {
  opname <- as.character(operation$qualified_name)[1]
  adoptions <- operation$supported_external_state_adoptions %||% list()
  if (length(adoptions) > 1L) .wb_operation_pack_v3_phase5_fail(
    paste0("Operation '", opname,
      "' declares more than one external-state adoption."))
  for (adoption in adoptions) {
    state <- inputs[[as.character(adoption$state_input)[1]]]
    source_parameter <- properties[[as.character(
      adoption$source_parameter)[1]]]
    model <- outputs[[as.character(adoption$model_output)[1]]]
    closure <- as.character(unlist(adoption$required_closure_outputs,
      use.names = FALSE))
    allowed_states <- as.character(unlist(
      adoption$allowed_source_byte_states, use.names = FALSE))
    allowed_types <- vapply(adoption$allowed_state_types, function(x)
      paste(as.character(x$engine)[1], as.character(x$model_type)[1],
        sep = "\034"), character(1))
    sibling <- model$contained_model_sibling_closure_policy %||% NULL
    valid <- !is.null(state) && identical(as.character(state$kind)[1],
      "external_state_candidate") && isTRUE(state$required) &&
      identical(as.character(state$alignment)[1], "none") &&
      !is.null(source_parameter) && identical(
        as.character(source_parameter$type %||% "")[1], "object") &&
      !is.null(model) && identical(as.character(model$kind)[1], "model_ref") &&
      !is.null(sibling) && length(adoption$allowed_state_types) > 0L &&
      !anyDuplicated(allowed_types) && length(allowed_states) > 0L &&
      !anyDuplicated(allowed_states) && all(allowed_states %in% c(
        "bytes_verified", "bytes_not_inspected", "bytes_unavailable")) &&
      !anyDuplicated(closure) && all(closure %in% names(outputs)) &&
      !as.character(adoption$model_output)[1] %in% closure &&
      identical(as.character(sibling$engine)[1],
        as.character(adoption$allowed_state_types[[1]]$engine)[1]) &&
      identical(as.character(sibling$model_type)[1],
        as.character(adoption$allowed_state_types[[1]]$model_type)[1]) &&
      identical(as.character(sibling$primary_path)[1],
        as.character(adoption$primary_path)[1]) &&
      identical(as.character(sibling$required_sibling_terminals), closure) &&
      as.integer(adoption$maximum_file_count) <= 32L &&
      as.numeric(adoption$maximum_total_bytes) <= 1073741824 &&
      as.integer(adoption$maximum_cell_count) <= 10000000L
    if (!valid) .wb_operation_pack_v3_phase5_fail(paste0("Operation '",
      opname, "' has an invalid supported external-state adoption."))
    .wb_operation_pack_v3_assert_self_identity(adoption,
      "declaration_identity", "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
      "semantic_admission")
  }
  self_reads <- operation$self_linked_contained_model_reads %||% list()
  .wb_operation_pack_v3_phase5_names_unique(vapply(self_reads, `[[`,
    character(1), "name"), paste0("Operation '", opname,
      "' self-linked model read names"))
  for (read in self_reads) {
    input <- inputs[[as.character(read$input)[1]]]
    pairs <- vapply(read$allowed_models, function(x) paste0(
      as.character(x$engine)[1], "\034", as.character(x$model_type)[1]),
      character(1))
    wildcard <- any(vapply(read$allowed_models, function(x) any(c(
      as.character(x$engine)[1], as.character(x$model_type)[1]) %in%
        c("*", "any")), logical(1)))
    if (is.null(input) || !identical(as.character(input$kind)[1],
        "model_ref") || !length(pairs) || anyDuplicated(pairs) || wildcard ||
        as.integer(read$maximum_file_count) > 32L ||
        as.numeric(read$maximum_total_bytes) > 1073741824)
      .wb_operation_pack_v3_phase5_fail(paste0("Operation '", opname,
        "' has an invalid self-linked contained-model read declaration."))
  }

  sibling_outputs <- Filter(function(x) !is.null(
    x$contained_model_sibling_closure_policy), operation$outputs)
  for (output in sibling_outputs) {
    policy <- output$contained_model_sibling_closure_policy
    source <- inputs[[as.character(policy$source_space_input)[1]]]
    siblings <- as.character(unlist(policy$required_sibling_terminals,
      use.names = FALSE))
    sibling_defs <- outputs[siblings]
    dims <- policy$dimensions_parameter
    dims_valid <- is.null(dims) || !is.null(properties[[as.character(dims)[1]]])
    valid <- identical(as.character(output$kind)[1], "model_ref") &&
      is.null(output$contained_model_policy) && !is.null(source) &&
      identical(as.character(source$kind)[1], "space") &&
      !anyDuplicated(siblings) && !as.character(output$name)[1] %in% siblings &&
      length(sibling_defs) == length(siblings) &&
      all(vapply(sibling_defs, function(x) isTRUE(x$required) &&
        identical(as.character(x$category)[1], "terminal_artifact") &&
        identical(as.character(x$promotion_group)[1],
          as.character(output$promotion_group)[1]), logical(1))) &&
      dims_valid && as.integer(policy$maximum_file_count) <= 32L &&
      as.numeric(policy$maximum_total_bytes) <= 1073741824
    if (!valid) .wb_operation_pack_v3_phase5_fail(paste0("Operation '",
      opname, "' has an invalid sibling-bound model closure."))
  }

  collections <- operation$artifact_collection_reads %||% list()
  .wb_operation_pack_v3_phase5_names_unique(vapply(collections, `[[`,
    character(1), "name"), paste0("Operation '", opname,
      "' retained-artifact collection names"))
  if (length(collections) > 8L) .wb_operation_pack_v3_phase5_fail(
    "An operation may declare at most eight artifact collections.")
  for (declaration in collections) {
    slots <- declaration$reference_slots
    slot_names <- vapply(slots, `[[`, character(1), "slot")
    fields <- vapply(slots, `[[`, character(1), "field")
    .wb_operation_pack_v3_phase5_names_unique(slot_names,
      "Artifact collection slots")
    .wb_operation_pack_v3_phase5_names_unique(fields,
      "Artifact collection fields")
    activation_ok <- vapply(slots, function(slot) identical(
      isTRUE(slot$required), identical(as.character(slot$activation)[1],
        "always")), logical(1))
    valid <- !is.null(properties[[as.character(declaration$parameter)[1]]]) &&
      as.integer(declaration$minimum_items) <=
        as.integer(declaration$maximum_items) &&
      as.integer(declaration$maximum_items) <= 64L && length(slots) <= 8L &&
      all(activation_ok) && as.integer(declaration$maximum_references) <= 256L &&
      as.numeric(declaration$maximum_single_payload_bytes) <= 268435456 &&
      as.numeric(declaration$maximum_total_payload_bytes) <= 1073741824 &&
      as.numeric(declaration$maximum_single_payload_bytes) <=
        as.numeric(declaration$maximum_total_payload_bytes)
    if (!valid) .wb_operation_pack_v3_phase5_fail(paste0("Operation '",
      opname, "' has an invalid retained-artifact collection declaration."))
  }

  axes <- operation$named_cell_axis_collections %||% list()
  .wb_operation_pack_v3_phase5_names_unique(vapply(axes, `[[`, character(1),
    "name"), paste0("Operation '", opname, "' named-axis collection names"))
  if (length(axes) > 4L) .wb_operation_pack_v3_phase5_fail(
    "An operation may declare at most four named-axis collections.")
  for (declaration in axes) {
    space <- inputs[[as.character(declaration$space_input)[1]]]
    valid <- !is.null(properties[[as.character(declaration$parameter)[1]]]) &&
      !is.null(space) && as.character(space$kind)[1] %in% c("space",
        "space_2d") && as.integer(declaration$minimum_axes) <=
          as.integer(declaration$maximum_axes) &&
      as.integer(declaration$maximum_axes) <= 64L &&
      as.integer(declaration$minimum_cells_per_axis) <=
        as.integer(declaration$maximum_cells_per_axis) &&
      as.integer(declaration$maximum_cells_per_axis) <= 10000000L &&
      as.integer(declaration$maximum_total_memberships) <= 20000000L
    if (!valid) .wb_operation_pack_v3_phase5_fail(paste0("Operation '",
      opname, "' has an invalid named-cell-axis collection declaration."))
  }

  groups <- operation$optional_display_axis_groups %||% list()
  .wb_operation_pack_v3_phase5_names_unique(vapply(groups, `[[`, character(1),
    "name"), paste0("Operation '", opname, "' optional display group names"))
  collection_names <- vapply(collections, `[[`, character(1), "name")
  for (group in groups) {
    scope <- as.character(group$scope)[1]
    collection <- as.character(group$collection_read %||% "")[1]
    collection_declaration <- collections[[match(collection,
      vapply(collections, function(x) as.character(x$name)[1L],
        character(1)))]]
    collection_parameter <- as.character(
      collection_declaration$parameter %||% "")[1L]
    item_properties <- properties[[collection_parameter]]$items$properties %||%
      list()
    display_parameter <- as.character(
      group$display_space_selector$operation_parameter)[1]
    item_display_field <- as.character(
      group$display_space_selector$item_field %||% "")[1]
    endpoint_parameters <- vapply(group$activation, function(x)
      as.character(x$endpoint_parameter)[1], character(1))
    top_parameters <- vapply(group$activation, function(x)
      as.character(x$top_level_cell_set_parameter %||% "")[1], character(1))
    valid <- length(groups) <= 64L &&
      identical(as.character(unlist(group$endpoint_roles,
        use.names = FALSE)), c("start", "end")) &&
      !is.null(properties[[display_parameter]]) &&
      ((identical(scope, "operation") &&
          all(endpoint_parameters %in% names(properties)) &&
          !nzchar(item_display_field)) ||
        (identical(scope, "collection_item") &&
          all(endpoint_parameters %in% names(item_properties)) &&
          nzchar(item_display_field) &&
          item_display_field %in% names(item_properties))) &&
      all(!nzchar(top_parameters) | top_parameters %in% names(properties)) &&
      ((identical(scope, "operation") && !nzchar(collection)) ||
       (identical(scope, "collection_item") &&
         collection %in% collection_names)) &&
      as.integer(group$maximum_groups) <= 64L &&
      as.integer(group$maximum_display_cells) <= 10000000L &&
      as.integer(group$maximum_cells_per_endpoint_axis) <= 10000000L &&
      as.integer(group$maximum_total_endpoint_memberships) <= 20000000L
    if (!valid) .wb_operation_pack_v3_phase5_fail(paste0("Operation '",
      opname, "' has an invalid optional display/endpoint declaration."))
  }
  invisible(TRUE)
}

.wb_operation_pack_v3_phase5_payload_manifest <- function(path, relative) {
  .wb_operation_pack_v2_identity_plain(
    "scworkbench.operation_pack.payload_manifest.v2", list(path = relative,
      size = as.numeric(file.info(path)$size),
      sha256 = .wb_operation_pack_v2_file_sha256(path)))
}

.wb_operation_pack_v3_phase5_primitive_identity <- function(bundle, value) {
  if (identical(as.character(value$kind %||% "")[1], "space") &&
      nzchar(as.character(value$space_id %||% "")[1])) {
    verified <- tryCatch(.wb_space_payload_summary(bundle, value$space_id,
      verify_hash = TRUE), error = identity)
    if (inherits(verified, "error")) .wb_operation_pack_v3_error(
      "PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Retained space payload differs from its durable content identity.",
      "resolution")
  }
  observed <- .wb_prov_payload_identity(bundle, value)
  if (!identical(as.character(observed$verification_status)[1],
      "content_verified")) .wb_operation_pack_v3_error(
        "PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Retained typed payload is not content verified.", "resolution")
  list(scheme = as.character(observed$content_identity_scheme)[1],
    sha256 = as.character(observed$content_sha256)[1])
}

.wb_operation_pack_v3_phase5_private_primitive <- function(value) {
  value <- .wb_operation_pack_v2_deep_copy(value)
  if (identical(as.character(value$kind %||% "")[1], "model_ref")) {
    # Model bytes have their own G1 capability. A G4 metadata reference must
    # not leak a committed/runtime path or silently become a model-tree reader.
    for (field in c("model_path", "model_tree_root", "model_primary_path",
        "model_payload_entry", "model_tree_manifest")) value[[field]] <- NULL
  }
  value
}

.wb_operation_pack_v3_prepare_artifact_collections <- function(bundle,
    operation, params, stage_root) {
  grants <- list(); values <- list(); source_snapshots <- list()
  for (declaration in operation$artifact_collection_reads %||% list()) {
    name <- as.character(declaration$name)[1]
    parameter <- as.character(declaration$parameter)[1]
    raw_items <- params[[parameter]] %||% list()
    if (!is.list(raw_items)) .wb_operation_pack_v3_error(
      "PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Artifact collection parameter must be an array of objects.",
      "resolution")
    n <- length(raw_items)
    if (n < as.integer(declaration$minimum_items) ||
        n > as.integer(declaration$maximum_items))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Artifact collection item count exceeds its declared bounds.",
        "resolution")
    key_field <- as.character(declaration$item_key_field)[1]
    order_field <- as.character(declaration$order_field)[1]
    keys <- vapply(raw_items, function(x) as.character(x[[key_field]] %||%
      "")[1], character(1))
    orders <- vapply(raw_items, function(x) suppressWarnings(as.numeric(
      x[[order_field]] %||% NA_real_)[1]), numeric(1))
    if (any(!nzchar(keys)) || anyDuplicated(keys) || any(!is.finite(orders)) ||
        anyDuplicated(orders)) .wb_operation_pack_v3_error(
          "PYBENCH_INPUT_IDENTITY_MISMATCH",
          "Artifact collection keys and finite order values must be unique.",
          "resolution")
    resolved_order <- order(orders, method = "radix")
    descriptors <- list(); resolved_values <- list(); seen <- character()
    total_bytes <- 0
    for (resolved_ordinal in seq_along(resolved_order)) {
      parameter_ordinal <- resolved_order[[resolved_ordinal]]
      item <- raw_items[[parameter_ordinal]]
      refs <- list(); item_values <- list()
      for (slot in declaration$reference_slots) {
        slot_name <- as.character(slot$slot)[1]
        field <- as.character(slot$field)[1]
        raw_ref <- item[[field]] %||% NULL
        active <- !is.null(raw_ref) && !(is.character(raw_ref) &&
          length(raw_ref) == 1L && !nzchar(raw_ref))
        if (!active && isTRUE(slot$required)) .wb_operation_pack_v3_error(
          "PYBENCH_INPUT_IDENTITY_MISMATCH",
          paste0("Required artifact collection slot is absent: ", slot_name),
          "resolution")
        if (!active) next
        ref <- .wb_operation_pack_v3_artifact_ref(raw_ref)
        if (is.null(ref)) .wb_operation_pack_v3_error(
          "PYBENCH_INPUT_IDENTITY_MISMATCH",
          "Artifact collection reference is not a symbolic artifact reference.",
          "resolution")
        output_name <- as.character(raw_ref$output_name %||% ref$output %||%
          "")[1]
        ref_key <- paste(ref$artifact_id, output_name, sep = "\034")
        if (ref_key %in% seen) .wb_operation_pack_v3_error(
          "PYBENCH_INPUT_IDENTITY_MISMATCH",
          "Artifact/output reference occurs more than once in a collection.",
          "resolution")
        seen <- c(seen, ref_key)
        primitive <- tryCatch(wb_art_load(bundle, ref$artifact_id),
          error = identity)
        if (inherits(primitive, "error") || !.wb_is_primitive(primitive))
          .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
            "Artifact collection reference cannot be loaded.", "resolution")
        kind <- as.character(primitive$kind)[1]
        allowed <- as.character(unlist(slot$allowed_kinds, use.names = FALSE))
        if (!kind %in% allowed) .wb_operation_pack_v3_error(
          "PYBENCH_CAPABILITY_MISMATCH",
          "Artifact collection reference kind is outside its slot allowlist.",
          "resolution")
        input_record <- .wb_operation_pack_v2_input_descriptor(slot_name,
          primitive, list(name = slot_name, kind = kind, required = TRUE,
            alignment = "none"))$descriptor
        ancestry_decl <- list(name = paste0(name, "_", resolved_ordinal,
          "_", slot_name), input = slot_name, parameter_assertions = list())
        ancestry <- .wb_operation_pack_v3_artifact_ancestry(bundle,
          ancestry_decl, input_record, ref$artifact_id)
        if (nzchar(output_name) && !identical(output_name,
            as.character(ancestry$source_output_name)[1]))
          .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
            "Artifact collection output name differs from its producer output.",
            "resolution")
        lifecycle_identity <- .wb_operation_pack_v2_identity_plain(
          "scworkbench.artifact.lifecycle.v1", ancestry$lifecycle)
        relative <- paste0("artifact_collection_reads/", name, "/",
          resolved_ordinal, "/", slot_name, "/payload.rds")
        path <- file.path(stage_root, relative)
        dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
        private_primitive <- .wb_operation_pack_v3_phase5_private_primitive(
          primitive)
        saveRDS(private_primitive, path, version = 3L, compress = FALSE)
        ancestry_relative <- paste0("artifact_collection_reads/", name, "/",
          resolved_ordinal, "/", slot_name, "/ancestry.json")
        ancestry_path <- file.path(stage_root, ancestry_relative)
        .wb_operation_pack_v3_atomic_canonical_json(ancestry, ancestry_path)
        bytes <- as.numeric(file.info(path)$size) +
          as.numeric(file.info(ancestry_path)$size)
        if (bytes > as.numeric(declaration$maximum_single_payload_bytes))
          .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
            "Artifact collection payload exceeds its per-payload limit.",
            "staging")
        total_bytes <- total_bytes + bytes
        payload_manifest <- .wb_operation_pack_v3_phase5_payload_manifest(
          path, relative)
        reference <- list(slot = slot_name, artifact_id = ref$artifact_id,
          output_name = as.character(ancestry$source_output_name)[1],
          kind = kind, content_identity = input_record$content_identity,
          lifecycle_identity = lifecycle_identity,
          ancestry_identity = .wb_operation_pack_v3_unscoped_identity(
            ancestry$snapshot_identity),
          payload_manifest_identity = payload_manifest)
        reference$reference_identity <- .wb_operation_pack_v2_identity_plain(
          "scworkbench.retained_artifact_reference.v1", reference)
        refs[[length(refs) + 1L]] <- reference
        item_values[[slot_name]] <- private_primitive
        source_snapshots[[ref_key]] <- list(reference = reference,
          ancestry = ancestry, primitive = primitive,
          ancestry_declaration = ancestry_decl)
      }
      descriptor <- list(parameter_ordinal = as.integer(parameter_ordinal),
        resolved_ordinal = as.integer(resolved_ordinal),
        item_key = keys[[parameter_ordinal]],
        order_value = orders[[parameter_ordinal]], references = refs)
      descriptor$item_identity <- .wb_operation_pack_v2_identity_plain(
        "scworkbench.retained_artifact_collection_item.v1", descriptor)
      if (!length(refs)) .wb_operation_pack_v3_error(
        "PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Artifact collection item activates no declared reference slot.",
        "resolution")
      descriptors[[resolved_ordinal]] <- descriptor
      resolved_values[[resolved_ordinal]] <- item_values
    }
    if (length(seen) > as.integer(declaration$maximum_references) ||
        total_bytes > as.numeric(declaration$maximum_total_payload_bytes))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Artifact collection exceeds its reference or aggregate-byte limit.",
        "staging")
    collection <- list(purpose = name, entries = lapply(descriptors,
      function(x) list(resolved_ordinal = x$resolved_ordinal,
        item_key = x$item_key, item_identity = x$item_identity)))
    collection_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.retained_artifact_collection.v1", collection)
    grant <- list(schema =
        "scworkbench.operation_pack.retained_artifact_collection_grant.v1",
      name = name, parameter = parameter,
      reader = "read_retained_artifact_collection_item",
      limits = list(minimum_items = as.integer(declaration$minimum_items),
        maximum_items = as.integer(declaration$maximum_items),
        maximum_references = as.integer(declaration$maximum_references),
        maximum_single_payload_bytes = as.integer(
          declaration$maximum_single_payload_bytes),
        maximum_total_payload_bytes = as.integer(
          declaration$maximum_total_payload_bytes)),
      collection_identity = collection_identity, items = descriptors,
      call_discipline = "resolved_ordinal_slot_exactly_once")
    grant$grant_identity <- .wb_operation_pack_v2_identity_scoped(grant$schema,
      "grant excluding grant_identity", grant)
    grants[[name]] <- grant; values[[name]] <- resolved_values
  }
  list(grants = grants, values = values, sources = source_snapshots)
}

.wb_operation_pack_v3_named_axis <- function(bundle, name, role,
    source_kind, source_cells, space_cells, space_descriptor_identity,
    parameter_selector_identity = NULL) {
  source_cells <- as.character(source_cells)
  bundle_cells <- as.character(wb_cells(bundle, cell_set = "all"))
  if (!length(source_cells) || anyNA(source_cells) ||
      any(!nzchar(source_cells)) || anyDuplicated(source_cells) ||
      length(setdiff(source_cells, bundle_cells)))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Named axis contains duplicate, empty, or foreign bundle cells.",
      "resolution")
  source_membership_identity <- .wb_operation_pack_v2_identity_plain(
    "scworkbench.cell_set.membership.v1",
    unname(as.list(sort(source_cells, method = "radix"))))
  universe_identity <- .wb_operation_pack_v2_identity_plain(
    "scworkbench.cell_order.v1", unname(as.list(bundle_cells)))
  source <- list(source_kind = source_kind,
    source_name = if (identical(source_kind, "named_cell_set")) name else NULL,
    parameter_selector_identity = parameter_selector_identity,
    source_membership_identity = source_membership_identity,
    bundle_cell_universe_identity = universe_identity)
  source_identity <- .wb_operation_pack_v2_identity_plain(
    "scworkbench.named_cell_axis.source.v1", source)
  selected <- space_cells[space_cells %in% source_cells]
  if (!length(selected)) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "Named axis has an empty selected-space projection.", "resolution")
  cell_order_identity <- .wb_operation_pack_v2_identity_plain(
    "scworkbench.cell_order.v1", unname(as.list(selected)))
  selection <- list(source_identity = source_identity,
    space_descriptor_identity = space_descriptor_identity,
    projection_policy = "bundle_membership_intersect_space_axis_v1",
    source_count = as.integer(length(source_cells)),
    selected_count = as.integer(length(selected)),
    excluded_by_projection_count = as.integer(length(source_cells) -
      length(selected)), selected_cell_id = unname(as.list(selected)),
    cell_order_identity = cell_order_identity)
  selection_identity <- .wb_operation_pack_v2_identity_plain(
    "scworkbench.named_cell_axis.selection.v1", selection)
  axis <- list(name = as.character(name)[1], role = as.character(role)[1],
    source_identity = source_identity, selection_identity = selection_identity,
    cell_count = as.integer(length(selected)),
    cell_order_identity = cell_order_identity,
    cell_id = unname(as.list(selected)))
  axis$axis_identity <- .wb_operation_pack_v2_identity_plain(
    "scworkbench.named_cell_axis.v1", axis)
  list(axis = axis, source = source, selection = selection)
}

.wb_operation_pack_v3_prepare_named_axis_collections <- function(bundle,
    operation, inputs, input_records, params, stage_root) {
  grants <- list(); values <- list(); sources <- list()
  for (declaration in operation$named_cell_axis_collections %||% list()) {
    name <- as.character(declaration$name)[1]
    parameter <- as.character(declaration$parameter)[1]
    space_name <- as.character(declaration$space_input)[1]
    space <- inputs[[space_name]]
    space_cells <- as.character(space$cell_id %||% rownames(space$values))
    axis_names <- as.character(unlist(params[[parameter]] %||% character(),
      use.names = FALSE))
    if (length(axis_names) < as.integer(declaration$minimum_axes) ||
        length(axis_names) > as.integer(declaration$maximum_axes) ||
        anyNA(axis_names) || any(!nzchar(axis_names)) || anyDuplicated(axis_names))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Named-axis collection names violate declared bounds or uniqueness.",
        "resolution")
    axes <- list(); axis_values <- list(); total <- 0L
    for (i in seq_along(axis_names)) {
      set_name <- axis_names[[i]]
      source_cells <- tryCatch(as.character(wb_cells(bundle,
        cell_set = set_name)), error = identity)
      if (inherits(source_cells, "error")) .wb_operation_pack_v3_error(
        "PYBENCH_INPUT_IDENTITY_MISMATCH",
        paste0("Unknown named cell set: ", set_name), "resolution")
      resolved <- .wb_operation_pack_v3_named_axis(bundle, set_name,
        "checkpoint", "named_cell_set", source_cells, space_cells,
        .wb_operation_pack_v3_unscoped_identity(
          input_records[[space_name]]$descriptor_identity))
      count <- length(resolved$axis$cell_id)
      if (count < as.integer(declaration$minimum_cells_per_axis) ||
          count > as.integer(declaration$maximum_cells_per_axis))
        .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
          "Named axis violates its declared membership bounds.", "resolution")
      total <- total + count
      relative <- paste0("named_cell_axis_reads/", name, "/", i,
        "/payload.json")
      path <- file.path(stage_root, relative)
      .wb_operation_pack_v3_atomic_canonical_json(resolved$axis, path)
      descriptor <- list(ordinal = as.integer(i), name = set_name,
        role = "checkpoint", source_count = resolved$selection$source_count,
        selected_count = resolved$selection$selected_count,
        excluded_by_projection_count = resolved$selection$
          excluded_by_projection_count,
        source_identity = resolved$axis$source_identity,
        selection_identity = resolved$axis$selection_identity,
        cell_order_identity = resolved$axis$cell_order_identity,
        axis_identity = resolved$axis$axis_identity,
        payload_manifest_identity =
          .wb_operation_pack_v3_phase5_payload_manifest(path, relative))
      axes[[i]] <- descriptor; axis_values[[i]] <- resolved$axis
      sources[[paste(name, i, sep = "\034")]] <- list(name = set_name,
        source_cells = source_cells, space_name = space_name,
        space_id = as.character(space$space_id)[1L],
        space_cells = space_cells,
        space_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
          input_records[[space_name]]$descriptor_identity),
        descriptor = descriptor)
    }
    if (total > as.integer(declaration$maximum_total_memberships))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Named-axis collection exceeds its aggregate membership limit.",
        "resolution")
    entries <- lapply(axes, function(x) list(ordinal = x$ordinal,
      name = x$name, role = x$role, axis_identity = x$axis_identity))
    collection_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.named_cell_axis_collection.v1", list(purpose = name,
        entries = entries))
    overlap <- list()
    if (length(axis_values) > 1L) for (i in seq_len(length(axis_values) - 1L))
      for (j in seq.int(i + 1L, length(axis_values))) overlap[[length(overlap) +
        1L]] <- list(left_ordinal = as.integer(i),
          right_ordinal = as.integer(j), count = as.integer(length(intersect(
            axis_values[[i]]$cell_id, axis_values[[j]]$cell_id))))
    counts <- vapply(axes, `[[`, integer(1), "selected_count")
    grant <- list(schema =
        "scworkbench.operation_pack.named_cell_axis_collection_grant.v1",
      name = name, parameter = parameter, space_input = space_name,
      space_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
        input_records[[space_name]]$descriptor_identity),
      collection_identity = collection_identity, axes = axes,
      quality_observations = list(pairwise_overlap_counts = overlap,
        minimum_selected_count = as.integer(min(counts)),
        maximum_selected_count = as.integer(max(counts)),
        selected_count_ratio = as.numeric(max(counts) / min(counts))),
      limits = list(minimum_axes = as.integer(declaration$minimum_axes),
        maximum_axes = as.integer(declaration$maximum_axes),
        minimum_cells_per_axis = as.integer(
          declaration$minimum_cells_per_axis),
        maximum_cells_per_axis = as.integer(
          declaration$maximum_cells_per_axis),
        maximum_total_memberships = as.integer(
          declaration$maximum_total_memberships)),
      call_discipline = "axis_ordinal_exactly_once")
    grant$grant_identity <- .wb_operation_pack_v2_identity_scoped(grant$schema,
      "grant excluding grant_identity", grant)
    grants[[name]] <- grant; values[[name]] <- axis_values
  }
  list(grants = grants, values = values, sources = sources)
}

.wb_operation_pack_v3_endpoint_selector <- function(endpoint, top_level,
    parameter_path) {
  if (is.list(endpoint) && !is.null(endpoint$x) && !is.null(endpoint$y)) {
    coordinates <- suppressWarnings(as.numeric(c(endpoint$x, endpoint$y)))
    if (length(coordinates) != 2L || any(!is.finite(coordinates)))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Explicit endpoint coordinates must be finite x/y scalars.",
        "resolution")
    return(NULL)
  }
  literal <- if (is.list(endpoint) && !is.null(endpoint$cells))
    endpoint$cells else if (is.list(endpoint) && !is.null(endpoint$cell_ids))
      endpoint$cell_ids else NULL
  if (!is.null(literal)) return(list(kind = "literal_parameter_cells",
    name = parameter_path, cells = as.character(unlist(literal,
      use.names = FALSE)), selector = list(parameter_path = parameter_path,
        source = if (!is.null(endpoint$cells)) "cells" else "cell_ids")))
  top <- as.character(top_level %||% "")[1]
  symbolic <- if (nzchar(top)) top else if (is.character(endpoint) &&
      length(endpoint) == 1L) endpoint else if (is.list(endpoint))
        as.character(endpoint$cell_set %||% "")[1] else ""
  if (!nzchar(symbolic)) return(NULL)
  list(kind = "named_cell_set", name = symbolic, cells = NULL,
    selector = list(parameter_path = parameter_path,
      source = if (nzchar(top)) "top_level_cell_set" else "endpoint_cell_set"))
}

.wb_operation_pack_v3_prepare_optional_display_groups <- function(bundle,
    operation, params, stage_root, artifact_collections) {
  grants <- list(); values <- list(); sources <- list(); activated <- 0L
  declarations <- stats::setNames(operation$artifact_collection_reads %||%
    list(), vapply(operation$artifact_collection_reads %||% list(), `[[`,
      character(1), "name"))
  for (declaration in operation$optional_display_axis_groups %||% list()) {
    name <- as.character(declaration$name)[1]
    scope <- as.character(declaration$scope)[1]
    groups <- if (identical(scope, "operation")) list(list(key = "operation",
      item = NULL, item_identity = NULL)) else {
        collection_name <- as.character(declaration$collection_read)[1]
        collection_grant <- artifact_collections$grants[[collection_name]]
        collection_decl <- declarations[[collection_name]]
        raw <- params[[as.character(collection_decl$parameter)[1]]]
        lapply(collection_grant$items, function(item) list(
          key = item$item_key, item = raw[[item$parameter_ordinal]],
          item_identity = item$item_identity))
      }
    for (group in groups) {
      endpoint_values <- list(); selectors <- list()
      for (role in c("start", "end")) {
        spec <- declaration$activation[[role]]
        endpoint_parameter <- as.character(spec$endpoint_parameter)[1]
        endpoint <- if (identical(scope, "operation"))
          params[[endpoint_parameter]] else group$item[[endpoint_parameter]]
        top_name <- as.character(spec$top_level_cell_set_parameter %||% "")[1]
        top <- if (nzchar(top_name)) params[[top_name]] else NULL
        selectors[[role]] <- .wb_operation_pack_v3_endpoint_selector(endpoint,
          top, paste(name, group$key, role, endpoint_parameter, sep = "/"))
      }
      if (all(vapply(selectors, is.null, logical(1)))) next
      activated <- activated + 1L
      if (activated > as.integer(declaration$maximum_groups))
        .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
          "Optional display groups exceed their activation limit.",
          "resolution")
      display_spec <- declaration$display_space_selector
      operation_space <- as.character(params[[as.character(
        display_spec$operation_parameter)[1]]] %||% "")[1]
      item_field <- as.character(display_spec$item_field %||% "")[1]
      item_space <- if (!is.null(group$item) && nzchar(item_field))
        as.character(group$item[[item_field]] %||% "")[1] else ""
      space_id <- if (nzchar(item_space)) item_space else operation_space
      if (!nzchar(space_id)) .wb_operation_pack_v3_error(
        "PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Activated endpoint axes require an authorized display space.",
        "resolution")
      coordinates <- tryCatch(.wb_as_coord_matrix(
        wb_space(bundle, space_id)),
        error = identity)
      verified_display <- tryCatch(.wb_space_payload_summary(bundle, space_id,
        verify_hash = TRUE), error = identity)
      if (inherits(coordinates, "error") || ncol(coordinates) != 2L ||
          !nrow(coordinates) || is.null(rownames(coordinates)) ||
          anyDuplicated(rownames(coordinates)) || any(!is.finite(coordinates)) ||
          inherits(verified_display, "error"))
        .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
          "Optional display space must be a complete finite two-dimensional space.",
          "resolution")
      cells <- rownames(coordinates)
      if (length(cells) > as.integer(declaration$maximum_display_cells))
        .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
          "Optional display space exceeds its cell limit.", "resolution")
      primitive <- structure(list(kind = "space", space_id = space_id,
        values = coordinates, dimensions = as.integer(dim(coordinates)),
        cell_id = cells, storage_profile = "space_dense_v1", meta = list()),
        class = "wb_primitive")
      display_record <- .wb_operation_pack_v2_input_descriptor("display_space",
        primitive, list(name = "display_space", kind = "space", required = TRUE,
          alignment = "cell_ordered"))$descriptor
      group_index <- length(grants) + 1L
      display_relative <- paste0("optional_display_axis_groups/", name, "/",
        group_index, "/display.rds")
      display_path <- file.path(stage_root, display_relative)
      dir.create(dirname(display_path), recursive = TRUE, showWarnings = FALSE)
      saveRDS(primitive, display_path, version = 3L, compress = FALSE)
      display <- list(space_id = space_id,
        space_descriptor_identity = .wb_operation_pack_v3_unscoped_identity(
          display_record$descriptor_identity),
        space_content_identity = .wb_operation_pack_v3_space_content(
          coordinates, cells),
        dimension_count = 2L, cell_count = as.integer(length(cells)),
        cell_order_identity = display_record$cell_order_identity,
        payload_manifest_identity =
          .wb_operation_pack_v3_phase5_payload_manifest(display_path,
            display_relative))
      display_identity <- .wb_operation_pack_v2_identity_plain(
        "scworkbench.operation_pack.optional_display_space.v1", display)
      endpoint_axes <- list(); endpoint_values <- list(); total <- 0L
      for (role in c("start", "end")) {
        selected <- selectors[[role]]
        if (is.null(selected)) next
        source_cells <- if (identical(selected$kind, "named_cell_set")) {
          tryCatch(as.character(wb_cells(bundle, cell_set = selected$name)),
            error = function(error) .wb_operation_pack_v3_error(
              "PYBENCH_INPUT_IDENTITY_MISMATCH",
              paste0("Unknown endpoint cell set: ", selected$name),
              "resolution"))
        } else selected$cells
        selector_identity <- .wb_operation_pack_v2_identity_plain(
          "scworkbench.operation_pack.parameter_selector.v1",
          c(selected$selector, list(value = unname(as.list(source_cells)))))
        resolved <- .wb_operation_pack_v3_named_axis(bundle, selected$name,
          role, selected$kind, source_cells, cells,
          display$space_descriptor_identity,
          if (identical(selected$kind, "literal_parameter_cells"))
            selector_identity else NULL)
        count <- length(resolved$axis$cell_id); total <- total + count
        if (count > as.integer(declaration$maximum_cells_per_endpoint_axis))
          .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
            "Endpoint axis exceeds its membership limit.", "resolution")
        ordinal <- length(endpoint_axes) + 1L
        relative <- paste0("optional_display_axis_groups/", name, "/",
          group_index, "/endpoint_", ordinal, ".json")
        path <- file.path(stage_root, relative)
        .wb_operation_pack_v3_atomic_canonical_json(resolved$axis, path)
        descriptor <- list(ordinal = as.integer(ordinal), role = role,
          name = selected$name, source_kind = selected$kind,
          source_identity = resolved$axis$source_identity,
          selection_identity = resolved$axis$selection_identity,
          cell_order_identity = resolved$axis$cell_order_identity,
          axis_identity = resolved$axis$axis_identity,
          payload_manifest_identity =
            .wb_operation_pack_v3_phase5_payload_manifest(path, relative))
        endpoint_axes[[ordinal]] <- descriptor
        endpoint_values[[ordinal]] <- resolved$axis
        sources[[paste(name, group$key, role, sep = "\034")]] <- list(
          selected = selected, source_cells = source_cells,
          display_cells = cells, display_identity = display_identity,
          space_descriptor_identity = display$space_descriptor_identity,
          parameter_selector_identity = if (identical(selected$kind,
            "literal_parameter_cells")) selector_identity else NULL,
          descriptor = descriptor)
      }
      if (total > as.integer(declaration$maximum_total_endpoint_memberships))
        .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
          "Endpoint axes exceed their aggregate membership limit.",
          "resolution")
      grant <- list(schema =
          "scworkbench.operation_pack.optional_display_axis_group_grant.v1",
        name = name, group_key = group$key, scope = scope,
        source_collection_item_identity = group$item_identity,
        display_space = display, endpoint_axes = endpoint_axes,
        limits = list(maximum_display_cells = as.integer(
          declaration$maximum_display_cells),
          maximum_cells_per_endpoint_axis = as.integer(
            declaration$maximum_cells_per_endpoint_axis),
          maximum_total_endpoint_memberships = as.integer(
            declaration$maximum_total_endpoint_memberships)),
        call_discipline =
          "display_partition_then_endpoint_ordinal_exactly_once")
      grant$grant_identity <- .wb_operation_pack_v2_identity_scoped(grant$schema,
        "grant excluding grant_identity", grant)
      key <- paste(name, group$key, sep = "\034")
      grants[[key]] <- grant; values[[key]] <- list(display = primitive,
        endpoints = endpoint_values)
    }
  }
  list(grants = grants, values = values, sources = sources)
}

.wb_operation_pack_v3_add_phase5_readers <- function(adapter, request) {
  state <- adapter$state
  artifact_grants <- stats::setNames(request$artifact_collection_grants %||%
    list(), vapply(request$artifact_collection_grants %||% list(), `[[`,
      character(1), "name"))
  artifact_values <- attr(request,
    "operation_pack_v3_artifact_collection_values") %||% list()
  state$artifact_collection_calls <- list()
  if (length(artifact_grants)) adapter$readers$
      read_retained_artifact_collection_item <- function(collection_name,
          resolved_ordinal, slot) {
    collection_name <- as.character(collection_name)[1]
    resolved_ordinal <- as.integer(resolved_ordinal)[1]
    slot <- as.character(slot)[1]
    grant <- artifact_grants[[collection_name]]
    calls <- state$artifact_collection_calls[[collection_name]] %||% list()
    expected <- do.call(c, lapply(grant$items, function(item) lapply(
      item$references, function(ref) list(ordinal = item$resolved_ordinal,
        slot = ref$slot, reference = ref))))
    next_ordinal <- length(calls) + 1L
    next_call <- if (next_ordinal <= length(expected))
      expected[[next_ordinal]] else NULL
    if (isTRUE(state$used) || is.null(next_call) ||
        !identical(resolved_ordinal, as.integer(next_call$ordinal)) ||
        !identical(slot, as.character(next_call$slot)[1]))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Artifact collection reads must follow resolved ordinal and slot order exactly once.",
        "execution")
    value <- artifact_values[[collection_name]][[resolved_ordinal]][[slot]]
    result <- list(grant_identity = .wb_operation_pack_v3_unscoped_identity(
        grant$grant_identity), resolved_ordinal = resolved_ordinal, slot = slot,
      reference_identity = next_call$reference$reference_identity,
      content_identity = next_call$reference$content_identity)
    result$result_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.retained_artifact_collection_result.v1",
      result)
    state$artifact_collection_calls[[collection_name]][[length(calls) + 1L]] <-
      list(result = result, reference = next_call$reference)
    .wb_operation_pack_v2_deep_copy(value)
  }

  axis_grants <- stats::setNames(request$named_cell_axis_collection_grants %||%
    list(), vapply(request$named_cell_axis_collection_grants %||% list(), `[[`,
      character(1), "name"))
  axis_values <- attr(request, "operation_pack_v3_named_axis_values") %||%
    list()
  state$named_axis_calls <- list()
  if (length(axis_grants)) adapter$readers$read_named_cell_axis <- function(
      collection_name, ordinal) {
    collection_name <- as.character(collection_name)[1]
    ordinal <- as.integer(ordinal)[1]
    grant <- axis_grants[[collection_name]]
    calls <- state$named_axis_calls[[collection_name]] %||% list()
    expected <- length(calls) + 1L
    if (isTRUE(state$used) || is.null(grant) || ordinal != expected ||
        ordinal > length(grant$axes))
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "Named-cell axes must be read in ordinal order exactly once.",
        "execution")
    axis <- axis_values[[collection_name]][[ordinal]]
    result <- list(grant_identity = .wb_operation_pack_v3_unscoped_identity(
        grant$grant_identity), ordinal = ordinal,
      axis_identity = grant$axes[[ordinal]]$axis_identity)
    result$result_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.named_cell_axis_result.v1", result)
    state$named_axis_calls[[collection_name]][[length(calls) + 1L]] <- result
    .wb_operation_pack_v2_deep_copy(axis)
  }

  display_grants <- request$optional_display_axis_group_grants %||% list()
  display_keys <- vapply(display_grants, function(x) paste(x$name,
    x$group_key, sep = "\034"), character(1))
  display_grants <- stats::setNames(display_grants, display_keys)
  display_values <- attr(request, "operation_pack_v3_optional_display_values") %||%
    list()
  state$optional_display_calls <- list(); state$optional_endpoint_calls <- list()
  if (length(display_grants)) {
    adapter$readers$read_optional_display_space <- function(group_name,
        group_key, cells) {
      key <- paste(as.character(group_name)[1], as.character(group_key)[1],
        sep = "\034")
      grant <- display_grants[[key]]; values <- display_values[[key]]$display
      prior <- state$optional_display_calls[[key]] %||% list()
      endpoint_prior <- state$optional_endpoint_calls[[key]] %||% list()
      cells <- as.character(cells)
      all_cells <- as.character(values$cell_id)
      consumed <- sum(vapply(prior, function(x) x$count, integer(1)))
      expected <- if (length(cells) && consumed + length(cells) <=
          length(all_cells)) all_cells[seq.int(consumed + 1L,
            consumed + length(cells))] else character()
      if (isTRUE(state$used) || is.null(grant) || length(endpoint_prior) ||
          !length(cells) ||
          !identical(cells, expected)) .wb_operation_pack_v3_error(
            "PYBENCH_CAPABILITY_MISMATCH",
            paste("Optional display reads must partition the cell axis in",
              "order before endpoint reads begin."),
            "execution")
      index <- match(cells, all_cells)
      value <- .wb_operation_pack_v2_deep_copy(values)
      value$values <- values$values[index, , drop = FALSE]
      value$cell_id <- cells; value$dimensions <- as.integer(dim(value$values))
      result <- .wb_operation_pack_v2_identity_plain(
        "scworkbench.operation_pack.optional_display_result.v1", list(
          grant_identity = .wb_operation_pack_v3_unscoped_identity(
            grant$grant_identity), ordinal = as.integer(length(prior) + 1L),
          cell_id = unname(as.list(cells)),
          content_identity = .wb_operation_pack_v3_space_content(
            value$values, cells)))
      state$optional_display_calls[[key]][[length(prior) + 1L]] <- list(
        identity = result, count = as.integer(length(cells)), cells = cells)
      value
    }
    adapter$readers$read_optional_endpoint_axis <- function(group_name,
        group_key, ordinal) {
      key <- paste(as.character(group_name)[1], as.character(group_key)[1],
        sep = "\034")
      grant <- display_grants[[key]]; prior <- state$optional_endpoint_calls[[key]] %||%
        list(); ordinal <- as.integer(ordinal)[1]
      display_prior <- state$optional_display_calls[[key]] %||% list()
      display_values_for_key <- display_values[[key]]$display
      display_consumed <- sum(vapply(display_prior,
        function(x) x$count, integer(1)))
      display_complete <- !is.null(display_values_for_key) &&
        display_consumed == length(as.character(
          display_values_for_key$cell_id))
      expected <- length(prior) + 1L
      if (isTRUE(state$used) || is.null(grant) || !display_complete ||
          ordinal != expected || ordinal > length(grant$endpoint_axes))
        .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
          paste("Optional endpoint axes require complete display coverage and",
            "must be read in role ordinal order exactly once."),
          "execution")
      value <- display_values[[key]]$endpoints[[ordinal]]
      result <- .wb_operation_pack_v2_identity_plain(
        "scworkbench.operation_pack.optional_endpoint_axis_result.v1", list(
          grant_identity = .wb_operation_pack_v3_unscoped_identity(
            grant$grant_identity), ordinal = ordinal,
          axis_identity = grant$endpoint_axes[[ordinal]]$axis_identity))
      state$optional_endpoint_calls[[key]][[length(prior) + 1L]] <- result
      .wb_operation_pack_v2_deep_copy(value)
    }
  }
  adapter
}

.wb_operation_pack_v3_phase5_usage <- function(adapter, request) {
  common <- function(grant) list(
    request_identity = .wb_operation_pack_v3_unscoped_identity(
      request$request_identity),
    capability_identity = .wb_operation_pack_v3_unscoped_identity(
      request$execution_capability$capability_identity),
    operation_definition_identity = .wb_operation_pack_v3_unscoped_identity(
      request$operation_authentication$operation_definition_identity),
    grant_identity = .wb_operation_pack_v3_unscoped_identity(
      grant$grant_identity))
  artifacts <- lapply(request$artifact_collection_grants %||% list(),
    function(grant) {
      calls <- adapter$state$artifact_collection_calls[[grant$name]] %||% list()
      expected <- sum(vapply(grant$items, function(x) length(x$references),
        integer(1)))
      if (length(calls) != expected) .wb_operation_pack_v3_error(
        "PYBENCH_RECEIPT_MISMATCH",
        "Artifact collection usage is incomplete.", "receipt")
      call_values <- lapply(calls, function(x) list(
        resolved_ordinal = x$result$resolved_ordinal, slot = x$result$slot,
        reference_identity = x$result$reference_identity,
        result_identity = x$result$result_identity))
      usage <- c(list(schema =
          "scworkbench.operation_pack.retained_artifact_collection_usage.v1"),
        common(grant), list(calls = call_values,
          call_count = as.integer(length(call_values)),
          concatenated_reference_order_identity =
            .wb_operation_pack_v2_identity_plain(
              "scworkbench.retained_artifact_reference_order.v1",
              lapply(call_values, `[[`, "reference_identity")),
          coverage_status = "exact"))
      usage$usage_identity <- .wb_operation_pack_v2_identity_scoped(
        usage$schema, "usage excluding usage_identity", usage)
      usage
    })
  axes <- lapply(request$named_cell_axis_collection_grants %||% list(),
    function(grant) {
      calls <- adapter$state$named_axis_calls[[grant$name]] %||% list()
      if (length(calls) != length(grant$axes)) .wb_operation_pack_v3_error(
        "PYBENCH_RECEIPT_MISMATCH", "Named-axis usage is incomplete.",
        "receipt")
      values <- lapply(calls, function(x) list(ordinal = x$ordinal,
        axis_identity = x$axis_identity, result_identity = x$result_identity))
      usage <- c(list(schema =
          "scworkbench.operation_pack.named_cell_axis_collection_usage.v1"),
        common(grant), list(calls = values,
          call_count = as.integer(length(values)),
          collection_order_identity = grant$collection_identity,
          coverage_status = "exact"))
      usage$usage_identity <- .wb_operation_pack_v2_identity_scoped(
        usage$schema, "usage excluding usage_identity", usage)
      usage
    })
  displays <- lapply(request$optional_display_axis_group_grants %||% list(),
    function(grant) {
      key <- paste(grant$name, grant$group_key, sep = "\034")
      display_calls <- adapter$state$optional_display_calls[[key]] %||% list()
      endpoint_calls <- adapter$state$optional_endpoint_calls[[key]] %||% list()
      selected <- unlist(lapply(display_calls, `[[`, "cells"),
        use.names = FALSE)
      values <- attr(request, "operation_pack_v3_optional_display_values")[[key]]
      if (!identical(selected, as.character(values$display$cell_id)) ||
          length(endpoint_calls) != length(grant$endpoint_axes))
        .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
          "Optional display/endpoint usage is incomplete.", "receipt")
      usage <- c(list(schema =
          "scworkbench.operation_pack.optional_display_axis_group_usage.v1"),
        common(grant), list(display_calls = lapply(display_calls, `[[`,
          "identity"), endpoint_calls = endpoint_calls,
          display_coverage_status = "exact",
          endpoint_coverage_status = "exact"))
      usage$usage_identity <- .wb_operation_pack_v2_identity_scoped(
        usage$schema, "usage excluding usage_identity", usage)
      usage
    })
  list(artifact_collection_usage = artifacts,
    named_cell_axis_collection_usage = axes,
    optional_display_axis_group_usage = displays)
}

.wb_operation_pack_v3_phase5_staged_payloads_assert <- function(request,
    phase = "staging") {
  root <- attr(request, "operation_pack_stage_root")
  fail <- function(message) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH", message, phase)
  assert_file <- function(relative, expected, reader = NULL,
      identity_field = NULL) {
    path <- file.path(root, relative)
    if (!file.exists(path) || !identical(
        .wb_operation_pack_v3_phase5_payload_manifest(path, relative),
        expected)) fail("A privately staged Phase 5 payload changed.")
    if (!is.null(reader)) {
      value <- tryCatch(reader(path), error = identity)
      if (inherits(value, "error")) fail(
        "A privately staged Phase 5 payload is unreadable.")
      if (!is.null(identity_field)) tryCatch(
        .wb_operation_pack_v3_assert_self_identity(value, identity_field,
          "PYBENCH_INPUT_IDENTITY_MISMATCH", phase),
        error = function(error) stop(error))
    }
    invisible(TRUE)
  }
  for (grant in request$artifact_collection_grants %||% list())
    for (item in grant$items) for (reference in item$references) {
      base <- paste0("artifact_collection_reads/", grant$name, "/",
        item$resolved_ordinal, "/", reference$slot, "/")
      assert_file(paste0(base, "payload.rds"),
        reference$payload_manifest_identity, readRDS)
      ancestry <- tryCatch(jsonlite::read_json(file.path(root, paste0(base,
        "ancestry.json")), simplifyVector = FALSE), error = identity)
      if (inherits(ancestry, "error")) fail(
        "A privately staged artifact ancestry snapshot is unreadable.")
      .wb_operation_pack_v3_assert_self_identity(ancestry,
        "snapshot_identity", "PYBENCH_INPUT_IDENTITY_MISMATCH", phase)
      if (!identical(.wb_operation_pack_v3_unscoped_identity(
          ancestry$snapshot_identity), reference$ancestry_identity)) fail(
        "A privately staged artifact ancestry snapshot changed.")
    }
  json <- function(path) jsonlite::read_json(path, simplifyVector = FALSE)
  for (grant in request$named_cell_axis_collection_grants %||% list())
    for (axis in grant$axes) assert_file(paste0("named_cell_axis_reads/",
      grant$name, "/", axis$ordinal, "/payload.json"),
      axis$payload_manifest_identity, json, "axis_identity")
  for (i in seq_along(request$optional_display_axis_group_grants %||%
      list())) {
    grant <- request$optional_display_axis_group_grants[[i]]
    base <- paste0("optional_display_axis_groups/", grant$name, "/", i,
      "/")
    assert_file(paste0(base, "display.rds"),
      grant$display_space$payload_manifest_identity, readRDS)
    for (axis in grant$endpoint_axes) assert_file(paste0(base, "endpoint_",
      axis$ordinal, ".json"), axis$payload_manifest_identity, json,
      "axis_identity")
  }
  invisible(TRUE)
}

.wb_operation_pack_v3_phase5_sources_assert_current <- function(bundle,
    operation, request, params) {
  .wb_operation_pack_v3_dfa_parent_current(bundle, request, phase = "audit")
  .wb_operation_pack_v3_phase5_staged_payloads_assert(request,
    phase = "audit")
  stage <- attr(request, "operation_pack_stage_root")
  for (grant in request$self_linked_model_payload_grants %||% list()) {
    .wb_operation_pack_v3_validate_model_read(stage, grant)
    linkage <- grant$model_source_linkage
    if (identical(as.character(linkage$schema %||% "")[1],
        "scworkbench.operation_pack.model_source_linkage.v3")) {
      .wb_operation_pack_v3_dfa_reopen(bundle, list(), linkage,
        file.path(stage, grant$relative_root), phase = "audit")
      next
    }
    values <- tryCatch(wb_space(bundle, linkage$source_space_id),
      error = identity)
    if (inherits(values, "error")) .wb_operation_pack_v3_error(
      "PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Self-linked model source space disappeared before publication.",
      "audit")
    primitive <- structure(list(kind = "space",
      space_id = linkage$source_space_id, values = as.matrix(values),
      dimensions = as.integer(dim(values)), cell_id = rownames(values),
      storage_profile = "space_dense_v1",
      meta = structure(list(), names = character())),
      class = "wb_primitive")
    durable_content <- .wb_operation_pack_v3_phase5_primitive_identity(
      bundle, primitive)
    cells <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", unname(as.list(rownames(values))))
    if (!identical(as.character(
        linkage$source_space_content_identity$scheme)[1],
          "scworkbench.space.content.v1") ||
        !identical(cells, linkage$fitted_cell_order_identity) ||
        !identical(as.character(durable_content$sha256)[1],
          as.character(linkage$source_snapshot_id)[1]))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Self-linked model source linkage changed before publication.",
        "audit", expected_content = linkage$source_space_content_identity,
        expected_snapshot = linkage$source_snapshot_id,
        observed_snapshot = durable_content$sha256)
  }
  artifact_sources <- attr(request,
    "operation_pack_v3_artifact_collection_sources") %||% list()
  for (source in artifact_sources) {
    ref <- source$reference
    primitive <- tryCatch(wb_art_load(bundle, ref$artifact_id),
      error = identity)
    if (inherits(primitive, "error")) .wb_operation_pack_v3_error(
      "PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Artifact collection source disappeared before publication.", "audit")
    input_record <- .wb_operation_pack_v2_input_descriptor(ref$slot,
      primitive, list(name = ref$slot, kind = primitive$kind,
        required = TRUE, alignment = "none"))$descriptor
    ancestry <- .wb_operation_pack_v3_artifact_ancestry(bundle,
      source$ancestry_declaration, input_record, ref$artifact_id)
    lifecycle_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.artifact.lifecycle.v1", ancestry$lifecycle)
    if (!identical(input_record$content_identity, ref$content_identity) ||
        !identical(lifecycle_identity, ref$lifecycle_identity) ||
        !identical(.wb_operation_pack_v3_unscoped_identity(
          ancestry$snapshot_identity), ref$ancestry_identity))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Artifact collection lifecycle, content, or ancestry changed before publication.",
        "audit")
  }
  axis_sources <- attr(request, "operation_pack_v3_named_axis_sources") %||%
    list()
  input_map <- stats::setNames(lapply(request$inputs, `[[`, "descriptor"),
    vapply(request$inputs, `[[`, character(1), "name"))
  for (source in axis_sources) {
    cells <- tryCatch(as.character(wb_cells(bundle, cell_set = source$name)),
      error = identity)
    space_cells <- tryCatch(rownames(wb_space(bundle, source$space_id)),
      error = identity)
    if (inherits(cells, "error") || inherits(space_cells, "error"))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Named-axis source disappeared before publication.", "audit")
    observed <- .wb_operation_pack_v3_named_axis(bundle, source$name,
      "checkpoint", "named_cell_set", cells, space_cells,
      source$space_descriptor_identity)
    if (!identical(observed$axis$axis_identity,
        source$descriptor$axis_identity)) .wb_operation_pack_v3_error(
          "PYBENCH_INPUT_IDENTITY_MISMATCH",
          "Named-axis membership or selected space changed before publication.",
          "audit")
  }
  display_values <- attr(request,
    "operation_pack_v3_optional_display_values") %||% list()
  for (key in names(display_values)) {
    grant <- request$optional_display_axis_group_grants[[match(key, vapply(
      request$optional_display_axis_group_grants, function(x) paste(x$name,
        x$group_key, sep = "\034"), character(1)))]]
    current <- tryCatch(.wb_as_coord_matrix(wb_space(bundle,
      grant$display_space$space_id)), error = identity)
    if (inherits(current, "error") || !identical(rownames(current),
        as.character(display_values[[key]]$display$cell_id)) ||
        !identical(.wb_operation_pack_v3_space_content(current,
          rownames(current)), grant$display_space$space_content_identity))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Optional display space changed before publication.", "audit")
  }
  endpoint_sources <- attr(request,
    "operation_pack_v3_optional_display_sources") %||% list()
  for (source in endpoint_sources) {
    cells <- if (identical(source$selected$kind, "named_cell_set"))
      tryCatch(as.character(wb_cells(bundle,
        cell_set = source$selected$name)), error = identity) else
          source$source_cells
    if (inherits(cells, "error")) .wb_operation_pack_v3_error(
      "PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Endpoint named set disappeared before publication.", "audit")
    observed <- .wb_operation_pack_v3_named_axis(bundle,
      source$selected$name, source$descriptor$role, source$selected$kind,
      cells, source$display_cells,
      source$space_descriptor_identity,
      source$parameter_selector_identity)
    # The complete axis identity is the authoritative comparison; it binds
    # source membership, projection and returned order.
    if (!identical(observed$axis$axis_identity,
        source$descriptor$axis_identity)) .wb_operation_pack_v3_error(
          "PYBENCH_INPUT_IDENTITY_MISMATCH",
          "Endpoint axis membership changed before publication.", "audit")
  }
  invisible(TRUE)
}

.wb_operation_pack_v3_phase5_receipt_audit <- function(receipt, request) {
  audit_usage <- function(observed, grants, label) {
    if (length(observed) != length(grants)) .wb_operation_pack_v3_error(
      "PYBENCH_RECEIPT_MISMATCH", paste0(label,
        " usage is not a bijection with grants."), "receipt")
    for (i in seq_along(observed)) {
      .wb_operation_pack_v3_assert_self_identity(observed[[i]],
        "usage_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
      if (!identical(observed[[i]]$grant_identity,
          .wb_operation_pack_v3_unscoped_identity(
            grants[[i]]$grant_identity))) .wb_operation_pack_v3_error(
              "PYBENCH_RECEIPT_MISMATCH",
              paste0(label, " usage differs from its grant."), "receipt")
    }
  }
  audit_usage(receipt$artifact_collection_usage %||% list(),
    request$artifact_collection_grants %||% list(), "Artifact collection")
  audit_usage(receipt$named_cell_axis_collection_usage %||% list(),
    request$named_cell_axis_collection_grants %||% list(), "Named-axis")
  audit_usage(receipt$optional_display_axis_group_usage %||% list(),
    request$optional_display_axis_group_grants %||% list(),
    "Optional display/endpoint")
  self_grants <- request$self_linked_model_payload_grants %||% list()
  self_reads <- receipt$self_linked_model_payload_reads %||% list()
  if (length(self_grants) != length(self_reads))
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "Self-linked model observations are not a bijection with grants.",
      "receipt")
  for (i in seq_along(self_reads)) {
    .wb_operation_pack_v3_assert_self_identity(self_reads[[i]],
      "observation_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
    if (!identical(self_reads[[i]]$grant_identity,
        self_grants[[i]]$grant_identity) ||
        !identical(self_reads[[i]]$model_source_linkage_identity,
          self_grants[[i]]$model_source_linkage_identity) ||
        !identical(as.integer(self_reads[[i]]$use_count), 1L) ||
        !identical(self_reads[[i]]$integrity_status, "unchanged"))
      .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
        "Self-linked model observation differs from its grant.", "receipt")
  }
  invisible(TRUE)
}
