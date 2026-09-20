# ABI-v3 G3: generic, path-free supported external-state adoption.

.wb_operation_pack_v3_external_candidates <- new.env(parent = emptyenv())

.wb_operation_pack_v3_external_candidate_get <- function(value,
    consume = FALSE) {
  if (!.wb_is_primitive(value) || !identical(value$kind,
      "external_state_candidate") || !nzchar(as.character(
        value$candidate_token %||% "")[1]))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "External-state candidate handle is absent or malformed.", "resolution")
  token <- as.character(value$candidate_token)[1]
  if (!exists(token, envir = .wb_operation_pack_v3_external_candidates,
      inherits = FALSE)) .wb_operation_pack_v3_error(
        "PYBENCH_INPUT_IDENTITY_MISMATCH",
        "External-state candidate is expired or has already been consumed.",
        "resolution")
  record <- get(token, envir = .wb_operation_pack_v3_external_candidates,
    inherits = FALSE)
  if (isTRUE(consume)) rm(list = token,
    envir = .wb_operation_pack_v3_external_candidates)
  record
}

.wb_operation_pack_v3_external_candidate_discard <- function(value) {
  token <- as.character(value$candidate_token %||% "")[1]
  if (!nzchar(token) || !exists(token,
      envir = .wb_operation_pack_v3_external_candidates, inherits = FALSE))
    return(invisible(FALSE))
  record <- get(token, envir = .wb_operation_pack_v3_external_candidates,
    inherits = FALSE)
  rm(list = token, envir = .wb_operation_pack_v3_external_candidates)
  if (dir.exists(record$root)) unlink(record$root, recursive = TRUE,
    force = TRUE)
  invisible(TRUE)
}

#' Create an authenticated external-state adoption candidate
#'
#' This constructor admits caller-owned bytes into a private, core-owned
#' candidate tree before an operation pack runs. The returned primitive is an
#' opaque, single-transition handle: operation-pack code receives only bounded
#' entry readers and never receives a host path or mutable authority handle.
#'
#' @param engine External model engine.
#' @param model_type External model type.
#' @param cells Exact fitted cell identifiers in order.
#' @param entries Named list of nonempty raw vectors. Names are archive-relative
#'   model-tree entry paths.
#' @param primary_path One entry name identifying the primary model payload.
#' @return An ephemeral `external_state_candidate` primitive.
#' @export
wb_supported_external_state_candidate <- function(engine, model_type, cells,
    entries, primary_path) {
  engine <- as.character(engine)[1]
  model_type <- as.character(model_type)[1]
  cells <- as.character(cells)
  primary_path <- as.character(primary_path)[1]
  .wb_assert(nzchar(engine) && nzchar(model_type),
    "External-state engine and model_type must be nonempty.")
  .wb_assert(length(cells) > 0L && !anyNA(cells) && all(nzchar(cells)) &&
      !anyDuplicated(cells),
    "External-state candidate cells must be unique, nonempty, and ordered.")
  .wb_assert(is.list(entries) && length(entries) > 0L &&
      !is.null(names(entries)) && all(nzchar(names(entries))) &&
      !anyDuplicated(names(entries)) &&
      all(vapply(names(entries), .wb_operation_pack_v3_safe_model_entry,
        logical(1))) && primary_path %in% names(entries),
    "External-state entries must be uniquely named safe relative paths and include primary_path.")
  .wb_assert(all(vapply(entries, function(x) is.raw(x) && length(x) > 0L,
    logical(1))), "External-state entries must be nonempty raw vectors.")
  root <- tempfile("scwb-external-state-candidate-")
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  ok <- FALSE
  on.exit(if (!ok && dir.exists(root)) unlink(root, recursive = TRUE,
    force = TRUE), add = TRUE)
  for (path in names(entries)) {
    target <- file.path(root, path)
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    con <- file(target, open = "wb")
    tryCatch(writeBin(entries[[path]], con), finally = close(con))
    Sys.chmod(target, mode = "0444")
  }
  manifest <- .wb_operation_pack_v3_model_tree_manifest(root, engine,
    model_type, primary_path)
  token <- .wb_allocate_identifier("candidate_", 24L,
    purpose = "external-state candidate")
  record <- list(root = root, engine = engine, model_type = model_type,
    cells = cells, tree_manifest = manifest,
    payload_manifest_identity =
      .wb_operation_pack_v3_model_payload_identity(manifest))
  assign(token, record, envir = .wb_operation_pack_v3_external_candidates)
  ok <- TRUE
  structure(list(kind = "external_state_candidate",
    candidate_token = token, engine = engine, model_type = model_type,
    cell_id = cells), class = "wb_primitive")
}

