.wb_v3_identity <- function(value, field) {
  payload <- value
  payload[[field]] <- NULL
  digest::digest(scworkbench:::.wb_operation_pack_canonical_json(payload),
    algo = "sha256", serialize = FALSE)
}

.wb_v3_fixture_install <- function() {
  lib <- tempfile("scwb_v3_fixture_lib_")
  dir.create(lib, recursive = TRUE)
  log <- tempfile("scwb_v3_fixture_install_", fileext = ".log")
  source <- file.path(normalizePath(".", winslash = "/", mustWork = TRUE),
    "tests", "fixtures", "operation-pack-v3-reference")
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(lib)), shQuote(source)), stdout = log,
    stderr = log)
  if (!identical(status, 0L)) stop(paste(readLines(log, warn = FALSE),
    collapse = "\n"), call. = FALSE)
  old <- .libPaths(); .libPaths(c(lib, old))
  manifest <- system.file("scworkbench", "operation-pack.json",
    package = "scwbV3Reference", lib.loc = lib)
  activated <- wb_operation_pack_activate(manifest, lib.loc = lib)
  list(lib = lib, old = old, manifest = manifest, activated = activated)
}

.wb_v3_fixture_cleanup <- function(installed = NULL, bundle = NULL,
                                    root = NULL) {
  try(wb_operation_pack_unload("scwbv3reference"), silent = TRUE)
  registry <- scworkbench:::.wb_operation_pack_registry
  pack <- registry$packs$scwbv3reference
  if (!is.null(pack)) {
    for (name in if (is.null(pack$operation_names)) character() else
        pack$operation_names)
      registry$operations[[name]] <- NULL
    registry$packs$scwbv3reference <- NULL
  }
  if (!is.null(bundle)) try(wb_close_bundle(bundle), silent = TRUE)
  if (!is.null(installed)) {
    if ("scwbV3Reference" %in% loadedNamespaces())
      try(unloadNamespace("scwbV3Reference"), silent = TRUE)
    .libPaths(installed$old)
    unlink(installed$lib, recursive = TRUE, force = TRUE)
  }
  if (!is.null(root)) unlink(root, recursive = TRUE, force = TRUE)
  invisible(TRUE)
}

.wb_v3_bundle <- function() {
  root <- tempfile("scwb_v3_bundle_")
  bundle <- wb_init_bundle(root)
  cells <- c("c2", "c1", "c3")
  features <- c("g2", "g1", "g3", "g4")
  wb_define_cells(bundle, cells)
  values <- Matrix::Matrix(matrix(seq_len(12L), nrow = 4L,
    dimnames = list(features, cells)), sparse = TRUE)
  wb_attach_matrix(bundle, "RNA", values, feature_type = "gene")
  list(root = root, bundle = bundle, cells = cells, features = features,
    params = list(features = list(sigB = list("g2", "g4"),
      sigA = list("g1", "g3")), name = "Module"))
}

.wb_v3_input_record <- function(name, value, kind = value$kind) {
  declaration <- list(name = name, kind = kind, required = TRUE,
    alignment = if (kind == "matrix") "cell_and_feature_ordered" else
      "cell_ordered")
  descriptor <- scworkbench:::.wb_operation_pack_v2_input_descriptor(name,
    value, declaration)
  descriptor
}

.wb_v3_matrix <- function() {
  cells <- c("c2", "c1", "c3")
  features <- c("g2", "g1", "g3")
  structure(list(kind = "matrix",
    values = matrix(seq_len(9L), nrow = 3L,
      dimnames = list(features, cells)), dimensions = c(3L, 3L),
    cell_id = cells, feature_id = features,
    storage_profile = "matrix_ordinary_v1", meta = list()),
    class = "wb_primitive")
}

