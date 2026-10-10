test_session_snapshot_source_observation_contract <- function() {
  root <- tempfile("session_snapshot_observation_")
  bundle <- wb_init_bundle(root); session <- NULL
  on.exit({
    if (!is.null(session)) try(wb_session_discard(session), silent = TRUE)
    try(wb_close_bundle(bundle), silent = TRUE)
    unlink(root, recursive = TRUE)
  }, add = TRUE)
  wb_define_cells(bundle, c("c2", "c1"))
  wb_attach_matrix(bundle, "fixture", Matrix::Matrix(matrix(1L, 1L, 2L,
    dimnames = list("f1", c("c2", "c1"))), sparse = TRUE))
  stopifnot(wb_finalize_recipient_bundle(bundle)$ready)
  wb_close_bundle(bundle)
  bundle <- wb_open_bundle(root)
  fingerprint <- function() {
    files <- sort(list.files(root, recursive = TRUE, all.files = TRUE,
      full.names = TRUE, no.. = TRUE), method = "radix")
    files <- files[!file.info(files)$isdir]
    stats::setNames(vapply(files, function(path) digest::digest(file = path,
      algo = "sha256", serialize = FALSE), character(1)), substring(files, nchar(root) + 2L))
  }
  before <- fingerprint()
  old <- options(scworkbench.manifest_test_hook = function(final = NULL, ...) {
    if (!is.null(final) && identical(final, file.path(root, "manifest.json")))
      stop("Source authentication/snapshot must not publish a manifest")
  }, scworkbench.session_backup_test_hook = function(source_con, destination_con, destination_path) {
    stopifnot(scworkbench:::.wb_writer_lock_held(bundle))
  })
  on.exit(options(old), add = TRUE)
  identity <- scworkbench:::.wb_session_source_identity(bundle)
  stopifnot(identity$schema == "scworkbench.session_source.v2", identical(fingerprint(), before),
    !scworkbench:::.wb_writer_lock_held(bundle))
  staged <- scworkbench:::.wb_session_stage_bundle(bundle, wb_session_new())
  session <- staged$session
  stopifnot(identical(fingerprint(), before), !scworkbench:::.wb_writer_lock_held(bundle),
    identical(scworkbench:::.wb_manifest_registry_snapshot(bundle$con),
      scworkbench:::.wb_manifest_registry_snapshot(staged$bundle$con)))
  wb_session_discard(session); session <- NULL
  scratch <- scworkbench:::.wb_session_stage_root()
  stages <- sort(list.dirs(scratch, recursive = FALSE))
  options(scworkbench.session_backup_test_hook = function(...) stop("snapshot-backup-fault"))
  failed <- tryCatch(scworkbench:::.wb_session_stage_bundle(bundle, wb_session_new()), error = base::identity)
  stopifnot(inherits(failed, "error"), grepl("snapshot-backup-fault", conditionMessage(failed), fixed = TRUE),
    identical(fingerprint(), before), !scworkbench:::.wb_writer_lock_held(bundle),
    identical(sort(list.dirs(scratch, recursive = FALSE)), stages))
  options(old)
  TRUE
}

test_session_snapshot_concurrent_owner_contract <- function() {
  root <- tempfile("snapshot_concurrent_"); dir.create(root)
  target <- file.path(root, "bundle")
  bundle <- wb_init_bundle(target)
  wb_define_cells(bundle, "c1")
  wb_close_bundle(bundle); bundle <- wb_open_bundle(target)
  session <- NULL
  release <- file.path(root, "release"); ready <- file.path(root, "ready")
  log <- file.path(root, "owner.log")
  on.exit({
    file.create(release)
    if (!is.null(session)) try(wb_session_discard(session), silent = TRUE)
    try(wb_close_bundle(bundle), silent = TRUE)
    # Preserve ownership until the child's release has actually completed.
    deadline <- Sys.time() + 10
    while (wb_bundle_writer_lock_info(target)$locked && Sys.time() < deadline) Sys.sleep(0.02)
    unlink(root, recursive = TRUE)
  }, add = TRUE)
  before <- digest::digest(file = file.path(target, "manifest.json"),
    algo = "sha256", serialize = FALSE)
  system2(file.path(R.home("bin"), "Rscript"), c("--vanilla",
    shQuote("tests/fixtures/session_snapshot_lock_holder.R"), shQuote(normalizePath(".")),
    shQuote(target), shQuote(ready), shQuote(release)), stdout = log, stderr = log, wait = FALSE)
  deadline <- Sys.time() + 20
  while (!file.exists(ready) && Sys.time() < deadline) Sys.sleep(0.02)
  if (!file.exists(ready)) stop(paste(readLines(log), collapse = "\n"))
  old <- options(scworkbench.writer_lock_timeout_seconds = 0)
  on.exit(options(old), add = TRUE)
  stages <- sort(list.dirs(scworkbench:::.wb_session_stage_root(), recursive = FALSE))
  for (action in list(function() scworkbench:::.wb_session_source_identity(bundle),
      function() scworkbench:::.wb_session_stage_bundle(bundle, wb_session_new()))) {
    failed <- tryCatch(action(), error = identity)
    stopifnot(inherits(failed, "error"), grepl("Timed out", conditionMessage(failed), fixed = TRUE),
      wb_bundle_writer_lock_info(target)$locked,
      identical(sort(list.dirs(scworkbench:::.wb_session_stage_root(), recursive = FALSE)), stages),
      digest::digest(file = file.path(target, "manifest.json"), algo = "sha256", serialize = FALSE) == before)
  }
  stopifnot(file.create(release))
  deadline <- Sys.time() + 10
  while (wb_bundle_writer_lock_info(target)$locked && Sys.time() < deadline) Sys.sleep(0.02)
  stopifnot(!wb_bundle_writer_lock_info(target)$locked)
  scworkbench:::.wb_session_source_identity(bundle)
  staged <- scworkbench:::.wb_session_stage_bundle(bundle, wb_session_new()); session <- staged$session
  stopifnot(digest::digest(file = file.path(target, "manifest.json"), algo = "sha256", serialize = FALSE) == before)
  options(old)
  TRUE
}
