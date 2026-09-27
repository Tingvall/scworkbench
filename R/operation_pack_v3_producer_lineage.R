# ABI-v3 authenticated producer transition lineage for paired typed outputs.

.wb_operation_pack_v3_lineage_fail <- function(message, phase = "resolution")
  .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH", message,
    phase)

.wb_operation_pack_v3_lineage_identity <- function(row) list(
  scheme = .wb_operation_pack_v3_scalar_db(row$content_identity_scheme),
  sha256 = .wb_operation_pack_v3_scalar_db(row$content_sha256))

.wb_operation_pack_v3_producer_lineage <- function(bundle, declaration,
    inputs, source_refs, input_records, source_state_identity) {
  names_in <- c("query_space_input", "summary_input", "model_input",
    "fitted_space_input")
  input_names <- vapply(names_in, function(field)
    as.character(declaration[[field]])[1], character(1))
  names(input_names) <- names_in
  query <- inputs[[input_names[["query_space_input"]]]]
  summary <- inputs[[input_names[["summary_input"]]]]
  model <- inputs[[input_names[["model_input"]]]]
  fitted <- inputs[[input_names[["fitted_space_input"]]]]
  summary_ref <- .wb_operation_pack_v3_artifact_ref(source_refs[[
    input_names[["summary_input"]]]])
  model_ref <- .wb_operation_pack_v3_artifact_ref(source_refs[[
    input_names[["model_input"]]]])
  if (is.null(summary_ref) || is.null(model_ref) ||
      !identical(as.character(query$kind)[1], "space") ||
      !identical(as.character(summary$kind)[1], "obs_table") ||
      !identical(as.character(model$kind)[1], "model_ref") ||
      !identical(as.character(fitted$kind)[1], "space"))
    .wb_operation_pack_v3_lineage_fail(
      "Producer lineage requires retained summary and model artifacts plus typed spaces.")
  query_id <- as.character(query$space_id)[1]
  fitted_id <- as.character(fitted$space_id)[1]
  model_fitted_id <- as.character(model$model_space_id %||%
    model$space_id %||% "")[1]
  if (!nzchar(query_id) || !nzchar(fitted_id) ||
      !identical(fitted_id, model_fitted_id))
    .wb_operation_pack_v3_lineage_fail(
      "Producer model does not bind the declared fitted reference space.")
  summary_name <- input_names[["summary_input"]]
  summary_ancestry <- .wb_operation_pack_v3_artifact_ancestry(bundle,
    list(name = as.character(declaration$name)[1], input = summary_name),
    input_records[[summary_name]], summary_ref)
  model_name <- input_names[["model_input"]]
  model_ancestry <- .wb_operation_pack_v3_artifact_ancestry(bundle,
    list(name = paste0(as.character(declaration$name)[1], "_model"),
      input = model_name), input_records[[model_name]], model_ref)
  snapshot_id <- summary_ancestry$source_snapshot_id
  run_id <- summary_ancestry$source_run_id
  con <- bundle$con
  run <- DBI::dbGetQuery(con,
    "SELECT * FROM prov_runs WHERE snapshot_id=? AND run_id=?;",
    params = list(snapshot_id, run_id))
  output <- DBI::dbGetQuery(con, paste0(
    "SELECT o.* FROM prov_run_outputs AS o JOIN prov_run_entity_bindings AS b ",
    "ON b.snapshot_id=o.snapshot_id AND b.run_id=o.run_id ",
    "AND b.binding_name=o.output_name WHERE o.snapshot_id=? AND o.run_id=? ",
    "AND b.direction='output' AND b.entity_kind='space' AND b.entity_id=?;"),
    params = list(snapshot_id, run_id, query_id))
  if (nrow(run) != 1L || nrow(output) != 1L ||
      !identical(as.character(output$primitive_kind[[1L]]), "space") ||
      !identical(as.character(output$verification_status[[1L]]),
        "content_verified"))
    .wb_operation_pack_v3_lineage_fail(
      "Query space is not one content-verified output of the summary producer.")
  run_hash <- .wb_prov_run_hash(as.character(run$op_name[[1L]]),
    as.character(run$params_json[[1L]]),
    as.character(run$inputs_json[[1L]]),
    as.character(run$symbolic_inputs_json[[1L]]),
    as.character(run$execution_inputs_json[[1L]]))
  if (!identical(as.character(run$run_hash[[1L]]), run_hash) ||
      !identical(summary_ancestry$source_run_identity,
        list(scheme = as.character(run$run_hash_scheme[[1L]]),
          sha256 = run_hash)))
    .wb_operation_pack_v3_lineage_fail(
      "Producer run provenance hash differs from its retained inputs.")
  query_observed <- tryCatch(.wb_prov_payload_identity(bundle,
    wb_prim_space(query_id)), error = identity)
  query_identity <- .wb_operation_pack_v3_lineage_identity(output)
  .wb_operation_pack_v3_full_space_assert_current(bundle, query_id,
    expected_provenance_identity = query_identity)
  .wb_operation_pack_v3_full_space_assert_current(bundle, fitted_id)
  if (inherits(query_observed, "error") || !identical(
      query_identity, list(scheme = as.character(query_observed$
        content_identity_scheme)[1], sha256 = as.character(query_observed$
          content_sha256)[1])))
    .wb_operation_pack_v3_lineage_fail(
      "Query space bytes differ from the retained producer output.")
  symbolic <- tryCatch(jsonlite::fromJSON(as.character(run$
    symbolic_inputs_json[[1L]]), simplifyVector = FALSE), error = identity)
  symbolic_model <- if (inherits(symbolic, "error")) NULL else
    .wb_operation_pack_v3_artifact_ref(symbolic[[model_name]])
  consumed <- DBI::dbGetQuery(con, paste0(
    "SELECT * FROM prov_run_entity_bindings WHERE snapshot_id=? AND run_id=? ",
    "AND direction='input' AND binding_name IN (?, ?) ",
    "AND entity_kind='artifact' ",
    "AND entity_id=?;"),
    params = list(snapshot_id, run_id, model_name,
      paste0("inputs$provenance_refs$", model_name), model_ref$artifact_id))
  if (is.null(symbolic_model) || !identical(
      symbolic_model$artifact_id, model_ref$artifact_id) ||
      nrow(consumed) < 1L)
    .wb_operation_pack_v3_lineage_fail(
      "Producer transition did not consume the declared retained model.")
  value <- list(schema =
      "scworkbench.operation_pack.producer_lineage_grant.v1",
    name = as.character(declaration$name)[1],
    reader = "read_producer_transition_lineage",
    source_mode = "retained_producer_v1",
    source_snapshot_id = snapshot_id, source_run_id = run_id,
    source_op_name = as.character(run$op_name[[1L]]),
    source_run_identity = summary_ancestry$source_run_identity,
    query_space = list(input_descriptor_identity =
        .wb_operation_pack_v3_unscoped_identity(input_records[[
          input_names[["query_space_input"]]]]$descriptor_identity),
      space_id = query_id, content_identity = query_identity,
      source_output_name = as.character(output$output_name[[1L]])),
    projection_summary = list(input_descriptor_identity =
        .wb_operation_pack_v3_unscoped_identity(input_records[[summary_name]]$
          descriptor_identity), artifact_id = summary_ref$artifact_id,
      content_identity = summary_ancestry$artifact_content_identity,
      source_output_name = summary_ancestry$source_output_name),
    model = list(input_descriptor_identity =
        .wb_operation_pack_v3_unscoped_identity(input_records[[model_name]]$
          descriptor_identity), artifact_id = model_ref$artifact_id,
      content_identity = model_ancestry$artifact_content_identity,
      fitted_space_id = model_fitted_id),
    fitted_space = list(input_descriptor_identity =
        .wb_operation_pack_v3_unscoped_identity(input_records[[
          input_names[["fitted_space_input"]]]]$descriptor_identity),
      space_id = fitted_id, content_identity = input_records[[
        input_names[["fitted_space_input"]]]]$content_identity),
    source_state_identity = source_state_identity)
  value$grant_identity <- .wb_operation_pack_v2_identity_scoped(
    value$schema, "grant excluding grant_identity", value)
  value
}

