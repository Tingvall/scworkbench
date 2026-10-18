.engine_mixed_fixture <- function() {
  library <- tempfile("scwb-mixed-seal-lib-"); dir.create(library)
  log <- tempfile("scwb-mixed-seal-install-", fileext = ".log")
  source <- normalizePath("tests/fixtures/operation-pack-v3-phase5", mustWork = TRUE)
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(library)), shQuote(source)), stdout = log, stderr = log)
  if (!identical(status, 0L)) stop(paste(readLines(log, warn = FALSE), collapse = "\n"))
  old <- .libPaths(); .libPaths(c(library, old))
  wb_operation_pack_activate(system.file("scworkbench", "operation-pack.json",
    package = "scwbV3Phase5", lib.loc = library), lib.loc = library)
  root <- tempfile("scwb-mixed-seal-bundle-"); bundle <- wb_init_bundle(root)
  cells <- c("c2", "c1", "c4", "c3"); wb_define_cells(bundle, cells)
  wb_add_space(bundle, "pca", matrix(seq_len(12L), 4L,
    dimnames = list(cells, c("PC1", "PC2", "PC3"))))
  list(library = library, old = old, root = root, bundle = bundle,
    workspace = tempfile("scwb-mixed-seal-sessions-"))
}

.engine_mixed_cleanup <- function(fixture) {
  try(wb_operation_pack_unload("scwbv3phase5"), silent = TRUE)
  if ("scwbV3Phase5" %in% loadedNamespaces()) try(unloadNamespace("scwbV3Phase5"), silent = TRUE)
  suppressWarnings(try(wb_close_bundle(fixture$bundle), silent = TRUE))
  .libPaths(fixture$old)
  unlink(c(fixture$library, fixture$root, fixture$workspace), recursive = TRUE, force = TRUE)
  invisible(TRUE)
}

.engine_mixed_run <- function(session, bundle) wb_session_run_op(session, bundle,
  "scwbv3phase5::fit_sibling_model", inputs = list(source = "pca",
    dims = c(1L, 2L), cell_set = "all", min_cells = 1L))

.engine_mixed_snapshot <- function(bundle) {
  tables <- intersect(c("artifacts", "prov_runs", "prov_run_outputs",
    "prov_materializations", "prov_registry_mutations", "prov_run_entity_bindings",
    "matrices", "spaces", "space_payloads", "space_models", "artifact_model_ref"),
    DBI::dbListTables(bundle$con))
  rows <- stats::setNames(vapply(tables, function(table) as.numeric(DBI::dbGetQuery(
    bundle$con, paste0("SELECT COUNT(*) AS n FROM ", DBI::dbQuoteIdentifier(bundle$con, table)))$n), 0), tables)
  store <- scworkbench:::.wb_operation_pack_v2_store(bundle)
  list(rows = rows, transitions = if (dir.exists(store))
    sort(list.files(store, recursive = TRUE, all.files = TRUE, no.. = TRUE,
      include.dirs = TRUE)) else character())
}

