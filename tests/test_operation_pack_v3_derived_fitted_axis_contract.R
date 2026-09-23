.wb_dfa_install <- function() {
  library <- tempfile("scwb-dfa-lib-"); dir.create(library)
  log <- tempfile("scwb-dfa-install-", fileext = ".log")
  source <- file.path(normalizePath(".", mustWork = TRUE), "tests",
    "fixtures", "operation-pack-v3-phase5")
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(library)), shQuote(source)), stdout = log,
    stderr = log)
  if (!identical(status, 0L)) stop(paste(readLines(log, warn = FALSE),
    collapse = "\n"), call. = FALSE)
  old <- .libPaths(); .libPaths(c(library, old))
  manifest <- system.file("scworkbench", "operation-pack.json",
    package = "scwbV3Phase5", lib.loc = library)
  wb_operation_pack_activate(manifest, lib.loc = library)
  list(library = library, old = old)
}

.wb_dfa_cleanup <- function(fixture) {
  try(wb_operation_pack_unload("scwbv3phase5"), silent = TRUE)
  if ("scwbV3Phase5" %in% loadedNamespaces())
    try(unloadNamespace("scwbV3Phase5"), silent = TRUE)
  .libPaths(fixture$old)
  unlink(fixture$library, recursive = TRUE, force = TRUE)
}

.wb_dfa_bundle <- function() {
  root <- tempfile("scwb-dfa-bundle-")
  bundle <- wb_init_bundle(root)
  cells <- c("c2", "c1", "c4", "c3")
  wb_define_cells(bundle, cells)
  wb_add_space(bundle, "pca", matrix(seq_len(12L), nrow = 4L,
    dimnames = list(cells, c("PC1", "PC2", "PC3"))))
  wb_cell_set_replace(bundle, "set:session", c("c2", "c4", "c3"),
    source = "derived-fitted-axis-contract")
  list(root = root, bundle = bundle, cells = cells)
}

.wb_dfa_bundle_case <- function(parent_count, session_cells) {
  root <- tempfile("scwb-dfa-case-")
  bundle <- wb_init_bundle(root)
  cells <- paste0("cell_", seq_len(parent_count))
  wb_define_cells(bundle, cells)
  wb_add_space(bundle, "pca", matrix(seq_len(parent_count * 3L),
    nrow = parent_count, dimnames = list(cells, c("PC1", "PC2", "PC3"))))
  if (!identical(session_cells, cells))
    wb_cell_set_replace(bundle, "set:session", session_cells,
      source = "derived-fitted-axis-contract")
  list(root = root, bundle = bundle, cells = cells,
    cell_set = if (identical(session_cells, cells)) "all" else "set:session")
}

.wb_dfa_run <- function(bundle, ...) {
  values <- utils::modifyList(list(source = "pca", dims = c(1L, 3L),
    fitted_cells = c("c2", "c3"), cell_set = "set:session",
    min_cells = 1L), list(...))
  wb_session_run_op(wb_session_new(), bundle,
    "scwbv3phase5::fit_derived_axis_model", inputs = values)
}

.wb_dfa_expect <- function(expr, codes) {
  error <- tryCatch(force(expr), error = identity)
  if (!inherits(error, "wb_operation_pack_v3_error") &&
      !inherits(error, "wb_operation_pack_v2_error"))
    stop("Expected an operation-pack error; observed: ",
      conditionMessage(error), call. = FALSE)
  if (!as.character(error$code) %in% codes)
    stop("Expected ", paste(codes, collapse = "/"), "; observed ",
      as.character(error$code), ": ", conditionMessage(error),
      call. = FALSE)
  invisible(error)
}

.wb_dfa_durable_state <- function(bundle) {
  tables <- DBI::dbGetQuery(bundle$con,
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name;")$name
  counts <- stats::setNames(vapply(tables, function(table)
    as.integer(DBI::dbGetQuery(bundle$con, paste0("SELECT COUNT(*) AS n FROM ",
      DBI::dbQuoteIdentifier(bundle$con, table), ";"))$n[[1L]]), integer(1)),
    tables)
  list(fingerprint = .wb_manifest_registry_snapshot(bundle$con)$fingerprint,
    counts = counts, artifacts = wb_art_list(bundle),
    operation_store = sort(list.files(.wb_operation_pack_v2_store(bundle),
      recursive = TRUE, all.files = TRUE, no.. = TRUE)))
}

.wb_dfa_rehash_request <- function(value) {
  for (i in seq_along(value$derived_fitted_axis_grants)) {
    grant <- value$derived_fitted_axis_grants[[i]]
    grant$parent_snapshot$parent_snapshot_identity <- NULL
    grant$parent_snapshot$parent_snapshot_identity <-
      .wb_operation_pack_v2_identity_scoped(
        "scworkbench.operation_pack.fitted_axis_parent_snapshot.v1",
        "parent snapshot excluding parent_snapshot_identity",
        grant$parent_snapshot)
    grant$session_projection$parent_snapshot_identity <-
      .wb_operation_pack_v3_unscoped_identity(
        grant$parent_snapshot$parent_snapshot_identity)
    grant$session_projection$session_identity <- NULL
    grant$session_projection$session_identity <-
      .wb_operation_pack_v2_identity_scoped(
        "scworkbench.operation_pack.derived_fitted_session.v1",
        "session projection excluding session_identity",
        grant$session_projection)
    grant$grant_identity <- NULL
    grant$grant_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.derived_fitted_axis_grant.v1",
      "provisional grant excluding grant_identity", grant)
    value$derived_fitted_axis_grants[[i]] <- grant
  }
  value$execution_capability$derived_fitted_axis_grant_identities <-
    lapply(value$derived_fitted_axis_grants, function(grant)
      .wb_operation_pack_v3_unscoped_identity(grant$grant_identity))
  value$execution_capability$capability_identity <- NULL
  value$execution_capability$capability_identity <-
    .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.capability.v3",
      "capability excluding capability_identity", value$execution_capability)
  value$request_identity <- NULL
  value$request_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.transition_request.v3",
    "request excluding request_identity", value)
  value
}

