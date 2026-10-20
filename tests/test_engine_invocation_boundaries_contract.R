.engine_epoch_fixture <- function() {
  root <- tempfile("engine_epoch_")
  b <- wb_init_bundle(root)
  cells <- paste0("cell_", seq_len(12L))
  wb_define_cells(b, cells, metadata = data.frame(cell_id = cells,
    group = rep(c("a", "b"), 6L)))
  list(bundle = b, root = root, cells = cells)
}

test_engine_source_registry_continuity_contract <- function() {
  fixture <- .engine_epoch_fixture(); b <- fixture$bundle
  other <- NULL
  on.exit({if (!is.null(other)) try(DBI::dbDisconnect(other), silent = TRUE)
    try(wb_close_bundle(b), silent = TRUE); unlink(fixture$root, recursive = TRUE)},
    add = TRUE)
  calls <- new.env(parent = emptyenv()); calls$n <- 0L
  old <- getOption("engine.epoch.test.calls")
  options(engine.epoch.test.calls = calls)
  trace(".wb_manifest_registry_snapshot", where = asNamespace("scworkbench"),
    print = FALSE, tracer = quote({
      counter <- getOption("engine.epoch.test.calls"); counter$n <- counter$n + 1L
    }))
  on.exit({untrace(".wb_manifest_registry_snapshot", where = asNamespace("scworkbench"))
    options(engine.epoch.test.calls = old)}, add = TRUE)
  scworkbench:::.wb_session_source_forget(b$con)
  original <- scworkbench:::.wb_session_source_identity(b)
  for (i in 1:5) stopifnot(identical(original,
    scworkbench:::.wb_session_source_identity(b)))
  stopifnot(calls$n == 1L)
  DBI::dbExecute(b$con, "UPDATE cells SET dataset_id='own' WHERE cell_id=?;",
    params = list(fixture$cells[1]))
  own <- scworkbench:::.wb_session_source_identity(b)
  stopifnot(calls$n == 2L, !identical(original$scientific_state_fingerprint,
    own$scientific_state_fingerprint))
  DBI::dbBegin(b$con)
  DBI::dbExecute(b$con, "UPDATE cells SET dataset_id='rolled_back' WHERE cell_id=?;",
    params = list(fixture$cells[1]))
  failure <- try(scworkbench:::.wb_session_source_identity(b), silent = TRUE)
  stopifnot(inherits(failure, "try-error"), grepl("SOURCE_TRANSACTION", failure))
  DBI::dbRollback(b$con)
  stopifnot(identical(own$scientific_state_fingerprint,
    scworkbench:::.wb_session_source_identity(b)$scientific_state_fingerprint),
    calls$n == 3L)
  DBI::dbExecute(b$con, "CREATE TABLE engine_epoch_probe(value INTEGER);")
  scworkbench:::.wb_session_source_identity(b)
  stopifnot(calls$n == 4L)
  DBI::dbExecute(b$con, "PRAGMA journal_mode=WAL;")
  other <- DBI::dbConnect(RSQLite::SQLite(), file.path(fixture$root, "db", "app.sqlite"))
  DBI::dbBegin(b$con)
  DBI::dbGetQuery(b$con, "SELECT count(*) FROM cells;")
  DBI::dbExecute(other, "UPDATE cells SET dataset_id='wal' WHERE cell_id=?;",
    params = list(fixture$cells[2]))
  failure <- try(scworkbench:::.wb_session_source_identity(b), silent = TRUE)
  stopifnot(inherits(failure, "try-error"), grepl("SOURCE_TRANSACTION", failure))
  DBI::dbRollback(b$con)
  wal <- scworkbench:::.wb_session_source_identity(b)
  stopifnot(calls$n == 5L, !identical(own$scientific_state_fingerprint,
    wal$scientific_state_fingerprint))
  scworkbench:::.wb_session_sqlite_backup(b$con,
    file.path(fixture$root, "epoch-copy.sqlite"))
  stopifnot(identical(wal$scientific_state_fingerprint,
    scworkbench:::.wb_session_source_identity(b)$scientific_state_fingerprint),
    # Intentional frequency-policy change: an eligible source-only backup
    # retains the ORIGINAL actual source observation, not a new authority.
    calls$n == 5L)
  scworkbench:::.wb_session_source_forget(b$con)
  scworkbench:::.wb_session_source_identity(b)
  stopifnot(calls$n == 6L)
  TRUE
}

