.wb_phase3b_context <- function() {
  root <- Sys.getenv("SCWORKBENCH_PHASE3B_PYBENCH_ROOT", unset = "")
  manifest <- Sys.getenv("SCWORKBENCH_PHASE3B_PYTHON_PACK_MANIFEST",
    unset = "")
  python <- Sys.getenv("SCWORKBENCH_PYBENCH_PYTHON", unset = "")
  if (!dir.exists(root) || !file.exists(manifest) || !file.exists(python))
    return(NULL)
  list(root = normalizePath(root, winslash = "/", mustWork = TRUE),
    manifest = normalizePath(manifest, winslash = "/", mustWork = TRUE),
    python = file.path(normalizePath(dirname(python), winslash = "/",
      mustWork = TRUE), basename(python)))
}

.wb_phase3b_skip <- function() contract_test_skip(paste(
  "Phase 3B Python fixture requires SCWORKBENCH_PHASE3B_PYBENCH_ROOT,",
  "SCWORKBENCH_PHASE3B_PYTHON_PACK_MANIFEST, and",
  "SCWORKBENCH_PYBENCH_PYTHON"))

.wb_phase3b_pybench_commit <- local({
  # Qualification may independently pin an explicitly reviewed final peer;
  # unchanged protocol bytes must still match below. Never infer expected HEAD.
  env <- new.env(parent = baseenv())
  sys.source("tests/helpers/operation_pack_test_peer_pin.R", env)
  env$.operation_pack_test_peer_pin("3412d37fe7154f6eeaa05f91eca783afe1f24d5c")
})

.wb_phase3b_shared_sha256 <- c(
  "943172e765d039a154fc428bf0adce16d57517c196b35bc75382cdb989c06dc1",
  "6e94c129d5199acd3e366ae92581ba4245caa7222757d8d5a694d4068d10660d",
  "770ed429cc3cbe6df896db62fabb8837c836e5cce07e45e7cbe5423e5acfdf7c",
  "27f0e7317298815b82dc7ab4d2b7f4967549a8f90663bf5d3f337d1e5bca9793")

.wb_phase3b_registry_guard <- function() {
  registry <- getFromNamespace(".wb_operation_pack_registry", "scworkbench")
  list(registry = registry, packs = registry$packs,
    operations = registry$operations)
}

.wb_phase3b_registry_restore <- function(guard) {
  guard$registry$packs <- guard$packs
  guard$registry$operations <- guard$operations
  invisible(TRUE)
}

.wb_phase3b_transition_inventory <- function(root) {
  final <- file.path(root, "operation_pack_v2")
  pending <- file.path(root, ".operation_pack_v2_pending")
  list(final = if (dir.exists(final)) sort(list.dirs(final,
    recursive = FALSE, full.names = FALSE), method = "radix") else
      character(), pending = if (dir.exists(pending)) sort(list.dirs(pending,
        recursive = FALSE, full.names = FALSE), method = "radix") else
      character())
}

.wb_phase3b_identity <- function(value) digest::digest(
  scworkbench:::.wb_operation_pack_canonical_json(unclass(value)),
  algo = "sha256", serialize = FALSE)

.wb_phase3b_mutate_python_payload <- function(relative, mutate) {
  fired <- FALSE
  options(scworkbench.operation_pack_v2_test_hook = function(event,
      stage = NULL, ...) {
    if (!fired && identical(event, "python_process_completed")) {
      fired <<- TRUE
      path <- file.path(stage, relative)
      value <- jsonlite::read_json(path, simplifyVector = FALSE)
      scworkbench:::.wb_operation_pack_v2_atomic_json(mutate(value), path)
    }
  })
  function() fired
}

test_operation_pack_v3_python_composite_protocol_contract <- function() {
  context <- .wb_phase3b_context()
  if (is.null(context)) return(.wb_phase3b_skip())
  observed <- system2("git", c("-C", context$root, "rev-parse", "HEAD"),
    stdout = TRUE)
  stopifnot(identical(observed, .wb_phase3b_pybench_commit))
  shared <- c("operation-pack-v3.schema.json",
    "operation-pack-transition-request-v3.schema.json",
    "operation-pack-transition-receipt-v3.schema.json",
    "fixtures/operation-pack-v3/identities.json")
  for (i in seq_along(shared)) {
    r_path <- file.path("inst", "protocol", shared[[i]])
    py_path <- file.path(context$root, "protocol", shared[[i]])
    stopifnot(identical(readBin(r_path, "raw", file.info(r_path)$size),
      readBin(py_path, "raw", file.info(py_path)$size)), identical(
      digest::digest(file = r_path, algo = "sha256", serialize = FALSE),
      .wb_phase3b_shared_sha256[[i]]))
  }
  TRUE
}

