test_exclusive_bundle_writer_lock_contract <- function(bundle_dir) {
  repo <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  root <- tempfile("scwb_writer_lock_")
  dir.create(root, recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  target <- file.path(root, "bundle")
  dir.create(target, recursive = TRUE)
  source_entries <- list.files(bundle_dir, full.names = TRUE, all.files = TRUE, no.. = TRUE)
  stopifnot(length(source_entries) > 0L, all(file.copy(source_entries, target, recursive = TRUE)))

  b <- wb_open_bundle(target)
  on.exit(try(wb_close_bundle(b), silent = TRUE), add = TRUE)
  cells_before <- wb_cells(b, "all")
  stopifnot(length(cells_before) >= 10L)
  matrices <- wb_matrices(b)
  matrix_id <- as.character(matrices$matrix_id[1])
  features <- head(wb_feature_ids(b, matrix_id), 20L)

  worker_script <- file.path(root, "writer_worker.R")
  writeLines(c(
    "args <- commandArgs(trailingOnly = TRUE)",
    "repo <- args[[1]]; target <- args[[2]]; ready <- args[[3]]; release <- args[[4]]; done <- args[[5]]; mode <- args[[6]]",
    "devtools::load_all(repo, quiet = TRUE)",
    "state <- new.env(parent = emptyenv()); state$stage <- 'startup'",
    "run_worker <- function() {",
    "  state$stage <- 'acquire writer lock'",
    "  lock <- scworkbench:::.wb_bundle_writer_lock_acquire(target, operation = paste0('contract worker: ', mode), timeout_seconds = 3)",
    "  on.exit(scworkbench:::.wb_bundle_writer_lock_release(lock), add = TRUE)",
    "  state$stage <- 'publish ready signal'",
    "  writeLines('ready', ready)",
    "  state$stage <- 'wait for release signal'",
    "  while (!file.exists(release)) Sys.sleep(0.02)",
    "  if (identical(mode, 'crash')) Sys.sleep(120) else {",
    "    state$stage <- 'open bundle'",
    "    bundle <- wb_open_bundle(target)",
    "    on.exit(wb_close_bundle(bundle), add = TRUE)",
    "    state$stage <- paste0(mode, ' mutation')",
    "    if (identical(mode, 'manifest')) scworkbench:::.wb_with_mutation_context(bundle, route = 'ingestion', code = wb_refresh_manifest(bundle))",
    "    if (identical(mode, 'finalize')) wb_finalize_recipient_bundle(bundle)",
    "  }",
    "  'success'",
    "}",
    "result <- tryCatch(run_worker(), error = function(e) paste0('error during ', state$stage, ': ', conditionMessage(e)))",
    "writeLines(result, done)",
    "if (!identical(result, 'success')) stop(result, call. = FALSE)"
  ), worker_script, useBytes = TRUE)

  # Provisioned containers can spend more than ten seconds reopening and
  # hashing the golden bundle after the release signal.  Keep the assertion
  # bounded, but allow enough wall time for the operation itself rather than
  # turning slow storage into a false contention failure.
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
  start_worker <- function(mode) {
    tag <- paste0(mode, "_", paste(sample(letters, 8L, TRUE), collapse = ""))
    ready <- file.path(root, paste0(tag, ".ready"))
    release <- file.path(root, paste0(tag, ".release"))
    done <- file.path(root, paste0(tag, ".done"))
    log <- file.path(root, paste0(tag, ".log"))
    status <- system2(
      file.path(R.home("bin"), "Rscript"),
      c(worker_script, repo, target, ready, release, done, mode),
      stdout = log, stderr = log, wait = FALSE
    )
    stopifnot(identical(as.integer(status), 0L))
    wait_for(function() file.exists(ready), paste0(mode, " worker acquisition"))
    list(ready = ready, release = release, done = done, log = log)
  }
  release_worker <- function(worker) {
    writeLines("release", worker$release)
    wait_for(function() file.exists(worker$done), "worker completion")
    result <- readLines(worker$done, warn = FALSE)
    if (!identical(result, "success")) {
      stop(
        "Writer worker failed: ", paste(result, collapse = "\n"), "\n",
        paste(readLines(worker$log, warn = FALSE), collapse = "\n"),
        call. = FALSE
      )
    }
    wait_for(function() !isTRUE(wb_bundle_writer_lock_info(target)$locked), "writer lock release")
  }

  old_timeout <- getOption("scworkbench.writer_lock_timeout_seconds")
  options(scworkbench.writer_lock_timeout_seconds = 0.2)
  on.exit(options(scworkbench.writer_lock_timeout_seconds = old_timeout), add = TRUE)

  # Existing readers retain ordinary SQLite snapshot semantics. New recipient
  # read-only opens refuse an unstable transfer state while a writer is active.
  manifest_worker <- start_worker("manifest")
  lock_info <- wb_bundle_writer_lock_info(target)
  stopifnot(
    isTRUE(lock_info$locked), identical(lock_info$owner_status, "live"),
    !isTRUE(lock_info$held_by_current_process),
    identical(wb_cells(b, "all"), cells_before),
    !startsWith(normalizePath(lock_info$lock_path, winslash = "/", mustWork = TRUE),
                paste0(normalizePath(target, winslash = "/", mustWork = TRUE), "/"))
  )
  recipient_open <- try(wb_open_bundle(target, read_only = TRUE), silent = TRUE)
  stopifnot(inherits(recipient_open, "try-error"), grepl("writer", as.character(recipient_open), ignore.case = TRUE))
  stage_root <- scworkbench:::.wb_session_stage_root()
  stage_before <- sort(list.files(stage_root, full.names = TRUE, all.files = TRUE, no.. = TRUE))
  blocked_snapshot <- try(wb_session_run_op(
    wb_session_new(), b, "matrix_log_normalize", inputs = list(
      matrix = matrix_id, min_cells = 1L, output_matrix_id = "writer_lock_blocked",
      cell_set = "all"
    )
  ), silent = TRUE)
  stopifnot(
    inherits(blocked_snapshot, "try-error"),
    grepl("Timed out", as.character(blocked_snapshot), fixed = TRUE),
    identical(sort(list.files(stage_root, full.names = TRUE, all.files = TRUE, no.. = TRUE)), stage_before)
  )

  manifest_path <- file.path(target, "manifest.json")
  manifest_before <- unname(tools::md5sum(manifest_path))
  blocked_manifest <- try(scworkbench:::.wb_with_mutation_context(
    b, route = "ingestion", code = wb_refresh_manifest(b)
  ), silent = TRUE)
  stopifnot(
    inherits(blocked_manifest, "try-error"),
    grepl("Timed out", as.character(blocked_manifest), fixed = TRUE),
    grepl("pid=", as.character(blocked_manifest), fixed = TRUE),
    grepl("wb_recover_bundle_writer_lock", as.character(blocked_manifest), fixed = TRUE),
    identical(unname(tools::md5sum(manifest_path)), manifest_before)
  )
  release_worker(manifest_worker)
  stopifnot(file.exists(manifest_path), is.list(jsonlite::read_json(manifest_path, simplifyVector = FALSE)))

  # Promotion cannot begin its SQLite transaction or payload publication while
  # another owner holds the bundle. The failed attempt leaves no commit,
  # artifact, payload, or manifest delta; it succeeds once exclusion ends.
  session <- wb_session_new()
  executed <- wb_session_run_op(session, b, "matrix_log_normalize", inputs = list(
    matrix = matrix_id, min_cells = 1L, output_matrix_id = "writer_lock_normalized",
    cell_set = "all"
  ))
  before_counts <- c(
    commits = as.integer(DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM prov_commits;")[[1]][1]),
    artifacts = as.integer(DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM artifacts;")[[1]][1])
  )
  payload_files <- function() {
    roots <- file.path(target, c("artifact_models", "models"))
    sort(unlist(lapply(roots[dir.exists(roots)], list.files, recursive = TRUE, full.names = TRUE), use.names = FALSE))
  }
  files_before <- payload_files()
  manifest_before <- unname(tools::md5sum(manifest_path))
  promotion_worker <- start_worker("hold")
  blocked_promotion <- try(wb_session_promote_current(
    b, executed$session, outputs = "summary", name_prefix = "writer_lock_contract"
  ), silent = TRUE)
  stopifnot(inherits(blocked_promotion, "try-error"), grepl("Timed out", as.character(blocked_promotion), fixed = TRUE))
  after_counts <- c(
    commits = as.integer(DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM prov_commits;")[[1]][1]),
    artifacts = as.integer(DBI::dbGetQuery(b$con, "SELECT COUNT(*) AS n FROM artifacts;")[[1]][1])
  )
  stopifnot(
    identical(after_counts, before_counts), identical(payload_files(), files_before),
    identical(unname(tools::md5sum(manifest_path)), manifest_before)
  )
  release_worker(promotion_worker)
  promoted <- wb_session_promote_current(
    b, executed$session, outputs = "summary", name_prefix = "writer_lock_contract"
  )
  stopifnot(any(promoted$promoted$status == "ok"), nrow(wb_art_list(b)) > before_counts[["artifacts"]])

  # Recipient finalization is likewise all-or-nothing at the lock boundary.
  finalization_worker <- start_worker("hold")
  readiness_during <- wb_recipient_readiness(target)
  blocked_finalization <- try(wb_finalize_recipient_bundle(b), silent = TRUE)
  stopifnot(
    !isTRUE(readiness_during$ready), grepl("writer", readiness_during$reason, ignore.case = TRUE),
    inherits(blocked_finalization, "try-error"), grepl("Timed out", as.character(blocked_finalization), fixed = TRUE)
  )
  release_worker(finalization_worker)
  finalized <- wb_finalize_recipient_bundle(b)
  stopifnot(isTRUE(finalized$ready), isTRUE(wb_recipient_readiness(target)$ready))

  # Crash leaves the portable owner record in place. Acquisition never steals
  # it. Recovery rejects a live owner, detects the killed same-host PID, and
  # requires exact explicit confirmation before a later writer can proceed.
  crash_worker <- start_worker("crash")
  live_recovery <- try(wb_recover_bundle_writer_lock(
    target, confirmation = "RECOVER STALE SCWORKBENCH WRITER LOCK", stale_after_seconds = 0
  ), silent = TRUE)
  stopifnot(inherits(live_recovery, "try-error"), grepl("live", as.character(live_recovery), fixed = TRUE))
  crash_info <- wb_bundle_writer_lock_info(target)
  crash_pid <- as.integer(crash_info$owner$pid)
  stopifnot(is.finite(crash_pid), tools::pskill(crash_pid, signal = 9L))
  wait_for(function() identical(wb_bundle_writer_lock_info(target)$owner_status, "dead"), "crashed owner detection")
  no_automatic_steal <- try(scworkbench:::.wb_bundle_writer_lock_acquire(
    target, operation = "must not steal stale lock", timeout_seconds = 0
  ), silent = TRUE)
  bad_confirmation <- try(wb_recover_bundle_writer_lock(
    target, confirmation = "recover", stale_after_seconds = 0
  ), silent = TRUE)
  stopifnot(inherits(no_automatic_steal, "try-error"), inherits(bad_confirmation, "try-error"))
  recovered <- wb_recover_bundle_writer_lock(
    target, confirmation = "RECOVER STALE SCWORKBENCH WRITER LOCK", stale_after_seconds = 3600
  )
  stopifnot(identical(recovered$owner_status, "dead"), !isTRUE(wb_bundle_writer_lock_info(target)$locked))
  post_crash <- wb_finalize_recipient_bundle(b)
  stopifnot(isTRUE(post_crash$ready))

  # Coordination state is a sibling and is absent from recipient contents.
  bundle_files <- list.files(target, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  stopifnot(
    !any(grepl("scworkbench-writer-lock", bundle_files, fixed = TRUE)),
    !any(grepl("^\\.manifest[.]json[.](staging|backup)-", bundle_files))
  )
  TRUE
}
