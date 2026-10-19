.ecr_fixture <- function() {
  f <- new.env(parent = emptyenv())
  f$root <- tempfile("empty_capsule_recovery_")
  f$bundle <- wb_init_bundle(f$root)
  f$close <- function() {
    if (!is.null(f$bundle) && DBI::dbIsValid(f$bundle$con)) {
      if (RSQLite::sqliteIsTransacting(f$bundle$con)) DBI::dbRollback(f$bundle$con)
      try(wb_close_bundle(f$bundle), silent = TRUE)
    }
    unlink(f$root, recursive = TRUE, force = TRUE)
  }
  f
}
.ecr_inventory <- function(root) {
  paths <- sort(list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE, no.. = TRUE))
  paths <- paths[!file.info(paths)$isdir]
  data.frame(path = substring(paths, nchar(root) + 2L), bytes = file.info(paths)$size,
    sha256 = vapply(paths, function(path) digest::digest(file = path, algo = "sha256"), ""))
}
.ecr_state <- function(b) scworkbench:::.wb_manifest_registry_snapshot(b$con)
.ecr_manifest_sha <- function(b) digest::digest(file = file.path(b$dir, "manifest.json"), algo = "sha256")
.ecr_spy <- function() {
  ns <- asNamespace("scworkbench"); dbi <- asNamespace("DBI")
  saved <- list(); counters <- new.env(parent = emptyenv())
  replace <- function(where, name, value) {
    original <- get(name, where)
    saved[[length(saved) + 1L]] <<- list(where = where, name = name, original = original)
    unlockBinding(name, where); assign(name, value, where); lockBinding(name, where)
    original
  }
  reset <- function() {
    counters$builders <- 0L; counters$publishers <- 0L; counters$checkpoints <- 0L
    counters$force <- logical(); counters$held <- logical()
  }
  reset()
  original_builder <- get(".wb_bundle_build_manifest", ns)
  replace(ns, ".wb_bundle_build_manifest", function(bundle_dir, con, bundle_id,
      bundle_name, created_at, id_policy = list()) {
    counters$builders <- counters$builders + 1L
    original_builder(bundle_dir, con, bundle_id, bundle_name, created_at, id_policy)
  })
  original_publisher <- get(".wb_manifest_publish_current_locked", ns)
  replace(ns, ".wb_manifest_publish_current_locked", function(bundle_or_dir, result = NULL, force = FALSE) {
    counters$publishers <- counters$publishers + 1L
    counters$force <- c(counters$force, force)
    counters$held <- c(counters$held, scworkbench:::.wb_writer_lock_held(bundle_or_dir))
    original_publisher(bundle_or_dir, result = result, force = force)
  })
  original_query <- get("dbGetQuery", dbi)
  replace(dbi, "dbGetQuery", function(conn, statement, ...) {
    if (identical(statement, "PRAGMA wal_checkpoint(TRUNCATE);"))
      counters$checkpoints <- counters$checkpoints + 1L
    original_query(conn, statement, ...)
  })
  list(counts = counters, reset = reset, close = function() {
    for (x in rev(saved)) {
      unlockBinding(x$name, x$where); assign(x$name, x$original, x$where); lockBinding(x$name, x$where)
      stopifnot(identical(get(x$name, x$where), x$original))
    }
    saved <<- list()
  })
}
.ecr_add_pending <- function(b, name = "cap_Pending") {
  path <- file.path(b$dir, "analysis", "capsules", ".pending", name)
  dir.create(path, recursive = TRUE); writeLines("owned recovery fixture", file.path(path, "payload.txt"))
  path
}
.ecr_add_orphan <- function(b, name = "cap_Orphan", valid = TRUE) {
  path <- file.path(b$dir, "analysis", "capsules", name)
  dir.create(path, recursive = TRUE)
  jsonlite::write_json(list(schema = if (valid) "scworkbench.analysis_capsule.v1" else "foreign.v1",
    capsule_id = name), file.path(path, "manifest.json"), auto_unbox = TRUE)
  path
}

