.engine_publication_witness_fixture <- function() {
  root <- tempfile("engine_publication_witness_")
  b <- wb_init_bundle(root)
  list(bundle = b, root = root)
}

test_engine_publication_witness_unchanged_and_explicit_contract <- function() {
  f <- .engine_publication_witness_fixture(); b <- f$bundle
  hook <- getOption("scworkbench.manifest_test_hook"); publications <- 0L
  on.exit({options(scworkbench.manifest_test_hook = hook);
    if (DBI::dbIsValid(b$con)) try(wb_close_bundle(b), silent = TRUE);
    unlink(f$root, recursive = TRUE)}, add = TRUE)
  options(scworkbench.manifest_test_hook = function(event, ...) {
    if (event == "published") publications <<- publications + 1L
  })
  wb_refresh_manifest(b) # Explicit public refresh is never memoized.
  stopifnot(publications == 1L, scworkbench:::.wb_manifest_publication_reusable(b))
  scworkbench:::.wb_with_bundle_writer_lock(b, operation = "empty nested assembly", code = TRUE)
  stopifnot(publications == 1L)
  wb_refresh_manifest(b)
  stopifnot(publications == 2L)
  wb_migrate_bundle(b) # Explicit migration always republishes after full admission.
  stopifnot(publications == 3L)
  wb_finalize_recipient_bundle(b)
  closed_count <- publications
  wb_close_bundle(b)
  stopifnot(publications == closed_count, !DBI::dbIsValid(b$con))
  changed <- .engine_publication_witness_fixture(); b2 <- changed$bundle
  on.exit({if (DBI::dbIsValid(b2$con)) try(wb_close_bundle(b2), silent = TRUE);
    unlink(changed$root, recursive = TRUE)}, add = TRUE)
  wb_refresh_manifest(b2); wb_finalize_recipient_bundle(b2)
  before_close <- publications
  DBI::dbExecute(b2$con, "INSERT INTO cells(cell_id) VALUES('written_after_finalize');")
  wb_close_bundle(b2)
  durable <- jsonlite::read_json(file.path(changed$root, "manifest.json"), simplifyVector = TRUE)
  stopifnot(publications == before_close + 1L,
    durable$current_state$tables$cells$row_count == 1L)
  TRUE
}

test_engine_publication_witness_sql_rollback_schema_and_attachment_contract <- function() {
  f <- .engine_publication_witness_fixture(); b <- f$bundle
  on.exit({if (DBI::dbIsValid(b$con)) try(wb_close_bundle(b), silent = TRUE);
    unlink(f$root, recursive = TRUE)}, add = TRUE)
  reusable <- scworkbench:::.wb_manifest_publication_reusable
  publications <- 0L
  publish <- function() {
    publications <<- publications + 1L
    wb_refresh_manifest(b)
    # Scoped temp_store restoration can reset an already emptied TEMP schema's
    # version during the build. That conservative epoch miss must rebuild, not
    # certify the old epoch; a second explicit refresh observes stable state.
    if (!reusable(b)) wb_refresh_manifest(b)
    if (!reusable(b)) stop("Fresh publication witness unavailable at checkpoint ", publications)
  }
  publish()
  DBI::dbExecute(b$con, "INSERT INTO cells(cell_id) VALUES('direct_sql');")
  stopifnot(!reusable(b)); publish()
  DBI::dbBegin(b$con)
  stopifnot(!reusable(b))
  DBI::dbRollback(b$con); publish()
  DBI::dbBegin(b$con)
  DBI::dbExecute(b$con, "UPDATE cells SET cell_id='rolled_back' WHERE cell_id='direct_sql';")
  DBI::dbRollback(b$con)
  stopifnot(!reusable(b)); publish()
  schema_version <- DBI::dbGetQuery(b$con, "PRAGMA main.schema_version;")[[1L]][[1L]]
  DBI::dbExecute(b$con, "CREATE TABLE witness_extra (x TEXT);")
  DBI::dbExecute(b$con, paste0("PRAGMA main.schema_version=", schema_version, ";"))
  stopifnot(!reusable(b)); publish()
  DBI::dbExecute(b$con, "CREATE TEMP TABLE witness_temp (x TEXT);")
  stopifnot(!reusable(b))
  # Existing scoped-memory policy deliberately refuses TEMP tables if it would
  # change temp_store; use FILE explicitly before constructing the fixture TEMP.
  DBI::dbExecute(b$con, "DROP TABLE temp.witness_temp;")
  publish()
  extra <- tempfile("engine_witness_attached_", fileext = ".sqlite")
  on.exit(unlink(extra), add = TRUE)
  DBI::dbExecute(b$con, "ATTACH DATABASE ? AS witness_attached;", params = list(extra))
  stopifnot(!reusable(b)); publish()
  DBI::dbExecute(b$con, "CREATE TABLE witness_attached.test (value TEXT);")
  DBI::dbExecute(b$con, "INSERT INTO witness_attached.test VALUES('original');")
  publish()
  external <- DBI::dbConnect(RSQLite::SQLite(), extra)
  DBI::dbExecute(external, "UPDATE test SET value='external_commit';")
  DBI::dbDisconnect(external)
  stopifnot(!reusable(b)); publish()
  DBI::dbExecute(b$con, "DETACH DATABASE witness_attached;")
  stopifnot(!reusable(b)); publish()
  # Same raw assembly lock remains held: a nested normal mutation still publishes.
  scworkbench:::.wb_with_bundle_writer_lock(b, operation = "nested direct SQL", code = {
    DBI::dbExecute(b$con, "INSERT INTO cells(cell_id) VALUES('nested_sql');")
  })
  stopifnot(reusable(b), identical(wb_manifest(b)$current_state$fingerprint,
    wb_manifest(b, "reconstructed")$current_state$fingerprint))
  TRUE
}