test_engine_invocation_registry_observation_contract <- function() {
  fixture <- .engine_epoch_fixture(); b <- fixture$bundle
  stage <- scworkbench:::.wb_session_stage_bundle(b, wb_session_new())
  on.exit({wb_session_discard(stage$session); wb_close_bundle(b)
    unlink(fixture$root, recursive = TRUE)}, add = TRUE)
  work <- stage$bundle
  scworkbench:::.wb_with_mutation_context(work, route = "session_execution",
    code = {
      a <- scworkbench:::.wb_operation_pack_registry_snapshot(work)
      context <- scworkbench:::.wb_current_mutation_context(work$con)
      stopifnot(identical(a, context$observations$registry$value))
      token <- context$observations$registry
      for (i in 1:5) stopifnot(identical(a,
        scworkbench:::.wb_operation_pack_registry_snapshot(work)))
      DBI::dbExecute(work$con, "UPDATE cells SET dataset_id='changed' WHERE cell_id=?;",
        params = list(fixture$cells[1]))
      changed <- scworkbench:::.wb_operation_pack_registry_snapshot(work)
      stopifnot(!identical(a$fingerprint, changed$fingerprint),
        !identical(token$epoch, context$observations$registry$epoch))
    })
  stopifnot(is.null(scworkbench:::.wb_current_mutation_context(work$con)))
  scworkbench:::.wb_with_mutation_context(work, route = "session_execution",
    code = stopifnot(is.null(scworkbench:::.wb_current_mutation_context(work$con)$
      observations$registry)))
  TRUE
}

test_engine_fresh_rds_seal_eligibility_contract <- function() {
  eligible <- scworkbench:::.wb_operation_pack_v2_direct_rds_seals
  for (kind in c(scworkbench:::.wb_object_primitive_kinds(), "feature_table", "obs_table")) {
    receipt <- list(outputs = list(list(descriptor = list(kind = kind,
      payload_manifest_identity = list(sha256 = "sealed")))))
    stopifnot(isTRUE(eligible(receipt, FALSE, FALSE)),
      !eligible(receipt, TRUE, FALSE), !eligible(receipt, FALSE, TRUE))
    for (field in c("matrix_fragment_manifest", "contained_model_tree",
        "contained_model_sibling_tree", "contained_matrix_model_sibling_tree")) {
      special <- receipt; special$outputs[[1]]$descriptor[[field]] <- list()
      stopifnot(!eligible(special, FALSE, FALSE))
    }
    registry <- receipt; registry$registry_requests <- list(list(name = "mutation"))
    unsealed <- receipt; unsealed$outputs[[1]]$descriptor$payload_manifest_identity <- NULL
    stopifnot(!eligible(registry, FALSE, FALSE), !eligible(unsealed, FALSE, FALSE))
  }
  for (kind in c("matrix", "space", "space_2d", "model_ref", "graph"))
    stopifnot(!eligible(list(outputs = list(list(descriptor = list(kind = kind,
      payload_manifest_identity = list(sha256 = "sealed"))))), FALSE, FALSE))
  stopifnot(!eligible(list(outputs = list()), FALSE, FALSE))
  TRUE
}

