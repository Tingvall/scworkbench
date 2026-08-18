# Immutable, externally executed analysis-capsule registration.

.wb_capsule_schema <- function() "scworkbench.analysis_capsule.v1"
.wb_capsule_file_scheme <- function() "scworkbench.content.raw-file.sha256.v1"
.wb_capsule_signature_scheme <- function(kind) paste0("scworkbench.analysis_capsule.", kind, ".sha256.v1")
.wb_capsule_purposes <- function() c("dataset_specific_reporting", "custom_visualization", "custom_terminal_summary")
.wb_capsule_relationship_types <- function() c("reproduction_of", "variant_of")
.wb_capsule_decisions <- function() c("retain_as_capsule", "use_existing_op", "split_standard_and_custom", "propose_new_op")

.wb_ensure_analysis_capsule_tables <- function(con) {
  DBI::dbExecute(con, paste(
    "CREATE TABLE IF NOT EXISTS analysis_capsules (",
    "capsule_id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE, description TEXT, purpose TEXT NOT NULL, rationale TEXT NOT NULL,",
    "created_by TEXT, executed_at TEXT, registered_at TEXT NOT NULL, execution_mode TEXT NOT NULL, assurance_level TEXT NOT NULL, replay_status TEXT NOT NULL,",
    "language TEXT NOT NULL, entrypoint TEXT NOT NULL, script_path TEXT NOT NULL UNIQUE, script_sha256 TEXT NOT NULL, content_identity_scheme TEXT NOT NULL,",
    "manifest_path TEXT NOT NULL UNIQUE, manifest_sha256 TEXT NOT NULL, parameters_json TEXT NOT NULL, command_json TEXT NOT NULL, runtime_json TEXT NOT NULL,",
    "catalog_review_json TEXT NOT NULL, family_hint TEXT, limitations_json TEXT NOT NULL, input_shape_signature TEXT NOT NULL, parameter_shape_signature TEXT NOT NULL,",
    "output_shape_signature TEXT NOT NULL, similarity_signature TEXT NOT NULL, signature_schema TEXT NOT NULL, manifest_json TEXT NOT NULL",
    ");"
  ))
  DBI::dbExecute(con, paste(
    "CREATE TABLE IF NOT EXISTS analysis_capsule_inputs (",
    "capsule_id TEXT NOT NULL, input_order INTEGER NOT NULL, input_name TEXT NOT NULL, entity_kind TEXT NOT NULL, entity_id TEXT NOT NULL,",
    "content_sha256 TEXT NOT NULL, content_identity_scheme TEXT NOT NULL, observed_identity_json TEXT NOT NULL,",
    "PRIMARY KEY(capsule_id,input_order), UNIQUE(capsule_id,input_name),",
    "FOREIGN KEY(capsule_id) REFERENCES analysis_capsules(capsule_id) DEFERRABLE INITIALLY DEFERRED",
    ");"
  ))
  DBI::dbExecute(con, paste(
    "CREATE TABLE IF NOT EXISTS analysis_capsule_outputs (",
    "output_id TEXT PRIMARY KEY, capsule_id TEXT NOT NULL, output_order INTEGER NOT NULL, output_name TEXT NOT NULL, role TEXT NOT NULL, media_type TEXT NOT NULL,",
    "size_bytes INTEGER NOT NULL, path TEXT NOT NULL UNIQUE, content_sha256 TEXT NOT NULL, content_identity_scheme TEXT NOT NULL, structural_metadata_json TEXT NOT NULL,",
    "UNIQUE(capsule_id,output_order), UNIQUE(capsule_id,output_name),",
    "FOREIGN KEY(capsule_id) REFERENCES analysis_capsules(capsule_id) DEFERRABLE INITIALLY DEFERRED",
    ");"
  ))
  DBI::dbExecute(con, paste(
    "CREATE TABLE IF NOT EXISTS analysis_capsule_relationships (",
    "capsule_id TEXT NOT NULL, relationship_order INTEGER NOT NULL, relationship_type TEXT NOT NULL, related_capsule_id TEXT, external_manifest_identity TEXT,",
    "PRIMARY KEY(capsule_id,relationship_order),",
    "FOREIGN KEY(capsule_id) REFERENCES analysis_capsules(capsule_id) DEFERRABLE INITIALLY DEFERRED",
    "FOREIGN KEY(related_capsule_id) REFERENCES analysis_capsules(capsule_id) DEFERRABLE INITIALLY DEFERRED",
    ");"
  ))
  invisible(TRUE)
}

.wb_capsule_json <- function(x) as.character(jsonlite::toJSON(.wb_json_sanitize(x), auto_unbox = TRUE, null = "null", digits = NA))
.wb_capsule_parse <- function(x) jsonlite::fromJSON(as.character(x)[1L], simplifyVector = FALSE)
.wb_capsule_signature <- function(kind, x) {
  paste0(.wb_capsule_signature_scheme(kind), ":", .wb_prov_sha256_object(list(schema = .wb_capsule_signature_scheme(kind), value = x)))
}
.wb_capsule_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6%z")
.wb_capsule_db_value <- function(x) if (is.null(x) || !length(x)) NA_character_ else x
.wb_capsule_scalar <- function(x, label, required = TRUE) {
  if (is.null(x) && !required) return(NULL)
  .wb_assert(is.character(x) && length(x) == 1L && !is.na(x) && (!required || nzchar(trimws(x))), paste0(label, " must be one ", if (required) "non-empty " else "", "string."))
  as.character(x)
}

#' Construct a typed durable-entity reference
#'
#' @param entity_kind One of `matrix`, `space`, `artifact`, `model`,
#'   `metadata_field`, or `external_source`.
#' @param entity_id Stable public entity identity.
#' @return A portable typed reference accepted by [wb_capsule_register()].
#' @export
wb_ref_entity <- function(entity_kind, entity_id) {
  kind <- match.arg(.wb_capsule_scalar(entity_kind, "entity_kind"), c("matrix", "space", "artifact", "model", "metadata_field", "external_source"))
  id <- .wb_capsule_scalar(entity_id, "entity_id")
  structure(list(ref_type = "bundle_entity", entity_kind = kind, entity_id = id), class = "wb_entity_ref")
}

.wb_capsule_normalize_ref <- function(x, label) {
  if (.wb_is_metadata_field_ref(x)) return(list(ref_type = "bundle_entity", entity_kind = "metadata_field", entity_id = x$field_id))
  .wb_assert(is.list(x) && identical(as.character(x$ref_type %||% "")[1L], "bundle_entity"), paste0(label, " must be created by wb_ref_entity() or wb_ref_metadata_field()."))
  .wb_assert(!is.null(names(x)) && !anyDuplicated(names(x)) && setequal(names(x), c("ref_type", "entity_kind", "entity_id")), paste0(label, " is malformed."))
  wb_ref_entity(x$entity_kind, x$entity_id)
}

.wb_capsule_lifecycle_current <- function(bundle, kind, id) {
  if (!.wb_table_exists(bundle$con, "entity_lifecycle")) return(TRUE)
  kinds <- if(kind=="model")c("model_ref","model","artifact") else kind
  marks<-paste(rep("?",length(kinds)),collapse=",")
  row <- DBI::dbGetQuery(bundle$con, paste0("SELECT lifecycle_state FROM entity_lifecycle WHERE entity_kind IN (",marks,") AND entity_id = ?;"), params = c(as.list(kinds),list(id)))
  !nrow(row) || all(as.character(row$lifecycle_state)=="current")
}