.wb_operation_pack_v3_producer_lineage_records <- function(bundle,
    operation, inputs, source_refs, input_records, source_state_identity) {
  lapply(operation$producer_lineage_reads %||% list(), function(declaration)
    .wb_operation_pack_v3_producer_lineage(bundle, declaration, inputs,
      source_refs, input_records, source_state_identity))
}

.wb_operation_pack_v3_producer_lineage_assert_current <- function(bundle,
    operation, inputs, source_refs, request) {
  grants <- request$producer_lineage_grants %||% list()
  declarations <- operation$producer_lineage_reads %||% list()
  if (length(grants) != length(declarations))
    .wb_operation_pack_v3_lineage_fail(
      "Producer lineage grants are not a bijection with declarations.",
      "audit")
  records <- stats::setNames(lapply(request$inputs, `[[`, "descriptor"),
    vapply(request$inputs, `[[`, character(1), "name"))
  current_state <- .wb_operation_pack_v2_identity_plain(
    "scworkbench.scientific_state.v1",
    .wb_manifest_registry_snapshot(bundle$con))
  for (i in seq_along(grants)) {
    grant <- grants[[i]]
    if (!identical(current_state, grant$source_state_identity))
      .wb_operation_pack_v3_lineage_fail(
        "Producer lineage source state changed before publication.",
        "audit")
    observed <- .wb_operation_pack_v3_producer_lineage(bundle,
      declarations[[i]], inputs, source_refs, records, current_state)
    if (!identical(observed$grant_identity, grant$grant_identity))
      .wb_operation_pack_v3_lineage_fail(
        "Producer lineage changed before publication.", "audit")
  }
  invisible(TRUE)
}

