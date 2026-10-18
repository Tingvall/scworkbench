.engine_initializer_spy <- function(failure = NULL) {
  ns <- asNamespace("scworkbench"); state <- new.env(parent = emptyenv())
  state$migrations <- 0L; state$opens <- 0L; state$con <- list(); state$restored <- FALSE
  names <- c(".wb_schema_migrate_connection", "wb_open_bundle", ".wb_register_assembly_bundle")
  original <- setNames(lapply(names, get, envir = ns), names)
  replacements <- list(
    .wb_schema_migrate_connection = function(con, ...) {
      state$migrations <- state$migrations + 1L
      state$con[[length(state$con) + 1L]] <- con
      if (identical(failure, "migration")) stop("initializer migration fault")
      original$.wb_schema_migrate_connection(con, ...)
    },
    wb_open_bundle = function(...) {
      state$opens <- state$opens + 1L
      original$wb_open_bundle(...)
    },
    .wb_register_assembly_bundle = function(bundle, writer_lock) {
      original$.wb_register_assembly_bundle(bundle, writer_lock)
      if (identical(failure, "registration")) stop("initializer partial registration fault")
      invisible(bundle)
    })
  locked <- vapply(names, bindingIsLocked, logical(1), env = ns)
  for (name in names) {
    if (locked[[name]]) unlockBinding(name, ns)
    assign(name, replacements[[name]], ns)
    if (locked[[name]]) lockBinding(name, ns)
  }
  restore <- function() {
    if (state$restored) return(invisible(NULL))
    for (name in names) {
      if (bindingIsLocked(name, ns)) unlockBinding(name, ns)
      assign(name, original[[name]], ns)
      if (locked[[name]]) lockBinding(name, ns)
    }
    state$restored <- TRUE
  }
  list(state = state, restore = restore)
}

.engine_initializer_close <- function(bundle, root) {
  if (!is.null(bundle) && DBI::dbIsValid(bundle$con)) wb_close_bundle(bundle)
  unlink(root, recursive = TRUE, force = TRUE)
}

test_engine_fresh_initializer_schema_and_connection_contract <- function() {
  root <- tempfile("fresh_initializer_"); bundle <- NULL
  on.exit(.engine_initializer_close(bundle, root), add = TRUE)
  spy <- .engine_initializer_spy()
  on.exit(spy$restore(), add = TRUE, after = FALSE)
  bundle <- tryCatch(wb_init_bundle(root, bundle_id = "fresh_contract", bundle_name = "Fresh contract"),
    finally = spy$restore())
  stopifnot(spy$state$migrations == 1L, spy$state$opens == 0L,
    identical(bundle$con, spy$state$con[[1L]]), DBI::dbIsValid(bundle$con),
    identical(names(bundle), c("dir", "manifest", "con", "read_only")),
    identical(class(bundle), "scworkbench_bundle"), identical(bundle$read_only, FALSE),
    DBI::dbGetQuery(bundle$con, "PRAGMA cache_size;")[[1L]][[1L]] == -2000L,
    DBI::dbGetQuery(bundle$con, "PRAGMA foreign_keys;")[[1L]][[1L]] == 1L,
    !RSQLite::sqliteIsTransacting(bundle$con),
    identical(wb_bundle_schema_status(bundle)$status, "current"),
    scworkbench:::.wb_is_assembly_connection(bundle$con),
    identical(bundle$manifest, jsonlite::read_json(file.path(root, "manifest.json"), simplifyVector = TRUE)),
    identical(bundle$manifest$current_state$fingerprint,
      scworkbench:::.wb_manifest_registry_snapshot(bundle$con)$fingerprint),
    length(wb_cells(bundle, cell_set = "all")) == 0L,
    nrow(wb_matrices(bundle)) == 0L, nrow(wb_spaces(bundle)) == 0L,
    nrow(wb_art_list(bundle)) == 0L)
  schema <- DBI::dbGetQuery(bundle$con, "SELECT type,name,tbl_name,sql FROM sqlite_schema ORDER BY type,name,tbl_name,sql;")
  ledger <- DBI::dbGetQuery(bundle$con, "SELECT * FROM bundle_schema_migrations ORDER BY version;")
  wb_finalize_recipient_bundle(bundle); wb_close_bundle(bundle)
  bundle <- wb_open_bundle(root)
  stopifnot(identical(schema, DBI::dbGetQuery(bundle$con,
    "SELECT type,name,tbl_name,sql FROM sqlite_schema ORDER BY type,name,tbl_name,sql;")),
    identical(ledger, DBI::dbGetQuery(bundle$con, "SELECT * FROM bundle_schema_migrations ORDER BY version;")),
    DBI::dbGetQuery(bundle$con, "PRAGMA cache_size;")[[1L]][[1L]] == -2000L)
  TRUE
}