.wb_operation_pack_v3_g3_declaration <- function(operation) {
  declarations <- operation$supported_external_state_adoptions %||% list()
  if (!length(declarations)) return(NULL)
  declarations[[1L]]
}

.wb_operation_pack_v3_g3_source_snapshot <- function(bundle, reference) {
  required <- c("source_id", "snapshot_id", "run_id")
  if (!is.list(reference) || !all(required %in% names(reference)) ||
      any(!vapply(reference[required], function(x) {
        x <- as.character(x %||% "")[1]; !is.na(x) && nzchar(x)
      }, logical(1)))) .wb_operation_pack_v3_error(
        "PYBENCH_INPUT_IDENTITY_MISMATCH",
        "External source reference must contain exact source_id, snapshot_id, and run_id.",
        "resolution")
  row <- DBI::dbGetQuery(bundle$con, paste0(
    "SELECT snapshot_id,run_id,source_id,source_json,checksum_status ",
    "FROM prov_source_inputs WHERE source_id=? AND snapshot_id=? AND run_id=?;"),
    params = list(as.character(reference$source_id)[1],
      as.character(reference$snapshot_id)[1], as.character(reference$run_id)[1]))
  if (nrow(row) != 1L) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "External source snapshot does not resolve exactly one immutable record.",
    "resolution")
  declaration <- tryCatch(jsonlite::fromJSON(row$source_json[[1]],
    simplifyVector = FALSE), error = identity)
  if (inherits(declaration, "error") ||
      !identical(as.character(row$checksum_status[[1]]), "checksummed"))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "External source snapshot is malformed or not checksummed.",
      "resolution")
  digest <- tolower(as.character(declaration$sha256 %||%
    declaration$checksum %||% "")[1])
  if (!grepl("^[a-f0-9]{64}$", digest))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "External source snapshot has no valid SHA-256 declaration.",
      "resolution")
  lifecycle <- DBI::dbGetQuery(bundle$con, paste0(
    "SELECT lifecycle_state FROM entity_lifecycle ",
    "WHERE entity_kind='external_source' AND entity_id=?;"),
    params = list(as.character(reference$source_id)[1]))
  if (nrow(lifecycle) != 1L || !identical(as.character(
      lifecycle$lifecycle_state[[1]]), "current"))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "External source snapshot is not the unique current lifecycle record.",
      "resolution")
  declared <- list(scheme = unname(.wb_content_identity_schemes()[["raw_file"]]),
    sha256 = digest)
  snapshot <- list(entity_kind = "external_source",
    source_id = as.character(row$source_id[[1]]),
    source_snapshot_id = as.character(row$snapshot_id[[1]]),
    source_run_id = as.character(row$run_id[[1]]),
    scope = as.character(declaration$scope %||% "external_file")[1],
    lifecycle_state = "current", recorded_checksum_status = "checksummed",
    declared_content_identity = declared)
  snapshot$source_snapshot_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.external_source_adoption_snapshot.v1",
    "external source snapshot excluding source_snapshot_identity", snapshot)
  list(snapshot = snapshot, declaration = declaration)
}

.wb_operation_pack_v3_g3_byte_evidence <- function(bundle, source,
    allowed) {
  declaration <- source$declaration
  declared <- source$snapshot$declared_content_identity
  raw_path <- as.character(declaration$path %||% "")[1]
  bundled <- isTRUE(declaration$bundled)
  observed <- NULL
  status <- if (bundled && nzchar(raw_path)) {
    checked <- .wb_path_status(bundle$dir, raw_path, expected_type = "file",
      must_exist = FALSE, purpose = "external-state source verification")
    if (isTRUE(checked$ok) && file.exists(checked$absolute)) {
      actual <- tolower(.wb_operation_pack_v2_file_sha256(checked$absolute))
      if (!identical(actual, declared$sha256))
        .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
          "Observed external source checksum differs from its declaration.",
          "resolution")
      observed <- list(scheme = declared$scheme, sha256 = actual)
      "bytes_verified"
    } else "bytes_unavailable"
  } else if (nzchar(raw_path) && file.exists(raw_path)) {
    "bytes_not_inspected"
  } else "bytes_unavailable"
  if (!status %in% as.character(unlist(allowed, use.names = FALSE)))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      paste0("Source-byte state is not manifest-authorized: ", status),
      "resolution")
  value <- list(status = status, declared_content_identity = declared,
    observed_content_identity = observed,
    nonverification_reason = switch(status,
      bytes_verified = NULL,
      bytes_not_inspected = "policy_did_not_inspect_external_bytes",
      bytes_unavailable = "external_bytes_unavailable"))
  value$source_byte_evidence_identity <-
    .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.external_source_byte_evidence.v1",
      "external source byte evidence excluding source_byte_evidence_identity",
      value)
  value
}