.wb_operation_pack_v3_producer_lineage_observations <- function(request,
    reader_calls) {
  lapply(request$producer_lineage_grants %||% list(), function(grant) {
    name <- as.character(grant$name)[1]
    uses <- sum(vapply(reader_calls, function(x)
      identical(as.character(x$category %||% "")[1],
        "producer_lineage_read") && identical(as.character(x$name %||%
          "")[1], name), logical(1)))
    if (uses != 1L) .wb_operation_pack_v3_error(
      "PYBENCH_CAPABILITY_MISMATCH",
      paste0("Producer-lineage reader '", name,
        "' must be consumed exactly once."), "execution")
    value <- list(schema =
        "scworkbench.operation_pack.producer_lineage_read_observation.v1",
      name = name, grant_identity =
        .wb_operation_pack_v3_unscoped_identity(grant$grant_identity),
      use_count = 1L)
    value$observation_identity <- .wb_operation_pack_v2_identity_scoped(
      value$schema, "observation excluding observation_identity", value)
    value
  })
}

.wb_operation_pack_v3_producer_lineage_receipt_audit <- function(receipt,
    request) {
  grants <- request$producer_lineage_grants %||% list()
  reads <- receipt$producer_lineage_reads %||% list()
  if (length(grants) != length(reads))
    .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
      "Producer-lineage reads are not a bijection with grants.", "receipt")
  for (i in seq_along(reads)) {
    observed <- reads[[i]]
    .wb_operation_pack_v3_assert_self_identity(observed,
      "observation_identity", "PYBENCH_RECEIPT_MISMATCH", "receipt")
    if (!identical(as.character(observed$name)[1],
        as.character(grants[[i]]$name)[1]) ||
        !identical(observed$grant_identity,
          .wb_operation_pack_v3_unscoped_identity(
            grants[[i]]$grant_identity)) ||
        !identical(as.integer(observed$use_count), 1L))
      .wb_operation_pack_v3_error("PYBENCH_RECEIPT_MISMATCH",
        "Producer-lineage observation differs from its exact grant.",
        "receipt")
  }
  invisible(TRUE)
}