.wb_capsule_input_identity <- function(bundle, ref) {
  kind <- as.character(ref$entity_kind); id <- as.character(ref$entity_id)
  .wb_assert(.wb_capsule_lifecycle_current(bundle, kind, id), paste0("CAPSULE_INPUT_NOT_CURRENT: ", kind, ":", id, " is deleted, tombstoned, or superseded."))
  if (kind == "metadata_field") {
    rows <- wb_metadata_fields(bundle, include_core = TRUE)
    row <- rows[as.character(rows$field_id) == id, , drop = FALSE]
    .wb_assert(nrow(row) == 1L, paste0("CAPSULE_INPUT_NOT_FOUND: metadata_field:", id))
    sha <- .wb_prov_sha256_object(as.list(row[1L, , drop = FALSE]))
    return(list(content_sha256 = sha, content_identity_scheme = "scworkbench.content.registry.canonical-json.v1", observed = list(field = as.list(row[1L, , drop = FALSE]))))
  }
  if (kind == "external_source") {
    rows <- wb_prov_source_inputs(bundle)
    row <- rows[as.character(rows$source_id) == id, , drop = FALSE]
    .wb_assert(nrow(row) > 0L, paste0("CAPSULE_INPUT_NOT_FOUND: external_source:", id))
    declarations <- unique(as.character(row$source_json))
    .wb_assert(length(declarations) == 1L, paste0("CAPSULE_INPUT_AMBIGUOUS: external_source:", id))
    declaration <- .wb_capsule_parse(declarations[[1L]])
    sha <- as.character(declaration$sha256 %||% declaration$checksum %||% "")[1L]
    .wb_assert(grepl("^[A-Fa-f0-9]{64}$", sha), paste0("CAPSULE_INPUT_UNBOUND: external_source:", id, " has no full SHA-256 identity."))
    return(list(content_sha256 = tolower(sha), content_identity_scheme = .wb_capsule_file_scheme(), observed = list(source_id = id, declaration_sha256 = .wb_prov_sha256_object(declaration))))
  }
  cert <- wb_entity_certificate(bundle, kind, id)
  state <- as.character(cert$lifecycle$state %||% "current")[1L]
  .wb_assert(identical(state, "current") || identical(state, "persisted"), paste0("CAPSULE_INPUT_NOT_CURRENT: ", kind, ":", id))
  candidates <- unlist(list(cert$identity$declared$content_sha256, cert$identity$observed$content_sha256, cert$identity$content_sha256, cert$producer$output$content_sha256), use.names = FALSE)
  candidates <- as.character(candidates[!is.na(candidates) & grepl("^[A-Fa-f0-9]{64}$", candidates)])
  schemes <- unlist(list(cert$identity$declared$content_identity_scheme, cert$identity$observed$content_identity_scheme, cert$identity$content_identity_scheme, cert$producer$output$content_identity_scheme), use.names = FALSE)
  schemes <- as.character(schemes[!is.na(schemes) & nzchar(schemes)])
  if (!length(candidates) && kind %in% c("matrix","space")) {
    primitive <- if (kind=="matrix") wb_prim_matrix(id) else wb_prim_space(id)
    identity <- .wb_prov_payload_identity(bundle,primitive)
    candidates <- as.character(identity$content_sha256 %||% character())
    schemes <- as.character(identity$content_identity_scheme %||% schemes)
  }
  if (!length(candidates) && kind %in% c("artifact","model") && .wb_table_exists(bundle$con,"artifact_model_ref")) {
    model <- DBI::dbGetQuery(bundle$con,"SELECT model_path FROM artifact_model_ref WHERE artifact_id=?;",params=list(id))
    if(nrow(model)) {
      path <- .wb_resolve_model_ref_path(bundle,as.character(model$model_path[[1L]]))
      identity <- .wb_prov_path_identity(path); candidates <- as.character(identity$content_sha256); schemes <- as.character(identity$content_identity_scheme)
    }
  }
  .wb_assert(length(candidates) > 0L && grepl("^[A-Fa-f0-9]{64}$",candidates[[1L]]), paste0("CAPSULE_INPUT_UNBOUND: ", kind, ":", id, " has no accepted full content identity."))
  list(content_sha256 = tolower(candidates[[1L]]), content_identity_scheme = schemes[[1L]] %||% "scworkbench.content.sha256.v1", observed = list(certificate_schema = cert$schema, node_id = cert$subject$node_id, lifecycle_state = state))
}

.wb_capsule_inputs_prepare <- function(bundle, inputs) {
  .wb_assert(is.list(inputs) && length(inputs) > 0L && !is.null(names(inputs)) && all(nzchar(names(inputs))) && !anyDuplicated(names(inputs)), "inputs must be a non-empty uniquely named list of public typed entity references.")
  .wb_assert(!any(grepl("[/\\\\]", names(inputs))) && !any(names(inputs) %in% c(".", "..")), "CAPSULE_BINDING_PATH_TRAVERSAL: input names cannot contain path separators or dot traversal components.")
  lapply(seq_along(inputs), function(i) {
    ref <- .wb_capsule_normalize_ref(inputs[[i]], paste0("inputs[['", names(inputs)[i], "']]"))
    identity <- .wb_capsule_input_identity(bundle, ref)
    list(order = i, name = names(inputs)[i], entity_kind = ref$entity_kind, entity_id = ref$entity_id, content_sha256 = identity$content_sha256, content_identity_scheme = identity$content_identity_scheme, observed_identity = identity$observed)
  })
}

.wb_capsule_assert_external_file <- function(bundle, path, label) {
  path <- .wb_capsule_scalar(path, label)
  .wb_assert(!nzchar(Sys.readlink(path)), paste0("CAPSULE_UNSAFE_PATH: ", label, " must not be a symlink."))
  info <- file.info(path)
  .wb_assert(nrow(info) == 1L && !is.na(info$isdir) && !info$isdir && file.exists(path), paste0("CAPSULE_FILE_REQUIRED: ", label, " must be an existing regular file."))
  .wb_assert(identical(as.character(fs::file_info(path)$type[[1L]]), "file"), paste0("CAPSULE_SPECIAL_FILE_REJECTED: ", label))
  root <- normalizePath(bundle$dir, winslash = "/", mustWork = TRUE)
  actual <- normalizePath(path, winslash = "/", mustWork = TRUE)
  .wb_assert(!identical(actual, root) && !startsWith(actual, paste0(root, "/")), paste0("CAPSULE_FORBIDDEN_BUNDLE_SOURCE: ", label, " is already inside the bundle."))
  actual
}

.wb_capsule_outputs_prepare <- function(bundle, outputs) {
  .wb_assert(is.list(outputs) && length(outputs) > 0L && !is.null(names(outputs)) && all(nzchar(names(outputs))) && !anyDuplicated(names(outputs)), "outputs must be a non-empty uniquely named list.")
  .wb_assert(!any(grepl("[/\\\\]", names(outputs))) && !any(names(outputs) %in% c(".", "..")), "CAPSULE_BINDING_PATH_TRAVERSAL: output names cannot contain path separators or dot traversal components.")
  authoritative <- c("matrix", "space", "model", "feature_set", "cell_set", "metadata", "metadata_field", "authoritative_matrix", "authoritative_space")
  out <- lapply(seq_along(outputs), function(i) {
    x <- outputs[[i]]
    if (is.character(x) && length(x) == 1L) x <- list(path = x)
    .wb_assert(is.list(x), paste0("outputs[['", names(outputs)[i], "']] must be a file declaration."))
    role <- .wb_capsule_scalar(x$role %||% "terminal_evidence", "output role")
    .wb_assert(!tolower(role) %in% authoritative, paste0("CAPSULE_AUTHORITATIVE_OUTPUT_REJECTED: ", role))
    path <- .wb_capsule_assert_external_file(bundle, x$path, paste0("output ", names(outputs)[i]))
    list(order = i, name = names(outputs)[i], source = path, role = role,
         media_type = .wb_capsule_scalar(x$media_type %||% "application/octet-stream", "output media_type"),
         structural_metadata = x$structural_metadata %||% list())
  })
  bases <- vapply(out, function(x) basename(x$source), character(1))
  .wb_assert(!anyDuplicated(bases) && !any(bases == "manifest.json"), "CAPSULE_OUTPUT_PATH_COLLISION: output basenames must be unique and cannot be manifest.json.")
  out
}