test_operation_pack_v3_derived_fitted_axis_protocol_contract <- function() {
  manifest <- jsonlite::read_json(file.path("tests", "fixtures",
    "operation-pack-v3-phase5", "inst", "scworkbench",
    "operation-pack.json"), simplifyVector = FALSE)
  validated <- wb_operation_pack_manifest_validate(manifest)
  definition <- validated$manifest$operations[[match(
    "fit_derived_axis_model", vapply(validated$manifest$operations, `[[`,
      character(1), "name"))]]
  policy <- definition$outputs[[1L]]$derived_fitted_axis_policy
  stopifnot(identical(policy$mode, "source_relative_subset_v1"),
    identical(vapply(policy$required_siblings, `[[`, character(1),
      "coverage_policy"), c("exact_fitted_axis_v1",
        "per_key_source_relative_subset_v1")))
  bad <- unserialize(serialize(manifest, NULL))
  index <- match("fit_derived_axis_model", vapply(bad$operations, `[[`,
    character(1), "name"))
  bad$operations[[index]]$outputs[[1L]]$derived_fitted_axis_policy$
    maximum_selected_cells <- 1000001L
  before <- wb_operation_catalog_identity()
  error <- tryCatch(wb_operation_pack_manifest_validate(bad), error = identity)
  stopifnot(inherits(error, "wb_operation_pack_v3_error"),
    identical(before, wb_operation_catalog_identity()))
  manifest_schema <- jsonlite::read_json(file.path("inst", "protocol",
    "operation-pack-v3.schema.json"), simplifyVector = FALSE)
  illegal_pair <- unserialize(serialize(manifest, NULL))
  illegal_pair$operations[[index]]$outputs[[1L]]$
    derived_fitted_axis_policy$required_siblings[[1L]]$coverage_policy <-
      "per_key_source_relative_subset_v1"
  stopifnot(!isTRUE(.wb_json_schema_validate_2020(illegal_pair,
    manifest_schema)$ok))
  limits <- list(maximum_selected_cells = 3L,
    maximum_combined_id_bytes = 12, maximum_id_bytes = 6L,
    maximum_family_keys = 2L)
  stopifnot(identical(.wb_operation_pack_v3_dfa_utf8(
    c("a", "bb", "ccc"), limits, "fixture")$ids,
    c("a", "bb", "ccc")))
  .wb_dfa_expect(.wb_operation_pack_v3_dfa_utf8(
    c("a", "b", "c", "d"), limits, "fixture"),
    "PYBENCH_CAPABILITY_MISMATCH")
  .wb_dfa_expect(.wb_operation_pack_v3_dfa_utf8(
    "seven77", limits, "fixture"), "PYBENCH_CAPABILITY_MISMATCH")
  .wb_dfa_expect(.wb_operation_pack_v3_dfa_combined_bytes(
    c(2, 2), 3, "fixture"),
    "PYBENCH_CAPABILITY_MISMATCH")
  identities <- jsonlite::read_json(file.path("inst", "protocol",
    "fixtures", "operation-pack-v3", "identities.json"),
    simplifyVector = FALSE)
  fixture_case <- function(name) identities$cases[[match(name,
    vapply(identities$cases, `[[`, character(1), "name"))]]$value
  request_schema <- jsonlite::read_json(file.path("inst", "protocol",
    "operation-pack-transition-request-v3.schema.json"),
    simplifyVector = FALSE)
  receipt_schema <- jsonlite::read_json(file.path("inst", "protocol",
    "operation-pack-transition-receipt-v3.schema.json"),
    simplifyVector = FALSE)
  stopifnot(isTRUE(.wb_json_schema_validate_2020(
      fixture_case("dfa_provisional_grant"),
      request_schema$`$defs`$derived_fitted_axis_grant,
      request_schema)$ok),
    isTRUE(.wb_json_schema_validate_2020(
      fixture_case("dfa_selected_axis_sidecar"),
      request_schema$`$defs`$selected_axis_evidence_sidecar,
      request_schema)$ok),
    isTRUE(.wb_json_schema_validate_2020(
      fixture_case("dfa_complete_observation"),
      receipt_schema$`$defs`$derived_fitted_axis_observation,
      receipt_schema)$ok))
  fixture_request <- fixture_case("dfa_success_request")
  fixture_receipt <- fixture_case("dfa_success_receipt")
  fixture_observation <- fixture_receipt$
    derived_fitted_axis_observations[[1L]]
  stopifnot(identical(.wb_operation_pack_v3_unscoped_identity(
      fixture_request$derived_fitted_axis_grants[[1L]]$grant_identity),
      fixture_observation$provisional_grant_identity),
    identical(vapply(fixture_receipt$outputs, `[[`, character(1), "name"),
      c(fixture_observation$model_output, vapply(
        fixture_observation$sibling_coverage_observations, `[[`,
        character(1), "output_name"))),
    identical(.wb_operation_pack_v3_unscoped_identity(
      fixture_receipt$outputs[[1L]]$descriptor$
        observed_descriptor_identity),
      fixture_observation$model_observed_descriptor_identity))
  schemas <- list(
    `operation-pack-transition-request-v3.schema.json` = request_schema,
    `operation-pack-transition-receipt-v3.schema.json` = receipt_schema)
  for (negative in identities$negative_cases) {
    if (startsWith(negative$name, "sparse_")) next
    root <- schemas[[negative$schema_file]]
    schema <- if (identical(negative$definition, "root")) root else
      root$`$defs`[[negative$definition]]
    result <- .wb_json_schema_validate_2020(negative$value, schema, root)
    stopifnot(identical(isTRUE(result$ok),
      identical(negative$expected, "semantic_reject")))
  }
  TRUE
}

