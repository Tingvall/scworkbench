# Actual runner-boundary integration. Only an owned copy of the synthetic
# reference pack changes; no official pack or core runtime is modified.
.engine_registry_runner_install <- function() {
  root <- tempfile("registry_runner_pack_"); dir.create(root)
  source_root <- Sys.getenv("SCWORKBENCH_SOURCE_ROOT", unset = getwd())
  fixture <- file.path(source_root, "tests", "fixtures", "operation-pack-v3-reference")
  stopifnot(dir.exists(fixture), !"scwbV3Reference" %in% loadedNamespaces())
  stopifnot(file.copy(fixture, root, recursive = TRUE))
  copied <- file.path(root, basename(fixture))
  manifest_path <- file.path(copied, "inst", "scworkbench", "operation-pack.json")
  manifest <- jsonlite::read_json(manifest_path, simplifyVector = FALSE)
  index <- which(vapply(manifest$operations, function(x)
    identical(x$name, "bounded_family"), logical(1)))
  stopifnot(length(index) == 1L)
  manifest$operations[[index]]$registry_reads <- list(list(name = "annotations",
    category = "authenticated_core_registry_snapshot", kind = "matrix_feature_annotations",
    reader = "read_matrix_feature_annotations", matrix_input = "matrix",
    fields = list("feature_type"), row_order = "matrix_feature_order_v1",
    missing_annotation_policy = "preserve_null", call_discipline = "single_use"))
  jsonlite::write_json(manifest, manifest_path, auto_unbox = TRUE, pretty = TRUE)
  register <- file.path(copied, "R", "register.R")
  writeLines(c(readLines(register, warn = FALSE),
    ".bounded_family_original <- .bounded_family",
    ".bounded_family <- function(readers, writers, params, context) {",
    "  annotations <- readers$annotations()",
    "  .bounded_family_original(readers, writers, params, context)",
    "}"), register)
  library <- file.path(root, "library"); dir.create(library)
  log <- file.path(root, "install.log")
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(library)), shQuote(copied)), stdout = log, stderr = log)
  if (!identical(as.integer(status), 0L)) stop(paste(readLines(log, warn = FALSE), collapse = "\n"))
  old <- .libPaths(); .libPaths(c(library, old))
  installed_manifest <- system.file("scworkbench", "operation-pack.json",
    package = "scwbV3Reference", lib.loc = library)
  wb_operation_pack_activate(installed_manifest, lib.loc = library)
  list(root = root, old = old)
}

.engine_registry_runner_cleanup <- function(installed, bundle = NULL, session = NULL, root = NULL) {
  if (!is.null(session)) try(wb_session_discard(session), silent = TRUE)
  if (!is.null(bundle) && DBI::dbIsValid(bundle$con)) wb_close_bundle(bundle)
  try(wb_operation_pack_unload("scwbv3reference"), silent = TRUE)
  if ("scwbV3Reference" %in% loadedNamespaces()) unloadNamespace("scwbV3Reference")
  .libPaths(installed$old)
  unlink(installed$root, recursive = TRUE, force = TRUE)
  if (!is.null(root)) unlink(root, recursive = TRUE, force = TRUE)
}

.engine_registry_runner_inventory <- function(bundle) {
  files <- sort(list.files(bundle$dir, recursive = TRUE, full.names = TRUE,
    all.files = TRUE, no.. = TRUE))
  files <- files[!file.info(files)$isdir]
  tables <- intersect(c("prov_runs", "prov_run_outputs", "prov_commits", "prov_materializations",
    "artifacts", "artifact_tables", "artifact_object_payload_meta", "entity_lifecycle",
    "matrices", "matrix_fragments", "spaces", "space_payloads"), DBI::dbListTables(bundle$con))
  list(logical = scworkbench:::.wb_manifest_registry_snapshot(bundle$con),
    counts = setNames(vapply(tables, function(table) as.numeric(DBI::dbGetQuery(bundle$con,
      paste0("SELECT COUNT(*) n FROM ", DBI::dbQuoteIdentifier(bundle$con, table)))$n[[1]]), numeric(1)), tables),
    files = data.frame(path = substring(files, nchar(bundle$dir) + 2L),
      bytes = file.info(files)$size,
      sha256 = vapply(files, digest::digest, "", algo = "sha256", file = TRUE)))
}

.engine_registry_runner_spy <- function(target = NULL) {
  ns <- asNamespace("scworkbench")
  name <- ".wb_operation_pack_v3_registry_reads_assert_current"
  original <- get(name, ns); state <- new.env(parent = emptyenv())
  state$calls <- 0L; state$stages <- character(); state$injected <- FALSE; state$restored <- FALSE
  replacement <- function(bundle, operation, inputs, params, request, effective_cells,
      session_id, run_id, generation) {
    state$calls <- state$calls + 1L
    state$stages <- unique(c(state$stages, bundle$dir))
    # Prove this is the real issued request at the executor's actual boundary,
    # not a hand-assembled unit-test observation passed directly to the helper.
    stopifnot(length(attr(request, "operation_pack_v3_registry_observations", exact = TRUE)) == 1L,
      length(request$registry_reads) == 1L,
      nzchar(request$registry_reads[[1L]]$descriptor$input_descriptor_identity$sha256))
    if (!is.null(target) && identical(state$calls, as.integer(target))) {
      changed <- DBI::dbExecute(bundle$con,
        "UPDATE features SET feature_type=? WHERE matrix_id=? AND feature_id=?;",
        params = list("changed_after_issuance", "RNA", "g2"))
      stopifnot(changed == 1L); state$injected <- TRUE
    }
    original(bundle, operation, inputs, params, request, effective_cells,
      session_id, run_id, generation)
  }
  locked <- bindingIsLocked(name, ns)
  if (locked) unlockBinding(name, ns)
  assign(name, replacement, ns); if (locked) lockBinding(name, ns)
  restore <- function() {
    if (state$restored) return(invisible(NULL))
    if (bindingIsLocked(name, ns)) unlockBinding(name, ns)
    assign(name, original, ns); if (locked) lockBinding(name, ns)
    state$restored <- TRUE
  }
  list(state = state, restore = restore)
}