test_engine_mixed_fresh_rds_semantic_scope_and_allowlist_contract <- function() {
  fixture <- .engine_mixed_fixture(); on.exit(.engine_mixed_cleanup(fixture), add = TRUE)
  spy <- new.env(parent = emptyenv()); spy$depth <- 0L; spy$vector <- 0L; spy$model_reads <- 0L
  previous <- getOption("scworkbench.engine_mixed_seal_spy")
  options(scworkbench.engine_mixed_seal_spy = spy)
  ns <- asNamespace("scworkbench")
  trace(".wb_operation_pack_v2_record_validate", where = ns, print = FALSE,
    tracer = quote({s <- getOption("scworkbench.engine_mixed_seal_spy"); s$depth <- s$depth + 1L}),
    exit = quote({s <- getOption("scworkbench.engine_mixed_seal_spy"); s$depth <- s$depth - 1L}))
  trace(".wb_operation_pack_sha256", where = ns, print = FALSE, tracer = quote({
    s <- getOption("scworkbench.engine_mixed_seal_spy")
    if (s$depth > 0L && is.list(x) && identical(x$kind, "cell_vector") &&
        !is.null(x$cell_id)) s$vector <- s$vector + 1L
  }))
  trace("readRDS", where = baseenv(), print = FALSE, tracer = quote({
    s <- getOption("scworkbench.engine_mixed_seal_spy")
    if (s$depth > 0L && is.character(file) && length(file) == 1L &&
        grepl("/outputs/model/payload[.]rds$", file)) s$model_reads <- s$model_reads + 1L
  }))
  on.exit({
    untrace("readRDS", where = baseenv())
    untrace(".wb_operation_pack_sha256", where = ns)
    untrace(".wb_operation_pack_v2_record_validate", where = ns)
    options(scworkbench.engine_mixed_seal_spy = previous)
  }, add = TRUE, after = FALSE)
  session <- wb_session_create(fixture$bundle, fixture$workspace, "healthy")
  result <- .engine_mixed_run(session, fixture$bundle)
  on.exit(suppressWarnings(try(wb_session_discard(result$session), silent = TRUE)), add = TRUE, after = FALSE)
  stopifnot(spy$depth == 0L, spy$vector == 0L, spy$model_reads >= 1L)
  path <- file.path(scworkbench:::.wb_operation_pack_v2_store(result$session$staging_bundle),
    result$run$operation_pack_transition$transition_id)
  receipt <- jsonlite::read_json(file.path(path, "receipt.json"), simplifyVector = FALSE)
  names_allowed <- scworkbench:::.wb_operation_pack_v2_direct_rds_names
  stopifnot(identical(names_allowed(receipt, FALSE, FALSE), "embedding"),
    !isTRUE(scworkbench:::.wb_operation_pack_v2_direct_rds_seals(receipt, FALSE, FALSE)))
  spy$vector <- 0L; spy$model_reads <- 0L
  full <- scworkbench:::.wb_operation_pack_v2_record_validate(path, load_payloads = TRUE)
  stopifnot(isTRUE(full$ok), spy$vector == 1L, spy$model_reads >= 1L)
  # Unrecognized/special requested names cannot turn the selective ordinary
  # shortcut into a blanket load_payloads=FALSE, including on a mixed record.
  spy$vector <- 0L; spy$model_reads <- 0L
  selective <- scworkbench:::.wb_operation_pack_v2_record_validate(path,
    load_payloads = TRUE, fresh_rds_outputs = c("embedding", "model", "foreign"))
  stopifnot(isTRUE(selective$ok), spy$vector == 0L, spy$model_reads >= 1L)
  stopifnot(!length(names_allowed(receipt, TRUE, FALSE)),
    !length(names_allowed(receipt, FALSE, TRUE)))
  changed <- receipt; changed$registry_requests <- list(list(name = "registry"))
  stopifnot(!length(names_allowed(changed, FALSE, FALSE)))
  index <- match("embedding", vapply(receipt$outputs, `[[`, "", "name"))
  changed <- receipt; changed$outputs[[index]]$descriptor$kind <- "graph"
  stopifnot(!length(names_allowed(changed, FALSE, FALSE)))
  changed <- receipt; changed$outputs[[index]]$descriptor$payload_manifest_identity <- NULL
  stopifnot(!length(names_allowed(changed, FALSE, FALSE)))
  for (field in c("matrix_fragment_manifest", "contained_model_tree",
      "contained_model_sibling_tree", "contained_matrix_model_sibling_tree")) {
    changed <- receipt; changed$outputs[[index]]$descriptor[[field]] <- list(identity = "special")
    stopifnot(!length(names_allowed(changed, FALSE, FALSE)))
  }
  TRUE
}

test_engine_mixed_fresh_rds_published_corruption_rollback_contract <- function() {
  fixture <- .engine_mixed_fixture(); on.exit(.engine_mixed_cleanup(fixture), add = TRUE)
  previous <- getOption("scworkbench.operation_pack_v2_test_hook")
  on.exit(options(scworkbench.operation_pack_v2_test_hook = previous), add = TRUE)
  for (target in c("embedding", "model")) {
    session <- wb_session_create(fixture$bundle, fixture$workspace, paste0("corrupt_", target))
    view <- wb_session_view(session)
    source_before <- .engine_mixed_snapshot(fixture$bundle)
    stage_before <- .engine_mixed_snapshot(view)
    fault <- new.env(parent = emptyenv()); fault$fired <- FALSE
    options(scworkbench.operation_pack_v2_test_hook = local({
      output <- target; directory <- view$dir
      function(event, transition_id, ...) if (identical(event, "published")) {
        path <- file.path(directory, "operation_pack_v2", transition_id,
          "outputs", output, "payload.rds")
        stopifnot(file.exists(path)); fault$fired <- TRUE
        writeBin(charToRaw("unreadable-rds-companion"), path)
      }
    }))
    failed <- tryCatch(.engine_mixed_run(session, fixture$bundle), error = identity)
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    stopifnot(isTRUE(fault$fired), inherits(failed, "wb_operation_pack_v2_error"),
      identical(failed$code, "PYBENCH_REOPEN_VALIDATION_FAILED"),
      identical(.engine_mixed_snapshot(fixture$bundle), source_before),
      identical(.engine_mixed_snapshot(view), stage_before), length(session$runs) == 0L)
    # Recovery remains the full persisted-byte/semantic boundary. Its source-only
    # checkpoint has no analytical claim and can execute the exact same request.
    wb_close_bundle(view)
    resumed <- wb_session_resume(fixture$bundle, session$durable$workspace)
    stopifnot(length(resumed$runs) == 0L, is.null(resumed$head_run_id))
    retried <- .engine_mixed_run(resumed, fixture$bundle)
    path <- file.path(scworkbench:::.wb_operation_pack_v2_store(retried$session$staging_bundle),
      retried$run$operation_pack_transition$transition_id)
    stopifnot(isTRUE(scworkbench:::.wb_operation_pack_v2_record_validate(path, load_payloads = TRUE)$ok),
      identical(.engine_mixed_snapshot(fixture$bundle), source_before))
    wb_session_discard(retried$session)
  }
  TRUE
}
