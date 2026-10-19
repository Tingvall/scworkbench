.engine_fresh_graph_inventory <- function(root) {
  paths <- sort(list.files(root, recursive = TRUE, all.files = TRUE, no.. = TRUE, full.names = TRUE))
  paths <- paths[!file.info(paths)$isdir]
  data.frame(path = substring(paths, nchar(root) + 2L), bytes = unname(file.info(paths)$size),
    sha256 = unname(vapply(paths, function(p) digest::digest(file = p, algo = "sha256"), "")))
}

.engine_fresh_graph_fixture <- function(code) {
  root <- tempfile("fresh_graph_handoff_"); dir.create(root)
  lib <- file.path(root, "library"); dir.create(lib)
  ns <- asNamespace("scworkbench"); registry <- scworkbench:::.wb_operation_pack_registry
  previous_packs <- registry$packs; previous_ops <- registry$operations
  old_lib <- .libPaths(); had_namespace <- "scwbGraphFixture" %in% loadedNamespaces()
  old_hooks <- options(scworkbench.graph_storage_test_hook = NULL,
    scworkbench.operation_pack_v2_test_hook = NULL)
  x <- new.env(parent = emptyenv()); x$bundle <- NULL; x$sessions <- list()
  x$undos <- list(); x$stages <- list()
  x$restore <- function() {
    for (item in rev(x$undos)) {
      unlockBinding(item$name, ns); assign(item$name, item$original, ns); lockBinding(item$name, ns)
    }
    x$undos <- list()
  }
  on.exit({
    # Restore hooks and namespace before any lifecycle cleanup. Always unlink
    # owned fixture trees even if an independent close/discard reports error.
    on.exit(unlink(root, recursive = TRUE), add = TRUE)
    options(old_hooks); x$restore()
    for (stage in x$stages) try(scworkbench:::.wb_graph_stage_discard(stage), silent = TRUE)
    for (session in x$sessions) try(wb_session_discard(session), silent = TRUE)
    try(wb_operation_pack_unload("scwbgraphfixture"), silent = TRUE)
    registry$packs <- previous_packs; registry$operations <- previous_ops
    if (!had_namespace && "scwbGraphFixture" %in% loadedNamespaces())
      try(unloadNamespace("scwbGraphFixture"), silent = TRUE)
    .libPaths(old_lib)
    if (!is.null(x$bundle) && DBI::dbIsValid(x$bundle$con)) try(wb_close_bundle(x$bundle), silent = TRUE)
  }, add = TRUE)
  source <- file.path(normalizePath("."), "tests/fixtures/operation-pack-v4-graph")
  log <- file.path(root, "install.log")
  status <- system2(file.path(R.home("bin"), "R"), c("CMD", "INSTALL",
    paste0("--library=", shQuote(lib)), shQuote(source)), stdout = log, stderr = log)
  if (status != 0L) stop(paste(readLines(log, warn = FALSE), collapse = "\n"))
  .libPaths(c(lib, old_lib))
  wb_operation_pack_activate(system.file("scworkbench", "operation-pack.json",
    package = "scwbGraphFixture", lib.loc = lib), lib.loc = lib)
  x$root <- root
  x$bundle <- wb_init_bundle(file.path(root, "source.bundle"))
  wb_define_cells(x$bundle, c("c2", "c1"))
  wb_attach_matrix(x$bundle, "RNA", Matrix::Matrix(matrix(c(1, 2, 3, 4), 2L,
    dimnames = list(c("g2", "g1"), c("c2", "c1"))), sparse = TRUE))
  x$swap <- function(name, value) {
    original <- get(name, ns)
    x$undos[[length(x$undos) + 1L]] <- list(name = name, original = original)
    unlockBinding(name, ns); assign(name, value, ns); lockBinding(name, ns)
  }
  x$run <- function(op = "matrix_to_graph", inputs = list(matrix = "RNA", cell_set = "all", min_cells = 1L)) {
    answer <- wb_session_run_op(wb_session_new(), x$bundle,
      paste0("scwbgraphfixture::", op), inputs = inputs)
    x$sessions[[length(x$sessions) + 1L]] <- answer$session
    answer
  }
  x$record <- function(run) file.path(wb_session_view(run$session)$dir, "operation_pack_v2",
    run$run$operation_pack_transition$transition_id)
  x$policy <- function() list(cache = DBI::dbGetQuery(x$bundle$con, "PRAGMA cache_size;"),
    temp = DBI::dbGetQuery(x$bundle$con, "PRAGMA temp_store;"),
    graph = x$bundle$con@ref$wb_graph_policy, graph_cache = x$bundle$con@ref$wb_graph_cache_kib)
  x$capture <- function(event, state) {
    if (identical(event, "connected")) x$stages[[length(x$stages) + 1L]] <- state
  }
  code(x)
}

