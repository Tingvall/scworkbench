.wb_g3_fixture_install <- function() {
  library <- tempfile("scwb-g3-lib-")
  dir.create(library, recursive = TRUE)
  log <- tempfile("scwb-g3-install-", fileext = ".log")
  source <- file.path(normalizePath(".", winslash = "/", mustWork = TRUE),
    "tests", "fixtures", "operation-pack-v3-phase5")
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

.wb_g3_fixture_cleanup <- function(fixture) {
  try(wb_operation_pack_unload("scwbv3phase5"), silent = TRUE)
  if ("scwbV3Phase5" %in% loadedNamespaces())
    try(unloadNamespace("scwbV3Phase5"), silent = TRUE)
  .libPaths(fixture$old)
  unlink(fixture$library, recursive = TRUE, force = TRUE)
  invisible(TRUE)
}

.wb_g3_expect_code <- function(expr, code) {
  error <- tryCatch(force(expr), error = identity)
  stopifnot(inherits(error, "wb_operation_pack_v3_error") ||
      inherits(error, "wb_operation_pack_v2_error"),
    identical(as.character(error$code), code))
  invisible(error)
}

.wb_g3_bundle <- function() {
  root <- tempfile("scwb-g3-bundle-")
  bundle <- wb_init_bundle(root)
  cells <- c("cell-b", "cell-a", "cell-c")
  wb_define_cells(bundle, cells)
  coordinates <- matrix(seq_len(9L), nrow = 3L,
    dimnames = list(cells, c("PC1", "PC2", "PC3")))
  wb_add_space(bundle, "pca", coordinates)
  list(root = root, bundle = bundle, cells = cells)
}

.wb_g3_record_source <- function(bundle, source_id, path, checksum) {
  declaration <- list(scope = "external_file", source_id = source_id,
    accession = "fixture", role = "published_fit", format = "binary",
    path = path, uri = NULL, bundled = FALSE, checksum = checksum,
    sha256 = checksum, checksum_algorithm = "sha256",
    accession_derived = FALSE)
  .wb_record_declared_ingestion(bundle, paste0("g3_", source_id),
    source = "G3 fixture", source_identity = list(
      source_type = "published_fit", inputs = list(declaration)))
  .wb_entity_lifecycle_migrate(bundle)
  row <- DBI::dbGetQuery(bundle$con, paste0(
    "SELECT snapshot_id,run_id,source_id FROM prov_source_inputs ",
    "WHERE source_id=? ORDER BY snapshot_id,run_id;"), params = list(source_id))
  stopifnot(nrow(row) == 1L)
  list(source_id = source_id, snapshot_id = row$snapshot_id[[1L]],
    run_id = row$run_id[[1L]])
}

.wb_g3_candidate <- function(cells, suffix = "")
  wb_supported_external_state_candidate("fixture", "external_state", cells,
    entries = list(model.bin = charToRaw(paste0("external-model", suffix)),
      `nested/state.bin` = as.raw(c(1L, 2L, 3L, 4L))),
    primary_path = "model.bin")

.wb_g3_run <- function(bundle, cells, source_ref, candidate =
    .wb_g3_candidate(cells)) {
  wb_session_run_op(wb_session_new(), bundle,
    "scwbv3phase5::adopt_external_state", inputs = list(source = "pca",
      candidate = candidate, dims = c(1L, 2L, 3L),
      external_source_ref = source_ref, cell_set = "all", min_cells = 1L))
}

test_operation_pack_v3_g3_external_state_adoption_contract <- function() {
  fixture <- .wb_g3_fixture_install()
  state <- .wb_g3_bundle()
  external <- tempfile("scwb-g3-source-")
  writeBin(charToRaw("published external fit"), external)
  source_ref <- .wb_g3_record_source(state$bundle, "external-fit", external,
    wb_source_sha256(external))
  on.exit({
    options(scworkbench.operation_pack_v2_test_hook = NULL,
      scworkbench.operation_pack_v3_output_test_hook = NULL)
    try(wb_close_bundle(state$bundle), silent = TRUE)
    .wb_g3_fixture_cleanup(fixture)
    unlink(c(state$root, external), recursive = TRUE, force = TRUE)
  }, add = TRUE)

  before_tables <- vapply(c("artifacts", "artifact_tables",
    "prov_run_entity_bindings"), function(table) DBI::dbGetQuery(
      state$bundle$con, paste0("SELECT COUNT(*) AS n FROM ", table))$n[[1L]],
    numeric(1))
  one_shot <- .wb_g3_candidate(state$cells)
  fit <- .wb_g3_run(state$bundle, state$cells, source_ref, one_shot)
  transition <- fit$run$operation_pack_transition$transition_id
  record <- file.path(.wb_operation_pack_v2_store(
    fit$session$staging_bundle), transition)
  request <- jsonlite::read_json(file.path(record, "request.json"),
    simplifyVector = FALSE)
  receipt <- jsonlite::read_json(file.path(record, "receipt.json"),
    simplifyVector = FALSE)
  grant <- request$supported_external_state_adoption_grants[[1L]]
  observed <- receipt$supported_external_state_adoption_observations[[1L]]
  stopifnot(identical(grant$source_byte_evidence$status,
      "bytes_not_inspected"),
    is.null(grant$source_byte_evidence$observed_content_identity),
    identical(grant$candidate_snapshot$tree_manifest_identity,
      observed$adopted_model_tree_manifest_identity),
    identical(grant$candidate_snapshot$payload_manifest_identity,
      observed$adopted_model_payload_manifest_identity),
    identical(grant$candidate_snapshot$ordered_cell_identity,
      .wb_operation_pack_v2_identity_plain("scworkbench.cell_order.v1",
        unname(as.list(state$cells)))),
    isTRUE(observed$pack_source_association_attestation),
    isTRUE(observed$pack_no_refit_attestation),
    !grepl(normalizePath(external, winslash = "/", mustWork = TRUE),
      .wb_operation_pack_canonical_json(request), fixed = TRUE),
    !grepl("candidate_token", .wb_operation_pack_canonical_json(request),
      fixed = TRUE))
  candidate_files <- grant$candidate_snapshot$tree_manifest$entries
  model_output <- receipt$outputs[[match("model", vapply(receipt$outputs,
    `[[`, character(1), "name"))]]$descriptor$contained_model_sibling_tree
  stopifnot(identical(candidate_files, model_output$tree_manifest$entries))
  mutate_request <- function(f) {
    value <- .wb_operation_pack_v2_deep_copy(request); value <- f(value)
    error <- tryCatch(.wb_operation_pack_v3_schema_assert(value, "request",
      "PYBENCH_CAPABILITY_MISMATCH"), error = identity)
    stopifnot(inherits(error, "wb_operation_pack_v3_error"))
  }
  mutate_request(function(x) {
    x$supported_external_state_adoption_grants[[1L]]$candidate_snapshot$
      relative_root <- "/private/host/path"; x
  })
  mutate_request(function(x) {
    x$supported_external_state_adoption_grants[[1L]]$source_byte_evidence$
      observed_content_identity <- x$supported_external_state_adoption_grants[[1L]]$
        source_byte_evidence$declared_content_identity; x
  })
  mutate_request(function(x) {
    x$supported_external_state_adoption_grants[[1L]]$ambient_handle <- "bad"; x
  })
  fake_state <- new.env(parent = emptyenv())
  fake_state$external_state_adoption_calls <- 1L
  .wb_g3_expect_code(.wb_operation_pack_v3_g3_observations(request,
    receipt, fake_state, list(pack_source_association_attestation = FALSE,
      pack_no_refit_attestation = TRUE)), "PYBENCH_RECEIPT_MISMATCH")

  missing_ref <- .wb_g3_record_source(state$bundle, "missing-fit",
    file.path(tempdir(), "g3-source-does-not-exist"),
    paste(rep("a", 64L), collapse = ""))
  unavailable_fit <- .wb_g3_run(state$bundle, state$cells, missing_ref)
  unavailable_receipt <- unavailable_fit$run$params$
    supported_external_state_adoption
  stopifnot(identical(unavailable_receipt$source_byte_evidence$status,
      "bytes_unavailable"),
    identical(unavailable_receipt$source_byte_evidence$
      nonverification_reason, "external_bytes_unavailable"),
    is.null(unavailable_receipt$source_byte_evidence$
      observed_content_identity))
  unavailable_fit$session <- wb_session_discard(unavailable_fit$session)

  promoted <- wb_session_promote_current(state$bundle, fit$session,
    outputs = c("model", "summary"), created_by = "g3-contract")
  stopifnot(nrow(promoted$promoted) == 2L,
    all(promoted$promoted$status == "ok"))
  params <- fit$run$params$supported_external_state_adoption
  stopifnot(identical(params$execution_mode,
      "supported_external_state_adoption"),
    identical(params$upstream_execution, "external"))
  model_id <- promoted$promoted$artifact_id[
    promoted$promoted$output == "model"][[1L]]
  loaded <- wb_art_load(state$bundle, model_id, expected_kind = "model_ref")
  stopifnot(identical(loaded$model_tree_manifest$manifest_identity,
    grant$candidate_snapshot$tree_manifest$manifest_identity))

  # Exactly-once candidate handles cannot be replayed.
  .wb_g3_expect_code(.wb_g3_run(state$bundle, state$cells, source_ref,
    one_shot), "PYBENCH_INPUT_IDENTITY_MISMATCH")

  # Every transition failure leaves no durable outputs or transition residue.
  before_store <- sort(list.files(.wb_operation_pack_v2_store(state$bundle),
    recursive = TRUE, all.files = TRUE, no.. = TRUE))
  before_artifacts <- nrow(wb_art_list(state$bundle))
  options(scworkbench.operation_pack_v2_test_hook = function(event, ...)
    if (identical(event, "before_publication")) stop("g3 publication fault"))
  .wb_g3_expect_code(.wb_g3_run(state$bundle, state$cells, source_ref),
    "PYBENCH_PUBLICATION_FAILED")
  options(scworkbench.operation_pack_v2_test_hook = NULL)
  stopifnot(nrow(wb_art_list(state$bundle)) == before_artifacts,
    identical(before_store, sort(list.files(
      .wb_operation_pack_v2_store(state$bundle), recursive = TRUE,
      all.files = TRUE, no.. = TRUE))))
  after_tables <- vapply(names(before_tables), function(table)
    DBI::dbGetQuery(state$bundle$con,
      paste0("SELECT COUNT(*) AS n FROM ", table))$n[[1L]], numeric(1))
  stopifnot(all(after_tables >= before_tables))
  TRUE
}

test_operation_pack_v3_g3_adversarial_contract <- function() {
  fixture <- .wb_g3_fixture_install()
  state <- .wb_g3_bundle()
  external <- tempfile("scwb-g3-source-")
  writeBin(charToRaw("source bytes"), external)
  checksum <- wb_source_sha256(external)
  source_ref <- .wb_g3_record_source(state$bundle, "adversarial-fit",
    external, checksum)
  on.exit({
    options(scworkbench.operation_pack_v2_test_hook = NULL,
      scworkbench.operation_pack_v3_output_test_hook = NULL)
    try(wb_close_bundle(state$bundle), silent = TRUE)
    .wb_g3_fixture_cleanup(fixture)
    unlink(c(state$root, external), recursive = TRUE, force = TRUE)
  }, add = TRUE)

  # Candidate ordered-cell substitution is rejected before dispatch.
  .wb_g3_expect_code(.wb_g3_run(state$bundle, state$cells, source_ref,
    .wb_g3_candidate(rev(state$cells), "-reordered")),
    "PYBENCH_INPUT_IDENTITY_MISMATCH")

  # A source checksum mismatch is never downgraded to an uninspected state.
  DBI::dbExecute(state$bundle$con, paste0(
    "UPDATE prov_source_inputs SET source_json=json_set(source_json,",
    "'$.bundled',json('true'),'$.path','source.bin') WHERE source_id=?;"),
    params = list(source_ref$source_id))
  file.copy(external, file.path(state$root, "source.bin"))
  con <- file(file.path(state$root, "source.bin"), open = "ab")
  writeBin(charToRaw("mutation"), con); close(con)
  snapshot <- .wb_operation_pack_v3_g3_source_snapshot(state$bundle,
    source_ref)
  .wb_g3_expect_code(.wb_operation_pack_v3_g3_byte_evidence(state$bundle,
    snapshot, c("bytes_verified", "bytes_not_inspected",
      "bytes_unavailable")), "PYBENCH_INPUT_IDENTITY_MISMATCH")

  # The other two byte states are distinct, falsifiable, and admission-bound.
  clean <- jsonlite::fromJSON(DBI::dbGetQuery(state$bundle$con,
    "SELECT source_json FROM prov_source_inputs WHERE source_id=?;",
    params = list(source_ref$source_id))$source_json[[1L]],
    simplifyVector = FALSE)
  clean$bundled <- TRUE; clean$path <- "source.bin"
  clean_json <- jsonlite::toJSON(clean, auto_unbox = TRUE, null = "null")
  DBI::dbExecute(state$bundle$con,
    "UPDATE prov_source_inputs SET source_json=? WHERE source_id=?;",
    params = list(clean_json, source_ref$source_id))
  file.copy(external, file.path(state$root, "source.bin"), overwrite = TRUE)
  verified_source <- .wb_operation_pack_v3_g3_source_snapshot(state$bundle,
    source_ref)
  verified <- .wb_operation_pack_v3_g3_byte_evidence(state$bundle,
    verified_source, c("bytes_verified"))
  stopifnot(identical(verified$status, "bytes_verified"),
    identical(verified$declared_content_identity,
      verified$observed_content_identity),
    is.null(verified$nonverification_reason))
  unlink(file.path(state$root, "source.bin"))
  unavailable <- .wb_operation_pack_v3_g3_byte_evidence(state$bundle,
    verified_source, c("bytes_unavailable"))
  stopifnot(identical(unavailable$status, "bytes_unavailable"),
    is.null(unavailable$observed_content_identity),
    identical(unavailable$nonverification_reason,
      "external_bytes_unavailable"))
  .wb_g3_expect_code(.wb_operation_pack_v3_g3_byte_evidence(state$bundle,
    verified_source, c("bytes_verified")), "PYBENCH_CAPABILITY_MISMATCH")

  # Schema and identity faults fail closed before catalog registration.
  manifest <- jsonlite::read_json(file.path("tests", "fixtures",
    "operation-pack-v3-phase5", "inst", "scworkbench",
    "operation-pack.json"), simplifyVector = FALSE)
  index <- match("scwbv3phase5::adopt_external_state", vapply(
    manifest$operations, `[[`, character(1), "qualified_name"))
  before <- wb_operation_catalog_identity()
  bad <- .wb_operation_pack_v2_deep_copy(manifest)
  bad$operations[[index]]$supported_external_state_adoptions[[1L]]$
    allowed_source_byte_states <- list("bytes_verified")
  bad$operations[[index]]$supported_external_state_adoptions[[1L]]$
    declaration_identity <- NULL
  error <- tryCatch(wb_operation_pack_manifest_validate(bad), error = identity)
  stopifnot(inherits(error, "wb_operation_pack_v3_error"),
    identical(before, wb_operation_catalog_identity()))
  TRUE
}

test_operation_pack_v3_g3_shared_identity_fixture_contract <- function() {
  fixture <- jsonlite::read_json(file.path("inst", "protocol", "fixtures",
    "operation-pack-v3", "identities.json"), simplifyVector = FALSE)
  cases <- Filter(function(x) startsWith(x$name, "g3_"), fixture$cases)
  expected <- c("g3_declaration", "g3_source_snapshot",
    "g3_candidate_snapshot", "g3_adopted_closure",
    unlist(lapply(c("verified", "not_inspected", "unavailable"), function(x)
      paste0("g3_", c("byte_evidence_", "grant_", "observation_",
        "request_", "receipt_"), x)), use.names = FALSE))
  stopifnot(setequal(vapply(cases, `[[`, character(1), "name"), expected))
  for (item in cases) stopifnot(identical(item$identity$sha256,
    .wb_operation_pack_sha256(item$preimage)))
  stopifnot(identical(vapply(fixture$g3_positive_examples, `[[`,
    character(1), "status"), c("bytes_verified", "bytes_not_inspected",
      "bytes_unavailable")))
  TRUE
}
