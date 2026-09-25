# Operation-pack ABI v3: consolidated bounded-output, typed-slice, and
# core-attested ancestry contracts. ABI v1/v2 readers remain frozen.

.wb_operation_pack_v3_manifest_schema <- function() {
  path <- system.file("protocol", "operation-pack-v3.schema.json",
    package = "scworkbench")
  if (!nzchar(path)) path <- file.path("inst", "protocol",
    "operation-pack-v3.schema.json")
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

.wb_operation_pack_v3_transition_schema <- function(kind = c("request", "receipt")) {
  kind <- match.arg(kind)
  path <- system.file("protocol", paste0("operation-pack-transition-", kind,
    "-v3.schema.json"), package = "scworkbench")
  if (!nzchar(path)) path <- file.path("inst", "protocol",
    paste0("operation-pack-transition-", kind, "-v3.schema.json"))
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

.wb_operation_pack_v3_error <- function(code, message, phase, ...) {
  .wb_operation_pack_abort(code, message, phase = phase, ...,
    class = "wb_operation_pack_v3_error")
}

.wb_operation_pack_v3_read_manifest <- function(path) {
  path <- normalizePath(.wb_operation_pack_scalar(path, "manifest"),
    winslash = "/", mustWork = TRUE)
  text <- readChar(path, nchars = file.info(path)$size, useBytes = TRUE)
  .wb_operation_pack_v2_assert_strict_json(text)
  parsed <- tryCatch(.wb_operation_pack_parse_canonical_json(text),
    error = identity)
  if (inherits(parsed, "error")) .wb_operation_pack_v3_error(
    "OPERATION_PACK_MANIFEST_PARSE_INVALID", conditionMessage(parsed), "parse")
  attr(parsed, "operation_pack_v3_source_path") <- path
  attr(parsed, "operation_pack_v3_source_sha256") <-
    .wb_operation_pack_v2_file_sha256(path)
  parsed
}

.wb_operation_pack_v3_id <- function(scheme, value, scope = NULL) {
  .wb_operation_pack_v2_id(scheme, value, scope)
}

.wb_operation_pack_v3_assert_self_identity <- function(value, field,
                                                         code, phase) {
  identity <- value[[field]] %||% list()
  preimage <- value
  preimage[[field]] <- NULL
  .wb_operation_pack_assert(
    identical(as.character(identity$sha256 %||% "")[1],
      .wb_operation_pack_sha256(preimage)), code,
    paste0("ABI v3 self-identity differs at ", field, "."),
    phase = phase, class = "wb_operation_pack_v3_error")
  invisible(TRUE)
}

.wb_operation_pack_v3_v2_projection <- function(manifest) {
  out <- .wb_operation_pack_v2_deep_copy(manifest)
  out$schema_version <- "scworkbench.operation_pack.v2"
  out$pack_abi_version <- "2"
  out$compatibility$pack_abi$minimum <- "2"
  out$compatibility$pack_abi$maximum <- "2"
  if (!is.null(out$compatibility$process_protocol)) {
    out$compatibility$process_protocol$minimum <- "pybench-op-v3"
    out$compatibility$process_protocol$maximum <- "pybench-op-v3"
  }
  out$operations <- lapply(out$operations, function(op) {
    g3_inputs <- vapply(Filter(function(x) identical(
      as.character(x$kind %||% "")[1], "external_state_candidate"),
      op$inputs), function(x) as.character(x$name)[1], character(1))
    op$inputs <- Filter(function(x) !as.character(x$name)[1] %in% g3_inputs,
      op$inputs)
    op$supported_external_state_adoptions <- NULL
    op$derived_cell_output_axes <- NULL
    selector_parameters <- vapply(op$cell_selector_axes %||% list(),
      function(x) as.character(x$parameter)[1], character(1))
    for (parameter in selector_parameters) {
      types <- as.character(unlist(op$params_schema$properties[[parameter]]$
        type, use.names = FALSE))
      op$params_schema$properties[[parameter]]$type <- unname(as.list(
        setdiff(types, "string")))
    }
    op$provenance_reads <- NULL
    op$typed_slice_reads <- NULL
    op$typed_space_reads <- NULL
    op$cell_selector_axes <- NULL
    op$contained_model_reads <- NULL
    op$self_linked_contained_model_reads <- NULL
    op$artifact_collection_reads <- NULL
    op$named_cell_axis_collections <- NULL
    op$optional_display_axis_groups <- NULL
    op$publication_policies <- NULL
    op$parameter_axes <- NULL
    op$parameter_bindings <- Filter(function(binding)
      !as.character(binding$policy %||% "")[1] %in% c(
        "input_id_with_numeric_suffix_v1",
        "feature_ids_from_table_or_matrix_v1",
        "input_id_with_literal_affix_v1", "model_space_id_v1"),
      op$parameter_bindings %||% list())
    if (!length(op$parameter_bindings)) op$parameter_bindings <- NULL
    op$retained_parameters <- Filter(function(item) !identical(
      as.character(item$source %||% "")[1], "effective_parameter_value"),
      op$retained_parameters %||% list())
    if (!length(op$retained_parameters)) op$retained_parameters <- NULL
    op$outputs <- lapply(op$outputs, function(output) {
      output$fragment_policy <- NULL
      output$contained_model_policy <- NULL
      output$contained_model_sibling_closure_policy <- NULL
      output$derived_fitted_axis_policy <- NULL
      output
    })
    op$registry_reads <- Filter(function(x) identical(
      as.character(x$kind %||% "")[1], "feature_set_registry"),
      op$registry_reads %||% list())
    if (!length(op$registry_reads)) op$registry_reads <- NULL
    op$dimension_policies <- Filter(function(x) !as.character(
      x$policy %||% "")[1] %in% c("authenticated_output_axes_v1",
        "data_dependent_family_v1",
        "standalone_sparse_cell_family_v1",
        "authenticated_sparse_membership_v1",
        "authenticated_pseudobulk_v1",
        "cell_by_parameter_axis_v1",
        "feature_parameter_axis_cartesian_v1",
        "one_per_parameter_axis_v1", "singleton_parameter_echo_v1"),
      op$dimension_policies %||% list())
    if (!length(op$dimension_policies)) op$dimension_policies <- NULL
    op
  })
  out
}

.wb_operation_pack_v3_param_is <- function(properties, name, type,
                                             nullable = FALSE) {
  schema <- properties[[as.character(name %||% "")[1]]]
  if (is.null(schema)) return(FALSE)
  types <- as.character(unlist(schema$type %||% character(),
    use.names = FALSE))
  type %in% types && (!nullable || "null" %in% types)
}

.wb_operation_pack_v3_semantic_validate <- function(manifest) {
  # Reuse the accepted v2 admission rules for unchanged fields, after removing
  # only the explicit v3 additions. This does not reinterpret a v2 document.
  projected <- .wb_operation_pack_v3_v2_projection(manifest)
  .wb_operation_pack_v2_outer_validate(projected)
  .wb_operation_pack_v2_semantic_validate(projected)

  for (operation in manifest$operations) {
    opname <- as.character(operation$qualified_name)[1]
    inputs <- stats::setNames(operation$inputs,
      vapply(operation$inputs, `[[`, character(1), "name"))
    outputs <- stats::setNames(operation$outputs,
      vapply(operation$outputs, `[[`, character(1), "name"))
    properties <- operation$params_schema$properties %||% list()
    registry_reads <- stats::setNames(operation$registry_reads %||% list(),
      vapply(operation$registry_reads %||% list(), function(x)
        as.character(x$name)[1], character(1)))
    policies <- operation$dimension_policies %||% list()
    policy_names <- vapply(policies, function(x) as.character(x$output)[1],
      character(1))
    if (anyDuplicated(policy_names)) .wb_operation_pack_v3_error(
      "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
      paste0("Operation '", opname, "' repeats a dimension-policy output."),
      "semantic_admission")
    for (policy in policies) {
      if (identical(as.character(policy$policy)[1],
          "data_dependent_family_v1")) {
        output <- outputs[[as.character(policy$output)[1]]]
        if (is.null(output) || !as.character(output$kind)[1] %in%
            c("path_2d_family", "space_path_family"))
          .wb_operation_pack_v3_error(
            "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
            paste0("Operation '", opname,
              "' has an invalid data-dependent family declaration."),
            "semantic_admission")
        next
      }
      if (as.character(policy$policy)[1] %in% c(
          "cell_by_parameter_axis_v1",
          "feature_parameter_axis_cartesian_v1",
          "one_per_parameter_axis_v1", "singleton_parameter_echo_v1")) {
        output <- outputs[[as.character(policy$output)[1]]]
        axes <- stats::setNames(operation$parameter_axes %||% list(),
          vapply(operation$parameter_axes %||% list(), function(x)
            as.character(x$name)[1], character(1)))
        axis_name <- as.character(policy$dimension_axis %||%
          policy$parameter_axis %||% "")[1]
        axis <- axes[[axis_name]]
        expected_kind <- switch(as.character(policy$policy)[1],
          cell_by_parameter_axis_v1 = "space",
          feature_parameter_axis_cartesian_v1 = "feature_table",
          "obs_table")
        if (is.null(output) || is.null(axis) ||
            !identical(as.character(output$kind)[1], expected_kind))
          .wb_operation_pack_v3_error(
            "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
            paste0("Operation '", opname,
              "' has an invalid parameter-bound output declaration."),
            "semantic_admission")
        next
      }
      if (!identical(as.character(policy$policy)[1],
          "authenticated_output_axes_v1")) next
      output <- outputs[[as.character(policy$output)[1]]]
      cell_source <- as.character(policy$cell_axis$source)[1]
      input <- inputs[[as.character(policy$cell_axis$input %||% "")[1]]]
      axis_read <- registry_reads[[as.character(
        policy$cell_axis$registry_read %||% "")[1]]]
      shape <- as.character(policy$shape)[1]
      cell_source_valid <- (!is.null(input) && cell_source %in% c(
        "effective_cells_v1", "distinct_input_cells_first_occurrence_v1") &&
        as.character(input$kind)[1] %in% c("matrix", "cell_vector_family", "space")) ||
        (identical(cell_source, "session_cell_axis_read_v1") &&
          identical(as.character(axis_read$kind %||% "")[1],
            "session_cell_axis"))
      valid <- !is.null(output) && cell_source_valid &&
        ((shape %in% c("cell_key_cartesian",
            "bounded_grouped_cell_key_cartesian") &&
          identical(as.character(output$kind)[1], "cell_vector_family") &&
          identical(as.character(policy$row_order)[1],
            "key_major_then_cell_v1") && !is.null(policy$key_axis)) ||
         (identical(shape, "one_per_cell") &&
          identical(as.character(output$kind)[1], "cell_vector") &&
          identical(as.character(policy$row_order)[1],
            if (identical(cell_source, "session_cell_axis_read_v1"))
              "session_cell_axis_order_v1" else "input_cell_order_v1") &&
          is.null(policy$key_axis)))
      if (!valid) .wb_operation_pack_v3_error(
        "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
        paste0("Operation '", opname,
          "' has an incompatible authenticated output-axis declaration."),
        "semantic_admission")
      if (shape %in% c("cell_key_cartesian",
          "bounded_grouped_cell_key_cartesian")) {
        key_axis <- policy$key_axis
        source <- as.character(key_axis$source %||% "")[1]
        if (identical(source, "resolved_parameter_feature_groups_v1")) {
          valid <- !is.null(inputs[[as.character(key_axis$matrix_input)[1]]]) &&
            identical(as.character(inputs[[as.character(key_axis$matrix_input)[1]]]$kind)[1],
              "matrix") && !is.null(properties[[as.character(
                key_axis$groups_parameter)[1]]]) &&
            .wb_operation_pack_v3_param_is(properties,
              key_axis$name_prefix_parameter, "string")
          missing <- key_axis$missing_feature_policy
          if (identical(as.character(missing$source)[1], "parameter_v1")) {
            valid <- valid && !is.null(properties[[as.character(missing$parameter)[1]]])
          }
        } else if (identical(source,
            "input_keys_with_optional_selector_v1")) {
          bound <- inputs[[as.character(key_axis$input)[1]]]
          selector <- as.character(key_axis$selector_parameter %||% "")[1]
          valid <- !is.null(bound) && identical(as.character(bound$kind)[1],
            "cell_vector_family") && (!nzchar(selector) ||
            !is.null(properties[[selector]]))
        } else if (identical(source,
            "declared_keys_with_optional_prefix_v1")) {
          keys <- as.character(unlist(key_axis$keys, use.names = FALSE))
          prefix <- as.character(key_axis$prefix_parameter)[1]
          valid <- length(keys) > 0L && !anyNA(keys) && all(nzchar(keys)) &&
            !anyDuplicated(keys) && !is.null(properties[[prefix]]) &&
            .wb_operation_pack_v3_param_is(properties, prefix, "string",
              nullable = TRUE)
        } else if (identical(source, "declared_bounded_key_groups_v1")) {
          required <- as.character(unlist(key_axis$required_keys,
            use.names = FALSE))
          groups <- key_axis$optional_groups %||% list()
          group_names <- vapply(groups, function(x) as.character(x$name)[1],
            character(1))
          group_keys <- unlist(lapply(groups, function(x)
            as.character(unlist(x$keys, use.names = FALSE))), use.names = FALSE)
          all_keys <- c(required, group_keys)
          valid <- length(required) > 0L && !anyNA(all_keys) &&
            all(nzchar(all_keys)) && !anyDuplicated(all_keys) &&
            !anyDuplicated(group_names) && all(nzchar(group_names))
        } else valid <- FALSE
        valid <- valid && identical(shape,
          "bounded_grouped_cell_key_cartesian") == identical(source,
            "declared_bounded_key_groups_v1")
        if (!valid) .wb_operation_pack_v3_error(
          "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
          paste0("Operation '", opname,
            "' has an incompatible authenticated key-axis resolver."),
          "semantic_admission")
      }
    }

    publication <- operation$publication_policies %||% list()
    publication_names <- vapply(publication, function(x)
      as.character(x$output)[1], character(1))
    if (anyDuplicated(publication_names)) .wb_operation_pack_v3_error(
      "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
      paste0("Operation '", opname,
        "' repeats a publication-policy output."), "semantic_admission")
    for (item in publication) {
      output <- outputs[[as.character(item$output)[1]]]
      target <- properties[[as.character(item$target_id_parameter)[1]]]
      policy_name <- as.character(item$policy)[1]
      if (identical(policy_name,
          "authenticated_space_2d_publication_v1")) {
        axis <- inputs[[as.character(item$cell_axis_input)[1]]]
        binding <- item$model_binding
        model <- if (identical(as.character(binding$source)[1], "input"))
          inputs[[as.character(binding$name)[1]]] else
          outputs[[as.character(binding$name)[1]]]
        overwrite_name <- as.character(item$mode$overwrite_parameter %||%
          "")[1]
        overwrite_valid <- !nzchar(overwrite_name) ||
          .wb_operation_pack_v3_param_is(properties, overwrite_name,
            "boolean")
        model_valid <- !is.null(model) && identical(as.character(
          model$kind)[1], "model_ref")
        binding_source <- as.character(binding$source)[1]
        mode_policy <- as.character(item$mode$policy)[1]
        mode_binding_valid <- if (identical(mode_policy, "add_only_v1")) {
          identical(binding_source, "sibling_output") &&
            !is.null(model$contained_model_policy)
        } else if (identical(mode_policy,
            "selected_merge_or_full_replace_v1")) {
          identical(binding_source, "input")
        } else FALSE
        same_group <- identical(as.character(binding$source)[1], "input") ||
          (!is.null(output) && !is.null(model) &&
            identical(as.character(output$promotion_group)[1],
              as.character(model$promotion_group)[1]))
        if (is.null(output) || !identical(as.character(output$category)[1],
            "materialization") || !identical(as.character(output$kind)[1],
            "space_2d") || !identical(as.character(item$target_kind)[1],
            "space_2d") || !.wb_operation_pack_v3_param_is(properties,
              item$target_id_parameter, "string") || is.null(axis) ||
            !as.character(axis$kind)[1] %in% c("space", "space_2d") ||
            !model_valid || !same_group || !overwrite_valid ||
            !mode_binding_valid)
          .wb_operation_pack_v3_error(
            "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
            paste0("Operation '", opname,
              "' has an invalid authenticated space_2d publication declaration."),
            "semantic_admission")
        next
      }
      overwrite <- properties[[as.character(item$overwrite_parameter)[1]]]
      if (is.null(output) || !identical(as.character(output$category)[1],
          "materialization") || !identical(as.character(output$kind)[1],
          as.character(item$target_kind)[1]) ||
          !.wb_operation_pack_v3_param_is(properties,
            item$target_id_parameter, "string") ||
          !.wb_operation_pack_v3_param_is(properties,
            item$overwrite_parameter, "boolean"))
        .wb_operation_pack_v3_error(
          "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
          paste0("Operation '", opname,
            "' has an invalid add/replace publication declaration."),
          "semantic_admission")
    }

    model_outputs <- Filter(function(x) !is.null(x$contained_model_policy),
      operation$outputs)
    for (output in model_outputs) {
      policy <- output$contained_model_policy
      source <- inputs[[as.character(policy$source_space_input)[1]]]
      paired <- outputs[[as.character(policy$paired_space_output)[1]]]
      if (!identical(as.character(output$kind)[1], "model_ref") ||
          is.null(source) || !identical(as.character(source$kind)[1],
            "space") || is.null(paired) || !identical(as.character(
              paired$kind)[1], "space_2d") || !identical(as.character(
              paired$category)[1], "materialization") ||
          !identical(as.character(output$promotion_group)[1],
            as.character(paired$promotion_group)[1]) ||
          is.null(properties[[as.character(policy$dimensions_parameter)[1]]]))
        .wb_operation_pack_v3_error(
          "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
          paste0("Operation '", opname,
            "' has an invalid contained-model output declaration."),
          "semantic_admission")
    }
    model_reads <- operation$contained_model_reads %||% list()
    read_names <- vapply(model_reads, function(x) as.character(x$name)[1],
      character(1))
    if (anyDuplicated(read_names)) .wb_operation_pack_v3_error(
      "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
      paste0("Operation '", opname,
        "' repeats a contained-model read name."), "semantic_admission")
    for (read in model_reads) {
      model <- inputs[[as.character(read$input)[1]]]
      source <- inputs[[as.character(read$source_space_input)[1]]]
      if (is.null(model) || !identical(as.character(model$kind)[1],
          "model_ref") || is.null(source) || !identical(as.character(
            source$kind)[1], "space") ||
          is.null(properties[[as.character(read$dimensions_parameter)[1]]]))
        .wb_operation_pack_v3_error(
          "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
          paste0("Operation '", opname,
            "' has an invalid contained-model read declaration."),
          "semantic_admission")
    }
    if (length(operation$supported_external_state_adoptions %||% list()) &&
        !identical(as.character(manifest$backend)[1], "R"))
      .wb_operation_pack_v3_error(
        "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
        paste0("Operation '", opname,
          "' uses the R-runtime-only external-state adoption capability."),
        "semantic_admission")
    .wb_operation_pack_v3_phase5_semantic_validate(operation, inputs,
      outputs, properties)
    .wb_operation_pack_v3_dfa_semantic_validate(operation, inputs,
      outputs, manifest$backend)
    .wb_operation_pack_v3_g7_semantic_validate(operation, inputs, outputs,
      properties, manifest$backend)
    .wb_operation_pack_v3_sscf_semantic_validate(operation, inputs, outputs,
      manifest$backend)
    axes <- operation$parameter_axes %||% list()
    axis_names <- vapply(axes, function(x) as.character(x$name)[1],
      character(1))
    if (anyDuplicated(axis_names)) .wb_operation_pack_v3_error(
      "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
      paste0("Operation '", opname, "' repeats a parameter axis."),
      "semantic_admission")
    slice_names <- vapply(operation$typed_slice_reads %||% list(),
      function(x) as.character(x$name)[1], character(1))
    for (axis in axes) {
      maximum <- axis$maximum
      if (!.wb_operation_pack_v3_param_is(properties, axis$parameter,
          "integer") || !as.character(maximum$typed_slice_read)[1] %in%
          slice_names)
        .wb_operation_pack_v3_error(
          "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
          paste0("Operation '", opname,
            "' has an invalid parameter-axis declaration."),
          "semantic_admission")
    }
    for (binding in Filter(function(x) identical(as.character(
        x$policy %||% "")[1], "input_id_with_numeric_suffix_v1"),
        operation$parameter_bindings %||% list())) {
      input <- inputs[[as.character(binding$input)[1]]]
      if (is.null(input) || !as.character(input$kind)[1] %in%
          c("matrix", "space") ||
          !.wb_operation_pack_v3_param_is(properties, binding$parameter,
            "string", nullable = TRUE) ||
          !.wb_operation_pack_v3_param_is(properties,
            binding$numeric_parameter, "number"))
        .wb_operation_pack_v3_error(
          "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
          paste0("Operation '", opname,
            "' has an invalid derived target identifier binding."),
          "semantic_admission")
    }
    for (binding in Filter(function(x) identical(as.character(
        x$policy %||% "")[1], "feature_ids_from_table_or_matrix_v1"),
        operation$parameter_bindings %||% list())) {
      input <- inputs[[as.character(binding$input)[1]]]
      table_input <- inputs[[as.character(binding$table_input)[1]]]
      if (is.null(input) || !identical(as.character(input$kind)[1],
          "matrix") || is.null(table_input) ||
          !identical(as.character(table_input$kind)[1], "feature_table") ||
          !.wb_operation_pack_v3_param_is(properties, binding$parameter,
            "array", nullable = TRUE))
        .wb_operation_pack_v3_error(
          "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
          paste0("Operation '", opname,
            "' has an invalid feature-axis binding."),
          "semantic_admission")
    }
    for (binding in Filter(function(x) as.character(
        x$policy %||% "")[1] %in% c("input_id_with_literal_affix_v1",
          "model_space_id_v1"), operation$parameter_bindings %||% list())) {
      input <- inputs[[as.character(binding$input)[1]]]
      policy <- as.character(binding$policy)[1]
      expected_kind <- if (identical(policy, "model_space_id_v1"))
        "model_ref" else "space"
      if (is.null(input) || !identical(as.character(input$kind)[1],
          expected_kind) || !.wb_operation_pack_v3_param_is(properties,
            binding$parameter, "string", nullable = TRUE))
        .wb_operation_pack_v3_error(
          "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
          paste0("Operation '", opname,
            "' has an invalid derived identifier binding."),
          "semantic_admission")
    }

    new_reads <- .wb_operation_pack_v3_new_registry_declarations(operation)
    new_names <- vapply(new_reads, function(x) as.character(x$name)[1],
      character(1))
    if (anyDuplicated(new_names)) .wb_operation_pack_v3_error(
      "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
      paste0("Operation '", opname,
        "' repeats an authenticated core snapshot name."),
      "semantic_admission")
    for (read in new_reads) {
      kind <- as.character(read$kind)[1]
      valid <- if (identical(kind, "session_cell_axis")) {
        identical(as.character(read$reader)[1], "read_session_cell_axis")
      } else {
        input <- inputs[[as.character(read$matrix_input)[1]]]
        identical(as.character(read$reader)[1],
          "read_matrix_feature_annotations") && !is.null(input) &&
          identical(as.character(input$kind)[1], "matrix")
      }
      if (!valid) .wb_operation_pack_v3_error(
        "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
        paste0("Operation '", opname,
          "' has an invalid authenticated core snapshot declaration."),
        "semantic_admission")
    }

    slices <- operation$typed_slice_reads %||% list()
    slice_names <- vapply(slices, function(x) as.character(x$name)[1],
      character(1))
    if (anyDuplicated(slice_names) || length(intersect(slice_names,
        names(inputs)))) .wb_operation_pack_v3_error(
      "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
      paste0("Operation '", opname,
        "' has duplicate or colliding typed-slice capability names."),
      "semantic_admission")
    for (slice in slices) {
      input <- inputs[[as.character(slice$input)[1]]]
      parameter <- as.character(slice$chunk_size_parameter)[1]
      axes <- as.character(unlist(slice$supported_axes, use.names = FALSE))
      selections <- slice$selection
      parameter_selectors <- vapply(selections, function(x)
        identical(as.character(x$policy)[1],
          "parameter_ordered_subset_v1"), logical(1))
      selector_names <- vapply(selections[parameter_selectors], function(x)
        as.character(x$parameter)[1], character(1))
      valid <- !is.null(input) && identical(as.character(input$kind)[1],
        "matrix") && .wb_operation_pack_v3_param_is(properties, parameter,
          "integer") && as.character(slice$chunk_axis)[1] %in% axes &&
        all(selector_names %in% names(properties))
      if (!valid) .wb_operation_pack_v3_error(
        "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
        paste0("Operation '", opname,
          "' has an incompatible typed-slice reader declaration."),
        "semantic_admission")
    }

    selectors <- operation$cell_selector_axes %||% list()
    selector_parameters <- vapply(selectors, function(x)
      as.character(x$parameter)[1], character(1))
    selector_roles <- vapply(selectors, function(x)
      as.character(x$role)[1], character(1))
    if (length(selectors) && (anyDuplicated(selector_parameters) ||
        !setequal(selector_roles, c("query", "candidate")) ||
        !all(selector_parameters %in% names(properties))))
      .wb_operation_pack_v3_error(
        "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
        paste0("Operation '", opname,
          "' has invalid generic cell-selector axes."),
        "semantic_admission")
    space_reads <- operation$typed_space_reads %||% list()
    space_names <- vapply(space_reads, function(x)
      as.character(x$name)[1], character(1))
    if (anyDuplicated(space_names) || length(intersect(space_names,
        c(names(inputs), slice_names)))) .wb_operation_pack_v3_error(
      "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
      paste0("Operation '", opname,
        "' has duplicate or colliding typed-space capability names."),
      "semantic_admission")
    for (read in space_reads) {
      input <- inputs[[as.character(read$input)[1]]]
      parameter <- as.character(read$selection$parameter)[1]
      chunk <- as.character(read$chunk_size_parameter)[1]
      if (is.null(input) || !identical(as.character(input$kind)[1],
          "space") || !parameter %in% selector_parameters ||
          !.wb_operation_pack_v3_param_is(properties, chunk, "integer"))
        .wb_operation_pack_v3_error(
          "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
          paste0("Operation '", opname,
            "' has an incompatible typed-space reader declaration."),
          "semantic_admission")
    }
    for (policy in policies) {
      policy_name <- as.character(policy$policy)[1]
      output <- outputs[[as.character(policy$output)[1]]]
      if (identical(policy_name, "authenticated_sparse_membership_v1")) {
        expected <- if (identical(as.character(policy$representation)[1],
          "obs_table")) "obs_table" else "cell_vector_family"
        if (is.null(output) || !identical(as.character(output$kind)[1],
            expected) || !as.character(policy$query_space_read)[1] %in%
            space_names || !as.character(policy$candidate_space_read)[1] %in%
            space_names || !.wb_operation_pack_v3_param_is(properties,
              policy$k_parameter, "integer"))
          .wb_operation_pack_v3_error(
            "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
            paste0("Operation '", opname,
              "' has an incompatible sparse-membership declaration."),
            "semantic_admission")
      } else if (identical(policy_name, "authenticated_pseudobulk_v1")) {
        if (is.null(output) || !identical(as.character(output$kind)[1],
            "feature_table") ||
            !as.character(policy$query_space_read)[1] %in% space_names ||
            !as.character(policy$matrix_slice_read)[1] %in% slice_names)
          .wb_operation_pack_v3_error(
            "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
            paste0("Operation '", opname,
              "' has an incompatible pseudobulk declaration."),
            "semantic_admission")
      }
    }

    reads <- operation$provenance_reads %||% list()
    read_names <- vapply(reads, function(x) as.character(x$name)[1],
      character(1))
    if (anyDuplicated(read_names) || length(intersect(read_names,
        names(inputs)))) .wb_operation_pack_v3_error(
      "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
      paste0("Operation '", opname,
        "' has duplicate or colliding provenance-read names."),
      "semantic_admission")
    for (read in reads) {
      input <- inputs[[as.character(read$input)[1]]]
      assertions <- unlist(read$parameter_assertions %||% list(),
        use.names = FALSE)
      if (is.null(input) || any(!as.character(assertions) %in%
          names(properties))) .wb_operation_pack_v3_error(
        "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
        paste0("Operation '", opname,
          "' has an invalid artifact-ancestry input or parameter assertion."),
        "semantic_admission")
    }
    reader_names <- c(names(inputs), vapply(operation$registry_reads %||%
      list(), function(x) as.character(x$name)[1], character(1)),
      slice_names, read_names)
    if (anyDuplicated(reader_names)) .wb_operation_pack_v3_error(
      "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
      paste0("Operation '", opname,
        "' has colliding reader capability names."),
      "semantic_admission")
  }
  invisible(TRUE)
}

.wb_operation_pack_v3_normalize <- function(manifest, package = NULL,
                                              package_description = NULL) {
  schema <- .wb_operation_pack_v2_read_schema(
    .wb_operation_pack_v3_manifest_schema())
  result <- .wb_json_schema_validate_2020(manifest, schema)
  if (!isTRUE(result$ok)) .wb_operation_pack_v3_error(
    "OPERATION_PACK_MANIFEST_SCHEMA_INVALID",
    paste0("Operation-pack v3 manifest failed Draft 2020-12 validation at ",
      result$path, ": ", result$message), "outer_schema",
    instance_path = result$path)
  .wb_operation_pack_v3_semantic_validate(manifest)
  for (op in manifest$operations) .wb_operation_pack_v2_param_profile_validate(
    op$params_schema, op$qualified_name)
  if (!identical(as.character(manifest$identity_scheme)[1],
      .wb_operation_pack_identity_scheme())) .wb_operation_pack_v3_error(
    "OPERATION_PACK_IDENTITY_SCHEME_MISMATCH",
    "Operation-pack v3 requires canonical JSON v1.", "identity")
  if (!identical(as.character(manifest$compatibility$pack_abi$minimum)[1],
      "3") || !identical(as.character(
        manifest$compatibility$pack_abi$maximum)[1], "3")) {
    .wb_operation_pack_v3_error("OPERATION_PACK_PROTOCOL_INCOMPATIBLE",
      "Operation-pack v3 requires the closed ABI interval 3 through 3.",
      "semantic_admission")
  }
  if (identical(as.character(manifest$backend)[1], "Python") &&
      (!identical(as.character(manifest$compatibility$process_protocol$minimum)[1],
        "pybench-op-v4") || !identical(as.character(
          manifest$compatibility$process_protocol$maximum)[1],
        "pybench-op-v4"))) .wb_operation_pack_v3_error(
      "OPERATION_PACK_PROTOCOL_INCOMPATIBLE",
      "Python ABI v3 requires pybench-op-v4 exactly.", "semantic_admission")
  current <- tryCatch(as.character(utils::packageVersion("scworkbench")),
    error = function(e) "0.1.0")
  minimum <- as.character(manifest$compatibility$scworkbench$minimum)[1]
  maximum <- as.character(manifest$compatibility$scworkbench$maximum_exclusive)[1]
  if (utils::compareVersion(current, minimum) < 0L ||
      utils::compareVersion(current, maximum) >= 0L) .wb_operation_pack_v3_error(
    "OPERATION_PACK_SCWORKBENCH_INCOMPATIBLE",
    paste0("Pack range [", minimum, ", ", maximum,
      ") excludes scworkbench ", current, "."), "semantic_admission")
  if (!is.null(package) && !identical(as.character(manifest$package$name)[1],
      as.character(package)[1])) .wb_operation_pack_v3_error(
    "OPERATION_PACK_PACKAGE_IDENTITY_MISMATCH",
    "Manifest package name differs from the installed R package.",
    "authentication")
  if (!is.null(package_description) && !identical(as.character(
      manifest$package$version)[1], as.character(package_description$Version)[1])) {
    .wb_operation_pack_v3_error("OPERATION_PACK_PACKAGE_IDENTITY_MISMATCH",
      "Manifest version differs from the installed R package.",
      "authentication")
  }
  manifest
}

.wb_operation_pack_v3_identity <- function(manifest, source_sha256,
                                             pack_content_identity) {
  definitions <- stats::setNames(lapply(manifest$operations, function(op) {
    .wb_operation_pack_v3_id("scworkbench.operation_pack.definition.v3", op)
  }), vapply(manifest$operations, function(op) as.character(
    op$qualified_name)[1], character(1)))
  definitions <- definitions[order(names(definitions), method = "radix")]
  manifest_id <- .wb_operation_pack_v3_id(
    "scworkbench.operation_pack.manifest.v3", manifest)
  entry <- .wb_operation_pack_v2_id(
    "scworkbench.operation_pack.entry_point.v2",
    list(backend = manifest$backend, package = manifest$package,
      value = manifest$entry_point))
  source_id <- list(
    scheme = "scworkbench.operation_pack.manifest_source.bytes.v1",
    sha256 = source_sha256)
  pack_value <- list(scheme = "scworkbench.operation_pack.pack.v3",
    manifest_sha256 = manifest_id$sha256, namespace = manifest$namespace,
    package = manifest$package, backend = manifest$backend,
    entry_point = manifest$entry_point,
    operation_definition_sha256 = lapply(definitions, `[[`, "sha256"),
    pack_content_sha256 = pack_content_identity$sha256)
  pack <- .wb_operation_pack_v3_id("scworkbench.operation_pack.pack.v3",
    pack_value)
  list(identity_scheme = .wb_operation_pack_identity_scheme(),
    schema_version = manifest$schema_version, pack_abi_version = "3",
    namespace = manifest$namespace, package = manifest$package,
    backend = manifest$backend, compatibility = manifest$compatibility,
    entry_point = manifest$entry_point,
    manifest_source_identity = source_id, manifest_identity = manifest_id,
    manifest_sha256 = manifest_id$sha256,
    operation_definition_identities = definitions,
    operation_definition_sha256 = lapply(definitions, `[[`, "sha256"),
    distribution_identity = pack_content_identity,
    entry_point_identity = entry, pack_identity = pack,
    pack_sha256 = pack$sha256)
}

.wb_operation_pack_v3_catalog_chunking <- function(op) {
  slices <- op$typed_slice_reads %||% list()
  # The public interface has one chunking record, so multiple reader grants
  # cannot be projected without claiming an unambiguous execution policy.
  if (length(slices) != 1L) return(NULL)
  slice <- slices[[1L]]
  axis <- as.character(slice$chunk_axis %||% "")[1L]
  parameter <- as.character(slice$chunk_size_parameter %||% "")[1L]
  input <- as.character(slice$input %||% "")[1L]
  inputs <- stats::setNames(op$inputs, vapply(op$inputs,
    function(item) as.character(item$name)[1L], character(1)))
  properties <- op$params_schema$properties %||% list()
  supported <- as.character(unlist(slice$supported_axes %||% list(),
    use.names = FALSE))
  if (!identical(as.character(slice$reader %||% "")[1L],
      "read_typed_slices") ||
      !identical(as.character(slice$kind %||% "")[1L], "matrix") ||
      !identical(as.character(slice$call_discipline %||% "")[1L],
        "ordered_partition_exactly_once") ||
      !axis %in% c("cells", "features") || !axis %in% supported ||
      !identical(as.character(inputs[[input]]$kind %||% "")[1L],
        "matrix") ||
      !.wb_operation_pack_v3_param_is(properties, parameter, "integer"))
    return(NULL)
  chunking <- list(chunkable = TRUE, axis = axis,
    chunk_size_param = parameter, status = "v3_typed_slice_capability")
  size <- properties[[parameter]]
  if ("default" %in% names(size)) {
    default <- size$default
    if (!is.numeric(default) || length(default) != 1L ||
        !is.finite(default) || default < 1 ||
        default > .Machine$integer.max || default != floor(default))
      return(NULL)
    chunking$chunk_size_default <- as.integer(default)
  }
  chunking
}

.wb_operation_pack_v3_catalog_definition <- function(op) {
  projected <- op
  selector_parameters <- vapply(projected$cell_selector_axes %||% list(),
    function(x) as.character(x$parameter)[1], character(1))
  for (parameter in selector_parameters) {
    types <- as.character(unlist(projected$params_schema$properties[[parameter]]$
      type, use.names = FALSE))
    projected$params_schema$properties[[parameter]]$type <- unname(as.list(
      setdiff(types, "string")))
  }
  projected$provenance_reads <- NULL
  projected$typed_slice_reads <- NULL
  projected$typed_space_reads <- NULL
  projected$cell_selector_axes <- NULL
  projected$derived_cell_output_axes <- NULL
  projected$publication_policies <- NULL
  projected$parameter_axes <- NULL
  projected$parameter_bindings <- Filter(function(binding)
    !as.character(binding$policy %||% "")[1] %in% c(
      "input_id_with_numeric_suffix_v1",
      "feature_ids_from_table_or_matrix_v1"),
    projected$parameter_bindings %||% list())
  if (!length(projected$parameter_bindings))
    projected$parameter_bindings <- NULL
  projected$retained_parameters <- Filter(function(item) !identical(
    as.character(item$source %||% "")[1], "effective_parameter_value"),
    projected$retained_parameters %||% list())
  if (!length(projected$retained_parameters))
    projected$retained_parameters <- NULL
  projected$outputs <- lapply(projected$outputs, function(output) {
    output$fragment_policy <- NULL
    output
  })
  projected$dimension_policies <- Filter(function(x) !as.character(
    x$policy %||% "")[1] %in% c("authenticated_output_axes_v1",
      "data_dependent_family_v1",
      "standalone_sparse_cell_family_v1",
      "authenticated_sparse_membership_v1",
      "authenticated_pseudobulk_v1",
      "cell_by_parameter_axis_v1", "feature_parameter_axis_cartesian_v1",
      "one_per_parameter_axis_v1", "singleton_parameter_echo_v1"),
    projected$dimension_policies %||% list())
  if (!length(projected$dimension_policies)) projected$dimension_policies <- NULL
  definition <- .wb_operation_pack_v2_catalog_definition(projected)
  typed_slice_chunking <- .wb_operation_pack_v3_catalog_chunking(op)
  if (!is.null(typed_slice_chunking))
    definition$chunking <- typed_slice_chunking
  operation_display_groups <- Filter(function(group) identical(
    as.character(group$scope)[1L], "operation"),
    op$optional_display_axis_groups %||% list())
  endpoint_parameters <- unique(unlist(lapply(operation_display_groups,
    function(group) vapply(group$activation, function(role)
      as.character(role$endpoint_parameter)[1L], character(1))),
    use.names = FALSE))
  if (length(endpoint_parameters)) definition$params <- lapply(
    definition$params, function(parameter) {
      if (as.character(parameter$name)[1L] %in% endpoint_parameters)
        parameter$type <- "list_or_cell_set"
      parameter
    })
  definition$pack_abi_version <- "3"
  definition$v2_definition <- NULL
  definition$v3_definition <- op
  if (length(op$typed_slice_reads %||% list()))
    definition$typed_slice_reads <- op$typed_slice_reads
  if (length(op$typed_space_reads %||% list()))
    definition$typed_space_reads <- op$typed_space_reads
  if (length(op$contained_model_reads %||% list())) {
    model_inputs <- vapply(op$contained_model_reads, function(x)
      as.character(x$input)[1], character(1))
    definition$coverage[model_inputs] <-
      rep("model_associated_unless_query_space", length(model_inputs))
  }
  definition
}

.wb_operation_pack_v3_registration <- function(manifest, runners,
                                                 package_description,
                                                 installed_path,
                                                 manifest_path) {
  .wb_operation_pack_named_object(runners, "operations", allow_empty = FALSE)
  expected <- vapply(manifest$operations, function(x) as.character(
    x$qualified_name)[1], character(1))
  if (!setequal(names(runners), expected) || anyDuplicated(names(runners)))
    .wb_operation_pack_v3_error("OPERATION_PACK_ENTRY_POINT_INVALID",
      "V3 runner names must exactly equal manifest qualified operation names.",
      "authentication")
  for (name in expected) {
    runner <- runners[[name]]
    if (!is.function(runner) || !identical(names(formals(runner)),
        c("readers", "writers", "params", "context"))) {
      .wb_operation_pack_v3_error("OPERATION_PACK_ENTRY_POINT_INVALID",
        paste0("V3 runner '", name,
          "' must have formals readers, writers, params, context."),
        "authentication")
    }
  }
  content <- .wb_operation_pack_v2_content_identity(installed_path)
  identity <- .wb_operation_pack_v3_identity(manifest,
    .wb_operation_pack_v2_file_sha256(manifest_path), content)
  definitions <- stats::setNames(lapply(manifest$operations,
    .wb_operation_pack_v3_catalog_definition), expected)
  structure(list(manifest = manifest, runners = runners,
    identity = identity, definitions = definitions, protocol_version = "3",
    manifest_path = manifest_path, installed_path = installed_path,
    runtime_attestation = list(schema = "scworkbench.operation_pack.runtime.r.v3",
      backend = "R", package = manifest$package,
      built = as.character(package_description$Built %||% NA_character_)[1],
      remote_sha = as.character(package_description$RemoteSha %||%
        NA_character_)[1], distribution_identity = content,
      manifest_source_identity = identity$manifest_source_identity,
      entry_point_identity = identity$entry_point_identity)),
    class = c("wb_operation_pack_registration_v3",
      "wb_operation_pack_registration_v2", "wb_operation_pack_registration",
      "list"))
}

.wb_operation_pack_v3_manifest_path <- .wb_operation_pack_v2_manifest_path

.wb_operation_pack_v3_invoke <- function(package, lib.loc = NULL) {
  manifest_path <- .wb_operation_pack_v3_manifest_path(package, lib.loc)
  description <- utils::packageDescription(package, lib.loc = lib.loc)
  manifest <- .wb_operation_pack_v3_normalize(
    .wb_operation_pack_v3_read_manifest(manifest_path), package,
    description)
  if (!identical(as.character(manifest$backend)[1], "R"))
    .wb_operation_pack_v3_error("OPERATION_PACK_RUNTIME_UNAVAILABLE",
      "Installed R invocation requires backend R.", "authentication")
  .wb_operation_pack_assert(requireNamespace(package, quietly = TRUE,
      lib.loc = lib.loc), "OPERATION_PACK_PACKAGE_UNAVAILABLE",
    paste0("Installed package '", package, "' could not be loaded."))
  entry_parts <- strsplit(as.character(manifest$entry_point)[1], "::",
    fixed = TRUE)[[1]]
  if (length(entry_parts) != 2L || !identical(entry_parts[[1]], package) ||
      !entry_parts[[2]] %in% getNamespaceExports(package))
    .wb_operation_pack_v3_error("OPERATION_PACK_ENTRY_POINT_INVALID",
      "V3 R entry point must be the exact installed package::export.",
      "authentication")
  entry <- getExportedValue(package, entry_parts[[2]])
  if (!is.function(entry) || length(formals(entry)) != 0L)
    .wb_operation_pack_v3_error("OPERATION_PACK_ENTRY_POINT_INVALID",
      "V3 R entry point must be a zero-argument function.", "authentication")
  context <- new.env(parent = emptyenv())
  context$abi <- "3"; context$package <- package
  context$manifest_path <- manifest_path
  context$package_description <- description
  context$installed_path <- dirname(dirname(manifest_path)); context$result <- NULL
  .wb_operation_pack_registry$registration_context <- context
  on.exit({ .wb_operation_pack_registry$registration_context <- NULL }, add = TRUE)
  returned <- tryCatch(entry(), error = function(error) {
    if (inherits(error, "wb_operation_pack_error")) stop(error)
    .wb_operation_pack_v3_error("OPERATION_PACK_ENTRY_POINT_FAILED",
      paste0("V3 R entry point failed: ", conditionMessage(error)),
      "authentication")
  })
  if (!inherits(returned, "wb_operation_pack_registration_v3") ||
      !inherits(context$result, "wb_operation_pack_registration_v3") ||
      !identical(returned, context$result)) .wb_operation_pack_v3_error(
    "OPERATION_PACK_ENTRY_POINT_INVALID",
    "V3 R entry point must return exactly one registration result.",
    "authentication")
  returned
}