test_operation_pack_v3_derived_fitted_axis_protocol_generation_is_stable <-
    function() {
  paths <- c("inst/protocol/operation-pack-v3.schema.json",
    "inst/protocol/operation-pack-transition-request-v3.schema.json",
    "inst/protocol/operation-pack-transition-receipt-v3.schema.json",
    "inst/protocol/fixtures/operation-pack-v3/identities.json")
  before <- vapply(paths, digest::digest, character(1), algo = "sha256",
    file = TRUE)
  status <- system2(file.path(R.home("bin"), "Rscript"),
    "scripts/generate_phase5_derived_fitted_axis_protocol.R",
    stdout = TRUE, stderr = TRUE)
  stopifnot(is.null(attr(status, "status")),
    identical(before, vapply(paths, digest::digest, character(1),
      algo = "sha256", file = TRUE)))
  TRUE
}

test_operation_pack_v3_derived_fitted_axis_positive_scale_contract <-
    function() {
  fixture <- .wb_dfa_install()
  on.exit(.wb_dfa_cleanup(fixture), add = TRUE)
  cases <- list(
    list(parent = 4L, session = paste0("cell_", 1:4),
      fitted = paste0("cell_", 1:4)),
    list(parent = 4L, session = paste0("cell_", 1:3),
      fitted = paste0("cell_", 1:3)),
    list(parent = 120L, session = paste0("cell_", 1:120),
      fitted = paste0("cell_", 1:80))
  )
  for (case in cases) {
    state <- .wb_dfa_bundle_case(case$parent, case$session)
    tryCatch({
      fit <- .wb_dfa_run(state$bundle, cell_set = state$cell_set,
        fitted_cells = case$fitted)
      transition <- fit$run$operation_pack_transition$transition_id
      model <- wb_operation_pack_transition_load(fit$session$staging_bundle,
        transition, "model")
      stopifnot(identical(rownames(.wb_operation_pack_v3_dfa_reopen(
          fit$session$staging_bundle, model,
          model$model_source_linkage, model$model_tree_root)), case$fitted))
      promoted <- wb_session_promote_current(state$bundle, fit$session,
        outputs = c("embedding", "model", "weights"),
        created_by = "dfa-scale-test")
      stopifnot(nrow(promoted$promoted) == 3L,
        isTRUE(wb_finalize_recipient_bundle(state$bundle)$ready))
      model_id <- promoted$promoted$artifact_id[
        promoted$promoted$output == "model"][[1L]]
      wb_close_bundle(state$bundle); state$bundle <- NULL
      relocated <- tempfile("scwb-dfa-scale-relocated-")
      fs::dir_copy(state$root, relocated)
      read_only <- wb_open_bundle(relocated, read_only = TRUE)
      durable <- wb_art_load(read_only, model_id, expected_kind = "model_ref")
      stopifnot(identical(rownames(.wb_operation_pack_v3_dfa_reopen(
          read_only, durable, durable$model_source_linkage,
          durable$model_tree_root)), case$fitted),
        isTRUE(wb_bundle_validation_report(relocated,
          level = "recipient")$ok))
      wb_close_bundle(read_only)
      unlink(relocated, recursive = TRUE, force = TRUE)
    }, finally = {
      try(wb_close_bundle(state$bundle), silent = TRUE)
      unlink(state$root, recursive = TRUE, force = TRUE)
    })
  }
  TRUE
}

