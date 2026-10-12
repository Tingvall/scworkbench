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

.wb_session_sqlite_backup <- function(source_con, destination_path) {
  .wb_assert(inherits(source_con, "SQLiteConnection"),
             "Session SQLite backup requires an RSQLite source connection.")
  .wb_assert(!file.exists(destination_path),
             paste0("Session SQLite backup destination already exists: ", destination_path))
  dir.create(dirname(destination_path), recursive = TRUE, showWarnings = FALSE)
  policy <- source_con@ref$wb_graph_policy
  cache_kib <- if(is.null(policy)) 2000L else floor((policy$sqlite_cache_kib-128L)/2L)
  if(!is.null(policy)) {
    restore_source <- .wb_graph_aggregate_connection_budget(list(source_con),policy,extra=1L)
    on.exit(restore_source(),add=TRUE)
  }
  destination_con <- DBI::dbConnect(RSQLite::SQLite(), destination_path,cache_size=-cache_kib)
  on.exit(try(DBI::dbDisconnect(destination_con), silent = TRUE), add = TRUE,after=FALSE)
  .wb_sqlite_configure_connection(destination_con, writable = TRUE)
  if(!is.null(policy)) .wb_graph_scoped_connection_budget(destination_con,policy,cache_kib=cache_kib)

  RSQLite::sqliteCopyDatabase(source_con, destination_con)

  test_hook <- getOption("scworkbench.session_backup_test_hook")
  if (is.function(test_hook)) test_hook(source_con, destination_con, destination_path)

  quick_check <- DBI::dbGetQuery(destination_con, "PRAGMA quick_check;")[[1]]
  .wb_assert(length(quick_check) == 1L && identical(tolower(as.character(quick_check)), "ok"),
             "Session SQLite online backup failed PRAGMA quick_check verification.")
  source_tables <- DBI::dbGetQuery(
    source_con,
    "SELECT name, type, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name;"
  )
  destination_tables <- DBI::dbGetQuery(
    destination_con,
    "SELECT name, type, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name;"
  )
  .wb_assert(
    identical(source_tables, destination_tables),
    "Session SQLite online backup does not match the committed source schema."
  )
  invisible(TRUE)
}

.wb_session_graph_copy_bytes <- function(bundle,policy) {
  db_file_bytes <- file.info(file.path(bundle$dir,bundle$manifest$storage$sqlite$path))$size
  .wb_graph_require(length(db_file_bytes)==1L && is.finite(db_file_bytes),
    "GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE","Cannot measure session database copy.")
  bytes <- max(db_file_bytes,.wb_graph_disk_usage(bundle$con)$database_bytes) +
    4096*ceiling(file.info(file.path(bundle$dir,"manifest.json"))$size/4096)
  tree <- file.path(bundle$dir,"operation_pack_v2")
  if(dir.exists(tree)) {
    status <- .wb_path_tree_status(bundle$dir,"operation_pack_v2",purpose="owned session transition copy")
    .wb_graph_require(isTRUE(status$ok),"GRAPH_SOURCE_PAYLOAD_INVALID","Unsafe owned transition copy.")
    entries <- c(tree,unlist(.wb_graph_native_tree_entries(tree,policy),use.names=FALSE))
    for(entry in entries) {
      size <- file.info(entry)$size
      .wb_graph_require(length(size)==1L && is.finite(size) && size>=0,
        "GRAPH_RESOURCE_ACCOUNTING_UNAVAILABLE","Cannot measure owned transition copy.")
      bytes <- bytes + max(4096,4096*ceiling(size/4096))
    }
  }
  .wb_graph_require(is.finite(bytes) && bytes<=as.numeric(policy$token_bytes),
    "GRAPH_RESOURCE_EXCEEDED","Session database/manifest/owned transition copy exceeds combined scratch admission.")
  .wb_graph_storage_fault("session_copy_admitted",list(bytes=bytes,budgets=policy))
  bytes
}

