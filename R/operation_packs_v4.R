# ABI4 is explicitly negotiated through the existing executor and broker.
.wb_operation_pack_v4_schema <- function(kind = c("manifest", "request", "receipt")) {
  kind <- match.arg(kind)
  name <- if (kind == "manifest") "operation-pack-v4.schema.json" else
    paste0("operation-pack-transition-", kind, "-v4.schema.json")
  path <- system.file("protocol", name, package = "scworkbench")
  if (!nzchar(path)) path <- file.path("inst", "protocol", name)
  .wb_operation_pack_v2_read_schema(normalizePath(path, mustWork = TRUE))
}

.wb_operation_pack_v4_schema_assert <- function(value, kind,
    code = "OPERATION_PACK_MANIFEST_SCHEMA_INVALID") {
  result <- .wb_json_schema_validate_2020(value, .wb_operation_pack_v4_schema(kind))
  if (!isTRUE(result$ok)) .wb_operation_pack_v3_error(code,
    paste0("ABI4 ", kind, " failed at ", result$path, ": ", result$message), "outer_schema")
  invisible(TRUE)
}

.wb_operation_pack_v4_read_manifest <- function(path) {
  value <- .wb_operation_pack_v3_read_manifest(path)
  attr(value, "operation_pack_v4_source_path") <- attr(value, "operation_pack_v3_source_path")
  attr(value, "operation_pack_v4_source_sha256") <- attr(value, "operation_pack_v3_source_sha256")
  value
}

.wb_operation_pack_v4_normalize <- function(manifest, package = NULL,
    package_description = NULL) {
  .wb_operation_pack_v4_schema_assert(manifest, "manifest")
  .wb_operation_pack_v3_semantic_validate(manifest, validated_successor = TRUE)
  for (operation in manifest$operations) .wb_operation_pack_v4_axis_sources_validate(operation)
  for (op in manifest$operations) .wb_operation_pack_v2_param_profile_validate(
    op$params_schema, op$qualified_name)
  .wb_operation_pack_assert(!manifest$namespace %in% .wb_operation_pack_reserved_namespaces(),
    "OPERATION_PACK_NAMESPACE_RESERVED", "Operation-pack namespace is reserved.")
  .wb_operation_pack_assert(identical(manifest$identity_scheme, .wb_operation_pack_identity_scheme()),
    "OPERATION_PACK_IDENTITY_SCHEME_MISMATCH", "ABI4 requires canonical JSON v1.")
  .wb_operation_pack_assert(identical(.wb_operation_pack_canonical_json(
    manifest$compatibility$pack_abi), .wb_operation_pack_canonical_json(list(minimum = "4", maximum = "4"))),
    "OPERATION_PACK_PROTOCOL_INCOMPATIBLE", "ABI4 requires exactly version 4.")
  if (manifest$backend == "Python") .wb_operation_pack_assert(identical(
    .wb_operation_pack_canonical_json(manifest$compatibility$process_protocol),
    .wb_operation_pack_canonical_json(list(minimum = "pybench-op-v5", maximum = "pybench-op-v5"))),
    "OPERATION_PACK_PROTOCOL_INCOMPATIBLE", "Python ABI4 requires pybench-op-v5 exactly.")
  version <- as.character(utils::packageVersion("scworkbench"))
  .wb_operation_pack_assert(utils::compareVersion(version,
    manifest$compatibility$scworkbench$minimum) >= 0 && utils::compareVersion(version,
      manifest$compatibility$scworkbench$maximum_exclusive) < 0,
    "OPERATION_PACK_SCWORKBENCH_INCOMPATIBLE", "ABI4 excludes the current engine version.")
  if (!is.null(package)) .wb_operation_pack_assert(identical(package, manifest$package$name),
    "OPERATION_PACK_PACKAGE_IDENTITY_MISMATCH", "Installed R package name differs.")
  if (!is.null(package_description)) .wb_operation_pack_assert(identical(
    package_description$Version, manifest$package$version),
    "OPERATION_PACK_PACKAGE_IDENTITY_MISMATCH", "Installed R package version differs.")
  manifest
}