test_engine_empty_capsule_no_work_and_public_open_contract <- function() {
  f <- .ecr_fixture(); on.exit(f$close(), add = TRUE)
  spy <- .ecr_spy(); on.exit(spy$close(), add = TRUE, after = FALSE)
  b <- f$bundle
  for (empty_root in c(FALSE, TRUE)) {
    if (empty_root) dir.create(file.path(b$dir, "analysis", "capsules"), recursive = TRUE)
    state <- .ecr_state(b); before <- .ecr_inventory(b$dir); spy$reset()
    answer <- withVisible(scworkbench:::.wb_capsule_recover_residue(b))
    after <- .ecr_inventory(b$dir)
    stopifnot(identical(answer$value, list(removed_pending = 0L, removed_orphan = 0L)), answer$visible,
      identical(before, after), identical(state, .ecr_state(b)),
      spy$counts$builders == 0L, spy$counts$publishers == 0L, spy$counts$checkpoints == 0L,
      !scworkbench:::.wb_writer_lock_held(b))
  }
  stopifnot(wb_finalize_recipient_bundle(b)$ready)
  wb_close_bundle(b); f$bundle <- NULL
  spy$reset()
  f$bundle <- wb_open_bundle(f$root, read_only = FALSE, validate = FALSE)
  stopifnot(spy$counts$builders == 1L, spy$counts$publishers == 1L,
    identical(spy$counts$force, TRUE), all(spy$counts$held))
  TRUE
}

test_engine_empty_capsule_actual_cleanup_and_empty_pending_contract <- function() {
  f <- .ecr_fixture(); on.exit(f$close(), add = TRUE)
  spy <- .ecr_spy(); on.exit(spy$close(), add = TRUE, after = FALSE)
  b <- f$bundle; state <- .ecr_state(b)
  pending_root <- file.path(b$dir, "analysis", "capsules", ".pending")
  dir.create(pending_root, recursive = TRUE); spy$reset()
  answer <- scworkbench:::.wb_capsule_recover_residue(b)
  stopifnot(identical(answer, list(removed_pending = 0L, removed_orphan = 0L)),
    !dir.exists(pending_root), spy$counts$publishers == 1L, spy$counts$builders == 1L,
    identical(spy$counts$force, TRUE), all(spy$counts$held), spy$counts$checkpoints == 1L,
    identical(state, .ecr_state(b)))
  pending <- .ecr_add_pending(b); orphan <- .ecr_add_orphan(b); spy$reset()
  answer <- scworkbench:::.wb_capsule_recover_residue(b)
  stopifnot(identical(answer, list(removed_pending = 1L, removed_orphan = 1L)),
    !dir.exists(pending), !dir.exists(orphan), !dir.exists(pending_root),
    spy$counts$publishers == 1L, identical(spy$counts$force, TRUE),
    spy$counts$builders == 1L, spy$counts$checkpoints == 1L, all(spy$counts$held),
    identical(state, .ecr_state(b)), !scworkbench:::.wb_writer_lock_held(b))
  TRUE
}