.wb_operation_pack_v3_g3_prepare <- function(bundle, operation, inputs,
    params, request, stage_root) {
  declaration <- .wb_operation_pack_v3_g3_declaration(operation)
  if (is.null(declaration)) return(list(grants = list(), candidate = NULL))
  state_name <- as.character(declaration$state_input)[1]
  candidate_value <- inputs[[state_name]]
  candidate <- .wb_operation_pack_v3_external_candidate_get(candidate_value)
  selected <- list(engine = candidate$engine, model_type = candidate$model_type)
  allowed_types <- declaration$allowed_state_types %||% list()
  if (!any(vapply(allowed_types, identical, logical(1), selected)))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "External-state candidate type is not manifest-authorized.", "resolution")
  if (!identical(as.character(declaration$primary_path)[1],
      candidate$tree_manifest$primary_path) ||
      candidate$tree_manifest$file_count > as.integer(
        declaration$maximum_file_count) ||
      candidate$tree_manifest$total_size > as.numeric(
        declaration$maximum_total_bytes) ||
      length(candidate$cells) > as.integer(declaration$maximum_cell_count))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "External-state candidate violates its declared tree limits.",
      "resolution")
  source <- .wb_operation_pack_v3_g3_source_snapshot(bundle,
    params[[as.character(declaration$source_parameter)[1]]])
  evidence <- .wb_operation_pack_v3_g3_byte_evidence(bundle, source,
    declaration$allowed_source_byte_states)
  model_name <- as.character(declaration$model_output)[1]
  outputs <- stats::setNames(request$outputs,
    vapply(request$outputs, `[[`, character(1), "name"))
  model <- outputs[[model_name]]
  writer <- model$descriptor$contained_model_sibling_write_grant %||% NULL
  if (is.null(writer)) .wb_operation_pack_v3_error(
    "PYBENCH_CAPABILITY_MISMATCH",
    "G3 requires the generic G2 sibling-bound model writer.", "staging")
  if (!identical(writer$engine, selected$engine) ||
      !identical(writer$model_type, selected$model_type) ||
      !identical(writer$primary_path, candidate$tree_manifest$primary_path) ||
      !identical(writer$model_source_linkage$fitted_cell_order_identity,
        .wb_operation_pack_v2_identity_plain("scworkbench.cell_order.v1",
          unname(as.list(candidate$cells)))))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Candidate state differs from the G2 model linkage or ordered-cell identity.",
      "resolution")
  relative_root <- paste0("external_state_adoptions/",
    as.character(declaration$name)[1], "/tree")
  target <- file.path(stage_root, relative_root)
  .wb_operation_pack_v3_copy_model_tree(candidate$root,
    candidate$tree_manifest, target)
  observed <- .wb_operation_pack_v3_model_tree_manifest(target,
    selected$engine, selected$model_type, candidate$tree_manifest$primary_path,
    declaration$maximum_file_count, declaration$maximum_total_bytes,
    code = "PYBENCH_INPUT_IDENTITY_MISMATCH", phase = "staging")
  if (!identical(observed, candidate$tree_manifest))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Private candidate copy differs from admitted bytes.", "staging")
  ordered_cell_identity <- .wb_operation_pack_v2_identity_plain(
    "scworkbench.cell_order.v1", unname(as.list(candidate$cells)))
  snapshot <- list(selected_state_type = selected,
    tree_manifest = candidate$tree_manifest,
    tree_manifest_identity = .wb_operation_pack_v3_unscoped_identity(
      candidate$tree_manifest$manifest_identity),
    payload_manifest_identity = candidate$payload_manifest_identity,
    primary_path = candidate$tree_manifest$primary_path,
    file_count = candidate$tree_manifest$file_count,
    total_bytes = candidate$tree_manifest$total_size,
    ordered_cell_count = as.integer(length(candidate$cells)),
    ordered_cell_identity = ordered_cell_identity,
    integrity_status = "authenticated", relative_root = relative_root)
  snapshot$candidate_snapshot_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.external_state_candidate.v1",
    "external state candidate excluding candidate_snapshot_identity", snapshot)
  closure_names <- unique(c(model_name, as.character(unlist(
    declaration$required_closure_outputs, use.names = FALSE))))
  if (!identical(closure_names, vapply(Filter(function(x) x$name %in%
      closure_names, request$outputs), `[[`, character(1), "name")))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Adoption closure order differs from the operation output order.",
      "staging")
  operation_outputs <- stats::setNames(operation$outputs,
    vapply(operation$outputs, `[[`, character(1), "name"))
  closure_outputs <- lapply(closure_names, function(name) {
    out <- outputs[[name]]; declared <- operation_outputs[[name]]
    list(name = name, allocated_id = as.character(out$allocated_id)[1],
      kind = as.character(declared$kind)[1],
      output_grant_identity = .wb_operation_pack_v3_unscoped_identity(
        out$descriptor$grant_identity),
      terminal_policy = as.character(operation$replay_equivalence[[name]])[1],
      promotion_group = as.character(declared$promotion_group)[1],
      expected_cell_order_identity_if_cell_indexed =
        out$descriptor$expected_cell_order_identity %||% NULL)
  })
  closure <- list(outputs = closure_outputs,
    contained_model_sibling_write_grant_identity =
      .wb_operation_pack_v3_unscoped_identity(writer$write_grant_identity),
    model_source_linkage_identity = .wb_operation_pack_v3_unscoped_identity(
      writer$model_source_linkage$linkage_identity))
  closure$adopted_closure_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.supported_external_state_adoption_closure.v1",
    "adopted closure excluding adopted_closure_identity", closure)
  grant <- list(schema =
      "scworkbench.operation_pack.supported_external_state_adoption_grant.v1",
    name = as.character(declaration$name)[1],
    declaration_identity = .wb_operation_pack_v3_unscoped_identity(
      declaration$declaration_identity),
    source_snapshot = source$snapshot, source_byte_evidence = evidence,
    candidate_snapshot = snapshot,
    contained_model_sibling_write_grant_identity =
      closure$contained_model_sibling_write_grant_identity,
    model_source_linkage_identity = closure$model_source_linkage_identity,
    adopted_closure = closure,
    access = "verified_private_copy_read_only_v1",
    call_discipline = "adoption_state_exactly_once",
    execution_semantics =
      "supported_external_state_adoption_without_refit_v1")
  grant$grant_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.supported_external_state_adoption_grant.v1",
    "supported external state adoption grant excluding grant_identity", grant)
  list(grants = list(grant), candidate = candidate_value)
}

