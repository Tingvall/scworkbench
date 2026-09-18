# Core-owned operation-pack ABI v2 staging, audit, publication, and recovery.

.wb_operation_pack_v2_fault <- function(event, ...) {
  hook <- getOption("scworkbench.operation_pack_v2_test_hook", NULL)
  if (is.function(hook)) {
    error <- tryCatch({ hook(event = event, ...); NULL }, error = identity)
    if (!is.null(error)) {
      if (startsWith(event, "catalog_")) stop(error)
      code <- if (event %in% c("before_publication", "published")) {
        "PYBENCH_PUBLICATION_FAILED"
      } else if (event %in% c("before_reopened", "reopened")) {
        "PYBENCH_REOPEN_VALIDATION_FAILED"
      } else if (event %in% c("receipt_received")) {
        "PYBENCH_RECEIPT_MISMATCH"
      } else if (event %in% c("audited")) {
        "PYBENCH_OUTPUT_INVALID"
      } else if (event %in% c("resolved", "preflighted")) {
        "OPERATION_PACK_PREFLIGHT_FAILED"
      } else "PYBENCH_PROCESS_FAILED"
      phase <- if (startsWith(code, "OPERATION_PACK_PREFLIGHT")) "preflight" else if (code == "PYBENCH_PUBLICATION_FAILED") "publication" else if (code == "PYBENCH_REOPEN_VALIDATION_FAILED") "reopen" else if (code == "PYBENCH_RECEIPT_MISMATCH") "receipt" else if (code == "PYBENCH_OUTPUT_INVALID") "audit" else "execution"
      .wb_operation_pack_v2_error(code,
        paste0("Injected ABI v2 failure at ", event, ": ", conditionMessage(error)), phase)
    }
  }
  invisible(TRUE)
}

.wb_operation_pack_v2_store <- function(bundle) {
  file.path(normalizePath(bundle$dir, winslash = "/", mustWork = TRUE),
    "operation_pack_v2")
}

.wb_operation_pack_v2_pending_root <- function(bundle) {
  file.path(.wb_operation_pack_v2_store(bundle), ".pending")
}

.wb_operation_pack_v2_cleanup_empty <- function(bundle) {
  pending <- .wb_operation_pack_v2_pending_root(bundle)
  root <- .wb_operation_pack_v2_store(bundle)
  if (dir.exists(pending) && !length(list.files(pending, all.files = TRUE, no.. = TRUE))) {
    unlink(pending, recursive = TRUE, force = TRUE)
  }
  if (dir.exists(root) && !length(list.files(root, all.files = TRUE, no.. = TRUE))) {
    unlink(root, recursive = TRUE, force = TRUE)
  }
  invisible(TRUE)
}

.wb_operation_pack_v2_safe_component <- function(value, label) {
  value <- as.character(value)[1]
  .wb_operation_pack_assert(nzchar(value) && identical(value, basename(value)) &&
    !value %in% c(".", "..") && !grepl("[/\\\\]", value),
    "PYBENCH_STALE_STAGING_IDENTITY", paste0(label, " is not one safe path component."),
    class = "wb_operation_pack_v2_error")
  value
}

.wb_operation_pack_v2_deep_copy <- function(value) {
  unserialize(serialize(value, NULL, version = 3L))
}

.wb_operation_pack_v2_value_identity <- function(value, scheme) {
  .wb_operation_pack_v2_id(scheme, .wb_json_sanitize(value))
}

.wb_operation_pack_v2_primitive_cells <- function(value) {
  if (!.wb_is_primitive(value)) return(character())
  as.character(value$cell_id %||% names(value$value %||% character()) %||% character())
}

.wb_operation_pack_v2_primitive_features <- function(value) {
  if (!.wb_is_primitive(value)) return(character())
  if (is.data.frame(value$table) && "feature_id" %in% names(value$table)) {
    return(as.character(value$table$feature_id))
  }
  as.character(value$feature_id %||% character())
}

.wb_operation_pack_v2_bind_inputs <- function(bundle, inputs, effective_cells) {
  cells <- unique(as.character(effective_cells))
  stats::setNames(lapply(names(inputs), function(name) {
    value <- .wb_operation_pack_v2_deep_copy(inputs[[name]])
    kind <- as.character(value$kind %||% "")[1]
    if (identical(kind, "matrix")) {
      matrix_cells <- if (is.null(value$values)) {
        wb_cells_with_matrix(bundle, value$matrix_id)
      } else {
        as.character(value$cell_id %||% colnames(value$values))
      }
      value$cell_id <- cells[cells %in% matrix_cells]
      value$feature_id <- if (is.null(value$values)) {
        wb_feature_ids(bundle, value$matrix_id)
      } else {
        as.character(value$feature_id %||% rownames(value$values))
      }
      if (is.null(value$values)) {
        # The Python ABI transport is a self-contained authenticated JSON
        # projection. Resolve a file-backed core matrix through the public
        # logical getter before hashing/staging it; a null physical-storage
        # placeholder cannot be consumed or authenticated by the recipient
        # process.
        # `wb_slice()` may preserve a sparse backend class. The ABI payload and
        # canonical identity are language-neutral JSON, so materialize the
        # projected slice as an ordinary dense R matrix before either step.
        value$values <- as.matrix(wb_slice(bundle,
          matrix_id = value$matrix_id, features = value$feature_id,
          cells = value$cell_id))
      } else {
        value$values <- value$values[match(value$feature_id,
          as.character(value$feature_id %||% rownames(value$values))),
          match(value$cell_id, matrix_cells), drop = FALSE]
        dimnames(value$values) <- list(value$feature_id, value$cell_id)
      }
      value$dimensions <- as.integer(c(length(value$feature_id), length(value$cell_id)))
      fragments <- if (is.null(value$values)) tryCatch(
        wb_matrix_fragments(bundle, value$matrix_id),
        error = function(error) data.frame()) else data.frame()
      value$storage_profile <- if (nrow(fragments) >= 1L) {
        "matrix_backed_chunked_v1"
      } else value$storage_profile %||% "matrix_ordinary_v1"
    } else if (identical(kind, "cell_vector")) {
      index <- which(as.character(value$cell_id) %in% cells)
      value$cell_id <- as.character(value$cell_id[index])
      value$value <- value$value[index]
      if (!is.null(names(value$value))) names(value$value) <- value$cell_id
    } else if (kind %in% c("space", "space_2d")) {
      coordinates <- value$values
      if (is.null(coordinates)) {
        space_id <- as.character(value$space_id %||% "")[1]
        .wb_operation_pack_assert(nzchar(space_id),
          "PYBENCH_INPUT_IDENTITY_MISMATCH",
          "Space input is missing its symbolic space_id.", phase = "resolution")
        coordinates <- wb_space(bundle, space_id)
      }
      .wb_operation_pack_assert(is.matrix(coordinates) &&
          !is.null(rownames(coordinates)), "PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Space input must resolve to a row-named coordinate matrix.",
        phase = "resolution")
      index <- match(cells, rownames(coordinates))
      .wb_operation_pack_assert(!anyNA(index),
        "PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Space input does not cover every effective cell.",
        phase = "resolution")
      value$values <- coordinates[index, , drop = FALSE]
      rownames(value$values) <- cells
      value$cell_id <- cells
      value$dimensions <- as.integer(dim(value$values))
      value$storage_profile <- value$storage_profile %||% "space_dense_v1"
    } else if (kind %in% c("cell_vector_family", "relation_family")) {
      index <- match(cells, unique(as.character(value$cell_id)))
      retained <- cells[!is.na(index)]
      keep <- as.character(value$cell_id) %in% retained
      order_index <- order(match(as.character(value$cell_id[keep]), retained),
        seq_along(value$cell_id)[keep], method = "radix")
      slots <- c("cell_id", "key", "value")
      for (slot in intersect(slots, names(value))) value[[slot]] <- value[[slot]][keep][order_index]
    }
    value
  }), names(inputs))
}

.wb_operation_pack_v2_dimensions <- function(value, kind = as.character(value$kind %||% "")[1]) {
  if (identical(kind, "cell_set_admission")) return(as.integer(length(value$cells %||% character())))
  if (identical(kind, "cell_set_family_admission")) return(as.integer(c(
    length(value$sets %||% list()),
    sum(vapply(value$sets %||% list(), function(x) length(x$cells %||% character()), integer(1)))
  )))
  if (.wb_is_primitive(value)) {
    if (!is.null(value$values) && length(dim(value$values)) == 2L) return(as.integer(dim(value$values)))
    if (kind %in% c("cell_vector")) return(as.integer(length(value$cell_id %||% value$value)))
    if (kind %in% c("cell_vector_family", "relation_family", "path_2d_family", "space_path_family")) {
      return(as.integer(c(length(value$cell_id %||% value$key %||% value$path_id),
        if (kind == "path_2d_family") 4L else if (kind == "space_path_family") 5L else 3L)))
    }
    if (kind %in% c("feature_table", "obs_table") && is.data.frame(value$table)) return(as.integer(dim(value$table)))
    if (kind == "model_ref") return(1L)
    if (kind %in% c("matrix", "space", "space_2d") && !is.null(value$dimensions)) return(as.integer(value$dimensions))
  }
  1L
}

.wb_operation_pack_v2_input_profile <- function(kind, value) {
  if (kind == "matrix") return(as.character(value$storage_profile %||% "matrix_ordinary_v1")[1])
  if (kind == "space") return(as.character(value$storage_profile %||% "space_dense_v1")[1])
  if (kind == "space_2d") return("space_2d_dense_v1")
  if (kind == "model_ref") return("model_ref_contained_tree_v1")
  if (kind == "path_2d_family") return("path_2d_family_v1")
  if (kind == "space_path_family") return("space_path_family_v1")
  "terminal_primitive_v1"
}

.wb_operation_pack_v2_reader_name <- function(kind) {
  switch(kind, matrix = "read_matrix", space = "read_space", space_2d = "read_space_2d",
    model_ref = "read_model_ref", path_2d_family = "read_path_2d_family",
    space_path_family = "read_space_path_family", "read_terminal_primitive")
}

.wb_operation_pack_v2_writer_name <- function(output) {
  kind <- as.character(output$kind)[1]
  if (identical(output$category, "core_registry_request")) return(switch(kind,
    cell_set_admission = "request_cell_set_admission",
    cell_set_family_admission = "request_cell_set_family_admission",
    .wb_operation_pack_v2_error("OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
      paste0("Unknown core registry request kind: ", kind), "semantic_admission")))
  switch(kind, matrix = "write_matrix", space = "write_space", space_2d = "write_space_2d",
    model_ref = "write_model_ref", path_2d_family = "write_path_2d_family",
    space_path_family = "write_space_path_family", "write_terminal_primitive")
}

.wb_operation_pack_v2_identity_plain <- function(scheme, value) {
  list(scheme = scheme, sha256 = .wb_operation_pack_sha256(value))
}

.wb_operation_pack_v2_identity_scoped <- function(scheme, scope, value) {
  list(scheme = scheme, scope = scope, sha256 = .wb_operation_pack_sha256(value))
}

