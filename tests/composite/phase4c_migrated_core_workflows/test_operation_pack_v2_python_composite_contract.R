.wb_phase2c_context <- function() {
  root <- Sys.getenv("SCWORKBENCH_PHASE2C_PYBENCH_ROOT", unset = "")
  manifest <- Sys.getenv("SCWORKBENCH_PHASE2C_PYTHON_PACK_MANIFEST", unset = "")
  python <- Sys.getenv("SCWORKBENCH_PYBENCH_PYTHON", unset = "")
  if (!dir.exists(root) || !file.exists(manifest) || !file.exists(python)) {
    return(NULL)
  }
  list(root = normalizePath(root, winslash = "/"),
    manifest = normalizePath(manifest, winslash = "/"),
    python = file.path(normalizePath(dirname(python), winslash = "/"),
      basename(python)))
}

.wb_phase2c_skip <- function() contract_test_skip(paste(
  "Phase 2C fixture requires SCWORKBENCH_PHASE2C_PYBENCH_ROOT,",
  "SCWORKBENCH_PHASE2C_PYTHON_PACK_MANIFEST, and SCWORKBENCH_PYBENCH_PYTHON"))

.wb_phase2c_pybench_commit <-
  "3e02ea266862adc3ffa96c5d0d99e817f1e43e06"

.wb_phase2c_shared_sha256 <- c(
  "e4ca57a6a40d87a62865aae43597646f5b6a3f5ca15dec65b89d163033acd8ec",
  "700665a2ba03a69c6df75f9640bf09b9be86b443c61060ffdf0381dcc24bcae5",
  "3e9f07c342fa929806e3747f36ef59f43838921b98907cf5d4ceeede1a1f0a15",
  "36f5f5c73b561420477a9f46c6a0fcad7e2121d85349859ceb3310db8342b52e"
)

.wb_phase2c_assert_pin <- function(root, expected = .wb_phase2c_pybench_commit) {
  observed <- system2("git", c("-C", root, "rev-parse", "HEAD"),
    stdout = TRUE)
  if (length(observed) != 1L || !identical(observed[[1]], expected)) {
    stop(sprintf("Pinned PyBench mismatch: expected %s, observed %s.",
      expected, paste(observed, collapse = ",")), call. = FALSE)
  }
  invisible(observed[[1]])
}

.wb_phase2c_assert_shared_protocol <- function(r_root, py_root,
    expected = .wb_phase2c_shared_sha256) {
  shared <- c("operation-pack-v2.schema.json",
    "operation-pack-transition-request-v2.schema.json",
    "operation-pack-transition-receipt-v2.schema.json",
    "fixtures/operation-pack-v2/identities.json")
  stopifnot(length(expected) == length(shared))
  for (i in seq_along(shared)) {
    r_path <- file.path(r_root, shared[[i]])
    p_path <- file.path(py_root, shared[[i]])
    if (!identical(readBin(r_path, "raw", file.info(r_path)$size),
        readBin(p_path, "raw", file.info(p_path)$size)) ||
        !identical(digest::digest(file = r_path, algo = "sha256",
          serialize = FALSE), expected[[i]])) {
      stop(sprintf("Shared protocol mismatch: %s", shared[[i]]),
        call. = FALSE)
    }
  }
  invisible(TRUE)
}

.wb_phase2c_registry_guard <- function() {
  registry <- getFromNamespace(".wb_operation_pack_registry", "scworkbench")
  list(registry = registry, packs = registry$packs, operations = registry$operations)
}

.wb_phase2c_registry_restore <- function(guard) {
  guard$registry$packs <- guard$packs
  guard$registry$operations <- guard$operations
  invisible(TRUE)
}

.wb_phase2c_inputs <- function(provider = "packaging") {
  make <- function(kind, ...) structure(c(list(kind = kind), list(...)),
    class = "wb_primitive")
  list(
    matrix = make("matrix", values = matrix(1, 1, 1), dimensions = c(1L, 1L),
      cell_id = "cell_1", feature_id = "feature_1",
      storage_profile = "matrix_ordinary_v1",
      meta = list(genome_provider = provider)),
    space = make("space", values = matrix(1, 1, 1), dimensions = c(1L, 1L),
      cell_id = "cell_1", storage_profile = "space_dense_v1"),
    space_2d = make("space_2d", values = matrix(c(0, 1), 1, 2),
      dimensions = c(1L, 2L), cell_id = "cell_1",
      storage_profile = "space_2d_dense_v1"),
    model_ref = make("model_ref", engine = "synthetic", model_space_id = "space",
      in_space_id = "matrix", payload_tree = list(`model.txt` = "input")),
    cell_vector = wb_prim_cell_vector(stats::setNames("a", "cell_1")),
    cell_vector_family = wb_prim_cell_vector_family("k", "cell_1", 1),
    relation_family = wb_prim_relation_family("k", "cell_1", value = 1),
    feature_table = wb_prim_feature_table(data.frame(feature_id = "feature_1")),
    obs_table = wb_prim_obs_table(data.frame(value = 1)),
    path_2d_family = wb_prim_path_2d_family("p", 1L, 0, 1),
    space_path_family = wb_prim_space_path_family("space", "p", 1L, 1L, 0))
}

.wb_phase2c_tree_identity <- function(root) {
  files <- sort(list.files(root, recursive = TRUE, all.files = TRUE,
    full.names = TRUE, include.dirs = FALSE, no.. = TRUE), method = "radix")
  rel <- substring(files, nchar(normalizePath(root, winslash = "/")) + 2L)
  rows <- lapply(seq_along(files), function(i) list(path = rel[[i]],
    size = as.numeric(file.info(files[[i]])$size),
    sha256 = digest::digest(file = files[[i]], algo = "sha256", serialize = FALSE)))
  digest::digest(scworkbench:::.wb_operation_pack_canonical_json(rows),
    algo = "sha256", serialize = FALSE)
}

.wb_phase2c_expect <- function(expr, code, phase = NULL) {
  error <- tryCatch(force(expr), error = identity)
  if (!inherits(error, "wb_operation_pack_error") ||
      !identical(as.character(error$code), code)) {
    stop(sprintf("expected %s, observed %s: %s", code,
      as.character(error$code %||% class(error)[[1]]), conditionMessage(error)),
      call. = FALSE)
  }
  stopifnot(inherits(error, "wb_operation_pack_error"),
    identical(as.character(error$code), code))
  if (!is.null(phase)) stopifnot(identical(as.character(error$phase), phase))
  invisible(error)
}

.wb_phase2c_install_r_fixtures <- function() {
  lib <- tempfile("scwb_phase2c_r_lib_")
  dir.create(lib, recursive = TRUE)
  old <- .libPaths(); .libPaths(c(lib, old))
  for (path in c("tests/fixtures/operation-pack-second",
      "tests/fixtures/operation-pack-v2-reference")) {
    log <- tempfile(fileext = ".log")
    status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
      paste0("--library=", shQuote(lib)), shQuote(normalizePath(path))),
      stdout = log, stderr = log)
    if (!identical(status, 0L)) stop(paste(readLines(log), collapse = "\n"))
  }
  list(lib = lib, old = old,
    v1 = system.file("scworkbench", "operation-pack.json",
      package = "scworkbenchOperationPackFixture", lib.loc = lib),
    v2 = system.file("scworkbench", "operation-pack.json",
      package = "scwbV2Reference", lib.loc = lib))
}

.wb_phase2c_cleanup_r_fixtures <- function(x) {
  for (package in c("scworkbenchOperationPackFixture", "scwbV2Reference")) {
    if (package %in% loadedNamespaces()) try(unloadNamespace(package), silent = TRUE)
  }
  .libPaths(x$old)
  unlink(x$lib, recursive = TRUE, force = TRUE)
  invisible(TRUE)
}