.wb_operation_pack_v3_g3_adapter <- function(base, request, stage_root) {
  grants <- request$supported_external_state_adoption_grants %||% list()
  if (!length(grants)) return(base)
  grant <- grants[[1L]]; state <- base$state
  state$external_state_adoption_calls <- 0L
  name <- as.character(grant$name)[1]
  base$readers[[name]] <- function(...) {
    if (isTRUE(state$used) || length(list(...)) ||
        state$external_state_adoption_calls != 0L)
      .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
        "External-state adoption reader is no-argument and exactly once.",
        "execution")
    root <- file.path(stage_root, grant$candidate_snapshot$relative_root)
    observed <- .wb_operation_pack_v3_model_tree_manifest(root,
      grant$candidate_snapshot$selected_state_type$engine,
      grant$candidate_snapshot$selected_state_type$model_type,
      grant$candidate_snapshot$primary_path)
    if (!identical(observed, grant$candidate_snapshot$tree_manifest))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "Authenticated candidate bytes changed before adoption.", "execution")
    state$external_state_adoption_calls <- 1L
    safe <- function(path) {
      path <- as.character(path)[1]
      if (!path %in% vapply(grant$candidate_snapshot$tree_manifest$entries,
          `[[`, character(1), "path"))
        .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
          "Adoption reader requested an unauthenticated entry.", "execution")
      file.path(root, path)
    }
    list(primary_path = grant$candidate_snapshot$primary_path,
      entries = .wb_operation_pack_v2_deep_copy(
        grant$candidate_snapshot$tree_manifest$entries),
      read_bytes = function(path) {
        target <- safe(path)
        readBin(target, "raw", n = file.info(target)$size)
      })
  }
  base
}