.wb_operation_pack_v2_input_descriptor <- function(name, value, declaration,
                                                     transport_value = NULL) {
  kind <- as.character(declaration$kind)[1]
  identity_value <- transport_value %||% unclass(value)
  cells <- if (is.null(transport_value)) .wb_operation_pack_v2_primitive_cells(value) else
    unname(unlist(identity_value$cell_id %||% list(), use.names = FALSE))
  features <- if (is.null(transport_value)) .wb_operation_pack_v2_primitive_features(value) else
    unname(unlist(identity_value$feature_id %||% list(), use.names = FALSE))
  descriptor <- list(
    kind = kind, storage_profile = .wb_operation_pack_v2_input_profile(kind, value),
    reader = .wb_operation_pack_v2_reader_name(kind),
    dimensions = unname(as.list(.wb_operation_pack_v2_dimensions(value, kind))),
    alignment = as.character(declaration$alignment)[1],
    content_identity = .wb_operation_pack_v2_identity_plain(paste0("scworkbench.", kind, ".content.v1"), identity_value),
    ancestry_identity = .wb_operation_pack_v2_identity_plain("scworkbench.provenance.ancestry.v1", list(input = name, value = identity_value)),
    payload_manifest_identity = .wb_operation_pack_v2_identity_plain("scworkbench.payload.manifest.v2", list(input = name, value = identity_value))
  )
  if (kind %in% c("matrix", "space", "space_2d", "cell_vector", "cell_vector_family", "relation_family")) {
    descriptor$cell_order_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", if (is.null(transport_value)) cells else
        identity_value$cell_id)
  }
  if (kind %in% c("matrix", "feature_table")) {
    descriptor$feature_order_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.feature_order.v1", if (is.null(transport_value)) features else
        identity_value$feature_id)
  }
  if (kind %in% c("cell_vector", "cell_vector_family", "relation_family", "feature_table", "obs_table", "path_2d_family", "space_path_family")) {
    descriptor$semantic_metadata_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.semantic_metadata.v2", identity_value$meta %||%
        structure(list(), names = character()))
  }
  if (kind %in% c("path_2d_family", "space_path_family")) {
    order_value <- if (kind == "path_2d_family") list(identity_value$key,
      identity_value$point) else list(identity_value$space_id,
      identity_value$path_id, identity_value$point, identity_value$dim)
    descriptor$row_order_identity <- .wb_operation_pack_v2_identity_plain("scworkbench.row_order.v1", order_value)
  }
  if (kind == "space_path_family") descriptor$linked_space_identity <- .wb_operation_pack_v2_identity_plain(
    "scworkbench.space.content.v1", if (is.null(transport_value)) {
      sort(unique(as.character(value$space_id)), method = "radix")
    } else unname(as.list(sort(unique(as.character(unlist(identity_value$space_id,
      use.names = FALSE))), method = "radix"))))
  if (kind == "model_ref") {
    descriptor$model_linkage_identity <- .wb_operation_pack_v2_identity_plain("scworkbench.model_linkage.v1", identity_value)
    descriptor$contained_payload_identity <- .wb_operation_pack_v2_identity_plain("scworkbench.operation_pack.contained_payload.v2", identity_value)
  }
  descriptor$descriptor_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.input_descriptor.v2", "descriptor excluding descriptor_identity", descriptor)
  list(name = name, reference = paste0(kind, ":", name), descriptor = descriptor)
}

.wb_operation_pack_v2_expected_dimensions <- function(output, inputs,
                                                        dimension_policy = NULL) {
  kind <- as.character(output$kind)[1]
  first <- if (length(inputs)) inputs[[1]] else NULL
  input_dims <- if (!is.null(first)) .wb_operation_pack_v2_dimensions(first) else 1L
  n_cells <- if (length(inputs)) {
    candidates <- vapply(inputs, function(x) length(.wb_operation_pack_v2_primitive_cells(x)), integer(1))
    max(candidates, 1L)
  } else 1L
  if (kind == "matrix") return(as.integer(if (length(input_dims) == 2L) input_dims else c(1L, n_cells)))
  if (kind == "space") return(as.integer(c(n_cells, max(1L, min(2L, if (length(input_dims) > 1L) input_dims[[2]] else 2L)))))
  if (kind == "space_2d") return(as.integer(c(n_cells, 2L)))
  if (kind %in% c("cell_vector", "cell_set_admission")) return(as.integer(n_cells))
  if (kind == "cell_set_family_admission") return(as.integer(c(0L, 0L)))
  if (kind %in% c("cell_vector_family", "relation_family")) return(as.integer(c(n_cells, 3L)))
  if (kind == "path_2d_family") return(as.integer(c(n_cells, 4L)))
  if (kind == "space_path_family") return(as.integer(c(n_cells, 5L)))
  if (kind %in% c("feature_table", "obs_table")) {
    # Statistics terminal tables are data-dependent. A zero pair is the
    # request-side sentinel for dimensions audited from the staged primitive.
    return(as.integer(if (identical(dimension_policy, "data_dependent_table_v1"))
      c(0L, 0L) else c(1L, 1L)))
  }
  1L
}

.wb_operation_pack_v2_semantic_constraints <- function(output) {
  kind <- as.character(output$kind)[1]
  switch(kind,
    matrix = list(value_domain = "real", finite_values = TRUE, sparse_allowed = TRUE),
    space = list(finite_values = TRUE, minimum_dimensions = 1L),
    space_2d = list(finite_values = TRUE, coordinate_dimensions = 2L),
    model_ref = list(engine = "synthetic", contained = TRUE, no_symlinks = TRUE),
    cell_vector = list(value_kind = as.character(output$value_kind %||% "categorical")[1], missing_values = "forbidden"),
    cell_vector_family = list(value_kind = as.character(output$value_kind %||% "continuous")[1], missing_values = "forbidden"),
    relation_family = list(value_kind = "continuous", missing_values = "forbidden"),
    feature_table = list(table_type = as.character(output$table_type %||% "generic")[1], row_order = "canonical"),
    obs_table = list(table_type = as.character(output$table_type %||% "generic")[1], row_order = "canonical"),
    path_2d_family = list(finite_coordinates = TRUE, key_fields = list("key", "point")),
    space_path_family = list(finite_coordinates = TRUE, key_fields = list("space_id", "path_id", "point", "dim")),
    cell_set_admission = list(members_unique = TRUE, members_in_universe = TRUE, order = "core_cell_order"),
    cell_set_family_admission = list(
      set_names_unique = TRUE, members_unique = TRUE,
      members_in_universe = TRUE, set_order = "canonical_name_order",
      member_order = "core_cell_order", family_mode = c("add", "replace"),
      source_provenance = "unambiguous"))
}

.wb_operation_pack_v2_output_grant <- function(output, inputs, allocated_id,
                                                registration = NULL,
                                                dimension_policy = NULL) {
  kind <- as.character(output$kind)[1]
  category <- as.character(output$category)[1]
  python_backend <- identical(as.character(registration$identity$backend %||% "R")[1],
    "Python")
  input_names <- if (python_backend) unname(as.list(names(inputs))) else names(inputs)
  descriptor <- list(
    category = category, kind = kind, storage_profile = as.character(output$storage_profile)[1],
    writer = .wb_operation_pack_v2_writer_name(output),
    expected_dimensions = unname(as.list(.wb_operation_pack_v2_expected_dimensions(
      output, inputs, dimension_policy = dimension_policy))),
    expected_alignment = if (kind == "matrix") "cell_and_feature_ordered" else if (kind %in% c("space", "space_2d", "cell_vector", "cell_vector_family", "relation_family", "cell_set_admission")) "cell_ordered" else if (kind == "cell_set_family_admission") "family_name_then_core_cell_order" else if (kind == "feature_table") "feature_ordered" else if (kind == "model_ref") "model_linked" else if (kind == "path_2d_family") "canonical_row_ordered" else if (kind == "space_path_family") "associated_space" else "none",
    expected_ancestry_identity = .wb_operation_pack_v2_identity_plain("scworkbench.provenance.ancestry.v1", list(output = output$name, inputs = input_names)),
    expected_model_linkage = list(mode = "none"),
    semantic_constraints = .wb_operation_pack_v2_semantic_constraints(output)
  )
  if (!identical(category, "core_registry_request")) descriptor$relative_root <- paste0("outputs/", output$name)
  cells <- if (length(inputs)) .wb_operation_pack_v2_primitive_cells(inputs[[1]]) else character()
  features <- if (length(inputs)) .wb_operation_pack_v2_primitive_features(inputs[[1]]) else character()
  if (python_backend) {
    cells <- unname(as.list(cells))
    features <- unname(as.list(features))
  }
  if (kind %in% c("matrix", "space", "space_2d", "cell_vector", "cell_vector_family", "relation_family", "cell_set_admission", "cell_set_family_admission")) {
    descriptor$expected_cell_order_identity <- .wb_operation_pack_v2_identity_plain("scworkbench.cell_order.v1", cells)
  }
  if (kind %in% c("matrix", "feature_table")) descriptor$expected_feature_order_identity <- .wb_operation_pack_v2_identity_plain("scworkbench.feature_order.v1", features)
  expectation <- registration$runtime_config$conformance_expectations[[as.character(output$name)[1]]] %||% list()
  if (kind %in% c("path_2d_family", "space_path_family")) {
    row_value <- expectation$row_order %||% list(output = output$name)
    descriptor$expected_row_order_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.row_order.v1", row_value)
  }
  if (kind == "space_path_family") {
    linked_value <- expectation$linked_space %||% list(output = output$name)
    descriptor$expected_linked_space_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.space.content.v1", linked_value)
  }
  if (kind == "model_ref") descriptor$contained_payload_requirements <- list(
    contained = TRUE, no_symlinks = TRUE, manifest_scheme = "scworkbench.operation_pack.payload_manifest.v2")
  descriptor$grant_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.output_grant.v2", "descriptor excluding grant_identity", descriptor)
  list(name = as.character(output$name)[1], allocated_id = allocated_id, descriptor = descriptor)
}

.wb_operation_pack_v2_selector_selected <- function(selector, params) {
  if (is.null(selector)) return(TRUE)
  name <- as.character(selector$parameter)[1]
  identical(.wb_operation_pack_canonical_json(params[[name]] %||% NULL),
    .wb_operation_pack_canonical_json(selector$equals %||% NULL))
}

.wb_operation_pack_v2_version_ok <- function(version, specifier) {
  .wb_operation_pack_version_satisfies(version, specifier)
}

.wb_operation_pack_v2_dynamic_value <- function(value, field) {
  meta <- value$meta %||% list()
  parts <- strsplit(as.character(field)[1], ".", fixed = TRUE)[[1]]
  out <- meta
  for (part in parts) out <- if (is.list(out)) out[[part]] else NULL
  as.character(out %||% "")[1]
}

