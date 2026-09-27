# Durable session checkpoints.  A session workspace is deliberately outside the
# bundle: it is an owned, lock-coordinated private overlay and is never a
# second mutation route for committed scientific state.

.wb_durable_session_abort <- function(code, message, evidence = list()) {
  code <- as.character(code)[1L]
  class <- if (identical(code, "DURABLE_SESSION_SOURCE_CHANGED")) {
    "scworkbench_durable_session_source_changed"
  } else {
    "scworkbench_durable_session_error"
  }
  stop(structure(
    c(list(message = paste0(code, ": ", message), call = NULL, code = code), evidence),
    class = unique(c(
      class, "scworkbench_durable_session_error", "scworkbench_error",
      "error", "condition"
    ))
  ))
}

.wb_session_workspace_root <- function() {
  root <- getOption("scworkbench.session_workspace", file.path(getwd(), "scworkbench_sessions"))
  root <- normalizePath(as.character(root)[1], winslash = "/", mustWork = FALSE)
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  .wb_assert(dir.exists(root), paste0("Session workspace root is unavailable: ", root))
  root
}

.wb_session_safe_id <- function(session_id) {
  id <- as.character(session_id %||% "")[1]
  .wb_assert(nzchar(id) && identical(id, basename(id)) && !id %in% c(".", "..") &&
               !grepl("[/\\\\]", id) && !grepl("^[A-Za-z]:", id) && !grepl("^~", id),
             "DURABLE_SESSION_UNSAFE_ID: session_id must be one safe path component.")
  id
}

.wb_session_contained_path <- function(root, path, purpose = "session path") {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  .wb_assert(identical(path, root) || startsWith(path, paste0(root, "/")),
             paste0("DURABLE_SESSION_PATH_ESCAPE: ", purpose, " is outside workspace root."))
  path
}

.wb_session_source_identity <- function(bundle) {
  .wb_with_bundle_writer_lock(bundle, operation = "durable session source identity", code = {
    state <- .wb_manifest_registry_snapshot(bundle$con)
    list(schema = "scworkbench.session_source.v2", bundle_dir = normalizePath(bundle$dir, winslash = "/", mustWork = TRUE), location_policy = "fixed_path",
         scientific_state_fingerprint = as.character(state$fingerprint)[1], scientific_state = state)
  })
}

.wb_session_workspace_lock <- function(session, operation, code) {
  durable <- session$durable %||% list()
  workspace <- as.character(durable$workspace %||% "")[1]
  if (!nzchar(workspace)) return(force(code))
  .wb_with_bundle_writer_lock(workspace, operation = paste0("durable session: ", operation), code = force(code))
}

.wb_session_generation_root <- function(session) {
  file.path(session$durable$workspace, "checkpoints")
}

.wb_session_pointer_file <- function(workspace) file.path(workspace, "CURRENT.json")

.wb_session_fault <- function(boundary) {
  hook <- getOption("scworkbench.durable_session_fault_hook", NULL)
  if (is.function(hook)) hook(as.character(boundary)[1])
  invisible(NULL)
}

