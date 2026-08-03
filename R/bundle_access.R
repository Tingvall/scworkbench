#' Open an scworkbench bundle
#'
#' Opens a bundle directory and returns a handle containing:
#' - manifest
#' - SQLite connection
#' - bundle path
#'
#' @param bundle_dir Path to bundle directory
#' @param validate If TRUE, run wb_validate_bundle().
#' @param read_only If TRUE, open SQLite explicitly read-only and disable all
#'   schema migration or bundle mutation. Use for recipient inspection mounts.
#' @return A bundle handle
# pybench-parity: yes
# pybench-counterpart: pybench.bundle.open_bundle
# contract-note: manifest.json + manifest$storage$sqlite$path resolution must stay aligned
#' @export
wb_open_bundle <- function(bundle_dir, validate = FALSE, read_only = FALSE) {
  if (!dir.exists(bundle_dir)) stop("Bundle directory does not exist: ", bundle_dir)

  man_path <- file.path(bundle_dir, "manifest.json")
  if (!file.exists(man_path)) stop("Missing manifest.json in bundle: ", bundle_dir)

  manifest <- jsonlite::read_json(man_path, simplifyVector = TRUE)

  db_rel <- manifest$storage$sqlite$path
  if (is.null(db_rel)) stop("manifest.json missing storage$sqlite$path")

  db_path <- file.path(bundle_dir, db_rel)
  if (!file.exists(db_path)) stop("SQLite DB not found: ", db_path)

  con <- if (isTRUE(read_only)) {
    # SQLite WAL readers may create -shm/-wal even with SQLITE_RO.  An
    # immutable URI is the only direct :ro-mount mode that forbids that I/O.
    # It is safe only after finalization has proved no uncheckpointed WAL
    # state exists; otherwise immutable could silently omit WAL frames.
    if (file.exists(paste0(db_path, "-wal")) || file.exists(paste0(db_path, "-shm"))) {
      stop("Bundle is not recipient-finalized: unresolved SQLite WAL sidecars are present. Open writable and run wb_finalize_recipient_bundle() before read-only transfer.", call.=FALSE)
    }
    DBI::dbConnect(RSQLite::SQLite(), paste0("file:", normalizePath(db_path, winslash="/", mustWork=TRUE), "?immutable=1"), flags = RSQLite::SQLITE_RO)
  } else DBI::dbConnect(RSQLite::SQLite(), db_path)
  attr(con, "scworkbench_read_only") <- isTRUE(read_only)

  bundle <- list(
    dir = bundle_dir,
    manifest = manifest,
    con = con, read_only = isTRUE(read_only)
  )
  class(bundle) <- "scworkbench_bundle"

  if (isTRUE(validate)) {
    wb_validate_bundle(bundle_dir, read_only = read_only)
  }
  if (!isTRUE(read_only)) wb_migrate_artifacts(bundle)

  bundle
}

.wb_assert_bundle_writable <- function(bundle, action = "mutation") {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(!isTRUE(bundle$read_only), paste0(action, " is unavailable: bundle was opened read_only=TRUE."))
  invisible(TRUE)
}

#' Close an scworkbench bundle
#'
#' @param bundle Bundle handle from [wb_open_bundle()].
#'
#' @return `TRUE` invisibly after closing the SQLite connection.
# pybench-parity: yes
# pybench-counterpart: pybench.bundle.close_bundle
#' @export
wb_close_bundle <- function(bundle) {
  if (inherits(bundle, "scworkbench_bundle") && !is.null(bundle$con)) {
    .wb_unregister_assembly_connection(bundle$con)
    DBI::dbDisconnect(bundle$con)
  }
  invisible(TRUE)
}

#' Check whether a bundle is ready for direct recipient read-only inspection
#'
#' A finalized recipient bundle has no unresolved SQLite WAL sidecars. A
#' persistent `journal_mode=WAL` setting is acceptable only when the WAL is
#' absent (all frames checkpointed); use `wb_finalize_recipient_bundle()` to
#' switch a writable bundle to rollback-journal mode before transfer.
#' @param bundle_dir Bundle directory.
#' @return Named readiness record.
#' @export
wb_recipient_readiness <- function(bundle_dir) {
  man <- jsonlite::read_json(file.path(bundle_dir, "manifest.json"), simplifyVector=TRUE)
  db <- file.path(bundle_dir, as.character(man$storage$sqlite$path)[1])
  wal <- paste0(db, "-wal"); shm <- paste0(db, "-shm")
  unresolved <- file.exists(wal) || file.exists(shm)
  jm <- if (unresolved) NA_character_ else {
    con <- DBI::dbConnect(RSQLite::SQLite(), paste0("file:", normalizePath(db, winslash="/", mustWork=TRUE), "?immutable=1"), flags=RSQLite::SQLITE_RO)
    on.exit(DBI::dbDisconnect(con), add=TRUE)
    as.character(DBI::dbGetQuery(con, "PRAGMA journal_mode;")[[1]][1])
  }
  list(ready=!unresolved, journal_mode=jm,
       wal_path=wal, shm_path=shm,
       reason=if (unresolved) "unresolved SQLite WAL state; finalize before transfer" else "no WAL sidecars")
}

#' Finalize a writable bundle for recipient read-only transfer
#'
#' @param bundle Open writable bundle.
#' @return Recipient readiness record.
#' @export
wb_finalize_recipient_bundle <- function(bundle) {
  .wb_assert_bundle_writable(bundle, "recipient finalization")
  DBI::dbExecute(bundle$con, "PRAGMA wal_checkpoint(TRUNCATE);")
  DBI::dbGetQuery(bundle$con, "PRAGMA journal_mode=DELETE;")
  DBI::dbExecute(bundle$con, "PRAGMA wal_checkpoint(TRUNCATE);")
  out <- wb_recipient_readiness(bundle$dir)
  .wb_assert(isTRUE(out$ready), out$reason)
  out
}
