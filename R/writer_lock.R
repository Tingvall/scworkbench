# Exclusive bundle-writer locking.
#
# The lock is a sibling directory, rather than bundle content, so atomic
# directory creation provides the exclusion primitive and recipient copies do
# not inherit runtime coordination state.  All lock acquisition happens before
# SQLite transactions; nested engine writers are process-local re-entrant.

.wb_writer_lock_state <- local({
  state <- new.env(parent = emptyenv())
  state$held <- new.env(parent = emptyenv())
  state
})

.wb_writer_lock_target <- function(bundle_or_dir) {
  path <- if (inherits(bundle_or_dir, "scworkbench_bundle")) {
    bundle_or_dir$dir
  } else {
    bundle_or_dir
  }
  .wb_assert(is.character(path) && length(path) == 1L && nzchar(path),
             "bundle_or_dir must identify one bundle path")
  normalizePath(path, winslash = "/", mustWork = FALSE)
}

.wb_writer_lock_path <- function(bundle_or_dir) {
  target <- .wb_writer_lock_target(bundle_or_dir)
  file.path(dirname(target), paste0(".", basename(target), ".scworkbench-writer-lock"))
}

.wb_writer_lock_key <- function(bundle_or_dir) .wb_writer_lock_target(bundle_or_dir)

.wb_bundle_dir_from_connection <- function(con) {
  dbs <- DBI::dbGetQuery(con, "PRAGMA database_list;")
  main <- dbs[as.character(dbs$name) == "main", , drop = FALSE]
  .wb_assert(nrow(main) == 1L && nzchar(as.character(main$file[1])),
             "Cannot resolve bundle directory from SQLite connection for writer locking.")
  dirname(dirname(normalizePath(as.character(main$file[1]), winslash = "/", mustWork = TRUE)))
}

.wb_writer_lock_target_from_connection <- function(con) {
  dbs <- DBI::dbGetQuery(con, "PRAGMA database_list;")
  main <- dbs[as.character(dbs$name) == "main", , drop = FALSE]
  .wb_assert(nrow(main) == 1L && nzchar(as.character(main$file[1])),
             "Cannot resolve a durable SQLite path for writer locking.")
  db_path <- normalizePath(as.character(main$file[1]), winslash = "/", mustWork = TRUE)
  candidate <- dirname(dirname(db_path))
  if (identical(basename(dirname(db_path)), "db") &&
      file.exists(file.path(candidate, "manifest.json"))) candidate else db_path
}

.wb_writer_lock_token <- function() {
  paste0(
    Sys.getpid(), "-", format(Sys.time(), "%Y%m%d%H%M%OS6"), "-",
    paste(sample(c(letters, LETTERS, 0:9), 24L, replace = TRUE), collapse = "")
  )
}

.wb_writer_lock_metadata <- function(target, token, operation) {
  info <- Sys.info()
  list(
    schema_version = "scworkbench.bundle_writer_lock.v1",
    owner_token = token,
    bundle_path = target,
    pid = as.integer(Sys.getpid()),
    host = as.character(info[["nodename"]] %||% NA_character_),
    user = as.character(info[["user"]] %||% Sys.getenv("USER", unset = NA_character_)),
    operation = as.character(operation %||% "committed mutation")[1],
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6%z"),
    created_unix = as.numeric(Sys.time()),
    r_version = R.version.string,
    platform = R.version$platform,
    command = paste(commandArgs(), collapse = " "),
    package_version = tryCatch(as.character(utils::packageVersion("scworkbench")), error = function(e) NA_character_)
  )
}

.wb_writer_lock_write_metadata <- function(lock_path, metadata) {
  tmp <- file.path(lock_path, paste0("owner.json.tmp-", metadata$owner_token))
  final <- file.path(lock_path, "owner.json")
  jsonlite::write_json(metadata, tmp, auto_unbox = TRUE, pretty = TRUE, null = "null")
  .wb_assert(file.rename(tmp, final), "Could not atomically publish writer-lock owner metadata.")
  invisible(TRUE)
}

.wb_writer_lock_read_metadata <- function(lock_path) {
  path <- file.path(lock_path, "owner.json")
  if (!file.exists(path)) return(NULL)
  tryCatch(
    jsonlite::read_json(path, simplifyVector = TRUE),
    error = function(e) NULL
  )
}

