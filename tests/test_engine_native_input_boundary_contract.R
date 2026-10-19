.engine_native_boundary_fixture <- function() {
  root <- tempfile("engine_native_boundary_"); dir.create(root)
  state <- new.env(parent = emptyenv())
  state$root <- root; state$b <- NULL; state$sessions <- list()
  old_lib <- .libPaths()
  state$close <- function() {
    on.exit(unlink(root, recursive = TRUE), add = TRUE)
    for (s in state$sessions) try(wb_session_discard(s), silent = TRUE)
    try(wb_operation_pack_unload("enginespacefixture"), silent = TRUE)
    if ("scwbEngineSpaceFixture" %in% loadedNamespaces())
      try(unloadNamespace("scwbEngineSpaceFixture"), silent = TRUE)
    .libPaths(old_lib)
    if (!is.null(state$b)) try(wb_close_bundle(state$b), silent = TRUE)
  }
  ok <- FALSE; on.exit(if (!ok) state$close(), add = TRUE)
  lib <- file.path(root, "lib"); dir.create(lib)
  log <- file.path(root, "install.log")
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(lib)),
    shQuote(normalizePath("tests/fixtures/engine-typed-space"))), stdout = log, stderr = log)
  if (status != 0L) stop(paste(readLines(log), collapse = "\n"))
  .libPaths(c(lib, old_lib))
  wb_operation_pack_activate(system.file("scworkbench", "operation-pack.json",
    package = "scwbEngineSpaceFixture", lib.loc = lib), lib.loc = lib)
  state$b <- wb_init_bundle(file.path(root, "bundle"))
  state$cells <- paste0("c", seq_len(65L)); wb_define_cells(state$b, state$cells)
  state$values <- matrix(as.double(seq_len(65L * 5L)), 65L,
    dimnames = list(state$cells, paste0("d", 1:5)))
  wb_add_space(state$b, "source", state$values, source = "contract")
  row <- scworkbench:::.wb_space_payload_registry_row(state$b, "source")
  state$path <- scworkbench:::.wb_space_payload_path(state$b, row, must_exist = TRUE)
  workspace <- file.path(root, "sessions"); dir.create(workspace)
  state$new <- function(id) {
    s <- wb_session_create(state$b, workspace_root = workspace, session_id = id)
    state$sessions[[length(state$sessions) + 1L]] <- s
    s
  }
  state$run <- function(s, chunk = 8L) {
    result <- wb_session_run_op(s, state$b, "enginespacefixture::row_sum",
      inputs = list(source = "source", chunk_size = as.integer(chunk)))
    state$sessions[[length(state$sessions) + 1L]] <- result$session
    result
  }
  ok <- TRUE; state
}

.engine_native_boundary_plan_fixture <- function() {
  root <- tempfile("engine_native_plan_"); b <- wb_init_bundle(root)
  ok <- FALSE
  on.exit(if (!ok) {try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE)}, add = TRUE)
  cells <- paste0("c", 1:5); wb_define_cells(b, cells)
  wb_add_space(b, "source", matrix(as.double(1:15), 5L,
    dimnames = list(cells, c("a", "b", "c"))))
  plan <- scworkbench:::.wb_space_payload_reader(b, "source")
  record <- list(name = "source", descriptor = list(kind = "space", literal = "issued"))
  grant <- list(name = "read_source", input_name = "source",
    source_reference = list(space_id = "source"), selected_axis = cells)
  attr(grant, "operation_pack_v3_cells") <- cells
  request <- list(inputs = list(record), typed_space_grants = list(grant))
  attr(request, "operation_pack_v3_typed_space_values") <- list(read_source = list(
    cells = cells, input = list(space_id = "source", cell_id = cells,
      dimensions = plan$dimensions), issued_grant = grant,
    issued_input_record = list(record), plan = plan))
  ok <- TRUE
  list(root = root, b = b, plan = plan, request = request,
    close = function() {plan$close(); try(wb_close_bundle(b), silent = TRUE); unlink(root, recursive = TRUE)})
}