.wb_session_stage_open <- function(bundle,stage_dir,copy_bytes=NULL) {
  if(is.null(bundle$con)) return(wb_open_bundle(stage_dir,validate=FALSE))
  policy <- bundle$con@ref$wb_graph_policy
  if(is.null(policy)) return(wb_open_bundle(stage_dir,validate=FALSE))
  if(is.null(copy_bytes)) {
    observed <- bundle
    observed$dir <- stage_dir
    copy_bytes <- .wb_session_graph_copy_bytes(observed,policy)
  }
  attr(policy,"wb_graph_session_copy_bytes") <- copy_bytes
  restore <- .wb_graph_aggregate_connection_budget(list(bundle$con),policy,extra=1L)
  on.exit(restore(),add=TRUE)
  opened <- .wb_open_bundle(stage_dir,validate=FALSE,graph_budgets=policy,
    graph_cache_kib=bundle$con@ref$wb_graph_cache_kib)
  opened$con@ref$wb_graph_session_copy_bytes <- copy_bytes
  opened
}

.wb_session_stage_bundle <- function(bundle, session) {
  .wb_assert(wb_is_session(session), "session must be wb_session")

  if (!is.null(session$staging_bundle) && inherits(session$staging_bundle, "scworkbench_bundle")) {
    if(!is.null(bundle$con) && !is.null(bundle$con@ref$wb_graph_policy)) session$staging_bundle$con@ref$wb_graph_session_copy_bytes <-
      .wb_session_graph_copy_bytes(session$staging_bundle,bundle$con@ref$wb_graph_policy)
    return(list(session = session, bundle = session$staging_bundle))
  }
  persisted_stage <- as.character(session$staging_dir %||% "")[1]
  if (nzchar(persisted_stage) && file.exists(file.path(persisted_stage, "manifest.json"))) {
    stage_bundle <- .wb_session_stage_open(bundle,persisted_stage)
    if(!is.null(bundle$con) && !is.null(bundle$con@ref$wb_graph_policy)) stage_bundle$con@ref$wb_graph_session_copy_bytes <-
      .wb_session_graph_copy_bytes(stage_bundle,bundle$con@ref$wb_graph_policy)
    stage_bundle$staging_source_dir <- as.character(session$staging_source_dir %||% "")[1]
    stage_bundle$staging_source_bundle <- bundle
    session$staging_bundle <- stage_bundle
    return(list(session = session, bundle = stage_bundle))
  }
  .wb_assert(inherits(bundle, "scworkbench_bundle"), "bundle must be scworkbench_bundle")

  # Session IDs label execution state, but callers may set the R RNG for
  # deterministic analyses. A filesystem staging path must remain unique even
  # if that produces the same generated session ID in a later session.
  stage_dir <- if (nzchar(persisted_stage)) persisted_stage else tempfile(
    pattern = paste0(as.character(session$session_id), "_"), tmpdir = .wb_session_stage_root()
  )
  dir.create(stage_dir, recursive = TRUE, showWarnings = FALSE)
  stage_ready <- FALSE
  on.exit({
    if (!isTRUE(stage_ready) && dir.exists(stage_dir)) {
      unlink(stage_dir, recursive = TRUE, force = TRUE)
    }
  }, add = TRUE)

  # Capture a coherent source snapshot under the committed bundle's lock. The
  # lock is released before the operation runs; later computation touches only
  # this private overlay and remains concurrent with committed writers.
  # Snapshotting is not a committed mutation. Own the same exclusive lock,
  # but do not use the mutation publisher: otherwise even a failed private
  # invocation durably rewrites the source manifest's publication timestamp.
  snapshot_lock <- .wb_bundle_writer_lock_acquire(bundle,
    operation = "session staging snapshot")
  tryCatch({
    copy_policy <- bundle$con@ref$wb_graph_policy
    copy_bytes <- if(is.null(copy_policy)) NULL else .wb_session_graph_copy_bytes(bundle,copy_policy)
    db_rel <- as.character(bundle$manifest$storage$sqlite$path)[1]
    .wb_session_sqlite_backup(bundle$con, file.path(stage_dir, db_rel))
    ok_manifest <- file.copy(file.path(bundle$dir, "manifest.json"), file.path(stage_dir, "manifest.json"), overwrite = FALSE)
    .wb_assert(isTRUE(ok_manifest), "Failed to copy bundle manifest into session staging.")

    roots <- list.files(bundle$dir, all.files = TRUE, no.. = TRUE)
    roots <- setdiff(roots, c("manifest.json", dirname(db_rel), ".git"))
    mutable <- c("mat", "models", "artifact_models", "space_payloads",
      "operation_pack_v2")
    for (nm in roots) {
      status <- if (nm %in% mutable && dir.exists(file.path(bundle$dir,nm))) {
        .wb_path_tree_status(bundle$dir,nm,purpose="session staging payload tree")
      } else .wb_path_status(bundle$dir,nm,expected_type="either",must_exist=TRUE,purpose="session staging payload root")
      .wb_assert(isTRUE(status$ok),paste0(status$code,": unsafe session staging payload root ",nm))
      src <- status$absolute
      dst <- file.path(stage_dir, nm)
      if (identical(nm, "operation_pack_v2") && dir.exists(src)) {
        # Retained transition manifests authenticate owned payload trees. Leaf
        # links outside the private record fail their containment checks and
        # recovery would remove matrix/model payloads referenced by the clone.
        # Copy the authenticated record tree without weakening its validator.
        fs::dir_copy(src, dst)
      } else if (nm %in% mutable && dir.exists(src)) {
        .wb_session_stage_link_children(src, dst)
      } else {
        ok <- file.symlink(src, dst)
        .wb_assert(isTRUE(ok), paste0("Failed to link bundle payload root into session staging: ", src))
      }
    }
    # ABI v2 creates its private transition root lazily. An eager empty root is
    # observable to the legacy PyBench payload-diff publisher and can change
    # which nested model tree it publishes. Existing transition roots still
    # enter the copy-on-write branch above.
    for (nm in setdiff(mutable, "operation_pack_v2")) {
      dir.create(file.path(stage_dir, nm), recursive = TRUE,
        showWarnings = FALSE)
    }
  }, finally = .wb_bundle_writer_lock_release(snapshot_lock))

  stage_bundle <- .wb_session_stage_open(bundle,stage_dir,copy_bytes)
  if(!is.null(copy_bytes)) stage_bundle$con@ref$wb_graph_session_copy_bytes <- copy_bytes
  # Runners receive this overlay bundle directly. Retain the known source
  # bundle location solely to resolve already-promoted artifact references
  # created after the overlay snapshot; no filesystem search is performed.
  stage_bundle$staging_source_dir <- normalizePath(bundle$dir, winslash = "/", mustWork = TRUE)
  stage_bundle$staging_source_bundle <- bundle
  session$staging_dir <- stage_dir
  session$staging_bundle <- stage_bundle
  session$staging_source_dir <- stage_bundle$staging_source_dir
  stage_ready <- TRUE
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
  # Graph staging databases are core-owned, bounded scratch outside the bundle.
  # Discard them explicitly; waiting for GC is not a lifecycle cleanup boundary.
  for (run in session$runs %||% list()) for (value in run$outputs %||% list()) {
    if (is.list(value) && identical(value$kind, "graph")) {
      graph_stage <- attr(value, "graph_stage", exact = TRUE)
      if (is.environment(graph_stage)) .wb_graph_stage_discard(graph_stage)
    }
  }
  stage_dir <- as.character(session$staging_dir %||% "")[1]
  if (!is.null(session$durable)) {
    workspace <- as.character(session$durable$workspace %||% "")[1]
    root <- as.character(session$durable$workspace_root %||% dirname(workspace))[1]
    .wb_session_contained_path(root, workspace, "discard workspace")
    .wb_session_workspace_lock(session, "discard", {
      .wb_session_assert_mutation_owner(session)
      if (!is.null(session$staging_bundle) && inherits(session$staging_bundle, "scworkbench_bundle")) {
        try(wb_close_bundle(session$staging_bundle), silent = TRUE)
      }
      # `workspace` is a validated owned directory, never a link followed from
      # stage into the source bundle.
      unlink(workspace, recursive = TRUE, force = TRUE)
    })
  } else {
    if (!is.null(session$staging_bundle) && inherits(session$staging_bundle, "scworkbench_bundle")) {
      try(wb_close_bundle(session$staging_bundle), silent = TRUE)
    }
    if (nzchar(stage_dir) && dir.exists(stage_dir)) unlink(stage_dir, recursive = TRUE, force = TRUE)
  }
  session$staging_bundle <- NULL
  session$staging_dir <- NULL
  session$staging_source_dir <- NULL
  session$durable <- NULL
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