test_operation_pack_v2_composite_protocol_contract <- function() {
  context <- .wb_phase2c_context(); if (is.null(context)) return(.wb_phase2c_skip())
  revision <- .wb_phase2c_assert_pin(context$root)
  .wb_phase2c_assert_shared_protocol(file.path("inst", "protocol"),
    file.path(context$root, "protocol"))
  wrong_pin <- try(.wb_phase2c_assert_pin(context$root, strrep("0", 40L)),
    silent = TRUE)
  wrong_protocol <- .wb_phase2c_shared_sha256
  wrong_protocol[[1]] <- strrep("0", 64L)
  wrong_bytes <- try(.wb_phase2c_assert_shared_protocol(
    file.path("inst", "protocol"), file.path(context$root, "protocol"),
    wrong_protocol), silent = TRUE)
  stopifnot(inherits(wrong_pin, "try-error"),
    inherits(wrong_bytes, "try-error"))
  sidecar <- file.path("inst", "protocol",
    "pybench-op-v3-python-runtime.schema.json")
  python_sidecar <- file.path(context$root, "protocol",
    "pybench-op-v3-python-runtime.schema.json")
  stopifnot(identical(digest::digest(file = sidecar, algo = "sha256",
    serialize = FALSE),
    "59fbaf6456d010bf777323e113ea0e36f94c5b41e75657148ae8cd0aeb9b0b7d"),
    identical(file.info(sidecar)$size, file.info(python_sidecar)$size),
    identical(readBin(sidecar, "raw", file.info(sidecar)$size),
      readBin(python_sidecar, "raw", file.info(python_sidecar)$size)),
    identical(revision, .wb_phase2c_pybench_commit),
    identical(read.dcf("inst/release/composite_release.dcf")[[1,
      "PyBenchCommit"]], "11232d000ee42aa1344c9d6fb25a73acb1d88fe2"))
  TRUE
}

.wb_phase2c_chunk_matrix <- function() {
  cells <- paste0("c", seq_len(4L)); features <- paste0("g", seq_len(5L))
  values <- matrix(seq_len(20L), nrow = 5L,
    dimnames = list(features, cells))
  structure(list(kind = "matrix", values = values,
    dimensions = as.integer(dim(values)), cell_id = cells,
    feature_id = features, storage_profile = "matrix_ordinary_v1",
    meta = list()), class = "wb_primitive")
}

.wb_phase2c_all_params <- function() list(features = list("feature_1"),
  chunk_size = 64L, p_adjust_method = "BH")