.wb_capsule_parameters <- function(parameters) {
  .wb_assert(is.list(parameters) && (length(parameters) == 0L || (!is.null(names(parameters)) && all(nzchar(names(parameters))) && !anyDuplicated(names(parameters)))), "parameters must be a uniquely named list.")
  lapply(seq_along(parameters), function(i) {
    x <- parameters[[i]]
    list(name = names(parameters)[i], value_type = if (is.null(x)) "null" else typeof(x), cardinality = if (is.null(x)) 0L else length(x), explicit_null = is.null(x), value = x)
  })
}

.wb_capsule_catalog_review <- function(x) {
  .wb_assert(is.list(x), "catalog_review is required and must be a structured list.")
  for (nm in c("catalog_identity", "catalog_version", "reviewed_at", "decision")) .wb_capsule_scalar(x[[nm]], paste0("catalog_review$", nm))
  decision <- match.arg(as.character(x$decision), .wb_capsule_decisions())
  .wb_assert(!identical(decision, "use_existing_op"), "CAPSULE_USE_EXISTING_OP: catalog review selected use_existing_op; execute the registered op instead.")
  .wb_assert(!identical(decision, "split_standard_and_custom") || isTRUE(x$minimized_custom_surface), "CAPSULE_SPLIT_REQUIRED: split_standard_and_custom requires minimized_custom_surface=TRUE after standard steps are executed as ops.")
  candidates<-as.character(x$candidate_op_names %||% character())
  .wb_assert(!anyNA(candidates)&&!anyDuplicated(candidates)&&all(nzchar(candidates)),"catalog_review$candidate_op_names must contain unique non-empty strings when supplied.")
  list(catalog_identity = as.character(x$catalog_identity), catalog_version = as.character(x$catalog_version), reviewed_at = as.character(x$reviewed_at), candidate_op_names = as.list(candidates), decision = decision, minimized_custom_surface = isTRUE(x$minimized_custom_surface), declaration = "operator_declared_not_engine_proven")
}

.wb_capsule_relationships <- function(bundle, relationships) {
  if (is.null(relationships)) return(list())
  .wb_assert(is.list(relationships), "relationships must be a list.")
  lapply(seq_along(relationships), function(i) {
    x <- relationships[[i]]; .wb_assert(is.list(x), "Each capsule relationship must be a list.")
    type <- match.arg(.wb_capsule_scalar(x$type, "relationship type"), .wb_capsule_relationship_types())
    local <- as.character(x$capsule_id %||% "")[1L]; external <- as.character(x$external_manifest_identity %||% "")[1L]
    .wb_assert(xor(nzchar(local), nzchar(external)), "A capsule relationship requires exactly one local capsule_id or complete external_manifest_identity.")
    if (nzchar(local)) .wb_assert(nrow(DBI::dbGetQuery(bundle$con, "SELECT 1 FROM analysis_capsules WHERE capsule_id=?;", params=list(local))) == 1L, paste0("Related capsule not found: ", local))
    if (nzchar(external)) .wb_assert(grepl("^sha256:[0-9a-fA-F]{64}$", external), "external_manifest_identity must be a complete sha256:<64 hex> identity.")
    list(order = i, type = type, capsule_id = if (nzchar(local)) local else NULL, external_manifest_identity = if (nzchar(external)) tolower(external) else NULL, assurance = "operator_declared_relationship")
  })
}

.wb_capsule_command <- function(command) {
  if (is.null(command)) return(list())
  command <- as.character(command)
  .wb_assert(length(command) > 0L && all(nzchar(command)), "command must be a non-empty character vector.")
  .wb_assert(!any(vapply(command, .wb_path_is_absolute, logical(1))) && !any(grepl("(^|[ =])(/|[A-Za-z]:[/\\\\])", command)), "CAPSULE_COMMAND_ABSOLUTE_PATH: declared command must not contain absolute host paths.")
  as.list(command)
}

.wb_capsule_publication_fault <- function(boundary, ...) {
  hook <- getOption("scworkbench.analysis_capsule_fault_hook", NULL)
  if (is.function(hook)) hook(boundary = boundary, ...)
  invisible(TRUE)
}

.wb_capsule_r_call_name <- function(head) {
  if (is.symbol(head)) return(as.character(head))
  if (is.call(head) && length(head) == 3L &&
      as.character(head[[1L]]) %in% c("::", ":::")) {
    return(as.character(head[[3L]]))
  }
  ""
}

.wb_capsule_r_registered_ops <- function(path, registered_ops) {
  expressions <- tryCatch(
    parse(file = path, keep.source = FALSE),
    error = function(e) stop(
      "CAPSULE_R_SOURCE_PARSE_FAILED: bounded operation review requires parseable R source: ",
      conditionMessage(e), call. = FALSE
    )
  )
  registered_ops <- unique(as.character(registered_ops))
  hits <- character()
  public_signature <- function(session, bundle, op_name, ..., inputs = list(), notes = NULL) NULL
  walk <- function(node) {
    if (is.call(node)) {
      call_name <- .wb_capsule_r_call_name(node[[1L]])
      private_prefix <- "wb_op_"
      if (startsWith(call_name, private_prefix)) {
        candidate <- substring(call_name, nchar(private_prefix) + 1L)
        if (candidate %in% registered_ops) hits <<- c(hits, candidate)
      }
      if (identical(call_name, "wb_session_run_op")) {
        normalized <- as.call(c(list(as.name("wb_session_run_op")), as.list(node)[-1L]))
        matched <- tryCatch(
          match.call(public_signature, normalized, expand.dots = FALSE),
          error = function(e) NULL
        )
        literal <- if (is.null(matched)) NULL else matched$op_name
        if (is.character(literal) && length(literal) == 1L &&
            !is.na(literal) && literal %in% registered_ops) {
          hits <<- c(hits, literal)
        }
      }
      for (child in as.list(node)[-1L]) walk(child)
    } else if (is.expression(node) || is.pairlist(node) || is.list(node)) {
      for (child in as.list(node)) walk(child)
    }
    invisible(NULL)
  }
  walk(expressions)
  unique(hits)
}

