# Durable session checkpoints.  A session workspace is deliberately outside the
# bundle: it is an owned, lock-coordinated private overlay and is never a
# second mutation route for committed scientific state.

.wb_session_workspace_root <- function() {
  root <- getOption("scworkbench.session_workspace", file.path(getwd(), "scworkbench_sessions"))
  root <- normalizePath(as.character(root)[1], winslash = "/", mustWork = FALSE)
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  .wb_assert(dir.exists(root), paste0("Session workspace root is unavailable: ", root))
  root
}

.wb_session_source_identity <- function(bundle) {
  db_rel <- as.character(bundle$manifest$storage$sqlite$path %||% "")[1]
  list(
    schema = "scworkbench.session_source.v1",
    bundle_dir = normalizePath(bundle$dir, winslash = "/", mustWork = TRUE),
    manifest_fingerprint = as.character(bundle$manifest$current_state$fingerprint %||% "")[1],
    manifest_sha256 = .wb_prov_sha256_file(file.path(bundle$dir, "manifest.json")),
    sqlite_sha256 = .wb_prov_sha256_file(file.path(bundle$dir, db_rel))
  )
}

.wb_session_workspace_lock <- function(session, operation, code) {
  durable <- session$durable %||% list()
  workspace <- as.character(durable$workspace %||% "")[1]
  if (!nzchar(workspace)) return(force(code))
  .wb_with_bundle_writer_lock(workspace, operation = paste0("durable session: ", operation), code = force(code))
}

.wb_session_checkpoint_file <- function(session) file.path(session$durable$workspace, "session.rds")

.wb_session_checkpoint <- function(session, state = "active") {
  if (is.null(session$durable)) return(session)
  session$durable$state <- as.character(state)[1]
  session$durable$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6%z")
  # SQLite connections are process-local external pointers.  The stage itself
  # is durable; reopening it is part of resume rather than RDS restoration.
  persisted <- session
  persisted$staging_bundle <- NULL
  path <- .wb_session_checkpoint_file(session)
  .wb_session_workspace_lock(session, "checkpoint", {
    tmp <- paste0(path, ".tmp-", .wb_writer_lock_token())
    saveRDS(persisted, tmp, version = 3)
    .wb_assert(file.rename(tmp, path), "Could not atomically publish durable session checkpoint.")
    meta <- list(schema = "scworkbench.durable_session.v1", session_id = session$session_id,
                 state = session$durable$state, updated_at = session$durable$updated_at,
                 source_identity = session$durable$source_identity)
    mtmp <- file.path(session$durable$workspace, paste0("session.json.tmp-", .wb_writer_lock_token()))
    jsonlite::write_json(meta, mtmp, auto_unbox = TRUE, pretty = TRUE, null = "null")
    .wb_assert(file.rename(mtmp, file.path(session$durable$workspace, "session.json")),
               "Could not atomically publish durable session metadata.")
  })
  session
}

.wb_session_record_payload_identities <- function(session, run) {
  if (is.null(session$durable) || is.null(session$staging_bundle)) return(session)
  ids <- lapply(run$outputs %||% list(), function(x) .wb_prov_payload_identity(session$staging_bundle, x))
  session$durable$payload_identities[[run$run_id]] <- ids
  session
}

.wb_session_validate_source <- function(session, bundle) {
  expected <- session$durable$source_identity %||% NULL
  if (is.null(expected)) return(invisible(TRUE))
  observed <- .wb_session_source_identity(bundle)
  # Manifests are publication receipts and may be refreshed on a clean close
  # (including timestamps).  The authoritative committed registry bytes are
  # the compatibility boundary; comparing the manifest receipt would reject a
  # source that has not changed scientifically.
  fields <- c("bundle_dir", "sqlite_sha256")
  bad <- fields[!vapply(fields, function(nm) identical(as.character(expected[[nm]]), as.character(observed[[nm]])), logical(1))]
  .wb_assert(!length(bad), paste0("DURABLE_SESSION_SOURCE_CHANGED: source bundle no longer matches checkpoint (", paste(bad, collapse = ", "), ")."))
  invisible(TRUE)
}

.wb_session_validate_payloads <- function(session) {
  if (is.null(session$durable) || !length(session$durable$payload_identities %||% list())) return(invisible(TRUE))
  .wb_assert(!is.null(session$staging_bundle), "DURABLE_SESSION_CORRUPT: staged bundle is unavailable.")
  for (rid in names(session$durable$payload_identities)) {
    run <- session$runs[[rid]]
    .wb_assert(!is.null(run), paste0("DURABLE_SESSION_CORRUPT: checkpoint references missing run ", rid))
    recorded <- session$durable$payload_identities[[rid]]
    for (nm in names(recorded)) {
      actual <- .wb_prov_payload_identity(session$staging_bundle, run$outputs[[nm]])
      .wb_assert(identical(as.character(recorded[[nm]]$content_sha256), as.character(actual$content_sha256)) &&
                   identical(as.character(recorded[[nm]]$content_identity_scheme), as.character(actual$content_identity_scheme)),
                 paste0("DURABLE_SESSION_PAYLOAD_CORRUPT: staged output ", rid, "/", nm, " no longer matches checkpoint identity."))
    }
  }
  invisible(TRUE)
}