test_engine_native_input_executor_two_hash_boundaries_contract <- function() {
  if (!requireNamespace("rhdf5", quietly = TRUE)) return(contract_test_skip("rhdf5 unavailable"))
  f <- .engine_native_boundary_fixture(); on.exit(f$close(), add = TRUE)
  observed <- new.env(parent = emptyenv()); observed$count <- 0L; observed$path <- normalizePath(f$path)
  saved <- options(scworkbench.native_boundary_hashes = observed)
  on.exit(options(saved), add = TRUE)
  trace(".wb_prov_sha256_file", where = asNamespace("scworkbench"), print = FALSE,
    tracer = quote({.o <- getOption("scworkbench.native_boundary_hashes")
      if (identical(normalizePath(path, mustWork = FALSE), .o$path)) .o$count <- .o$count + 1L}))
  on.exit(untrace(".wb_prov_sha256_file", where = asNamespace("scworkbench")), add = TRUE, after = FALSE)
  outputs <- list()
  for (chunk in c(8L, 2L)) {
    s <- f$new(paste0("boundary_", chunk)); observed$count <- 0L
    result <- f$run(s, chunk)
    stopifnot(observed$count == 2L,
      identical(result$run$outputs$sums$cell_id, f$cells),
      identical(as.numeric(result$run$outputs$sums$value), as.numeric(rowSums(f$values))))
    outputs[[length(outputs) + 1L]] <- result$run$outputs$sums
  }
  stopifnot(identical(outputs[[1L]], outputs[[2L]]))
  TRUE
}

test_engine_native_input_private_binding_and_full_default_contract <- function() {
  f <- .engine_native_boundary_plan_fixture(); on.exit(f$close(), add = TRUE)
  auth <- scworkbench:::.wb_operation_pack_v3_native_space_sources_authenticate
  stopifnot(identical(auth(f$b, f$request, .native_middle = TRUE), "read_source"),
    identical(auth(f$b, f$request), "read_source"))
  for (field in c("name", "source_reference", "selected_axis")) {
    bad <- f$request; bad$typed_space_grants[[1L]][[field]] <- "substituted"
    stopifnot(inherits(try(auth(f$b, bad, .native_middle = TRUE), silent = TRUE), "try-error"))
  }
  bad <- f$request; bad$inputs[[1L]]$descriptor$literal <- "substituted"
  stopifnot(inherits(try(auth(f$b, bad, .native_middle = TRUE), silent = TRUE), "try-error"))
  # Both declarations share one real plan, but neither binding may be skipped.
  shared <- f$request; second <- shared$typed_space_grants[[1L]]; second$name <- "second"
  shared$typed_space_grants[[2L]] <- second
  map <- attr(shared, "operation_pack_v3_typed_space_values")
  map$second <- map$read_source; map$second$issued_grant <- second
  attr(shared, "operation_pack_v3_typed_space_values") <- map
  stopifnot(identical(auth(f$b, shared, .native_middle = TRUE), c("read_source", "second")))
  for (index in 1:2) {
    bad <- shared; bad$typed_space_grants[[index]]$selected_axis <- "substituted"
    stopifnot(inherits(try(auth(f$b, bad, .native_middle = TRUE), silent = TRUE), "try-error"))
  }
  bad <- shared; bad$typed_space_grants <- bad$typed_space_grants[1L]
  stopifnot(inherits(try(auth(f$b, bad, .native_middle = TRUE), silent = TRUE), "try-error"))
  foreign_root <- file.path(f$root, "foreign-root"); dir.create(foreign_root)
  retargeted <- f$b; retargeted$dir <- foreign_root
  stopifnot(inherits(try(auth(retargeted, f$request, .native_middle = TRUE), silent = TRUE), "try-error"))
  other <- DBI::dbConnect(RSQLite::SQLite(), DBI::dbGetQuery(f$b$con, "PRAGMA database_list;")$file[[1L]])
  on.exit(if (DBI::dbIsValid(other)) DBI::dbDisconnect(other), add = TRUE, after = FALSE)
  replacement <- f$b; replacement$con <- other
  stopifnot(inherits(try(auth(replacement, f$request, .native_middle = TRUE), silent = TRUE), "try-error"))
  plain <- f$request; attr(plain, "operation_pack_v3_typed_space_values") <- NULL
  stopifnot(identical(auth(f$b, plain, .native_middle = TRUE), character()))
  DBI::dbBegin(f$b$con); DBI::dbExecute(f$b$con, "UPDATE spaces SET description='changed'")
  rejected <- inherits(try(auth(f$b, f$request, .native_middle = TRUE), silent = TRUE), "try-error")
  DBI::dbRollback(f$b$con); stopifnot(rejected)
  f$plan$close()
  stopifnot(inherits(try(auth(f$b, f$request, .native_middle = TRUE), silent = TRUE), "try-error"))
  TRUE
}