.engine_registry_runner_failure_and_retry <- function(target = NULL, publication_fault = FALSE) {
  installed <- .engine_registry_runner_install()
  bundle <- NULL; session <- NULL; root <- tempfile("registry_runner_source_")
  on.exit(.engine_registry_runner_cleanup(installed, bundle, session, root), add = TRUE)
  bundle <- wb_init_bundle(root)
  cells <- c("c2", "c1", "c3"); features <- c("g2", "g1", "g3", "g4")
  wb_define_cells(bundle, cells)
  wb_attach_matrix(bundle, "RNA", Matrix::Matrix(matrix(seq_len(12L), 4L,
    dimnames = list(features, cells)), sparse = TRUE), feature_type = "gene")
  wb_finalize_recipient_bundle(bundle)
  before <- .engine_registry_runner_inventory(bundle)
  run <- function() wb_session_run_op(wb_session_new(), bundle,
    "scwbv3reference::bounded_family", inputs = list(matrix = "RNA", cell_set = "all",
      min_cells = 1L, features = list(sigB = list("g2", "g4"), sigA = list("g1", "g3")), name = "Module"))
  spy <- .engine_registry_runner_spy(target)
  # Register restore ahead of cleanup and also restore before any assertions or
  # successful retry. Test spies must never escape into cleanup/publication.
  on.exit(spy$restore(), add = TRUE, after = FALSE)
  old_hook <- getOption("scworkbench.operation_pack_v2_test_hook")
  hook_fired <- FALSE
  on.exit(options(scworkbench.operation_pack_v2_test_hook = old_hook), add = TRUE, after = FALSE)
  if (publication_fault) options(scworkbench.operation_pack_v2_test_hook = function(event, ...) {
    if (identical(event, "before_publication")) {
      hook_fired <<- TRUE; stop("registry runner injected publication failure")
    }
  })
  failure <- tryCatch(run(), error = identity, finally = {
    spy$restore(); options(scworkbench.operation_pack_v2_test_hook = old_hook)
  })
  stopifnot(inherits(failure, "error"), isTRUE(spy$state$restored),
    identical(before, .engine_registry_runner_inventory(bundle)),
    length(spy$state$stages) == 1L, !identical(spy$state$stages[[1]], bundle$dir),
    !dir.exists(spy$state$stages[[1]]))
  if (publication_fault) stopifnot(hook_fired, spy$state$calls == 2L,
    identical(failure$code, "PYBENCH_PUBLICATION_FAILED")) else stopifnot(
    spy$state$injected, spy$state$calls == as.integer(target),
    identical(failure$code, "PYBENCH_INPUT_IDENTITY_MISMATCH"))
  stopifnot(identical(as.character(wb_features(bundle, "RNA")$feature_type), rep("gene", 4L)))

  retry <- run(); session <- retry$session
  stopifnot(identical(as.character(retry$run$outputs$scores$key), rep(c("sigB", "sigA"), each = 3L)),
    identical(as.character(retry$run$outputs$scores$cell_id), rep(cells, 2L)),
    identical(as.numeric(retry$run$outputs$scores$value), as.numeric(seq_len(6L))))
  transition <- retry$run$operation_pack_transition$transition_id
  staged_reads <- wb_operation_pack_transition_registry_reads(wb_session_view(session), transition)
  stopifnot(identical(names(staged_reads), "annotations"),
    staged_reads$annotations$snapshot$feature_count == 4L,
    staged_reads$annotations$observation$use_count == 1L,
    identical(staged_reads$annotations$descriptor$content_identity,
      staged_reads$annotations$observation$content_identity),
    identical(staged_reads$annotations$descriptor$source_identity,
      staged_reads$annotations$observation$source_identity))
  promotion <- wb_session_promote_current(bundle, session, outputs = "scores",
    created_by = "registry-runner-contract")
  stopifnot(nrow(promotion$promoted) == 1L)
  artifact <- as.character(promotion$promoted$artifact_id[[1L]])
  wb_session_discard(session); session <- NULL
  wb_finalize_recipient_bundle(bundle); wb_close_bundle(bundle); bundle <- NULL
  wb_operation_pack_unload("scwbv3reference")
  bundle <- wb_open_bundle(root, validate = FALSE, read_only = TRUE)
  before_recipient <- .engine_registry_runner_inventory(bundle)
  loaded <- wb_art_load(bundle, artifact, expected_kind = "cell_vector_family")
  retained_reads <- wb_operation_pack_transition_registry_reads(bundle, transition)
  report <- wb_bundle_validation_report(root, level = "recipient")
  stopifnot(identical(loaded$value, retry$run$outputs$scores$value),
    identical(retained_reads, staged_reads), isTRUE(report$ok),
    identical(before_recipient, .engine_registry_runner_inventory(bundle)))
  TRUE
}

test_engine_registry_runner_predispatch_change_contract <- function() {
  .engine_registry_runner_failure_and_retry(target = 1L)
}

test_engine_registry_runner_prepublication_change_contract <- function() {
  .engine_registry_runner_failure_and_retry(target = 2L)
}

test_engine_registry_runner_publication_rollback_contract <- function() {
  .engine_registry_runner_failure_and_retry(publication_fault = TRUE)
}