.wb_operation_pack_v3_producer_lineage_retained_assert_current <- function(
    bundle, request) {
  for (grant in request$producer_lineage_grants %||% list()) {
    run <- DBI::dbGetQuery(bundle$con,
      "SELECT * FROM prov_runs WHERE snapshot_id=? AND run_id=?;",
      params = list(grant$source_snapshot_id, grant$source_run_id))
    if (nrow(run) != 1L || !identical(as.character(run$op_name[[1L]]),
        grant$source_op_name) || !identical(
          list(scheme = as.character(run$run_hash_scheme[[1L]]),
            sha256 = .wb_prov_run_hash(as.character(run$op_name[[1L]]),
              as.character(run$params_json[[1L]]),
              as.character(run$inputs_json[[1L]]),
              as.character(run$symbolic_inputs_json[[1L]]),
              as.character(run$execution_inputs_json[[1L]]))),
          grant$source_run_identity))
      .wb_operation_pack_v3_lineage_fail(
        "Retained producer run identity changed.", "recipient")
    for (source in c("projection_summary", "model")) {
      item <- grant[[source]]
      ancestry <- .wb_operation_pack_v3_artifact_ancestry(bundle,
        list(name = grant$name, input = source),
        list(descriptor_identity = item$input_descriptor_identity,
          content_identity = item$content_identity), item$artifact_id)
      if (!identical(ancestry$artifact_content_identity,
          item$content_identity) ||
          (identical(source, "projection_summary") &&
            (!identical(ancestry$source_snapshot_id,
                grant$source_snapshot_id) ||
              !identical(ancestry$source_run_id, grant$source_run_id) ||
              !identical(ancestry$source_output_name,
                item$source_output_name))))
        .wb_operation_pack_v3_lineage_fail(
          "Retained producer lineage source was superseded or changed.",
          "recipient")
    }
    query <- grant$query_space
    .wb_operation_pack_v3_full_space_assert_current(bundle, query$space_id,
      expected_provenance_identity = query$content_identity,
      phase = "recipient")
    .wb_operation_pack_v3_full_space_assert_current(bundle,
      grant$fitted_space$space_id, phase = "recipient")
    observed <- tryCatch(.wb_prov_payload_identity(bundle,
      wb_prim_space(query$space_id)), error = identity)
    if (inherits(observed, "error") || !identical(query$content_identity,
        list(scheme = as.character(observed$content_identity_scheme)[1],
          sha256 = as.character(observed$content_sha256)[1])))
      .wb_operation_pack_v3_lineage_fail(
        "Retained producer query-space bytes changed.", "recipient")
    output <- DBI::dbGetQuery(bundle$con, paste0(
      "SELECT o.content_identity_scheme,o.content_sha256,o.verification_status ",
      "FROM prov_run_outputs AS o JOIN prov_run_entity_bindings AS b ",
      "ON b.snapshot_id=o.snapshot_id AND b.run_id=o.run_id ",
      "AND b.binding_name=o.output_name WHERE o.snapshot_id=? AND o.run_id=? ",
      "AND o.output_name=? AND o.primitive_kind='space' ",
      "AND b.direction='output' AND b.entity_kind='space' AND b.entity_id=?;"),
      params = list(grant$source_snapshot_id, grant$source_run_id,
        query$source_output_name, query$space_id))
    if (nrow(output) != 1L || !identical(as.character(
        output$verification_status[[1L]]), "content_verified") ||
        !identical(.wb_operation_pack_v3_lineage_identity(output),
          query$content_identity))
      .wb_operation_pack_v3_lineage_fail(
        "Retained producer query-space output identity changed.",
        "recipient")
  }
  invisible(TRUE)
}
