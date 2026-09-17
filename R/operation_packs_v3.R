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
    op$provenance_reads <- NULL
    op$typed_slice_reads <- NULL
    op$dimension_policies <- Filter(function(x) !identical(
      as.character(x$policy %||% "")[1], "authenticated_output_axes_v1"),
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
    policies <- operation$dimension_policies %||% list()
    policy_names <- vapply(policies, function(x) as.character(x$output)[1],
      character(1))
    if (anyDuplicated(policy_names)) .wb_operation_pack_v3_error(
      "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
      paste0("Operation '", opname, "' repeats a dimension-policy output."),
      "semantic_admission")
    for (policy in policies) {
      if (!identical(as.character(policy$policy)[1],
          "authenticated_output_axes_v1")) next
      output <- outputs[[as.character(policy$output)[1]]]
      input <- inputs[[as.character(policy$cell_axis$input)[1]]]
      shape <- as.character(policy$shape)[1]
      valid <- !is.null(output) && !is.null(input) &&
        as.character(input$kind)[1] %in% c("matrix", "cell_vector_family") &&
        ((identical(shape, "cell_key_cartesian") &&
          identical(as.character(output$kind)[1], "cell_vector_family") &&
          identical(as.character(policy$row_order)[1],
            "key_major_then_cell_v1") && !is.null(policy$key_axis)) ||
         (identical(shape, "one_per_cell") &&
          identical(as.character(output$kind)[1], "cell_vector") &&
          identical(as.character(policy$row_order)[1], "input_cell_order_v1") &&
          is.null(policy$key_axis)))
      if (!valid) .wb_operation_pack_v3_error(
        "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
        paste0("Operation '", opname,
          "' has an incompatible authenticated output-axis declaration."),
        "semantic_admission")
      if (identical(shape, "cell_key_cartesian")) {
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
        } else valid <- FALSE
        if (!valid) .wb_operation_pack_v3_error(
          "OPERATION_PACK_MANIFEST_SEMANTICS_INVALID",
          paste0("Operation '", opname,
            "' has an incompatible authenticated key-axis resolver."),
          "semantic_admission")
      }
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

.wb_operation_pack_v3_catalog_definition <- function(op) {
  projected <- op
  projected$provenance_reads <- NULL
  projected$typed_slice_reads <- NULL
  projected$dimension_policies <- Filter(function(x) !identical(
    as.character(x$policy %||% "")[1], "authenticated_output_axes_v1"),
    projected$dimension_policies %||% list())
  if (!length(projected$dimension_policies)) projected$dimension_policies <- NULL
  definition <- .wb_operation_pack_v2_catalog_definition(projected)
  definition$pack_abi_version <- "3"
  definition$v2_definition <- NULL
  definition$v3_definition <- op
  if (length(op$typed_slice_reads %||% list()))
    definition$typed_slice_reads <- op$typed_slice_reads
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