test_engine_fresh_initializer_changed_publication_fallback_contract <- function() {
  for (mode in c("SQL", "rollback", "DDL_reset", "manifest")) {
    root <- tempfile("fresh_initializer_changed_"); bundle <- NULL
    spy <- .engine_initializer_spy()
    hook <- getOption("scworkbench.manifest_test_hook"); fired <- FALSE
    tryCatch({
      options(scworkbench.manifest_test_hook = function(event, final, ...) {
        if (!identical(event, "published") || fired) return(invisible(NULL))
        fired <<- TRUE; con <- spy$state$con[[1L]]
        if (mode == "SQL") DBI::dbExecute(con,
          "INSERT INTO datasets(dataset_id,n_cells) VALUES('hook_dataset',0);")
        if (mode == "rollback") {
          DBI::dbBegin(con)
          DBI::dbExecute(con, "INSERT INTO datasets(dataset_id,n_cells) VALUES('rolled_back',0);")
          DBI::dbRollback(con)
        }
        if (mode == "DDL_reset") {
          version <- DBI::dbGetQuery(con, "PRAGMA main.schema_version;")[[1L]][[1L]]
          DBI::dbExecute(con, "CREATE TABLE initializer_extra(value TEXT);")
          DBI::dbExecute(con, paste0("PRAGMA main.schema_version=", version, ";"))
        }
        if (mode == "manifest") {
          manifest <- jsonlite::read_json(final, simplifyVector = FALSE)
          manifest$current_state$fingerprint <- "unrelated_posthook_manifest"
          jsonlite::write_json(manifest, final, auto_unbox = TRUE)
        }
      })
      bundle <- tryCatch(wb_init_bundle(root), finally = {
        spy$restore(); options(scworkbench.manifest_test_hook = hook)
      })
      stopifnot(fired, spy$state$opens == 1L, spy$state$migrations == 2L,
        !DBI::dbIsValid(spy$state$con[[1L]]), DBI::dbIsValid(bundle$con),
        !identical(bundle$con, spy$state$con[[1L]]),
        identical(bundle$manifest, jsonlite::read_json(file.path(root, "manifest.json"), simplifyVector = TRUE)),
        identical(bundle$manifest$current_state$fingerprint,
          scworkbench:::.wb_manifest_registry_snapshot(bundle$con)$fingerprint))
      if (mode == "SQL") stopifnot(bundle$manifest$current_state$tables$datasets$row_count == 1L)
      if (mode == "rollback") stopifnot(bundle$manifest$current_state$tables$datasets$row_count == 0L)
    }, finally = {
      spy$restore(); options(scworkbench.manifest_test_hook = hook)
      .engine_initializer_close(bundle, root)
    })
  }
  TRUE
}

test_engine_fresh_initializer_fault_cleanup_contract <- function() {
  for (mode in c("migration", "registration", "publication", "malformed_manifest", "ledger")) {
    root <- tempfile("fresh_initializer_fault_")
    before <- scworkbench:::.wb_mutation_boundary_state$assembly_connections
    spy <- .engine_initializer_spy(failure = mode)
    hook <- getOption("scworkbench.manifest_test_hook"); fired <- FALSE
    tryCatch({
      options(scworkbench.manifest_test_hook = function(event, final, ...) {
        if (mode == "publication" && event == "before_publish") stop("initializer publication fault")
        if (!event == "published" || fired) return(invisible(NULL))
        fired <<- TRUE
        if (mode == "malformed_manifest") writeLines("not JSON", final)
        if (mode == "ledger") DBI::dbExecute(spy$state$con[[1L]],
          "UPDATE bundle_schema_migrations SET migration_id='unrecognized' WHERE version=1;")
      })
      failure <- tryCatch(wb_init_bundle(root), error = identity, finally = {
        spy$restore(); options(scworkbench.manifest_test_hook = hook)
      })
      stopifnot(inherits(failure, "error"), length(spy$state$con) >= 1L,
        all(!vapply(spy$state$con, DBI::dbIsValid, logical(1))),
        identical(before, scworkbench:::.wb_mutation_boundary_state$assembly_connections),
        !isTRUE(wb_bundle_writer_lock_info(root)$locked))
    }, finally = {
      spy$restore(); options(scworkbench.manifest_test_hook = hook)
      unlink(root, recursive = TRUE, force = TRUE)
    })
  }
  TRUE
}

test_engine_fresh_initializer_assembly_recipient_contract <- function() {
  root <- tempfile("fresh_initializer_recipient_"); bundle <- NULL
  on.exit(.engine_initializer_close(bundle, root), add = TRUE)
  bundle <- wb_init_bundle(root)
  cells <- c("c2", "c1"); features <- c("g2", "g1", "g3")
  values <- Matrix::Matrix(matrix(1:6, 3L, dimnames = list(features, cells)), sparse = TRUE)
  wb_define_cells(bundle, cells)
  wb_attach_matrix(bundle, "counts", values, feature_type = "gene")
  wb_finalize_recipient_bundle(bundle); wb_close_bundle(bundle)
  bundle <- wb_open_bundle(root, read_only = TRUE)
  stopifnot(identical(as.matrix(wb_slice(bundle, "counts", features = features, cells = cells)), as.matrix(values)),
    isTRUE(wb_bundle_validation_report(root, level = "recipient")$ok))
  TRUE
}