.wb_operation_pack_v3_g3_observations <- function(request, receipt,
    state, attestations) {
  grants <- request$supported_external_state_adoption_grants %||% list()
  if (!length(grants)) return(list())
  if (!identical(as.integer(state$external_state_adoption_calls %||% 0L),
      1L) || !is.list(attestations) ||
      !isTRUE(attestations$pack_source_association_attestation) ||
      !isTRUE(attestations$pack_no_refit_attestation))
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "G3 requires one read plus distinct source-association and no-refit pack attestations.",
      "receipt")
  grant <- grants[[1L]]
  observed <- stats::setNames(receipt$outputs,
    vapply(receipt$outputs, `[[`, character(1), "name"))
  model_name <- grant$adopted_closure$outputs[[1L]]$name
  model <- observed[[model_name]]
  tree <- model$descriptor$contained_model_sibling_tree
  candidate <- grant$candidate_snapshot
  if (is.null(tree) || !identical(tree$tree_manifest_identity,
      candidate$tree_manifest_identity) ||
      !identical(tree$payload_manifest_identity,
        candidate$payload_manifest_identity))
    .wb_operation_pack_v3_error("PYBENCH_OUTPUT_INVALID",
      "Adopted model tree is not byte-identical to the admitted candidate.",
      "audit")
  ordered <- lapply(grant$adopted_closure$outputs, function(x)
    .wb_operation_pack_v3_unscoped_identity(observed[[x$name]]$descriptor$
      observed_descriptor_identity))
  value <- list(schema =
      "scworkbench.operation_pack.observed_supported_external_state_adoption.v1",
    name = grant$name,
    grant_identity = .wb_operation_pack_v3_unscoped_identity(
      grant$grant_identity),
    source_snapshot_identity = .wb_operation_pack_v3_unscoped_identity(
      grant$source_snapshot$source_snapshot_identity),
    source_byte_evidence = grant$source_byte_evidence,
    candidate_snapshot_identity = .wb_operation_pack_v3_unscoped_identity(
      candidate$candidate_snapshot_identity),
    candidate_tree_manifest_identity = candidate$tree_manifest_identity,
    candidate_payload_manifest_identity = candidate$payload_manifest_identity,
    ordered_cell_count = candidate$ordered_cell_count,
    ordered_cell_identity = candidate$ordered_cell_identity,
    contained_model_sibling_tree_observation_identity =
      .wb_operation_pack_v3_unscoped_identity(tree$observation_identity),
    adopted_model_tree_manifest_identity = tree$tree_manifest_identity,
    adopted_model_payload_manifest_identity = tree$payload_manifest_identity,
    model_source_linkage_identity = grant$model_source_linkage_identity,
    adopted_closure_identity = .wb_operation_pack_v3_unscoped_identity(
      grant$adopted_closure$adopted_closure_identity),
    ordered_observed_output_descriptor_identities = ordered,
    read_count = 1L, event_count = 1L,
    execution_mode = "supported_external_state_adoption",
    upstream_execution = "external",
    pack_source_association_attestation = TRUE,
    pack_no_refit_attestation = TRUE, integrity_status = "unchanged",
    publication_status = "validated_not_published")
  value$observation_identity <- .wb_operation_pack_v2_identity_scoped(
    value$schema,
    "observed supported external state adoption excluding observation_identity",
    value)
  list(value)
}

.wb_operation_pack_v3_g3_sources_assert_current <- function(bundle,
    request) {
  grants <- request$supported_external_state_adoption_grants %||% list()
  for (grant in grants) {
    snapshot <- grant$source_snapshot
    current <- .wb_operation_pack_v3_g3_source_snapshot(bundle, list(
      source_id = snapshot$source_id,
      snapshot_id = snapshot$source_snapshot_id,
      run_id = snapshot$source_run_id))$snapshot
    if (!identical(current, snapshot))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "External source snapshot changed after adoption admission.", "audit")
    root <- file.path(attr(request, "operation_pack_stage_root"),
      grant$candidate_snapshot$relative_root)
    candidate <- grant$candidate_snapshot
    observed <- .wb_operation_pack_v3_model_tree_manifest(root,
      candidate$selected_state_type$engine,
      candidate$selected_state_type$model_type, candidate$primary_path,
      code = "PYBENCH_INPUT_IDENTITY_MISMATCH", phase = "audit")
    if (!identical(observed, candidate$tree_manifest) ||
        !identical(.wb_operation_pack_v3_model_payload_identity(observed),
          candidate$payload_manifest_identity))
      .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "External-state candidate changed after adoption admission.", "audit")
  }
  invisible(TRUE)
}