.wb_writer_lock_pid_status <- function(metadata) {
  if (is.null(metadata)) return("unknown")
  owner_host <- as.character(metadata$host %||% "")[1]
  current_host <- as.character(Sys.info()[["nodename"]] %||% "")[1]
  pid <- suppressWarnings(as.integer(metadata$pid %||% NA_integer_)[1])
  if (!nzchar(owner_host) || !identical(owner_host, current_host) || is.na(pid) || pid < 1L) {
    return("unknown")
  }
  if (identical(pid, as.integer(Sys.getpid()))) return("live")
  if (.Platform$OS.type == "windows") {
    output <- tryCatch(
      suppressWarnings(system2("tasklist", c("/FI", shQuote(paste0("PID eq ", pid)), "/NH"), stdout = TRUE, stderr = TRUE)),
      error = function(e) character(0)
    )
    if (!length(output)) return("unknown")
    return(if (any(grepl(paste0("(^|[[:space:]])", pid, "([[:space:]]|$)"), output))) "live" else "dead")
  }
  status <- tryCatch(
    suppressWarnings(system2("kill", c("-0", as.character(pid)), stdout = FALSE, stderr = FALSE)),
    error = function(e) NA_integer_
  )
  if (is.na(status)) "unknown" else if (identical(as.integer(status), 0L)) "live" else "dead"
}

.wb_writer_lock_age <- function(lock_path, metadata) {
  created <- suppressWarnings(as.numeric(metadata$created_unix %||% NA_real_)[1])
  if (is.na(created)) {
    modified <- suppressWarnings(as.numeric(file.info(lock_path)$mtime[1]))
    created <- modified
  }
  if (is.na(created)) return(NA_real_)
  max(0, as.numeric(Sys.time()) - created)
}

.wb_writer_lock_held <- function(bundle_or_dir) {
  key <- .wb_writer_lock_key(bundle_or_dir)
  if (!exists(key, envir = .wb_writer_lock_state$held, inherits = FALSE)) return(FALSE)
  entry <- get(key, envir = .wb_writer_lock_state$held, inherits = FALSE)
  identical(as.integer(entry$pid), as.integer(Sys.getpid())) && isTRUE(entry$depth > 0L)
}

#' Inspect Exclusive Bundle-Writer Lock State
#'
#' Reports portable owner, process, runtime, age, liveness, and stale-candidate
#' diagnostics for the sibling lock directory associated with a bundle path.
#' Inspection never changes lock state.
#'
#' @param bundle_or_dir An open bundle or bundle directory path.
#' @param stale_after_seconds Age after which an unverifiable owner is reported
#'   as a stale candidate. A verified live owner is never stale.
#' @return A named lock-diagnostics list.
#' @export
wb_bundle_writer_lock_info <- function(bundle_or_dir, stale_after_seconds = 3600) {
  target <- .wb_writer_lock_target(bundle_or_dir)
  lock_path <- .wb_writer_lock_path(target)
  locked <- dir.exists(lock_path)
  metadata <- if (locked) .wb_writer_lock_read_metadata(lock_path) else NULL
  owner_status <- if (locked) .wb_writer_lock_pid_status(metadata) else "absent"
  age <- if (locked) .wb_writer_lock_age(lock_path, metadata) else NA_real_
  stale_after_seconds <- suppressWarnings(as.numeric(stale_after_seconds)[1])
  .wb_assert(is.finite(stale_after_seconds) && stale_after_seconds >= 0,
             "stale_after_seconds must be a finite non-negative number")
  stale <- isTRUE(locked) && !identical(owner_status, "live") &&
    (identical(owner_status, "dead") || (!is.na(age) && age >= stale_after_seconds))
  list(
    locked = locked,
    bundle_path = target,
    lock_path = lock_path,
    owner = metadata,
    owner_status = owner_status,
    age_seconds = age,
    stale_candidate = stale,
    held_by_current_process = .wb_writer_lock_held(target),
    recovery_requires_confirmation = "RECOVER STALE SCWORKBENCH WRITER LOCK"
  )
}

.wb_writer_lock_diagnostic <- function(info, timeout_seconds = NULL) {
  owner <- info$owner %||% list()
  prefix <- if (is.null(timeout_seconds)) {
    "Exclusive bundle-writer lock is unavailable"
  } else {
    paste0("Timed out after ", format(timeout_seconds, trim = TRUE), " seconds waiting for exclusive bundle-writer lock")
  }
  paste0(
    prefix, " for ", info$bundle_path, ". ",
    "lock_path=", info$lock_path,
    "; owner_status=", info$owner_status,
    "; pid=", as.character(owner$pid %||% "unknown"),
    "; host=", as.character(owner$host %||% "unknown"),
    "; operation=", as.character(owner$operation %||% "unknown"),
    "; created_at=", as.character(owner$created_at %||% "unknown"),
    "; age_seconds=", if (is.na(info$age_seconds)) "unknown" else format(round(info$age_seconds, 3), trim = TRUE),
    ". Inspect with wb_bundle_writer_lock_info(). Stale locks are never stolen automatically; recover explicitly with wb_recover_bundle_writer_lock()."
  )
}