test_engine_promotion_locked_source_contract <- function() {
  fixture <- .engine_epoch_fixture(); b <- fixture$bundle
  workspace <- tempfile("engine_locked_promotion_")
  on.exit({options(scworkbench.durable_session_fault_hook = NULL)
    try(wb_close_bundle(b), silent = TRUE)
    unlink(c(fixture$root, workspace), recursive = TRUE)}, add = TRUE)
  result <- wb_session_run_op(wb_session_create(b, workspace, "locked"), b,
    "metadata_cell_vector", inputs = list(source_column = "group",
      vector_name = "group", value_type = "categorical", cell_set = "all",
      min_cells = 1L))
  before <- nrow(wb_art_list(b)); injected <- FALSE
  options(scworkbench.durable_session_fault_hook = function(where) {
    if (identical(where, "before_promotion_source_lock")) {
      injected <<- TRUE
      DBI::dbExecute(b$con, "UPDATE cells SET dataset_id='raced' WHERE cell_id=?;",
        params = list(fixture$cells[1]))
    }
  })
  failure <- try(wb_session_promote_current(b, result$session, outputs = "vector"),
    silent = TRUE)
  options(scworkbench.durable_session_fault_hook = NULL)
  stopifnot(injected, inherits(failure, "try-error"),
    grepl("DURABLE_SESSION_SOURCE_CHANGED", failure), nrow(wb_art_list(b)) == before)
  wb_session_discard(result$session)
  TRUE
}