.wb_operation_pack_v4_axis_sources_validate <- function(operation) {
  inputs <- stats::setNames(operation$inputs, vapply(operation$inputs, `[[`, character(1), "name"))
  for (output in operation$outputs) {
    if (!identical(output$kind, "graph")) next
    sources <- output$axis_sources
    .wb_operation_pack_assert(!(output$binding_policy == "forbidden" && length(sources)) &&
      !(output$binding_policy == "required" && !length(sources)),
      "OPERATION_PACK_MANIFEST_SCHEMA_INVALID", "Graph binding policy contradicts declared axis sources.")
    keys <- character()
    for (source in sources) {
      input <- inputs[[source$input_name]]
      .wb_operation_pack_assert(!is.null(input), "OPERATION_PACK_MANIFEST_SCHEMA_INVALID",
        "Graph axis source names an undeclared input.")
      if (source$selection_mode == "retained_input_axis") {
        .wb_operation_pack_assert(input$kind %in% c("cell_vector", "cell_vector_family"),
          "OPERATION_PACK_MANIFEST_SCHEMA_INVALID", "Retained graph axis requires a declared cell vector input.")
      } else {
        .wb_operation_pack_assert(input$kind == "graph", "OPERATION_PACK_MANIFEST_SCHEMA_INVALID",
          "Selected graph binding requires a graph input.")
        selector <- source$source_binding_selector
        if (selector$kind == "fixed_binding_id_v1")
          .wb_operation_pack_assert(.wb_graph_string(selector$binding_id),
            "OPERATION_PACK_MANIFEST_SCHEMA_INVALID", "Invalid graph binding selector ID.")
        if (selector$kind == "parameter_binding_id_v1") {
          parameter <- operation$params_schema$properties[[selector$parameter]]
          .wb_operation_pack_assert(selector$parameter %in% unlist(operation$params_schema$required) &&
            identical(parameter$type, "string") && (parameter$minLength %||% 0) >= 1,
            "OPERATION_PACK_MANIFEST_SCHEMA_INVALID", "Binding selector must name a required nonempty string parameter.")
        }
      }
      key <- .wb_operation_pack_canonical_json(source)
      .wb_operation_pack_assert(!key %in% keys, "OPERATION_PACK_MANIFEST_SCHEMA_INVALID",
        "Duplicate graph axis source declaration.")
      keys <- c(keys, key)
    }
  }
  invisible(TRUE)
}

.wb_operation_pack_v4_identity <- function(manifest, source_sha256, pack_content_identity) {
  definitions <- stats::setNames(lapply(manifest$operations, function(op)
    .wb_operation_pack_v2_id("scworkbench.operation_pack.definition.v4", op)),
    vapply(manifest$operations, `[[`, character(1), "qualified_name"))
  definitions <- definitions[order(names(definitions), method = "radix")]
  manifest_id <- .wb_operation_pack_v2_id("scworkbench.operation_pack.manifest.v4", manifest)
  entry <- .wb_operation_pack_v2_id("scworkbench.operation_pack.entry_point.v2",
    list(backend = manifest$backend, package = manifest$package, value = manifest$entry_point))
  pack <- .wb_operation_pack_v2_id("scworkbench.operation_pack.pack.v4",
    list(scheme = "scworkbench.operation_pack.pack.v4", manifest_sha256 = manifest_id$sha256,
      namespace = manifest$namespace, package = manifest$package, backend = manifest$backend,
      entry_point = manifest$entry_point,
      operation_definition_sha256 = lapply(definitions, `[[`, "sha256"),
      pack_content_sha256 = pack_content_identity$sha256))
  list(identity_scheme = .wb_operation_pack_identity_scheme(),
    schema_version = manifest$schema_version, pack_abi_version = "4",
    namespace = manifest$namespace, package = manifest$package, backend = manifest$backend,
    compatibility = manifest$compatibility, entry_point = manifest$entry_point,
    manifest_source_identity = list(scheme = "scworkbench.operation_pack.manifest_source.bytes.v1",
      sha256 = source_sha256), manifest_identity = manifest_id, manifest_sha256 = manifest_id$sha256,
    operation_definition_identities = definitions,
    operation_definition_sha256 = lapply(definitions, `[[`, "sha256"),
    distribution_identity = pack_content_identity, entry_point_identity = entry,
    pack_identity = pack, pack_sha256 = pack$sha256)
}

.wb_operation_pack_v4_catalog_definition <- function(op) {
  definition <- .wb_operation_pack_v3_catalog_definition(op)
  definition$pack_abi_version <- "4"
  definition$v4_definition <- op
  definition$v3_definition <- NULL
  definition$cell_axis_policy <- "optional_if_no_cell_aligned_inputs"
  reference_inputs <- vapply(Filter(function(input) input$alignment == "none",
    op$inputs), `[[`, character(1), "name")
  definition$coverage[reference_inputs] <- rep("reference_only", length(reference_inputs))
  definition
}
