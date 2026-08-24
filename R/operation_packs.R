# Operation-pack v1 process-local registry and public R author boundary.

.wb_operation_pack_protocol_version <- function() "1"

.wb_operation_pack_registry <- local({
  e <- new.env(parent = emptyenv())
  e$packs <- list()
  e$operations <- list()
  e$registration_context <- NULL
  e
})

.wb_operation_pack_abort <- function(code, message, ..., class = "wb_operation_pack_error") {
  fields <- list(...)
  condition <- structure(
    c(list(message = as.character(message)[1], call = NULL, code = as.character(code)[1]), fields),
    class = c(class, "wb_operation_pack_error", "error", "condition")
  )
  stop(condition)
}

.wb_operation_pack_assert <- function(ok, code, message, ..., class = "wb_operation_pack_validation_error") {
  if (!isTRUE(ok)) .wb_operation_pack_abort(code, message, ..., class = class)
  invisible(TRUE)
}

.wb_operation_pack_scalar <- function(x, label, pattern = NULL) {
  .wb_operation_pack_assert(
    is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x),
    "OPERATION_PACK_MANIFEST_INVALID", paste0(label, " must be one non-empty string."), field = label
  )
  if (!is.null(pattern)) {
    .wb_operation_pack_assert(
      grepl(pattern, x, perl = TRUE), "OPERATION_PACK_MANIFEST_INVALID",
      paste0(label, " has an invalid value: ", x, "."), field = label
    )
  }
  as.character(x)[1]
}

.wb_operation_pack_named_object <- function(x, label, allow_empty = TRUE) {
  .wb_operation_pack_assert(is.list(x), "OPERATION_PACK_MANIFEST_INVALID",
                            paste0(label, " must be a JSON object."), field = label)
  if (length(x)) {
    .wb_operation_pack_assert(!is.null(names(x)) && !anyNA(names(x)) &&
      all(nzchar(names(x))) && !anyDuplicated(names(x)),
      "OPERATION_PACK_MANIFEST_INVALID", paste0(label, " must have unique non-empty keys."), field = label)
  } else if (!isTRUE(allow_empty)) {
    .wb_operation_pack_abort("OPERATION_PACK_MANIFEST_INVALID",
      paste0(label, " must not be empty."), field = label,
      class = "wb_operation_pack_validation_error")
  }
  x
}

.wb_operation_pack_canonicalize <- function(x) {
  if (is.factor(x)) return(as.character(x))
  if (is.data.frame(x)) {
    rows <- lapply(seq_len(nrow(x)), function(i) .wb_operation_pack_canonicalize(as.list(x[i, , drop = FALSE])))
    return(rows)
  }
  if (is.list(x)) {
    out <- lapply(x, .wb_operation_pack_canonicalize)
    nms <- names(x)
    if (!is.null(nms)) {
      ord <- order(nms, method = "radix")
      out <- out[ord]
      names(out) <- nms[ord]
    }
    return(out)
  }
  if (is.integer(x) || is.logical(x) || is.character(x)) return(x)
  if (is.numeric(x)) return(as.numeric(x))
  x
}

.wb_operation_pack_canonical_json <- function(x) {
  .wb_require_pkg("jsonlite", "operation-pack canonical identity")
  as.character(jsonlite::toJSON(
    .wb_operation_pack_canonicalize(x), auto_unbox = TRUE, null = "null",
    na = "null", digits = NA, pretty = FALSE
  ))
}

.wb_operation_pack_sha256 <- function(x) {
  .wb_require_pkg("digest", "operation-pack canonical identity")
  digest::digest(.wb_operation_pack_canonical_json(x), algo = "sha256", serialize = FALSE)
}