.wb_bundle_writer_lock_acquire <- function(bundle_or_dir,
                                           operation = "committed mutation",
                                           timeout_seconds = getOption("scworkbench.writer_lock_timeout_seconds", 10),
                                           poll_seconds = getOption("scworkbench.writer_lock_poll_seconds", 0.05)) {
  bundle_handle <- if (inherits(bundle_or_dir, "scworkbench_bundle")) bundle_or_dir else NULL
  target <- .wb_writer_lock_target(bundle_or_dir)
  key <- .wb_writer_lock_key(target)
  timeout_seconds <- suppressWarnings(as.numeric(timeout_seconds)[1])
  poll_seconds <- suppressWarnings(as.numeric(poll_seconds)[1])
  .wb_assert(is.finite(timeout_seconds) && timeout_seconds >= 0,
             "writer lock timeout_seconds must be a finite non-negative number")
  .wb_assert(is.finite(poll_seconds) && poll_seconds > 0,
             "writer lock poll_seconds must be a finite positive number")

  if (exists(key, envir = .wb_writer_lock_state$held, inherits = FALSE)) {
    entry <- get(key, envir = .wb_writer_lock_state$held, inherits = FALSE)
    if (identical(as.integer(entry$pid), as.integer(Sys.getpid()))) {
      entry$depth <- as.integer(entry$depth) + 1L
      entry$operations <- c(entry$operations, as.character(operation)[1])
      assign(key, entry, envir = .wb_writer_lock_state$held)
      return(structure(list(key = key, token = entry$token, pid = entry$pid), class = "scworkbench_writer_lock"))
    }
    rm(list = key, envir = .wb_writer_lock_state$held)
  }

  held_keys <- ls(envir = .wb_writer_lock_state$held, all.names = TRUE)
  held_elsewhere <- held_keys[vapply(held_keys, function(k) {
    entry <- get(k, envir = .wb_writer_lock_state$held, inherits = FALSE)
    identical(as.integer(entry$pid), as.integer(Sys.getpid())) && isTRUE(entry$depth > 0L)
  }, logical(1))]
  # A process that already owns another bundle may acquire a free second lock,
  # but it must never wait while retaining the first. This try-lock rule makes
  # a cross-bundle wait cycle impossible while preserving multi-bundle assembly
  # workflows in one process.
  acquisition_timeout <- if (length(held_elsewhere)) 0 else timeout_seconds
  if (!is.null(bundle_handle) && !is.null(bundle_handle$con) &&
      isTRUE(tryCatch(RSQLite::sqliteIsTransacting(bundle_handle$con), error = function(e) FALSE))) {
    stop(
      "Exclusive bundle-writer lock must be acquired before opening a SQLite transaction.",
      call. = FALSE
    )
  }

  parent <- dirname(target)
  dir.create(parent, recursive = TRUE, showWarnings = FALSE)
  .wb_assert(dir.exists(parent), paste0("Writer-lock parent directory is unavailable: ", parent))
  lock_path <- .wb_writer_lock_path(target)
  started <- proc.time()[["elapsed"]]
  repeat {
    acquired <- suppressWarnings(dir.create(lock_path, recursive = FALSE, showWarnings = FALSE))
    if (isTRUE(acquired)) {
      token <- .wb_writer_lock_token()
      metadata <- .wb_writer_lock_metadata(target, token, operation)
      ok <- try(.wb_writer_lock_write_metadata(lock_path, metadata), silent = TRUE)
      if (inherits(ok, "try-error")) {
        unlink(lock_path, recursive = TRUE, force = TRUE)
        stop("Failed to initialize exclusive bundle-writer lock metadata: ", as.character(ok), call. = FALSE)
      }
      entry <- list(
        key = key, target = target, lock_path = lock_path, token = token,
        pid = as.integer(Sys.getpid()), depth = 1L,
        operations = as.character(operation)[1]
      )
      assign(key, entry, envir = .wb_writer_lock_state$held)
      return(structure(list(key = key, token = token, pid = entry$pid), class = "scworkbench_writer_lock"))
    }
    elapsed <- proc.time()[["elapsed"]] - started
    if (elapsed >= acquisition_timeout) {
      info <- wb_bundle_writer_lock_info(target)
      stop(.wb_writer_lock_diagnostic(info, acquisition_timeout), call. = FALSE)
    }
    Sys.sleep(min(poll_seconds, max(0, acquisition_timeout - elapsed)))
  }
}