test_operation_pack_v3_python_composite_lifecycle_contract <- function() {
  context <- .wb_phase3b_context()
  if (is.null(context)) return(.wb_phase3b_skip())
  guard <- .wb_phase3b_registry_guard()
  on.exit(.wb_phase3b_registry_restore(guard), add = TRUE)
  activated <- wb_operation_pack_activate(context$manifest,
    python = context$python)
  stopifnot(identical(activated$identity$pack_abi_version, "3"),
    identical(activated$identity$backend, "Python"))

  root <- tempfile("scwb_phase3b_python_")
  bundle <- wb_init_bundle(root)
  on.exit({
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    try(wb_close_bundle(bundle), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  cells <- c("c2", "c1", "c3")
  features <- c("g2", "g1", "g3")
  wb_define_cells(bundle, cells)
  values <- Matrix::Matrix(matrix(seq_len(9L), nrow = 3L,
    dimnames = list(features, cells)), sparse = TRUE)
  wb_attach_matrix(bundle, "RNA", values, feature_type = "gene")
  family <- wb_prim_cell_vector_family(rep(c("sigB", "sigA"), each = 3L),
    rep(cells, 2L), c(1, 2, 3, 4, 5, 6), meta = list(fixture = "phase3b"))
  session <- wb_session_new()

  run_family <- function(session_value = session) wb_session_run_op(
    session_value, bundle, "scwbpyv3reference::cardinality_family_probe",
    inputs = list(signals = family,
      cell_set = "all", min_cells = 1L))
  bounded <- run_family()
  scores <- bounded$run$outputs$scores
  stopifnot(identical(as.character(scores$key),
      rep(c("sigB", "sigA"), each = 3L)),
    identical(as.character(scores$cell_id), rep(cells, 2L)),
    identical(as.numeric(scores$value), as.numeric(family$value)))

  # A changed staged family payload is rejected before publication and leaves
  # neither a published transition nor a pending staging directory.
  before <- .wb_phase3b_transition_inventory(root)
  fired <- .wb_phase3b_mutate_python_payload("outputs/scores/payload.json",
    function(value) {
      value$cell_id[c(1L, 2L)] <- value$cell_id[c(2L, 1L)]
      value
    })
  failed <- try(run_family(), silent = TRUE)
  options(scworkbench.operation_pack_v2_test_hook = NULL)
  stopifnot(fired(), inherits(failed, "try-error"),
    identical(before, .wb_phase3b_transition_inventory(root)))

  bounded_promotion <- wb_session_promote_current(bundle, bounded$session,
    outputs = "scores", created_by = "phase3b-composite")
  source_artifact <- as.character(bounded_promotion$promoted$artifact_id[[1]])
  reduced <- wb_session_run_op(wb_session_new(), bundle,
    "scwbpyv3reference::cardinality_reduction_probe", inputs = list(
      signals = wb_ref_artifact(source_artifact, "scores"),
      cell_set = "all", min_cells = 1L))
  stopifnot(identical(as.character(reduced$run$outputs$reduced$cell_id),
      cells), identical(as.numeric(reduced$run$outputs$reduced$value),
      c(5, 7, 9)))

  run_chunk <- function(size, matrix_input = "RNA",
      session_value = session) wb_session_run_op(session_value, bundle,
    "scwbpyv3reference::cell_chunk_probe", inputs = list(matrix = matrix_input,
      cell_set = "all", min_cells = 1L,
      features = list(module1 = c("g2", "g1")),
      slice_features = c("g2", "g1"), name = "Module",
      chunk_size = as.integer(size)))
  one <- run_chunk(3L)
  many <- run_chunk(2L)
  stopifnot(identical(.wb_phase3b_identity(one$run$outputs$scores),
      .wb_phase3b_identity(many$run$outputs$scores)),
    identical(.wb_phase3b_identity(one$run$outputs$summary),
      .wb_phase3b_identity(many$run$outputs$summary)))
  inline_matrix <- structure(list(kind = "matrix",
    values = as.matrix(values), dimensions = as.integer(dim(values)),
    cell_id = cells, feature_id = features,
    storage_profile = "matrix_ordinary_v1", meta = list()),
    class = "wb_primitive")
  inline <- run_chunk(2L, inline_matrix, wb_session_new())
  stopifnot(identical(.wb_phase3b_identity(inline$run$outputs$scores),
      .wb_phase3b_identity(many$run$outputs$scores)),
    identical(.wb_phase3b_identity(inline$run$outputs$summary),
      .wb_phase3b_identity(many$run$outputs$summary)))
  zero <- wb_session_run_op(wb_session_new(), bundle,
    "scwbpyv3reference::zero_axis_probe", inputs = list(matrix = "RNA",
      cell_set = "all", min_cells = 1L, slice_features = character(),
      chunk_size = 2L))
  stopifnot(identical(as.integer(
    zero$run$outputs$summary$table$typed_slice_calls), 0L))
  before <- .wb_phase3b_transition_inventory(root)
  fired <- .wb_phase3b_mutate_python_payload("outputs/summary/payload.json",
    function(value) {
      value$rows[[1]]$score_rows <- 999L
      value
    })
  failed <- try(run_chunk(2L), silent = TRUE)
  options(scworkbench.operation_pack_v2_test_hook = NULL)
  stopifnot(fired(), inherits(failed, "try-error"),
    identical(before, .wb_phase3b_transition_inventory(root)))

  ancestry <- wb_session_run_op(wb_session_new(), bundle,
    "scwbpyv3reference::ancestry_probe", inputs = list(
      signals = wb_ref_artifact(source_artifact, "scores"),
      cell_set = "all", min_cells = 1L))
  stopifnot(identical(as.character(
    ancestry$run$outputs$summary$table$artifact_id), source_artifact))
  before <- .wb_phase3b_transition_inventory(root)
  fired <- .wb_phase3b_mutate_python_payload(
    "provenance_reads/ancestry/payload.json", function(value) {
      value$artifact_id <- paste0(value$artifact_id, "-forged")
      value
    })
  failed <- try(wb_session_run_op(wb_session_new(), bundle,
    "scwbpyv3reference::ancestry_probe", inputs = list(
      signals = wb_ref_artifact(source_artifact, "scores"),
      cell_set = "all", min_cells = 1L)), silent = TRUE)
  options(scworkbench.operation_pack_v2_test_hook = NULL)
  stopifnot(fired(), inherits(failed, "try-error"),
    identical(before, .wb_phase3b_transition_inventory(root)))

  reduced_promotion <- wb_session_promote_current(bundle, reduced$session,
    outputs = "reduced", created_by = "phase3b-composite")
  chunk_promotion <- wb_session_promote_current(bundle, many$session,
    outputs = "scores", created_by = "phase3b-composite")
  wb_session_promote_current(bundle, inline$session,
    outputs = "scores", created_by = "phase3b-composite-inline")
  zero_promotion <- wb_session_promote_current(bundle, zero$session,
    outputs = "summary", created_by = "phase3b-composite")
  ancestry_promotion <- wb_session_promote_current(bundle, ancestry$session,
    outputs = "summary", created_by = "phase3b-composite")
  chunk_record_path <- file.path(root, "operation_pack_v2",
    inline$run$operation_pack_transition$transition_id)
  chunk_record <- scworkbench:::.wb_operation_pack_v2_record_validate(
    chunk_record_path, load_payloads = TRUE)
  stopifnot(isTRUE(chunk_record$ok), identical(
      chunk_record$request$typed_slice_grants[[1]]$source_reference$
        source_kind, "in_memory_selected_projection"),
    identical(chunk_record$receipt$typed_slice_usage[[1]]$coverage_status,
      "exact"),
    !dir.exists(file.path(chunk_record_path, "broker")),
    !file.exists(file.path(chunk_record_path,
      "broker-observations.json")))
  zero_record <- scworkbench:::.wb_operation_pack_v2_record_validate(
    file.path(root, "operation_pack_v2",
      zero$run$operation_pack_transition$transition_id),
    load_payloads = TRUE)
  stopifnot(isTRUE(zero_record$ok), identical(
      zero_record$receipt$typed_slice_usage[[1]]$calls, list()),
    identical(zero_record$receipt$typed_slice_usage[[1]]$call_count, 0L),
    identical(zero_record$receipt$typed_slice_usage[[1]]$coverage_status,
      "empty"))
  for (snapshot in c(reduced_promotion$provenance_snapshot_id,
      chunk_promotion$provenance_snapshot_id,
      zero_promotion$provenance_snapshot_id,
      ancestry_promotion$provenance_snapshot_id)) {
    replay <- wb_prov_validate_replay(bundle, snapshot_id = snapshot,
      mode = "symbolic", profile = "strict", strict = TRUE)
    stopifnot(isTRUE(replay$summary$valid),
      all(replay$per_run$status == "ok"))
  }

  registry <- scworkbench:::.wb_operation_pack_registry
  saved_pack <- registry$packs$scwbpyv3reference
  saved_operations <- registry$operations[saved_pack$operation_names]
  for (name in saved_pack$operation_names) registry$operations[[name]] <- NULL
  registry$packs$scwbpyv3reference <- NULL
  on.exit({
    registry$packs$scwbpyv3reference <- saved_pack
    for (name in names(saved_operations))
      registry$operations[[name]] <- saved_operations[[name]]
  }, add = TRUE)
  wb_finalize_recipient_bundle(bundle)
  wb_close_bundle(bundle)
  bundle <- wb_open_bundle(root, read_only = TRUE)
  report <- wb_bundle_validation_report(root, level = "recipient")
  reduced_loaded <- wb_art_load(bundle,
    reduced_promotion$promoted$artifact_id[[1]], expected_kind = "cell_vector")
  scores_loaded <- wb_art_load(bundle,
    chunk_promotion$promoted$artifact_id[
      chunk_promotion$promoted$output == "scores"][[1]],
    expected_kind = "cell_vector_family")
  summary_loaded <- wb_art_load(bundle,
    ancestry_promotion$promoted$artifact_id[[1]], expected_kind = "obs_table")
  stopifnot(isTRUE(report$ok),
    identical(as.character(reduced_loaded$cell_id), cells),
    identical(as.numeric(reduced_loaded$value), c(5, 7, 9)),
    identical(as.character(scores_loaded$cell_id), cells),
    identical(as.character(summary_loaded$table$artifact_id), source_artifact))
  TRUE
}

test_operation_pack_v3_python_phase5_model_lifecycle_contract <- function() {
  context <- .wb_phase3b_context()
  if (is.null(context)) return(.wb_phase3b_skip())
  guard <- .wb_phase3b_registry_guard()
  on.exit(.wb_phase3b_registry_restore(guard), add = TRUE)
  wb_operation_pack_activate(context$manifest, python = context$python)

  root <- tempfile("scwb_phase5_python_model_")
  bundle <- wb_init_bundle(root)
  on.exit({
    try(wb_close_bundle(bundle), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  cells <- c("c2", "c1", "c3")
  wb_define_cells(bundle, cells)
  coordinates <- matrix(c(2, 1, 4, 1, 2, 5, 0, 3, 6), nrow = 3L,
    dimnames = list(cells, c("D1", "D2", "D3")))
  wb_add_space(bundle, "fit-space", coordinates)

  fit <- wb_session_run_op(wb_session_new(), bundle,
    "scwbpyv3reference::sibling_model_fit_probe", inputs = list(
      fit_space = "fit-space", dims = c(2L, 1L), cell_set = "all",
      min_cells = 1L))
  transition_model <- wb_operation_pack_transition_load(
    fit$session$staging_bundle,
    fit$run$operation_pack_transition$transition_id, "model")
  stopifnot(identical(transition_model$kind, "model_ref"),
    identical(transition_model$model_source_linkage$source_space_id,
      "fit-space"), dir.exists(transition_model$model_tree_root),
    file.exists(file.path(transition_model$model_tree_root,
      transition_model$model_primary_path)))

  promoted <- wb_session_promote_current(bundle, fit$session,
    outputs = c("model", "pseudotime", "entropy", "summary"),
    created_by = "phase5-python-composite")
  stopifnot(nrow(promoted$promoted) == 4L,
    all(promoted$promoted$status == "ok"))
  model_id <- promoted$promoted$artifact_id[
    promoted$promoted$output == "model"][[1L]]
  try(wb_session_discard(fit$session), silent = TRUE)

  consumed <- wb_session_run_op(wb_session_new(), bundle,
    "scwbpyv3reference::self_linked_model_read_probe", inputs = list(
      model = wb_ref_artifact(model_id, "model"), reader_calls = 1L,
      cell_set = "all", min_cells = 1L))
  receipt <- jsonlite::read_json(file.path(.wb_operation_pack_v2_store(
    consumed$session$staging_bundle),
    consumed$run$operation_pack_transition$transition_id, "receipt.json"),
    simplifyVector = FALSE)
  stopifnot(length(receipt$self_linked_model_payload_reads) == 1L,
    identical(receipt$self_linked_model_payload_reads[[1L]]$
      integrity_status, "unchanged"))
  consumed_promotion <- wb_session_promote_current(bundle, consumed$session,
    outputs = "summary", created_by = "phase5-python-composite")
  stopifnot(nrow(consumed_promotion$promoted) == 1L,
    consumed_promotion$promoted$status[[1L]] == "ok")
  try(wb_session_discard(consumed$session), silent = TRUE)

  stopifnot(isTRUE(wb_finalize_recipient_bundle(bundle)$ready))
  wb_close_bundle(bundle); bundle <- NULL
  bundle <- wb_open_bundle(root, read_only = TRUE)
  validation <- wb_bundle_validation_report(root, level = "recipient")
  reopened <- wb_art_load(bundle, model_id, expected_kind = "model_ref")
  if (!isTRUE(validation$ok)) stop(paste(capture.output(print(
    validation$diagnostics)), collapse = "\n"), call. = FALSE)
  stopifnot(isTRUE(validation$ok), dir.exists(reopened$model_tree_root),
    identical(reopened$model_source_linkage$source_space_id, "fit-space"),
    identical(reopened$model_source_linkage$linkage_identity,
      transition_model$model_source_linkage$linkage_identity))
  TRUE
}