.wb_v3_family_policy <- function() list(output = "scores",
  policy = "authenticated_output_axes_v1", shape = "cell_key_cartesian",
  cell_axis = list(source = "effective_cells_v1", input = "matrix"),
  key_axis = list(source = "resolved_parameter_feature_groups_v1",
    groups_parameter = "features", matrix_input = "matrix",
    name_prefix_parameter = "name", matching = "exact_feature_id_v1",
    normalization = "ordered_unique_features_v1",
    generated_names = "legacy_module_group_names_v1",
    missing_feature_policy = list(source = "fixed_drop_v1"),
    empty_group_policy = "drop", zero_key_policy = "error"),
  row_order = "key_major_then_cell_v1", missing_values = "forbidden")

.wb_v3_family_grant <- function() {
  matrix <- .wb_v3_matrix()
  records <- list(matrix = .wb_v3_input_record("matrix", matrix))
  output <- list(name = "scores", kind = "cell_vector_family")
  grant <- scworkbench:::.wb_operation_pack_v3_cardinality_grant(
    .wb_v3_family_policy(), output, list(matrix = matrix),
    list(features = list(sigB = c("g2", "missing"), sigA = c("g1", "g3")),
      name = "Module"), records, matrix$cell_id)
  list(grant = grant, matrix = matrix, records = records)
}

test_operation_pack_v3_identity_fixture_contract <- function() {
  fixture <- jsonlite::read_json(
    "inst/protocol/fixtures/operation-pack-v3/identities.json",
    simplifyVector = FALSE)
  stopifnot(identical(fixture$canonical_json_scheme,
    "scworkbench.operation_pack.canonical_json.v1"),
    identical(as.character(unlist(fixture$authoritative_axes$cells)),
      c("c2", "c1", "c3")),
    length(fixture$cases) == 11L)
  identity_fields <- c(
    cardinality_three_cells_two_keys = "cardinality_grant_identity",
    observed_cardinality_three_cells_two_keys = "observed_cardinality_identity",
    typed_slice_cells_axis = "manifest_identity",
    typed_slice_features_axis = "manifest_identity",
    typed_slice_bundle_source = "source_reference_identity",
    typed_slice_cells_grant = "grant_identity",
    typed_slice_result_first_partition = "slice_result_identity",
    observed_typed_slice_call_first_partition = "call_identity",
    typed_slice_usage_one_independent_call = "usage_identity",
    source_snapshot_head = "source_snapshot_identity",
    current_artifact_ancestry = "snapshot_identity")
  for (case in fixture$cases) {
    field <- identity_fields[[case$name]]
    stopifnot(!is.null(field), identical(case$preimage,
      case$value[names(case$value) != field]),
      identical(.wb_v3_identity(case$value, field), case$identity$sha256))
  }
  TRUE
}

test_operation_pack_v3_bounded_cardinality_contract <- function() {
  state <- .wb_v3_family_grant()
  grant <- state$grant
  stopifnot(identical(as.character(unlist(grant$key_axis)),
    c("sigB", "sigA")), identical(grant$expected_row_count, 6L),
    identical(vapply(grant$key_axis_resolution$groups, `[[`, character(1),
      "key"), c("sigB", "sigA")),
    identical(grant$key_axis_resolution$groups[[1]]$features_missing,
      list("missing")), identical(.wb_v3_identity(grant,
        "cardinality_grant_identity"),
      grant$cardinality_grant_identity$sha256))
  value <- wb_prim_cell_vector_family(
    rep(c("sigB", "sigA"), each = 3L),
    rep(c("c2", "c1", "c3"), 2L), seq_len(6L),
    meta = list(fixture = "v3"))
  observed <- scworkbench:::.wb_operation_pack_v3_observe_cardinality(
    value, grant)
  stopifnot(identical(observed$observed_row_count, 6L),
    identical(observed$missing_count, 0L),
    identical(.wb_v3_identity(observed, "observed_cardinality_identity"),
      observed$observed_cardinality_identity$sha256))
  wrong <- value
  wrong$cell_id[c(1L, 2L)] <- wrong$cell_id[c(2L, 1L)]
  error <- try(scworkbench:::.wb_operation_pack_v3_observe_cardinality(
    wrong, grant), silent = TRUE)
  stopifnot(inherits(error, "try-error"),
    grepl("exact granted Cartesian product", as.character(error), fixed = TRUE))
  TRUE
}