test_engine_empty_capsule_invalid_paths_and_unlink_failure_contract <- function() {
  f <- .ecr_fixture(); on.exit(f$close(), add = TRUE)
  spy <- .ecr_spy(); on.exit(spy$close(), add = TRUE, after = FALSE)
  b <- f$bundle
  for (kind in c("foreign_pending", "foreign_orphan", "bad_manifest")) {
    path <- if (kind == "foreign_pending") .ecr_add_pending(b, "foreign") else
      .ecr_add_orphan(b, if (kind == "foreign_orphan") "foreign" else "cap_Bad", valid = FALSE)
    before <- .ecr_inventory(b$dir); spy$reset()
    failed <- try(scworkbench:::.wb_capsule_recover_residue(b), silent = TRUE)
    stopifnot(inherits(failed, "try-error"), grepl("CAPSULE_RESIDUE_RECOVERY_REFUSED", as.character(failed), fixed = TRUE),
      dir.exists(path), identical(before, .ecr_inventory(b$dir)), spy$counts$publishers == 0L,
      !scworkbench:::.wb_writer_lock_held(b))
    unlink(path, recursive = TRUE)
    scworkbench:::.wb_capsule_recover_residue(b)
  }
  pending <- .ecr_add_pending(b); invalid <- .ecr_add_orphan(b, "cap_Invalid", valid = FALSE)
  spy$reset(); failed <- try(scworkbench:::.wb_capsule_recover_residue(b), silent = TRUE)
  stopifnot(inherits(failed, "try-error"), !dir.exists(pending), dir.exists(invalid),
    spy$counts$publishers == 0L, !scworkbench:::.wb_writer_lock_held(b))
  unlink(invalid, recursive = TRUE)
  scworkbench:::.wb_capsule_recover_residue(b)
  outside <- tempfile("capsule_external_owned_"); dir.create(outside)
  on.exit(unlink(outside, recursive = TRUE), add = TRUE)
  writeLines("untouched", file.path(outside, "payload.txt"))
  link <- file.path(b$dir, "analysis", "capsules", ".pending")
  stopifnot(file.symlink(outside, link))
  outside_before <- .ecr_inventory(outside); spy$reset()
  failed <- try(scworkbench:::.wb_capsule_recover_residue(b), silent = TRUE)
  stopifnot(inherits(failed, "try-error"), identical(outside_before, .ecr_inventory(outside)),
    identical(Sys.readlink(link), outside), spy$counts$publishers == 0L)
  unlink(link)
  # Exact installed helper with a lexical unlink fault; no production hook.
  for (empty in c(FALSE, TRUE)) {
    target <- if (empty) {
      dir.create(link, recursive = TRUE); link
    } else .ecr_add_pending(b)
    recover <- scworkbench:::.wb_capsule_recover_residue
    fault <- new.env(parent = environment(recover)); fault$unlink <- function(...) 1L
    environment(recover) <- fault; before <- .ecr_inventory(b$dir); spy$reset()
    failed <- try(recover(b), silent = TRUE)
    stopifnot(inherits(failed, "try-error"), grepl("CAPSULE_RESIDUE_RECOVERY_FAILED", as.character(failed), fixed = TRUE),
      dir.exists(target), identical(before, .ecr_inventory(b$dir)), spy$counts$publishers == 0L,
      !scworkbench:::.wb_writer_lock_held(b))
    scworkbench:::.wb_capsule_recover_residue(b)
    stopifnot(!dir.exists(target))
  }
  TRUE
}