.wb_operation_pack_manifest_path <- function(package, lib.loc = NULL) {
  package <- .wb_operation_pack_scalar(package, "package", "^[A-Za-z][A-Za-z0-9.]*$")
  path <- system.file("scworkbench", "operation-pack.json", package = package, lib.loc = lib.loc)
  .wb_operation_pack_assert(nzchar(path) && file.exists(path), "OPERATION_PACK_MANIFEST_NOT_FOUND",
    paste0("Installed package '", package, "' has no inst/scworkbench/operation-pack.json manifest."),
    package = package)
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

.wb_operation_pack_read_manifest <- function(path) {
  .wb_require_pkg("jsonlite", "operation-pack manifest")
  path <- .wb_operation_pack_scalar(path, "manifest")
  .wb_operation_pack_assert(file.exists(path), "OPERATION_PACK_MANIFEST_NOT_FOUND",
                            paste0("Operation-pack manifest does not exist: ", path), manifest = path)
  manifest <- tryCatch(jsonlite::read_json(path, simplifyVector = FALSE), error = identity)
  .wb_operation_pack_assert(!inherits(manifest, "error") && is.list(manifest),
    "OPERATION_PACK_MANIFEST_INVALID",
    paste0("Operation-pack manifest is not valid JSON: ", if (inherits(manifest, "error")) conditionMessage(manifest) else path),
    manifest = path)
  manifest
}

.wb_operation_pack_allowed_primitives <- function() {
  c("matrix", "space", "space_2d", "cell_vector", "cell_vector_family",
    "relation_family", "feature_table", "obs_table", "model_ref",
    "path_2d_family", "space_path_family")
}

.wb_operation_pack_reserved_namespaces <- function() {
  c("scworkbench", "core", "wb", "internal", "base", "stats", "utils",
    "methods", "graphics", "grDevices", "datasets")
}

.wb_operation_pack_version_satisfies <- function(version, requirement) {
  version <- as.character(version)[1]
  requirement <- trimws(as.character(requirement)[1])
  clauses <- strsplit(requirement, "[[:space:],]+", perl = TRUE)[[1]]
  clauses <- clauses[nzchar(clauses)]
  if (!length(clauses)) return(FALSE)
  all(vapply(clauses, function(clause) {
    m <- regexec("^(>=|<=|==|=|>|<)([0-9]+(?:[.][0-9A-Za-z-]+)*)$", clause, perl = TRUE)
    hit <- regmatches(clause, m)[[1]]
    if (length(hit) != 3L) return(FALSE)
    cmp <- utils::compareVersion(version, hit[3])
    switch(hit[2], ">=" = cmp >= 0L, "<=" = cmp <= 0L, ">" = cmp > 0L,
           "<" = cmp < 0L, "=" = cmp == 0L, "==" = cmp == 0L, FALSE)
  }, logical(1)))
}

.wb_operation_pack_validate_param <- function(param, op_name) {
  .wb_operation_pack_named_object(param, paste0(op_name, "$params[]"), allow_empty = FALSE)
  allowed <- c("name", "type", "default", "required", "nullable", "allow_non_finite",
               "min", "max", "choices", "help")
  extra <- setdiff(names(param), allowed)
  .wb_operation_pack_assert(!length(extra), "OPERATION_PACK_PARAMETER_INVALID",
    paste0("Operation '", op_name, "' parameter contains unsupported fields: ", paste(extra, collapse = ", "), "."),
    operation = op_name)
  name <- .wb_operation_pack_scalar(param$name, paste0(op_name, "$params$name"), "^[a-z][a-z0-9_]*$")
  type <- .wb_operation_pack_scalar(param$type, paste0(op_name, "$params$", name, "$type"))
  supported <- c("int", "int_range", "int_vec", "dbl", "number", "bool", "logical",
                 "string", "path", "cell_set", "choice", "string_vec", "string_array",
                 "cell_ids", "metadata_field", "metadata_field_array", "string_vec_or_list",
                 "cell_ids_or_set", "list_or_cell_set", "list")
  .wb_operation_pack_assert(type %in% supported, "OPERATION_PACK_PARAMETER_INVALID",
    paste0("Operation '", op_name, "' parameter '", name, "' has unsupported type '", type, "'."),
    operation = op_name, parameter = name)
  if (identical(type, "choice")) {
    choices <- unlist(param$choices %||% list(), use.names = FALSE)
    .wb_operation_pack_assert(is.character(choices) && length(choices) && !anyNA(choices) &&
      all(nzchar(choices)) && !anyDuplicated(choices), "OPERATION_PACK_PARAMETER_INVALID",
      paste0("Operation '", op_name, "' choice parameter '", name, "' requires unique non-empty choices."),
      operation = op_name, parameter = name)
    param$choices <- choices
  }
  if ("default" %in% names(param)) {
    tryCatch(.wb_validate_param_value(param$default, param, op_name), error = function(e) {
      .wb_operation_pack_abort("OPERATION_PACK_PARAMETER_INVALID",
        paste0("Operation '", op_name, "' parameter '", name, "' has an invalid default: ", conditionMessage(e)),
        operation = op_name, parameter = name, class = "wb_operation_pack_validation_error")
    })
  }
  param$name <- name
  param$type <- type
  param
}

.wb_operation_pack_validate_definition <- function(definition, namespace) {
  .wb_operation_pack_named_object(definition, "manifest$operations[]", allow_empty = FALSE)
  allowed <- c("name", "title", "description", "intent", "requires", "optional_requires",
               "inputs", "params", "produces", "promotable", "replay_equivalence", "coverage",
               "interface_produces", "chunking", "determinism", "resources", "software")
  extra <- setdiff(names(definition), allowed)
  .wb_operation_pack_assert(!length(extra), "OPERATION_PACK_DEFINITION_INVALID",
    paste0("Operation definition contains forbidden or unknown fields: ", paste(extra, collapse = ", "), "."))
  required_fields <- c("name", "title", "description", "intent", "requires", "inputs", "params",
                       "produces", "promotable", "replay_equivalence", "determinism", "resources", "software")
  missing <- setdiff(required_fields, names(definition))
  .wb_operation_pack_assert(!length(missing), "OPERATION_PACK_DEFINITION_INVALID",
    paste0("Operation definition is missing required fields: ", paste(missing, collapse = ", "), "."))

  name <- .wb_operation_pack_scalar(definition$name, "operation$name",
                                    "^[a-z][a-z0-9._-]*::[a-z][a-z0-9_]*$")
  expected_prefix <- paste0(namespace, "::")
  .wb_operation_pack_assert(startsWith(name, expected_prefix), "OPERATION_PACK_NAMESPACE_MISMATCH",
    paste0("Operation '", name, "' must use namespace '", namespace, "'."), operation = name)
  .wb_operation_pack_scalar(definition$title, paste0(name, "$title"))
  .wb_operation_pack_scalar(definition$description, paste0(name, "$description"))
  intent <- unlist(definition$intent, use.names = FALSE)
  .wb_operation_pack_assert(is.character(intent) && length(intent) && !anyNA(intent) && all(nzchar(intent)),
    "OPERATION_PACK_DEFINITION_INVALID", paste0("Operation '", name, "' intent must be non-empty."), operation = name)

  requires <- .wb_operation_pack_named_object(definition$requires, paste0(name, "$requires"))
  optional <- .wb_operation_pack_named_object(definition$optional_requires %||% list(), paste0(name, "$optional_requires"))
  typed <- c(requires, optional)
  .wb_operation_pack_assert(!anyDuplicated(names(typed)), "OPERATION_PACK_DEFINITION_INVALID",
    paste0("Operation '", name, "' duplicates a required/optional input."), operation = name)
  kinds <- unlist(typed, use.names = FALSE)
  .wb_operation_pack_assert(is.character(kinds) && all(kinds %in% .wb_operation_pack_allowed_primitives()),
    "OPERATION_PACK_PRIMITIVE_UNSUPPORTED",
    paste0("Operation '", name, "' declares an unknown input primitive: ",
           paste(setdiff(kinds, .wb_operation_pack_allowed_primitives()), collapse = ", "), "."), operation = name)
  inputs <- .wb_operation_pack_named_object(definition$inputs, paste0(name, "$inputs"))
  .wb_operation_pack_assert(setequal(names(inputs), names(typed)), "OPERATION_PACK_DEFINITION_INVALID",
    paste0("Operation '", name, "' inputs must exactly describe requires and optional_requires."), operation = name)
  for (input_name in names(typed)) {
    item <- .wb_operation_pack_named_object(inputs[[input_name]], paste0(name, "$inputs$", input_name), allow_empty = FALSE)
    item_kind <- as.character(item$kind %||% "")[1]
    .wb_operation_pack_assert(identical(item_kind, as.character(typed[[input_name]])[1]),
      "OPERATION_PACK_DEFINITION_INVALID", paste0("Operation '", name, "' input '", input_name,
      "' kind must match its typed requirement."), operation = name, input = input_name)
    required_flag <- item$required
    .wb_operation_pack_assert(is.logical(required_flag) && length(required_flag) == 1L && !is.na(required_flag) &&
      identical(isTRUE(required_flag), input_name %in% names(requires)),
      "OPERATION_PACK_DEFINITION_INVALID", paste0("Operation '", name, "' input '", input_name,
      "' required flag disagrees with requires/optional_requires."), operation = name, input = input_name)
  }

  produces <- .wb_operation_pack_named_object(definition$produces, paste0(name, "$produces"), allow_empty = FALSE)
  output_kinds <- unlist(produces, use.names = FALSE)
  .wb_operation_pack_assert(all(grepl("^[a-z][a-z0-9_]*$", names(produces), perl = TRUE)),
    "OPERATION_PACK_OUTPUT_INVALID", paste0("Operation '", name, "' output names are malformed."), operation = name)
  .wb_operation_pack_assert(is.character(output_kinds) && all(output_kinds %in% .wb_operation_pack_allowed_primitives()),
    "OPERATION_PACK_PRIMITIVE_UNSUPPORTED",
    paste0("Operation '", name, "' declares an unknown output primitive: ",
           paste(setdiff(output_kinds, .wb_operation_pack_allowed_primitives()), collapse = ", "), "."), operation = name)
  interface_produces <- .wb_operation_pack_named_object(
    definition$interface_produces %||% lapply(produces, function(kind) list(kind = kind)),
    paste0(name, "$interface_produces"), allow_empty = FALSE)
  .wb_operation_pack_assert(setequal(names(interface_produces), names(produces)),
    "OPERATION_PACK_OUTPUT_INVALID",
    paste0("Operation '", name, "' interface_produces must exactly describe declared outputs."), operation = name)
  for (output_name in names(produces)) {
    item <- .wb_operation_pack_named_object(interface_produces[[output_name]],
      paste0(name, "$interface_produces$", output_name), allow_empty = FALSE)
    actual <- as.character(item$kind %||% "")[1]
    .wb_operation_pack_assert(identical(actual, as.character(produces[[output_name]])[1]),
      "OPERATION_PACK_OUTPUT_INVALID", paste0("Operation '", name, "' output '", output_name,
      "' interface kind disagrees with produces."), operation = name, output = output_name)
  }
  promotable <- unlist(definition$promotable, use.names = FALSE)
  .wb_operation_pack_assert(is.character(promotable) && length(promotable) && !anyNA(promotable) &&
    all(nzchar(promotable)) && !anyDuplicated(promotable) && all(promotable %in% names(produces)),
    "OPERATION_PACK_PROMOTABLE_INVALID",
    paste0("Operation '", name, "' must declare unique promotable terminal outputs drawn from produces."), operation = name)
  replay <- .wb_operation_pack_named_object(definition$replay_equivalence,
                                             paste0(name, "$replay_equivalence"), allow_empty = FALSE)
  .wb_operation_pack_assert(setequal(names(replay), names(produces)), "OPERATION_PACK_OUTPUT_INVALID",
    paste0("Operation '", name, "' replay_equivalence must cover every output exactly."), operation = name)
  policies <- unlist(replay, use.names = FALSE)
  .wb_operation_pack_assert(all(policies %in% .wb_replay_equivalence_policies()),
    "OPERATION_PACK_OUTPUT_INVALID", paste0("Operation '", name, "' has an unsupported replay-equivalence policy."), operation = name)
  .wb_operation_pack_assert(!any(unlist(replay[promotable], use.names = FALSE) == "not_comparable"),
    "OPERATION_PACK_PROMOTABLE_INVALID", paste0("Operation '", name,
    "' promotable terminals must declare an executable replay-equivalence policy."), operation = name)

  coverage <- .wb_operation_pack_named_object(definition$coverage %||% list(), paste0(name, "$coverage"))
  .wb_operation_pack_assert(all(names(coverage) %in% names(typed)) &&
    all(unlist(coverage, use.names = FALSE) %in% c("cell_indexed", "reference_only", "model_associated_unless_query_space")),
    "OPERATION_PACK_DEFINITION_INVALID", paste0("Operation '", name, "' coverage contains an unknown input or mode."), operation = name)
  .wb_operation_pack_named_object(definition$determinism, paste0(name, "$determinism"), allow_empty = FALSE)
  .wb_operation_pack_named_object(definition$resources, paste0(name, "$resources"), allow_empty = FALSE)
  .wb_operation_pack_named_object(definition$software, paste0(name, "$software"), allow_empty = FALSE)

  params <- definition$params %||% list()
  .wb_operation_pack_assert(is.list(params), "OPERATION_PACK_PARAMETER_INVALID",
                            paste0("Operation '", name, "' params must be an array."), operation = name)
  params <- lapply(params, .wb_operation_pack_validate_param, op_name = name)
  param_names <- vapply(params, function(p) p$name, character(1))
  .wb_operation_pack_assert(!anyDuplicated(param_names), "OPERATION_PACK_PARAMETER_INVALID",
                            paste0("Operation '", name, "' duplicates parameter names."), operation = name)
  reserved_inputs <- unique(c(names(typed), names(.wb_op_engine_input_specs())))
  .wb_operation_pack_assert(!length(intersect(param_names, reserved_inputs)), "OPERATION_PACK_PARAMETER_INVALID",
    paste0("Operation '", name, "' parameters collide with typed or engine inputs: ",
           paste(intersect(param_names, reserved_inputs), collapse = ", "), "."), operation = name)

  definition$name <- name
  definition$op_name <- name
  definition$intent <- intent
  definition$requires <- requires
  definition$optional_requires <- optional
  definition$inputs <- inputs
  definition$params <- params
  definition$produces <- produces
  definition$interface_produces <- interface_produces
  definition$promotable <- promotable
  definition$replay_equivalence <- replay
  definition$coverage <- coverage
  definition$definition_sha256 <- .wb_operation_pack_sha256(definition[setdiff(names(definition), c("op_name", "definition_sha256"))])
  definition
}

.wb_operation_pack_validate_manifest <- function(manifest, package = NULL, package_description = NULL) {
  .wb_operation_pack_named_object(manifest, "manifest", allow_empty = FALSE)
  allowed <- c("schema_version", "protocol_version", "namespace", "package", "backend",
               "compatibility", "entry_point", "operations")
  extra <- setdiff(names(manifest), allowed)
  missing <- setdiff(allowed, names(manifest))
  .wb_operation_pack_assert(!length(extra) && !length(missing), "OPERATION_PACK_MANIFEST_INVALID",
    paste0("Manifest fields disagree with v1 schema; missing=[", paste(missing, collapse = ", "),
           "], unknown=[", paste(extra, collapse = ", "), "]."))
  schema_version <- .wb_operation_pack_scalar(manifest$schema_version, "schema_version")
  protocol_version <- .wb_operation_pack_scalar(manifest$protocol_version, "protocol_version")
  .wb_operation_pack_assert(identical(schema_version, "scworkbench.operation_pack.v1"),
    "OPERATION_PACK_SCHEMA_INCOMPATIBLE", paste0("Unsupported operation-pack schema: ", schema_version, "."))
  .wb_operation_pack_assert(identical(protocol_version, .wb_operation_pack_protocol_version()),
    "OPERATION_PACK_PROTOCOL_INCOMPATIBLE",
    paste0("Operation-pack protocol '", protocol_version, "' is incompatible with protocol '",
           .wb_operation_pack_protocol_version(), "'."), protocol_version = protocol_version)
  namespace <- .wb_operation_pack_scalar(manifest$namespace, "namespace", "^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$")
  .wb_operation_pack_assert(!namespace %in% .wb_operation_pack_reserved_namespaces(),
    "OPERATION_PACK_NAMESPACE_RESERVED", paste0("Operation-pack namespace '", namespace, "' is reserved."), namespace = namespace)
  package_rec <- .wb_operation_pack_named_object(manifest$package, "package", allow_empty = FALSE)
  .wb_operation_pack_assert(setequal(names(package_rec), c("name", "version")), "OPERATION_PACK_MANIFEST_INVALID",
                            "Manifest package must contain exactly name and version.")
  package_name <- .wb_operation_pack_scalar(package_rec$name, "package$name", "^[A-Za-z][A-Za-z0-9.]*$")
  package_version <- .wb_operation_pack_scalar(package_rec$version, "package$version", "^[0-9]+(?:[.-][0-9A-Za-z]+)*$")
  if (!is.null(package)) .wb_operation_pack_assert(identical(package_name, as.character(package)[1]),
    "OPERATION_PACK_PACKAGE_IDENTITY_MISMATCH", paste0("Manifest package '", package_name,
      "' does not match installed package '", package, "'."), package = package)
  if (!is.null(package_description)) {
    installed_version <- as.character(package_description$Version %||% "")[1]
    .wb_operation_pack_assert(identical(package_version, installed_version),
      "OPERATION_PACK_PACKAGE_IDENTITY_MISMATCH", paste0("Manifest version '", package_version,
      "' does not match installed package version '", installed_version, "'."), package = package_name)
  }
  backend <- .wb_operation_pack_scalar(manifest$backend, "backend")
  .wb_operation_pack_assert(identical(backend, "R"), "OPERATION_PACK_BACKEND_UNSUPPORTED",
                            paste0("Phase 1 supports only backend 'R'; found '", backend, "'."), backend = backend)
  compatibility <- .wb_operation_pack_named_object(manifest$compatibility, "compatibility", allow_empty = FALSE)
  .wb_operation_pack_assert(setequal(names(compatibility), c("scworkbench", "protocol")),
                            "OPERATION_PACK_MANIFEST_INVALID",
                            "Manifest compatibility must contain exactly scworkbench and protocol.")
  requirement <- .wb_operation_pack_scalar(compatibility$scworkbench, "compatibility$scworkbench")
  required_protocol <- .wb_operation_pack_scalar(compatibility$protocol, "compatibility$protocol")
  current_version <- tryCatch(as.character(utils::packageVersion("scworkbench")), error = function(e) "0.1.0")
  .wb_operation_pack_assert(.wb_operation_pack_version_satisfies(current_version, requirement),
    "OPERATION_PACK_SCWORKBENCH_INCOMPATIBLE", paste0("Pack requires scworkbench '", requirement,
    "'; current version is '", current_version, "'."), requirement = requirement, current_version = current_version)
  .wb_operation_pack_assert(identical(required_protocol, .wb_operation_pack_protocol_version()),
    "OPERATION_PACK_PROTOCOL_INCOMPATIBLE", paste0("Pack compatibility requires protocol '",
    required_protocol, "'; current protocol is '", .wb_operation_pack_protocol_version(), "'."))
  entry_point <- .wb_operation_pack_scalar(manifest$entry_point, "entry_point", "^[A-Za-z][A-Za-z0-9._]*$")
  operations <- manifest$operations
  .wb_operation_pack_assert(is.list(operations) && length(operations), "OPERATION_PACK_DEFINITION_INVALID",
                            "Manifest operations must be a non-empty array.")
  operations <- lapply(operations, .wb_operation_pack_validate_definition, namespace = namespace)
  op_names <- vapply(operations, function(x) x$name, character(1))
  .wb_operation_pack_assert(!anyDuplicated(op_names), "OPERATION_PACK_OPERATION_DUPLICATE",
                            "Manifest contains duplicate operation names.", namespace = namespace)
  names(operations) <- op_names
  manifest$operations <- unname(operations)
  manifest$schema_version <- schema_version
  manifest$protocol_version <- protocol_version
  manifest$namespace <- namespace
  manifest$package <- list(name = package_name, version = package_version)
  manifest$backend <- backend
  manifest$compatibility <- list(scworkbench = requirement, protocol = required_protocol)
  manifest$entry_point <- entry_point
  manifest
}

.wb_operation_pack_registration <- function(manifest, runners, package_description = NULL,
                                            installed_path = NULL) {
  operation_names <- vapply(manifest$operations, function(x) x$name, character(1))
  .wb_operation_pack_named_object(runners, "operations", allow_empty = FALSE)
  .wb_operation_pack_assert(setequal(names(runners), operation_names), "OPERATION_PACK_ENTRY_POINT_INVALID",
    paste0("Entry point runners must exactly match manifest operations; expected [",
           paste(operation_names, collapse = ", "), "]."), namespace = manifest$namespace)
  for (name in names(runners)) {
    runner <- runners[[name]]
    .wb_operation_pack_assert(is.function(runner), "OPERATION_PACK_ENTRY_POINT_INVALID",
                              paste0("Entry point for operation '", name, "' is not a function."), operation = name)
    expected <- c("bundle", "resolved", "effective_cells", "inputs", "...")
    .wb_operation_pack_assert(identical(names(formals(runner)), expected), "OPERATION_PACK_ENTRY_POINT_INVALID",
      paste0("Runner '", name, "' must have formals: ", paste(expected, collapse = ", "), "."), operation = name)
  }
  definition_hashes <- stats::setNames(
    vapply(manifest$operations, function(x) x$definition_sha256, character(1)), operation_names)
  manifest_identity_input <- manifest
  manifest_identity_input$operations <- lapply(manifest_identity_input$operations, function(x) x[setdiff(names(x), c("op_name", "definition_sha256"))])
  manifest_sha256 <- .wb_operation_pack_sha256(manifest_identity_input)
  pack_identity <- list(
    schema_version = manifest$schema_version,
    protocol_version = manifest$protocol_version,
    manifest_sha256 = manifest_sha256,
    namespace = manifest$namespace,
    package = manifest$package,
    backend = manifest$backend,
    compatibility = manifest$compatibility,
    entry_point = manifest$entry_point,
    operation_definition_sha256 = as.list(definition_hashes)
  )
  pack_identity$pack_sha256 <- .wb_operation_pack_sha256(pack_identity)
  attestation <- list(
    package = manifest$package,
    installed_path = as.character(installed_path %||% NA_character_)[1],
    built = as.character(package_description$Built %||% NA_character_)[1],
    remote_sha = as.character(package_description$RemoteSha %||% NA_character_)[1]
  )
  structure(list(manifest = manifest, runners = runners, identity = pack_identity,
                 runtime_attestation = attestation),
            class = c("wb_operation_pack_registration", "list"))
}

#' Register an R Operation-Pack Definition
#'
#' This is the public pack-author boundary called by a package's exported
#' manifest entry point. It validates and returns a registration object; it
#' does not activate operations by itself. Users activate an installed package
#' explicitly with [wb_operation_pack_load()]. Pack code is trusted executable
#' R code, not a host sandbox.
#'
#' @param manifest Path to the installed canonical `operation-pack.json`.
#' @param operations Named list of runner functions. Names must exactly match
#'   the fully qualified operation names declared by the manifest. Every runner
#'   has formals `bundle, resolved, effective_cells, inputs, ...`, consumes only
#'   sanctioned arguments, and returns `list(outputs = ..., params = ...)`.
#' @return A validated `wb_operation_pack_registration` object.
#' @export
wb_operation_pack_register <- function(manifest, operations) {
  context <- .wb_operation_pack_registry$registration_context
  .wb_operation_pack_assert(is.environment(context), "OPERATION_PACK_REGISTRATION_CONTEXT_REQUIRED",
    "wb_operation_pack_register() may only be called by an entry point invoked through wb_operation_pack_validate() or wb_operation_pack_load().")
  path <- normalizePath(.wb_operation_pack_scalar(manifest, "manifest"), winslash = "/", mustWork = TRUE)
  .wb_operation_pack_assert(identical(path, context$manifest_path), "OPERATION_PACK_MANIFEST_IDENTITY_MISMATCH",
                            "Entry point attempted to register a manifest other than the installed manifest.")
  validated <- .wb_operation_pack_validate_manifest(.wb_operation_pack_read_manifest(path),
    package = context$package, package_description = context$package_description)
  registration <- .wb_operation_pack_registration(validated, operations,
    package_description = context$package_description, installed_path = context$installed_path)
  .wb_operation_pack_assert(is.null(context$result), "OPERATION_PACK_ENTRY_POINT_INVALID",
                            "Operation-pack entry point called wb_operation_pack_register() more than once.")
  context$result <- registration
  registration
}

.wb_operation_pack_invoke <- function(package, lib.loc = NULL) {
  package <- .wb_operation_pack_scalar(package, "package", "^[A-Za-z][A-Za-z0-9.]*$")
  manifest_path <- .wb_operation_pack_manifest_path(package, lib.loc = lib.loc)
  description <- utils::packageDescription(package, lib.loc = lib.loc)
  manifest <- .wb_operation_pack_validate_manifest(.wb_operation_pack_read_manifest(manifest_path),
    package = package, package_description = description)
  .wb_operation_pack_assert(requireNamespace(package, quietly = TRUE, lib.loc = lib.loc),
                            "OPERATION_PACK_PACKAGE_UNAVAILABLE",
                            paste0("Installed package '", package, "' could not be loaded."), package = package)
  exports <- getNamespaceExports(package)
  .wb_operation_pack_assert(manifest$entry_point %in% exports, "OPERATION_PACK_ENTRY_POINT_INVALID",
    paste0("Manifest entry point '", manifest$entry_point, "' is not exported by package '", package, "'."),
    package = package, entry_point = manifest$entry_point)
  entry <- getExportedValue(package, manifest$entry_point)
  .wb_operation_pack_assert(is.function(entry), "OPERATION_PACK_ENTRY_POINT_INVALID",
                            paste0("Exported entry point '", manifest$entry_point, "' is not a function."),
                            package = package, entry_point = manifest$entry_point)
  .wb_operation_pack_assert(length(formals(entry)) == 0L, "OPERATION_PACK_ENTRY_POINT_INVALID",
                            paste0("Exported entry point '", manifest$entry_point, "' must have no formal arguments."),
                            package = package, entry_point = manifest$entry_point)
  context <- new.env(parent = emptyenv())
  context$package <- package
  context$manifest_path <- manifest_path
  context$package_description <- description
  context$installed_path <- dirname(dirname(manifest_path))
  context$result <- NULL
  .wb_operation_pack_registry$registration_context <- context
  on.exit({ .wb_operation_pack_registry$registration_context <- NULL }, add = TRUE)
  returned <- tryCatch(entry(), error = function(e) {
    if (inherits(e, "wb_operation_pack_error")) stop(e)
    .wb_operation_pack_abort("OPERATION_PACK_ENTRY_POINT_FAILED",
      paste0("Operation-pack entry point failed: ", conditionMessage(e)), package = package,
      entry_point = manifest$entry_point, class = "wb_operation_pack_entry_point_error")
  })
  .wb_operation_pack_assert(inherits(returned, "wb_operation_pack_registration") &&
    inherits(context$result, "wb_operation_pack_registration") && identical(returned, context$result),
    "OPERATION_PACK_ENTRY_POINT_INVALID",
    "Operation-pack entry point must return the object from exactly one wb_operation_pack_register() call.",
    package = package, entry_point = manifest$entry_point)
  returned
}

#' Validate an Installed R Operation Pack Without Activating It
#'
#' Validation is read-only with respect to bundles and the process-local
#' operation registry, but it loads and executes the package's declared entry
#' point. Treat it as an explicit trust decision. Passing conformance means the
#' pack matches engine contracts; it is not scientific validation of a method.
#'
#' @param package Installed R package name.
#' @param lib.loc Optional R library location.
#' @return A machine-readable conformance report containing canonical pack,
#'   manifest, and operation-definition identities.
#' @export
wb_operation_pack_validate <- function(package, lib.loc = NULL) {
  registration <- .wb_operation_pack_invoke(package, lib.loc = lib.loc)
  structure(list(
    schema_version = "scworkbench.operation_pack.conformance.v1",
    ok = TRUE,
    activated = FALSE,
    identity = registration$identity,
    operations = lapply(registration$manifest$operations, function(x) list(
      op_name = x$name, definition_sha256 = x$definition_sha256,
      consumes = x$requires, produces = x$produces, promotable = x$promotable
    )),
    claims = list(engine_compatible = TRUE, scientifically_validated = FALSE,
                  host_sandboxed = FALSE, bundle_mutated = FALSE)
  ), class = c("wb_operation_pack_conformance", "list"))
}

.wb_operation_pack_runner <- function(op_name, runner) {
  force(op_name); force(runner)
  function(bundle, resolved, effective_cells, inputs, ...) {
    rec <- .wb_operation_pack_registry$operations[[op_name]]
    .wb_operation_pack_assert(!is.null(rec), "OPERATION_PACK_REQUIRED",
      paste0("Operation pack required for '", op_name, "' is not loaded."), operation = op_name,
      class = "wb_operation_pack_unavailable")
    rec$execution_depth <- as.integer(rec$execution_depth %||% 0L) + 1L
    .wb_operation_pack_registry$operations[[op_name]] <- rec
    on.exit({
      current <- .wb_operation_pack_registry$operations[[op_name]]
      if (!is.null(current)) {
        current$execution_depth <- max(0L, as.integer(current$execution_depth %||% 1L) - 1L)
        current$used <- TRUE
        .wb_operation_pack_registry$operations[[op_name]] <- current
        pack <- .wb_operation_pack_registry$packs[[current$namespace]]
        if (!is.null(pack)) {
          pack$used <- TRUE
          .wb_operation_pack_registry$packs[[current$namespace]] <- pack
        }
      }
    }, add = TRUE)
    runner(bundle = bundle, resolved = resolved, effective_cells = effective_cells, inputs = inputs, ...)
  }
}

#' Explicitly Load and Activate an Installed R Operation Pack
#'
#' Installing a package is inert. This function is the explicit process-local
#' trust and activation boundary; no installed-package scan is performed.
#'
#' @param package Installed R package name.
#' @param lib.loc Optional R library location.
#' @return The inspected activated pack record, invisibly.
#' @export
wb_operation_pack_load <- function(package, lib.loc = NULL) {
  registration <- .wb_operation_pack_invoke(package, lib.loc = lib.loc)
  identity <- registration$identity
  namespace <- identity$namespace
  op_names <- names(identity$operation_definition_sha256)
  core_names <- names(.wb_op_catalog())
  .wb_operation_pack_assert(!namespace %in% names(.wb_operation_pack_registry$packs),
    "OPERATION_PACK_NAMESPACE_DUPLICATE", paste0("Operation-pack namespace '", namespace, "' is already loaded."),
    namespace = namespace)
  loaded_packages <- vapply(.wb_operation_pack_registry$packs, function(x) x$identity$package$name, character(1))
  .wb_operation_pack_assert(!identity$package$name %in% loaded_packages,
    "OPERATION_PACK_PACKAGE_DUPLICATE", paste0("Operation-pack package '", identity$package$name, "' is already loaded."),
    package = identity$package$name)
  .wb_operation_pack_assert(!length(intersect(op_names, core_names)), "OPERATION_PACK_CORE_SHADOW",
                            "Operation pack attempts to shadow a core operation.")
  .wb_operation_pack_assert(!length(intersect(op_names, names(.wb_operation_pack_registry$operations))),
    "OPERATION_PACK_OPERATION_DUPLICATE", "Operation pack duplicates an already loaded operation.")

  operations <- list()
  definitions <- stats::setNames(registration$manifest$operations, op_names)
  for (op_name in sort(op_names, method = "radix")) {
    definition <- definitions[[op_name]]
    raw_runner <- registration$runners[[op_name]]
    definition$runner <- .wb_operation_pack_runner(op_name, raw_runner)
    definition$source_pack <- identity
    operations[[op_name]] <- list(namespace = namespace, definition = definition,
                                  execution_depth = 0L, used = FALSE)
  }
  pack <- list(identity = identity, manifest = registration$manifest,
               runtime_attestation = registration$runtime_attestation,
               operation_names = sort(op_names, method = "radix"), used = FALSE)
  # Publish only after the complete pack has validated and staged in memory.
  .wb_operation_pack_registry$packs[[namespace]] <- pack
  for (op_name in names(operations)) .wb_operation_pack_registry$operations[[op_name]] <- operations[[op_name]]
  invisible(wb_operation_pack_inspect(namespace))
}

#' List Explicitly Loaded Operation Packs
#'
#' @return A data frame with process-local pack identities and usage state.
#' @export
wb_operation_packs <- function() {
  packs <- .wb_operation_pack_registry$packs
  if (!length(packs)) return(data.frame(
    namespace = character(), package = character(), version = character(), backend = character(),
    manifest_sha256 = character(), pack_sha256 = character(), operation_count = integer(), used = logical(),
    stringsAsFactors = FALSE))
  namespaces <- sort(names(packs), method = "radix")
  do.call(rbind, lapply(namespaces, function(namespace) {
    x <- packs[[namespace]]
    data.frame(namespace = namespace, package = x$identity$package$name,
      version = x$identity$package$version, backend = x$identity$backend,
      manifest_sha256 = x$identity$manifest_sha256, pack_sha256 = x$identity$pack_sha256,
      operation_count = length(x$operation_names), used = isTRUE(x$used), stringsAsFactors = FALSE)
  }))
}

#' Inspect One Loaded Operation Pack
#'
#' @param pack Loaded namespace or package name.
#' @return A JSON-friendly record containing exact identity, canonical manifest,
#'   operation definitions, runtime attestation, and usage state. Runner
#'   functions are deliberately omitted.
#' @export
wb_operation_pack_inspect <- function(pack) {
  key <- .wb_operation_pack_scalar(pack, "pack")
  packs <- .wb_operation_pack_registry$packs
  if (!key %in% names(packs)) {
    hits <- names(packs)[vapply(packs, function(x) identical(x$identity$package$name, key), logical(1))]
    .wb_operation_pack_assert(length(hits) == 1L, "OPERATION_PACK_NOT_LOADED",
                              paste0("Operation pack '", key, "' is not loaded."), pack = key,
                              class = "wb_operation_pack_unavailable")
    key <- hits[[1]]
  }
  x <- packs[[key]]
  definitions <- stats::setNames(x$manifest$operations, vapply(x$manifest$operations, function(z) z$name, character(1)))
  structure(list(schema_version = "scworkbench.operation_pack.inspection.v1",
    identity = x$identity, manifest = x$manifest, operations = definitions,
    runtime_attestation = x$runtime_attestation, used = isTRUE(x$used)),
    class = c("wb_operation_pack", "list"))
}

#' Safely Unload a Process-Local Operation Pack
#'
#' A pack can be unloaded only before any contributed operation has executed in
#' the process. This conservative rule ensures no ephemeral or durable staged
#' session can lose the contract needed for promotion. Package namespaces may
#' remain loaded by R; only scworkbench activation is removed.
#'
#' @param pack Loaded namespace or package name.
#' @return Invisibly `TRUE` on success.
#' @export
wb_operation_pack_unload <- function(pack) {
  inspected <- wb_operation_pack_inspect(pack)
  namespace <- inspected$identity$namespace
  current <- .wb_operation_pack_registry$packs[[namespace]]
  active <- any(vapply(current$operation_names, function(op) {
    x <- .wb_operation_pack_registry$operations[[op]]
    as.integer(x$execution_depth %||% 0L) > 0L
  }, logical(1)))
  .wb_operation_pack_assert(!active && !isTRUE(current$used), "OPERATION_PACK_IN_USE",
    paste0("Operation pack '", namespace, "' cannot be unloaded after execution because active or staged session state may depend on it."),
    namespace = namespace, class = "wb_operation_pack_in_use")
  for (op in current$operation_names) .wb_operation_pack_registry$operations[[op]] <- NULL
  .wb_operation_pack_registry$packs[[namespace]] <- NULL
  invisible(TRUE)
}

.wb_operation_pack_definitions <- function() {
  records <- .wb_operation_pack_registry$operations
  if (!length(records)) return(list())
  names_sorted <- sort(names(records), method = "radix")
  stats::setNames(lapply(names_sorted, function(name) records[[name]]$definition), names_sorted)
}

.wb_operation_catalog <- function() {
  core <- .wb_op_catalog()
  external <- .wb_operation_pack_definitions()
  if (!length(external)) return(core)
  c(core, external)
}

.wb_operation_pack_identity_for_op <- function(op_name) {
  rec <- .wb_operation_pack_registry$operations[[as.character(op_name)[1]]]
  if (is.null(rec)) return(NULL)
  rec$definition$source_pack %||% NULL
}

#' Canonical Identity of the Runtime Operation Catalog
#'
#' The identity covers core operation interfaces plus explicitly loaded pack
#' identities and is independent of pack load order and process identifiers.
#'
#' @return A list containing the identity scheme, SHA-256, core operation count,
#'   and sorted loaded pack identities.
#' @export
wb_operation_catalog_identity <- function() {
  catalog <- .wb_operation_catalog()
  definitions <- lapply(names(catalog), function(name) {
    x <- catalog[[name]]
    list(op_name = name, title = x$title %||% "", description = x$description %||% "",
      intent = x$intent %||% character(), requires = x$requires %||% list(),
      optional_requires = x$optional_requires %||% list(), inputs = x$inputs %||% list(),
      params = x$params %||% list(), produces = x$produces %||% list(),
      promotable = x$promotable %||% character(), replay_equivalence = x$replay_equivalence %||% list(),
      source_pack = x$source_pack %||% NULL)
  })
  names(definitions) <- names(catalog)
  packs <- .wb_operation_pack_registry$packs
  pack_names <- if (length(packs)) sort(names(packs), method = "radix") else character(0)
  pack_ids <- lapply(pack_names, function(namespace) packs[[namespace]]$identity)
  names(pack_ids) <- pack_names
  payload <- list(protocol_version = .wb_operation_pack_protocol_version(),
                  definitions = definitions, loaded_packs = pack_ids)
  list(scheme = "scworkbench-operation-catalog-v1",
       sha256 = .wb_operation_pack_sha256(payload),
       core_operation_count = length(.wb_op_catalog()), loaded_packs = pack_ids)
}