#' Create A Durable, Resumable Analysis Session
#' @param bundle Writable source bundle.
#' @param workspace_root Durable workspace parent. Defaults to option
#'   `scworkbench.session_workspace` or `./scworkbench_sessions`.
#' @param session_id Optional stable session identifier.
#' @return A checkpointed `wb_session` with a private staged bundle snapshot.
#' @export
wb_session_create <- function(bundle, workspace_root = .wb_session_workspace_root(), session_id = NULL) {
  .wb_assert_bundle_writable(bundle, "durable session creation")
  root <- normalizePath(as.character(workspace_root)[1], winslash = "/", mustWork = FALSE)
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  s <- wb_session_new()
  if (!is.null(session_id)) s$session_id <- as.character(session_id)[1]
  workspace <- file.path(root, s$session_id)
  .wb_assert(!dir.exists(workspace), paste0("Durable session workspace already exists: ", workspace))
  dir.create(workspace, recursive = TRUE, showWarnings = FALSE)
  s$staging_dir <- file.path(workspace, "stage")
  s$durable <- list(workspace = normalizePath(workspace, winslash = "/", mustWork = TRUE),
                    source_identity = .wb_session_source_identity(bundle), state = "creating",
                    payload_identities = list(), runtime_attestation = .wb_prov_runtime_fingerprint("session"),
                    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6%z"))
  staged <- try(.wb_session_stage_bundle(bundle, s), silent = TRUE)
  if (inherits(staged, "try-error")) { unlink(workspace, recursive = TRUE, force = TRUE); stop(staged) }
  s <- staged$session
  # Snapshot acquisition is writer-lock coordinated and may publish an already
  # committed manifest checkpoint; bind the durable session to that final,
  # coherent source identity rather than the pre-lock view.
  s$durable$source_identity <- .wb_session_source_identity(bundle)
  .wb_session_checkpoint(s, "active")
}

#' List Durable Session Workspaces
#' @param workspace_root Durable session workspace parent.
#' @return Data frame of discovered durable-session checkpoints.
#' @export
wb_session_list <- function(workspace_root = .wb_session_workspace_root()) {
  root <- normalizePath(as.character(workspace_root)[1], winslash = "/", mustWork = FALSE)
  dirs <- list.dirs(root, recursive = FALSE, full.names = TRUE)
  out <- lapply(dirs, function(d) { p <- file.path(d, "session.json"); if (!file.exists(p)) return(NULL); x <- try(jsonlite::read_json(p, simplifyVector = TRUE), silent = TRUE); if (inherits(x, "try-error")) return(data.frame(workspace=d, session_id=NA_character_, state="corrupt", stringsAsFactors=FALSE)); data.frame(workspace=d, session_id=as.character(x$session_id), state=as.character(x$state), updated_at=as.character(x$updated_at), stringsAsFactors=FALSE) })
  out <- Filter(Negate(is.null), out); if (!length(out)) return(data.frame(workspace=character(), session_id=character(), state=character(), updated_at=character(), stringsAsFactors=FALSE)); do.call(rbind, out)
}

#' Open A Durable Session Checkpoint
#' @param workspace Durable session workspace directory.
#' @return A session with its private staging bundle reopened.
#' @export
wb_session_open <- function(workspace) {
  workspace <- normalizePath(as.character(workspace)[1], winslash = "/", mustWork = TRUE)
  path <- file.path(workspace, "session.rds")
  .wb_assert(file.exists(path), paste0("DURABLE_SESSION_CORRUPT: checkpoint missing: ", path))
  lock <- .wb_bundle_writer_lock_acquire(workspace, operation = "durable session open")
  on.exit(.wb_bundle_writer_lock_release(lock), add = TRUE)
  s <- try(readRDS(path), silent = TRUE)
  .wb_assert(!inherits(s, "try-error") && wb_is_session(s) && !is.null(s$durable), "DURABLE_SESSION_CORRUPT: checkpoint cannot be read.")
  .wb_assert(identical(normalizePath(s$durable$workspace, winslash="/", mustWork=TRUE), workspace), "DURABLE_SESSION_CORRUPT: workspace identity mismatch.")
  .wb_assert(identical(as.character(s$durable$state), "active") || identical(as.character(s$durable$state), "finalized"), "DURABLE_SESSION_INCOMPLETE: checkpoint was not completed.")
  s$staging_bundle <- NULL
  staged <- .wb_session_stage_bundle(structure(list(), class="scworkbench_bundle"), s)
  staged$session
}

#' Resume A Durable Analysis Session
#' @param bundle Writable source bundle.
#' @param workspace Durable session workspace directory.
#' @return A validated active `wb_session`.
#' @export
wb_session_resume <- function(bundle, workspace) {
  s <- wb_session_open(workspace)
  .wb_session_validate_source(s, bundle)
  .wb_session_validate_payloads(s)
  s
}

#' Finalize A Durable Session
#' @param session Durable session.
#' @return Checkpointed finalized session.
#' @export
wb_session_finalize <- function(session) { .wb_assert(wb_is_session(session), "session must be wb_session"); .wb_session_checkpoint(session, "finalized") }
