# Session-local bundle overlays for promotion-gated execution.

.wb_session_stage_root <- function() {
  root <- file.path(tempdir(), "scworkbench_sessions")
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  root
}

.wb_session_stage_link_children <- function(source, target) {
  dir.create(target, recursive = TRUE, showWarnings = FALSE)
  kids <- list.files(source, all.files = TRUE, no.. = TRUE, full.names = TRUE)
  for (src in kids) {
    dst <- file.path(target, basename(src))
    if (file.exists(dst) || dir.exists(dst)) next
    # Mutable roots are a copy-on-write overlay.  Linking a whole child
    # directory would let a staged writer traverse that link and create a new
    # payload in the live bundle (for example models/umap/<new>.uwot).  Keep
    # directory nodes private and link only immutable leaf payloads.
    if (dir.exists(src)) {
      .wb_session_stage_link_children(src, dst)
    } else {
      ok <- file.symlink(src, dst)
      .wb_assert(isTRUE(ok), paste0("Failed to link immutable session payload: ", src))
    }
  }
  invisible(TRUE)
}

.wb_session_stage_bundle <- function(bundle, session) {
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")
  .wb_assert(wb_is_session(session), "session must be wb_session")

  if (!is.null(session$staging_bundle) && inherits(session$staging_bundle, "scworkbench_bundle")) {
    return(list(session = session, bundle = session$staging_bundle))
  }

  # Session IDs label execution state, but callers may set the R RNG for
  # deterministic analyses. A filesystem staging path must remain unique even
  # if that produces the same generated session ID in a later session.
  stage_dir <- tempfile(
    pattern = paste0(as.character(session$session_id), "_"),
    tmpdir = .wb_session_stage_root()
  )
  dir.create(stage_dir, recursive = TRUE, showWarnings = FALSE)

  # Flush the source DB before copying it. Payload directories are linked read-only
  # by convention; newly created matrix/model payloads are written into stage dirs.
  try(DBI::dbExecute(bundle$con, "PRAGMA wal_checkpoint(FULL);"), silent = TRUE)
  db_rel <- as.character(bundle$manifest$storage$sqlite$path)[1]
  dir.create(dirname(file.path(stage_dir, db_rel)), recursive = TRUE, showWarnings = FALSE)
  ok_db <- file.copy(file.path(bundle$dir, db_rel), file.path(stage_dir, db_rel), overwrite = FALSE)
  .wb_assert(isTRUE(ok_db), "Failed to copy bundle SQLite metadata into session staging.")
  ok_manifest <- file.copy(file.path(bundle$dir, "manifest.json"), file.path(stage_dir, "manifest.json"), overwrite = FALSE)
  .wb_assert(isTRUE(ok_manifest), "Failed to copy bundle manifest into session staging.")

  roots <- list.files(bundle$dir, all.files = TRUE, no.. = TRUE)
  roots <- setdiff(roots, c("manifest.json", dirname(db_rel), ".git"))
  mutable <- c("mat", "models", "artifact_models")
  for (nm in roots) {
    src <- file.path(bundle$dir, nm)
    dst <- file.path(stage_dir, nm)
    if (nm %in% mutable && dir.exists(src)) {
      .wb_session_stage_link_children(src, dst)
    } else {
      ok <- file.symlink(src, dst)
      .wb_assert(isTRUE(ok), paste0("Failed to link bundle payload root into session staging: ", src))
    }
  }
  for (nm in mutable) dir.create(file.path(stage_dir, nm), recursive = TRUE, showWarnings = FALSE)

  stage_bundle <- wb_open_bundle(stage_dir, validate = FALSE)
  # Runners receive this overlay bundle directly. Retain the known source
  # bundle location solely to resolve already-promoted artifact references
  # created after the overlay snapshot; no filesystem search is performed.
  stage_bundle$staging_source_dir <- normalizePath(bundle$dir, winslash = "/", mustWork = TRUE)
  session$staging_dir <- stage_dir
  session$staging_bundle <- stage_bundle
  session$staging_source_dir <- stage_bundle$staging_source_dir
  list(session = session, bundle = stage_bundle)
}

#' Discard an ephemeral session staging workspace
#'
#' Removes unpromoted staged payloads and closes the private staging bundle.
#' This never removes committed bundle state.
#'
#' @param session A `wb_session`.
#' @return The session with its staging fields cleared.
#' @export
wb_session_discard <- function(session) {
  .wb_assert(wb_is_session(session), "session must be wb_session")
  if (!is.null(session$staging_bundle) && inherits(session$staging_bundle, "scworkbench_bundle")) {
    try(wb_close_bundle(session$staging_bundle), silent = TRUE)
  }
  stage_dir <- as.character(session$staging_dir %||% "")[1]
  if (nzchar(stage_dir) && dir.exists(stage_dir)) unlink(stage_dir, recursive = TRUE, force = TRUE)
  session$staging_bundle <- NULL
  session$staging_dir <- NULL
  session$staging_source_dir <- NULL
  session
}

#' Get the Ephemeral Bundle View for a Session
#'
#' Returns the session-local bundle overlay that contains staged outputs from
#' [wb_session_run_op()]. The handle is valid only while the session has not
#' been discarded. Use it to inspect staged matrices or spaces before promotion;
#' use the original bundle after promotion and reopen it for portable state.
#'
#' @param session A `wb_session` returned by [wb_session_run_op()].
#' @return An open `scworkbench_bundle` session view.
#' @export
wb_session_view <- function(session) {
  .wb_assert(wb_is_session(session), "session must be wb_session")
  .wb_assert(
    !is.null(session$staging_bundle) && inherits(session$staging_bundle, "scworkbench_bundle"),
    "This session has no active staged bundle view. Run an operation first, or the session was discarded."
  )
  session$staging_bundle
}