test_operation_pack_v3_one_per_cell_contract <- function() {
  input <- wb_prim_cell_vector_family(c("b", "a", "b", "a"),
    c("c2", "c2", "c1", "c1"), c(1, 2, 3, 4))
  policy <- list(output = "reduced",
    policy = "authenticated_output_axes_v1", shape = "one_per_cell",
    cell_axis = list(source = "distinct_input_cells_first_occurrence_v1",
      input = "signal"), row_order = "input_cell_order_v1",
    missing_values = "canonical_null_allowed")
  record <- .wb_v3_input_record("signal", input)
  grant <- scworkbench:::.wb_operation_pack_v3_cardinality_grant(policy,
    list(name = "reduced", kind = "cell_vector"), list(signal = input),
    list(), list(signal = record))
  value <- wb_prim_cell_vector(stats::setNames(c(1, NA_real_),
    c("c2", "c1")), value_type = "continuous")
  observed <- scworkbench:::.wb_operation_pack_v3_observe_cardinality(value,
    grant)
  stopifnot(identical(grant$expected_row_count, 2L),
    identical(observed$missing_count, 1L))
  mutation <- value; mutation$cell_id <- rev(mutation$cell_id)
  stopifnot(inherits(try(scworkbench:::.wb_operation_pack_v3_observe_cardinality(
    mutation, grant), silent = TRUE), "try-error"))
  TRUE
}

test_operation_pack_v3_typed_slice_getter_contract <- function() {
  stopifnot(identical(wb_partition_axis(c("c2", "c1", "c3"), 2L),
    list(c("c2", "c1"), "c3")),
    identical(wb_partition_axis(character(), 2L), list()),
    inherits(try(wb_partition_axis(c("c1", "c1"), 1L), silent = TRUE),
      "try-error"))
  state <- .wb_v3_bundle()
  on.exit(.wb_v3_fixture_cleanup(bundle = state$bundle, root = state$root),
    add = TRUE)
  iterator <- wb_slice_chunks(state$bundle, "RNA",
    features = c("g2", "g1"), cells = c("c2", "c1", "c3"),
    axis = "cells", chunk_size = 2L)
  first <- iterator$next_chunk()
  second <- iterator$next_chunk()
  stopifnot(identical(first$ids, c("c2", "c1")),
    identical(second$ids, "c3"), is.null(iterator$next_chunk()),
    identical(rownames(first$value), c("g2", "g1")),
    identical(colnames(first$value), c("c2", "c1")))
  TRUE
}