.engine_fresh_graph_checked <- function(x, record) {
  checked <- scworkbench:::.wb_operation_pack_v2_record_validate(record, load_payloads = TRUE,
    .retain_graph_payload = TRUE)
  stopifnot(isTRUE(checked$ok), !is.null(checked$graph_handoff))
  x$stages[[length(x$stages) + 1L]] <- checked$graph_handoff$stage
  checked$request$request_identity <- checked$request_identity
  checked$receipt$receipt_identity <- checked$receipt_identity
  checked
}

test_engine_fresh_graph_single_import_and_default_revalidation_contract <- function() {
  .engine_fresh_graph_fixture(function(x) {
    original <- scworkbench:::.wb_graph_import_parts; calls <- 0L
    x$swap(".wb_graph_import_parts", function(...) {calls <<- calls + 1L; original(...)})
    options(scworkbench.graph_storage_test_hook = x$capture)
    before <- .engine_fresh_graph_inventory(x$bundle$dir)
    run <- x$run()
    stopifnot(calls == 1L, identical(before, .engine_fresh_graph_inventory(x$bundle$dir)))
    value <- run$run$outputs$result; stage <- attr(value, "graph_stage", exact = TRUE)
    stopifnot(!is.null(stage), !is.null(stage$handoff_bytes),
      isTRUE(scworkbench:::.wb_sqlite_aux_read_target(stage$con)$immutable),
      !any(file.exists(paste0(stage$path, c("-wal", "-shm", "-journal")))))
    expected <- wb_graph_identity(wb_prim_graph(list(list(node_id = "c2"), list(node_id = "c1")),
      list(), list(), direction_mode = "undirected"))
    stopifnot(identical(value$content_identity, expected$content_identity))
    calls <- 0L
    checked <- scworkbench:::.wb_operation_pack_v2_record_validate(x$record(run), load_payloads = TRUE)
    stopifnot(isTRUE(checked$ok), is.null(checked$graph_handoff), calls == 1L)
    x$restore()
    promoted <- wb_session_promote_current(x$bundle, run$session, outputs = "result")
    id <- promoted$promoted$artifact_id[promoted$promoted$output == "result"][[1L]]
    stopifnot(identical(vapply(wb_art_graph_slice(x$bundle, id, "nodes"), `[[`, "", "node_id"), c("c2", "c1")),
      identical(wb_art_graph_info(x$bundle, id)$content_identity, expected$content_identity))
    TRUE
  })
}

test_engine_fresh_graph_record_and_seal_tamper_contract <- function() {
  .engine_fresh_graph_fixture(function(x) {
    run <- x$run(); record <- x$record(run)
    for (target in c("request.json", "receipt.json", "outputs/result/payload.json", "outputs/result/graph.parts.ndjson")) {
      copy <- tempfile("record_copy_", tmpdir = x$root); fs::dir_copy(record, copy)
      checked <- .engine_fresh_graph_checked(x, copy)
      path <- file.path(copy, target)
      if (target %in% c("request.json", "receipt.json")) {
        raw <- jsonlite::read_json(path, simplifyVector = FALSE)
        field <- if (target == "request.json") "request_identity" else "receipt_identity"
        raw[[field]] <- NULL; raw$transition_id <- paste0(raw$transition_id, "_foreign")
        raw[[field]] <- list(scheme = checked[[field]]$scheme,
          sha256 = scworkbench:::.wb_operation_pack_sha256(raw))
        scworkbench:::.wb_operation_pack_v2_atomic_json(raw, path)
      } else cat("not-json", file = path, append = TRUE)
      item <- checked$receipt$outputs[[1L]]
      failed <- tryCatch(scworkbench:::.wb_operation_pack_v4_graph_handoff_accept(
        checked$graph_handoff, copy, item, checked$receipt, checked$request), error = identity)
      stopifnot(inherits(failed, "error"), grepl("GRAPH_PAYLOAD_INVALID", conditionMessage(failed), fixed = TRUE))
      actual <- scworkbench:::.wb_operation_pack_v2_record_validate(copy, load_payloads = TRUE)
      stopifnot(!isTRUE(actual$ok))
      if (target %in% c("request.json", "receipt.json")) {
        bound <- scworkbench:::.wb_operation_pack_v2_record_validate(copy,
          load_payloads = TRUE, .retain_graph_payload = TRUE,
          .expected_graph_identities = list(request = checked$request_identity,
            receipt = checked$receipt_identity))
        stopifnot(!isTRUE(bound$ok), identical(bound$code, "identity_mismatch"))
      }
      scworkbench:::.wb_graph_stage_discard(checked$graph_handoff$stage)
    }
    checked <- .engine_fresh_graph_checked(x, record)
    receipt <- checked$receipt
    receipt$graph_write_observations[[1L]]$complete <- FALSE
    failed <- tryCatch(scworkbench:::.wb_operation_pack_v4_graph_handoff_accept(checked$graph_handoff,
      record, receipt$outputs[[1L]], receipt, checked$request), error = identity)
    stopifnot(inherits(failed, "error"))
    TRUE
  })
}