test_operation_pack_v3_derived_fitted_axis_lifecycle_contract <- function() {
  fixture <- .wb_dfa_install(); state <- .wb_dfa_bundle()
  on.exit({
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    options(scworkbench.promotion_workspace_publish_hook = NULL)
    options(scworkbench.promotion_transaction_test_hook = NULL)
    try(wb_close_bundle(state$bundle), silent = TRUE)
    .wb_dfa_cleanup(fixture)
    unlink(state$root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  fit <- .wb_dfa_run(state$bundle)
  transition <- fit$run$operation_pack_transition$transition_id
  record <- file.path(.wb_operation_pack_v2_store(fit$session$staging_bundle),
    transition)
  request <- jsonlite::read_json(file.path(record, "request.json"),
    simplifyVector = FALSE)
  receipt <- jsonlite::read_json(file.path(record, "receipt.json"),
    simplifyVector = FALSE)
  grant <- request$derived_fitted_axis_grants[[1L]]
  observation <- receipt$derived_fitted_axis_observations[[1L]]
  stopifnot(grant$parent_snapshot$full_cell_count == 4L,
    grant$session_projection$session_cell_count == 3L,
    observation$seal$fitted_cell_count == 2L,
    identical(unlist(observation$seal$fitted_cell_ids), c("c2", "c3")),
    identical(receipt$receipt_identity$scheme,
      "scworkbench.operation_pack.transition_receipt.v3"),
    is.null(observation$selected_axis_evidence$content_sha256),
    is.null(observation$model_source_linkage$model_tree_manifest_identity),
    length(observation$sibling_coverage_observations) == 2L,
    identical(unlist(observation$sibling_coverage_observations[[2L]]$
      observed_keys), c("lineage_a", "lineage_b")))
  registration <- .wb_operation_pack_registry$packs[["scwbv3phase5"]]$
    registration
  operation <- registration$manifest$operations[[match(
    "scwbv3phase5::fit_derived_axis_model", vapply(
      registration$manifest$operations, `[[`, character(1),
      "qualified_name"))]]
  audit_cells <- as.character(unlist(grant$session_projection$
    session_cell_ids, use.names = FALSE))
  audit_source <- .wb_operation_pack_v2_bind_inputs(
    fit$session$staging_bundle, list(source = wb_prim_space("pca")),
    audit_cells)$source
  audit_params <- list(dims = c(1L, 3L), fitted_cells = c("c2", "c3"),
    declaration_mode = "normal", bad_embedding_order = FALSE,
    foreign_family_cell = FALSE)
  forged_request <- .wb_operation_pack_v2_deep_copy(request)
  forged_request$derived_fitted_axis_grants[[1L]]$model_base_grant$
    grant_identity$sha256 <- paste(rep("7", 64L), collapse = "")
  forged_request$derived_fitted_axis_grants[[1L]]$grant_identity <- NULL
  forged_request$derived_fitted_axis_grants[[1L]]$grant_identity <-
    .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.derived_fitted_axis_grant.v1",
      "provisional grant excluding grant_identity",
      forged_request$derived_fitted_axis_grants[[1L]])
  forged_request$execution_capability$
    derived_fitted_axis_grant_identities[[1L]] <-
      .wb_operation_pack_v3_unscoped_identity(
        forged_request$derived_fitted_axis_grants[[1L]]$grant_identity)
  forged_request$execution_capability$capability_identity <- NULL
  forged_request$execution_capability$capability_identity <-
    .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.capability.v3",
      "capability excluding capability_identity",
      forged_request$execution_capability)
  forged_request$request_identity <- NULL
  forged_request$request_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.transition_request.v3",
    "request excluding request_identity", forged_request)
  .wb_dfa_expect(.wb_operation_pack_v3_dfa_request_audit(
    fit$session$staging_bundle, forged_request, operation,
    list(source = audit_source), audit_params),
    "PYBENCH_CAPABILITY_MISMATCH")
  changed_dimensions <- .wb_operation_pack_v2_deep_copy(request)
  changed_dimensions$derived_fitted_axis_grants[[1L]]$parent_snapshot$
    selected_dimension_ids <- list("PC1", "PC2")
  changed_dimensions$derived_fitted_axis_grants[[1L]]$parent_snapshot$
    selected_dimension_order_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.dimension_order.v1", list("PC1", "PC2"))
  changed_dimensions$derived_fitted_axis_grants[[1L]]$parent_snapshot$
    parent_snapshot_identity <- NULL
  changed_dimensions$derived_fitted_axis_grants[[1L]]$parent_snapshot$
    parent_snapshot_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.fitted_axis_parent_snapshot.v1",
      "parent snapshot excluding parent_snapshot_identity",
      changed_dimensions$derived_fitted_axis_grants[[1L]]$parent_snapshot)
  changed_dimensions$derived_fitted_axis_grants[[1L]]$session_projection$
    selected_dimension_order_identity <- changed_dimensions$
      derived_fitted_axis_grants[[1L]]$parent_snapshot$
        selected_dimension_order_identity
  changed_dimensions$derived_fitted_axis_grants[[1L]]$session_projection$
    parent_snapshot_identity <- .wb_operation_pack_v3_unscoped_identity(
      changed_dimensions$derived_fitted_axis_grants[[1L]]$parent_snapshot$
        parent_snapshot_identity)
  changed_dimensions$derived_fitted_axis_grants[[1L]]$session_projection$
    session_identity <- NULL
  changed_dimensions$derived_fitted_axis_grants[[1L]]$session_projection$
    session_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.derived_fitted_session.v1",
      "session projection excluding session_identity",
      changed_dimensions$derived_fitted_axis_grants[[1L]]$session_projection)
  changed_dimensions$derived_fitted_axis_grants[[1L]]$grant_identity <- NULL
  changed_dimensions$derived_fitted_axis_grants[[1L]]$grant_identity <-
    .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.derived_fitted_axis_grant.v1",
      "provisional grant excluding grant_identity",
      changed_dimensions$derived_fitted_axis_grants[[1L]])
  changed_dimensions$execution_capability$
    derived_fitted_axis_grant_identities[[1L]] <-
      .wb_operation_pack_v3_unscoped_identity(changed_dimensions$
        derived_fitted_axis_grants[[1L]]$grant_identity)
  changed_dimensions$execution_capability$capability_identity <- NULL
  changed_dimensions$execution_capability$capability_identity <-
    .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.capability.v3",
      "capability excluding capability_identity",
      changed_dimensions$execution_capability)
  changed_dimensions$request_identity <- NULL
  changed_dimensions$request_identity <-
    .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.transition_request.v3",
      "request excluding request_identity", changed_dimensions)
  .wb_dfa_expect(.wb_operation_pack_v3_dfa_request_audit(
    fit$session$staging_bundle, changed_dimensions, operation,
    list(source = audit_source), audit_params),
    "PYBENCH_CAPABILITY_MISMATCH")
  changed_session <- .wb_operation_pack_v2_deep_copy(request)
  changed_session$derived_fitted_axis_grants[[1L]]$session_projection$
    session_cell_ids <- list("c2", "c3")
  changed_session$derived_fitted_axis_grants[[1L]]$session_projection$
    session_cell_count <- 2L
  changed_session$derived_fitted_axis_grants[[1L]]$session_projection$
    session_cell_order_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", list("c2", "c3"))
  changed_session <- .wb_dfa_rehash_request(changed_session)
  .wb_dfa_expect(.wb_operation_pack_v3_dfa_request_audit(
    fit$session$staging_bundle, changed_session, operation,
    list(source = audit_source), audit_params),
    "PYBENCH_CAPABILITY_MISMATCH")
  changed_limits <- .wb_operation_pack_v2_deep_copy(request)
  changed_limits$derived_fitted_axis_grants[[1L]]$limits$
    maximum_selected_cells <- 2L
  changed_limits <- .wb_dfa_rehash_request(changed_limits)
  .wb_dfa_expect(.wb_operation_pack_v3_dfa_request_audit(
    fit$session$staging_bundle, changed_limits, operation,
    list(source = audit_source), audit_params),
    "PYBENCH_CAPABILITY_MISMATCH")
  changed_source <- .wb_operation_pack_v2_deep_copy(request)
  changed_source$inputs[[1L]]$descriptor$content_identity$sha256 <-
    paste(rep("8", 64L), collapse = "")
  changed_source$inputs[[1L]]$descriptor$descriptor_identity <- NULL
  changed_source$inputs[[1L]]$descriptor$descriptor_identity <-
    .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.input_descriptor.v2",
      "descriptor excluding descriptor_identity",
      changed_source$inputs[[1L]]$descriptor)
  changed_source$derived_fitted_axis_grants[[1L]]$session_projection$
    source_input_descriptor_identity <- .wb_operation_pack_v3_unscoped_identity(
      changed_source$inputs[[1L]]$descriptor$descriptor_identity)
  changed_source$derived_fitted_axis_grants[[1L]]$session_projection$
    source_input_content_identity <- changed_source$inputs[[1L]]$descriptor$
      content_identity
  changed_source <- .wb_dfa_rehash_request(changed_source)
  .wb_dfa_expect(.wb_operation_pack_v3_dfa_request_audit(
    fit$session$staging_bundle, changed_source, operation,
    list(source = audit_source), audit_params),
    "PYBENCH_INPUT_IDENTITY_MISMATCH")
  attr(request, "operation_pack_stage_root") <- record
  forged_receipt <- .wb_operation_pack_v2_deep_copy(receipt)
  forged_receipt$derived_fitted_axis_observations[[1L]]$seal$
    fitted_cell_ids <- list("c2")
  forged_receipt$derived_fitted_axis_observations[[1L]]$seal$
    fitted_cell_count <- 1L
  forged_receipt$derived_fitted_axis_observations[[1L]]$seal$
    fitted_cell_order_identity <- .wb_operation_pack_v2_identity_plain(
      "scworkbench.cell_order.v1", list("c2"))
  forged_receipt$derived_fitted_axis_observations[[1L]]$seal$
    seal_identity <- NULL
  forged_receipt$derived_fitted_axis_observations[[1L]]$seal$
    seal_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.derived_fitted_axis_seal.v1",
      "seal excluding seal_identity",
      forged_receipt$derived_fitted_axis_observations[[1L]]$seal)
  forged_receipt$derived_fitted_axis_observations[[1L]]$
    observation_identity <- NULL
  forged_receipt$derived_fitted_axis_observations[[1L]]$
    observation_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.observed_derived_fitted_axis.v1",
      "observation excluding observation_identity",
      forged_receipt$derived_fitted_axis_observations[[1L]])
  forged_receipt$receipt_identity <- NULL
  forged_receipt$receipt_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.transition_receipt.v3",
    "receipt excluding receipt_identity", forged_receipt)
  .wb_dfa_expect(.wb_operation_pack_v3_dfa_receipt_audit(forged_receipt,
    request, operation), "PYBENCH_RECEIPT_MISMATCH")
  no_grant_request <- .wb_operation_pack_v2_deep_copy(request)
  no_grant_request$derived_fitted_axis_grants <- list()
  no_grant_request$execution_capability$
    derived_fitted_axis_grant_identities <- list()
  no_grant_request$execution_capability$capability_identity <- NULL
  no_grant_request$execution_capability$capability_identity <-
    .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.capability.v3",
      "capability excluding capability_identity",
      no_grant_request$execution_capability)
  no_grant_request$request_identity <- NULL
  no_grant_request$request_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.transition_request.v3",
    "request excluding request_identity", no_grant_request)
  .wb_dfa_expect(.wb_operation_pack_v3_dfa_receipt_audit(receipt,
    no_grant_request, operation), "PYBENCH_RECEIPT_MISMATCH")
  receipt_path <- file.path(record, "receipt.json")
  request_path <- file.path(record, "request.json")
  receipt_bytes <- readBin(receipt_path, "raw", n = file.info(
    receipt_path)$size)
  jsonlite::write_json(forged_receipt, receipt_path, auto_unbox = TRUE,
    pretty = TRUE, null = "null", digits = NA)
  .wb_dfa_expect(wb_operation_pack_transition_load(
    fit$session$staging_bundle, transition, "model"),
    "PYBENCH_REOPEN_VALIDATION_FAILED")
  connection <- file(receipt_path, "wb"); writeBin(receipt_bytes, connection)
  close(connection)
  request_bytes <- readBin(request_path, "raw", n = file.info(
    request_path)$size)
  jsonlite::write_json(no_grant_request, request_path, auto_unbox = TRUE,
    pretty = TRUE, null = "null", digits = NA)
  .wb_dfa_expect(wb_operation_pack_transition_load(
    fit$session$staging_bundle, transition, "model"),
    "PYBENCH_REOPEN_VALIDATION_FAILED")
  connection <- file(request_path, "wb"); writeBin(request_bytes, connection)
  close(connection)
  missing_sibling <- .wb_operation_pack_v2_deep_copy(receipt)
  missing_sibling$derived_fitted_axis_observations[[1L]]$
    sibling_coverage_observations <- missing_sibling$
      derived_fitted_axis_observations[[1L]]$
        sibling_coverage_observations[1L]
  missing_sibling$derived_fitted_axis_observations[[1L]]$
    observation_identity <- NULL
  missing_sibling$derived_fitted_axis_observations[[1L]]$
    observation_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.observed_derived_fitted_axis.v1",
      "observation excluding observation_identity",
      missing_sibling$derived_fitted_axis_observations[[1L]])
  missing_sibling$receipt_identity <- NULL
  missing_sibling$receipt_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.transition_receipt.v3",
    "receipt excluding receipt_identity", missing_sibling)
  .wb_dfa_expect(.wb_operation_pack_v3_dfa_receipt_audit(missing_sibling,
    request, operation), "PYBENCH_RECEIPT_MISMATCH")
  changed_keys <- .wb_operation_pack_v2_deep_copy(receipt)
  coverage <- changed_keys$derived_fitted_axis_observations[[1L]]$
    sibling_coverage_observations[[2L]]
  coverage$observed_keys <- rev(coverage$observed_keys)
  coverage$per_key_coverage <- rev(coverage$per_key_coverage)
  coverage$observation_identity <- NULL
  coverage$observation_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.observed_sealed_sibling_coverage.v1",
    "coverage observation excluding observation_identity", coverage)
  changed_keys$derived_fitted_axis_observations[[1L]]$
    sibling_coverage_observations[[2L]] <- coverage
  changed_keys$derived_fitted_axis_observations[[1L]]$
    observation_identity <- NULL
  changed_keys$derived_fitted_axis_observations[[1L]]$
    observation_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.observed_derived_fitted_axis.v1",
      "observation excluding observation_identity",
      changed_keys$derived_fitted_axis_observations[[1L]])
  changed_keys$receipt_identity <- NULL
  changed_keys$receipt_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.transition_receipt.v3",
    "receipt excluding receipt_identity", changed_keys)
  .wb_dfa_expect(.wb_operation_pack_v3_dfa_receipt_audit(changed_keys,
    request, operation), "PYBENCH_RECEIPT_MISMATCH")
  changed_linkage <- .wb_operation_pack_v2_deep_copy(receipt)
  changed_linkage$derived_fitted_axis_observations[[1L]]$
    model_source_linkage$source_space_id <- "substituted_space"
  changed_linkage$derived_fitted_axis_observations[[1L]]$
    model_source_linkage$linkage_identity <- NULL
  changed_linkage$derived_fitted_axis_observations[[1L]]$
    model_source_linkage$linkage_identity <-
      .wb_operation_pack_v2_identity_scoped(
        "scworkbench.operation_pack.model_source_linkage.v3",
        "linkage excluding linkage_identity", changed_linkage$
          derived_fitted_axis_observations[[1L]]$model_source_linkage)
  changed_linkage$derived_fitted_axis_observations[[1L]]$
    observation_identity <- NULL
  changed_linkage$derived_fitted_axis_observations[[1L]]$
    observation_identity <- .wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.observed_derived_fitted_axis.v1",
      "observation excluding observation_identity", changed_linkage$
        derived_fitted_axis_observations[[1L]])
  changed_linkage$receipt_identity <- NULL
  changed_linkage$receipt_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.transition_receipt.v3",
    "receipt excluding receipt_identity", changed_linkage)
  .wb_dfa_expect(.wb_operation_pack_v3_dfa_receipt_audit(changed_linkage,
    request, operation), "PYBENCH_RECEIPT_MISMATCH")
  stopifnot(isTRUE(.wb_operation_pack_v3_dfa_receipt_audit(receipt,
    request, operation)))
  model <- wb_operation_pack_transition_load(fit$session$staging_bundle,
    transition, "model")
  stopifnot(identical(model$model_source_linkage$schema,
      "scworkbench.operation_pack.model_source_linkage.v3"))
  forged <- .wb_operation_pack_v2_deep_copy(model$model_source_linkage)
  forged$fitted_cell_order_identity$sha256 <- paste(rep("0", 64L),
    collapse = "")
  forged$linkage_identity <- NULL
  forged$linkage_identity <- .wb_operation_pack_v2_identity_scoped(
    "scworkbench.operation_pack.model_source_linkage.v3",
    "linkage excluding linkage_identity", forged)
  .wb_dfa_expect(.wb_operation_pack_v3_dfa_reopen(
    fit$session$staging_bundle, model, forged, model$model_tree_root),
    "PYBENCH_INPUT_IDENTITY_MISMATCH")
  unknown <- .wb_operation_pack_v2_deep_copy(model$model_source_linkage)
  unknown$linkage_identity$scheme <- "unknown.identity.scheme"
  .wb_dfa_expect(.wb_operation_pack_v3_dfa_reopen(
    fit$session$staging_bundle, model, unknown, model$model_tree_root),
    "PYBENCH_INPUT_IDENTITY_MISMATCH")
  sidecar <- file.path(model$model_tree_root,
    model$model_source_linkage$selected_axis_evidence$relative_path)
  sidecar_bytes <- readBin(sidecar, "raw", n = file.info(sidecar)$size)
  unlink(sidecar)
  .wb_dfa_expect(.wb_operation_pack_v3_dfa_reopen(
    fit$session$staging_bundle, model, model$model_source_linkage,
    model$model_tree_root), "PYBENCH_INPUT_IDENTITY_MISMATCH")
  missing_cell <- .wb_operation_pack_parse_canonical_json(
    rawToChar(sidecar_bytes))
  missing_cell$fitted_cell_ids <- missing_cell$fitted_cell_ids[1L]
  missing_bytes <- charToRaw(.wb_operation_pack_canonical_json(missing_cell))
  connection <- file(sidecar, "wb"); writeBin(missing_bytes, connection)
  close(connection)
  .wb_dfa_expect(.wb_operation_pack_v3_dfa_reopen(
    fit$session$staging_bundle, model, model$model_source_linkage,
    model$model_tree_root), "PYBENCH_INPUT_IDENTITY_MISMATCH")
  connection <- file(sidecar, "wb"); writeBin(sidecar_bytes, connection)
  close(connection)
  sidecar_value <- .wb_operation_pack_parse_canonical_json(
    rawToChar(sidecar_bytes))
  sidecar_value$session_cell_ids <- rev(sidecar_value$session_cell_ids)
  reordered <- charToRaw(.wb_operation_pack_canonical_json(sidecar_value))
  connection <- file(sidecar, "wb"); writeBin(reordered, connection)
  close(connection)
  .wb_dfa_expect(.wb_operation_pack_v3_dfa_reopen(
    fit$session$staging_bundle, model, model$model_source_linkage,
    model$model_tree_root), "PYBENCH_INPUT_IDENTITY_MISMATCH")
  connection <- file(sidecar, "wb"); writeBin(sidecar_bytes, connection)
  close(connection)
  registry <- .wb_space_payload_registry_row(state$bundle, "pca")
  parent_path <- .wb_space_payload_path(state$bundle, registry)
  parent_bytes <- readBin(parent_path, "raw", n = file.info(parent_path)$size)
  changed <- parent_bytes
  changed[[length(changed)]] <- as.raw(bitwXor(as.integer(
    changed[[length(changed)]]), 1L))
  connection <- file(parent_path, "wb"); writeBin(changed, connection)
  close(connection)
  .wb_dfa_expect(.wb_operation_pack_v3_dfa_parent_assert_current(
    state$bundle, grant$parent_snapshot),
    "PYBENCH_INPUT_IDENTITY_MISMATCH")
  connection <- file(parent_path, "wb"); writeBin(parent_bytes, connection)
  close(connection)
  stopifnot(identical(.wb_operation_pack_v3_dfa_parent_assert_current(
    state$bundle, grant$parent_snapshot), state$cells))
  promoted <- wb_session_promote_current(state$bundle, fit$session,
    outputs = c("embedding", "model", "weights"), created_by = "dfa-test")
  stopifnot(nrow(promoted$promoted) == 3L,
    all(promoted$promoted$status == "ok"))
  model_id <- promoted$promoted$artifact_id[
    promoted$promoted$output == "model"][[1L]]
  durable <- wb_art_load(state$bundle, model_id, expected_kind = "model_ref")
  stopifnot(identical(durable$model_source_linkage$linkage_identity,
    observation$model_source_linkage$linkage_identity))
  consume <- .wb_operation_pack_registry$operations[[
    "scwbv3phase5::consume_self_linked_model"]]$definition$v3_definition
  descriptor <- .wb_operation_pack_v2_input_descriptor("model", durable,
    consume$inputs[[1L]])$descriptor
  stage <- tempfile("scwb-dfa-reopen-"); dir.create(stage)
  prepared <- .wb_operation_pack_v3_prepare_self_linked_model_reads(
    state$bundle, consume, list(model = durable), list(model = descriptor),
    stage)
  stopifnot(length(prepared$grants) == 1L,
    identical(rownames(prepared$values[[1L]]$fitted_space), c("c2", "c3")),
    identical(colnames(prepared$values[[1L]]$fitted_space), c("PC1", "PC3")))
  unlink(stage, recursive = TRUE, force = TRUE)
  stopifnot(isTRUE(wb_finalize_recipient_bundle(state$bundle)$ready))
  wb_close_bundle(state$bundle)
  relocated <- tempfile("scwb-dfa-relocated-")
  fs::dir_copy(state$root, relocated)
  read_only <- wb_open_bundle(relocated, read_only = TRUE)
  report <- wb_bundle_validation_report(relocated, level = "recipient")
  relocated_model <- wb_art_load(read_only, model_id,
    expected_kind = "model_ref")
  stopifnot(isTRUE(report$ok),
    identical(relocated_model$model_source_linkage$linkage_identity,
      observation$model_source_linkage$linkage_identity))
  wb_close_bundle(read_only)
  unlink(relocated, recursive = TRUE, force = TRUE)
  state$bundle <- NULL
  TRUE
}