test_operation_pack_v3_in_memory_typed_slice_source_contract <- function() {
  state <- .wb_v3_bundle()
  on.exit(.wb_v3_fixture_cleanup(bundle = state$bundle, root = state$root),
    add = TRUE)
  input <- .wb_v3_matrix()
  record <- .wb_v3_input_record("matrix", input)$descriptor
  stage <- tempfile("scwb_v3_private_source_")
  dir.create(stage)
  on.exit(unlink(stage, recursive = TRUE, force = TRUE), add = TRUE)
  declaration <- list(name = "matrix_chunks", input = "matrix",
    supported_axes = list("cells"), chunk_axis = "cells",
    chunk_size_parameter = "chunk_size",
    call_discipline = "ordered_partition_exactly_once",
    empty_selection_policy = "reject", selection = list(
      cells = list(policy = "effective_input_axis_v1"),
      features = list(policy = "effective_input_axis_v1")))
  source_state <- scworkbench:::.wb_operation_pack_v2_identity_plain(
    "scworkbench.scientific_state.v1",
    scworkbench:::.wb_manifest_registry_snapshot(state$bundle$con))
  grant <- scworkbench:::.wb_operation_pack_v3_typed_slice_grant(
    state$bundle, declaration, input, record, list(chunk_size = 2L),
    input$cell_id, source_state, stage)
  source <- grant$source_reference
  path <- file.path(stage, "typed_slice_sources", "matrix_chunks",
    "matrix.mtx")
  stopifnot(identical(source$source_kind,
      "in_memory_selected_projection"), file.exists(path),
    identical(scworkbench:::.wb_operation_pack_v3_unscoped_identity(
      source$projected_content_identity),
      source$projected_content_identity),
    identical(nrow(Matrix::readMM(path)), length(input$feature_id)),
    identical(ncol(Matrix::readMM(path)), length(input$cell_id)))
  validated <- scworkbench:::.wb_operation_pack_v3_private_source_validate(
    stage, grant)
  stopifnot(identical(as.integer(dim(validated)), c(3L, 3L)))
  first_value <- input
  first_value$values <- input$values[, c("c2", "c1"), drop = FALSE]
  first_value$cell_id <- c("c2", "c1")
  first <- scworkbench:::.wb_operation_pack_v3_slice_result(grant, 1L,
    first_value)
  last_value <- input
  last_value$values <- input$values[, "c3", drop = FALSE]
  last_value$cell_id <- "c3"
  last <- scworkbench:::.wb_operation_pack_v3_slice_result(grant, 2L,
    last_value)
  request <- list(typed_slice_grants = list(grant), request_identity = list(
      scheme = "scworkbench.operation_pack.transition_request.v3",
      sha256 = paste(rep("a", 64L), collapse = "")),
    execution_capability = list(capability_identity = list(
      scheme = "scworkbench.operation_pack.capability.v3",
      sha256 = paste(rep("b", 64L), collapse = ""))),
    operation_authentication = list(operation_definition_identity = list(
      scheme = "scworkbench.operation_pack.definition.v3",
      sha256 = paste(rep("c", 64L), collapse = ""))))
  adapter <- list(state = new.env(parent = emptyenv()))
  adapter$state$typed_slice_calls <- list(matrix_chunks = list(list(
    result = first, chunk_values = c("c2", "c1"))))
  partial <- try(scworkbench:::.wb_operation_pack_v3_typed_slice_usage(
    adapter, request), silent = TRUE)
  stopifnot(inherits(partial, "try-error"))
  adapter$state$typed_slice_calls$matrix_chunks[[2L]] <- list(
    result = last, chunk_values = "c3")
  usage <- scworkbench:::.wb_operation_pack_v3_typed_slice_usage(
    adapter, request)[[1L]]
  stopifnot(identical(usage$coverage_status, "exact"),
    identical(usage$call_count, 2L))
  zero <- grant
  attr(zero, "operation_pack_v3_cells") <- character()
  zero_request <- request
  zero_request$typed_slice_grants <- list(zero)
  zero_adapter <- list(state = new.env(parent = emptyenv()))
  zero_adapter$state$typed_slice_calls <- list(matrix_chunks = list())
  zero_usage <- scworkbench:::.wb_operation_pack_v3_typed_slice_usage(
    zero_adapter, zero_request)[[1L]]
  stopifnot(identical(zero_usage$coverage_status, "empty"),
    identical(zero_usage$call_count, 0L))
  zero_adapter$state$typed_slice_calls$matrix_chunks <- list(list(
    result = first, chunk_values = c("c2", "c1")))
  stopifnot(inherits(try(
    scworkbench:::.wb_operation_pack_v3_typed_slice_usage(zero_adapter,
      zero_request), silent = TRUE), "try-error"))
  mutated <- first_value
  mutated$values[1L, 1L] <- mutated$values[1L, 1L] + 1
  second <- scworkbench:::.wb_operation_pack_v3_slice_result(grant, 1L,
    mutated)
  stopifnot(!identical(first$semantic_content_identity,
      second$semantic_content_identity),
    !identical(first$slice_result_identity, second$slice_result_identity))
  bytes <- readBin(path, "raw", n = file.info(path)$size)
  bytes[[length(bytes)]] <- as.raw(bitwXor(as.integer(bytes[[length(bytes)]]),
    1L))
  writeBin(bytes, path)
  stopifnot(inherits(try(
    scworkbench:::.wb_operation_pack_v3_private_source_validate(stage, grant),
    silent = TRUE), "try-error"))
  TRUE
}