.wb_operation_pack_v2_preflight <- function(operation, inputs, params,
                                             registration = NULL,
                                             transport_inputs = NULL) {
  declared <- operation$dependencies %||% list()
  selected <- list(); dynamic <- list()
  dispositions <- structure(list(), names = character())
  python_backend <- identical(as.character(registration$identity$backend %||% "R")[1],
    "Python")
  for (dependency in declared) {
    id <- as.character(dependency$requirement_id)[1]
    kind <- as.character(dependency$kind)[1]
    selected_now <- identical(as.character(dependency$disposition)[1], "required") ||
      .wb_operation_pack_v2_selector_selected(dependency$selected_when %||% NULL, params)
    if (!selected_now) {
      dispositions[[id]] <- list(status = "not_selected", requirement_id = id)
      next
    }
    selected[[length(selected) + 1L]] <- dependency
    if (kind == "r_package") {
      available <- requireNamespace(as.character(dependency$name)[1], quietly = TRUE)
      if (!available) .wb_operation_pack_v2_error("OPERATION_PACK_DEPENDENCY_MISSING",
        paste0("Required R package '", dependency$name, "' is unavailable."), "preflight", requirement_id = id)
      version <- as.character(utils::packageVersion(as.character(dependency$name)[1]))
      if (!.wb_operation_pack_v2_version_ok(version, dependency$version$specifier)) .wb_operation_pack_v2_error(
        "OPERATION_PACK_DEPENDENCY_INCOMPATIBLE", paste0("R package '", dependency$name, "' version is incompatible."),
        "preflight", requirement_id = id, observed_version = version)
      dispositions[[id]] <- list(status = "available", requirement_id = id, name = dependency$name, version = version)
    } else if (kind == "python_distribution") {
      if (!python_backend) .wb_operation_pack_v2_error("OPERATION_PACK_PREFLIGHT_FAILED",
        "Python dependency cannot be selected for an R adapter.", "preflight", requirement_id = id)
      evidence <- .wb_operation_pack_v2_python_probe_distribution(registration,
        as.character(dependency$name)[1])
      if (!.wb_operation_pack_v2_version_ok(evidence$version,
          dependency$version$specifier)) .wb_operation_pack_v2_error(
        "OPERATION_PACK_DEPENDENCY_INCOMPATIBLE",
        paste0("Python distribution '", dependency$name, "' version is incompatible."),
        "preflight", requirement_id = id, observed_version = evidence$version)
      dispositions[[id]] <- c(list(requirement_id = id, status = "available"), evidence)
    } else if (kind == "device_runtime") {
      available <- identical(as.character(dependency$name)[1], "cpu") || isTRUE(getOption(paste0("scworkbench.device.", dependency$name), FALSE))
      if (!available) .wb_operation_pack_v2_error("OPERATION_PACK_PREFLIGHT_FAILED",
        paste0("Required device '", dependency$name, "' is unavailable."), "preflight", requirement_id = id)
      dispositions[[id]] <- list(status = "available", requirement_id = id, name = dependency$name)
    } else if (kind == "system_library") {
      probes <- getOption("scworkbench.operation_pack_v2.system_probes", list())
      evidence <- probes[[as.character(dependency$name)[1]]]
      if (is.null(evidence)) .wb_operation_pack_v2_error("OPERATION_PACK_PREFLIGHT_FAILED",
        paste0("System dependency '", dependency$name, "' has no core-owned probe."), "preflight", requirement_id = id)
      dispositions[[id]] <- list(status = "available", requirement_id = id, evidence = evidence)
    } else if (kind == "dynamic_input_metadata_package") {
      input_name <- as.character(dependency$input_name)[1]
      value <- .wb_operation_pack_v2_dynamic_value(inputs[[input_name]], dependency$metadata_field)
      pattern <- if (identical(dependency$ecosystem, "R")) "^[A-Za-z][A-Za-z0-9.]*$" else "^[A-Za-z0-9][A-Za-z0-9._-]*$"
      if (!nzchar(value) || !grepl(pattern, value, perl = TRUE)) .wb_operation_pack_v2_error(
        "OPERATION_PACK_DYNAMIC_PROVIDER_INVALID", "Dynamic provider metadata is absent or malformed.",
        "preflight", requirement_id = id, input_name = input_name)
      if (identical(dependency$ecosystem, "Python")) {
        if (!python_backend) .wb_operation_pack_v2_error("OPERATION_PACK_DEPENDENCY_MISSING",
          paste0("Dynamic provider '", value, "' requires the Python adapter."),
          "preflight", requirement_id = id)
        evidence <- .wb_operation_pack_v2_python_probe_distribution(registration, value)
        resolved <- list(name = evidence$name, version = evidence$version,
          artifact_identity = evidence$artifact_identity,
          probe_evidence_identity = .wb_operation_pack_v2_identity_plain(
            "scworkbench.python_import_spec.v1", list(import_name = value)))
      } else {
        if (!identical(dependency$ecosystem, "R") ||
            !requireNamespace(value, quietly = TRUE)) .wb_operation_pack_v2_error(
          "OPERATION_PACK_DEPENDENCY_MISSING", paste0("Dynamic provider '", value,
            "' is unavailable."), "preflight", requirement_id = id)
        version <- as.character(utils::packageVersion(value))
        resolved <- list(name = value, version = version,
          artifact_identity = .wb_operation_pack_v2_identity_plain(
            "scworkbench.r_package.artifact.v1", list(name = value, version = version)),
          probe_evidence_identity = .wb_operation_pack_v2_identity_plain(
            "scworkbench.r_namespace_exports.v1", getNamespaceExports(value)))
      }
      identity_value <- if (python_backend) transport_inputs[[input_name]] else
        unclass(inputs[[input_name]])
      input_identity <- .wb_operation_pack_v2_identity_plain(paste0("scworkbench.",
        inputs[[input_name]]$kind, ".content.v1"), identity_value)
      resolution <- list(
        requirement_id = id,
        selector_identity = .wb_operation_pack_v2_identity_plain("scworkbench.operation_pack.dynamic_dependency_selector.v2", dependency),
        input_name = input_name, input_identity = input_identity, metadata_field = dependency$metadata_field,
        ecosystem = dependency$ecosystem, provider_name = value,
        package_name_scheme = dependency$package_name_scheme, probe = dependency$probe,
        disposition = dependency$disposition,
        resolved_package = resolved,
        status = "available")
      resolution$resolution_identity <- .wb_operation_pack_v2_identity_scoped(
        "scworkbench.operation_pack.dynamic_dependency_resolution.v2", "resolution excluding resolution_identity", resolution)
      dynamic[[length(dynamic) + 1L]] <- resolution
      dispositions[[id]] <- resolution
    }
  }
  declared_id <- .wb_operation_pack_v2_identity_plain("scworkbench.operation_pack.dependencies.v2", declared)
  selected_id <- .wb_operation_pack_v2_identity_plain("scworkbench.operation_pack.dependencies.v2", selected)
  preflight_value <- list(declared = declared, selected = selected,
    dispositions = dispositions, dynamic = dynamic, network_policy = "deny")
  list(declared = declared, selected = selected, dispositions = dispositions, dynamic = dynamic,
    declared_identity = declared_id, selected_identity = selected_id,
    preflight_identity = .wb_operation_pack_v2_identity_plain("scworkbench.operation_pack.preflight.v2", preflight_value))
}

.wb_operation_pack_v2_dynamic_reread <- function(operation, inputs, preflight) {
  for (resolution in preflight$dynamic) {
    dependency <- Filter(function(x) identical(as.character(x$requirement_id)[1], resolution$requirement_id), operation$dependencies)[[1]]
    observed <- .wb_operation_pack_v2_dynamic_value(inputs[[dependency$input_name]], dependency$metadata_field)
    if (!identical(observed, resolution$provider_name)) .wb_operation_pack_v2_error(
      "OPERATION_PACK_DYNAMIC_PROVIDER_CHANGED", "Dynamic provider metadata changed after preflight.",
      "dispatch", requirement_id = resolution$requirement_id,
      expected = resolution$provider_name, observed = observed)
  }
  invisible(TRUE)
}

.wb_operation_pack_v2_runtime_attestation <- function(registration, op_name, preflight) {
  identity <- registration$identity
  value <- list(
    schema = "scworkbench.operation_pack.runtime.v2",
    backend = as.character(identity$backend)[1],
    pack_identity = identity$pack_identity,
    manifest_source_identity = identity$manifest_source_identity,
    distribution_identity = identity$distribution_identity,
    operation_definition_identity = identity$operation_definition_identities[[op_name]],
    entry_point = list(value = identity$entry_point, identity = identity$entry_point_identity),
    declared_requirement_set_identity = preflight$declared_identity,
    selected_requirement_set_identity = preflight$selected_identity,
    dynamic_resolutions = preflight$dynamic,
    preflight_report_identity = preflight$preflight_identity,
    path_policy = "no_absolute_paths")
  value$runtime_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.runtime.v2", "runtime attestation excluding runtime_identity", value)
  value
}

.wb_operation_pack_v2_request <- function(bundle, registration, operation, inputs, params,
                                           transition_id, session_id, run_id, generation,
                                           preflight, stage_root) {
  op_name <- as.character(operation$qualified_name)[1]
  declarations <- stats::setNames(operation$inputs, vapply(operation$inputs, `[[`, character(1), "name"))
  python_backend <- identical(as.character(registration$identity$backend)[1], "Python")
  transport_inputs <- if (python_backend) stats::setNames(lapply(names(inputs),
    function(name) .wb_operation_pack_v2_transport_value(inputs[[name]],
      declarations[[name]]$kind)), names(inputs)) else NULL
  input_records <- lapply(names(inputs), function(name) .wb_operation_pack_v2_input_descriptor(
    name, inputs[[name]], declarations[[name]],
    if (python_backend) transport_inputs[[name]] else NULL))
  input_records <- input_records[order(vapply(input_records, `[[`, character(1), "name"), method = "radix")]
  registry_state <- .wb_operation_pack_v2_registry_read_records(
    bundle, operation, inputs, params, input_records, stage_root)
  policies <- stats::setNames(operation$dimension_policies %||% list(),
    vapply(operation$dimension_policies %||% list(), function(x) as.character(x$output)[1], character(1)))
  output_records <- lapply(operation$outputs, function(output) .wb_operation_pack_v2_output_grant(
    output, inputs, .wb_allocate_identifier(paste0(as.character(output$allocated_id_key)[1], "_"),
      12L, purpose = "operation-pack v2 output"), registration = registration,
    dimension_policy = as.character(policies[[as.character(output$name)[1]]]$policy %||% "")[1]))
  transition_value <- list(transition_id = transition_id, session_id = session_id, run_id = run_id,
    checkpoint_generation = generation,
    source_state_identity = .wb_operation_pack_v2_identity_plain("scworkbench.scientific_state.v1",
      .wb_manifest_registry_snapshot(bundle$con)))
  transition_value$transition_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.transition.v2", "transition excluding transition_identity", transition_value)
  identity <- registration$identity
  capability <- list(
    capability_id = .wb_allocate_identifier("capability_", 16L, purpose = "operation-pack v2 capability"),
    mode = "private_staging_write", transition_identity = transition_value$transition_identity,
    session_id = session_id, run_id = run_id, checkpoint_generation = generation,
    source_state_identity = transition_value$source_state_identity,
    staging_root_identity = .wb_operation_pack_v2_identity_plain("scworkbench.operation_pack.staging_root.v1", list(transition = transition_id, root = basename(stage_root))),
    lease_id = .wb_allocate_identifier("lease_", 16L, purpose = "operation-pack v2 lease"),
    pack_identity = identity$pack_identity, distribution_identity = identity$distribution_identity,
    manifest_source_identity = identity$manifest_source_identity,
    operation_definition_identity = identity$operation_definition_identities[[op_name]],
    entry_point_identity = identity$entry_point_identity,
    selected_requirement_set_identity = preflight$selected_identity,
    preflight_report_identity = preflight$preflight_identity,
    reader_grants = c(lapply(input_records, function(x) list(input_name = x$name,
      reader = x$descriptor$reader, descriptor_identity = x$descriptor$descriptor_identity)),
      lapply(registry_state$records, function(x) list(registry_read_name = x$name,
        reader = x$descriptor$reader,
        descriptor_identity = x$descriptor$descriptor_identity))),
    writer_grants = lapply(output_records, function(x) list(output_name = x$name,
      writer = x$descriptor$writer, grant_identity = x$descriptor$grant_identity)),
    single_use = TRUE)
  capability$capability_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.capability.v2", "capability excluding capability_identity", capability)
  request <- list(
    schema = "scworkbench.operation_pack.transition_request.v2", message_type = "request",
    process_protocol_version = "pybench-op-v3", pack_abi_version = "2",
    canonical_json_scheme = .wb_operation_pack_identity_scheme(), transition = transition_value,
    operation_authentication = list(name = op_name, pack_identity = identity$pack_identity,
      manifest_identity = identity$manifest_identity,
      manifest_source_identity = identity$manifest_source_identity,
      distribution_identity = identity$distribution_identity,
      operation_definition_identity = identity$operation_definition_identities[[op_name]],
      entry_point = list(value = identity$entry_point, identity = identity$entry_point_identity)),
    engine_contract = list(implementation = "scworkbench",
      implementation_version = tryCatch(as.character(utils::packageVersion("scworkbench")), error = function(e) "0.1.0"),
      scientific_state_scheme = "scworkbench.scientific_state.v1",
      scientific_state_schema_identity = .wb_operation_pack_v2_identity_plain("scworkbench.scientific_state.schema.v1", .wb_bundle_schema_version()),
      reader_api = "scworkbench.operation_pack.typed_readers.v2",
      writer_api = "scworkbench.operation_pack.staged_writers.v2"),
    dependency_resolution = list(declared_requirement_set_identity = preflight$declared_identity,
      selected_requirement_set_identity = preflight$selected_identity,
      dynamic_resolutions = preflight$dynamic,
      preflight_report_identity = preflight$preflight_identity, network_policy = "deny"),
    inputs = input_records,
    params = if (!length(params)) structure(list(), names = character()) else params,
    outputs = output_records,
    execution_capability = capability)
  if (length(registry_state$records)) request$registry_reads <- registry_state$records
  request$request_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.transition_request.v2", "request excluding request_identity", request)
  attr(request, "operation_pack_v2_transport_inputs") <- transport_inputs
  attr(request, "operation_pack_v2_registry_read_values") <- registry_state$values
  request
}

.wb_operation_pack_v2_schema_assert <- function(value, kind = c("request", "receipt"), code) {
  kind <- match.arg(kind)
  schema <- .wb_operation_pack_v2_read_schema(.wb_operation_pack_v2_transition_schema(kind))
  result <- .wb_json_schema_validate_2020(value, schema)
  if (!isTRUE(result$ok)) .wb_operation_pack_v2_error(code,
    paste0("V2 ", kind, " failed Draft 2020-12 validation at ", result$path, ": ", result$message),
    if (kind == "request") "staging" else "receipt", instance_path = result$path)
  invisible(TRUE)
}

.wb_operation_pack_v2_assert_self_identity <- function(value, field, code, phase) {
  claimed <- value[[field]]
  payload <- value; payload[[field]] <- NULL
  if (is.null(claimed) || !identical(as.character(claimed$sha256 %||% "")[1],
      .wb_operation_pack_sha256(payload))) .wb_operation_pack_v2_error(
    code, paste0("Self identity mismatch at ", field, "."), phase, identity_field = field)
  invisible(TRUE)
}