test_engine_native_input_initial_authentication_window_contract <- function() {
  f <- .engine_native_boundary_plan_fixture(); on.exit(f$close(), add = TRUE)
  observed <- new.env(parent = emptyenv()); observed$done <- FALSE; observed$b <- f$b
  saved <- options(scworkbench.native_boundary_initial_window = observed)
  on.exit(options(saved), add = TRUE)
  # Real SHA completes, then actual SQL changes before reader construction
  # returns. The old post-hash baseline would adopt this changed metadata.
  trace(".wb_prov_sha256_file", where = asNamespace("scworkbench"), print = FALSE,
    exit = quote({.o <- getOption("scworkbench.native_boundary_initial_window")
      if (!.o$done) {.o$done <- TRUE
        DBI::dbExecute(.o$b$con, "UPDATE spaces SET description='during-initial-sha'")}}))
  on.exit(untrace(".wb_prov_sha256_file", where = asNamespace("scworkbench")), add = TRUE, after = FALSE)
  budget <- scworkbench:::.wb_operation_pack_v3_broker_projection_budget(f$b)
  held <- budget$used
  bad <- try(scworkbench:::.wb_space_payload_reader(f$b, "source", .budget = budget), silent = TRUE)
  stopifnot(observed$done, inherits(bad, "try-error"), budget$used == held)
  TRUE
}

test_engine_native_input_final_actual_bytes_with_hidden_observation_contract <- function() {
  f <- .engine_native_boundary_plan_fixture(); on.exit(f$close(), add = TRUE)
  # Explicit fault model: hide file-stat changes ONLY in an isolated copy of
  # the reader's environment. Actual file SHA/HDF and original helper are not
  # replaced. This proves final bytes remain authority, not OS spoofability.
  reader <- scworkbench:::.wb_space_payload_reader
  env <- new.env(parent = environment(reader))
  env$file.info <- local({ original <- base::file.info; frozen <- NULL
    function(...) {if (is.null(frozen)) frozen <<- original(...); frozen} })
  environment(reader) <- env
  plan <- reader(f$b, "source"); on.exit(plan$close(), add = TRUE, after = FALSE)
  request <- f$request; map <- attr(request, "operation_pack_v3_typed_space_values")
  map$read_source$plan <- plan; attr(request, "operation_pack_v3_typed_space_values") <- map
  row <- scworkbench:::.wb_space_payload_registry_row(f$b, "source")
  path <- scworkbench:::.wb_space_payload_path(f$b, row, must_exist = TRUE)
  rhdf5::h5write(12345, path, "coordinates", index = list(1L, 1L))
  auth <- scworkbench:::.wb_operation_pack_v3_native_space_sources_authenticate
  stopifnot(identical(auth(f$b, request, .native_middle = TRUE), "read_source"),
    inherits(try(auth(f$b, request), silent = TRUE), "try-error"))
  TRUE
}