test_operation_pack_v3_shared_schema_drift_contract <- function() {
  files <- c("operation-pack-v3.schema.json",
    "operation-pack-transition-request-v3.schema.json",
    "operation-pack-transition-receipt-v3.schema.json",
    "fixtures/operation-pack-v3/identities.json")
  expected <- c(
    "f263fbcf15d3a928c5a3b7cfa41ca27b4f5d3e0f31f2b8f42cc930b1d9713ff3",
    "9935a10ca05c5c767e739d06839b5d4fcbf53de549ea95b8cd4d1e711e8089d6",
    "6ba0a1875100cda766cc5c5f10caa01fc654dd9688250d3ff17389bb4c561e28",
    "ed31bcf18062d57b6ea8d8f7a787f8932138f959e5762d195b3968438d052f32")
  observed <- vapply(file.path("inst", "protocol", files),
    digest::digest, character(1), algo = "sha256", serialize = FALSE,
    file = TRUE)
  stopifnot(identical(unname(observed), expected))
  TRUE
}

test_operation_pack_v3_r_lifecycle_contract <- function() {
  installed <- .wb_v3_fixture_install()
  state <- .wb_v3_bundle()
  on.exit(.wb_v3_fixture_cleanup(installed, state$bundle, state$root),
    add = TRUE)
  stopifnot(identical(installed$activated$identity$pack_abi_version, "3"))

  bounded <- wb_session_run_op(wb_session_new(), state$bundle,
    "scwbv3reference::bounded_family", inputs = c(list(
      matrix = "RNA", cell_set = "all", min_cells = 1L), state$params))
  scores <- bounded$run$outputs$scores
  stopifnot(identical(as.character(scores$key),
      rep(c("sigB", "sigA"), each = 3L)),
    identical(as.character(scores$cell_id), rep(state$cells, 2L)))
  reduced <- wb_session_run_op(bounded$session, state$bundle,
    "scwbv3reference::reduce_family", inputs = list(
      signal = wb_ref_run(bounded$run$run_id, "scores"),
      cell_set = "all", min_cells = 1L))
  stopifnot(identical(as.character(reduced$run$outputs$reduced$cell_id),
    state$cells), length(reduced$run$outputs$reduced$value) == 3L)
  reduced_promotion <- wb_session_promote_current(state$bundle,
    reduced$session, outputs = "reduced", created_by = "abi-v3-contract")
  reduced_id <- as.character(reduced_promotion$promoted$artifact_id[
    reduced_promotion$promoted$output == "reduced"][[1]])
  reduced_loaded <- wb_art_load(state$bundle,
    reduced_id, expected_kind = "cell_vector")
  stopifnot(identical(as.character(reduced_loaded$cell_id), state$cells))
  promoted <- wb_session_promote_current(state$bundle, bounded$session,
    outputs = "scores", created_by = "abi-v3-contract")
  artifact_id <- as.character(promoted$promoted$artifact_id[[1]])

  ancestry <- wb_session_run_op(wb_session_new(), state$bundle,
    "scwbv3reference::ancestry_family", inputs = list(
      signal = wb_ref_artifact(artifact_id, "scores"),
      artifact_id = artifact_id, cell_set = "all", min_cells = 1L))
  stopifnot(identical(as.numeric(ancestry$run$outputs$smoothed$value),
    as.numeric(scores$value)))
  artifact_count <- DBI::dbGetQuery(state$bundle$con,
    "SELECT COUNT(*) AS n FROM artifacts;")$n[[1]]
  DBI::dbExecute(state$bundle$con, paste0(
    "UPDATE entity_lifecycle SET lifecycle_state='superseded' ",
    "WHERE entity_kind='artifact' AND entity_id=?;"),
    params = list(artifact_id))
  stale <- try(wb_session_promote_current(state$bundle, ancestry$session,
    outputs = "smoothed", created_by = "abi-v3-contract"), silent = TRUE)
  stopifnot(inherits(stale, "try-error"), identical(
    DBI::dbGetQuery(state$bundle$con,
      "SELECT COUNT(*) AS n FROM artifacts;")$n[[1]], artifact_count))
  DBI::dbExecute(state$bundle$con, paste0(
    "UPDATE entity_lifecycle SET lifecycle_state='current' ",
    "WHERE entity_kind='artifact' AND entity_id=?;"),
    params = list(artifact_id))
  ancestry_promotion <- wb_session_promote_current(state$bundle,
    ancestry$session, outputs = "smoothed", created_by = "abi-v3-contract")
  transition_id <- as.character(ancestry$run$operation_pack_transition$
    transition_id)[1]
  record_path <- file.path(scworkbench:::.wb_operation_pack_v2_store(
    state$bundle), transition_id)
  record <- scworkbench:::.wb_operation_pack_v2_record_validate(record_path,
    load_payloads = TRUE)
  stopifnot(isTRUE(record$ok), length(record$request$provenance_reads) == 1L,
    length(record$receipt$provenance_reads) == 1L)
  copied <- tempfile("scwb_v3_record_")
  dir.create(copied)
  stopifnot(file.copy(list.files(record_path, full.names = TRUE,
    all.files = TRUE, no.. = TRUE), copied, recursive = TRUE))
  copied_payload <- file.path(copied, "provenance_reads",
    "source_ancestry", "payload.json")
  bytes <- readBin(copied_payload, "raw", n = file.info(copied_payload)$size)
  bytes[[max(1L, length(bytes) - 2L)]] <- as.raw(bitwXor(as.integer(
    bytes[[max(1L, length(bytes) - 2L)]]), 1L))
  writeBin(bytes, copied_payload)
  corrupted <- scworkbench:::.wb_operation_pack_v2_record_validate(copied,
    load_payloads = TRUE)
  unlink(copied, recursive = TRUE, force = TRUE)
  stopifnot(!isTRUE(corrupted$ok), identical(corrupted$code,
    "v3_provenance_read_payload_identity_mismatch"))

  replay <- wb_prov_validate_replay(state$bundle,
    snapshot_id = ancestry_promotion$provenance_snapshot_id,
    mode = "symbolic", profile = "strict", strict = TRUE)
  stopifnot(isTRUE(replay$summary$valid),
    all(replay$per_run$status == "ok"))

  registry <- scworkbench:::.wb_operation_pack_registry
  saved_pack <- registry$packs$scwbv3reference
  saved_operations <- registry$operations[
    saved_pack$operation_names]
  for (name in saved_pack$operation_names)
    registry$operations[[name]] <- NULL
  registry$packs$scwbv3reference <- NULL
  on.exit({
    registry$packs$scwbv3reference <- saved_pack
    for (name in names(saved_operations))
      registry$operations[[name]] <- saved_operations[[name]]
  }, add = TRUE)
  wb_finalize_recipient_bundle(state$bundle)
  wb_close_bundle(state$bundle)
  state$bundle <- wb_open_bundle(state$root, read_only = TRUE)
  report <- wb_bundle_validation_report(state$root, level = "recipient")
  loaded <- wb_art_load(state$bundle,
    ancestry_promotion$promoted$artifact_id[[1]],
    expected_kind = "cell_vector_family")
  stopifnot(isTRUE(report$ok), identical(as.numeric(loaded$value),
    as.numeric(scores$value)))
  TRUE
}

