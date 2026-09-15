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
  revision <- system2("git", c("-C", context$root, "rev-parse", "HEAD"),
    stdout = TRUE)
  stopifnot(identical(revision[[1]],
    "11232d000ee42aa1344c9d6fb25a73acb1d88fe2"))
  shared <- c("operation-pack-v2.schema.json",
    "operation-pack-transition-request-v2.schema.json",
    "operation-pack-transition-receipt-v2.schema.json",
    "fixtures/operation-pack-v2/identities.json")
  expected <- c(
    "d6756c057704820f2b6f1069035546a85fa2cbf504885f519bfe4535550f727c",
    "81bf35b2827778f149aee3e3ca2e921332f22415a290b5e9c704af37b7e1aed2",
    "2cd5e6192daa799bd4562dd1f0d4761eb1a7e8847ff048b3880783a0db0fba1b",
    "2bbb704a50c9c3fbed15c305e1767b953520df8a471613b493ba7f3f4b27925d")
  for (i in seq_along(shared)) {
    r_path <- file.path("inst", "protocol", shared[[i]])
    p_path <- file.path(context$root, "protocol", shared[[i]])
    stopifnot(identical(readBin(r_path, "raw", file.info(r_path)$size),
      readBin(p_path, "raw", file.info(p_path)$size)),
      identical(digest::digest(file = r_path, algo = "sha256", serialize = FALSE),
        expected[[i]]))
  }
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
    identical(read.dcf("inst/release/composite_release.dcf")[[1,
      "PyBenchCommit"]], revision[[1]]))
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
    identical(conformance$backend, "Python"), length(wb_list_ops()) == 53L)
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
    length(wb_list_ops()) == 56L)
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
  stopifnot(identical(first, second), length(wb_list_ops()) == 53L)
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
    "stopifnot(nrow(wb_operation_packs())==0L,length(wb_list_ops())==53L,",
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
  stopifnot(identical(r_inventory[, columns], py_inventory[, columns]),
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