.wb_operation_pack_v2_request_audit <- function(request, registration, operation) {
  .wb_operation_pack_v2_assert_self_identity(request$transition, "transition_identity",
    "PYBENCH_CAPABILITY_MISMATCH", "staging")
  for (input in request$inputs) .wb_operation_pack_v2_assert_self_identity(input$descriptor,
    "descriptor_identity", "PYBENCH_INPUT_IDENTITY_MISMATCH", "resolution")
  for (registry_read in request$registry_reads %||% list()) {
    .wb_operation_pack_v2_assert_self_identity(registry_read$descriptor,
      "descriptor_identity", "PYBENCH_INPUT_IDENTITY_MISMATCH", "resolution")
  }
  for (output in request$outputs) .wb_operation_pack_v2_assert_self_identity(output$descriptor,
    "grant_identity", "PYBENCH_CAPABILITY_MISMATCH", "staging")
  .wb_operation_pack_v2_assert_self_identity(request$execution_capability, "capability_identity",
    "PYBENCH_CAPABILITY_MISMATCH", "staging")
  .wb_operation_pack_v2_assert_self_identity(request, "request_identity",
    "PYBENCH_CAPABILITY_MISMATCH", "staging")
  identity <- registration$identity; op_name <- operation$qualified_name
  expected_authentication <- list(name = op_name, pack_identity = identity$pack_identity,
    manifest_identity = identity$manifest_identity,
    manifest_source_identity = identity$manifest_source_identity,
    distribution_identity = identity$distribution_identity,
    operation_definition_identity = identity$operation_definition_identities[[op_name]],
    entry_point = list(value = identity$entry_point, identity = identity$entry_point_identity))
  if (!identical(.wb_operation_pack_canonical_json(request$operation_authentication),
      .wb_operation_pack_canonical_json(expected_authentication))) .wb_operation_pack_v2_error(
    "PYBENCH_CAPABILITY_MISMATCH", "Request operation authentication differs from the activated pack.", "staging")
  readers <- c(lapply(request$inputs, function(x) list(input_name = x$name,
    reader = x$descriptor$reader, descriptor_identity = x$descriptor$descriptor_identity)),
    lapply(request$registry_reads %||% list(), function(x) list(
      registry_read_name = x$name, reader = x$descriptor$reader,
      descriptor_identity = x$descriptor$descriptor_identity)))
  writers <- lapply(request$outputs, function(x) list(output_name = x$name,
    writer = x$descriptor$writer, grant_identity = x$descriptor$grant_identity))
  capability <- request$execution_capability
  if (!identical(.wb_operation_pack_canonical_json(readers), .wb_operation_pack_canonical_json(capability$reader_grants)) ||
      !identical(.wb_operation_pack_canonical_json(writers), .wb_operation_pack_canonical_json(capability$writer_grants)) ||
      !identical(capability$transition_identity$sha256, request$transition$transition_identity$sha256) ||
      !identical(capability$source_state_identity$sha256, request$transition$source_state_identity$sha256)) {
    .wb_operation_pack_v2_error("PYBENCH_CAPABILITY_MISMATCH",
      "Capability authentication or named grants differ from the request.", "staging")
  }
  invisible(TRUE)
}

.wb_operation_pack_v2_receipt_audit <- function(receipt, request, registration, operation, preflight) {
  .wb_operation_pack_v2_assert_self_identity(receipt, "receipt_identity",
    "PYBENCH_RECEIPT_MISMATCH", "receipt")
  if (!identical(receipt$transition_identity$sha256, request$transition$transition_identity$sha256) ||
      !identical(receipt$request_identity$sha256, request$request_identity$sha256) ||
      !identical(receipt$capability_identity$sha256, request$execution_capability$capability_identity$sha256)) {
    .wb_operation_pack_v2_error("PYBENCH_RECEIPT_MISMATCH",
      "Receipt transition, request, or capability identity differs from the request.", "receipt")
  }
  grants <- request$outputs
  observed <- c(receipt$outputs %||% list(), receipt$registry_requests %||% list())
  grant_keys <- vapply(grants, function(x) paste(x$name, x$allocated_id,
    x$descriptor$writer, x$descriptor$grant_identity$sha256, sep = "\r"), character(1))
  observed_keys <- vapply(observed, function(x) paste(x$name, x$allocated_id,
    x$descriptor$writer, x$descriptor$grant_identity$sha256, sep = "\r"), character(1))
  if (!setequal(grant_keys, observed_keys) || anyDuplicated(observed_keys) || length(grant_keys) != length(observed_keys)) {
    .wb_operation_pack_v2_error("PYBENCH_RECEIPT_MISMATCH",
      "Receipt outputs and registry requests are not an exact bijection with grants.", "receipt")
  }
  for (item in observed) .wb_operation_pack_v2_assert_self_identity(item$descriptor,
    "observed_descriptor_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
  expected_reads <- request$registry_reads %||% list()
  observed_reads <- receipt$registry_reads %||% list()
  expected_read_keys <- vapply(expected_reads, function(x) paste(x$name,
    x$descriptor$descriptor_identity$sha256,
    x$descriptor$content_identity$sha256,
    x$descriptor$source_identity$sha256,
    x$descriptor$ancestry_identity$sha256,
    x$descriptor$payload_manifest_identity$sha256, sep = "\r"), character(1))
  observed_read_keys <- vapply(observed_reads, function(x) paste(x$name,
    x$descriptor$descriptor_identity$sha256,
    x$descriptor$content_identity$sha256,
    x$descriptor$source_identity$sha256,
    x$descriptor$ancestry_identity$sha256,
    x$descriptor$payload_manifest_identity$sha256, sep = "\r"), character(1))
  if (!identical(expected_read_keys, observed_read_keys) ||
      anyDuplicated(observed_read_keys)) {
    .wb_operation_pack_v2_error("PYBENCH_RECEIPT_MISMATCH",
      "Receipt registry reads are not an exact ordered bijection with grants.",
      "receipt")
  }
  for (item in observed_reads) .wb_operation_pack_v2_assert_self_identity(
    item$descriptor, "observed_descriptor_identity",
    "PYBENCH_RECEIPT_MISMATCH", "receipt")
  for (item in receipt$registry_requests %||% list()) {
    if (!identical(as.character(item$descriptor$kind)[1],
        "cell_set_family_admission")) next
    grant_index <- match(as.character(item$name)[1],
      vapply(grants, `[[`, character(1), "name"))
    expected_order <- grants[[grant_index]]$descriptor$
      expected_cell_order_identity
    dimensions <- as.integer(unlist(item$descriptor$dimensions,
      use.names = FALSE))
    if (!identical(item$descriptor$cell_order_identity, expected_order) ||
        length(dimensions) != 2L ||
        dimensions[[1]] != length(item$descriptor$member_identities)) {
      .wb_operation_pack_v2_error(
        "PYBENCH_RECEIPT_MISMATCH",
        "Cell-set-family receipt contradicts its granted bundle order or member count.",
        "receipt")
    }
  }
  .wb_operation_pack_v2_assert_self_identity(receipt$mutation_manifest, "mutation_identity",
    "PYBENCH_RECEIPT_MISMATCH", "receipt")
  expected_runtime <- .wb_operation_pack_v2_runtime_attestation(registration,
    operation$qualified_name, preflight)
  if (!identical(.wb_operation_pack_canonical_json(receipt$runtime_attestation),
      .wb_operation_pack_canonical_json(expected_runtime))) .wb_operation_pack_v2_error(
    "PYBENCH_RECEIPT_MISMATCH", "Receipt runtime attestation does not bind the audited execution.", "receipt")
  invisible(TRUE)
}

.wb_operation_pack_v2_writer_value <- function(output, value, bundle = NULL) {
  kind <- as.character(output$kind)[1]
  if (identical(kind, "cell_set_admission")) {
    .wb_operation_pack_assert(is.list(value) && is.character(value$cells) && length(value$cells) &&
      !anyNA(value$cells) && all(nzchar(value$cells)) && !anyDuplicated(value$cells),
      "PYBENCH_OUTPUT_INVALID", "Cell-set admission requires unique non-empty cells.",
      class = "wb_operation_pack_v2_error")
    return(list(kind = kind, name = as.character(value$name %||% output$name)[1], cells = as.character(value$cells)))
  }
  if (identical(kind, "cell_set_family_admission")) {
    return(.wb_operation_pack_cell_set_family_normalize(bundle, value))
  }
  .wb_operation_pack_assert(.wb_is_primitive(value) && identical(as.character(value$kind)[1], kind),
    "PYBENCH_OUTPUT_INVALID", paste0("Writer for '", output$name, "' requires a ", kind, " primitive."),
    class = "wb_operation_pack_v2_error")
  if (kind == "model_ref") {
    paths <- c(as.character(value$model_path %||% ""), as.character(value$payload_paths %||% character()))
    paths <- paths[nzchar(paths)]
    if (length(paths) && any(vapply(paths, .wb_path_is_absolute, logical(1)))) .wb_operation_pack_v2_error(
      "PYBENCH_OUTPUT_INVALID", "Model references may not carry absolute pack-supplied paths.", "audit")
  }
  value
}

.wb_operation_pack_v2_capability_adapter <- function(request, operation, inputs, stage_root,
                                                      bundle = NULL,
                                                      registry_read_values = list()) {
  state <- new.env(parent = emptyenv()); state$used <- FALSE; state$writes <- list()
  state$reader_calls <- list()
  declarations <- stats::setNames(operation$outputs, vapply(operation$outputs, `[[`, character(1), "name"))
  grants <- stats::setNames(request$outputs, vapply(request$outputs, `[[`, character(1), "name"))
  readers <- stats::setNames(lapply(names(inputs), function(name) {
    force(name)
    if (identical(as.character(inputs[[name]]$kind %||% "")[1], "matrix")) {
      function(features = NULL, cells = NULL) {
        value <- inputs[[name]]
        allowed_features <- as.character(value$feature_id %||% character())
        allowed_cells <- as.character(value$cell_id %||% character())
        features <- if (is.null(features)) allowed_features else as.character(features)
        cells <- if (is.null(cells)) allowed_cells else as.character(cells)
        if (length(setdiff(features, allowed_features)) || length(setdiff(cells, allowed_cells))) {
          .wb_operation_pack_v2_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
            "Matrix reader selection exceeds the authenticated input descriptor.", "execution")
        }
        values <- if (!is.null(value$values)) {
          value$values[match(features, allowed_features), match(cells, allowed_cells),
            drop = FALSE]
        } else {
          if (is.null(bundle)) .wb_operation_pack_v2_error(
            "PYBENCH_INPUT_IDENTITY_MISMATCH",
            "Symbolic matrix reader has no core bundle binding.", "execution")
          wb_slice(bundle, matrix_id = value$matrix_id,
            features = features, cells = cells)
        }
        dimnames(values) <- list(features, cells)
        state$reader_calls[[length(state$reader_calls) + 1L]] <- list(
          category = "input", input = name,
          features = as.character(features), cells = as.character(cells))
        structure(list(kind = "matrix", matrix_id = value$matrix_id,
          values = values, dimensions = as.integer(dim(values)),
          feature_id = features, cell_id = cells,
          storage_profile = value$storage_profile,
          meta = value$meta %||% list()), class = "wb_primitive")
      }
    } else {
      function(...) {
        if (length(list(...))) .wb_operation_pack_v2_error(
          "PYBENCH_CAPABILITY_MISMATCH",
          "Only read_matrix accepts a typed selection.", "execution")
        state$reader_calls[[length(state$reader_calls) + 1L]] <- list(
          category = "input", input = name)
        .wb_operation_pack_v2_deep_copy(inputs[[name]])
      }
    }
  }), names(inputs))
  registry_readers <- stats::setNames(lapply(names(registry_read_values), function(name) {
    force(name)
    function(...) {
      if (isTRUE(state$used) || length(list(...))) {
        .wb_operation_pack_v2_error("PYBENCH_CAPABILITY_MISMATCH",
          "Registry readers are private, no-argument and single-use.", "execution")
      }
      prior <- Filter(function(x) identical(x$category %||% "", "registry_read") &&
        identical(as.character(x$name)[1], name), state$reader_calls)
      if (length(prior)) .wb_operation_pack_v2_error(
        "PYBENCH_CAPABILITY_MISMATCH",
        paste0("Registry reader '", name, "' was consumed more than once."),
        "execution", registry_read = name)
      state$reader_calls[[length(state$reader_calls) + 1L]] <- list(
        category = "registry_read", name = name)
      value <- .wb_operation_pack_v2_deep_copy(registry_read_values[[name]])
      structure(value, class = c("wb_operation_pack_feature_set_registry", "list"))
    }
  }), names(registry_read_values))
  readers <- c(readers, registry_readers)
  write_one <- function(writer, name, value, semantic_metadata = list()) {
    if (isTRUE(state$used)) .wb_operation_pack_v2_error("PYBENCH_CAPABILITY_MISMATCH",
      "Capability has already been consumed.", "execution")
    name <- as.character(name)[1]
    declaration <- declarations[[name]]; grant <- grants[[name]]
    if (is.null(declaration) || is.null(grant) || !identical(grant$descriptor$writer, writer)) {
      .wb_operation_pack_v2_error("PYBENCH_CAPABILITY_MISMATCH",
        paste0("Writer '", writer, "' is not granted for output '", name, "'."), "execution", output = name)
    }
    if (!is.null(state$writes[[name]])) .wb_operation_pack_v2_error("PYBENCH_RECEIPT_MISMATCH",
      paste0("Output '", name, "' was written more than once."), "receipt", output = name)
    value <- .wb_operation_pack_v2_writer_value(declaration, value,
      bundle = bundle)
    output_dir <- file.path(stage_root, "outputs", name)
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
    payload <- file.path(output_dir, "payload.rds")
    saveRDS(value, payload, version = 3L, compress = FALSE)
    state$writes[[name]] <- list(value = value, payload = payload,
      semantic_metadata = semantic_metadata %||% list(), writer = writer)
    invisible(list(name = name, allocated_id = grant$allocated_id,
      grant_identity = grant$descriptor$grant_identity))
  }
  writers <- list(
    write_matrix = function(name, value, semantic_metadata = list()) write_one("write_matrix", name, value, semantic_metadata),
    write_space = function(name, value, semantic_metadata = list()) write_one("write_space", name, value, semantic_metadata),
    write_space_2d = function(name, value, semantic_metadata = list()) write_one("write_space_2d", name, value, semantic_metadata),
    write_model_ref = function(name, value, semantic_metadata = list()) write_one("write_model_ref", name, value, semantic_metadata),
    write_terminal_primitive = function(name, value, semantic_metadata = list()) write_one("write_terminal_primitive", name, value, semantic_metadata),
    write_path_2d_family = function(name, value, semantic_metadata = list()) write_one("write_path_2d_family", name, value, semantic_metadata),
    write_space_path_family = function(name, value, semantic_metadata = list()) write_one("write_space_path_family", name, value, semantic_metadata),
    request_cell_set_admission = function(name, value, semantic_metadata = list()) write_one("request_cell_set_admission", name, value, semantic_metadata),
    request_cell_set_family_admission = function(name, value, semantic_metadata = list()) write_one("request_cell_set_family_admission", name, value, semantic_metadata))
  list(readers = readers, writers = writers, state = state, consume = function() { state$used <- TRUE; invisible(TRUE) })
}