.wb_session_operation_marker <- function(session, op_name = NULL, run_id = NULL, clear = FALSE) {
  if (is.null(session$durable)) return(invisible(NULL))
  .wb_session_workspace_lock(session, "operation marker", {
    .wb_session_assert_mutation_owner(session)
    path <- file.path(session$durable$workspace, "OPERATION.json")
    if (isTRUE(clear)) {
      if (file.exists(path)) unlink(path, force = TRUE)
      return(invisible(NULL))
    }
    .wb_session_atomic_json(list(schema = "scworkbench.durable_session.operation.v1", op_name = as.character(op_name)[1],
                                 run_id = as.character(run_id)[1], started_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6%z")), path)
  })
  invisible(NULL)
}

.wb_session_atomic_json <- function(value, path) {
  tmp <- paste0(path, ".tmp-", .wb_writer_lock_token())
  jsonlite::write_json(value, tmp, auto_unbox = TRUE, pretty = FALSE, null = "null")
  .wb_assert(file.rename(tmp, path), paste0("Could not atomically publish ", basename(path), "."))
  invisible(path)
}

.wb_session_pointer <- function(workspace) {
  path <- .wb_session_pointer_file(workspace)
  .wb_assert(file.exists(path), "DURABLE_SESSION_CORRUPT: current checkpoint pointer is missing.")
  x <- try(jsonlite::read_json(path, simplifyVector = TRUE), silent = TRUE)
  .wb_assert(!inherits(x, "try-error") && identical(as.character(x$schema %||% "")[1], "scworkbench.durable_session.pointer.v2"),
             "DURABLE_SESSION_CORRUPT: current checkpoint pointer is malformed.")
  gen <- .wb_session_safe_id(x$generation %||% "")
  meta <- file.path(workspace, "checkpoints", gen, "session.json")
  .wb_assert(file.exists(meta) && identical(as.character(x$metadata_sha256 %||% "")[1], .wb_prov_sha256_file(meta)),
             "DURABLE_SESSION_CORRUPT: checkpoint pointer/metadata binding failed.")
  list(generation = gen, metadata_path = meta, pointer = x)
}

.wb_session_validate_ownership <- function(session) {
  .wb_assert(!is.null(session$durable), "DURABLE_SESSION_OWNERSHIP: durable metadata is missing.")
  binding <- .wb_session_pointer(session$durable$workspace)
  meta <- try(jsonlite::read_json(binding$metadata_path, simplifyVector = TRUE), silent = TRUE)
  .wb_assert(!inherits(meta, "try-error") && identical(as.character(meta$ownership_token %||% "")[1],
               as.character(session$durable$ownership_token %||% "")[1]) &&
               nzchar(as.character(meta$ownership_token %||% "")[1]),
             "DURABLE_SESSION_OWNERSHIP: session does not own this workspace.")
  invisible(TRUE)
}

# A durable handle is an optimistic lease on one exact publication, not merely
# on a workspace.  The writer lock serializes publication, while this binding
# prevents a second process that opened an older graph from publishing over a
# newer one after it acquires that lock.
.wb_session_assert_current_generation <- function(session, allow_unbound = FALSE) {
  .wb_assert(!is.null(session$durable), "DURABLE_SESSION_OWNERSHIP: durable metadata is missing.")
  expected <- as.character(session$durable$checkpoint_generation %||% "")[1]
  if (!nzchar(expected)) {
    .wb_assert(isTRUE(allow_unbound), "DURABLE_SESSION_STALE_GENERATION: session is not bound to a current checkpoint generation.")
    return(invisible(TRUE))
  }
  binding <- .wb_session_pointer(session$durable$workspace)
  expected_meta <- as.character(session$durable$checkpoint_metadata_sha256 %||% "")[1]
  .wb_assert(identical(expected, binding$generation) &&
               (!nzchar(expected_meta) || identical(expected_meta, as.character(binding$pointer$metadata_sha256 %||% "")[1])),
             "DURABLE_SESSION_STALE_GENERATION: workspace current generation changed; reopen the session before mutating it.")
  invisible(TRUE)
}

.wb_session_assert_mutation_owner <- function(session, allow_unbound = FALSE) {
  if (!isTRUE(allow_unbound) || nzchar(as.character(session$durable$checkpoint_generation %||% "")[1])) {
    .wb_session_validate_ownership(session)
  }
  .wb_session_assert_current_generation(session, allow_unbound = allow_unbound)
  invisible(TRUE)
}

.wb_session_checkpoint_state_sha <- function(session) {
  # Deliberately hash only checkpointable semantic state. Connections, pointer
  # identities and timestamps are process/publication mechanics, not graph
  # state; including them would make a valid reopened handle look modified.
  durable <- session$durable %||% list()
  state <- list(runs = session$runs, head_run_id = session$head_run_id,
                active = session$active, payload_identities = durable$payload_identities,
                lifecycle_state = durable$state, promotion_receipt = durable$promotion_receipt %||% NULL)
  tmp <- tempfile("scwb_session_state_")
  on.exit(unlink(tmp, force = TRUE), add = TRUE)
  saveRDS(state, tmp, version = 3)
  .wb_prov_sha256_file(tmp)
}

.wb_session_validate_checkpoint_state <- function(session) {
  expected <- as.character(session$durable$checkpoint_state_sha %||% "")[1]
  observed <- .wb_session_checkpoint_state_sha(session)
  .wb_assert(nzchar(expected) && identical(expected, observed),
             paste0("DURABLE_SESSION_UNCHECKPOINTED_STATE: in-memory session graph differs from its published checkpoint (expected=", expected, ", observed=", observed, ")."))
  invisible(TRUE)
}

.wb_session_checkpoint_file <- function(session) {
  p <- .wb_session_pointer(session$durable$workspace)
  file.path(dirname(p$metadata_path), "session.rds")
}

.wb_session_checkpoint <- function(session, state = "active", allow_uncheckpointed_state = FALSE) {
  if (is.null(session$durable)) return(session)
  .wb_session_workspace_lock(session, "checkpoint", {
    unbound <- !nzchar(as.character(session$durable$checkpoint_generation %||% "")[1])
    .wb_session_assert_mutation_owner(session, allow_unbound = unbound)
    if (!unbound && !isTRUE(allow_uncheckpointed_state)) .wb_session_validate_checkpoint_state(session)
    parent_generation <- as.character(session$durable$checkpoint_generation %||% "")[1]
    session$durable$state <- as.character(state)[1]
    session$durable$updated_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6%z")
    root <- .wb_session_generation_root(session)
    dir.create(root, recursive = TRUE, showWarnings = FALSE)
    generation <- paste0("g_", format(Sys.time(), "%Y%m%d%H%M%OS6"), "_", .wb_writer_lock_token())
    generation <- gsub("[^A-Za-z0-9_.-]", "", generation)
    dir <- .wb_session_contained_path(session$durable$workspace, file.path(root, generation), "checkpoint generation")
    dir.create(dir, recursive = FALSE, showWarnings = FALSE)
    # The serialized session is bound to the generation it is about to publish.
    # The metadata SHA is filled into the live handle after its own bytes exist.
    session$durable$checkpoint_generation <- generation
    session$durable$checkpoint_metadata_sha256 <- NULL
    session$durable$checkpoint_state_sha <- .wb_session_checkpoint_state_sha(session)
    # SQLite connections are process-local external pointers.  The stage itself
    # is durable; reopening it is part of resume rather than RDS restoration.
    persisted <- session
    persisted$staging_bundle <- NULL
    .wb_session_fault("before_serialization")
    rds <- file.path(dir, "session.rds")
    saveRDS(persisted, rds, version = 3)
    .wb_session_fault("after_serialized_bytes")
    meta <- list(schema = "scworkbench.durable_session.v2", generation = generation,
                 parent_generation = if (nzchar(parent_generation)) parent_generation else NULL,
                 session_id = session$session_id, state = session$durable$state,
                 updated_at = session$durable$updated_at, ownership_token = session$durable$ownership_token,
                 source_identity = session$durable$source_identity,
                 checkpoint_sha256 = .wb_prov_sha256_file(rds),
                 checkpoint_state_sha256 = session$durable$checkpoint_state_sha,
                 payload_identities = session$durable$payload_identities,
                 runtime_attestations = session$durable$runtime_attestations)
    jsonlite::write_json(meta, file.path(dir, "session.json"), auto_unbox = TRUE, pretty = FALSE, null = "null")
    .wb_session_fault("after_metadata")
    pointer <- list(schema = "scworkbench.durable_session.pointer.v2", generation = generation,
                    metadata_sha256 = .wb_prov_sha256_file(file.path(dir, "session.json")))
    .wb_session_fault("before_generation_publication")
    .wb_session_atomic_json(pointer, .wb_session_pointer_file(session$durable$workspace))
    session$durable$checkpoint_metadata_sha256 <- pointer$metadata_sha256
    .wb_session_fault("after_generation_publication")
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
  fields <- c("bundle_dir", "scientific_state_fingerprint")
  bad <- fields[!vapply(fields, function(nm) identical(as.character(expected[[nm]]), as.character(observed[[nm]])), logical(1))]
  if (length(bad)) .wb_durable_session_abort(
    "DURABLE_SESSION_SOURCE_CHANGED",
    paste0("source bundle no longer matches checkpoint (", paste(bad, collapse = ", "), ")."),
    evidence = list(changed_fields = bad)
  )
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
      actual <- try(.wb_prov_payload_identity(session$staging_bundle, run$outputs[[nm]]), silent = TRUE)
      .wb_assert(!inherits(actual, "try-error") &&
                   identical(as.character(recorded[[nm]]$content_sha256), as.character(actual$content_sha256)) &&
                   identical(as.character(recorded[[nm]]$content_identity_scheme), as.character(actual$content_identity_scheme)) &&
                   identical(as.character(recorded[[nm]]$registry_binding_sha256 %||% NA_character_),
                             as.character(actual$registry_binding_sha256 %||% NA_character_)),
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
  if (is.null(session_id)) {
    s$session_id <- .wb_allocate_identifier(
      "session_", 12L, purpose = "durable session",
      occupied = function(candidate) dir.exists(file.path(root, candidate)) ||
        file.exists(file.path(root, candidate))
    )
  } else {
    s$session_id <- .wb_session_safe_id(session_id)
    if (dir.exists(file.path(root, s$session_id)) || file.exists(file.path(root, s$session_id))) {
      .wb_identifier_error(
        "SCWORKBENCH_IDENTIFIER_CONFLICT",
        paste0("preallocated durable session identifier already exists: ", s$session_id),
        "durable session"
      )
    }
  }
  workspace <- .wb_session_contained_path(root, file.path(root, s$session_id), "workspace")
  dir.create(workspace, recursive = TRUE, showWarnings = FALSE)
  s$staging_dir <- .wb_session_contained_path(root, file.path(workspace, "stage"), "stage")
  s$durable <- list(workspace = normalizePath(workspace, winslash = "/", mustWork = TRUE),
                    source_identity = .wb_session_source_identity(bundle), state = "creating",
                    ownership_token = .wb_writer_lock_token(), workspace_root = root,
                    payload_identities = list(), runtime_attestations = list(session = .wb_prov_runtime_fingerprint("session")),
                    checkpoint_generation = NULL, checkpoint_metadata_sha256 = NULL,
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
  if (!dir.exists(root)) return(data.frame(workspace=character(), session_id=character(), state=character(), updated_at=character(), stringsAsFactors=FALSE))
  dirs <- list.dirs(root, recursive = FALSE, full.names = TRUE)
  out <- lapply(dirs, function(d) {
    d <- try(.wb_session_contained_path(root, d, "listed workspace"), silent = TRUE)
    if (inherits(d, "try-error")) return(data.frame(workspace=NA_character_, session_id=NA_character_, state="corrupt", updated_at=NA_character_, stringsAsFactors=FALSE))
    pointer <- try(.wb_session_pointer(d), silent = TRUE)
    if (inherits(pointer, "try-error")) {
      partial <- dir.exists(file.path(d, "checkpoints"))
      current <- file.exists(.wb_session_pointer_file(d))
      return(data.frame(workspace=d, session_id=NA_character_, state=if (current) "corrupt" else if (partial) "partial" else "abandoned", updated_at=NA_character_, stringsAsFactors=FALSE))
    }
    x <- try(jsonlite::read_json(pointer$metadata_path, simplifyVector = TRUE), silent = TRUE)
    if (inherits(x, "try-error")) return(data.frame(workspace=d, session_id=NA_character_, state="corrupt", updated_at=NA_character_, stringsAsFactors=FALSE))
    state <- as.character(x$state %||% "corrupt")[1]
    if (file.exists(file.path(d, "OPERATION.json")) && identical(state, "active")) state <- "interrupted"
    data.frame(workspace=d, session_id=as.character(x$session_id %||% NA_character_)[1], state=state, updated_at=as.character(x$updated_at %||% NA_character_)[1], stringsAsFactors=FALSE)
  })
  out <- Filter(Negate(is.null), out); if (!length(out)) return(data.frame(workspace=character(), session_id=character(), state=character(), updated_at=character(), stringsAsFactors=FALSE)); do.call(rbind, out)
}

#' Open A Durable Session Checkpoint
#' @param workspace Durable session workspace directory.
#' @return A session with its private staging bundle reopened.
#' @export
wb_session_open <- function(workspace) {
  workspace <- normalizePath(as.character(workspace)[1], winslash = "/", mustWork = TRUE)
  lock <- .wb_bundle_writer_lock_acquire(workspace, operation = "durable session open")
  on.exit(.wb_bundle_writer_lock_release(lock), add = TRUE)
  binding <- .wb_session_pointer(workspace)
  meta <- try(jsonlite::read_json(binding$metadata_path, simplifyVector = TRUE), silent = TRUE)
  .wb_assert(!inherits(meta, "try-error") && identical(as.character(meta$schema %||% "")[1], "scworkbench.durable_session.v2"),
             "DURABLE_SESSION_CORRUPT: checkpoint metadata is malformed.")
  path <- file.path(dirname(binding$metadata_path), "session.rds")
  .wb_assert(file.exists(path) && identical(as.character(meta$checkpoint_sha256 %||% "")[1], .wb_prov_sha256_file(path)),
             "DURABLE_SESSION_CORRUPT: checkpoint serialized-byte binding failed.")
  s <- try(readRDS(path), silent = TRUE)
  .wb_assert(!inherits(s, "try-error") && wb_is_session(s) && !is.null(s$durable), "DURABLE_SESSION_CORRUPT: checkpoint cannot be read.")
  .wb_assert(identical(normalizePath(s$durable$workspace, winslash="/", mustWork=TRUE), workspace), "DURABLE_SESSION_CORRUPT: workspace identity mismatch.")
  .wb_session_contained_path(as.character(s$durable$workspace_root %||% "")[1], workspace,
                             "opened workspace")
  .wb_assert(identical(as.character(s$session_id)[1], as.character(meta$session_id)[1]) &&
               identical(as.character(s$durable$ownership_token %||% "")[1], as.character(meta$ownership_token %||% "")[1]) &&
               nzchar(as.character(meta$ownership_token %||% "")[1]), "DURABLE_SESSION_CORRUPT: checkpoint ownership binding failed.")
  .wb_assert(as.character(s$durable$state) %in% c("active", "finalized", "promoted"), "DURABLE_SESSION_INCOMPLETE: checkpoint was not completed.")
  .wb_assert(identical(as.character(meta$checkpoint_state_sha256 %||% "")[1],
                       .wb_session_checkpoint_state_sha(s)),
             "DURABLE_SESSION_CORRUPT: checkpoint graph-state binding failed.")
  s$durable$checkpoint_generation <- binding$generation
  s$durable$checkpoint_metadata_sha256 <- as.character(binding$pointer$metadata_sha256)[1]
  s$durable$checkpoint_state_sha <- as.character(meta$checkpoint_state_sha256)[1]
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
  validated <- FALSE
  on.exit({
    if (!validated && !is.null(s$staging_bundle) && inherits(s$staging_bundle, "scworkbench_bundle")) {
      try(wb_close_bundle(s$staging_bundle), silent = TRUE)
    }
  }, add = TRUE)
  .wb_assert(identical(as.character(s$durable$state), "active"),
             paste0("DURABLE_SESSION_", toupper(as.character(s$durable$state)), ": terminal sessions are inspectable but cannot resume execution."))
  .wb_session_validate_source(s, bundle)
  # A checkpoint cannot serialize the source's SQLite connection. Restore its
  # verified live handle only after checking the exact source path and registry
  # identity, so stage-leaf authentication remains available after replacement.
  s$staging_bundle$staging_source_bundle <- bundle
  .wb_session_validate_payloads(s)
  validated <- TRUE
  s
}

#' Finalize A Durable Session
#' @param session Durable session.
#' @return Checkpointed finalized session.
#' @export
wb_session_finalize <- function(session) { .wb_assert(wb_is_session(session), "session must be wb_session"); if (as.character(session$durable$state %||% "") %in% c("finalized", "promoted")) return(session); .wb_session_checkpoint(session, "finalized") }

#' Clean Durable Session Checkpoint Retention
#'
#' Removes only unpublished checkpoint generations below an owned workspace.
#' Active/finalized checkpoints and their stage are retained; this function
#' never traverses staging links or source-bundle payload paths.
#' @param session Durable session handle.
#' @return Session handle invisibly.
#' @export
wb_session_cleanup <- function(session) {
  .wb_assert(wb_is_session(session) && !is.null(session$durable), "session must be a durable wb_session")
  workspace <- session$durable$workspace
  root <- session$durable$workspace_root
  .wb_session_contained_path(root, workspace, "cleanup workspace")
  .wb_session_workspace_lock(session, "cleanup", {
    .wb_session_assert_mutation_owner(session)
    current <- .wb_session_pointer(workspace)$generation
    # Faulted atomic pointer publications and incomplete generations are never
    # current state.  Retention only visits direct checkpoint children.
    tmp_pointers <- list.files(workspace, pattern = "^CURRENT\\.json\\.tmp-", full.names = TRUE)
    if (length(tmp_pointers)) unlink(tmp_pointers, force = TRUE)
    generations <- list.dirs(.wb_session_generation_root(session), recursive = FALSE, full.names = TRUE)
    for (dir in generations) {
      dir <- .wb_session_contained_path(workspace, dir, "cleanup generation")
      if (identical(basename(dir), current) || nzchar(Sys.readlink(dir))) next
      meta_path <- file.path(dir, "session.json")
      rds_path <- file.path(dir, "session.rds")
      meta <- try(jsonlite::read_json(meta_path, simplifyVector = TRUE), silent = TRUE)
      complete <- !inherits(meta, "try-error") &&
        identical(as.character(meta$schema %||% "")[1], "scworkbench.durable_session.v2") &&
        identical(as.character(meta$generation %||% "")[1], basename(dir)) &&
        file.exists(rds_path) &&
        identical(as.character(meta$checkpoint_sha256 %||% "")[1], .wb_prov_sha256_file(rds_path))
      # Historical complete generations are audit/recovery records.  Only an
      # incomplete, unpublished child is eligible for deletion.
      if (!complete) unlink(dir, recursive = TRUE, force = TRUE)
    }
  })
  invisible(session)
}
