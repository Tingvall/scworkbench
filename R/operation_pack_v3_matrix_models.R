# Generic ABI-v3 authority for a model fitted from an authenticated matrix.
# This is deliberately separate from the accepted space-trained G2 grant.

.wb_operation_pack_v3_matrix_model_linkage <- function(bundle, policy,
    source, source_record, axis_grant, latent_count, transition_state,
    paired_fitted_space_id) {
  cells <- attr(axis_grant, "operation_pack_v3_cells")
  features <- attr(axis_grant, "operation_pack_v3_features")
  source_bundle <- if (nzchar(as.character(source$matrix_id %||% "")[1]))
    .wb_operation_pack_v3_matrix_identity_bundle(bundle, source$matrix_id) else
      bundle
  snapshot <- .wb_operation_pack_v3_phase5_primitive_identity(
    source_bundle, source)
  value <- list(schema =
      "scworkbench.operation_pack.matrix_model_source_linkage.v1",
    engine = as.character(policy$engine)[1],
    model_type = as.character(policy$model_type)[1],
    source_matrix_id = as.character(source$matrix_id %||% "")[1],
    source_matrix_content_identity = source_record$content_identity,
    source_matrix_descriptor_identity =
      .wb_operation_pack_v3_unscoped_identity(
        source_record$descriptor_identity),
    feature_order_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.feature_order.v1", unname(as.list(features))),
    fitted_cell_order_identity = .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", unname(as.list(cells))),
    paired_fitted_space_id = paired_fitted_space_id,
    latent_dimension_count = as.integer(latent_count),
    source_matrix_snapshot_id = snapshot$sha256,
    transition_source_state_identity = transition_state)
  value$linkage_identity <- .wb_operation_pack_v2_identity_scoped(
    value$schema, "linkage excluding linkage_identity", value)
  value
}

.wb_operation_pack_v3_assert_matrix_model_linkage <- function(value,
    code = "PYBENCH_INPUT_IDENTITY_MISMATCH", phase = "resolution") {
  required <- c("schema", "engine", "model_type", "source_matrix_id",
    "source_matrix_content_identity", "source_matrix_descriptor_identity",
    "feature_order_identity", "fitted_cell_order_identity",
    "paired_fitted_space_id",
    "latent_dimension_count", "source_matrix_snapshot_id",
    "transition_source_state_identity", "linkage_identity")
  if (!is.list(value) || !setequal(names(value), required) ||
      !identical(as.character(value$schema)[1],
        "scworkbench.operation_pack.matrix_model_source_linkage.v1") ||
      !nzchar(as.character(value$source_matrix_id)[1]) ||
      !nzchar(as.character(value$paired_fitted_space_id)[1]) ||
      as.integer(value$latent_dimension_count)[1] < 1L)
    .wb_operation_pack_v3_error(code,
      "Matrix-trained model has incomplete source linkage.", phase)
  .wb_operation_pack_v3_assert_self_identity(value, "linkage_identity",
    code, phase)
  invisible(TRUE)
}

# A matrix-trained model's fitted space is an output, so its content cannot
# appear in the pre-execution source linkage. Recover the one authenticated
# terminal receipt through the promoted artifact/run binding instead. This is
# deliberately read-only and fails closed on missing or ambiguous evidence.
.wb_operation_pack_v3_matrix_model_fitted_space_recheck <- function(bundle,
    artifact_id, linkage, fitted_values) {
  source <- bundle$staging_source_bundle %||% NULL
  if (inherits(source, "scworkbench_bundle") &&
      nrow(DBI::dbGetQuery(source$con,
        "SELECT 1 FROM artifact_model_ref WHERE artifact_id=? LIMIT 1;",
        params = list(artifact_id))) == 1L) bundle <- source
  bindings <- unique(DBI::dbGetQuery(bundle$con, paste0(
    "SELECT run_id, output_name FROM prov_run_outputs ",
    "WHERE artifact_id = ?;"), params = list(artifact_id)))
  root <- .wb_operation_pack_v2_store(bundle)
  paths <- if (dir.exists(root)) list.dirs(root, recursive = FALSE,
    full.names = TRUE) else character()
  matches <- list()
  for (path in paths) {
    if (startsWith(basename(path), ".")) next
    result <- .wb_operation_pack_v2_record_validate(path,
      load_payloads = TRUE)
    if (!isTRUE(result$ok) || !identical(result$state$state, "reopened"))
      next
    bound <- bindings$output_name[bindings$run_id ==
      as.character(result$request$transition$run_id %||% "")[1]]
    if (length(bound) != 1L) next
    outputs <- result$receipt$outputs %||% list()
    model <- Filter(function(x) identical(x$name, bound) &&
      !is.null(x$descriptor$contained_matrix_model_sibling_tree), outputs)
    if (length(model) == 1L) matches[[length(matches) + 1L]] <- list(
      path = path, receipt = result$receipt, model = model[[1L]])
  }
  if (length(matches) != 1L) .wb_operation_pack_v3_error(
    "PYBENCH_INPUT_IDENTITY_MISMATCH",
    "Matrix-trained model lacks one durable promoted receipt.",
    "resolution")
  match <- matches[[1L]]
  observed <- match$model$descriptor$contained_matrix_model_sibling_tree
  space_id <- as.character(linkage$paired_fitted_space_id)[1]
  space <- Filter(function(x) identical(x$allocated_id, space_id) &&
    identical(x$descriptor$kind, "space"),
    match$receipt$outputs %||% list())
  if (length(space) != 1L ||
      !identical(observed$paired_fitted_space_id, space_id) ||
      !identical(observed$paired_space_content_identity,
        space[[1L]]$descriptor$content_identity) ||
      !identical(observed$model_source_linkage_identity,
        .wb_operation_pack_v3_unscoped_identity(linkage$linkage_identity)))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Matrix-trained model receipt does not bind its fitted space.",
      "resolution")
  staged <- wb_operation_pack_transition_load(bundle,
    basename(match$path), space[[1L]]$name)
  staged$values <- fitted_values
  actual <- .wb_operation_pack_v2_identity_plain(
    "scworkbench.space.content.v1", unclass(staged))
  if (!identical(actual, observed$paired_space_content_identity))
    .wb_operation_pack_v3_error("PYBENCH_INPUT_IDENTITY_MISMATCH",
      "Matrix-trained fitted-space content changed after promotion.",
      "resolution")
  invisible(TRUE)
}