.wb_operation_pack_v2_chunk_observation <- function(operation, params, reader_calls, inputs) {
  chunk <- operation$chunking %||% NULL
  if (is.null(chunk)) return(NULL)
  sequence <- as.character(unlist(params[[as.character(chunk$sequence_parameter)[1]]],
    use.names = FALSE))
  if (!length(sequence)) sequence <- as.character(
    inputs[[as.character(chunk$input)[1]]]$feature_id %||% character())
  size <- as.integer(params[[as.character(chunk$size_parameter)[1]]])[1]
  expected <- if (!length(sequence)) list() else split(sequence,
    ceiling(seq_along(sequence) / size))
  observed <- Filter(function(x) identical(as.character(x$input)[1],
    as.character(chunk$input)[1]), reader_calls)
  batches <- lapply(observed, function(x) as.character(x$features))
  valid <- length(observed) == length(expected) &&
    identical(unname(batches), unname(expected)) &&
    all(lengths(batches) > 0L & lengths(batches) <= size)
  if (!valid) .wb_operation_pack_v2_error("PYBENCH_CAPABILITY_MISMATCH",
    "Observed matrix-reader calls do not implement the authenticated chunk declaration.",
    "execution", expected_batches = expected, observed_batches = batches)
  list(axis = as.character(chunk$axis)[1],
    requested_chunk_size = size,
    observed_call_count = length(observed),
    observed_batch_sizes = as.integer(lengths(batches)),
    observed_batches = unname(batches))
}

