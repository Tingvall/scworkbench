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
  .wb_open_bundle(bundle_dir,validate,read_only)
}

.wb_open_bundle <- function(bundle_dir,validate=FALSE,read_only=FALSE,
    graph_budgets=NULL,graph_cache_kib=NULL) {
  if (!dir.exists(bundle_dir)) stop("Bundle directory does not exist: ", bundle_dir)

  if (isTRUE(read_only)) {
    lock_info <- wb_bundle_writer_lock_info(bundle_dir)
    if (isTRUE(lock_info$locked)) {
      stop(
        "Recipient read-only open refused while an exclusive bundle writer is active. ",
        .wb_writer_lock_diagnostic(lock_info),
        call. = FALSE
      )
    }
  }

  man_path <- .wb_bundle_path_require(bundle_dir,"manifest.json",expected_type="file",
                                      purpose="bundle manifest")
  manifest <- jsonlite::read_json(man_path, simplifyVector = TRUE)

  db_rel <- manifest$storage$sqlite$path
  if (is.null(db_rel)) stop("manifest.json missing storage$sqlite$path")

  db_path <- .wb_bundle_path_require(bundle_dir, db_rel, expected_type = "file",
                                     must_exist = TRUE, purpose = "manifest SQLite database")

  cache_kib <- graph_cache_kib %||% 2000L
  con <- if (isTRUE(read_only)) {
    # SQLite WAL readers may create -shm/-wal even with SQLITE_RO.  An
    # immutable URI is the only direct :ro-mount mode that forbids that I/O.
    # It is safe only after finalization has proved no uncheckpointed WAL
    # state exists; otherwise immutable could silently omit WAL frames.
    if (file.exists(paste0(db_path, "-wal")) || file.exists(paste0(db_path, "-shm"))) {
      stop("Bundle is not recipient-finalized: unresolved SQLite WAL sidecars are present. Open writable and run wb_finalize_recipient_bundle() before read-only transfer.", call.=FALSE)
    }
    DBI::dbConnect(RSQLite::SQLite(), paste0("file:", normalizePath(db_path, winslash="/", mustWork=TRUE), "?immutable=1"), flags = RSQLite::SQLITE_RO,cache_size=-cache_kib)
  } else DBI::dbConnect(RSQLite::SQLite(), db_path,cache_size=-cache_kib)
  opened <- FALSE
  on.exit(if (!opened && DBI::dbIsValid(con)) try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)
  if(!is.null(graph_budgets)) {
    restore_graph <- .wb_graph_scoped_connection_budget(con,graph_budgets,cache_kib=cache_kib)
    on.exit(restore_graph(),add=TRUE)
  }
  # Foreign-key enforcement is connection-local and is verified immediately.
  # Durable journal-mode coordination remains inside the writer-locked
  # migration scope below.
  .wb_sqlite_configure_connection(
    con, writable = !isTRUE(read_only), configure_journal = FALSE
  )

  schema_status <- .wb_schema_status(con)
  if (isTRUE(read_only) && !identical(schema_status$status, "current")) {
    try(DBI::dbDisconnect(con), silent = TRUE)
    stop(
      "BUNDLE_SCHEMA_UPGRADE_REQUIRED: ", schema_status$message,
      " Open the bundle writable with the current scworkbench and run wb_migrate_bundle().",
      call. = FALSE
    )
  }

  bundle <- list(
    dir = bundle_dir,
    manifest = manifest,
    con = con, read_only = isTRUE(read_only)
  )
  class(bundle) <- "scworkbench_bundle"

  if (!isTRUE(read_only)) {
    wb_migrate_bundle(bundle)
    .wb_capsule_recover_residue(bundle)
    .wb_operation_pack_v2_recover(bundle)
  } else {
    .wb_capsule_assert_no_residue(bundle, "recipient read-only open")
    .wb_operation_pack_v2_assert_recipient(bundle)
  }
  if (isTRUE(validate)) {
    wb_validate_bundle(bundle_dir, read_only = read_only)
  }

  opened <- TRUE
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
    con <- bundle$con
    .wb_session_source_forget(con)
    on.exit(.wb_unregister_assembly_connection(con), add = TRUE)
    publication <- if (.wb_is_assembly_connection(con) && DBI::dbIsValid(con)) {
      try(.wb_refresh_manifest_committed(bundle), silent = TRUE)
    } else TRUE
    DBI::dbDisconnect(con)
    if (inherits(publication, "try-error")) stop(as.character(publication), call. = FALSE)
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
  lock_info <- wb_bundle_writer_lock_info(bundle_dir)
  if (isTRUE(lock_info$locked) && !isTRUE(lock_info$held_by_current_process)) {
    return(list(
      ready = FALSE, journal_mode = NA_character_,
      wal_path = NA_character_, shm_path = NA_character_,
      writer_lock = lock_info,
      reason = "exclusive bundle writer is active; recipient state is not stable"
    ))
  }
  man_path <- .wb_bundle_path_require(bundle_dir,"manifest.json",expected_type="file",purpose="bundle manifest")
  man <- jsonlite::read_json(man_path, simplifyVector=TRUE)
  db <- .wb_bundle_path_require(bundle_dir, as.character(man$storage$sqlite$path)[1],
                                expected_type="file", purpose="manifest SQLite database")
  wal <- paste0(db, "-wal"); shm <- paste0(db, "-shm")
  unresolved <- file.exists(wal) || file.exists(shm)
  jm <- if (unresolved) NA_character_ else {
    con <- DBI::dbConnect(RSQLite::SQLite(), paste0("file:", normalizePath(db, winslash="/", mustWork=TRUE), "?immutable=1"), flags=RSQLite::SQLITE_RO)
    on.exit(DBI::dbDisconnect(con), add=TRUE)
    .wb_sqlite_configure_connection(con, writable = FALSE)
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
  .wb_with_bundle_writer_lock(bundle, operation = "recipient finalization", code = {
    .wb_capsule_assert_no_residue(bundle, "recipient finalization")
    DBI::dbExecute(bundle$con, "PRAGMA wal_checkpoint(TRUNCATE);")
    DBI::dbGetQuery(bundle$con, "PRAGMA journal_mode=DELETE;")
    DBI::dbExecute(bundle$con, "PRAGMA wal_checkpoint(TRUNCATE);")
    transient_manifests <- list.files(
      bundle$dir,
      pattern = "^\\.manifest[.]json[.](staging|backup)-",
      full.names = TRUE,
      all.files = TRUE
    )
    if (length(transient_manifests)) unlink(transient_manifests, force = TRUE)
    out <- wb_recipient_readiness(bundle$dir)
    .wb_assert(isTRUE(out$ready), out$reason)
    out
  })
}