.wb_capsule_residue_inventory <- function(root, con) {
  capsule_root <- file.path(root, "analysis", "capsules")
  empty <- character()
  if (!dir.exists(capsule_root)) {
    return(list(pending = empty, orphan = empty, committed = empty))
  }
  committed <- if (.wb_table_exists(con, "analysis_capsules")) {
    as.character(DBI::dbGetQuery(con, "SELECT capsule_id FROM analysis_capsules;")$capsule_id)
  } else empty
  top <- as.character(fs::dir_ls(
    capsule_root, recurse = FALSE, type = "any", all = TRUE, follow = FALSE,
    fail = FALSE
  ))
  pending_root <- file.path(capsule_root, ".pending")
  pending_link <- Sys.readlink(pending_root)
  pending_is_link <- !is.na(pending_link) && nzchar(pending_link)
  pending <- if (dir.exists(pending_root) && !pending_is_link) {
    as.character(fs::dir_ls(
      pending_root, recurse = FALSE, type = "any", all = TRUE, follow = FALSE,
      fail = FALSE
    ))
  } else if (file.exists(pending_root) || pending_is_link) pending_root else empty
  legacy_pending <- top[grepl("^\\.pending-", basename(top))]
  final_entries <- top[!basename(top) %in% ".pending" &
                         !grepl("^\\.pending-", basename(top))]
  orphan <- final_entries[!basename(final_entries) %in% committed]
  list(
    pending = sort(unique(c(pending, legacy_pending))),
    orphan = sort(unique(orphan)),
    committed = sort(unique(committed))
  )
}

.wb_capsule_assert_no_residue <- function(bundle, operation) {
  residue <- .wb_capsule_residue_inventory(bundle$dir, bundle$con)
  paths <- c(residue$pending, residue$orphan)
  .wb_assert(
    !length(paths),
    paste0(
      "CAPSULE_UNRESOLVED_PUBLICATION_RESIDUE: ", operation,
      " requires recovery of ", paste(substring(paths, nchar(bundle$dir) + 2L), collapse = ", "), "."
    )
  )
  invisible(TRUE)
}

.wb_capsule_recover_residue <- function(bundle) {
  .wb_assert_bundle_writable(bundle, "analysis capsule publication recovery")
  .wb_with_bundle_writer_lock(bundle, operation = "analysis capsule publication recovery", code = {
    residue <- .wb_capsule_residue_inventory(bundle$dir, bundle$con)
    valid_id <- function(path) grepl("^cap_[A-Za-z0-9]+$", sub("^\\.pending-", "", basename(path)))
    for (path in residue$pending) {
      relative <- substring(path, nchar(normalizePath(bundle$dir, winslash = "/", mustWork = TRUE)) + 2L)
      status <- .wb_path_status(bundle$dir, relative, expected_type = "either", must_exist = TRUE,
                                purpose = "capsule pending recovery")
      .wb_assert(isTRUE(status$ok) && valid_id(path),
                 paste0("CAPSULE_RESIDUE_RECOVERY_REFUSED: unrecognized pending path ", path))
      unlink(status$absolute, recursive = TRUE, force = TRUE)
      .wb_assert(!file.exists(status$absolute) && !dir.exists(status$absolute),
                 paste0("CAPSULE_RESIDUE_RECOVERY_FAILED: ", status$relative))
    }
    for (path in residue$orphan) {
      link <- Sys.readlink(path); is_link <- !is.na(link) && nzchar(link)
      .wb_assert(dir.exists(path) && !is_link && valid_id(path),
                 paste0("CAPSULE_RESIDUE_RECOVERY_REFUSED: unrecognized orphan path ", path))
      manifest_path <- file.path(path, "manifest.json")
      manifest <- tryCatch(jsonlite::read_json(manifest_path, simplifyVector = FALSE),
                           error = function(e) NULL)
      .wb_assert(
        !is.null(manifest) && identical(as.character(manifest$schema), .wb_capsule_schema()) &&
          identical(as.character(manifest$capsule_id), basename(path)),
        paste0("CAPSULE_RESIDUE_RECOVERY_REFUSED: orphan is not a complete self-identifying capsule tree: ", path)
      )
      unlink(path, recursive = TRUE, force = TRUE)
      .wb_assert(!dir.exists(path), paste0("CAPSULE_RESIDUE_RECOVERY_FAILED: ", path))
    }
    pending_root <- file.path(bundle$dir, "analysis", "capsules", ".pending")
    if (dir.exists(pending_root) && !length(list.files(pending_root, all.files = TRUE, no.. = TRUE))) {
      unlink(pending_root, recursive = TRUE, force = TRUE)
    }
    .wb_capsule_assert_no_residue(bundle, "analysis capsule publication recovery")
    invisible(list(removed_pending = length(residue$pending), removed_orphan = length(residue$orphan)))
  })
}