.wb_operation_pack_v2_observed_descriptor <- function(grant, write) {
  value <- write$value; descriptor <- grant$descriptor
  kind <- descriptor$kind
  dimensions <- .wb_operation_pack_v2_dimensions(value, kind)
  expected_dimensions <- as.integer(unlist(descriptor$expected_dimensions, use.names = FALSE))
  dynamic_dimensions <- (kind %in% c("feature_table", "obs_table") ||
    identical(kind, "cell_set_family_admission")) &&
    identical(expected_dimensions, c(0L, 0L))
  if (!dynamic_dimensions && !identical(as.integer(dimensions), expected_dimensions)) .wb_operation_pack_v2_error(
    "PYBENCH_OUTPUT_INVALID", paste0("Output '", grant$name, "' dimensions do not match its grant."),
    "audit", output = grant$name, expected = descriptor$expected_dimensions, observed = dimensions)
  cells <- if (identical(kind, "cell_set_admission")) value$cells else .wb_operation_pack_v2_primitive_cells(value)
  features <- if (.wb_is_primitive(value)) .wb_operation_pack_v2_primitive_features(value) else character()
  if (identical(kind, "cell_set_admission")) {
    observed <- list(
      category = descriptor$category, kind = kind, storage_profile = descriptor$storage_profile,
      writer = descriptor$writer, grant_identity = descriptor$grant_identity,
      dimensions = unname(as.list(as.integer(dimensions))), alignment = "cell_ordered",
      cell_order_identity = .wb_operation_pack_v2_identity_scoped("scworkbench.cell_order.v1",
        "ordered admitted cell identifiers", cells),
      ancestry_identity = .wb_operation_pack_v2_identity_scoped("scworkbench.provenance.ancestry.v1",
        "registry request ancestry", descriptor$expected_ancestry_identity),
      membership_identity = .wb_operation_pack_v2_identity_scoped("scworkbench.cell_set.membership.v1",
        "ordered exact membership", cells),
      semantic_validation = list(constraints_identity = .wb_operation_pack_v2_identity_scoped(
        "scworkbench.operation_pack.semantic_constraints.v2", "cell-set admission constraints",
        descriptor$semantic_constraints), status = "passed"))
    observed$observed_descriptor_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.observed_registry_request.v2",
      "descriptor excluding observed_descriptor_identity", observed)
    return(observed)
  }
  if (identical(kind, "cell_set_family_admission")) {
    family_identity <- attr(value, "family_identity") %||%
      .wb_operation_pack_v2_identity_scoped(
        "scworkbench.cell_set.family_admission.v1",
        "normalized family payload", value)
    member_identities <- attr(value, "member_identities") %||%
      lapply(value$sets %||% list(), function(item) list(
        name = item$name,
        membership_identity = .wb_operation_pack_v2_identity_scoped(
          "scworkbench.cell_set.membership.v1",
          "ordered exact membership", item$cells)))
    source_identity <- attr(value, "source_identity") %||%
      .wb_operation_pack_v2_identity_scoped(
        "scworkbench.cell_set.family_source.v1",
        "normalized source metadata", value$source)
    observed <- list(
      category = descriptor$category, kind = kind,
      storage_profile = descriptor$storage_profile,
      writer = descriptor$writer, grant_identity = descriptor$grant_identity,
      dimensions = unname(as.list(as.integer(dimensions))),
      alignment = "family_name_then_core_cell_order",
      cell_order_identity = descriptor$expected_cell_order_identity,
      ancestry_identity = .wb_operation_pack_v2_identity_scoped(
        "scworkbench.provenance.ancestry.v1",
        "registry request ancestry", descriptor$expected_ancestry_identity),
      family_identity = family_identity,
      member_identities = unname(member_identities),
      source_identity = source_identity,
      semantic_validation = list(
        constraints_identity = .wb_operation_pack_v2_identity_scoped(
          "scworkbench.operation_pack.semantic_constraints.v2",
          "cell-set-family admission constraints",
          descriptor$semantic_constraints), status = "passed"))
    observed$observed_descriptor_identity <-
      .wb_operation_pack_v2_identity_scoped(
        "scworkbench.operation_pack.observed_registry_request.v2",
        "descriptor excluding observed_descriptor_identity", observed)
    return(observed)
  }
  observed <- list(
    category = descriptor$category, kind = kind, storage_profile = descriptor$storage_profile,
    writer = descriptor$writer, grant_identity = descriptor$grant_identity,
    dimensions = unname(as.list(as.integer(dimensions))), alignment = descriptor$expected_alignment,
    ancestry_identity = descriptor$expected_ancestry_identity,
    model_linkage = descriptor$expected_model_linkage,
    content_identity = .wb_operation_pack_v2_identity_plain(paste0("scworkbench.", kind, ".content.v1"), unclass(value)),
    payload_manifest_identity = .wb_operation_pack_v2_identity_plain("scworkbench.operation_pack.payload_manifest.v2",
      list(path = paste0("outputs/", grant$name, "/payload.rds"), size = as.numeric(file.info(write$payload)$size), sha256 = .wb_operation_pack_v2_file_sha256(write$payload))),
    semantic_metadata_identity = .wb_operation_pack_v2_identity_plain("scworkbench.operation_pack.semantic_metadata.v2", write$semantic_metadata),
    semantic_validation = list(constraints_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.operation_pack.semantic_constraints.v2", descriptor$semantic_constraints), status = "passed"))
  if (kind %in% c("matrix", "space", "space_2d", "cell_vector", "cell_vector_family", "relation_family")) {
    observed$cell_order_identity <- .wb_operation_pack_v2_identity_plain("scworkbench.cell_order.v1", cells)
  }
  if (kind %in% c("matrix", "feature_table")) observed$feature_order_identity <- .wb_operation_pack_v2_identity_plain("scworkbench.feature_order.v1", features)
  if (kind %in% c("path_2d_family", "space_path_family")) {
    order_value <- if (kind == "path_2d_family") list(value$key, value$point) else list(value$space_id, value$path_id, value$point, value$dim)
    observed$row_order_identity <- .wb_operation_pack_v2_identity_plain("scworkbench.row_order.v1", order_value)
  }
  if (kind == "space_path_family") observed$linked_space_identity <- descriptor$expected_linked_space_identity
  if (kind == "model_ref") {
    observed$model_linkage_identity <- .wb_operation_pack_v2_identity_plain("scworkbench.model_linkage.v1", unclass(value))
    observed$contained_payload <- list(contained = TRUE, no_symlinks = TRUE,
      payload_tree_identity = .wb_operation_pack_v2_identity_plain("scworkbench.operation_pack.contained_payload.v2", unclass(value)))
  }
  scheme <- if (identical(kind, "cell_set_admission")) "scworkbench.operation_pack.observed_registry_request.v2" else "scworkbench.operation_pack.observed_output.v2"
  observed$observed_descriptor_identity <- .wb_operation_pack_v2_identity_scoped(
    scheme, "descriptor excluding observed_descriptor_identity", observed)
  observed
}

.wb_operation_pack_v2_receipt <- function(request, registration, operation, writes, preflight,
                                           registry_reads = list()) {
  grants <- stats::setNames(request$outputs, vapply(request$outputs, `[[`, character(1), "name"))
  expected <- names(grants)
  if (!setequal(names(writes), expected) || anyDuplicated(names(writes)) || length(writes) != length(expected)) {
    .wb_operation_pack_v2_error("PYBENCH_RECEIPT_MISMATCH",
      paste0("Returned output closure differs from grants; expected [", paste(sort(expected), collapse = ","),
        "] observed [", paste(sort(names(writes)), collapse = ","), "]."), "receipt")
  }
  outputs <- list(); registry <- list()
  for (name in expected) {
    grant <- grants[[name]]
    rec <- list(name = name, allocated_id = grant$allocated_id,
      descriptor = .wb_operation_pack_v2_observed_descriptor(grant, writes[[name]]))
    if (identical(grant$descriptor$category, "core_registry_request")) registry[[length(registry) + 1L]] <- rec
    else outputs[[length(outputs) + 1L]] <- rec
  }
  entries <- lapply(expected, function(name) list(path = paste0("outputs/", name, "/payload.rds"),
    sha256 = .wb_operation_pack_v2_file_sha256(writes[[name]]$payload)))
  mutation <- list(entries_identity = .wb_operation_pack_v2_identity_plain(
    "scworkbench.operation_pack.mutation_entries.v2", entries), entry_count = as.integer(length(entries)), unexpected_entries = 0L)
  mutation$mutation_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.mutation_manifest.v2", "mutation manifest excluding mutation_identity", mutation)
  receipt <- list(
    schema = "scworkbench.operation_pack.transition_receipt.v2", message_type = "receipt",
    process_protocol_version = "pybench-op-v3", pack_abi_version = "2",
    canonical_json_scheme = .wb_operation_pack_identity_scheme(),
    status = "ok", transition_id = request$transition$transition_id,
    session_id = request$transition$session_id, run_id = request$transition$run_id,
    transition_identity = request$transition$transition_identity,
    request_identity = request$request_identity,
    capability_identity = request$execution_capability$capability_identity,
    outputs = outputs, registry_requests = registry, mutation_manifest = mutation,
    runtime_attestation = .wb_operation_pack_v2_runtime_attestation(registration, operation$qualified_name, preflight))
  if (length(registry_reads)) receipt$registry_reads <- registry_reads
  receipt$receipt_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.transition_receipt.v2", "receipt excluding receipt_identity", receipt)
  receipt
}

.wb_operation_pack_v2_atomic_json <- function(value, path) {
  tmp <- paste0(path, ".tmp-", .wb_allocate_identifier("", 12L, purpose = "operation-pack v2 JSON publication"))
  on.exit(if (file.exists(tmp)) unlink(tmp, force = TRUE), add = TRUE)
  # Preserve IEEE-754 values across the authenticated JSON transport. The
  # jsonlite default rounds to four decimal places, which can make a staged
  # file-backed matrix differ from the descriptor identity computed before
  # serialization.
  jsonlite::write_json(value, tmp, auto_unbox = TRUE, pretty = TRUE,
    null = "null", na = "null", digits = NA)
  .wb_operation_pack_assert(file.rename(tmp, path), "PYBENCH_PUBLICATION_FAILED",
    paste0("Could not publish ", basename(path), "."), class = "wb_operation_pack_v2_error")
  invisible(TRUE)
}

.wb_operation_pack_v2_record_validate <- function(path, load_payloads = FALSE) {
  receipt_path <- file.path(path, "receipt.json")
  request_path <- file.path(path, "request.json")
  state_path <- file.path(path, "state.json")
  if (!file.exists(receipt_path) || !file.exists(request_path) || !file.exists(state_path)) return(list(ok = FALSE, code = "incomplete_record"))
  request <- tryCatch(jsonlite::read_json(request_path, simplifyVector = FALSE), error = identity)
  receipt <- tryCatch(jsonlite::read_json(receipt_path, simplifyVector = FALSE), error = identity)
  state <- tryCatch(jsonlite::read_json(state_path, simplifyVector = FALSE), error = identity)
  if (inherits(request, "error") || inherits(receipt, "error") || inherits(state, "error")) return(list(ok = FALSE, code = "invalid_json"))
  request_id <- request$request_identity; request$request_identity <- NULL
  receipt_id <- receipt$receipt_identity; receipt$receipt_identity <- NULL
  if (!identical(request_id$sha256, .wb_operation_pack_sha256(request)) ||
      !identical(receipt_id$sha256, .wb_operation_pack_sha256(receipt))) return(list(ok = FALSE, code = "identity_mismatch"))
  if (identical(as.character(request$schema %||% "")[1],
      "scworkbench.operation_pack.transition_request.v3")) {
    request$request_identity <- request_id
    receipt$receipt_identity <- receipt_id
    v3 <- .wb_operation_pack_v3_record_validate(request, receipt, path,
      load_payloads = load_payloads)
    if (!isTRUE(v3$ok)) return(v3)
    request$request_identity <- NULL
    receipt$receipt_identity <- NULL
  }
  observed <- c(receipt$outputs %||% list(), receipt$registry_requests %||% list())
  for (item in observed) {
    python_payload <- identical(as.character(
      receipt$runtime_attestation$backend %||% "R")[1], "Python")
    payload_root <- if (python_payload && identical(as.character(item$descriptor$category)[1],
        "core_registry_request")) "registry_requests" else "outputs"
    payload <- file.path(path, payload_root, item$name,
      if (python_payload) "payload.json" else "payload.rds")
    if (!file.exists(payload)) return(list(ok = FALSE, code = "payload_missing", output = item$name))
    manifest <- item$descriptor$payload_manifest_identity %||% NULL
    if (!is.null(manifest)) {
      expected <- manifest$sha256
      actual <- .wb_operation_pack_sha256(list(path = paste0(payload_root, "/",
        item$name, "/", if (python_payload) "payload.json" else "payload.rds"),
        size = as.numeric(file.info(payload)$size), sha256 = .wb_operation_pack_v2_file_sha256(payload)))
      if (!identical(expected, actual)) return(list(ok = FALSE, code = "payload_identity_mismatch", output = item$name))
    }
    if (isTRUE(load_payloads)) {
      value <- tryCatch(if (python_payload) {
        raw <- readChar(payload, nchars = file.info(payload)$size, useBytes = TRUE)
        .wb_operation_pack_v2_assert_strict_json(raw)
        .wb_operation_pack_parse_canonical_json(raw)
      } else readRDS(payload), error = identity)
      if (inherits(value, "error")) return(list(ok = FALSE, code = "payload_unreadable", output = item$name))
      actual <- if (identical(as.character(item$descriptor$kind)[1],
          "cell_set_family_admission")) {
        # The writer has already stored the normalized family payload; bundle
        # universe validation is repeated by staging, promotion and recipient
        # audit where a bundle handle is available.
        .wb_operation_pack_sha256(value)
      } else .wb_operation_pack_sha256(if (python_payload) value else unclass(value))
      expected_content <- item$descriptor$content_identity$sha256 %||%
        item$descriptor$family_identity$sha256 %||% NULL
      if (!is.null(expected_content) && !identical(actual, expected_content)) return(list(ok = FALSE, code = "content_identity_mismatch", output = item$name))
    }
  }
  request_reads <- request$registry_reads %||% list()
  receipt_reads <- receipt$registry_reads %||% list()
  if (length(request_reads) != length(receipt_reads) ||
      !identical(vapply(request_reads, `[[`, character(1), "name"),
        vapply(receipt_reads, `[[`, character(1), "name"))) {
    return(list(ok = FALSE, code = "registry_read_bijection_mismatch"))
  }
  for (i in seq_along(request_reads)) {
    request_read <- request_reads[[i]]; receipt_read <- receipt_reads[[i]]
    name <- as.character(request_read$name)[1]
    descriptor_ok <- tryCatch({
      .wb_operation_pack_v2_assert_self_identity(request_read$descriptor,
        "descriptor_identity", "PYBENCH_INPUT_IDENTITY_MISMATCH", "reopen")
      .wb_operation_pack_v2_assert_self_identity(receipt_read$descriptor,
        "observed_descriptor_identity", "PYBENCH_RECEIPT_MISMATCH", "reopen")
      identical(as.integer(receipt_read$descriptor$use_count)[1], 1L) &&
        identical(receipt_read$descriptor$descriptor_identity,
          request_read$descriptor$descriptor_identity) &&
        identical(receipt_read$descriptor$content_identity,
          request_read$descriptor$content_identity) &&
        identical(receipt_read$descriptor$source_identity,
          request_read$descriptor$source_identity) &&
        identical(receipt_read$descriptor$ancestry_identity,
          request_read$descriptor$ancestry_identity) &&
        identical(receipt_read$descriptor$payload_manifest_identity,
          request_read$descriptor$payload_manifest_identity)
    }, error = function(error) FALSE)
    if (!isTRUE(descriptor_ok)) return(list(ok = FALSE,
      code = "registry_read_descriptor_identity_mismatch", output = name))
    payload <- file.path(path, "registry_reads", name, "payload.json")
    if (!file.exists(payload)) return(list(ok = FALSE,
      code = "registry_read_payload_missing", output = name))
    payload_manifest <- list(path = paste0("registry_reads/", name, "/payload.json"),
      size = as.numeric(file.info(payload)$size),
      sha256 = .wb_operation_pack_v2_file_sha256(payload))
    observed_manifest <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.payload_manifest.v2",
      "registry read payload manifest", payload_manifest)
    if (!identical(observed_manifest,
        request_read$descriptor$payload_manifest_identity) ||
        !identical(receipt_read$descriptor$payload_manifest_identity,
          request_read$descriptor$payload_manifest_identity)) {
      return(list(ok = FALSE, code = "registry_read_payload_identity_mismatch",
        output = name))
    }
    if (isTRUE(load_payloads)) {
      value <- tryCatch({
        raw <- readChar(payload, nchars = file.info(payload)$size, useBytes = TRUE)
        .wb_operation_pack_v2_assert_strict_json(raw)
        .wb_operation_pack_parse_canonical_json(raw)
      }, error = identity)
      if (inherits(value, "error")) return(list(ok = FALSE,
        code = "registry_read_payload_unreadable", output = name))
      validated <- tryCatch(
        .wb_operation_pack_v2_feature_set_registry_snapshot_validate(value),
        error = identity)
      if (inherits(validated, "error")) return(list(ok = FALSE,
        code = "registry_read_payload_invalid", output = name))
      content <- .wb_operation_pack_v2_identity_scoped(
        "scworkbench.feature_set_registry.snapshot.v1",
        "canonical matrix-bound registry snapshot", value)
      source <- .wb_operation_pack_v2_identity_scoped(
        "scworkbench.feature_set_registry.source.v1",
        "ordered registry source state", list(matrix_id = value$matrix_id,
          feature_universe = value$feature_universe, sets = value$sets))
      if (!identical(content, request_read$descriptor$content_identity) ||
          !identical(source, request_read$descriptor$source_identity) ||
          !identical(receipt_read$descriptor$content_identity, content) ||
          !identical(receipt_read$descriptor$source_identity, source)) {
        return(list(ok = FALSE, code = "registry_read_content_identity_mismatch",
          output = name))
      }
    }
  }
  list(ok = TRUE, request = request, request_identity = request_id,
    receipt = receipt, receipt_identity = receipt_id, state = state)
}

.wb_operation_pack_v2_recover <- function(bundle) {
  root <- .wb_operation_pack_v2_store(bundle)
  pending <- file.path(root, ".pending")
  if (dir.exists(pending)) {
    entries <- list.dirs(pending, recursive = FALSE, full.names = TRUE)
    for (entry in entries) unlink(entry, recursive = TRUE, force = TRUE)
  }
  if (!dir.exists(root)) return(invisible(TRUE))
  records <- setdiff(list.dirs(root, recursive = FALSE, full.names = TRUE), pending)
  for (record in records) {
    result <- .wb_operation_pack_v2_record_validate(record, load_payloads = FALSE)
    state <- as.character(result$state$state %||% "")[1]
    if (isTRUE(result$ok) && identical(state, "published")) {
      complete <- .wb_operation_pack_v2_record_validate(record, load_payloads = TRUE)
      if (isTRUE(complete$ok)) {
        .wb_operation_pack_v2_atomic_json(list(
          schema = "scworkbench.operation_pack.transition_state.v2", state = "reopened",
          transition_id = basename(record), receipt_identity = result$receipt_identity),
          file.path(record, "state.json"))
      } else unlink(record, recursive = TRUE, force = TRUE)
    } else if (!isTRUE(result$ok) || !state %in% c("reopened")) {
      unlink(record, recursive = TRUE, force = TRUE)
    }
  }
  invisible(TRUE)
}

.wb_operation_pack_v2_assert_recipient <- function(bundle) {
  pending <- .wb_operation_pack_v2_pending_root(bundle)
  residue <- if (dir.exists(pending)) list.dirs(pending, recursive = FALSE, full.names = TRUE) else character()
  .wb_operation_pack_assert(!length(residue), "PYBENCH_REOPEN_VALIDATION_FAILED",
    "Recipient bundle contains an interrupted ABI v2 private generation.",
    class = "wb_operation_pack_v2_error")
  root <- .wb_operation_pack_v2_store(bundle)
  if (!dir.exists(root)) return(invisible(TRUE))
  records <- setdiff(list.dirs(root, recursive = FALSE, full.names = TRUE), pending)
  for (record in records) {
    result <- .wb_operation_pack_v2_record_validate(record, load_payloads = FALSE)
    .wb_operation_pack_assert(isTRUE(result$ok) && identical(result$state$state, "reopened"),
      "PYBENCH_REOPEN_VALIDATION_FAILED",
      paste0("Recipient ABI v2 transition record is invalid: ", basename(record), " (", result$code %||% "not_reopened", ")."),
      class = "wb_operation_pack_v2_error")
    if (identical(as.character(result$request$schema %||% "")[1],
        "scworkbench.operation_pack.transition_request.v3"))
      .wb_operation_pack_v3_retained_provenance_assert_current(bundle,
        result$request, record)
  }
  .wb_operation_pack_v2_assert_registry_receipts(bundle)
  invisible(TRUE)
}