test_engine_selected_dependency_corruption_contract <- function() {
  contract_test_activate_phase5_conformance_pack()
  on.exit(contract_test_deactivate_phase5_conformance_pack(), add = TRUE)
  fixture <- .engine_epoch_fixture(); b <- fixture$bundle
  workspace <- tempfile("engine_selected_dependency_")
  session <- NULL
  on.exit({if (!is.null(session)) try(wb_session_discard(session), silent = TRUE)
    try(wb_close_bundle(b), silent = TRUE)
    unlink(c(fixture$root, workspace), recursive = TRUE)}, add = TRUE)
  wb_add_space(b, "source.pca", matrix(seq_len(48L) / 10, 12L,
    dimnames = list(fixture$cells, paste0("PC", 1:4))), source = "contract")
  fit <- wb_session_run_op(wb_session_create(b, workspace, "dependencies"), b,
    "scwbv3phase5::fit_sibling_model", inputs = list(source = "source.pca",
      cell_set = "all", min_cells = 1L, dims = 1:4))
  session <- fit$session
  path <- fit$run$outputs$model$model_path
  if (!scworkbench:::.wb_path_is_absolute(path))
    path <- file.path(session$staging_bundle$dir, path)
  victim <- if (dir.exists(path)) list.files(path, recursive = TRUE,
    full.names = TRUE)[1L] else path
  stopifnot(file.exists(victim))
  original_bytes <- readBin(victim, "raw", n = file.info(victim)$size)
  connection <- file(victim, "ab")
  tryCatch(writeBin(charToRaw("changed retained bytes"), connection),
    finally = close(connection))
  # Controller-approved sibling scope: authenticate the intact embedding, not
  # its unused model sibling. Full checkpoint binding still precedes dispatch.
  source_before <- scworkbench:::.wb_prov_file_tree_sha256(b$dir)
  clean <- wb_session_run_op(session, b, "scwbv3phase5::derived_subset",
    inputs = list(source = wb_ref_run(fit$run$run_id, "embedding"),
      selected_cells = fixture$cells[c(1L, 3L)], key_prefix = "scope_",
      cell_set = "all", min_cells = 1L))
  session <- clean$session
  stopifnot(identical(clean$run$outputs$vector$cell_id, fixture$cells[c(1L, 3L)]),
    identical(as.numeric(clean$run$outputs$vector$value), c(1, 3)),
    identical(clean$run$inputs$parents, fit$run$run_id),
    identical(source_before, scworkbench:::.wb_prov_file_tree_sha256(b$dir)))
  # Unrelated metadata execution is not a whole-history verification boundary.
  unrelated <- wb_session_run_op(session, b, "metadata_cell_vector",
    inputs = list(source_column = "group", vector_name = "independent",
      value_type = "categorical", cell_set = "all", min_cells = 1L))
  session <- unrelated$session
  stopifnot(length(session$runs) == 3L)
  before <- nrow(wb_art_list(b))
  calls <- new.env(parent = emptyenv()); calls$n <- 0L
  options(scwb.test.dependency_dispatch = calls)
  trace(".wb_operation_pack_v2_execute", where = asNamespace("scworkbench"),
    print = FALSE, tracer = quote({
      counter <- getOption("scwb.test.dependency_dispatch"); counter$n <- counter$n + 1L
    }))
  on.exit({untrace(".wb_operation_pack_v2_execute", where = asNamespace("scworkbench"))
    options(scwb.test.dependency_dispatch = NULL)}, add = TRUE)
  for (input in list(wb_ref_run(fit$run$run_id, "model"), fit$run$outputs$model)) {
    stage_before <- scworkbench:::.wb_prov_file_tree_sha256(session$staging_bundle$dir)
    checkpoint_before <- digest::digest(file = scworkbench:::.wb_session_checkpoint_file(session), algo = "sha256")
    failure <- try(wb_session_run_op(session, b,
      "scwbv3phase5::consume_self_linked_model", inputs = list(model = input,
        cell_set = "all", min_cells = 1L)), silent = TRUE)
    stopifnot(inherits(failure, "try-error"),
      grepl("DURABLE_SESSION_PAYLOAD_CORRUPT", failure), nrow(wb_art_list(b)) == before,
      identical(stage_before, scworkbench:::.wb_prov_file_tree_sha256(session$staging_bundle$dir)),
      identical(checkpoint_before, digest::digest(file = scworkbench:::.wb_session_checkpoint_file(session), algo = "sha256")))
  }
  failure <- try(wb_session_run_op(session, b,
    "scwbv3phase5::consume_self_linked_model", inputs = list(
      cell_set = "all", min_cells = 1L)), silent = TRUE)
  stopifnot(inherits(failure, "try-error"), grepl("DURABLE_SESSION_PAYLOAD_CORRUPT", failure))
  edited <- session
  edited$runs[[fit$run$run_id]]$outputs$embedding$value[[1L]] <- 999
  failure <- try(wb_session_run_op(edited, b, "scwbv3phase5::derived_subset",
    inputs = list(source = wb_ref_run(fit$run$run_id, "embedding"),
      selected_cells = fixture$cells[c(1L, 3L)], key_prefix = "scope_",
      cell_set = "all", min_cells = 1L)), silent = TRUE)
  stopifnot(inherits(failure, "try-error"), grepl("DURABLE_SESSION_UNCHECKPOINTED_STATE", failure))
  failure <- try(wb_session_promote_current(b, session,
    outputs = list(wb_ref_run(fit$run$run_id, "model"))), silent = TRUE)
  stopifnot(inherits(failure, "try-error"), grepl("DURABLE_SESSION_PAYLOAD_CORRUPT", failure),
    nrow(wb_art_list(b)) == before)
  failure <- try(wb_session_resume(b, session$durable$workspace), silent = TRUE)
  stopifnot(inherits(failure, "try-error"), grepl("DURABLE_SESSION_PAYLOAD_CORRUPT", failure))
  stopifnot(calls$n == 0L)
  # Restore actual bytes, not a recorded hash: full validation and retry work.
  connection <- file(victim, "wb")
  tryCatch(writeBin(original_bytes, connection), finally = close(connection))
  scworkbench:::.wb_session_validate_payloads(session)
  retry <- wb_session_run_op(session, b, "scwbv3phase5::derived_subset",
    inputs = list(source = wb_ref_run(fit$run$run_id, "embedding"),
      selected_cells = fixture$cells[c(1L, 3L)], key_prefix = "scope_",
      cell_set = "all", min_cells = 1L))
  session <- retry$session
  stopifnot(calls$n == 1L,
    identical(retry$run$outputs$vector, clean$run$outputs$vector))
  # Selecting only the independent branch does not silently promote the model.
  promoted <- wb_session_promote_current(b, session,
    outputs = list(wb_ref_run(unrelated$run$run_id, "vector")))
  stopifnot(nrow(promoted$promoted) == 1L,
    all(promoted$promoted$status == "ok"), nrow(wb_art_list(b)) == before + 1L)
  session <- promoted$session
  TRUE
}