#' Register externally executed terminal analysis evidence
#'
#' Registration copies exact source/output bytes. It does not execute code,
#' supervise the external runtime, validate scientific semantics, or establish
#' replay equivalence.
#' @param bundle Writable bundle.
#' @param name,description Capsule label and optional description.
#' @param inputs Uniquely named list of [wb_ref_entity()] references.
#' @param script Existing external source file.
#' @param outputs Uniquely named output declarations with `path`, `role`, and
#'   `media_type`.
#' @param parameters Named observed parameter values; explicit `NULL` is retained.
#' @param command Optional portable declared command vector.
#' @param runtime Declared runtime metadata, not engine-observed attestation.
#' @param executed_at,created_by Optional operator declarations.
#' @param purpose Controlled terminal-evidence purpose.
#' @param rationale Non-empty reason an installed op is inappropriate.
#' @param catalog_review Structured operation-catalog review declaration.
#' @param language Source language.
#' @param family_hint Optional operator-declared discovery hint.
#' @param relationships Optional typed capsule relationships.
#' @param limitations Optional recipient-facing limitations.
#' @return Registered capsule inspection record.
#' @export
wb_capsule_register <- function(bundle, name, description = NULL, inputs, script, outputs,
                                parameters = list(), command = NULL, runtime = list(),
                                executed_at = NULL, created_by = NULL, purpose, rationale,
                                catalog_review, language = NULL, family_hint = NULL,
                                relationships = list(), limitations = list()) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert_bundle_writable(bundle, "analysis capsule registration")
  .wb_require_pkg("jsonlite", "analysis capsule registration")
  name <- .wb_capsule_scalar(name, "name"); description <- .wb_capsule_scalar(description, "description", FALSE)
  purpose <- match.arg(.wb_capsule_scalar(purpose, "purpose"), .wb_capsule_purposes())
  rationale <- .wb_capsule_scalar(rationale, "rationale")
  family_hint <- .wb_capsule_scalar(family_hint, "family_hint", FALSE)
  if(!is.null(family_hint)) .wb_assert(nchar(family_hint)<=120L&&!grepl("[[:cntrl:]]",family_hint),"family_hint must be at most 120 printable characters.")
  script <- .wb_capsule_assert_external_file(bundle, script, "script")
  entrypoint <- basename(script)
  language <- as.character(language %||% if (grepl("[.]R$", entrypoint, ignore.case=TRUE)) "R" else if (grepl("[.]py$", entrypoint, ignore.case=TRUE)) "Python" else "declared_external")
  in_rows <- .wb_capsule_inputs_prepare(bundle, inputs)
  out_rows <- .wb_capsule_outputs_prepare(bundle, outputs)
  observed_parameters <- .wb_capsule_parameters(parameters)
  review <- .wb_capsule_catalog_review(catalog_review)
  rels <- .wb_capsule_relationships(bundle, relationships)
  command <- .wb_capsule_command(command)
  .wb_assert(is.list(runtime), "runtime must be a list declaration.")

  op_names <- tryCatch({z<-wb_list_ops();if(is.data.frame(z))as.character(z$op_name) else as.character(z)}, error=function(e) character())
  explicit <- if (identical(tolower(language), "r")) .wb_capsule_r_registered_ops(script, op_names) else character()
  .wb_assert(!length(explicit), paste0("CAPSULE_MINIMUM_CUSTOM_SURFACE: source explicitly calls registered operation(s): ", paste(explicit, collapse=", "), ". Execute standard transformations as ops and register only the terminal custom surface."))

  input_shape <- lapply(in_rows, function(x) list(name=x$name, entity_kind=x$entity_kind))
  parameter_shape <- lapply(observed_parameters, function(x) x[c("name","value_type","cardinality","explicit_null")])
  output_shape <- lapply(out_rows, function(x) list(name=x$name, role=x$role, media_type=x$media_type, structural_metadata=x$structural_metadata))
  sigs <- list(input_shape=.wb_capsule_signature("input-shape", input_shape), parameter_shape=.wb_capsule_signature("parameter-shape", parameter_shape), output_shape=.wb_capsule_signature("output-shape", output_shape))

  .wb_with_bundle_writer_lock(bundle, operation = "analysis capsule registration", code = {
    .wb_ensure_analysis_capsule_tables(bundle$con)
    .wb_assert(nrow(DBI::dbGetQuery(bundle$con, "SELECT 1 FROM analysis_capsules WHERE name=?;", params=list(name))) == 0L, paste0("Capsule name already exists: ", name))
    capsule_id <- .wb_allocate_db_identifier(bundle$con, "analysis_capsules", "capsule_id", "cap_", purpose="analysis capsule")
    output_ids <- vapply(seq_along(out_rows), function(i) .wb_allocate_db_identifier(bundle$con, "analysis_capsule_outputs", "output_id", "capout_", purpose="analysis capsule output"), character(1))
    final_rel <- file.path("analysis", "capsules", capsule_id)
    final_abs <- file.path(bundle$dir, final_rel)
    pending_root <- file.path(bundle$dir, "analysis", "capsules", ".pending")
    pending <- file.path(pending_root, capsule_id)
    .wb_assert(!dir.exists(final_abs) && !dir.exists(pending), "Capsule payload collision.")
    dir.create(file.path(pending,"source"), recursive=TRUE, showWarnings=FALSE)
    dir.create(file.path(pending,"outputs"), recursive=TRUE, showWarnings=FALSE)
    visible <- FALSE; committed <- FALSE
    on.exit({
      if (!committed && dir.exists(final_abs)) unlink(final_abs, recursive=TRUE, force=TRUE)
      if (dir.exists(pending)) unlink(pending, recursive=TRUE, force=TRUE)
      if (dir.exists(pending_root) && !length(list.files(pending_root, all.files=TRUE, no..=TRUE))) unlink(pending_root, recursive=TRUE, force=TRUE)
    }, add=TRUE)
    .wb_capsule_publication_fault("before_payload_publication", capsule_id=capsule_id)
    script_pending <- file.path(pending,"source",entrypoint)
    .wb_assert(file.copy(script, script_pending, copy.mode=FALSE, copy.date=FALSE), "Failed to stage capsule source.")
    script_sha <- .wb_prov_sha256_file(script_pending)
    for (i in seq_along(out_rows)) {
      dest <- file.path(pending,"outputs",basename(out_rows[[i]]$source))
      .wb_assert(file.copy(out_rows[[i]]$source, dest, copy.mode=FALSE, copy.date=FALSE), "Failed to stage capsule output.")
      out_rows[[i]]$path <- file.path(final_rel,"outputs",basename(dest))
      out_rows[[i]]$size_bytes <- unname(file.info(dest)$size)
      out_rows[[i]]$content_sha256 <- .wb_prov_sha256_file(dest)
      out_rows[[i]]$output_id <- output_ids[[i]]
      .wb_capsule_publication_fault("during_multifile_publication", capsule_id=capsule_id, publication_index=i)
    }
    source_sig <- paste0(.wb_capsule_signature_scheme("exact-source"), ":", script_sha)
    sigs$exact_source <- source_sig
    sigs$composite <- .wb_capsule_signature("similarity", list(input=sigs$input_shape, parameter=sigs$parameter_shape, output=sigs$output_shape, source=source_sig, family_hint=family_hint))
    registered_at <- .wb_capsule_now()
    manifest <- list(schema=.wb_capsule_schema(), capsule_id=capsule_id, name=name, description=description, purpose=purpose, rationale=rationale, created_by=created_by, executed_at=executed_at, registered_at=registered_at,
      execution=list(mode="externally_executed", assurance_level="content_registered", replay_status="not_verified", language=language, entrypoint=entrypoint, command=command, runtime=list(status="declared_not_observed", declaration=runtime)),
      source=list(path=file.path(final_rel,"source",entrypoint), content_sha256=script_sha, content_identity_scheme=.wb_capsule_file_scheme()), inputs=in_rows,
      parameters=observed_parameters, outputs=lapply(out_rows, function(x) x[setdiff(names(x),"source")]), catalog_review=review, family_hint=family_hint, relationships=rels, signatures=sigs,
      limitations=c(list("scworkbench verified accepted input identities and copied bytes; it did not observe or control execution.", "Matching hashes are not replay-equivalence evidence.", "Declared runtime metadata is not engine-observed runtime attestation."), limitations))
    manifest_identity_basis <- manifest
    manifest_identity_basis$manifest_identity <- NULL
    manifest$manifest_identity <- list(content_sha256=.wb_prov_sha256_object(manifest_identity_basis), content_identity_scheme="scworkbench.analysis_capsule.canonical-json.sha256.v1")
    manifest_txt <- .wb_capsule_json(manifest)
    writeLines(manifest_txt, file.path(pending,"manifest.json"), useBytes=TRUE)
    manifest_file_sha <- .wb_prov_sha256_file(file.path(pending,"manifest.json"))
    .wb_capsule_publication_fault("after_private_payload_staging", capsule_id=capsule_id)
    manifest_rel <- file.path(final_rel,"manifest.json")
    script_rel <- file.path(final_rel,"source",entrypoint)
    DBI::dbBegin(bundle$con)
    tryCatch({
      DBI::dbExecute(bundle$con, paste0("INSERT INTO analysis_capsules(capsule_id,name,description,purpose,rationale,created_by,executed_at,registered_at,execution_mode,assurance_level,replay_status,language,entrypoint,script_path,script_sha256,content_identity_scheme,manifest_path,manifest_sha256,parameters_json,command_json,runtime_json,catalog_review_json,family_hint,limitations_json,input_shape_signature,parameter_shape_signature,output_shape_signature,similarity_signature,signature_schema,manifest_json) VALUES(",paste(rep("?",30),collapse=","),");"), params=list(capsule_id,name,.wb_capsule_db_value(description),purpose,rationale,.wb_capsule_db_value(created_by),.wb_capsule_db_value(executed_at),registered_at,"externally_executed","content_registered","not_verified",language,entrypoint,script_rel,script_sha,.wb_capsule_file_scheme(),manifest_rel,manifest_file_sha,.wb_capsule_json(observed_parameters),.wb_capsule_json(command),.wb_capsule_json(list(status="declared_not_observed",declaration=runtime)),.wb_capsule_json(review),.wb_capsule_db_value(family_hint),.wb_capsule_json(manifest$limitations),sigs$input_shape,sigs$parameter_shape,sigs$output_shape,sigs$composite,"scworkbench.analysis_capsule.signatures.v1",manifest_txt))
      for (x in in_rows) DBI::dbExecute(bundle$con,"INSERT INTO analysis_capsule_inputs VALUES(?,?,?,?,?,?,?,?);",params=list(capsule_id,x$order,x$name,x$entity_kind,x$entity_id,x$content_sha256,x$content_identity_scheme,.wb_capsule_json(x$observed_identity)))
      for (x in out_rows) DBI::dbExecute(bundle$con,"INSERT INTO analysis_capsule_outputs VALUES(?,?,?,?,?,?,?,?,?,?,?);",params=list(x$output_id,capsule_id,x$order,x$name,x$role,x$media_type,x$size_bytes,x$path,x$content_sha256,.wb_capsule_file_scheme(),.wb_capsule_json(x$structural_metadata)))
      for (x in rels) DBI::dbExecute(bundle$con,"INSERT INTO analysis_capsule_relationships VALUES(?,?,?,?,?);",params=list(capsule_id,x$order,x$type,.wb_capsule_db_value(x$capsule_id),.wb_capsule_db_value(x$external_manifest_identity)))
      dir.create(dirname(final_abs),recursive=TRUE,showWarnings=FALSE)
      .wb_assert(file.rename(pending, final_abs), "Failed atomic capsule payload publication.")
      visible <- TRUE
      .wb_capsule_publication_fault("after_final_directory_rename_before_sqlite_commit", capsule_id=capsule_id)
      .wb_capsule_publication_fault("before_sqlite_commit", capsule_id=capsule_id)
      DBI::dbCommit(bundle$con); committed <- TRUE
      .wb_capsule_publication_fault("after_sqlite_commit_before_manifest_publication", capsule_id=capsule_id)
      tryCatch(.wb_capsule_publication_fault("commit_point", capsule_id=capsule_id), error=function(e) {
        .wb_manifest_publish_current_locked(bundle)
        stop(e)
      })
    }, error=function(e) {
      if (isTRUE(RSQLite::sqliteIsTransacting(bundle$con))) try(DBI::dbRollback(bundle$con),silent=TRUE)
      if (!committed && dir.exists(final_abs)) unlink(final_abs,recursive=TRUE,force=TRUE)
      stop(e)
    })
    wb_capsule(bundle,capsule_id)
  })
}