test_engine_fresh_graph_hook_failure_cleanup_retry_contract <- function() {
  .engine_fresh_graph_fixture(function(x) {
    options(scworkbench.graph_storage_test_hook = x$capture)
    before <- .engine_fresh_graph_inventory(x$bundle$dir)
    policy <- x$policy()
    for (scenario in c("fault_before", "fault_after", "parts_before", "receipt_after")) {
      target <- if (endsWith(scenario, "before")) "before_reopened" else "reopened"
      baseline <- list.dirs(scworkbench:::.wb_session_stage_root(), recursive = FALSE)
      start <- length(x$stages)
      options(scworkbench.operation_pack_v2_test_hook = function(event, transition_id = NULL, ...) {
        if (!identical(event, target)) return(invisible(NULL))
        if (startsWith(scenario, "fault")) stop(paste0("FRESH_GRAPH_ABORT_", target))
        roots <- setdiff(list.dirs(scworkbench:::.wb_session_stage_root(), recursive = FALSE), baseline)
        files <- unlist(lapply(roots, function(root) list.files(root,
          pattern = "receipt[.]json$", recursive = TRUE, full.names = TRUE)), use.names = FALSE)
        receipt_path <- files[endsWith(files, paste0("/", transition_id, "/receipt.json"))]
        stopifnot(length(receipt_path) == 1L)
        if (identical(scenario, "parts_before")) {
          cat("not-json", file = file.path(dirname(receipt_path), "outputs/result/graph.parts.ndjson"), append = TRUE)
        } else {
          receipt <- jsonlite::read_json(receipt_path, simplifyVector = FALSE)
          identity <- receipt$receipt_identity; receipt$receipt_identity <- NULL
          receipt$transition_id <- paste0(receipt$transition_id, "_foreign")
          identity$sha256 <- scworkbench:::.wb_operation_pack_sha256(receipt)
          receipt$receipt_identity <- identity
          scworkbench:::.wb_operation_pack_v2_atomic_json(receipt, receipt_path)
        }
      })
      failure <- tryCatch(x$run(), error = identity)
      options(scworkbench.operation_pack_v2_test_hook = NULL)
      stopifnot(inherits(failure, "error"),
        if (startsWith(scenario, "fault")) grepl(paste0("FRESH_GRAPH_ABORT_", target), conditionMessage(failure), fixed = TRUE) else
          grepl("GRAPH_PAYLOAD_INVALID", conditionMessage(failure), fixed = TRUE),
        identical(before, .engine_fresh_graph_inventory(x$bundle$dir)),
        identical(policy, x$policy()),
        identical(baseline, list.dirs(scworkbench:::.wb_session_stage_root(), recursive = FALSE)),
        !any(vapply(x$stages[seq.int(start + 1L, length(x$stages))],
          function(stage) file.exists(stage$path), logical(1))))
      retry <- x$run(); stopifnot(retry$run$outputs$result$kind == "graph")
      wb_session_discard(retry$session)
      stopifnot(identical(before, .engine_fresh_graph_inventory(x$bundle$dir)), identical(policy, x$policy()))
    }
    TRUE
  })
}

test_engine_fresh_graph_private_stage_mutation_rejects_contract <- function() {
  .engine_fresh_graph_fixture(function(x) {
    options(scworkbench.graph_storage_test_hook = x$capture)
    before <- .engine_fresh_graph_inventory(x$bundle$dir); mutated <- FALSE
    options(scworkbench.operation_pack_v2_test_hook = function(event, ...) {
      if (identical(event, "reopened")) {
        candidates <- Filter(function(stage) !isTRUE(stage$closed) && !is.null(stage$handoff_bytes), x$stages)
        stopifnot(length(candidates) == 1L)
        con <- file(candidates[[1L]]$path, open = "ab"); on.exit(close(con), add = TRUE)
        writeBin(as.raw(88L), con); mutated <<- TRUE
      }
    })
    failure <- tryCatch(x$run(), error = identity)
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    stopifnot(mutated, inherits(failure, "error"),
      identical(before, .engine_fresh_graph_inventory(x$bundle$dir)),
      !any(vapply(x$stages, function(stage) file.exists(stage$path), logical(1))))
    stopifnot(x$run()$run$outputs$result$kind == "graph")
    TRUE
  })
}