test_engine_consumed_output_binding_fallback_contract <- function() {
  state <- new.env(parent = asNamespace("scworkbench"))
  state$selected <- NULL; state$outputs <- NULL
  state$.wb_session_validate_payloads <- function(session, run_ids = NULL, .outputs = NULL) {
    state$selected <- run_ids; state$outputs <- .outputs; invisible(TRUE)
  }
  check <- scworkbench:::.wb_session_validate_dependencies
  environment(check) <- state
  vector <- wb_prim_cell_vector(c(c2 = 1, c1 = 2), value_type = "continuous")
  session <- list(durable = list(), runs = list(a = list(outputs = list(
    left = vector, right = vector)), b = list(outputs = list(vector = vector))))
  binding <- list(source = list(run_id = "a", output = "right"))
  check(session, list(source = vector), "a", .bindings = binding)
  stopifnot(identical(state$selected, "a"), identical(state$outputs, list(a = "right")))
  # Equal values cannot select the first sibling or explain another parent.
  check(session, list(source = vector), c("a", "b"), .bindings = binding)
  stopifnot(identical(state$selected, c("a", "b")), identical(state$outputs, list(a = "right")))
  for (bad in list(NULL, list(), list(other = binding$source),
      list(source = list(run_id = "a", output = "missing")),
      list(source = list(run_id = "b", output = "vector")),
      list(source = list(run_id = "a", output = "right", extra = TRUE)))) {
    check(session, list(source = vector), "a", .bindings = bad)
    stopifnot(identical(state$selected, "a"), is.null(state$outputs))
  }
  check(session, list(), "a")
  stopifnot(identical(state$selected, "a"), is.null(state$outputs))
  # Unnamed direct helper input retains original matrix ownership checking.
  session$runs$m <- list(outputs = list(matrix = wb_prim_matrix("stage")))
  check(session, list(wb_prim_matrix("stage")), character())
  stopifnot(identical(state$selected, "m"), is.null(state$outputs))
  TRUE
}

test_engine_direct_axis_dependency_selection_contract <- function() {
  state <- new.env(parent = asNamespace("scworkbench"))
  state$selected <- NULL
  state$.wb_session_validate_payloads <- function(session, run_ids = NULL) {
    state$selected <- run_ids; invisible(TRUE)
  }
  check <- scworkbench:::.wb_session_validate_dependencies
  environment(check) <- state
  matrix <- wb_prim_matrix("derived")
  space <- wb_prim_space("fitted")
  session <- list(durable = list(), runs = list(a = list(outputs = list(matrix = matrix)),
    b = list(outputs = list(space = space))))
  check(session, list(matrix = wb_prim_matrix("derived")), character())
  stopifnot(identical(state$selected, "a"))
  check(session, list(space = wb_prim_space("fitted")), character())
  stopifnot(identical(state$selected, "b"))
  check(session, list(matrix = wb_prim_matrix("committed")), character())
  stopifnot(identical(state$selected, character()))
  check(session, list(), "a")
  stopifnot(identical(state$selected, "a"))
  session$runs$c <- list(outputs = list(matrix = matrix))
  stopifnot(inherits(try(check(session, list(matrix = matrix), character()),
    silent = TRUE), "try-error"))
  TRUE
}