.wb_capsule_row_public <- function(row) {
  if (!nrow(row)) return(NULL)
  x <- as.list(row[1L,,drop=FALSE])
  for (nm in c("parameters_json","command_json","runtime_json","catalog_review_json","limitations_json","manifest_json")) x[[sub("_json$","",nm)]] <- .wb_capsule_parse(x[[nm]])
  x[c("parameters_json","command_json","runtime_json","catalog_review_json","limitations_json","manifest_json")] <- NULL
  class(x) <- c("wb_analysis_capsule","list")
  x
}

#' List registered analysis capsules
#' @param bundle Open bundle.
#' @return Data frame of lower-assurance terminal evidence records.
#' @export
wb_capsules <- function(bundle) {
  .wb_assert(inherits(bundle,"scworkbench_bundle"),"bundle must be scworkbench_bundle")
  if (!.wb_table_exists(bundle$con,"analysis_capsules")) return(data.frame(capsule_id=character(),name=character(),purpose=character(),assurance_level=character(),replay_status=character(),registered_at=character(),stringsAsFactors=FALSE))
  DBI::dbGetQuery(bundle$con,"SELECT capsule_id,name,description,purpose,assurance_level,replay_status,family_hint,registered_at,script_sha256,input_shape_signature,parameter_shape_signature,output_shape_signature,similarity_signature FROM analysis_capsules ORDER BY registered_at,capsule_id;")
}

#' Inspect one registered analysis capsule
#' @param bundle Open bundle.
#' @param capsule_id Capsule identity.
#' @return Complete normalized public capsule record.
#' @export
wb_capsule <- function(bundle,capsule_id) {
  .wb_assert(inherits(bundle,"scworkbench_bundle"),"bundle must be scworkbench_bundle")
  .wb_assert(.wb_table_exists(bundle$con,"analysis_capsules"),"CAPSULE_NOT_FOUND: no capsule registry exists.")
  row <- DBI::dbGetQuery(bundle$con,"SELECT * FROM analysis_capsules WHERE capsule_id=?;",params=list(as.character(capsule_id)[1L]))
  .wb_assert(nrow(row)==1L,paste0("CAPSULE_NOT_FOUND: ",capsule_id))
  out <- .wb_capsule_row_public(row)
  out$inputs <- wb_capsule_inputs(bundle,capsule_id); out$outputs <- wb_capsule_outputs(bundle,capsule_id)
  rel <- DBI::dbGetQuery(bundle$con,"SELECT relationship_order,relationship_type,related_capsule_id,external_manifest_identity FROM analysis_capsule_relationships WHERE capsule_id=? ORDER BY relationship_order;",params=list(capsule_id))
  out$relationships <- rel
  out
}

#' List ordered capsule input bindings
#' @inheritParams wb_capsule
#' @export
wb_capsule_inputs <- function(bundle,capsule_id) {
  .wb_assert(.wb_table_exists(bundle$con,"analysis_capsule_inputs"),"CAPSULE_NOT_FOUND: no capsule registry exists.")
  DBI::dbGetQuery(bundle$con,"SELECT input_order,input_name,entity_kind,entity_id,content_sha256,content_identity_scheme,observed_identity_json FROM analysis_capsule_inputs WHERE capsule_id=? ORDER BY input_order;",params=list(as.character(capsule_id)[1L]))
}

#' List ordered capsule output bindings
#' @inheritParams wb_capsule
#' @export
wb_capsule_outputs <- function(bundle,capsule_id) {
  .wb_assert(.wb_table_exists(bundle$con,"analysis_capsule_outputs"),"CAPSULE_NOT_FOUND: no capsule registry exists.")
  DBI::dbGetQuery(bundle$con,"SELECT output_id,output_order,output_name,role,media_type,size_bytes,path,content_sha256,content_identity_scheme,structural_metadata_json FROM analysis_capsule_outputs WHERE capsule_id=? ORDER BY output_order;",params=list(as.character(capsule_id)[1L]))
}

.wb_capsule_resolve_payload <- function(bundle, rel, expected, purpose) {
  status <- .wb_path_status(bundle$dir,rel,expected_type="file",must_exist=TRUE,purpose=purpose)
  .wb_assert(isTRUE(status$ok),paste0(status$code,": ",purpose))
  .wb_assert(!nzchar(Sys.readlink(status$absolute)),paste0("CAPSULE_SYMLINK_SUBSTITUTION: ",purpose))
  .wb_assert(identical(tolower(.wb_prov_sha256_file(status$absolute)),tolower(expected)),paste0("CAPSULE_CONTENT_MISMATCH: ",purpose))
  status$absolute
}

#' Resolve the verified bundle-owned capsule source path
#' @inheritParams wb_capsule
#' @export
wb_capsule_script_path <- function(bundle,capsule_id) {
  x <- wb_capsule(bundle,capsule_id)
  .wb_capsule_resolve_payload(bundle,x$script_path,x$script_sha256,"capsule script")
}

#' Resolve a verified bundle-owned capsule output path
#' @inheritParams wb_capsule
#' @param output_name Registered output name.
#' @export
wb_capsule_output_path <- function(bundle,capsule_id,output_name) {
  rows <- wb_capsule_outputs(bundle,capsule_id); hit <- rows[as.character(rows$output_name)==as.character(output_name)[1L],,drop=FALSE]
  .wb_assert(nrow(hit)==1L,paste0("CAPSULE_OUTPUT_NOT_FOUND: ",output_name))
  .wb_capsule_resolve_payload(bundle,hit$path[[1L]],hit$content_sha256[[1L]],paste0("capsule output ",output_name))
}