test_engine_publication_witness_tamper_failure_and_reconnect_contract <- function() {
  f <- .engine_publication_witness_fixture(); b <- f$bundle
  hook <- getOption("scworkbench.manifest_test_hook")
  on.exit({options(scworkbench.manifest_test_hook = hook);
    if (DBI::dbIsValid(b$con)) try(wb_close_bundle(b), silent = TRUE);
    unlink(f$root, recursive = TRUE)}, add = TRUE)
  wb_refresh_manifest(b)
  path <- file.path(f$root, "manifest.json")
  original <- readBin(path, "raw", n = file.info(path)$size)
  append <- file(path, "ab"); writeBin(charToRaw("\n"), append); close(append)
  stopifnot(!scworkbench:::.wb_manifest_publication_reusable(b))
  wb_refresh_manifest(b)
  options(scworkbench.manifest_test_hook = function(event, ...) {
    if (event == "published") {
      replacement <- file(path, "ab")
      writeBin(charToRaw("\n"), replacement); close(replacement)
    }
  })
  wb_refresh_manifest(b)
  stopifnot(is.null(b$con@ref$wb_manifest_publication_witness))
  options(scworkbench.manifest_test_hook = hook)
  wb_refresh_manifest(b)
  old <- readBin(path, "raw", n = file.info(path)$size)
  options(scworkbench.manifest_test_hook = function(event, ...) {
    if (event == "before_publish") stop("WITNESS_PUBLICATION_FAULT")
  })
  failure <- tryCatch(scworkbench:::.wb_with_bundle_writer_lock(b, code = {
    DBI::dbExecute(b$con, "INSERT INTO cells(cell_id) VALUES('committed_before_fault');")
  }), error = identity)
  stopifnot(inherits(failure, "error"), grepl("WITNESS_PUBLICATION_FAULT", conditionMessage(failure)),
    identical(readBin(path, "raw", n = file.info(path)$size), old),
    is.null(b$con@ref$wb_manifest_publication_witness))
  options(scworkbench.manifest_test_hook = hook)
  wb_refresh_manifest(b)
  stopifnot(scworkbench:::.wb_manifest_publication_reusable(b),
    !identical(readBin(path, "raw", n = file.info(path)$size), old))
  old_reference <- b$con@ref
  wb_finalize_recipient_bundle(b); wb_close_bundle(b)
  b <- wb_open_bundle(f$root, read_only = FALSE, validate = FALSE)
  witness <- b$con@ref$wb_manifest_publication_witness
  # Writable open can itself publish after migration. That is a NEW witness,
  # never an inherited reference/owner epoch from the closed connection.
  stopifnot(is.null(witness) || !identical(witness$epoch$connection, old_reference))
  # No witness carries across connections, even for identical files/owner path.
  lock <- scworkbench:::.wb_bundle_writer_lock_acquire(b)
  on.exit(scworkbench:::.wb_bundle_writer_lock_release(lock), add = TRUE)
  stopifnot(!scworkbench:::.wb_manifest_publication_reusable(b))
  TRUE
}

test_engine_publication_witness_close_active_transaction_contract <- function() {
  f <- .engine_publication_witness_fixture(); b <- f$bundle
  on.exit({if (DBI::dbIsValid(b$con)) try(wb_close_bundle(b), silent = TRUE);
    unlink(f$root, recursive = TRUE)}, add = TRUE)
  wb_refresh_manifest(b); wb_finalize_recipient_bundle(b)
  path <- file.path(f$root, "manifest.json")
  bytes <- readBin(path, "raw", n = file.info(path)$size)
  DBI::dbBegin(b$con)
  DBI::dbExecute(b$con, "INSERT INTO cells(cell_id) VALUES('never_committed');")
  failure <- tryCatch(wb_close_bundle(b), error = identity)
  stopifnot(inherits(failure, "error"),
    grepl("Manifest publication cannot precede the committed SQLite transaction", conditionMessage(failure), fixed = TRUE),
    !DBI::dbIsValid(b$con), identical(readBin(path, "raw", n = file.info(path)$size), bytes))
  recipient <- wb_open_bundle(f$root, read_only = TRUE, validate = FALSE)
  on.exit(wb_close_bundle(recipient), add = TRUE)
  stopifnot(DBI::dbGetQuery(recipient$con, "SELECT COUNT(*) n FROM cells;")$n[[1L]] == 0L,
    !wb_bundle_writer_lock_info(f$root)$locked)
  TRUE
}
