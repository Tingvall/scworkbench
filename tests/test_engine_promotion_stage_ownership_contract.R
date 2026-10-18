.engine_stage_ownership_fixture <- function() {
  root <- tempfile("promotion_stage_owner_")
  dir.create(root)
  b <- wb_init_bundle(file.path(root, "destination.bundle"))
  cells <- paste0("cell_", seq_len(12L))
  wb_define_cells(b, cells, metadata = data.frame(cell_id = cells,
    group = rep(c("a", "b"), 6L)))
  wb_add_space(b, "source.pca", matrix(seq_len(48L) / 10, 12L,
    dimnames = list(cells, paste0("PC", 1:4))), source = "contract")
  fit <- wb_session_run_op(wb_session_create(b, file.path(root, "sessions"),
    "stage_ownership"), b, "scwbv3phase5::fit_sibling_model", inputs = list(
      source = "source.pca", cell_set = "all", min_cells = 1L, dims = 1:4))
  list(root = root, bundle = b, session = fit$session, run = fit$run)
}

.engine_stage_ownership_worker <- function(fixture, mode) {
  script <- file.path(fixture$root, paste0("worker_", mode, ".R"))
  ready <- file.path(fixture$root, paste0(mode, ".ready"))
  release <- file.path(fixture$root, paste0(mode, ".release"))
  log <- file.path(fixture$root, paste0(mode, ".log"))
  writeLines(c(
    "args <- commandArgs(trailingOnly=TRUE)",
    ".libPaths(c(args[[1]], .libPaths()))",
    "suppressPackageStartupMessages(library(scworkbench))",
    "main <- function() {",
    "  if (args[[5]] == 'probe') {",
    "    answer <- tryCatch(scworkbench:::.wb_bundle_writer_lock_acquire(args[[2]], operation='concurrent stage mutation probe', timeout_seconds=0), error=identity)",
    "    if (!inherits(answer, 'error')) { scworkbench:::.wb_bundle_writer_lock_release(answer); stop('Stage writer unexpectedly admitted') }",
    "    stopifnot(grepl('writer.lock|writer-lock', conditionMessage(answer)))",
    "    cat('STAGE_MUTATION_BLOCKED\\n'); return(invisible(TRUE))",
    "  }",
    "  lock <- scworkbench:::.wb_bundle_writer_lock_acquire(args[[2]], operation='concurrent stage mutation owner', timeout_seconds=0)",
    "  on.exit(scworkbench:::.wb_bundle_writer_lock_release(lock), add=TRUE)",
    "  stopifnot(file.create(args[[3]]))",
    "  deadline <- Sys.time()+30",
    "  while (!file.exists(args[[4]])) { if (Sys.time()>deadline) stop('Release deadline'); Sys.sleep(0.02) }",
    "  cat('STAGE_OWNER_RELEASED\\n')",
    "}",
    "main()"), script)
  process <- processx::process$new(file.path(R.home("bin"), "Rscript"),
    args = c(script, dirname(find.package("scworkbench")),
      fixture$session$staging_bundle$dir, ready, release, mode),
    stdout = log, stderr = log, cleanup_tree = TRUE)
  list(process = process, ready = ready, release = release, log = log)
}

.engine_stage_ownership_wait <- function(worker, ready = FALSE) {
  start <- proc.time()[["elapsed"]]
  while (if (ready) !file.exists(worker$ready) else worker$process$is_alive()) {
    if (proc.time()[["elapsed"]] - start > 30 ||
        (ready && !worker$process$is_alive())) stop(paste(
      "Stage worker failed:", paste(readLines(worker$log, warn = FALSE),
        collapse = "\n")))
    Sys.sleep(.02)
  }
  if (!ready) stopifnot(worker$process$get_exit_status() == 0L)
  invisible(TRUE)
}

.engine_stage_ownership_destination <- function(b) {
  tables <- sort(DBI::dbListTables(b$con))
  counts <- vapply(tables, function(table) as.numeric(DBI::dbGetQuery(b$con,
    paste0("SELECT COUNT(*) FROM ", DBI::dbQuoteIdentifier(b$con, table),
      ";"))[[1L]]), numeric(1))
  list(tables = tables, counts = counts,
    manifest = digest::digest(file = file.path(b$dir, "manifest.json"),
      algo = "sha256"), paths = sort(list.files(b$dir, recursive = TRUE,
        all.files = TRUE, include.dirs = TRUE, no.. = TRUE)))
}

.engine_stage_ownership_tree <- function(bundle, model) {
  path <- model$model_tree_root
  if (is.null(path) || !length(path) || !nzchar(path[[1L]])) path <- model$model_path
  path <- as.character(path)[[1L]]
  if (!scworkbench:::.wb_path_is_absolute(path)) path <- file.path(bundle$dir, path)
  stopifnot(dir.exists(path))
  files <- sort(list.files(path, recursive = TRUE, all.files = TRUE,
    no.. = TRUE, include.dirs = FALSE))
  stopifnot(length(files) > 0L)
  data.frame(path = files, size = as.numeric(file.info(file.path(path, files))$size),
    sha256 = vapply(file.path(path, files), function(file)
      digest::digest(file = file, algo = "sha256"), character(1)),
    stringsAsFactors = FALSE, row.names = NULL)
}