test_operation_pack_v3_chunk_replay_and_rollback_contract <- function() {
  installed <- .wb_v3_fixture_install()
  state <- .wb_v3_bundle()
  on.exit(.wb_v3_fixture_cleanup(installed, state$bundle, state$root),
    add = TRUE)
  run_chunked <- function(size) wb_session_run_op(wb_session_new(),
    state$bundle, "scwbv3reference::chunked_family", inputs = c(list(
      matrix = "RNA", cell_set = "all", min_cells = 1L,
      chunk_size = as.integer(size)), state$params))
  one <- run_chunked(3L)
  many <- run_chunked(2L)
  identity <- function(value) digest::digest(
    scworkbench:::.wb_operation_pack_canonical_json(unclass(value)),
    algo = "sha256", serialize = FALSE)
  stopifnot(identical(identity(one$run$outputs$scores),
      identity(many$run$outputs$scores)),
    identical(identity(one$run$outputs$summary),
      identity(many$run$outputs$summary)))
  wb_session_promote_current(state$bundle, many$session,
    outputs = c("scores", "summary"), created_by = "abi-v3-typed-slice")
  transition_id <- many$run$operation_pack_transition$transition_id
  record_path <- file.path(state$root, "operation_pack_v2", transition_id)
  record <- scworkbench:::.wb_operation_pack_v2_record_validate(record_path,
    load_payloads = TRUE)
  stopifnot(isTRUE(record$ok),
    length(record$request$typed_slice_grants) == 1L,
    length(record$receipt$typed_slice_usage) == 1L,
    identical(record$receipt$typed_slice_usage[[1]]$coverage_status, "exact"),
    identical(record$receipt$typed_slice_usage[[1]]$call_count, 2L),
    identical(vapply(record$receipt$typed_slice_usage[[1]]$calls, `[[`,
      integer(1), "cell_count"), c(2L, 1L)),
    file.exists(file.path(record_path,
      record$request$typed_slice_grants[[1]]$cells_axis$relative_path)))
  copied <- tempfile("scwb_v3_typed_slice_record_")
  dir.create(copied)
  stopifnot(file.copy(list.files(record_path, full.names = TRUE,
    all.files = TRUE, no.. = TRUE), copied, recursive = TRUE))
  receipt_path <- file.path(copied, "receipt.json")
  corrupted_receipt <- jsonlite::read_json(receipt_path,
    simplifyVector = FALSE)
  corrupted_receipt$typed_slice_usage[[1]]$calls[[1]]$cell_count <- 1L
  scworkbench:::.wb_operation_pack_v2_atomic_json(corrupted_receipt,
    receipt_path)
  corrupted <- scworkbench:::.wb_operation_pack_v2_record_validate(copied,
    load_payloads = TRUE)
  unlink(copied, recursive = TRUE, force = TRUE)
  stopifnot(!isTRUE(corrupted$ok))

  store <- file.path(state$root, "operation_pack_v2")
  before <- if (dir.exists(store))
    list.dirs(store, recursive = FALSE,
      full.names = FALSE) else character()
  fired <- FALSE
  options(scworkbench.operation_pack_v2_test_hook = function(event, ...) {
    if (!fired && identical(event, "before_publication")) {
      fired <<- TRUE
      stop("injected ABI v3 publication failure")
    }
  })
  on.exit(options(scworkbench.operation_pack_v2_test_hook = NULL), add = TRUE)
  failed <- try(run_chunked(2L), silent = TRUE)
  options(scworkbench.operation_pack_v2_test_hook = NULL)
  after <- if (dir.exists(store))
    list.dirs(store, recursive = FALSE,
      full.names = FALSE) else character()
  stopifnot(fired, inherits(failed, "try-error"), identical(before, after),
    identical(run_chunked(2L)$run$outputs$scores$value,
      many$run$outputs$scores$value))
  TRUE
}
