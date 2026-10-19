.engine_backup_fixture <- function() {
  root <- tempfile("backup_source_"); b <- wb_init_bundle(root)
  wb_define_cells(b, paste0("cell_", 1:4))
  scworkbench:::.wb_session_source_identity(b)
  list(bundle = b, root = root, close = function() {
    if (DBI::dbIsValid(b$con)) wb_close_bundle(b)
    unlink(root, recursive = TRUE)
  })
}
.engine_backup_swap <- function(package, name, replacement) {
  ns <- asNamespace(package); original <- get(name, ns, inherits = FALSE)
  unlockBinding(name, ns); assign(name, replacement, ns); lockBinding(name, ns)
  function() {unlockBinding(name, ns); assign(name, original, ns); lockBinding(name, ns)}
}
.engine_backup_copy <- function(bundle, directory) {
  path <- tempfile("backup_destination_", tmpdir = directory, fileext = ".sqlite")
  scworkbench:::.wb_session_sqlite_backup(bundle$con, path); path
}

# Literal df8db854 .wb_session_sqlite_backup, not a candidate-derived oracle.
.engine_backup_df8_oracle <- function(source_con, destination_path) {
  .wb_session_source_forget(source_con)
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

test_engine_backup_original_actual_observation_and_other_forget_slots_contract <- function() {
  fixture <- .engine_backup_fixture(); b <- fixture$bundle
  on.exit(fixture$close(), add = TRUE)
  original <- b$con@ref$wb_session_source_observation
  # A source assembly bundle is not an engine-created session stage. Use the
  # legitimate source ingestion context to check invocation-observation clearing.
  scworkbench:::.wb_with_mutation_context(b, route = "ingestion", code = {
    context <- scworkbench:::.wb_current_mutation_context(b$con)
    context$observations$registry <- list(not_authority = TRUE)
    b$con@ref$wb_schema_structure_observation <- list(not_authority = TRUE)
    b$con@ref$wb_manifest_publication_witness <- list(not_authority = TRUE)
    b$con@ref$wb_graph_retained_observation <- list(not_authority = TRUE)
    path <- .engine_backup_copy(b, fixture$root)
    stopifnot(identical(original, b$con@ref$wb_session_source_observation),
      is.null(context$observations$registry), is.null(b$con@ref$wb_schema_structure_observation),
      is.null(b$con@ref$wb_manifest_publication_witness), is.null(b$con@ref$wb_graph_retained_observation))
    destination <- DBI::dbConnect(RSQLite::SQLite(), path, flags = RSQLite::SQLITE_RO)
    tryCatch({
      stopifnot(is.null(destination@ref$wb_session_source_observation),
        identical(scworkbench:::.wb_manifest_registry_snapshot(b$con),
          scworkbench:::.wb_manifest_registry_snapshot(destination)))
    }, finally = DBI::dbDisconnect(destination))
  })
  TRUE
}

test_engine_backup_source_mutation_rollback_and_external_commit_contract <- function() {
  for (kind in c("DML", "DDL", "rollback", "foreign_WAL")) {
    fixture <- .engine_backup_fixture(); b <- fixture$bundle; other <- NULL
    tryCatch({
      original <- b$con@ref$wb_session_source_observation
      if (kind == "foreign_WAL") {
        DBI::dbGetQuery(b$con, "PRAGMA journal_mode=WAL")
        other <- DBI::dbConnect(RSQLite::SQLite(), file.path(fixture$root, "db/app.sqlite"))
        scworkbench:::.wb_session_source_identity(b); original <- b$con@ref$wb_session_source_observation
      }
      copy <- get("sqliteCopyDatabase", asNamespace("RSQLite"))
      undo <- .engine_backup_swap("RSQLite", "sqliteCopyDatabase", function(from, to) {
        answer <- copy(from, to)
        if (kind == "DML") DBI::dbExecute(from, "UPDATE cells SET dataset_id='changed' WHERE cell_id='cell_1'")
        if (kind == "DDL") DBI::dbExecute(from, "CREATE TABLE backup_extra(value INTEGER)")
        if (kind == "rollback") {
          DBI::dbBegin(from)
          tryCatch(DBI::dbExecute(from, "UPDATE cells SET dataset_id='rolled_back' WHERE cell_id='cell_1'"),
            finally = DBI::dbRollback(from))
        }
        if (kind == "foreign_WAL") DBI::dbExecute(other, "UPDATE cells SET dataset_id='foreign' WHERE cell_id='cell_1'")
        answer
      })
      error <- tryCatch(.engine_backup_copy(b, fixture$root), error = identity)
      undo()
      if (kind == "DDL") stopifnot(inherits(error, "error"), grepl("committed source schema", conditionMessage(error))) else stopifnot(!inherits(error, "error"))
      stopifnot(is.null(b$con@ref$wb_session_source_observation))
      current <- scworkbench:::.wb_session_source_identity(b)
      stopifnot(!is.null(b$con@ref$wb_session_source_observation))
      if (kind == "rollback") stopifnot(identical(original$state$fingerprint, current$scientific_state_fingerprint))
    }, finally = {
      if (exists("undo", inherits = FALSE)) {undo(); rm(undo)}
      if (!is.null(other) && DBI::dbIsValid(other)) DBI::dbDisconnect(other)
      fixture$close()
    })
  }
  TRUE
}

test_engine_backup_errors_hooks_unknown_epoch_and_cleanup_contract <- function() {
  fixture <- .engine_backup_fixture(); b <- fixture$bundle
  option <- getOption("scworkbench.session_backup_test_hook")
  on.exit({options(scworkbench.session_backup_test_hook = option); fixture$close()}, add = TRUE)
  for (hook in list(function(...) invisible(NULL), FALSE, function(...) stop("BACKUP_HOOK_ERROR"))) {
    scworkbench:::.wb_session_source_identity(b)
    options(scworkbench.session_backup_test_hook = hook)
    result <- tryCatch(.engine_backup_copy(b, fixture$root), error = identity)
    stopifnot(is.null(b$con@ref$wb_session_source_observation))
    if (is.function(hook) && inherits(result, "error")) stopifnot(grepl("BACKUP_HOOK_ERROR", conditionMessage(result)))
    options(scworkbench.session_backup_test_hook = NULL)
  }
  scworkbench:::.wb_session_source_identity(b)
  query <- get("dbGetQuery", asNamespace("DBI"))
  undo <- .engine_backup_swap("DBI", "dbGetQuery", function(conn, statement, ...) {
    if (identical(conn@ref, b$con@ref) && identical(statement, "SELECT total_changes();")) return(data.frame(value = NA_real_))
    query(conn, statement, ...)
  })
  tryCatch(.engine_backup_copy(b, fixture$root), finally = undo())
  stopifnot(is.null(b$con@ref$wb_session_source_observation))
  scworkbench:::.wb_session_source_identity(b)
  disconnect <- get("dbDisconnect", asNamespace("DBI")); injected <- FALSE
  undo <- .engine_backup_swap("DBI", "dbDisconnect", function(conn, ...) {
    if (!identical(conn@ref, b$con@ref) && !injected) {injected <<- TRUE; stop("BACKUP_CLOSE_ERROR")}
    disconnect(conn, ...)
  })
  tryCatch(.engine_backup_copy(b, fixture$root), finally = undo())
  stopifnot(injected, is.null(b$con@ref$wb_session_source_observation))
  # Destination collision and real backup failure also leave the original slot gone.
  scworkbench:::.wb_session_source_identity(b)
  path <- tempfile(tmpdir = fixture$root); file.create(path)
  error <- tryCatch(scworkbench:::.wb_session_sqlite_backup(b$con, path), error = identity)
  stopifnot(inherits(error, "error"), is.null(b$con@ref$wb_session_source_observation))
  scworkbench:::.wb_session_source_identity(b)
  undo <- .engine_backup_swap("RSQLite", "sqliteCopyDatabase", function(...) stop("BACKUP_COPY_ERROR"))
  error <- tryCatch(.engine_backup_copy(b, fixture$root), error = identity)
  undo()
  stopifnot(inherits(error, "error"), grepl("BACKUP_COPY_ERROR", conditionMessage(error)), is.null(b$con@ref$wb_session_source_observation))
  # A real policy restore can fail after completing its own work. No success
  # observation may be installed before that last fallible cleanup returns.
  p <- scworkbench:::.wb_graph_budgets(list(memory_bytes = "8388608",
    sqlite_cache_kib = 512L, partition_bytes = 65536, collect_bytes = 1048576))
  restore_policy <- scworkbench:::.wb_graph_scoped_connection_budget(b$con, p)
  scworkbench:::.wb_session_source_identity(b)
  aggregate <- get(".wb_graph_aggregate_connection_budget", asNamespace("scworkbench"))
  undo <- .engine_backup_swap("scworkbench", ".wb_graph_aggregate_connection_budget", function(...) {
    restore <- aggregate(...)
    function() {restore(); stop("SOURCE_POLICY_CLEANUP_ERROR")}
  })
  error <- tryCatch(.engine_backup_copy(b, fixture$root), error = identity)
  undo(); restore_policy()
  stopifnot(inherits(error, "error"), grepl("SOURCE_POLICY_CLEANUP_ERROR", conditionMessage(error)), is.null(b$con@ref$wb_session_source_observation))
  # Do not overwrite an observation made during the backup by another legitimate
  # boundary. Its state is freshly obtained, not taken from a manifest claim.
  scworkbench:::.wb_session_source_identity(b)
  copy <- get("sqliteCopyDatabase", asNamespace("RSQLite"))
  newer <- NULL
  undo <- .engine_backup_swap("RSQLite", "sqliteCopyDatabase", function(from, to) {
    answer <- copy(from, to); scworkbench:::.wb_session_source_identity(b)
    newer <<- from@ref$wb_session_source_observation; newer$test_distinguishing_field <<- TRUE
    from@ref$wb_session_source_observation <- newer
    answer
  })
  tryCatch(.engine_backup_copy(b, fixture$root), finally = undo())
  stopifnot(identical(newer, b$con@ref$wb_session_source_observation))
  # The old helper also permits independent issuance inside a failing hook.
  # Preserve that evidence; never restore the pre-backup original on this path.
  old <- .engine_backup_df8_oracle
  environment(old) <- asNamespace("scworkbench")
  for (backup in list(old, scworkbench:::.wb_session_sqlite_backup)) {
    options(scworkbench.session_backup_test_hook = NULL)
    scworkbench:::.wb_session_source_identity(b)
    original <- b$con@ref$wb_session_source_observation
    issued <- NULL; hook_calls <- 0L
    options(scworkbench.session_backup_test_hook = function(from, to, path) {
      hook_calls <<- hook_calls + 1L
      stopifnot(is.null(from@ref$wb_session_source_observation))
      scworkbench:::.wb_session_source_identity(b)
      issued <<- from@ref$wb_session_source_observation
      stop("BACKUP_AFTER_INDEPENDENT_ISSUANCE")
    })
    error <- tryCatch(backup(b$con, tempfile(tmpdir = fixture$root)), error = identity)
    stopifnot(inherits(error, "error"),
      identical(conditionMessage(error), "BACKUP_AFTER_INDEPENDENT_ISSUANCE"),
      hook_calls == 1L, !is.null(issued),
      identical(issued, b$con@ref$wb_session_source_observation),
      identical(original$epoch, issued$epoch),
      identical(original$state, issued$state))
    options(scworkbench.session_backup_test_hook = NULL)
  }
  TRUE
}

test_engine_backup_no_transfer_no_transaction_no_lost_lock_reuse_contract <- function() {
  fixture <- .engine_backup_fixture(); b <- fixture$bundle
  on.exit(fixture$close(), add = TRUE)
  other <- DBI::dbConnect(RSQLite::SQLite(), file.path(fixture$root, "db/app.sqlite"))
  on.exit(if (DBI::dbIsValid(other)) DBI::dbDisconnect(other), add = TRUE)
  original <- b$con@ref$wb_session_source_observation
  scworkbench:::.wb_session_sqlite_backup(other, tempfile(tmpdir = fixture$root))
  stopifnot(is.null(other@ref$wb_session_source_observation), identical(original, b$con@ref$wb_session_source_observation))
  DBI::dbBegin(b$con)
  # Existing backup may reject an active source transaction; either way its
  # unsupported source observation must remain cleared, never rebased.
  tryCatch(.engine_backup_copy(b, fixture$root), error = function(error) invisible(NULL), finally = DBI::dbRollback(b$con))
  stopifnot(is.null(b$con@ref$wb_session_source_observation))
  scworkbench:::.wb_session_source_identity(b)
  scworkbench:::.wb_unregister_assembly_connection(b$con)
  stopifnot(!scworkbench:::.wb_writer_lock_held(b))
  .engine_backup_copy(b, fixture$root)
  stopifnot(is.null(b$con@ref$wb_session_source_observation))
  TRUE
}

test_engine_backup_public_session_and_pybench_clone_preimage_contract <- function() {
  fixture <- .engine_backup_fixture(); b <- fixture$bundle; session <- NULL; clone <- NULL
  workspace <- tempfile("backup_session_workspace_")
  on.exit({
    if (!is.null(session)) wb_session_discard(session)
    if (!is.null(clone)) {if (DBI::dbIsValid(clone$bundle$con)) wb_close_bundle(clone$bundle); unlink(clone$root, recursive = TRUE)}
    fixture$close(); unlink(workspace, recursive = TRUE)
  }, add = TRUE)
  original <- b$con@ref$wb_session_source_observation
  session <- wb_session_create(b, workspace_root = workspace, session_id = "continuity")
  stopifnot(identical(original, b$con@ref$wb_session_source_observation),
    is.null(session$staging_bundle$con@ref$wb_session_source_observation))
  session <- wb_session_discard(session); session <- NULL
  clone <- scworkbench:::.wb_pybench_clone_bundle(b)
  stopifnot(identical(original, b$con@ref$wb_session_source_observation), is.null(clone$bundle$con@ref$wb_session_source_observation))
  DBI::dbExecute(clone$bundle$con, "UPDATE cells SET dataset_id='published' WHERE cell_id='cell_1'")
  scworkbench:::.wb_pybench_publish_transition(clone$bundle, b, list(), list())
  # Preimage backup is read-only, but the following actual publication MUST
  # still forget the source observation before replacing destination SQLite.
  stopifnot(is.null(b$con@ref$wb_session_source_observation),
    DBI::dbGetQuery(b$con, "SELECT dataset_id FROM cells WHERE cell_id='cell_1'")$dataset_id[[1L]] == "published")
  TRUE
}