.engine_stage_ownership_check_publication <- function(fixture, promoted,
                                                     stage_manifest, source_tree) {
  stage <- fixture$session$staging_bundle
  stopifnot(identical(stage_manifest, digest::digest(
    file = file.path(stage$dir, "manifest.json"), algo = "sha256")))
  model_ids <- as.character(promoted$promoted$artifact_id[
    promoted$promoted$output == "model" & promoted$promoted$status == "ok"])
  stopifnot(length(model_ids) == 1L)
  model <- wb_art_load(fixture$bundle, model_ids[[1L]], expected_kind = "model_ref")
  stopifnot(startsWith(normalizePath(model$model_path, winslash = "/",
    mustWork = TRUE), paste0(normalizePath(fixture$bundle$dir, winslash = "/",
      mustWork = TRUE), "/")),
    identical(source_tree, .engine_stage_ownership_tree(fixture$bundle, model)))
  invisible(TRUE)
}

test_engine_promotion_stage_verification_copy_ownership_contract <- function() {
  contract_test_activate_phase5_conformance_pack()
  on.exit(contract_test_deactivate_phase5_conformance_pack(), add = TRUE)
  fixture <- .engine_stage_ownership_fixture()
  on.exit({ try(wb_session_discard(fixture$session), silent = TRUE)
    try(wb_close_bundle(fixture$bundle), silent = TRUE)
    unlink(fixture$root, recursive = TRUE) }, add = TRUE)
  stage_manifest <- digest::digest(file = file.path(
    fixture$session$staging_bundle$dir, "manifest.json"), algo = "sha256")
  source_tree <- .engine_stage_ownership_tree(fixture$session$staging_bundle,
    fixture$run$outputs$model)
  state <- new.env(parent = emptyenv()); state$seen <- character()
  old <- getOption("engine.stage.ownership.probe")
  options(engine.stage.ownership.probe = function(phase) {
    stopifnot(scworkbench:::.wb_writer_lock_held(fixture$session$staging_bundle),
      scworkbench:::.wb_writer_lock_held(fixture$bundle))
    if (phase %in% state$seen) return(invisible(TRUE))
    worker <- .engine_stage_ownership_worker(fixture, "probe")
    on.exit(if (worker$process$is_alive()) worker$process$kill_tree(), add = TRUE)
    .engine_stage_ownership_wait(worker)
    stopifnot(any(grepl("STAGE_MUTATION_BLOCKED",
      readLines(worker$log, warn = FALSE))))
    state$seen <- c(state$seen, phase)
  })
  ns <- asNamespace("scworkbench")
  trace(".wb_session_validate_payloads", where = ns, print = FALSE,
    tracer = quote(getOption("engine.stage.ownership.probe")("verification")))
  trace(".wb_prepare_staged_payload", where = ns, print = FALSE,
    tracer = quote(getOption("engine.stage.ownership.probe")("copy")))
  on.exit({ untrace(".wb_session_validate_payloads", where = ns)
    untrace(".wb_prepare_staged_payload", where = ns)
    options(engine.stage.ownership.probe = old) }, add = TRUE)
  promoted <- wb_session_promote_current(fixture$bundle, fixture$session,
    outputs = "model")
  fixture$session <- promoted$session
  .engine_stage_ownership_check_publication(fixture, promoted, stage_manifest, source_tree)
  stopifnot(setequal(state$seen, c("verification", "copy")),
    all(promoted$promoted$status == "ok"),
    !scworkbench:::.wb_writer_lock_held(fixture$session$staging_bundle))
  TRUE
}

test_engine_promotion_stage_contention_retry_contract <- function() {
  contract_test_activate_phase5_conformance_pack()
  on.exit(contract_test_deactivate_phase5_conformance_pack(), add = TRUE)
  fixture <- .engine_stage_ownership_fixture()
  worker <- NULL
  on.exit({ if (!is.null(worker) && worker$process$is_alive())
      worker$process$kill_tree()
    try(wb_session_discard(fixture$session), silent = TRUE)
    try(wb_close_bundle(fixture$bundle), silent = TRUE)
    unlink(fixture$root, recursive = TRUE) }, add = TRUE)
  before <- .engine_stage_ownership_destination(fixture$bundle)
  stage_manifest <- digest::digest(file = file.path(
    fixture$session$staging_bundle$dir, "manifest.json"), algo = "sha256")
  source_tree <- .engine_stage_ownership_tree(fixture$session$staging_bundle,
    fixture$run$outputs$model)
  worker <- .engine_stage_ownership_worker(fixture, "hold")
  .engine_stage_ownership_wait(worker, ready = TRUE)
  start <- proc.time()[["elapsed"]]
  failure <- try(wb_session_promote_current(fixture$bundle, fixture$session,
    outputs = "model"), silent = TRUE)
  elapsed <- proc.time()[["elapsed"]] - start
  stopifnot(inherits(failure, "try-error"),
    grepl("writer.lock|writer-lock", as.character(failure)), elapsed < 5,
    identical(before, .engine_stage_ownership_destination(fixture$bundle)))
  stopifnot(file.create(worker$release))
  .engine_stage_ownership_wait(worker)
  promoted <- wb_session_promote_current(fixture$bundle, fixture$session,
    outputs = "model")
  fixture$session <- promoted$session
  .engine_stage_ownership_check_publication(fixture, promoted, stage_manifest, source_tree)
  stopifnot(all(promoted$promoted$status == "ok"),
    nrow(wb_art_list(fixture$bundle)) > 0L,
    !scworkbench:::.wb_writer_lock_held(fixture$session$staging_bundle))
  TRUE
}