test_engine_empty_capsule_nested_transaction_and_readonly_contract <- function() {
  f <- .ecr_fixture(); on.exit(f$close(), add = TRUE)
  spy <- .ecr_spy(); on.exit(spy$close(), add = TRUE, after = FALSE)
  b <- f$bundle
  lock <- scworkbench:::.wb_bundle_writer_lock_acquire(b, operation = "caller-owned capsule fixture")
  on.exit(scworkbench:::.wb_bundle_writer_lock_release(lock), add = TRUE, after = FALSE)
  key <- scworkbench:::.wb_writer_lock_key(b)
  held <- get(key, scworkbench:::.wb_writer_lock_state$held)
  snapshot <- list(token = held$token, depth = held$depth)
  scworkbench:::.wb_capsule_recover_residue(b)
  held <- get(key, scworkbench:::.wb_writer_lock_state$held)
  stopifnot(identical(snapshot, list(token = held$token, depth = held$depth)), spy$counts$publishers == 0L)
  DBI::dbBegin(b$con)
  on.exit(if (DBI::dbIsValid(b$con) && RSQLite::sqliteIsTransacting(b$con)) DBI::dbRollback(b$con), add = TRUE, after = FALSE)
  scworkbench:::.wb_capsule_recover_residue(b)
  stopifnot(RSQLite::sqliteIsTransacting(b$con), spy$counts$publishers == 0L)
  held <- get(key, scworkbench:::.wb_writer_lock_state$held)
  stopifnot(identical(snapshot, list(token = held$token, depth = held$depth)))
  DBI::dbRollback(b$con)
  scworkbench:::.wb_bundle_writer_lock_release(lock)
  # Without an existing owner, the old route rejects lock acquisition first.
  DBI::dbBegin(b$con); spy$reset()
  failed <- try(scworkbench:::.wb_capsule_recover_residue(b), silent = TRUE)
  stopifnot(inherits(failed, "try-error"), grepl("Exclusive bundle-writer lock must be acquired before opening a SQLite transaction", as.character(failed), fixed = TRUE),
    RSQLite::sqliteIsTransacting(b$con), spy$counts$publishers == 0L,
    !scworkbench:::.wb_writer_lock_held(b))
  DBI::dbRollback(b$con)
  stopifnot(wb_finalize_recipient_bundle(b)$ready)
  wb_close_bundle(b); f$bundle <- wb_open_bundle(f$root, read_only = TRUE)
  before <- .ecr_inventory(f$root); spy$reset()
  failed <- try(scworkbench:::.wb_capsule_recover_residue(f$bundle), silent = TRUE)
  stopifnot(inherits(failed, "try-error"), grepl("read_only=TRUE", as.character(failed), fixed = TRUE),
    identical(before, .ecr_inventory(f$root)), spy$counts$publishers == 0L)
  TRUE
}

test_engine_empty_capsule_publication_failure_and_explicit_retry_contract <- function() {
  f <- .ecr_fixture(); on.exit(f$close(), add = TRUE)
  spy <- .ecr_spy(); on.exit(spy$close(), add = TRUE, after = FALSE)
  b <- f$bundle; pending <- .ecr_add_pending(b); state <- .ecr_state(b); old_sha <- .ecr_manifest_sha(b)
  lock <- scworkbench:::.wb_bundle_writer_lock_acquire(b, operation = "outer publication-fault fixture")
  on.exit(scworkbench:::.wb_bundle_writer_lock_release(lock), add = TRUE, after = FALSE)
  key <- scworkbench:::.wb_writer_lock_key(b); held <- get(key, scworkbench:::.wb_writer_lock_state$held)
  snapshot <- list(token = held$token, depth = held$depth)
  saved <- options(scworkbench.manifest_test_hook = function(event, ...) {
    if (identical(event, "before_publish")) stop("capsule fixture publication failure")
  })
  on.exit(options(saved), add = TRUE, after = FALSE)
  spy$reset(); failed <- try(scworkbench:::.wb_capsule_recover_residue(b), silent = TRUE)
  held <- get(key, scworkbench:::.wb_writer_lock_state$held)
  stopifnot(inherits(failed, "try-error"), grepl("capsule fixture publication failure", as.character(failed), fixed = TRUE),
    !dir.exists(pending), identical(state, .ecr_state(b)), identical(old_sha, .ecr_manifest_sha(b)),
    identical(snapshot, list(token = held$token, depth = held$depth)),
    spy$counts$publishers == 1L, identical(spy$counts$force, TRUE), spy$counts$checkpoints == 0L)
  options(saved)
  scworkbench:::.wb_bundle_writer_lock_release(lock)
  stopifnot(!scworkbench:::.wb_writer_lock_held(b))
  # Cleanup is irreversible; explicit manifest refresh completes publication.
  wb_refresh_manifest(b)
  stopifnot(identical(state, .ecr_state(b)), !scworkbench:::.wb_writer_lock_held(b))
  spy$reset(); answer <- scworkbench:::.wb_capsule_recover_residue(b)
  stopifnot(identical(answer, list(removed_pending = 0L, removed_orphan = 0L)),
    spy$counts$publishers == 0L, !scworkbench:::.wb_writer_lock_held(b))
  TRUE
}
