test_exclusive_bundle_writer_lock_safety_closure_contract <- function() {
  root <- tempfile("scwb_writer_safety_")
  dir.create(root, recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  target <- file.path(root, "bundle")
  dir.create(target)

  lock <- scworkbench:::.wb_bundle_writer_lock_acquire(
    target, operation = "release substitution regression", timeout_seconds = 0
  )
  shared <- scworkbench:::.wb_writer_lock_path(target)
  owner <- scworkbench:::.wb_writer_lock_read_metadata(shared)
  stopifnot(
    is.list(owner), nzchar(as.character(owner$owner_token)),
    !identical(as.character(owner$owner_token), "replacement-owner")
  )
  if (identical(Sys.info()[["sysname"]], "Linux")) {
    stopifnot(
      is.list(owner$process_birth),
      identical(as.character(owner$process_birth$scheme), "linux_boot_id_proc_start_v1"),
      nzchar(as.character(owner$process_birth$fingerprint))
    )
  }

  replacement <- owner
  replacement$owner_token <- "replacement-owner"
  replacement$operation <- "replacement created during release"
  replacement$created_unix <- as.numeric(Sys.time())
  replacement$created_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6%z")
  hook_called <- FALSE
  old_hook <- getOption("scworkbench.writer_lock_test_hook")
  options(scworkbench.writer_lock_test_hook = function(event, shared_path, private_path, token) {
    if (!identical(event, "release_moved")) return(invisible(TRUE))
    hook_called <<- TRUE
    stopifnot(!dir.exists(shared_path), dir.exists(private_path))
    dir.create(shared_path)
    jsonlite::write_json(
      replacement, file.path(shared_path, "owner.json"),
      auto_unbox = TRUE, pretty = TRUE, null = "null"
    )
    invisible(TRUE)
  })
  released <- scworkbench:::.wb_bundle_writer_lock_release(lock)
  options(scworkbench.writer_lock_test_hook = old_hook)
  stopifnot(isTRUE(released), isTRUE(hook_called), dir.exists(shared))
  surviving <- scworkbench:::.wb_writer_lock_read_metadata(shared)
  stopifnot(identical(as.character(surviving$owner_token), "replacement-owner"))

  # Clean up only after atomically moving and verifying the replacement. This
  # mirrors the production ownership law and leaves no shared-path deletion in
  # the regression itself.
  cleanup <- paste0(shared, ".test-cleanup")
  stopifnot(file.rename(shared, cleanup))
  stopifnot(identical(
    as.character(scworkbench:::.wb_writer_lock_read_metadata(cleanup)$owner_token),
    "replacement-owner"
  ))
  unlink(cleanup, recursive = TRUE, force = TRUE)

  # A mismatched directory moved by acquisition-failure cleanup is restored,
  # never deleted. Both acquisition failure and normal release use this helper.
  dir.create(shared)
  jsonlite::write_json(
    replacement, file.path(shared, "owner.json"),
    auto_unbox = TRUE, pretty = TRUE, null = "null"
  )
  mismatch <- scworkbench:::.wb_writer_lock_retire_shared(
    shared, token = "not-the-owner", action = "acquire-failure-test",
    allow_pending = TRUE
  )
  stopifnot(
    !isTRUE(mismatch$ok), isTRUE(mismatch$moved), isTRUE(mismatch$restored),
    dir.exists(shared),
    identical(
      as.character(scworkbench:::.wb_writer_lock_read_metadata(shared)$owner_token),
      "replacement-owner"
    )
  )
  stopifnot(file.rename(shared, cleanup))
  unlink(cleanup, recursive = TRUE, force = TRUE)

  # PID reuse is dead when a recorded process-birth identity no longer matches.
  fingerprinted <- owner
  fingerprinted$process_birth <- list(fingerprint = "boot-a:start-a")
  reused <- scworkbench:::.wb_writer_lock_pid_status(
    fingerprinted,
    probe = function(pid) list(
      status = "live", birth_fingerprint = "boot-a:start-b",
      detail = "PID exists with a different birth identity"
    )
  )
  stopifnot(identical(reused, "dead"))
  if (identical(Sys.info()[["sysname"]], "Linux")) {
    dir.create(shared)
    fingerprinted$process_birth$fingerprint <- paste0(
      as.character(owner$process_birth$fingerprint), ":reused"
    )
    jsonlite::write_json(
      fingerprinted, file.path(shared, "owner.json"),
      auto_unbox = TRUE, pretty = TRUE, null = "null"
    )
    reused_info <- wb_bundle_writer_lock_info(target, stale_after_seconds = 3600)
    stopifnot(
      identical(reused_info$owner_status, "dead"),
      isTRUE(reused_info$stale_candidate)
    )
    recovered <- wb_recover_bundle_writer_lock(
      target,
      confirmation = "RECOVER STALE SCWORKBENCH WRITER LOCK",
      stale_after_seconds = 3600
    )
    stopifnot(identical(recovered$owner_status, "dead"), !dir.exists(shared))
  }

  # Permission-denied or otherwise ambiguous probes remain unknown. Legacy
  # metadata without a birth fingerprint retains conservative live/dead/unknown
  # behavior from an authoritative probe.
  legacy <- owner
  legacy$process_birth <- NULL
  ambiguous_probe <- function(pid) list(
    status = "unknown", birth_fingerprint = NA_character_,
    detail = "permission denied"
  )
  stopifnot(
    identical(scworkbench:::.wb_writer_lock_pid_status(legacy, ambiguous_probe), "unknown"),
    identical(scworkbench:::.wb_writer_lock_pid_status(
      legacy, function(pid) list(status = "live", birth_fingerprint = NA_character_)
    ), "live"),
    identical(scworkbench:::.wb_writer_lock_pid_status(
      legacy, function(pid) list(status = "dead", birth_fingerprint = NA_character_)
    ), "dead"),
    identical(scworkbench:::.wb_writer_lock_pid_status(fingerprinted, ambiguous_probe), "unknown")
  )
  TRUE
}

test_session_wal_snapshot_contract <- function(bundle_dir) {
  b <- wb_open_bundle(bundle_dir)
  on.exit(try(wb_close_bundle(b), silent = TRUE), add = TRUE)
  journal_mode <- scworkbench:::.wb_with_bundle_writer_lock(
    b, operation = "WAL snapshot regression setup",
    code = DBI::dbGetQuery(b$con, "PRAGMA journal_mode=WAL;")[[1]][1]
  )
  stopifnot(identical(tolower(as.character(journal_mode)), "wal"))

  set_name <- paste0("set:wal_snapshot_", Sys.getpid())
  cell_id <- wb_cells(b, "all")[[1]]
  db_rel <- as.character(b$manifest$storage$sqlite$path)[1]
  db_path <- file.path(bundle_dir, db_rel)
  root <- tempfile("scwb_wal_reader_")
  dir.create(root, recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  ready <- file.path(root, "reader.ready")
  release <- file.path(root, "reader.release")
  done <- file.path(root, "reader.done")
  log <- file.path(root, "reader.log")
  script <- file.path(root, "reader.R")
  writeLines(c(
    "args <- commandArgs(trailingOnly = TRUE)",
    "db_path <- args[[1]]; set_name <- args[[2]]; ready <- args[[3]]; release <- args[[4]]; done <- args[[5]]",
    "run <- function() {",
    "  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)",
    "  DBI::dbBegin(con)",
    "  on.exit({",
    "    if (DBI::dbIsValid(con) && RSQLite::sqliteIsTransacting(con)) try(DBI::dbRollback(con), silent = TRUE)",
    "    if (DBI::dbIsValid(con)) try(DBI::dbDisconnect(con), silent = TRUE)",
    "  }, add = TRUE)",
    "  n <- DBI::dbGetQuery(con, 'SELECT COUNT(*) AS n FROM cell_set_membership WHERE cell_set = ?;', params = list(set_name))$n[[1]]",
    "  writeLines(as.character(n), ready)",
    "  while (!file.exists(release)) Sys.sleep(0.02)",
    "  'success'",
    "}",
    "result <- tryCatch(run(), error = function(e) paste0('error: ', conditionMessage(e)))",
    "writeLines(result, done)",
    "if (!identical(result, 'success')) stop(result, call. = FALSE)"
  ), script, useBytes = TRUE)

  wait_for <- function(predicate, label, timeout = 60) {
    started <- proc.time()[["elapsed"]]
    repeat {
      if (isTRUE(predicate())) return(invisible(TRUE))
      if (proc.time()[["elapsed"]] - started >= timeout) {
        stop("Timed out waiting for ", label, call. = FALSE)
      }
      Sys.sleep(0.02)
    }
  }
  status <- system2(
    file.path(R.home("bin"), "Rscript"),
    c(script, db_path, set_name, ready, release, done),
    stdout = log, stderr = log, wait = FALSE
  )
  stopifnot(identical(as.integer(status), 0L))
  wait_for(function() file.exists(ready), "pinned WAL reader")
  stopifnot(identical(readLines(ready, warn = FALSE), "0"))
  reader_released <- FALSE
  release_reader <- function() {
    if (isTRUE(reader_released)) return(invisible(TRUE))
    writeLines("release", release)
    wait_for(function() file.exists(done), "pinned WAL reader completion")
    result <- readLines(done, warn = FALSE)
    if (!identical(result, "success")) {
      stop("Pinned WAL reader failed: ", paste(result, collapse = "\n"), "\n",
           paste(readLines(log, warn = FALSE), collapse = "\n"), call. = FALSE)
    }
    reader_released <<- TRUE
    invisible(TRUE)
  }
  on.exit(try(release_reader(), silent = TRUE), add = TRUE, after = FALSE)

  scworkbench:::.wb_with_mutation_context(
    b, route = "ingestion",
    code = wb_cell_set_add(
      b, set_name, cell_id, source = "wal_snapshot_contract",
      created_by = "contract"
    )
  )
  latest <- DBI::dbGetQuery(
    b$con,
    "SELECT COUNT(*) AS n FROM cell_set_membership WHERE cell_set = ?;",
    params = list(set_name)
  )$n[[1]]
  stopifnot(identical(as.integer(latest), 1L), file.exists(paste0(db_path, "-wal")))

  # The former main-file copy loses this committed WAL-only row while the old
  # reader pins its earlier snapshot. Prove the fixture has that property.
  plain_path <- file.path(root, "plain-main-file.sqlite")
  stopifnot(file.copy(db_path, plain_path, overwrite = FALSE))
  plain <- DBI::dbConnect(
    RSQLite::SQLite(),
    paste0("file:", normalizePath(plain_path, winslash = "/", mustWork = TRUE), "?immutable=1"),
    flags = RSQLite::SQLITE_RO
  )
  plain_n <- DBI::dbGetQuery(
    plain,
    "SELECT COUNT(*) AS n FROM cell_set_membership WHERE cell_set = ?;",
    params = list(set_name)
  )$n[[1]]
  DBI::dbDisconnect(plain)
  stopifnot(identical(as.integer(plain_n), 0L))

  staged <- scworkbench:::.wb_session_stage_bundle(b, wb_session_new())
  staged_n <- DBI::dbGetQuery(
    staged$bundle$con,
    "SELECT COUNT(*) AS n FROM cell_set_membership WHERE cell_set = ?;",
    params = list(set_name)
  )$n[[1]]
  stopifnot(
    identical(as.integer(staged_n), 1L),
    !isTRUE(wb_bundle_writer_lock_info(b)$held_by_current_process)
  )
  staged$session <- wb_session_discard(staged$session)

  # Backup verification failures fail closed and leave no private stage behind.
  stage_root <- scworkbench:::.wb_session_stage_root()
  stage_before <- sort(list.files(stage_root, full.names = TRUE, all.files = TRUE, no.. = TRUE))
  old_backup_hook <- getOption("scworkbench.session_backup_test_hook")
  options(scworkbench.session_backup_test_hook = function(...) stop("forced online-backup verification failure"))
  failed <- try(scworkbench:::.wb_session_stage_bundle(b, wb_session_new()), silent = TRUE)
  options(scworkbench.session_backup_test_hook = old_backup_hook)
  stopifnot(
    inherits(failed, "try-error"),
    grepl("forced online-backup verification failure", as.character(failed), fixed = TRUE),
    identical(
      sort(list.files(stage_root, full.names = TRUE, all.files = TRUE, no.. = TRUE)),
      stage_before
    )
  )

  release_reader()
  TRUE
}
