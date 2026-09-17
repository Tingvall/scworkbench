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
    length(fixture$cases) == 8L)
  identity_fields <- c(
    cardinality_three_cells_two_keys = "cardinality_grant_identity",
    observed_cardinality_three_cells_two_keys = "observed_cardinality_identity",
    pure_summary_finalizer = "finalizer_definition_identity",
    fragment_1 = "fragment_grant_identity",
    fragment_2 = "fragment_grant_identity",
    cell_schedule_two_batches = "schedule_identity",
    source_snapshot_head = "source_snapshot_identity",
    current_successor_artifact_ancestry = "snapshot_identity")
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

test_operation_pack_v3_cell_chunk_contract <- function() {
  state <- .wb_v3_family_grant()
  chunk <- list(axis = "cells", input = "matrix",
    size_parameter = "chunk_size", fragment_output = "scores",
    summary_output = "summary", key_axis_policy = "scores",
    merge = "row_bind_cell_vector_family_v1",
    summary = list(interface = "pure_summary_finalizer_v1",
      callable = "summarize_scores", isolation = "fresh_pack_invocation_v1",
      metadata_sources = list(list(name = "keys",
        source = "resolved_key_axis", output = "scores"))))
  schedule <- scworkbench:::.wb_operation_pack_v3_chunk_schedule(chunk,
    list(chunk_size = 2L), state$grant, state$records$matrix)
  stopifnot(length(schedule$batches) == 2L,
    identical(vapply(schedule$batches, `[[`, integer(1), "start"),
      c(1L, 3L)), identical(.wb_v3_identity(schedule, "schedule_identity"),
      schedule$schedule_identity$sha256))
  make <- function(batch, offset) {
    keys <- as.character(unlist(batch$fragment_grant$key_axis))
    cells <- attr(batch$fragment_grant, "operation_pack_v3_cells")
    wb_prim_cell_vector_family(rep(keys, each = length(cells)),
      rep(cells, length(keys)), seq_len(length(keys) * length(cells)) +
        offset)
  }
  fragments <- list(`1` = make(schedule$batches[[1]], 0),
    `2` = make(schedule$batches[[2]], 10))
  merged <- scworkbench:::.wb_operation_pack_v3_merge_fragments(fragments,
    schedule)
  stopifnot(identical(merged$value$key,
    rep(c("sigB", "sigA"), each = 3L)),
    identical(merged$value$cell_id, rep(c("c2", "c1", "c3"), 2L)),
    length(merged$observations) == 2L)
  stopifnot(inherits(try(scworkbench:::.wb_operation_pack_v3_merge_fragments(
    fragments[1], schedule), silent = TRUE), "try-error"))
  TRUE
}

test_operation_pack_v3_shared_schema_drift_contract <- function() {
  files <- c("operation-pack-v3.schema.json",
    "operation-pack-transition-request-v3.schema.json",
    "operation-pack-transition-receipt-v3.schema.json",
    "fixtures/operation-pack-v3/identities.json")
  expected <- c(
    "a4f095902b5dcb71bc4d84b5b248997b3c9748ef7e51e91c7ab6b77483efee8b",
    "9ff65685bcad2358b26a325beeed617cd6695ebf629b5c6412df3762ff929052",
    "e6ab7b7eeac2a4b60a4da405cdd70425d417a2fc61689dca585335f3f5eec25d",
    "31e104e2167a5c5c9b147afe280bd7b36220c3d61f1773445ded6ee9d52bbbee")
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
  record_path <- file.path(state$root, "operation_pack_v2", transition_id)
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

  before <- if (dir.exists(file.path(state$root, "operation_pack_v2")))
    list.dirs(file.path(state$root, "operation_pack_v2"), recursive = FALSE,
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
  after <- if (dir.exists(file.path(state$root, "operation_pack_v2")))
    list.dirs(file.path(state$root, "operation_pack_v2"), recursive = FALSE,
      full.names = FALSE) else character()
  stopifnot(fired, inherits(failed, "try-error"), identical(before, after),
    identical(run_chunked(2L)$run$outputs$scores$value,
      many$run$outputs$scores$value))
  TRUE
}
