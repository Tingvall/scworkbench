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

.wb_phase3b_pybench_commit <-
  "c85bf4136be6db92d8f1ffabbfdcdb2571869805"

.wb_phase3b_shared_sha256 <- c(
  "a4f095902b5dcb71bc4d84b5b248997b3c9748ef7e51e91c7ab6b77483efee8b",
  "9ff65685bcad2358b26a325beeed617cd6695ebf629b5c6412df3762ff929052",
  "e6ab7b7eeac2a4b60a4da405cdd70425d417a2fc61689dca585335f3f5eec25d",
  "31e104e2167a5c5c9b147afe280bd7b36220c3d61f1773445ded6ee9d52bbbee")

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
  source <- wb_new_run("phase3b_fixture_source",
    inputs = list(cell_set = "all", parents = character(),
      provenance_refs = list(), user_inputs = list()), params = list(),
    outputs = list(signals = family))
  session <- wb_session_add_run(wb_session_new(), source)

  run_family <- function(session_value = session) wb_session_run_op(
    session_value, bundle, "scwbpyv3reference::cardinality_family_probe",
    inputs = list(signals = wb_ref_run(source$run_id, "signals"),
      cell_set = "all", min_cells = 1L))
  bounded <- run_family()
  cat("PHASE3B_COMPOSITE bounded\n")
  scores <- bounded$run$outputs$scores
  stopifnot(identical(as.character(scores$key),
      rep(c("sigB", "sigA"), each = 3L)),
    identical(as.character(scores$cell_id), rep(cells, 2L)),
    identical(as.numeric(scores$value), as.numeric(family$value)))

  reduced <- wb_session_run_op(bounded$session, bundle,
    "scwbpyv3reference::cardinality_reduction_probe", inputs = list(
      signals = wb_ref_run(bounded$run$run_id, "scores"),
      cell_set = "all", min_cells = 1L))
  stopifnot(identical(as.character(reduced$run$outputs$reduced$cell_id),
      cells), identical(as.numeric(reduced$run$outputs$reduced$value),
      c(5, 7, 9)))
  cat("PHASE3B_COMPOSITE reduced\n")

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
  cat("PHASE3B_COMPOSITE cardinality_fault\n")

  run_chunk <- function(size) wb_session_run_op(session, bundle,
    "scwbpyv3reference::cell_chunk_probe", inputs = list(matrix = "RNA",
      cell_set = "all", min_cells = 1L, features = c("g2", "g1"),
      name = "Module", chunk_size = as.integer(size)))
  one <- run_chunk(3L)
  cat("PHASE3B_COMPOSITE chunk_one\n")
  many <- run_chunk(2L)
  cat("PHASE3B_COMPOSITE chunk_many\n")
  stopifnot(identical(.wb_phase3b_identity(one$run$outputs$scores),
      .wb_phase3b_identity(many$run$outputs$scores)),
    identical(.wb_phase3b_identity(one$run$outputs$summary),
      .wb_phase3b_identity(many$run$outputs$summary)))
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

  bounded_promotion <- wb_session_promote_current(bundle, bounded$session,
    outputs = "scores", created_by = "phase3b-composite")
  source_artifact <- as.character(bounded_promotion$promoted$artifact_id[[1]])
  ancestry <- wb_session_run_op(wb_session_new(), bundle,
    "scwbpyv3reference::ancestry_probe", inputs = list(
      signals = wb_ref_artifact(source_artifact, "scores"),
      cell_set = "all", min_cells = 1L))
  stopifnot(identical(as.character(
    ancestry$run$outputs$summary$rows$artifact_id), source_artifact))
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
  ancestry_promotion <- wb_session_promote_current(bundle, ancestry$session,
    outputs = "summary", created_by = "phase3b-composite")
  for (snapshot in c(reduced_promotion$provenance_snapshot_id,
      chunk_promotion$provenance_snapshot_id,
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
    identical(as.character(summary_loaded$rows$artifact_id), source_artifact))
  TRUE
}