.wb_operation_pack_v2_execute <- function(bundle, op_name, inputs, params = list(),
                                           session_id = NULL, run_id = NULL,
                                           checkpoint_generation = "ephemeral",
                                           effective_cells = NULL) {
  .wb_assert_bundle_writable(bundle, "operation-pack v2 transition")
  op_name <- as.character(op_name)[1]
  record <- .wb_operation_pack_registry$operations[[op_name]]
  if (is.null(record)) .wb_operation_pack_v2_error("OPERATION_PACK_REQUIRED",
    paste0("Exact operation pack required for '", op_name, "'."), "resolution")
  registration <- .wb_operation_pack_registry$packs[[record$namespace]]$registration
  if (is.null(registration) || !inherits(registration, "wb_operation_pack_registration_v2")) {
    .wb_operation_pack_v2_error("OPERATION_PACK_INCOMPATIBLE", "Activated handler is not ABI v2.", "resolution")
  }
  abi_v3 <- inherits(registration, "wb_operation_pack_registration_v3")
  operation <- if (abi_v3) record$definition$v3_definition else
    record$definition$v2_definition
  declarations <- stats::setNames(operation$inputs, vapply(operation$inputs, `[[`, character(1), "name"))
  required <- vapply(operation$inputs, function(x) isTRUE(x$required), logical(1))
  required_names <- vapply(operation$inputs[required], `[[`, character(1), "name")
  if (!is.list(inputs) || is.null(names(inputs)) || !all(required_names %in% names(inputs)) ||
      any(!names(inputs) %in% names(declarations)) || anyDuplicated(names(inputs))) {
    .wb_operation_pack_v2_error("PYBENCH_INPUT_IDENTITY_MISMATCH", "Resolved input closure does not match the manifest.", "resolution")
  }
  for (name in names(inputs)) .wb_assert_kind(inputs[[name]], declarations[[name]]$kind,
    where = paste0(" for ABI v2 input '", name, "'"))
  params_result <- .wb_json_schema_validate_2020(params, operation$params_schema)
  if (!isTRUE(params_result$ok)) .wb_operation_pack_v2_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
    paste0("Parameters fail the admitted schema at ", params_result$path, ": ", params_result$message), "resolution")
  for (binding in operation$parameter_bindings %||% list()) {
    if (identical(as.character(binding$policy)[1], "feature_ids_or_all_v1") &&
        is.null(params[[as.character(binding$parameter)[1]]])) {
      params[[as.character(binding$parameter)[1]]] <- unname(as.list(as.character(
        inputs[[as.character(binding$input)[1]]]$feature_id %||% character())))
    }
  }
  transition_id <- .wb_allocate_identifier("transition_", 16L, purpose = "operation-pack v2 transition")
  session_id <- as.character(session_id %||% .wb_allocate_identifier("session_", 12L, purpose = "operation-pack v2 session"))[1]
  run_id <- as.character(run_id %||% .wb_allocate_identifier("run_", 12L, purpose = "operation-pack v2 run"))[1]
  generation <- as.character(checkpoint_generation)[1]
  pending_root <- .wb_operation_pack_v2_pending_root(bundle)
  dir.create(pending_root, recursive = TRUE, showWarnings = FALSE)
  stage <- file.path(pending_root, .wb_operation_pack_v2_safe_component(transition_id, "transition_id"))
  final <- file.path(.wb_operation_pack_v2_store(bundle), basename(stage))
  if (dir.exists(stage) || dir.exists(final)) .wb_operation_pack_v2_error("PYBENCH_STALE_STAGING_IDENTITY",
    "Transition identifier already exists.", "staging")
  dir.create(stage, recursive = TRUE, showWarnings = FALSE)
  published <- FALSE
  on.exit({
    if (dir.exists(stage)) unlink(stage, recursive = TRUE, force = TRUE)
    if (!published && dir.exists(final)) unlink(final, recursive = TRUE, force = TRUE)
    .wb_operation_pack_v2_cleanup_empty(bundle)
  }, add = TRUE)
  .wb_operation_pack_v2_fault("resolved", transition_id = transition_id)
  python_backend <- identical(as.character(registration$identity$backend)[1], "Python")
  transport_inputs <- if (python_backend) stats::setNames(lapply(names(inputs),
    function(name) .wb_operation_pack_v2_transport_value(inputs[[name]],
      declarations[[name]]$kind)), names(inputs)) else NULL
  preflight <- .wb_operation_pack_v2_preflight(operation, inputs, params,
    registration = registration, transport_inputs = transport_inputs)
  .wb_operation_pack_v2_fault("preflighted", transition_id = transition_id)
  source_refs <- attr(inputs, "operation_pack_v3_source_refs") %||% list()
  request <- if (abi_v3) .wb_operation_pack_v3_request(bundle,
    registration, operation, inputs, params, transition_id, session_id,
    run_id, generation, preflight, stage, effective_cells, source_refs) else
    .wb_operation_pack_v2_request(bundle, registration, operation, inputs,
      params, transition_id, session_id, run_id, generation, preflight, stage)
  if (abi_v3) {
    .wb_operation_pack_v3_schema_assert(request, "request",
      "PYBENCH_CAPABILITY_MISMATCH")
    .wb_operation_pack_v3_request_audit(request, registration, operation)
  } else {
    .wb_operation_pack_v2_schema_assert(request, "request",
      "PYBENCH_CAPABILITY_MISMATCH")
    .wb_operation_pack_v2_request_audit(request, registration, operation)
  }
  .wb_operation_pack_v2_atomic_json(request, file.path(stage, "request.json"))
  if (python_backend) {
    staged_inputs <- attr(request, "operation_pack_v2_transport_inputs") %||%
      transport_inputs
    if (abi_v3) {
      typed_input_names <- unique(vapply(request$typed_slice_grants %||% list(),
        `[[`, character(1), "input_name"))
      staged_inputs <- staged_inputs[setdiff(names(staged_inputs),
        typed_input_names)]
    }
    .wb_operation_pack_v2_python_stage_inputs(stage, staged_inputs)
  }
  .wb_operation_pack_v2_atomic_json(list(schema = "scworkbench.operation_pack.transition_state.v2",
    state = "staged", transition_id = transition_id), file.path(stage, "state.json"))
  .wb_operation_pack_v2_fault("staged", transition_id = transition_id)
  .wb_operation_pack_v2_dynamic_reread(operation, inputs, preflight)
  .wb_operation_pack_v2_registry_reads_assert_current(bundle, operation,
    inputs, params, request$registry_reads %||% list())
  if (abi_v3) .wb_operation_pack_v3_provenance_reads_assert_current(bundle,
    operation, inputs, source_refs, request, params)
  if (abi_v3) .wb_operation_pack_v3_typed_slice_sources_assert_current(
    bundle, request)
  .wb_operation_pack_v2_fault("before_dispatch", transition_id = transition_id)
  if (python_backend) {
    process_result <- if (abi_v3) .wb_operation_pack_v3_python_dispatch(
      request, registration, stage, bundle = bundle) else .wb_operation_pack_v2_python_dispatch(
        request, registration, stage)
    receipt <- process_result$receipt
    unlink(file.path(stage, "inputs"), recursive = TRUE, force = TRUE)
  } else {
    adapter <- if (abi_v3) .wb_operation_pack_v3_capability_adapter(request,
      operation, inputs, stage, bundle = bundle,
      registry_read_values = attr(request,
        "operation_pack_v2_registry_read_values") %||% list(),
      provenance_read_values = attr(request,
        "operation_pack_v3_provenance_read_values") %||% list()) else
      .wb_operation_pack_v2_capability_adapter(request, operation, inputs,
        stage, bundle = bundle, registry_read_values = attr(request,
          "operation_pack_v2_registry_read_values") %||% list())
    runner <- registration$runners[[op_name]]
    result <- tryCatch(runner(readers = adapter$readers, writers = adapter$writers,
      params = .wb_operation_pack_v2_deep_copy(params),
      context = list(transition_id = transition_id, session_id = session_id, run_id = run_id,
        checkpoint_generation = generation, network_policy = "deny",
        typed_slice_reads = stats::setNames(lapply(
          request$typed_slice_grants %||% list(), function(x) list(
            name = x$name, input_name = x$input_name,
            chunk_axis = x$chunk_axis,
            requested_chunk_size = x$requested_chunk_size,
            call_discipline = x$call_discipline,
            cells = attr(x, "operation_pack_v3_cells"),
            features = attr(x, "operation_pack_v3_features"))), vapply(
              request$typed_slice_grants %||% list(), `[[`, character(1),
              "name")),
        effective_cells = unname(as.character(effective_cells %||%
          .wb_operation_pack_v2_primitive_cells(inputs[[1]]))))), error = identity)
    if (inherits(result, "error")) {
      adapter$consume()
      if (inherits(result, "wb_operation_pack_v2_error")) stop(result)
      .wb_operation_pack_v2_error("PYBENCH_PROCESS_FAILED",
        paste0("R operation-pack runner failed: ", conditionMessage(result)), "execution")
    }
    typed_slice_usage <- if (abi_v3)
      .wb_operation_pack_v3_typed_slice_usage(adapter, request) else list()
    reader_observation <- if (abi_v3) NULL else .wb_operation_pack_v2_chunk_observation(operation,
        params, adapter$state$reader_calls, inputs)
    registry_read_observations <- .wb_operation_pack_v2_registry_read_observations(
      request, adapter$state$reader_calls)
    provenance_read_observations <- if (abi_v3)
      .wb_operation_pack_v3_provenance_observations(request,
        adapter$state$reader_calls) else list()
    adapter$consume()
    receipt <- if (abi_v3) .wb_operation_pack_v3_receipt(request,
      registration, operation, adapter$state$writes, preflight, inputs,
      registry_read_observations, provenance_read_observations,
      typed_slice_usage = typed_slice_usage) else .wb_operation_pack_v2_receipt(request,
        registration, operation, adapter$state$writes, preflight,
        registry_read_observations)
  }
  .wb_operation_pack_v2_fault("receipt_received", transition_id = transition_id)
  if (abi_v3) {
    .wb_operation_pack_v3_schema_assert(receipt, "receipt",
      "PYBENCH_RECEIPT_MISMATCH")
    .wb_operation_pack_v3_receipt_audit(receipt, request, registration,
      operation, preflight)
  } else {
    .wb_operation_pack_v2_schema_assert(receipt, "receipt",
      "PYBENCH_RECEIPT_MISMATCH")
    .wb_operation_pack_v2_receipt_audit(receipt, request, registration,
      operation, preflight)
  }
  if (!python_backend) .wb_operation_pack_v2_atomic_json(receipt,
    file.path(stage, "receipt.json"))
  .wb_operation_pack_v2_atomic_json(list(schema = "scworkbench.operation_pack.transition_state.v2",
    state = "audited", transition_id = transition_id, receipt_identity = receipt$receipt_identity), file.path(stage, "state.json"))
  .wb_operation_pack_v2_fault("audited", transition_id = transition_id)
  if (python_backend) {
    if (abi_v3) .wb_operation_pack_v3_python_audit(stage, request, receipt) else
      .wb_operation_pack_v2_python_audit(stage, request, receipt)
  } else {
    inventory <- list.files(stage, recursive = TRUE, all.files = TRUE,
      include.dirs = FALSE, no.. = TRUE)
    registry_names <- names(attr(request,
      "operation_pack_v2_registry_read_values") %||% list())
    registry_payloads <- if (length(registry_names)) paste0(
      "registry_reads/", registry_names, "/payload.json") else character()
    provenance_names <- names(attr(request,
      "operation_pack_v3_provenance_read_values") %||% list())
    provenance_payloads <- if (length(provenance_names)) paste0(
      "provenance_reads/", provenance_names, "/payload.json") else character()
    typed_slice_axes <- unlist(lapply(request$typed_slice_grants %||% list(),
      function(x) c(x$cells_axis$relative_path,
        x$features_axis$relative_path)), use.names = FALSE)
    typed_slice_sources <- vapply(Filter(function(x) identical(
      x$source_reference$source_kind, "in_memory_selected_projection"),
      request$typed_slice_grants %||% list()), function(x)
        sub("^private_projection:", "typed_slice_sources/",
          paste0(x$source_reference$input_reference, "/matrix.mtx")),
        character(1))
    expected_inventory <- sort(c("request.json", "receipt.json", "state.json",
      paste0("outputs/", names(adapter$state$writes), "/payload.rds"),
      registry_payloads, provenance_payloads, typed_slice_axes,
      typed_slice_sources), method = "radix")
    if (!identical(sort(inventory, method = "radix"), expected_inventory)) .wb_operation_pack_v2_error(
      "PYBENCH_OUT_OF_SCOPE_MUTATION", "Private stage contains undeclared files.", "audit",
      unexpected = setdiff(inventory, expected_inventory))
  }
  if (abi_v3) .wb_operation_pack_v3_provenance_reads_assert_current(bundle,
    operation, inputs, source_refs, request, params)
  if (abi_v3) .wb_operation_pack_v3_typed_slice_sources_assert_current(
    bundle, request)
  .wb_operation_pack_v2_fault("before_publication", transition_id = transition_id)
  moved <- try(file.rename(stage, final), silent = TRUE)
  if (!isTRUE(moved) || !dir.exists(final)) .wb_operation_pack_v2_error("PYBENCH_PUBLICATION_FAILED",
    "Atomic transition-directory publication failed.", "publication")
  .wb_operation_pack_v2_atomic_json(list(schema = "scworkbench.operation_pack.transition_state.v2",
    state = "published", transition_id = transition_id, receipt_identity = receipt$receipt_identity), file.path(final, "state.json"))
  .wb_operation_pack_v2_fault("published", transition_id = transition_id)
  reopen <- .wb_operation_pack_v2_record_validate(final, load_payloads = TRUE)
  if (!isTRUE(reopen$ok)) .wb_operation_pack_v2_error("PYBENCH_REOPEN_VALIDATION_FAILED",
    paste0("Fresh transition reopen failed: ", reopen$code,
      if (!is.null(reopen$output)) paste0(" (", reopen$output, ")") else ""), "reopen")
  .wb_operation_pack_v2_fault("before_reopened", transition_id = transition_id)
  .wb_operation_pack_v2_atomic_json(list(schema = "scworkbench.operation_pack.transition_state.v2",
    state = "reopened", transition_id = transition_id, receipt_identity = receipt$receipt_identity), file.path(final, "state.json"))
  .wb_operation_pack_v2_fault("reopened", transition_id = transition_id)
  published <- TRUE
  values <- stats::setNames(lapply(receipt$outputs %||% list(), function(item) {
    if (python_backend) {
      raw <- jsonlite::read_json(file.path(final, "outputs", item$name,
        "payload.json"), simplifyVector = FALSE)
      .wb_operation_pack_v2_python_to_primitive(raw, item$descriptor)
    } else readRDS(file.path(final, "outputs", item$name, "payload.rds"))
  }), vapply(receipt$outputs %||% list(), `[[`, character(1), "name"))
  registry_values <- stats::setNames(lapply(receipt$registry_requests %||%
      list(), function(item) {
    if (python_backend) {
      jsonlite::read_json(file.path(final, "registry_requests", item$name,
        "payload.json"), simplifyVector = FALSE)
    } else readRDS(file.path(final, "outputs", item$name, "payload.rds"))
  }), vapply(receipt$registry_requests %||% list(), `[[`, character(1),
    "name"))
  list(transition_id = transition_id, request = request, receipt = receipt,
    outputs = values, registry_requests = receipt$registry_requests %||% list(),
    registry_request_values = registry_values,
    runtime_sidecar = if (python_backend) process_result$sidecar else NULL,
    reader_observation = if (python_backend) {
      process_result$reader_observation
    } else reader_observation,
    state = "reopened", path = final)
}