#' @export
print.wb_analysis_capsule <- function(x, ...) {
  cat("<wb_analysis_capsule>",x$capsule_id,"\n", "  externally executed terminal evidence; assurance:",x$assurance_level,"; replay:",x$replay_status,"\n")
  invisible(x)
}

#' Scaffold a portable externally executed capsule workspace
#' @param bundle Open bundle used only to validate declared inputs.
#' @param name Capsule name.
#' @param inputs Named public entity references.
#' @param outputs Named output declarations (role and media type; paths are generated).
#' @param language Currently `R`.
#' @param out_dir New workspace directory.
#' @param purpose,rationale Mandatory policy declarations.
#' @return Normalized workspace path.
#' @export
wb_capsule_scaffold <- function(bundle,name,inputs,outputs,language="R",out_dir,purpose,rationale) {
  name <- .wb_capsule_scalar(name,"name"); purpose <- match.arg(.wb_capsule_scalar(purpose,"purpose"),.wb_capsule_purposes()); rationale <- .wb_capsule_scalar(rationale,"rationale")
  .wb_capsule_inputs_prepare(bundle,inputs)
  .wb_assert(is.list(outputs)&&length(outputs)>0L&&!is.null(names(outputs))&&all(nzchar(names(outputs)))&&!anyDuplicated(names(outputs)),"outputs must be a non-empty uniquely named list of terminal declarations.")
  .wb_assert(identical(toupper(language),"R"),"Capsule scaffold v1 supports language='R'.")
  out_dir <- normalizePath(out_dir,winslash="/",mustWork=FALSE); .wb_assert(!dir.exists(out_dir),"out_dir must not already exist.")
  dir.create(file.path(out_dir,"outputs"),recursive=TRUE,showWarnings=FALSE)
  refs <- lapply(inputs,.wb_capsule_normalize_ref,label="input")
  output_specs <- lapply(seq_along(outputs),function(i){x<-outputs[[i]];if(!is.list(x))x<-list();list(name=names(outputs)[i],role=x$role%||%"terminal_evidence",media_type=x$media_type%||%"application/octet-stream",path=file.path("outputs",paste0(names(outputs)[i],x$extension%||%".out")))})
  spec <- list(schema="scworkbench.analysis_capsule.draft.v1",name=name,purpose=purpose,rationale=rationale,status="not_executed",bundle_path_parameter="SCWORKBENCH_BUNDLE",inputs=refs,parameters=list(),outputs=output_specs)
  writeLines(.wb_capsule_json(spec),file.path(out_dir,"capsule-spec.json"),useBytes=TRUE)
  getter_lines <- vapply(seq_along(refs),function(i){r<-refs[[i]]; if(r$entity_kind=="metadata_field") sprintf("inputs[['%s']] <- wb_metadata_field_resolve(bundle, wb_ref_metadata_field('%s'))",names(inputs)[i],r$entity_id) else sprintf("inputs[['%s']] <- wb_entity_certificate(bundle, '%s', '%s')",names(inputs)[i],r$entity_kind,r$entity_id)},character(1))
  lines <- c("library(scworkbench)","args <- commandArgs(trailingOnly = TRUE)","if (length(args) != 2L) stop('usage: Rscript analysis.R <bundle> <workspace>')","bundle <- wb_open_bundle(args[[1L]], read_only = TRUE)","on.exit(wb_close_bundle(bundle), add = TRUE)","workspace <- normalizePath(args[[2L]], winslash = '/', mustWork = TRUE)","output_dir <- file.path(workspace, 'outputs')","stopifnot(dir.exists(output_dir))","spec <- jsonlite::fromJSON(file.path(workspace, 'capsule-spec.json'), simplifyVector = FALSE)","parameters <- spec$parameters","inputs <- list()",getter_lines,"# ---- researcher-owned analysis begins ----","# Write only declared terminal files beneath output_dir.","# No scientific analysis is invented by this scaffold.","# ---- researcher-owned analysis ends ----")
  writeLines(lines,file.path(out_dir,"analysis.R"),useBytes=TRUE)
  out_dir
}

#' Export exact registered source and reproduction inspection metadata
#' @inheritParams wb_capsule
#' @param out_dir New export directory.
#' @return Normalized export path. Export status is `source_exported`, never replay verified.
#' @export
wb_capsule_emit_reproduction <- function(bundle,capsule_id,out_dir) {
  x <- wb_capsule(bundle,capsule_id); out_dir<-normalizePath(out_dir,winslash="/",mustWork=FALSE);.wb_assert(!dir.exists(out_dir),"out_dir must not already exist.")
  dir.create(out_dir,recursive=TRUE,showWarnings=FALSE)
  file.copy(wb_capsule_script_path(bundle,capsule_id),file.path(out_dir,x$entrypoint),copy.mode=FALSE,copy.date=FALSE)
  metadata <- list(schema="scworkbench.analysis_capsule.reproduction.v1",export_status="source_exported",replay_ready=FALSE,replay_verified=FALSE,capsule_id=capsule_id,source=list(entrypoint=x$entrypoint,content_sha256=x$script_sha256),inputs=x$inputs,parameters=x$parameters,command=x$command,runtime=x$runtime,expected_outputs=x$outputs,assurance_level=x$assurance_level,replay_status=x$replay_status)
  writeLines(.wb_capsule_json(metadata),file.path(out_dir,"reproduction.json"),useBytes=TRUE)
  writeLines(c("library(scworkbench)","args <- commandArgs(trailingOnly=TRUE)","if (length(args) != 1L) stop('usage: Rscript inspect.R <bundle>')","bundle <- wb_open_bundle(args[[1L]], read_only=TRUE)","on.exit(wb_close_bundle(bundle), add=TRUE)",sprintf("print(wb_capsule(bundle, '%s'))",capsule_id),sprintf("print(wb_capsule_inputs(bundle, '%s'))",capsule_id),sprintf("print(wb_capsule_outputs(bundle, '%s'))",capsule_id)),file.path(out_dir,"inspect.R"),useBytes=TRUE)
  out_dir
}