.wb_operation_pack_v3_matrix_model_grant <- function(bundle, output,
    operation, inputs, input_records, params, typed_slice_grants,
    output_records, transition_state) {
  policy <- output$matrix_trained_contained_model_closure_policy
  if (is.null(policy)) return(NULL)
  source_name <- as.character(policy$source_matrix_input)[1]
  source <- inputs[[source_name]]
  source_record <- input_records[[source_name]]
  candidates <- Filter(function(x) identical(as.character(x$input_name)[1],
    source_name), typed_slice_grants)
  if (length(candidates) != 1L) .wb_operation_pack_v3_error(
    "PYBENCH_CAPABILITY_MISMATCH",
    "Matrix-trained model requires exactly one typed matrix reader.",
    "resolution")
  axis_grant <- candidates[[1L]]
  cells <- attr(axis_grant, "operation_pack_v3_cells")
  features <- attr(axis_grant, "operation_pack_v3_features")
  if (!length(cells) || !length(features) ||
      !identical(features, as.character(source$feature_id)))
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Matrix-trained model requires the complete authenticated feature axis.",
      "resolution")
  latent_count <- as.integer(params[[as.character(
    policy$latent_dimensions_parameter)[1]]])[1]
  if (is.na(latent_count) || latent_count < 1L || latent_count > 4096L)
    .wb_operation_pack_v3_error("PYBENCH_CAPABILITY_MISMATCH",
      "Matrix-trained latent dimension is outside its bound.", "resolution")
  paired <- output_records[[as.character(policy$paired_space_output)[1]]]
  linkage <- .wb_operation_pack_v3_matrix_model_linkage(bundle, policy,
    source, source_record, axis_grant, latent_count, transition_state,
    as.character(paired$allocated_id)[1])
  sibling_names <- as.character(unlist(policy$required_sibling_terminals,
    use.names = FALSE))
  definitions <- stats::setNames(operation$outputs,
    vapply(operation$outputs, `[[`, character(1), "name"))
  siblings <- lapply(sibling_names, function(name) {
    record <- output_records[[name]]
    kind <- as.character(definitions[[name]]$kind)[1]
    list(name = name, allocated_id = as.character(record$allocated_id)[1],
      kind = kind, grant_identity = .wb_operation_pack_v3_unscoped_identity(
        record$descriptor$grant_identity),
      replay_policy = as.character(operation$replay_equivalence[[name]])[1],
      expected_cell_order_identity_if_cell_indexed = if (identical(kind,
        "space")) linkage$fitted_cell_order_identity else NULL)
  })
  model_name <- as.character(output$name)[1]
  model_record <- output_records[[model_name]]
  closure <- .wb_operation_pack_v2_identity_plain(
    "scworkbench.operation_pack.matrix_model_sibling_closure.v1", list(
      model_output = model_name,
      model_grant_identity = .wb_operation_pack_v3_unscoped_identity(
        model_record$descriptor$grant_identity),
      model_source_linkage_identity = .wb_operation_pack_v3_unscoped_identity(
        linkage$linkage_identity),
      promotion_group = as.character(output$promotion_group)[1],
      siblings = lapply(siblings, function(x) x[c("name", "grant_identity",
        "replay_policy")])))
  grant <- list(schema =
      "scworkbench.operation_pack.contained_matrix_model_sibling_write_grant.v1",
    output = model_name, engine = linkage$engine, model_type = linkage$model_type,
    primary_path = as.character(policy$primary_path)[1],
    relative_root = paste0("outputs/", model_name, "/model_tree"),
    source_matrix = list(input_name = source_name,
      input_descriptor_identity = linkage$source_matrix_descriptor_identity,
      content_identity = source_record$content_identity,
      cell_order_identity = linkage$fitted_cell_order_identity,
      feature_order_identity = linkage$feature_order_identity,
      dimensions = unname(as.list(as.integer(source$dimensions)))),
    model_source_linkage = linkage,
    paired_space_output = list(name = as.character(
      policy$paired_space_output)[1],
      allocated_id = as.character(paired$allocated_id)[1],
      expected_dimensions = list(as.integer(length(cells)), latent_count),
      expected_cell_order_identity = linkage$fitted_cell_order_identity),
    required_sibling_terminals = siblings,
    model_sibling_closure_identity = closure,
    limits = list(maximum_file_count = as.integer(policy$maximum_file_count),
      maximum_total_bytes = as.integer(policy$maximum_total_bytes)))
  grant$write_grant_identity <- .wb_operation_pack_v2_identity_scoped(
    grant$schema, "grant excluding write_grant_identity", grant)
  grant
}