test_operation_pack_v3_derived_fitted_axis_adversarial_atomicity_contract <-
    function() {
  fixture <- .wb_dfa_install(); state <- .wb_dfa_bundle()
  on.exit({
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    options(scworkbench.promotion_workspace_publish_hook = NULL)
    options(scworkbench.promotion_transaction_test_hook = NULL)
    try(wb_close_bundle(state$bundle), silent = TRUE)
    .wb_dfa_cleanup(fixture)
    unlink(state$root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  before <- .wb_dfa_durable_state(state$bundle)
  for (arguments in list(
      list(fitted_cells = c("c3", "c2")),
      list(fitted_cells = c("c2", "foreign_cell")),
      list(declaration_mode = "omit"),
      list(declaration_mode = "repeat"),
      list(declaration_mode = "after_output"),
      list(bad_embedding_order = TRUE),
      list(foreign_family_cell = TRUE),
      list(fitted_axis_attack = "duplicate"),
      list(fitted_axis_attack = "empty"),
      list(fitted_axis_attack = "oversized_id"),
      list(weights_attack = "duplicate_cell"),
      list(weights_attack = "reordered_cells"),
      list(weights_attack = "too_many_keys"),
      list(output_attack = "missing_weights"),
      list(output_attack = "extra_output"))) {
    .wb_dfa_expect(do.call(.wb_dfa_run, c(list(bundle = state$bundle),
      arguments)), c("PYBENCH_INPUT_IDENTITY_MISMATCH",
        "PYBENCH_CAPABILITY_MISMATCH", "PYBENCH_OUTPUT_INVALID",
        "PYBENCH_PROCESS_FAILED", "PYBENCH_RECEIPT_MISMATCH"))
    stopifnot(identical(before, .wb_dfa_durable_state(state$bundle)))
  }
  options(scworkbench.operation_pack_v2_test_hook = function(event,
      stage_root = NULL, model_output = NULL, ...) {
    if (!identical(event, "derived_fitted_axis_model_closed")) return()
    sidecar <- file.path(stage_root, "outputs", model_output, "model_tree",
      ".scworkbench", "selected-axis-v1.json")
    connection <- file(sidecar, "ab")
    writeBin(charToRaw("tamper"), connection); close(connection)
  })
  .wb_dfa_expect(.wb_dfa_run(state$bundle),
    "PYBENCH_RECEIPT_MISMATCH")
  options(scworkbench.operation_pack_v2_test_hook = NULL)
  stopifnot(identical(before, .wb_dfa_durable_state(state$bundle)))
  options(scworkbench.operation_pack_v2_test_hook = function(event,
      stage_root = NULL, model_output = NULL, ...) {
    if (!identical(event, "derived_fitted_axis_model_closed")) return()
    model_file <- file.path(stage_root, "outputs", model_output,
      "model_tree", "model.bin")
    connection <- file(model_file, "ab")
    writeBin(charToRaw("tree-substitution"), connection); close(connection)
  })
  .wb_dfa_expect(.wb_dfa_run(state$bundle),
    "PYBENCH_RECEIPT_MISMATCH")
  options(scworkbench.operation_pack_v2_test_hook = NULL)
  stopifnot(identical(before, .wb_dfa_durable_state(state$bundle)))
  parent_registry <- .wb_space_payload_registry_row(state$bundle, "pca")
  parent_path <- .wb_space_payload_path(state$bundle, parent_registry)
  parent_bytes <- readBin(parent_path, "raw", n = file.info(parent_path)$size)
  changed_parent <- parent_bytes
  changed_parent[[length(changed_parent)]] <- as.raw(bitwXor(as.integer(
    changed_parent[[length(changed_parent)]]), 1L))
  parent_changed <- FALSE
  options(scworkbench.operation_pack_v2_test_hook = function(event, ...) {
    if (!identical(event, "audited")) return()
    parent_changed <<- TRUE
    connection <- file(parent_path, "wb")
    writeBin(changed_parent, connection); close(connection)
  })
  .wb_dfa_expect(.wb_dfa_run(state$bundle), c(
    "PYBENCH_INPUT_IDENTITY_MISMATCH", "PYBENCH_OUTPUT_INVALID"))
  options(scworkbench.operation_pack_v2_test_hook = NULL)
  connection <- file(parent_path, "wb"); writeBin(parent_bytes, connection)
  close(connection)
  stopifnot(parent_changed,
    identical(before, .wb_dfa_durable_state(state$bundle)))
  for (fault in c("derived_fitted_axis_sealed",
      "derived_fitted_axis_first_sibling", "derived_fitted_axis_model_closed",
      "derived_fitted_axis_receipt_audited", "audited",
      "before_publication", "published", "before_reopened")) {
    options(scworkbench.operation_pack_v2_test_hook = local({
      target <- fault
      function(event, ...) if (identical(event, target)) stop(target)
    }))
    .wb_dfa_expect(.wb_dfa_run(state$bundle), c("PYBENCH_PROCESS_FAILED",
      "PYBENCH_OUTPUT_INVALID", "PYBENCH_PUBLICATION_FAILED",
      "PYBENCH_REOPEN_VALIDATION_FAILED"))
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    stopifnot(identical(before, .wb_dfa_durable_state(state$bundle)))
  }
  fit <- .wb_dfa_run(state$bundle)
  transition <- fit$run$operation_pack_transition$transition_id
  model <- wb_operation_pack_transition_load(fit$session$staging_bundle,
    transition, "model")
  sidecar <- file.path(model$model_tree_root,
    model$model_source_linkage$selected_axis_evidence$relative_path)
  original <- readBin(sidecar, "raw", n = file.info(sidecar)$size)
  connection <- file(sidecar, "ab"); writeBin(charToRaw("tamper"), connection)
  close(connection)
  .wb_dfa_expect(wb_operation_pack_transition_load(
    fit$session$staging_bundle, transition, "model"),
    "PYBENCH_REOPEN_VALIDATION_FAILED")
  connection <- file(sidecar, "wb"); writeBin(original, connection)
  close(connection)
  stopifnot(identical(wb_operation_pack_transition_load(
    fit$session$staging_bundle, transition, "model")$kind, "model_ref"))
  before_promotion <- .wb_dfa_durable_state(state$bundle)
  calls <- 0L
  options(scworkbench.promotion_workspace_publish_hook = function(...) {
    calls <<- calls + 1L
    if (calls == 1L) stop("injected derived-axis publication failure")
  })
  failed <- try(wb_session_promote_current(state$bundle, fit$session,
    outputs = c("embedding", "model", "weights"),
    created_by = "dfa-publication-fault"), silent = TRUE)
  options(scworkbench.promotion_workspace_publish_hook = NULL)
  stopifnot(inherits(failed, "try-error"), calls == 1L,
    identical(before_promotion, .wb_dfa_durable_state(state$bundle)))
  options(scworkbench.promotion_transaction_test_hook = function(event,
      ...) {
    if (identical(event, "after_payload_move_before_database_commit"))
      stop("injected derived-axis pre-commit failure")
  })
  failed_commit <- try(wb_session_promote_current(state$bundle, fit$session,
    outputs = c("embedding", "model", "weights"),
    created_by = "dfa-precommit-fault"), silent = TRUE)
  options(scworkbench.promotion_transaction_test_hook = NULL)
  stopifnot(inherits(failed_commit, "try-error"),
    identical(before_promotion, .wb_dfa_durable_state(state$bundle)))
  retry <- wb_session_promote_current(state$bundle, fit$session,
    outputs = c("embedding", "model", "weights"),
    created_by = "dfa-publication-retry")
  stopifnot(nrow(retry$promoted) == 3L,
    all(retry$promoted$status == "ok"))
  TRUE
}