.wb_validate_analysis_capsules <- function(root, con, add, content = TRUE) {
  if (!.wb_table_exists(con,"analysis_capsules")) return(invisible(TRUE))
  residue <- .wb_capsule_residue_inventory(root, con)
  relative <- function(path) substring(path, nchar(normalizePath(root, winslash="/", mustWork=TRUE)) + 2L)
  if (length(residue$pending)) for (path in residue$pending) add(
    "CAPSULE_PENDING_RESIDUE", check_class="analysis_capsules",
    entity_kind="pending_publication", entity_id=basename(path), path=relative(path),
    observed="uncommitted private payload", message="An interrupted analysis-capsule private publication tree requires writer-locked recovery."
  )
  if (length(residue$orphan)) for (path in residue$orphan) add(
    "CAPSULE_ORPHAN_PAYLOAD", check_class="analysis_capsules",
    entity_kind="capsule", entity_id=basename(path), path=relative(path),
    observed="payload directory without committed registry row", message="An analysis-capsule payload tree is visible without a corresponding committed registry row."
  )
  caps <- DBI::dbGetQuery(con,"SELECT * FROM analysis_capsules ORDER BY capsule_id;")
  for (i in seq_len(nrow(caps))) {
    row <- caps[i,,drop=FALSE]; id <- as.character(row$capsule_id[[1L]])
    issue <- function(code,path=NA_character_,expected=NA_character_,observed=NA_character_,message) add(code,check_class="analysis_capsules",entity_kind="capsule",entity_id=id,path=path,expected=expected,observed=observed,message=message)
    if (!identical(as.character(row$execution_mode[[1L]]),"externally_executed") || !identical(as.character(row$assurance_level[[1L]]),"content_registered") || !identical(as.character(row$replay_status[[1L]]),"not_verified")) issue("CAPSULE_UNSUPPORTED_ASSURANCE_CLAIM",message="Capsule registry contains an unsupported execution, assurance, or replay claim.")
    for (spec in list(list("script_path","script_sha256","CAPSULE_SCRIPT"),list("manifest_path","manifest_sha256","CAPSULE_MANIFEST"))) {
      rel <- as.character(row[[spec[[1L]]]][[1L]]); status <- .wb_path_status(root,rel,expected_type="file",must_exist=TRUE,purpose="capsule validation")
      if (!isTRUE(status$ok)) issue(paste0(spec[[3L]],"_MISSING_OR_UNSAFE"),rel,message=paste0(spec[[3L]]," payload is missing, escaped, or unsafe."))
      else if (nzchar(Sys.readlink(status$absolute))) issue(paste0(spec[[3L]],"_SYMLINK"),rel,message="Capsule payload was replaced by a symlink.")
      else if (isTRUE(content)) { actual <- .wb_prov_sha256_file(status$absolute); expected <- as.character(row[[spec[[2L]]]][[1L]]); if(!identical(tolower(actual),tolower(expected))) issue(paste0(spec[[3L]],"_CONTENT_MISMATCH"),rel,expected,actual,"Capsule payload bytes differ from the immutable registry identity.") }
    }
    manifest <- tryCatch(.wb_capsule_parse(readLines(file.path(root,row$manifest_path[[1L]]),warn=FALSE)),error=function(e) NULL)
    if (is.null(manifest)) issue("CAPSULE_MANIFEST_MALFORMED",row$manifest_path[[1L]],message="Capsule manifest is malformed JSON.")
    else {
      if (!identical(as.character(manifest$schema),.wb_capsule_schema())) issue("CAPSULE_MANIFEST_SCHEMA_UNSUPPORTED",row$manifest_path[[1L]],.wb_capsule_schema(),as.character(manifest$schema),"Capsule manifest schema is unsupported.")
      stored <- tryCatch(.wb_capsule_parse(row$manifest_json[[1L]]),error=function(e) NULL)
      if (is.null(stored) || !identical(.wb_capsule_json(manifest),.wb_capsule_json(stored))) issue("CAPSULE_MANIFEST_REGISTRY_DISAGREEMENT",row$manifest_path[[1L]],message="Capsule manifest and SQLite registry disagree.")
    }
    ins <- DBI::dbGetQuery(con,"SELECT * FROM analysis_capsule_inputs WHERE capsule_id=? ORDER BY input_order;",params=list(id))
    if (!nrow(ins) || anyDuplicated(ins$input_name) || !identical(as.integer(ins$input_order),seq_len(nrow(ins)))) issue("CAPSULE_INPUT_BINDINGS_INVALID",message="Capsule ordered input bindings are missing or invalid.")
    if(nrow(ins)) {
      reader<-structure(list(dir=root,con=con,manifest=list(),read_only=TRUE),class="scworkbench_bundle")
      for(j in seq_len(nrow(ins))) {
        observed<-tryCatch(.wb_capsule_input_identity(reader,list(entity_kind=as.character(ins$entity_kind[j]),entity_id=as.character(ins$entity_id[j]))),error=identity)
        if(inherits(observed,"error")) issue("CAPSULE_INPUT_ENTITY_INVALID",message=paste0("Capsule input binding is no longer a valid accepted entity: ",conditionMessage(observed)))
        else if(isTRUE(content)&&(!identical(tolower(as.character(observed$content_sha256)),tolower(as.character(ins$content_sha256[j])))||!identical(as.character(observed$content_identity_scheme),as.character(ins$content_identity_scheme[j])))) issue("CAPSULE_INPUT_IDENTITY_MISMATCH",expected=as.character(ins$content_sha256[j]),observed=as.character(observed$content_sha256),message="Capsule input current identity differs from the immutable accepted binding.")
      }
    }
    outs <- DBI::dbGetQuery(con,"SELECT * FROM analysis_capsule_outputs WHERE capsule_id=? ORDER BY output_order;",params=list(id))
    if (!nrow(outs) || anyDuplicated(outs$output_name) || anyDuplicated(outs$path) || !identical(as.integer(outs$output_order),seq_len(nrow(outs)))) issue("CAPSULE_OUTPUT_BINDINGS_INVALID",message="Capsule ordered output bindings are missing or invalid.")
    if (!is.null(manifest)) {
      expected_inputs <- lapply(manifest$inputs %||% list(),function(x)list(order=as.integer(x$order),name=as.character(x$name),entity_kind=as.character(x$entity_kind),entity_id=as.character(x$entity_id),content_sha256=as.character(x$content_sha256),content_identity_scheme=as.character(x$content_identity_scheme)))
      observed_inputs <- lapply(seq_len(nrow(ins)),function(j)list(order=as.integer(ins$input_order[j]),name=as.character(ins$input_name[j]),entity_kind=as.character(ins$entity_kind[j]),entity_id=as.character(ins$entity_id[j]),content_sha256=as.character(ins$content_sha256[j]),content_identity_scheme=as.character(ins$content_identity_scheme[j])))
      if(!identical(.wb_capsule_json(expected_inputs),.wb_capsule_json(observed_inputs))) issue("CAPSULE_INPUT_MANIFEST_REGISTRY_DISAGREEMENT",message="Capsule manifest and registry input bindings disagree or historical bindings were deleted.")
      expected_outputs <- lapply(manifest$outputs %||% list(),function(x)list(output_id=as.character(x$output_id),order=as.integer(x$order),name=as.character(x$name),role=as.character(x$role),media_type=as.character(x$media_type),size_bytes=as.numeric(x$size_bytes),path=as.character(x$path),content_sha256=as.character(x$content_sha256)))
      observed_outputs <- lapply(seq_len(nrow(outs)),function(j)list(output_id=as.character(outs$output_id[j]),order=as.integer(outs$output_order[j]),name=as.character(outs$output_name[j]),role=as.character(outs$role[j]),media_type=as.character(outs$media_type[j]),size_bytes=as.numeric(outs$size_bytes[j]),path=as.character(outs$path[j]),content_sha256=as.character(outs$content_sha256[j])))
      if(!identical(.wb_capsule_json(expected_outputs),.wb_capsule_json(observed_outputs))) issue("CAPSULE_OUTPUT_MANIFEST_REGISTRY_DISAGREEMENT",message="Capsule manifest and registry output bindings disagree or historical outputs were deleted.")
    }
    if (nrow(outs)) for(j in seq_len(nrow(outs))) {
      rel<-as.character(outs$path[j]);status<-.wb_path_status(root,rel,expected_type="file",must_exist=TRUE,purpose="capsule output validation")
      if(!isTRUE(status$ok)) issue("CAPSULE_OUTPUT_MISSING_OR_UNSAFE",rel,message="Capsule output is missing, escaped, or unsafe.")
      else if(nzchar(Sys.readlink(status$absolute))) issue("CAPSULE_OUTPUT_SYMLINK",rel,message="Capsule output was replaced by a symlink.")
      else if(isTRUE(content)){actual<-.wb_prov_sha256_file(status$absolute);expected<-as.character(outs$content_sha256[j]);if(!identical(tolower(actual),tolower(expected))) issue("CAPSULE_OUTPUT_CONTENT_MISMATCH",rel,expected,actual,"Capsule output bytes differ from the immutable registry identity.")}
    }
  }
  invisible(TRUE)
}