.wb_operation_pack_v2_bind_parameters <- function(bundle, operation, params,
                                                   bound, effective_cells) {
  for (binding in operation$parameter_bindings %||% list()) {
    parameter <- as.character(binding$parameter)[1]
    policy <- as.character(binding$policy)[1]
    input <- bound[[as.character(binding$input)[1]]]
    if (identical(policy, "cell_ids_or_set_v1")) {
      params[[parameter]] <- unname(as.list(.wb_resolve_group_cells(
        bundle, params[[parameter]], effective_cells)))
    } else if (identical(policy, "feature_ids_or_all_v1")) {
      value <- params[[parameter]]
      resolved <- if (is.null(value)) as.character(input$feature_id) else
        as.character(unlist(value, use.names = FALSE))
      # These binding policies are JSON arrays even when the resolved
      # selection contains one identifier. Preserve that shape explicitly;
      # the generic scalar transport cannot infer it from length alone.
      params[[parameter]] <- unname(as.list(resolved))
    }
  }
  .wb_operation_pack_params_transport(params)
}

.wb_operation_pack_v2_retained_parameters <- function(operation, original,
                                                        effective, bound, outputs) {
  out <- list()
  for (item in operation$retained_parameters %||% list()) {
    source <- as.character(item$source)[1]
    output <- outputs[[as.character(item$output %||% "")[1]]]
    value <- switch(source,
      output_meta = output$meta[[as.character(item$field)[1]]],
      output_first_row = {
        table <- output$table
        if (is.data.frame(table) && nrow(table)) table[[as.character(item$field)[1]]][[1]] else NULL
      },
      output_row_count = if (is.data.frame(output$table)) nrow(output$table) else NULL,
      input_feature_count = length(bound[[as.character(item$input)[1]]]$feature_id %||% character()),
      parameter_supplied = !is.null(original[[as.character(item$parameter)[1]]]),
      parameter_count = length(unlist(effective[[as.character(item$parameter)[1]]], use.names = FALSE)),
      parameter_value = original[[as.character(item$parameter)[1]]],
      NULL)
    if (is.null(value) && isTRUE(item$required %||% TRUE)) .wb_operation_pack_v2_error(
      "PYBENCH_RECEIPT_MISMATCH", paste0("Required retained parameter '", item$name,
        "' is absent from the declared source."), "receipt")
    name <- as.character(item$name)[1]
    if (is.null(value) && !isTRUE(item$required %||% TRUE)) {
      out[name] <- list(NULL)
    } else if (!is.null(value)) out[[name]] <- value
  }
  out
}

.wb_operation_pack_v2_runner <- function(op_name) {
  force(op_name)
  function(bundle, resolved, effective_cells, inputs, ...) {
    binding <- bundle$pybench_session_binding %||% list()
    bound <- .wb_operation_pack_v2_bind_inputs(bundle, resolved, effective_cells)
    all_inputs <- inputs
    params <- inputs[setdiff(names(inputs), c(names(resolved), names(.wb_op_engine_input_specs())))]
    definition <- .wb_operation_pack_registry$operations[[op_name]]$definition
    operation <- definition$v2_definition
    mutation_context <- .wb_current_mutation_context(bundle$con, bundle$dir)
    .wb_operation_pack_assert(
      !is.null(mutation_context) &&
        identical(as.character(mutation_context$route)[1],
          "session_execution") &&
        nzchar(as.character(mutation_context$run_id %||% "")[1]),
      "PYBENCH_CAPABILITY_MISMATCH",
      "ABI v2 execution requires a preallocated session run.",
      phase = "execution", class = "wb_operation_pack_v2_error")
    params <- .wb_operation_pack_v2_bind_parameters(bundle, operation, params,
      bound, effective_cells)
    result <- .wb_operation_pack_v2_execute(bundle, op_name, bound,
      params = params,
      session_id = binding$session_id %||% NULL,
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
        if (dir.exists(result$path)) {
          unlink(result$path, recursive = TRUE, force = TRUE)
        }
        stop(error)
      })
    list(outputs = result$outputs, params = returned_params,
      operation_pack_runtime = result$receipt$runtime_attestation,
      operation_pack_transition = list(transition_id = result$transition_id,
        receipt_identity = result$receipt$receipt_identity),
      operation_pack_registry_requests = registry_requests)
  }
}

#' List Durable ABI v2 Transition Outputs
#'
#' This pack-free getter reads core-owned transition descriptors. It never
#' loads or executes operation-pack code.
#'
#' @param bundle Open scworkbench bundle, including a read-only recipient.
#' @param transition_id Durable ABI v2 transition identifier.
#' @return Data frame of published outputs and registry requests.
#' @export
wb_operation_pack_transition_outputs <- function(bundle, transition_id) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  transition_id <- .wb_operation_pack_v2_safe_component(transition_id, "transition_id")
  path <- file.path(.wb_operation_pack_v2_store(bundle), transition_id)
  result <- .wb_operation_pack_v2_record_validate(path, load_payloads = FALSE)
  .wb_operation_pack_assert(isTRUE(result$ok) && identical(result$state$state, "reopened"),
    "PYBENCH_REOPEN_VALIDATION_FAILED", paste0("Transition is absent or invalid: ", result$code %||% "not_reopened"),
    class = "wb_operation_pack_v2_error")
  values <- c(result$receipt$outputs %||% list(), result$receipt$registry_requests %||% list())
  if (!length(values)) return(data.frame(name = character(), allocated_id = character(),
    category = character(), kind = character(), storage_profile = character(), stringsAsFactors = FALSE))
  do.call(rbind, lapply(values, function(x) data.frame(name = x$name, allocated_id = x$allocated_id,
    category = x$descriptor$category, kind = x$descriptor$kind,
    storage_profile = x$descriptor$storage_profile, stringsAsFactors = FALSE)))
}

#' Load One Durable ABI v2 Transition Output
#'
#' The payload is reconstructed from a core-owned finalized record. The
#' originating operation pack need not be installed or active.
#'
#' @param bundle Open scworkbench bundle, including a read-only recipient.
#' @param transition_id Durable ABI v2 transition identifier.
#' @param output_name Declared output or registry-request name.
#' @return A typed primitive or validated cell-set admission record.
#' @export
wb_operation_pack_transition_load <- function(bundle, transition_id, output_name) {
  table <- wb_operation_pack_transition_outputs(bundle, transition_id)
  output_name <- as.character(output_name)[1]
  .wb_operation_pack_assert(output_name %in% table$name, "PYBENCH_REOPEN_VALIDATION_FAILED",
    paste0("Transition has no output named '", output_name, "'."), class = "wb_operation_pack_v2_error")
  receipt <- jsonlite::read_json(file.path(.wb_operation_pack_v2_store(bundle), transition_id, "receipt.json"), simplifyVector = FALSE)
  records <- c(receipt$outputs %||% list(), receipt$registry_requests %||% list())
  record <- records[[match(output_name, vapply(records, `[[`, character(1), "name"))]]
  python_payload <- identical(as.character(
    receipt$runtime_attestation$backend %||% "R")[1], "Python")
  payload_root <- if (python_payload && identical(
      as.character(record$descriptor$category)[1], "core_registry_request")) {
    "registry_requests"
  } else "outputs"
  path <- file.path(.wb_operation_pack_v2_store(bundle), transition_id,
    payload_root, output_name, if (python_payload) "payload.json" else "payload.rds")
  raw_value <- if (python_payload) jsonlite::read_json(path,
    simplifyVector = FALSE) else readRDS(path)
  observed <- if (identical(as.character(record$descriptor$kind)[1],
      "cell_set_family_admission")) {
    normalized <- .wb_operation_pack_cell_set_family_normalize(bundle,
      raw_value)
    attr(normalized, "family_identity")$sha256
  } else if (is.null(record$descriptor$content_identity)) {
    .wb_operation_pack_sha256(if (python_payload) raw_value$cells else
      as.character(unlist(raw_value$cells, use.names = FALSE)))
  } else .wb_operation_pack_sha256(if (python_payload) raw_value else unclass(raw_value))
  expected <- record$descriptor$content_identity$sha256 %||%
    record$descriptor$family_identity$sha256 %||%
    record$descriptor$membership_identity$sha256 %||% observed
  .wb_operation_pack_assert(identical(observed, expected), "PYBENCH_REOPEN_VALIDATION_FAILED",
    paste0("Durable ABI v2 output content identity changed for '", output_name,
      "'."), class = "wb_operation_pack_v2_error")
  if (python_payload) .wb_operation_pack_v2_python_to_primitive(raw_value,
    record$descriptor) else raw_value
}