test_engine_native_input_executor_rollback_receipt_retry_contract <- function() {
  f <- .engine_native_boundary_fixture(); on.exit(f$close(), add = TRUE)
  s <- f$new("rollback")
  s <- scworkbench:::.wb_session_stage_bundle(f$b, s)$session
  f$sessions[[length(f$sessions) + 1L]] <- s
  stage_before <- function(b) {
    paths <- sort(list.files(b$dir, recursive = TRUE, all.files = TRUE,
      no.. = TRUE, full.names = TRUE))
    main <- DBI::dbGetQuery(b$con, "PRAGMA database_list;")
    main <- main$file[main$name == "main"][[1L]]
    payloads <- paths[!paths %in% c(main, paste0(main, c("-shm", "-wal")))]
    list(sql = scworkbench:::.wb_manifest_registry_snapshot(b$con),
      files = substring(paths, nchar(b$dir) + 2L),
      payload_sha = stats::setNames(vapply(payloads, scworkbench:::.wb_prov_sha256_file,
        character(1)), substring(payloads, nchar(b$dir) + 2L)))
  }
  registry <- scworkbench:::.wb_manifest_registry_snapshot(f$b$con)
  transition_files <- function() sort(list.files(file.path(f$b$dir, "operation_pack_v2"),
    recursive = TRUE, all.files = TRUE, no.. = TRUE))
  before <- transition_files()
  for (event in c("staged", "receipt_received")) {
    saved <- options(scworkbench.operation_pack_v2_test_hook = local({target <- event
      function(event, ...) if (identical(event, target)) stop("native boundary rollback fault") }))
    failure <- try(f$run(s), silent = TRUE); options(saved)
    stopifnot(inherits(failure, "try-error"), length(s$runs) == 0L,
      identical(before, transition_files()),
      identical(registry, scworkbench:::.wb_manifest_registry_snapshot(f$b$con)))
  }
  observed <- new.env(parent = emptyenv()); observed$bundle <- NULL
  observed$before_dispatch <- FALSE; observed$middle_calls <- 0L; observed$substitute <- NULL
  saved_observed <- options(scworkbench.native_boundary_executor = observed)
  on.exit(options(saved_observed), add = TRUE)
  trace(".wb_operation_pack_v2_execute", where = asNamespace("scworkbench"),
    print = FALSE, tracer = quote({.o <- getOption("scworkbench.native_boundary_executor")
      .o$bundle <- bundle}))
  on.exit(untrace(".wb_operation_pack_v2_execute", where = asNamespace("scworkbench")),
    add = TRUE, after = FALSE)
  trace(".wb_operation_pack_v3_native_space_sources_authenticate", where = asNamespace("scworkbench"),
    print = FALSE, tracer = quote({.o <- getOption("scworkbench.native_boundary_executor")
      if (isTRUE(.native_middle)) {
        .o$middle_calls <- .o$middle_calls + 1L
        if (identical(.o$substitute, "input")) request$inputs[[1L]]$descriptor$kind <- "changed"
        if (identical(.o$substitute, "grant")) request$typed_space_grants[[1L]]$source_reference$space_id <- "changed"
        if (identical(.o$substitute, "drop")) request$typed_space_grants <- list()
      }}))
  on.exit(untrace(".wb_operation_pack_v3_native_space_sources_authenticate",
    where = asNamespace("scworkbench")), add = TRUE, after = FALSE)
  original_stage <- stage_before(s$staging_bundle)
  saved <- options(scworkbench.operation_pack_v2_test_hook = function(event, ...) {
    if (identical(event, "before_dispatch")) observed$before_dispatch <- TRUE
    if (identical(event, "staged")) {
      stopifnot(!is.null(observed$bundle),
        !identical(observed$bundle$con@ref, f$b$con@ref))
      observed$description <- DBI::dbGetQuery(observed$bundle$con,
        "SELECT description FROM spaces WHERE space_id='source'")$description[[1L]]
      DBI::dbExecute(observed$bundle$con,
        "UPDATE spaces SET description='changed-before-dispatch'")
    }
  })
  failed <- try(f$run(s), silent = TRUE); options(saved)
  # Source mutation is deliberate test-owned work; restore it explicitly.
  DBI::dbExecute(observed$bundle$con, "UPDATE spaces SET description=? WHERE space_id='source'",
    params = list(observed$description))
  stopifnot(inherits(failed, "try-error"), observed$middle_calls == 1L,
    !observed$before_dispatch, length(s$runs) == 0L,
    identical(before, transition_files()), identical(original_stage, stage_before(observed$bundle)))
  for (field in c("input", "grant", "drop")) {
    observed$substitute <- field; observed$middle_calls <- 0L; observed$before_dispatch <- FALSE
    saved <- options(scworkbench.operation_pack_v2_test_hook = function(event, ...) {
      if (identical(event, "before_dispatch")) observed$before_dispatch <- TRUE
    })
    failed <- try(f$run(s), silent = TRUE); options(saved)
    stopifnot(inherits(failed, "try-error"), observed$middle_calls == 1L,
      !observed$before_dispatch, length(s$runs) == 0L,
      identical(original_stage, stage_before(observed$bundle)))
  }
  observed$substitute <- NULL
  backup <- file.path(f$root, "source-before-mutation.h5")
  stopifnot(file.copy(f$path, backup))
  saved <- options(scworkbench.operation_pack_v2_test_hook = function(event, ...) {
    if (identical(event, "receipt_received"))
      rhdf5::h5write(9999, f$path, "coordinates", index = list(1L, 1L))
  })
  failed <- try(f$run(s), silent = TRUE); options(saved)
  stopifnot(inherits(failed, "try-error"), length(s$runs) == 0L,
    identical(before, transition_files()),
    identical(registry, scworkbench:::.wb_manifest_registry_snapshot(f$b$con)),
    file.copy(backup, f$path, overwrite = TRUE))
  result <- f$run(s)
  stopifnot(identical(as.numeric(result$run$outputs$sums$value), as.numeric(rowSums(f$values))))
  TRUE
}