test_engine_fresh_graph_eligibility_fallback_contract <- function() {
  .engine_fresh_graph_fixture(function(x) {
    run <- x$run(); record <- x$record(run)
    checked <- scworkbench:::.wb_operation_pack_v2_record_validate(record, load_payloads = TRUE)
    stopifnot(isTRUE(checked$ok), is.null(checked$graph_handoff),
      scworkbench:::.wb_operation_pack_v4_graph_handoff_eligible(checked$request, checked$receipt))
    request <- checked$request; receipt <- checked$receipt
    receipt$runtime_attestation$backend <- "python"
    stopifnot(!scworkbench:::.wb_operation_pack_v4_graph_handoff_eligible(request, receipt))
    receipt <- checked$receipt; request$graph_write_grants <- rep(request$graph_write_grants, 2L)
    stopifnot(!scworkbench:::.wb_operation_pack_v4_graph_handoff_eligible(request, receipt))
    # Size admission precedes new byte hashing, even for an invalid grant.
    grant <- checked$request$graph_write_grants[[1L]]
    grant$resource_budgets$max_staged_bytes <- "1"
    calls <- 0L
    original_hash <- scworkbench:::.wb_prov_sha256_file
    x$swap(".wb_prov_sha256_file", function(...) {
      calls <<- calls + 1L
      original_hash(...)
    })
    failure <- tryCatch(scworkbench:::.wb_operation_pack_v4_graph_record_bytes(record, grant), error = identity)
    stopifnot(inherits(failure, "error"), calls == 0L,
      grepl("GRAPH_RESOURCE_EXCEEDED", conditionMessage(failure), fixed = TRUE))
    x$restore()
    link <- file.path(x$root, "linked_record")
    stopifnot(file.symlink(record, link))
    failure <- tryCatch(scworkbench:::.wb_operation_pack_v4_graph_record_bytes(link,
      checked$request$graph_write_grants[[1L]]), error = identity)
    stopifnot(inherits(failure, "error"),
      grepl("GRAPH_PAYLOAD_INVALID", conditionMessage(failure), fixed = TRUE))
    # Eligibility-only Python/multiple-output negatives do NOT claim Python
    # graph runtime execution or a supported multi-graph fixture lifecycle.
    TRUE
  })
}

test_engine_fresh_graph_mixed_closure_late_failure_contract <- function() {
  .engine_fresh_graph_fixture(function(x) {
    seed <- x$run()
    graph_promotion <- wb_session_promote_current(x$bundle, seed$session, outputs = "result")
    graph_id <- graph_promotion$promoted$artifact_id[graph_promotion$promoted$output == "result"][[1L]]
    vector <- wb_prim_cell_vector(stats::setNames(c("B", "A"), c("c2", "c1")))
    run <- wb_new_run("metadata_cell_vector", inputs = list(cell_set = "all"), params = list(),
      outputs = list(vector = vector))
    promotion <- wb_promote_analysis(x$bundle, stats::setNames(list(run), run$run_id),
      run$run_id, outputs = "vector")
    vector_id <- promotion$promoted$artifact_id[[1L]]
    inputs <- list(source = wb_ref_artifact(graph_id, "result"),
      metadata = wb_ref_artifact(vector_id, "vector"), min_cells = 1L)
    before <- .engine_fresh_graph_inventory(x$bundle$dir)
    baseline <- list.dirs(scworkbench:::.wb_session_stage_root(), recursive = FALSE)
    options(scworkbench.graph_storage_test_hook = x$capture)
    # The hook is core-owned test instrumentation, never a path/capability made
    # available to the pack. Locate only the newly owned execution record.
    options(scworkbench.operation_pack_v2_test_hook = function(event, transition_id = NULL, ...) {
      if (identical(event, "reopened")) {
        roots <- setdiff(list.dirs(scworkbench:::.wb_session_stage_root(), recursive = FALSE), baseline)
        files <- unlist(lapply(roots, function(root) list.files(root,
          pattern = "payload[.]rds$", recursive = TRUE, full.names = TRUE)), use.names = FALSE)
        target <- files[endsWith(files, paste0("/", transition_id, "/outputs/summary/payload.rds"))]
        stopifnot(length(target) == 1L)
        writeBin(charToRaw("not-an-RDS"), target[[1L]])
      }
    })
    failed <- tryCatch(x$run("graph_and_cell_metadata", inputs), error = identity)
    options(scworkbench.operation_pack_v2_test_hook = NULL)
    stopifnot(inherits(failed, "error"), identical(before, .engine_fresh_graph_inventory(x$bundle$dir)),
      identical(baseline, list.dirs(scworkbench:::.wb_session_stage_root(), recursive = FALSE)),
      !any(vapply(x$stages, function(stage) file.exists(stage$path), logical(1))))
    retry <- x$run("graph_and_cell_metadata", inputs)
    stopifnot(identical(sort(names(retry$run$outputs)), c("result", "summary")),
      retry$run$outputs$summary$table$value == 2L)
    TRUE
  })
}