test_operation_pack_v2_python_chunk_observation_contract <- function() {
  context <- .wb_phase2c_context(); if (is.null(context)) return(.wb_phase2c_skip())
  guard <- .wb_phase2c_registry_guard()
  on.exit(.wb_phase2c_registry_restore(guard), add = TRUE)
  wb_operation_pack_activate(context$manifest, python = context$python)
  root <- tempfile("scwb_phase2c_python_chunk_")
  bundle <- wb_init_bundle(root)
  on.exit({
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    try(wb_close_bundle(bundle), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  matrix <- .wb_phase2c_chunk_matrix()
  wb_define_cells(bundle, matrix$cell_id)
  wb_attach_matrix(bundle, "inline_matrix", matrix$values, feature_type = "gene")
  matrix$matrix_id <- "inline_matrix"
  source <- wb_new_run("synthetic_matrix_source",
    inputs = list(cell_set = "all", parents = character(),
      provenance_refs = list(), user_inputs = list()),
    params = list(), outputs = list(matrix = matrix))
  session <- wb_session_add_run(wb_session_new(), source)
  session_params <- list(features = matrix$feature_id, chunk_size = 2L,
    p_adjust_method = "BH")
  params <- session_params
  params$features <- unname(as.list(params$features))
  result <- wb_session_run_op(session, bundle,
    "scwbpyv2reference::chunk_probe", inputs = c(list(
      matrix = wb_ref_run(source$run_id, "matrix"),
      cell_set = "all", min_cells = 1L), session_params))
  run_chunk <- function() scworkbench:::.wb_operation_pack_v2_execute(bundle,
    "scwbpyv2reference::chunk_probe", list(matrix = matrix), params)
  direct <- run_chunk()
  expected <- list(c("g1", "g2"), c("g3", "g4"), "g5")
  observed <- direct$runtime_sidecar$chunk_observation
  retained <- result$run$params$chunking
  stopifnot(
    identical(result$run$op_name, "scwbpyv2reference::chunk_probe"),
    identical(as.character(observed$observation_identity$scheme),
      "pybench.operation_pack.chunk_observation.v1"),
    identical(lapply(observed$observed_batches, as.character), expected),
    identical(as.integer(unlist(observed$observed_batch_sizes)), c(2L, 2L, 1L)),
    identical(as.integer(observed$observed_call_count), 3L),
    identical(direct$reader_observation$observed_batches, expected),
    identical(retained$observed_batches, expected),
    identical(as.integer(retained$observed_batch_sizes), c(2L, 2L, 1L)),
    identical(as.integer(retained$observed_call_count), 3L),
    identical(as.integer(retained$requested_chunk_size), 2L))

  baseline_db <- scworkbench:::.wb_manifest_registry_snapshot(bundle$con)
  baseline_tree <- .wb_phase2c_tree_identity(root)
  assert_zero_residue <- function() {
    stopifnot(identical(baseline_db,
      scworkbench:::.wb_manifest_registry_snapshot(bundle$con)),
      identical(baseline_tree, .wb_phase2c_tree_identity(root)))
    pending <- scworkbench:::.wb_operation_pack_v2_pending_root(bundle)
    stopifnot(!dir.exists(pending) || !length(list.dirs(pending,
      recursive = FALSE)))
  }
  rehash_runtime <- function(value) {
    value$runtime_identity <- NULL
    value$runtime_identity <- scworkbench:::.wb_operation_pack_v2_identity_scoped(
      "pybench.operation_pack.python_runtime.v3",
      "python runtime sidecar excluding runtime_identity", value)
    value
  }
  rehash_observation <- function(value) {
    value$observation_identity <- NULL
    value$observation_identity <- scworkbench:::.wb_operation_pack_v2_identity_scoped(
      "pybench.operation_pack.chunk_observation.v1",
      "chunk observation excluding observation_identity", value)
    value
  }
  faults <- list(
    missing = function(value) {
      value$chunk_observation <- NULL; rehash_runtime(value)
    },
    schedule = function(value) {
      value$chunk_observation$observed_batches[[1]] <- c("g2", "g1")
      value$chunk_observation <- rehash_observation(value$chunk_observation)
      rehash_runtime(value)
    },
    substitution = function(value) {
      value$chunk_observation <- observed; rehash_runtime(value)
    })
  for (mutate in faults) {
    options(scworkbench.operation_pack_v2_test_hook = local({ change <- mutate
      function(event, stage = NULL, ...) if (identical(event,
          "python_process_completed")) {
        path <- file.path(stage, "python-runtime.json")
        value <- jsonlite::read_json(path, simplifyVector = FALSE)
        scworkbench:::.wb_operation_pack_v2_atomic_json(change(value), path)
      }
    }))
    .wb_phase2c_expect(run_chunk(),
      "OPERATION_PACK_RUNTIME_ATTESTATION_INVALID", "receipt")
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    assert_zero_residue()
  }

  options(scworkbench.operation_pack_v2_test_hook = function(event,
      stage = NULL, ...) if (identical(event, "python_process_completed")) {
    path <- file.path(stage, "python-runtime.json")
    value <- jsonlite::read_json(path, simplifyVector = FALSE)
    value$chunk_observation <- observed
    scworkbench:::.wb_operation_pack_v2_atomic_json(rehash_runtime(value), path)
  })
  .wb_phase2c_expect(scworkbench:::.wb_operation_pack_v2_execute(bundle,
    "scwbpyv2reference::dynamic_provider", .wb_phase2c_inputs()["matrix"],
    list()),
    "OPERATION_PACK_RUNTIME_ATTESTATION_INVALID", "receipt")
  options(scworkbench.operation_pack_v2_test_hook = NULL)
  assert_zero_residue()
  TRUE
}

test_operation_pack_v2_python_activation_contract <- function() {
  context <- .wb_phase2c_context(); if (is.null(context)) return(.wb_phase2c_skip())
  guard <- .wb_phase2c_registry_guard()
  on.exit(.wb_phase2c_registry_restore(guard), add = TRUE)
  before <- list(packs = wb_operation_packs(), ops = wb_list_ops(),
    identity = wb_operation_catalog_identity())
  conformance <- wb_operation_pack_manifest_validate(context$manifest)
  stopifnot(isTRUE(conformance$ok), !isTRUE(conformance$activated),
    identical(conformance$backend, "Python"), length(wb_list_ops()) == 39L)
  manifest <- scworkbench:::.wb_operation_pack_v2_normalize(
    scworkbench:::.wb_operation_pack_v2_read_manifest(context$manifest))
  inert <- scworkbench:::.wb_operation_pack_v2_python_discover(context$manifest,
    manifest, context$python, 30, activate = FALSE)
  stopifnot(identical(inert$identity$backend, "Python"),
    identical(wb_operation_packs(), before$packs))
  for (boundary in c("catalog_before_pack", "catalog_pack_installed",
      "catalog_operation_installed", "catalog_before_commit")) {
    fired <- FALSE
    options(scworkbench.operation_pack_v2_test_hook = function(event, ...) {
      if (!fired && identical(event, boundary)) {
        fired <<- TRUE; stop(paste0("injected ", boundary))
      }
    })
    .wb_phase2c_expect(wb_operation_pack_activate(context$manifest,
      python = context$python), "OPERATION_PACK_CATALOG_PUBLICATION_FAILED",
      "catalog_publication")
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    stopifnot(fired, identical(wb_operation_packs(), before$packs),
      identical(wb_list_ops(), before$ops),
      identical(wb_operation_catalog_identity(), before$identity))
  }
  .wb_phase2c_expect(wb_operation_pack_activate(context$manifest,
    python = file.path(tempdir(), "absent-phase2c-python")),
    "OPERATION_PACK_RUNTIME_UNAVAILABLE")
  stopifnot(identical(wb_operation_packs(), before$packs),
    identical(wb_list_ops(), before$ops),
    identical(wb_operation_catalog_identity(), before$identity))
  activated <- wb_operation_pack_activate(context$manifest, python = context$python)
  stopifnot(identical(activated$identity$backend, "Python"),
    length(wb_list_ops()) == 45L)
  TRUE
}

test_operation_pack_v2_python_coexistence_and_order_contract <- function() {
  context <- .wb_phase2c_context(); if (is.null(context)) return(.wb_phase2c_skip())
  guard <- .wb_phase2c_registry_guard()
  on.exit(.wb_phase2c_registry_restore(guard), add = TRUE)
  fixtures <- .wb_phase2c_install_r_fixtures()
  on.exit(.wb_phase2c_cleanup_r_fixtures(fixtures), add = TRUE)
  activate_order <- function(order) {
    for (item in order) switch(item,
      r1 = wb_operation_pack_activate(fixtures$v1, lib.loc = fixtures$lib),
      r2 = wb_operation_pack_activate(fixtures$v2, lib.loc = fixtures$lib),
      py2 = wb_operation_pack_activate(context$manifest, python = context$python))
    identity <- wb_operation_catalog_identity()
    stopifnot(nrow(wb_operation_packs()) == 3L,
      setequal(wb_operation_packs()$backend, c("R", "Python")))
    for (pack in rev(wb_operation_packs()$namespace)) wb_operation_pack_unload(pack)
    identity
  }
  first <- activate_order(c("r1", "r2", "py2"))
  second <- activate_order(c("py2", "r2", "r1"))
  stopifnot(identical(first, second), length(wb_list_ops()) == 39L)
  TRUE
}

test_operation_pack_v2_python_durable_lifecycle_contract <- function() {
  context <- .wb_phase2c_context(); if (is.null(context)) return(.wb_phase2c_skip())
  guard <- .wb_phase2c_registry_guard()
  on.exit(.wb_phase2c_registry_restore(guard), add = TRUE)
  activated <- wb_operation_pack_activate(context$manifest, python = context$python)
  root <- tempfile("scwb_phase2c_python_bundle_")
  bundle <- wb_init_bundle(root)
  result <- scworkbench:::.wb_operation_pack_v2_execute(bundle,
    "scwbpyv2reference::all_contracts", .wb_phase2c_inputs(),
    .wb_phase2c_all_params(),
    session_id = "phase2c_session", run_id = "phase2c_run",
    checkpoint_generation = "generation_1")
  stopifnot(identical(result$state, "reopened"),
    length(result$outputs) == 14L, length(result$registry_requests) == 1L,
    nrow(wb_operation_pack_transition_outputs(bundle, result$transition_id)) == 15L,
    identical(result$receipt$runtime_attestation$backend, "Python"),
    identical(result$runtime_sidecar$backend, "Python"))
  identities <- list(pack = activated$identity$pack_identity,
    definition = activated$identity$operation_definition_identities[[
      "scwbpyv2reference::all_contracts"]],
    transition = result$request$transition$transition_identity,
    request = result$request$request_identity,
    capability = result$request$execution_capability$capability_identity,
    receipt = result$receipt$receipt_identity,
    runtime_sidecar = result$runtime_sidecar$runtime_identity,
    mutation = result$receipt$mutation_manifest$mutation_identity)
  stopifnot(all(vapply(identities, function(x)
    grepl("^[0-9a-f]{64}$", x$sha256), logical(1))))
  wb_finalize_recipient_bundle(bundle)
  wb_close_bundle(bundle)
  before <- .wb_phase2c_tree_identity(root)
  repo <- normalizePath(".", winslash = "/")
  expression <- paste0(
    "args<-commandArgs(TRUE);devtools::load_all(args[1],quiet=TRUE);",
    "stopifnot(nrow(wb_operation_packs())==0L,length(wb_list_ops())==39L,",
    "isTRUE(wb_validate_bundle(args[2],read_only=TRUE)));",
    "b<-wb_open_bundle(args[2],read_only=TRUE);",
    "x<-wb_operation_pack_transition_outputs(b,args[3]);stopifnot(nrow(x)==15L);",
    "for(n in x$name){v<-wb_operation_pack_transition_load(b,args[3],n);stopifnot(!is.null(v))};",
    "wb_close_bundle(b);cat('recipient_ok outputs=15 pack_active=0\\n')")
  reopened <- processx::run(file.path(R.home("bin"), "Rscript"),
    c("--vanilla", "-e", expression, repo, root, result$transition_id),
    echo = FALSE, error_on_status = FALSE, timeout = 120)
  if (reopened$status != 0L) stop(paste(reopened$stdout, reopened$stderr,
    collapse = "\n"), call. = FALSE)
  stopifnot(reopened$status == 0L,
    grepl("recipient_ok outputs=15 pack_active=0", reopened$stdout, fixed = TRUE),
    identical(before, .wb_phase2c_tree_identity(root)))
  .wb_phase2c_expect(scworkbench:::.wb_operation_pack_v2_python_dispatch(
    result$request, guard$registry$packs[["scwbpyv2reference"]]$registration %||%
      guard$registry$packs[[1]]$registration, result$path),
    "PYBENCH_STALE_STAGING_IDENTITY")
  unlink(root, recursive = TRUE, force = TRUE)
  TRUE
}

test_operation_pack_v2_python_dynamic_dependency_contract <- function() {
  context <- .wb_phase2c_context(); if (is.null(context)) return(.wb_phase2c_skip())
  guard <- .wb_phase2c_registry_guard()
  on.exit(.wb_phase2c_registry_restore(guard), add = TRUE)
  wb_operation_pack_activate(context$manifest, python = context$python)
  root <- tempfile("scwb_phase2c_dynamic_"); bundle <- wb_init_bundle(root)
  result <- scworkbench:::.wb_operation_pack_v2_execute(bundle,
    "scwbpyv2reference::dynamic_provider", .wb_phase2c_inputs("packaging")["matrix"],
    list())
  dynamic <- result$request$dependency_resolution$dynamic_resolutions
  stopifnot(length(dynamic) == 1L,
    identical(dynamic[[1]]$provider_name, "packaging"),
    identical(dynamic[[1]]$ecosystem, "Python"),
    identical(scworkbench:::.wb_operation_pack_canonical_json(
      result$receipt$runtime_attestation$dynamic_resolutions),
      scworkbench:::.wb_operation_pack_canonical_json(dynamic)))
  wb_close_bundle(bundle); unlink(root, recursive = TRUE, force = TRUE)
  TRUE
}

test_operation_pack_v2_python_failure_conformance_contract <- function() {
  context <- .wb_phase2c_context(); if (is.null(context)) return(.wb_phase2c_skip())
  guard <- .wb_phase2c_registry_guard()
  on.exit(.wb_phase2c_registry_restore(guard), add = TRUE)
  wb_operation_pack_activate(context$manifest, python = context$python)
  registration <- guard$registry$packs[["scwbpyv2reference"]]$registration
  root <- tempfile("scwb_phase2c_failure_"); bundle <- wb_init_bundle(root)
  on.exit({ try(wb_close_bundle(bundle), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
    options(scworkbench.operation_pack_v2_test_hook = NULL) }, add = TRUE)
  baseline_db <- scworkbench:::.wb_manifest_registry_snapshot(bundle$con)
  assert_residue <- function() {
    stopifnot(identical(baseline_db,
      scworkbench:::.wb_manifest_registry_snapshot(bundle$con)))
    pending <- scworkbench:::.wb_operation_pack_v2_pending_root(bundle)
    stopifnot(!dir.exists(pending) || !length(list.dirs(pending,
      recursive = FALSE)))
  }
  run <- function(inputs = .wb_phase2c_inputs(), op =
      "scwbpyv2reference::all_contracts", params = .wb_phase2c_all_params()) {
    scworkbench:::.wb_operation_pack_v2_execute(bundle, op, inputs, params)
  }
  options(scworkbench.operation_pack_v2_test_hook = function(event,
      transition_id = NULL, ...) {
    if (identical(event, "staged")) {
      path <- file.path(scworkbench:::.wb_operation_pack_v2_pending_root(bundle),
        transition_id, "request.json")
      value <- jsonlite::read_json(path, simplifyVector = FALSE)
      value$process_protocol_version <- "pybench-op-v2"
      value$request_identity <- NULL
      value$request_identity <- scworkbench:::.wb_operation_pack_v2_identity_scoped(
        "scworkbench.operation_pack.transition_request.v2",
        "request excluding request_identity", value)
      scworkbench:::.wb_operation_pack_v2_atomic_json(value, path)
    }
  })
  .wb_phase2c_expect(run(), "PYBENCH_PROCESS_FAILED", "staging")
  options(scworkbench.operation_pack_v2_test_hook = NULL); assert_residue()

  options(scworkbench.operation_pack_v2_test_hook = function(event,
      transition_id = NULL, ...) {
    if (identical(event, "before_dispatch")) {
      path <- file.path(scworkbench:::.wb_operation_pack_v2_pending_root(bundle),
        transition_id, "inputs", "matrix", "payload.json")
      value <- jsonlite::read_json(path, simplifyVector = FALSE)
      value$values <- list(list(999))
      scworkbench:::.wb_operation_pack_v2_atomic_json(value, path)
    }
  })
  .wb_phase2c_expect(run(), "PYBENCH_INPUT_IDENTITY_MISMATCH", "resolution")
  options(scworkbench.operation_pack_v2_test_hook = NULL); assert_residue()

  post_process_faults <- list(
    malformed_receipt = list(code = "PYBENCH_RECEIPT_MISMATCH",
      mutate = function(stage) writeLines("{", file.path(stage, "receipt.json"),
        useBytes = TRUE)),
    invalid_runtime_sidecar = list(
      code = "OPERATION_PACK_RUNTIME_ATTESTATION_INVALID",
      mutate = function(stage) {
        path <- file.path(stage, "python-runtime.json")
        value <- jsonlite::read_json(path, simplifyVector = FALSE)
        value$backend <- "R"; value$runtime_identity <- NULL
        value$runtime_identity <- scworkbench:::.wb_operation_pack_v2_identity_scoped(
          "pybench.operation_pack.python_runtime.v3",
          "python runtime sidecar excluding runtime_identity", value)
        scworkbench:::.wb_operation_pack_v2_atomic_json(value, path)
      }),
    missing_payload = list(code = "PYBENCH_OUTPUT_INVALID",
      mutate = function(stage) unlink(file.path(stage, "outputs", "cell_vector",
        "payload.json"), force = TRUE)),
    undeclared_file = list(code = "PYBENCH_OUT_OF_SCOPE_MUTATION",
      mutate = function(stage) writeLines("undeclared",
        file.path(stage, "undeclared.txt"), useBytes = TRUE))
  )
  for (fault in post_process_faults) {
    options(scworkbench.operation_pack_v2_test_hook = local({ current <- fault
      function(event, stage = NULL, ...) if (identical(event,
          "python_process_completed")) current$mutate(stage) }))
    .wb_phase2c_expect(run(), fault$code)
    options(scworkbench.operation_pack_v2_test_hook = NULL); assert_residue()
  }

  options(scworkbench.operation_pack_v2_test_hook = function(event,
      transition_id = NULL, stage = NULL, ...) {
    if (identical(event, "python_receipt_loaded")) {
      path <- file.path(stage, "outputs", "cell_vector", "payload.json")
      value <- jsonlite::read_json(path, simplifyVector = FALSE)
      value$value <- list("mutated")
      jsonlite::write_json(value, path, auto_unbox = TRUE, null = "null")
    }
  })
  .wb_phase2c_expect(run(), "PYBENCH_OUTPUT_INVALID")
  options(scworkbench.operation_pack_v2_test_hook = NULL); assert_residue()

  for (boundary in c("receipt_received", "before_publication", "published",
      "before_reopened", "reopened")) {
    options(scworkbench.operation_pack_v2_test_hook = local({ target <- boundary
      function(event, ...) if (identical(event, target)) stop(paste("injected", target)) }))
    expected <- if (boundary == "receipt_received") "PYBENCH_RECEIPT_MISMATCH" else
      if (boundary %in% c("before_publication", "published"))
        "PYBENCH_PUBLICATION_FAILED" else "PYBENCH_REOPEN_VALIDATION_FAILED"
    .wb_phase2c_expect(run(), expected)
    options(scworkbench.operation_pack_v2_test_hook = NULL); assert_residue()
  }
  wrapper <- tempfile("phase2c_python_death_")
  writeLines(c("#!/bin/sh",
    "case \"$*\" in *pybench.operation_pack_v3_cli*) kill -9 $$ ;; esac",
    paste("exec", shQuote(context$python), '"$@"')), wrapper)
  Sys.chmod(wrapper, mode = "0755")
  live <- guard$registry$packs[["scwbpyv2reference"]]
  live$registration$runtime_config$python <- wrapper
  guard$registry$packs[["scwbpyv2reference"]] <- live
  .wb_phase2c_expect(run(), "PYBENCH_PROCESS_FAILED")
  assert_residue()
  TRUE
}

test_operation_pack_v2_r_python_logical_equivalence_contract <- function() {
  context <- .wb_phase2c_context(); if (is.null(context)) return(.wb_phase2c_skip())
  guard <- .wb_phase2c_registry_guard()
  on.exit(.wb_phase2c_registry_restore(guard), add = TRUE)
  fixtures <- .wb_phase2c_install_r_fixtures()
  on.exit(.wb_phase2c_cleanup_r_fixtures(fixtures), add = TRUE)
  wb_operation_pack_activate(fixtures$v2, lib.loc = fixtures$lib)
  wb_operation_pack_activate(context$manifest, python = context$python)
  r_root <- tempfile("phase2c_r_"); py_root <- tempfile("phase2c_py_")
  r_bundle <- wb_init_bundle(r_root); py_bundle <- wb_init_bundle(py_root)
  r <- scworkbench:::.wb_operation_pack_v2_execute(r_bundle,
    "scwbv2reference::all_contracts", .wb_phase2c_inputs("stats"), list())
  py <- scworkbench:::.wb_operation_pack_v2_execute(py_bundle,
    "scwbpyv2reference::all_contracts", .wb_phase2c_inputs(),
    .wb_phase2c_all_params())
  r_inventory <- wb_operation_pack_transition_outputs(r_bundle, r$transition_id)
  py_inventory <- wb_operation_pack_transition_outputs(py_bundle, py$transition_id)
  columns <- c("name", "category", "kind", "storage_profile")
  # The R conformance operation also carries its local family fixture; Python
  # exposes the equivalent contract through family_probe. Preserve the exact
  # pre-amendment all_contracts comparison and qualify the family separately.
  r_shared <- r_inventory[r_inventory$name != "cell_set_family", , drop = FALSE]
  stopifnot(identical(r_shared[, columns], py_inventory[, columns]),
    identical(r_inventory$name[r_inventory$name == "cell_set_family"],
      "cell_set_family"),
    identical(r$outputs$cell_vector$value, py$outputs$cell_vector$value),
    identical(r$outputs$path_2d$key, py$outputs$path_2d$key),
    !identical(r$receipt$receipt_identity$sha256,
      py$receipt$receipt_identity$sha256),
    identical(r$receipt$runtime_attestation$backend, "R"),
    identical(py$receipt$runtime_attestation$backend, "Python"))
  wb_close_bundle(r_bundle); wb_close_bundle(py_bundle)
  unlink(r_root, recursive = TRUE, force = TRUE)
  unlink(py_root, recursive = TRUE, force = TRUE)
  TRUE
}

.wb_phase2c_family_fixture <- function() {
  jsonlite::read_json(file.path("inst", "protocol", "fixtures",
    "operation-pack-v2", "identities.json"), simplifyVector = FALSE)$
    cell_set_family_examples[[1]]
}

.wb_phase2c_family_bundle <- function(label) {
  root <- tempfile(paste0("scwb_phase2c_family_", label, "_"))
  bundle <- wb_init_bundle(root)
  cells <- c("cell_c", "cell_a", "cell_b", "cell_d")
  features <- c("feature_1", "feature_2")
  values <- matrix(seq_len(8L), nrow = 2L,
    dimnames = list(features, cells))
  wb_define_cells(bundle, cells)
  wb_attach_matrix(bundle, "family_input", values, feature_type = "gene")
  matrix <- structure(list(
    kind = "matrix", values = values,
    dimensions = as.integer(dim(values)), cell_id = cells,
    feature_id = features, storage_profile = "matrix_ordinary_v1",
    matrix_id = "family_input", meta = list(fixture = "family")),
    class = "wb_primitive")
  normalized <- wb_session_run_op(wb_session_new(), bundle,
    "matrix_log_normalize", inputs = list(
      matrix = "family_input", cell_set = "all", min_cells = 1L,
      output_matrix_id = "family_normalized", scale_factor = 10000,
      overwrite = TRUE))
  list(root = root, bundle = bundle, cells = cells, matrix = matrix,
    source = normalized$run, session = normalized$session)
}

.wb_phase2c_family_run <- function(setup, payload) {
  wb_session_run_op(setup$session, setup$bundle,
    "scwbpyv2reference::family_probe", inputs = list(
      matrix = wb_ref_run(setup$source$run_id, "matrix"),
      family = payload, cell_set = "all", min_cells = 1L))
}

.wb_phase2c_family_state <- function(bundle) {
  list(
    fingerprint = scworkbench:::.wb_session_source_identity(bundle)$
      scientific_state_fingerprint,
    registry = scworkbench:::.wb_manifest_registry_snapshot(bundle$con),
    receipts = wb_operation_pack_registry_receipts(bundle),
    artifacts = wb_art_list(bundle, include_history = TRUE),
    sets = wb_cell_sets(bundle)
  )
}

test_operation_pack_v2_python_cell_set_family_lifecycle_contract <- function() {
  context <- .wb_phase2c_context(); if (is.null(context)) return(.wb_phase2c_skip())
  guard <- .wb_phase2c_registry_guard()
  on.exit(.wb_phase2c_registry_restore(guard), add = TRUE)
  wb_operation_pack_activate(context$manifest, python = context$python)
  fixture <- .wb_phase2c_family_fixture()
  for (count in 0:2) {
    setup <- .wb_phase2c_family_bundle(paste0("lifecycle_", count))
    bundle <- setup$bundle
    payload <- fixture$input_payload
    payload$sets <- payload$sets[seq_len(count)]
    wb_close_bundle(bundle)
    clone_parent <- tempfile("scwb_phase2c_family_replay_")
    dir.create(clone_parent)
    stopifnot(isTRUE(file.copy(setup$root, clone_parent, recursive = TRUE)))
    clone <- file.path(clone_parent, basename(setup$root))
    bundle <- wb_open_bundle(setup$root)
    setup$bundle <- bundle
    baseline <- .wb_phase2c_family_state(bundle)
    result <- .wb_phase2c_family_run(setup, payload)
    stopifnot(identical(.wb_phase2c_family_state(bundle), baseline),
      length(result$run$operation_pack_registry_requests) == 1L)
    staged <- result$run$operation_pack_registry_requests[[1]]
    expected <- scworkbench:::.wb_operation_pack_cell_set_family_normalize(
      bundle, payload)
    stopifnot(
      identical(staged$family_identity$sha256,
        attr(expected, "family_identity")$sha256),
      identical(staged$family$sets, expected$sets))
    receipt_item <- result$run$operation_pack_registry_requests[[1]]
    transition <- wb_operation_pack_transition_load(
      result$session$staging_bundle,
      receipt_item$transition_id, "family")
    stopifnot(identical(
      scworkbench:::.wb_operation_pack_canonical_json(transition$sets),
      scworkbench:::.wb_operation_pack_canonical_json(expected$sets)))

    promotion <- wb_session_promote_current(bundle, result$session,
      outputs = "summary", created_by = "phase2c_composite")
    receipt <- wb_operation_pack_registry_receipts(bundle)
    expected_names <- vapply(expected$sets, `[[`, character(1), "name")
    stopifnot(nrow(receipt) == 1L, receipt$n_sets[[1]] == count,
      identical(receipt$family_sha256[[1]],
        attr(expected, "family_identity")$sha256),
      all(expected_names %in% wb_cell_sets(bundle)),
      any(promotion$promoted$output == "summary"))
    for (set in expected$sets) {
      stopifnot(identical(wb_cells(bundle, set$name), set$cells))
    }

    if (count == 2L) {
      descriptor <- result$run$operation_pack_registry_requests[[1]]
      stopifnot(
        identical(descriptor$family_identity, fixture$family_identity),
        identical(attr(expected, "member_identities"),
          fixture$member_identities),
        identical(attr(expected, "source_identity"),
          fixture$source_identity))
      artifact_id <- as.character(promotion$promoted$artifact_id[
        promotion$promoted$output == "summary"][[1]])
      plan <- wb_target_reproduction_plan(bundle,
        paste0("artifact:", artifact_id))
      stopifnot(nrow(plan$registry_requests) == 1L,
        identical(plan$registry_requests$family_sha256[[1]],
          receipt$family_sha256[[1]]))
      replay <- wb_target_execute_plan(plan, clone)
      stopifnot(identical(replay$status, "promoted_and_verified"))
      replayed <- wb_open_bundle(clone, read_only = TRUE)
      stopifnot(nrow(wb_operation_pack_registry_receipts(replayed)) == 1L)
      for (set in expected$sets) {
        stopifnot(identical(wb_cells(replayed, set$name), set$cells))
      }
      wb_close_bundle(replayed)

      wb_finalize_recipient_bundle(bundle)
      wb_close_bundle(bundle)
      before <- .wb_phase2c_tree_identity(setup$root)
      repo <- normalizePath(".", winslash = "/")
      expression <- paste0(
        "a<-commandArgs(TRUE);devtools::load_all(a[1],quiet=TRUE);",
        "stopifnot(nrow(wb_operation_packs())==0L);",
        "b<-wb_open_bundle(a[2],read_only=TRUE);",
        "x<-wb_operation_pack_registry_receipts(b);",
        "r<-wb_bundle_validation_report(a[2],level='recipient');",
        "stopifnot(isTRUE(r$ok),nrow(x)==1L,",
        "identical(x$family_sha256[[1]],a[3]));",
        "wb_close_bundle(b);cat('pack_free_family_recipient_ok\\n')")
      recipient <- processx::run(file.path(R.home("bin"), "Rscript"),
        c("--vanilla", "-e", expression, repo, setup$root,
          fixture$family_identity$sha256),
        echo = FALSE, error_on_status = FALSE, timeout = 180)
      if (recipient$status != 0L) stop(paste(recipient$stdout,
        recipient$stderr, collapse = "\n"), call. = FALSE)
      stopifnot(grepl("pack_free_family_recipient_ok", recipient$stdout,
        fixed = TRUE))
      stopifnot(identical(before, .wb_phase2c_tree_identity(setup$root)))
      bundle <- NULL
    }
    if (!is.null(bundle)) wb_close_bundle(bundle)
    unlink(c(setup$root, clone_parent), recursive = TRUE, force = TRUE)
  }
  TRUE
}

test_operation_pack_v2_python_cell_set_family_failure_contract <- function() {
  context <- .wb_phase2c_context(); if (is.null(context)) return(.wb_phase2c_skip())
  guard <- .wb_phase2c_registry_guard()
  on.exit(.wb_phase2c_registry_restore(guard), add = TRUE)
  wb_operation_pack_activate(context$manifest, python = context$python)
  fixture <- .wb_phase2c_family_fixture()

  variants <- list(
    duplicate_member = within(fixture$input_payload,
      sets[[1]]$cells <- rep(sets[[1]]$cells[[1]], 2L)),
    foreign_member = within(fixture$input_payload,
      sets[[1]]$cells <- "foreign_cell"),
    invalid_name = within(fixture$input_payload,
      sets[[1]]$name <- "bad/name"),
    source_mismatch = within(fixture$input_payload, {
      source$input_run_id <- "run_x"
      source$input_snapshot_id <- NULL
    })
  )
  for (name in names(variants)) {
    setup <- .wb_phase2c_family_bundle(paste0("invalid_", name))
    before <- .wb_phase2c_family_state(setup$bundle)
    error <- try(.wb_phase2c_family_run(setup, variants[[name]]), silent = TRUE)
    stopifnot(inherits(error, "try-error"),
      identical(.wb_phase2c_family_state(setup$bundle), before))
    pending <- scworkbench:::.wb_operation_pack_v2_pending_root(setup$bundle)
    stopifnot(!dir.exists(pending) || !length(list.dirs(pending,
      recursive = FALSE)))
    wb_close_bundle(setup$bundle)
    unlink(setup$root, recursive = TRUE, force = TRUE)
  }

  faults <- c("projected_order", "payload_identity", "receipt_identity",
    "duplicate_receipt")
  for (fault in faults) {
    setup <- .wb_phase2c_family_bundle(paste0("tamper_", fault))
    before <- .wb_phase2c_family_state(setup$bundle)
    options(scworkbench.operation_pack_v2_test_hook = local({ target <- fault
      function(event, stage = NULL, transition_id = NULL, ...) {
        if (identical(target, "projected_order") &&
            identical(event, "before_dispatch")) {
          path <- file.path(
            scworkbench:::.wb_operation_pack_v2_pending_root(setup$bundle),
            transition_id, "inputs", "matrix", "payload.json")
          value <- jsonlite::read_json(path, simplifyVector = FALSE)
          value$cell_id <- rev(value$cell_id)
          scworkbench:::.wb_operation_pack_v2_atomic_json(value, path)
        }
        if (!identical(event, "python_process_completed")) return(invisible())
        if (identical(target, "payload_identity")) {
          path <- file.path(stage, "registry_requests", "family",
            "payload.json")
          value <- jsonlite::read_json(path, simplifyVector = FALSE)
          value$sets[[1]]$cells <- rev(value$sets[[1]]$cells)
          scworkbench:::.wb_operation_pack_v2_atomic_json(value, path)
        } else if (target %in% c("receipt_identity", "duplicate_receipt")) {
          path <- file.path(stage, "receipt.json")
          value <- jsonlite::read_json(path, simplifyVector = FALSE)
          if (identical(target, "receipt_identity")) {
            value$registry_requests[[1]]$descriptor$family_identity$sha256 <-
              strrep("0", 64L)
          } else {
            value$registry_requests[[2]] <- value$registry_requests[[1]]
          }
          scworkbench:::.wb_operation_pack_v2_atomic_json(value, path)
        }
      }
    }))
    error <- try(if (identical(fault, "projected_order")) {
      scworkbench:::.wb_operation_pack_v2_execute(
        setup$bundle, "scwbpyv2reference::family_probe",
        list(matrix = setup$matrix),
        list(family = fixture$input_payload))
    } else {
      .wb_phase2c_family_run(setup, fixture$input_payload)
    }, silent = TRUE)
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    stopifnot(inherits(error, "try-error"),
      identical(.wb_phase2c_family_state(setup$bundle), before))
    wb_close_bundle(setup$bundle)
    unlink(setup$root, recursive = TRUE, force = TRUE)
  }

  setup <- .wb_phase2c_family_bundle("promotion_fault")
  result <- .wb_phase2c_family_run(setup, fixture$input_payload)
  before <- .wb_phase2c_family_state(setup$bundle)
  fired <- FALSE
  options(scworkbench.operation_pack_registry_test_hook = function(event,
      member_index = NULL, ...) {
    if (!fired && identical(event, "between_family_member_writes") &&
        identical(as.integer(member_index), 1L)) {
      fired <<- TRUE
      stop("injected family member publication fault")
    }
  })
  error <- try(wb_session_promote_current(setup$bundle, result$session,
    outputs = "summary"), silent = TRUE)
  options(scworkbench.operation_pack_registry_test_hook = NULL)
  if (!fired) {
    condition <- attr(error, "condition")
    stop("Promotion fault hook was not reached: ",
      if (inherits(condition, "condition")) conditionMessage(condition) else
        as.character(error), call. = FALSE)
  }
  stopifnot(inherits(error, "try-error"), fired,
    identical(.wb_phase2c_family_state(setup$bundle), before))
  retry <- wb_session_promote_current(setup$bundle, result$session,
    outputs = "summary")
  stopifnot(any(retry$promoted$output == "summary"),
    nrow(wb_operation_pack_registry_receipts(setup$bundle)) == 1L)
  wb_close_bundle(setup$bundle)
  unlink(setup$root, recursive = TRUE, force = TRUE)
  TRUE
}

test_operation_pack_v2_python_legacy_cell_set_acceptance_contract <- function() {
  context <- .wb_phase2c_context(); if (is.null(context)) return(.wb_phase2c_skip())
  guard <- .wb_phase2c_registry_guard()
  on.exit(.wb_phase2c_registry_restore(guard), add = TRUE)
  wb_operation_pack_activate(context$manifest, python = context$python)
  root <- tempfile("scwb_phase2c_legacy_cell_set_")
  bundle <- wb_init_bundle(root)
  wb_define_cells(bundle, "cell_1")
  before <- .wb_phase2c_family_state(bundle)
  result <- .wb_operation_pack_v2_execute(
    bundle = bundle,
    op_name = "scwbpyv2reference::all_contracts",
    inputs = .wb_phase2c_inputs(),
    params = .wb_phase2c_all_params()
  )
  stopifnot(!"set:v2_cells" %in% wb_cell_sets(bundle),
    nrow(wb_operation_pack_registry_receipts(bundle)) == 0L,
    identical(.wb_phase2c_family_state(bundle), before),
    length(result$registry_requests) == 1L,
    identical(result$registry_requests[[1]]$descriptor$kind,
      "cell_set_admission"),
    identical(result$registry_request_values$cell_set$name,
      "v2_cells"),
    identical(unlist(result$registry_request_values$cell_set$cells,
      use.names = FALSE),
      "cell_1"))
  wb_close_bundle(bundle)
  unlink(root, recursive = TRUE, force = TRUE)
  TRUE
}

.wb_phase2c_registry_fixture <- function(label) {
  root <- tempfile(paste0("scwb_phase2c_registry_", label, "_"))
  bundle <- wb_init_bundle(root, overwrite = TRUE)
  cells <- c("cell_2", "cell_1")
  features <- c("gene_c", "gene_a", "gene_b", "gene_d")
  values <- Matrix::Matrix(matrix(seq_len(8L), nrow = 4L,
    dimnames = list(features, cells)), sparse = TRUE)
  wb_define_cells(bundle, cells)
  wb_attach_matrix(bundle, "RNA_counts", values, feature_type = "gene")
  wb_feature_set_replace(bundle, "SET_B", "RNA_counts",
    c("gene_b", "gene_a"), namespace = "ns_beta", organism = "mouse",
    source_id = "source_beta", source_version = "2", origin = "fixture",
    recipe = list(n_genes_raw = 3L, method = "fixture"), is_readonly = TRUE,
    description = "Beta set", created_by = "composite", strict = TRUE)
  wb_feature_set_replace(bundle, "SET_A", "RNA_counts",
    c("gene_c", "gene_a", "gene_d"), namespace = "ns_alpha",
    organism = "mouse", source_id = "source_alpha", source_version = "1",
    origin = "fixture", recipe = list(n_genes_raw = 4L, method = "fixture"),
    is_readonly = TRUE, description = "Alpha set", created_by = "composite",
    strict = TRUE)
  list(root = root, bundle = bundle, cells = cells, features = features)
}

.wb_phase2c_registry_inputs <- function(fixture) {
  scworkbench:::.wb_operation_pack_v2_bind_inputs(fixture$bundle,
    list(matrix = wb_prim_matrix("RNA_counts")), fixture$cells)
}

.wb_phase2c_registry_params <- function(namespace = NULL,
    namespaces = NULL, selected_sets = NULL) {
  list(namespace = namespace, namespaces = namespaces,
    selected_sets = selected_sets)
}

.wb_phase2c_registry_state <- function(fixture) {
  transition_root <- file.path(fixture$root, "operation_pack_v2")
  transitions <- if (dir.exists(transition_root)) sort(list.dirs(
    transition_root, recursive = FALSE, full.names = FALSE), method = "radix") else
    character()
  list(
    fingerprint = scworkbench:::.wb_session_source_identity(fixture$bundle)$
      scientific_state_fingerprint,
    registry = scworkbench:::.wb_manifest_registry_snapshot(fixture$bundle$con),
    artifacts = wb_art_list(fixture$bundle, include_history = TRUE),
    receipts = wb_operation_pack_registry_receipts(fixture$bundle),
    transitions = transitions)
}

.wb_phase2c_registry_assert_no_residue <- function(fixture, before) {
  stopifnot(identical(.wb_phase2c_registry_state(fixture), before))
  pending <- scworkbench:::.wb_operation_pack_v2_pending_root(fixture$bundle)
  stopifnot(!dir.exists(pending) || !length(list.dirs(pending,
    recursive = FALSE)))
  invisible(TRUE)
}

test_operation_pack_v2_python_feature_set_registry_lifecycle_contract <- function() {
  context <- .wb_phase2c_context(); if (is.null(context)) return(.wb_phase2c_skip())
  guard <- .wb_phase2c_registry_guard()
  on.exit(.wb_phase2c_registry_restore(guard), add = TRUE)
  wb_operation_pack_activate(context$manifest, python = context$python)
  cases <- list(
    zero = .wb_phase2c_registry_params(namespace = "missing"),
    one = .wb_phase2c_registry_params(namespace = "ns_alpha",
      selected_sets = list("SET_A")),
    many = .wb_phase2c_registry_params())
  expected_counts <- c(zero = 0L, one = 1L, many = 2L)
  observed_identity_fields <- c("content_identity", "source_identity",
    "ancestry_identity", "payload_manifest_identity")
  for (name in names(cases)) {
    fixture <- .wb_phase2c_registry_fixture(name)
    result <- scworkbench:::.wb_operation_pack_v2_execute(fixture$bundle,
      "scwbpyv2reference::registry_probe",
      .wb_phase2c_registry_inputs(fixture), cases[[name]])
    request <- result$request$registry_reads[[1]]$descriptor
    observed <- result$receipt$registry_reads[[1]]$descriptor
    matrix_grant <- result$request$inputs[[which(vapply(result$request$inputs,
      `[[`, character(1), "name") == "matrix")]]$descriptor
    published <- wb_operation_pack_transition_registry_reads(fixture$bundle,
      result$transition_id)$feature_sets
    stopifnot(
      identical(result$state, "reopened"),
      identical(as.integer(result$outputs$summary$table$set_count),
        expected_counts[[name]]),
      identical(result$request$transition$transition_identity,
        result$receipt$transition_identity),
      identical(result$request$request_identity,
        result$receipt$request_identity),
      identical(as.integer(observed$use_count), 1L),
      identical(observed$descriptor_identity,
        request$descriptor_identity),
      all(vapply(observed_identity_fields, function(field)
        identical(request[[field]], observed[[field]]), logical(1))),
      identical(published$descriptor, request),
      identical(published$observation, observed),
      identical(published$snapshot$matrix_id, "RNA_counts"),
      identical(request$matrix_id, "RNA_counts"),
      is.null(matrix_grant$matrix_id),
      identical(request$matrix_content_identity,
        matrix_grant$content_identity),
      identical(request$feature_order_identity,
        matrix_grant$feature_order_identity),
      identical(unlist(published$snapshot$feature_universe, use.names = FALSE),
        fixture$features),
      identical(as.integer(result$receipt$mutation_manifest$entry_count), 1L))
    if (identical(name, "one")) {
      set <- published$snapshot$sets[[1]]
      stopifnot(identical(set$feature_set, "SET_A"),
        identical(set$namespace, "ns_alpha"),
        identical(set$source_id, "source_alpha"),
        identical(set$source_version, "1"),
        identical(set$origin, "fixture"),
        identical(set$description, "Alpha set"),
        identical(set$created_by, "composite"),
        identical(vapply(set$memberships, `[[`, character(1), "feature_id"),
          c("gene_c", "gene_a", "gene_d")),
        identical(vapply(set$memberships, function(x) as.integer(x$rank),
          integer(1)), 1:3))
    }
    wb_close_bundle(fixture$bundle)
    unlink(fixture$root, recursive = TRUE, force = TRUE)
  }

  fixture <- .wb_phase2c_registry_fixture("durable")
  on.exit({ try(wb_close_bundle(fixture$bundle), silent = TRUE)
    unlink(fixture$root, recursive = TRUE, force = TRUE) }, add = TRUE)
  run <- wb_session_run_op(wb_session_new(), fixture$bundle,
    "scwbpyv2reference::registry_probe", inputs = list(
      matrix = wb_prim_matrix("RNA_counts"), namespace = NULL,
      namespaces = c("ns_beta", "ns_alpha"), selected_sets = NULL,
      cell_set = "all", min_cells = 1L))
  transition_id <- as.character(
    run$run$operation_pack_transition$transition_id)[1]
  promoted <- wb_session_promote_current(fixture$bundle, run$session,
    outputs = "summary", created_by = "phase2c_registry_composite")
  stopifnot(nrow(promoted$promoted) == 1L)
  wb_finalize_recipient_bundle(fixture$bundle)
  wb_close_bundle(fixture$bundle)
  before <- .wb_phase2c_tree_identity(fixture$root)
  repo <- normalizePath(".", winslash = "/")
  expression <- paste0(
    "a<-commandArgs(TRUE);devtools::load_all(a[1],quiet=TRUE);",
    "stopifnot(nrow(wb_operation_packs())==0L);",
    "b<-wb_open_bundle(a[2],read_only=TRUE);",
    "r<-wb_operation_pack_transition_registry_reads(b,a[3]);",
    "v<-wb_bundle_validation_report(a[2],level='recipient');",
    "stopifnot(isTRUE(v$ok),identical(names(r),'feature_sets'),",
    "length(r$feature_sets$snapshot$sets)==2L,",
    "as.integer(r$feature_sets$observation$use_count)==1L);",
    "wb_close_bundle(b);cat('pack_free_registry_recipient_ok sets=2\\n')")
  recipient <- processx::run(file.path(R.home("bin"), "Rscript"),
    c("--vanilla", "-e", expression, repo, fixture$root, transition_id),
    echo = FALSE, error_on_status = FALSE, timeout = 180)
  if (recipient$status != 0L) stop(paste(recipient$stdout, recipient$stderr,
    collapse = "\n"), call. = FALSE)
  stopifnot(grepl("pack_free_registry_recipient_ok sets=2",
    recipient$stdout, fixed = TRUE),
    identical(before, .wb_phase2c_tree_identity(fixture$root)))
  fixture$bundle <- NULL
  TRUE
}

test_operation_pack_v2_python_feature_set_registry_failure_contract <- function() {
  context <- .wb_phase2c_context(); if (is.null(context)) return(.wb_phase2c_skip())
  guard <- .wb_phase2c_registry_guard()
  on.exit(.wb_phase2c_registry_restore(guard), add = TRUE)
  on.exit({ options(scworkbench.operation_pack_v2_test_hook = NULL)
    Sys.unsetenv("SCWBPYV2_REGISTRY_PROBE_FAULT") }, add = TRUE)
  wb_operation_pack_activate(context$manifest, python = context$python)
  fixture <- .wb_phase2c_registry_fixture("failure")
  on.exit({ try(wb_close_bundle(fixture$bundle), silent = TRUE)
    unlink(fixture$root, recursive = TRUE, force = TRUE) }, add = TRUE)
  inputs <- .wb_phase2c_registry_inputs(fixture)
  params <- .wb_phase2c_registry_params()
  run <- function(op = "scwbpyv2reference::registry_probe", p = params) {
    scworkbench:::.wb_operation_pack_v2_execute(fixture$bundle, op, inputs, p)
  }
  expect_clean <- function(expr, codes) {
    before <- .wb_phase2c_registry_state(fixture)
    error <- tryCatch(force(expr), error = identity)
    stopifnot(inherits(error, "wb_operation_pack_error"),
      as.character(error$code) %in% codes)
    .wb_phase2c_registry_assert_no_residue(fixture, before)
    invisible(error)
  }

  expect_clean(run("scwbpyv2reference::registry_probe_strict",
    .wb_phase2c_registry_params(namespace = "missing")),
    "PYBENCH_INPUT_IDENTITY_MISMATCH")

  payload_faults <- list(
    wrong_matrix = function(x) { x$matrix_id <- "other"; x },
    wrong_feature_order = function(x) { x$feature_universe <-
      rev(x$feature_universe); x },
    wrong_namespace = function(x) { x$sets[[1]]$namespace <- "wrong"; x },
    duplicate_member = function(x) { x$sets[[1]]$memberships[[2]]$feature_id <-
      x$sets[[1]]$memberships[[1]]$feature_id; x },
    foreign_member = function(x) { x$sets[[1]]$memberships[[1]]$feature_id <-
      "foreign"; x },
    altered_rank = function(x) { x$sets[[1]]$memberships[[1]]$rank <- 9L; x },
    altered_metadata = function(x) { x$sets[[1]]$description <- "changed"; x })
  for (mutate in payload_faults) {
    options(scworkbench.operation_pack_v2_test_hook = local({ change <- mutate
      function(event, transition_id = NULL, ...) if (identical(event,
          "before_dispatch")) {
        path <- file.path(
          scworkbench:::.wb_operation_pack_v2_pending_root(fixture$bundle),
          transition_id, "registry_reads", "feature_sets", "payload.json")
        value <- jsonlite::read_json(path, simplifyVector = FALSE)
        scworkbench:::.wb_operation_pack_v2_atomic_json(change(value), path)
      }
    }))
    expect_clean(run(), "PYBENCH_INPUT_IDENTITY_MISMATCH")
    options(scworkbench.operation_pack_v2_test_hook = NULL)
  }

  for (fault in c("missing_reader", "duplicate_reader", "undeclared_reader")) {
    Sys.setenv(SCWBPYV2_REGISTRY_PROBE_FAULT = fault)
    expect_clean(run(), c("PYBENCH_PROCESS_FAILED", "PYBENCH_CAPABILITY_MISMATCH"))
    Sys.unsetenv("SCWBPYV2_REGISTRY_PROBE_FAULT")
  }

  rehash_receipt <- function(value) {
    value$receipt_identity <- NULL
    value$receipt_identity <- scworkbench:::.wb_operation_pack_v2_identity_scoped(
      "scworkbench.operation_pack.transition_receipt.v2",
      "receipt excluding receipt_identity", value)
    value
  }
  receipt_faults <- list(
    missing = function(x) { x$registry_reads <- list(); rehash_receipt(x) },
    extra = function(x) { extra <- x$registry_reads[[1]]; extra$name <- "extra"
      x$registry_reads[[2]] <- extra; rehash_receipt(x) },
    forged = function(x) {
      observed <- x$registry_reads[[1]]$descriptor
      observed$content_identity$sha256 <- strrep("0", 64L)
      observed$observed_descriptor_identity <- NULL
      observed$observed_descriptor_identity <-
        scworkbench:::.wb_operation_pack_v2_identity_scoped(
          "scworkbench.operation_pack.observed_registry_read.v2",
          "descriptor excluding observed_descriptor_identity", observed)
      x$registry_reads[[1]]$descriptor <- observed
      rehash_receipt(x)
    })
  for (mutate in receipt_faults) {
    options(scworkbench.operation_pack_v2_test_hook = local({ change <- mutate
      function(event, stage = NULL, ...) if (identical(event,
          "python_process_completed")) {
        path <- file.path(stage, "receipt.json")
        value <- jsonlite::read_json(path, simplifyVector = FALSE)
        scworkbench:::.wb_operation_pack_v2_atomic_json(change(value), path)
      }
    }))
    expect_clean(run(), "PYBENCH_RECEIPT_MISMATCH")
    options(scworkbench.operation_pack_v2_test_hook = NULL)
  }

  before <- .wb_phase2c_registry_state(fixture)
  options(scworkbench.operation_pack_v2_test_hook = function(event, ...) {
    if (identical(event, "staged")) {
      DBI::dbExecute(fixture$bundle$con,
        paste("UPDATE feature_sets SET description = ?",
          "WHERE matrix_id = ? AND feature_set = ?"),
        params = list("changed after preflight", "RNA_counts", "SET_A"))
    }
  })
  error <- tryCatch(run(), error = identity)
  options(scworkbench.operation_pack_v2_test_hook = NULL)
  DBI::dbExecute(fixture$bundle$con,
    paste("UPDATE feature_sets SET description = ?",
      "WHERE matrix_id = ? AND feature_set = ?"),
    params = list("Alpha set", "RNA_counts", "SET_A"))
  stopifnot(inherits(error, "wb_operation_pack_error"),
    identical(as.character(error$code), "PYBENCH_INPUT_IDENTITY_MISMATCH"))
  .wb_phase2c_registry_assert_no_residue(fixture, before)

  Sys.setenv(SCWBPYV2_REGISTRY_PROBE_FAULT = "mutate_private_copy")
  private <- run()
  Sys.unsetenv("SCWBPYV2_REGISTRY_PROBE_FAULT")
  retained <- wb_operation_pack_transition_registry_reads(fixture$bundle,
    private$transition_id)$feature_sets$snapshot
  stopifnot(as.integer(private$outputs$summary$table$set_count) == 0L,
    length(retained$sets) == 2L)
  retry <- run()
  stopifnot(identical(retry$state, "reopened"),
    as.integer(retry$outputs$summary$table$set_count) == 2L)
  TRUE
}