test_engine_native_input_matrix_private_and_full_fallback_contract <- function() {
  fixtures <- new.env(parent = asNamespace("scworkbench"))
  sys.source("tests/test_engine_broker_streaming_contract.R", fixtures)
  f <- fixtures$.engine_broker_fixture()
  on.exit(fixtures$.engine_broker_close(f), add = TRUE)
  b <- f$staged$bundle
  guard <- scworkbench:::.wb_operation_pack_matrix_light_guard(b, "counts")
  bound <- fixtures$.engine_broker_grant(f)
  guard()
  grant <- bound$grant
  record <- list(name = "matrix", descriptor = list(literal = "issued"))
  request <- list(inputs = list(record), typed_slice_grants = list(grant))
  attr(request, "operation_pack_stage_root") <- f$stage
  attr(request, "operation_pack_v3_native_matrix_issuance") <- stats::setNames(list(list(
    guard = guard, con_ref = b$con@ref, issued_grant = grant,
    bundle_dir = normalizePath(b$dir, winslash = "/", mustWork = TRUE),
    issued_input_record = list(record),
    features = attr(grant, "operation_pack_v3_features"),
    cells = attr(grant, "operation_pack_v3_cells"))), grant$name)
  check <- scworkbench:::.wb_operation_pack_v3_typed_slice_sources_assert_current
  calls <- new.env(parent = emptyenv()); calls$n <- 0L
  saved <- options(scworkbench.native_matrix_hash_calls = calls)
  on.exit(options(saved), add = TRUE)
  trace(".wb_operation_pack_v3_matrix_consumed_identity", where = asNamespace("scworkbench"),
    print = FALSE, tracer = quote({.o <- getOption("scworkbench.native_matrix_hash_calls"); .o$n <- .o$n + 1L}))
  on.exit(untrace(".wb_operation_pack_v3_matrix_consumed_identity", where = asNamespace("scworkbench")),
    add = TRUE, after = FALSE)
  stopifnot(isTRUE(check(b, request, .native_middle = TRUE)), calls$n == 0L,
    isTRUE(check(b, request)), calls$n == 1L)
  plain <- request; attr(plain, "operation_pack_v3_native_matrix_issuance") <- NULL
  stopifnot(isTRUE(check(b, plain, .native_middle = TRUE)), calls$n == 2L)
  for (field in c("name", "source_reference", "input_content_identity")) {
    bad <- request; bad$typed_slice_grants[[1L]][[field]] <- "changed"
    stopifnot(inherits(try(check(b, bad, .native_middle = TRUE), silent = TRUE), "try-error"))
  }
  bad <- request; bad$inputs[[1L]]$descriptor$literal <- "changed"
  stopifnot(inherits(try(check(b, bad, .native_middle = TRUE), silent = TRUE), "try-error"))
  foreign_root <- file.path(f$root, "foreign-root"); dir.create(foreign_root)
  retargeted <- b; retargeted$dir <- foreign_root
  stopifnot(inherits(try(check(retargeted, request, .native_middle = TRUE), silent = TRUE), "try-error"))
  DBI::dbBegin(b$con); DBI::dbExecute(b$con, "UPDATE matrices SET description='changed'")
  rejected <- inherits(try(check(b, request, .native_middle = TRUE), silent = TRUE), "try-error")
  DBI::dbRollback(b$con); stopifnot(rejected)
  TRUE
}

test_engine_native_input_matrix_executor_two_boundaries_contract <- function() {
  fixtures <- new.env(parent = asNamespace("scworkbench"))
  sys.source("tests/test_operation_pack_v3_matrix_model_boundary_contract.R", fixtures)
  f <- fixtures$.wb_phase6_matrix_fixture()
  on.exit(fixtures$.wb_phase6_matrix_cleanup(f), add = TRUE)
  count <- new.env(parent = emptyenv()); count$n <- 0L
  saved <- options(scworkbench.native_matrix_executor_count = count)
  on.exit(options(saved), add = TRUE)
  trace(".wb_operation_pack_v3_matrix_consumed_identity", where = asNamespace("scworkbench"),
    print = FALSE, tracer = quote({.o <- getOption("scworkbench.native_matrix_executor_count")
      if (identical(matrix_id, "ATAC")) .o$n <- .o$n + 1L}))
  on.exit(untrace(".wb_operation_pack_v3_matrix_consumed_identity", where = asNamespace("scworkbench")),
    add = TRUE, after = FALSE)
  result <- wb_session_run_op(wb_session_new(), f$bundle,
    "scwbv3matrixmodel::fit_matrix_model", inputs = list(matrix = "ATAC",
      n_latent = 2L, chunk_size = 2L, cell_set = "all", min_cells = 1L))
  on.exit(wb_session_discard(result$session), add = TRUE, after = FALSE)
  stopifnot(count$n == 2L, identical(sort(names(result$run$outputs)), c("model", "space", "summary")))
  # The existing generic fixture has literal method calculations; its output
  # and receipt closure are validated by the unmodified executor validators.
  TRUE
}