.wb_bundle_writer_lock_release <- function(lock) {
  if (is.null(lock) || !inherits(lock, "scworkbench_writer_lock")) return(invisible(FALSE))
  key <- as.character(lock$key)[1]
  if (!exists(key, envir = .wb_writer_lock_state$held, inherits = FALSE)) return(invisible(FALSE))
  entry <- get(key, envir = .wb_writer_lock_state$held, inherits = FALSE)
  if (!identical(as.integer(entry$pid), as.integer(Sys.getpid())) ||
      !identical(as.character(entry$token), as.character(lock$token))) return(invisible(FALSE))
  entry$depth <- as.integer(entry$depth) - 1L
  if (entry$depth > 0L) {
    entry$operations <- head(entry$operations, entry$depth)
    assign(key, entry, envir = .wb_writer_lock_state$held)
    return(invisible(TRUE))
  }
  rm(list = key, envir = .wb_writer_lock_state$held)
  metadata <- .wb_writer_lock_read_metadata(entry$lock_path)
  if (dir.exists(entry$lock_path) && !is.null(metadata) &&
      identical(as.character(metadata$owner_token), as.character(entry$token))) {
    unlink(entry$lock_path, recursive = TRUE, force = TRUE)
  }
  invisible(!dir.exists(entry$lock_path))
}

.wb_with_bundle_writer_lock <- function(bundle_or_dir,
                                        operation = "committed mutation",
                                        timeout_seconds = getOption("scworkbench.writer_lock_timeout_seconds", 10),
                                        code) {
  lock <- .wb_bundle_writer_lock_acquire(
    bundle_or_dir, operation = operation, timeout_seconds = timeout_seconds
  )
  on.exit(.wb_bundle_writer_lock_release(lock), add = TRUE)
  force(code)
}

#' Explicitly Recover A Stale Bundle-Writer Lock
#'
#' Recovery is deliberately separate from acquisition. It refuses a verified
#' live owner and requires an exact confirmation phrase. Remote or otherwise
#' unverifiable owners additionally require `allow_unknown_owner = TRUE` after
#' the age threshold has elapsed.
#'
#' @inheritParams wb_bundle_writer_lock_info
#' @param confirmation Exact string
#'   `RECOVER STALE SCWORKBENCH WRITER LOCK`.
#' @param allow_unknown_owner Permit explicit recovery of an old lock whose
#'   process liveness cannot be verified on this host.
#' @return Invisibly returns the pre-recovery diagnostics.
#' @export
wb_recover_bundle_writer_lock <- function(bundle_or_dir,
                                          confirmation,
                                          stale_after_seconds = 3600,
                                          allow_unknown_owner = FALSE) {
  .wb_assert(
    identical(as.character(confirmation)[1], "RECOVER STALE SCWORKBENCH WRITER LOCK"),
    "Writer-lock recovery requires confirmation='RECOVER STALE SCWORKBENCH WRITER LOCK'."
  )
  info <- wb_bundle_writer_lock_info(bundle_or_dir, stale_after_seconds = stale_after_seconds)
  .wb_assert(isTRUE(info$locked), "No bundle-writer lock exists to recover.")
  .wb_assert(!identical(info$owner_status, "live"),
             "Refusing to recover a bundle-writer lock whose owner process is live.")
  .wb_assert(isTRUE(info$stale_candidate),
             "Bundle-writer lock is not yet a stale candidate; wait for the configured age threshold or verify its owner.")
  if (identical(info$owner_status, "unknown")) {
    .wb_assert(isTRUE(allow_unknown_owner),
               "Lock owner liveness is unknown; explicit recovery requires allow_unknown_owner=TRUE.")
  }

  quarantine <- paste0(info$lock_path, ".recovery-", .wb_writer_lock_token())
  .wb_assert(file.rename(info$lock_path, quarantine),
             "Stale writer lock changed while recovery was attempted; inspect again before retrying.")
  moved <- .wb_writer_lock_read_metadata(quarantine)
  expected <- as.character(info$owner$owner_token %||% "")[1]
  observed <- as.character(moved$owner_token %||% "")[1]
  if (!identical(expected, observed)) {
    restored <- !dir.exists(info$lock_path) && file.rename(quarantine, info$lock_path)
    stop(
      "Writer lock ownership changed during recovery; no mismatched lock was deleted. restored=",
      isTRUE(restored), call. = FALSE
    )
  }
  unlink(quarantine, recursive = TRUE, force = TRUE)
  .wb_assert(!dir.exists(quarantine), "Recovered lock quarantine could not be removed.")
  invisible(info)
}
