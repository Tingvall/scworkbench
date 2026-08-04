# Central owner for the durable bundle schema and its ordered migrations.
# Component schema helpers remain compatibility shims for callers inside the
# package, but only this file orchestrates schema creation and upgrades.

.wb_bundle_schema_version <- function() 3L

.wb_bundle_schema_migrations <- function() {
  list(
    list(version = 1L, id = "001_consolidate_durable_schema", apply = .wb_schema_migration_001),
    list(version = 2L, id = "002_referential_integrity", apply = .wb_schema_migration_002),
    list(version = 3L, id = "003_lifecycle_backfill", apply = .wb_schema_migration_003)
  )
}

.wb_sqlite_configure_connection <- function(con, writable = TRUE, configure_journal = TRUE) {
  .wb_assert(DBI::dbIsValid(con), "SQLite connection is not valid.")
  attr(con, "scworkbench_read_only") <- !isTRUE(writable)
  if (!isTRUE(writable)) return(invisible(TRUE))
  transacting <- isTRUE(tryCatch(RSQLite::sqliteIsTransacting(con), error = function(e) FALSE))
  if (transacting) {
    enabled <- suppressWarnings(as.integer(DBI::dbGetQuery(con, "PRAGMA foreign_keys;")[[1L]][1L]))
    .wb_assert(identical(enabled, 1L),
               "Writable SQLite transaction has foreign-key enforcement disabled; mutation is forbidden.")
    return(invisible(TRUE))
  }
  DBI::dbExecute(con, "PRAGMA foreign_keys=ON;")
  enabled <- suppressWarnings(as.integer(DBI::dbGetQuery(con, "PRAGMA foreign_keys;")[[1L]][1L]))
  .wb_assert(identical(enabled, 1L),
             "Writable SQLite connection refused PRAGMA foreign_keys=ON; no mutation is permitted.")
  if (isTRUE(configure_journal)) DBI::dbExecute(con, "PRAGMA journal_mode=WAL;")
  DBI::dbExecute(con, "PRAGMA synchronous=NORMAL;")
  invisible(TRUE)
}

.wb_schema_ledger_exists <- function(con) {
  nrow(DBI::dbGetQuery(
    con,
    "SELECT 1 FROM sqlite_schema WHERE type='table' AND name='bundle_schema_migrations' LIMIT 1;"
  )) == 1L
}

.wb_schema_component_is_current <- function(con, tables, columns = list()) {
  if (!.wb_schema_ledger_exists(con) || !identical(.wb_schema_status(con)$status, "current")) return(FALSE)
  missing <- setdiff(as.character(tables), DBI::dbListTables(con))
  .wb_assert(!length(missing), paste0(
    "BUNDLE_SCHEMA_CORRUPT: current migration ledger is missing table(s): ",
    paste(missing, collapse = ", "), ". Restore a backup; lazy repair is forbidden."
  ))
  for (table in names(columns)) {
    absent <- setdiff(columns[[table]], DBI::dbListFields(con, table))
    .wb_assert(!length(absent), paste0(
      "BUNDLE_SCHEMA_CORRUPT: current migration ledger is missing ", table,
      " column(s): ", paste(absent, collapse = ", "), ". Restore a backup; lazy repair is forbidden."
    ))
  }
  TRUE
}

.wb_schema_status <- function(con) {
  current <- .wb_bundle_schema_version()
  if (!.wb_schema_ledger_exists(con)) {
    return(list(current = current, observed = 0L, status = "upgrade_required",
                message = paste0("Bundle schema ledger is absent; writable migration to version ", current, " is required.")))
  }
  rows <- DBI::dbGetQuery(
    con,
    "SELECT version, migration_id FROM bundle_schema_migrations ORDER BY version;"
  )
  observed <- if (nrow(rows)) max(as.integer(rows$version)) else 0L
  expected <- .wb_bundle_schema_migrations()
  expected_ids <- vapply(expected, `[[`, character(1), "id")
  expected_versions <- vapply(expected, `[[`, integer(1), "version")
  valid_prefix <- nrow(rows) <= length(expected) && identical(
    as.integer(rows$version), head(expected_versions, nrow(rows))
  ) && identical(as.character(rows$migration_id), head(expected_ids, nrow(rows)))
  if (observed > current) {
    return(list(current = current, observed = observed, status = "newer_schema",
                message = paste0("Bundle schema version ", observed, " is newer than this scworkbench supports (", current, ").")))
  }
  if (!isTRUE(valid_prefix)) {
    return(list(current = current, observed = observed, status = "invalid_ledger",
                message = "Bundle schema migration ledger is not a valid ordered migration prefix."))
  }
  if (observed < current) {
    return(list(current = current, observed = observed, status = "upgrade_required",
                message = paste0("Bundle schema version ", observed, " requires writable migration to version ", current, ".")))
  }
  definitions <- .wb_schema_foreign_key_definitions()
  missing_constraints <- names(definitions)[vapply(names(definitions), function(table) {
    if (!.wb_table_exists(con, table)) return(TRUE)
    actual <- DBI::dbGetQuery(con, paste0("PRAGMA foreign_key_list(", DBI::dbQuoteIdentifier(con, table), ");"))
    length(unique(actual$id)) < length(definitions[[table]])
  }, logical(1))]
  if (length(missing_constraints)) {
    return(list(
      current = current, observed = observed, status = "invalid_schema",
      message = paste0(
        "Bundle migration ledger is current but required foreign-key declarations are missing from: ",
        paste(missing_constraints, collapse = ", "), ". Restore a verified schema backup."
      )
    ))
  }
  list(current = current, observed = observed, status = "current",
       message = paste0("Bundle schema is current at version ", current, "."))
}

.wb_schema_create_ledger <- function(con) {
  DBI::dbExecute(con, paste(
    "CREATE TABLE IF NOT EXISTS bundle_schema_migrations (",
    "version INTEGER PRIMARY KEY,",
    "migration_id TEXT NOT NULL UNIQUE,",
    "applied_at TEXT NOT NULL,",
    "scworkbench_version TEXT NOT NULL",
    ");"
  ))
  invisible(TRUE)
}

.wb_schema_migration_hook <- function(event, version = NA_integer_, migration_id = NA_character_, con = NULL) {
  hook <- getOption("scworkbench.schema_migration_test_hook")
  if (is.function(hook)) hook(event = event, version = version, migration_id = migration_id, con = con)
  invisible(TRUE)
}

.wb_schema_migration_001 <- function(con, bundle_dir = NULL) {
  .wb_ensure_schema_app_bundle(con)
  .wb_create_artifacts_schema(con)
  .wb_migrate_provenance_tables_locked(con)
  .wb_ensure_feature_set_tables(con)
  .wb_ensure_cell_vectors_tables(con)
  .wb_ensure_cell_set_recipes_table(con)
  .wb_ensure_motif_registry_tables(con)
  .wb_ensure_space_models_table(con)
  .wb_ensure_registry_mutation_events_table(con)
  .wb_ensure_prov_registry_mutations_table(con)
  invisible(TRUE)
}

.wb_schema_rebuild_with_foreign_keys <- function(con, table, constraints) {
  .wb_assert(.wb_table_exists(con, table), paste0("Schema migration expected table: ", table))
  existing <- DBI::dbGetQuery(con, paste0("PRAGMA foreign_key_list(", DBI::dbQuoteIdentifier(con, table), ");"))
  if (nrow(existing) >= length(constraints)) return(invisible(FALSE))

  schema <- DBI::dbGetQuery(
    con, "SELECT sql FROM sqlite_schema WHERE type='table' AND name=?;", params = list(table)
  )$sql[[1L]]
  .wb_assert(is.character(schema) && length(schema) == 1L && nzchar(schema),
             paste0("Cannot recover canonical CREATE statement for ", table, "."))
  indexes <- DBI::dbGetQuery(
    con,
    "SELECT sql FROM sqlite_schema WHERE type='index' AND tbl_name=? AND sql IS NOT NULL ORDER BY name;",
    params = list(table)
  )$sql
  temporary <- paste0("__wb_schema_new_", table)
  DBI::dbExecute(con, paste0("DROP TABLE IF EXISTS ", DBI::dbQuoteIdentifier(con, temporary), ";"))
  create <- sub(
    "^CREATE[[:space:]]+TABLE[[:space:]]+[^[:space:]\\(]+",
    paste("CREATE TABLE", temporary), schema, ignore.case = TRUE, perl = TRUE
  )
  create <- sub("[)][[:space:]]*$", paste0(",\n  ", paste(constraints, collapse = ",\n  "), "\n)"), create, perl = TRUE)
  .wb_assert(!identical(create, schema), paste0("Could not prepare constrained schema for ", table, "."))
  DBI::dbExecute(con, create)
  tryCatch(
    DBI::dbExecute(
      con,
      paste0("INSERT INTO ", DBI::dbQuoteIdentifier(con, temporary),
             " SELECT * FROM ", DBI::dbQuoteIdentifier(con, table), ";")
    ),
    error = function(e) stop(
      "Referential-integrity migration rejected existing rows in ", table,
      ": ", conditionMessage(e), call. = FALSE
    )
  )
  DBI::dbExecute(con, paste0("DROP TABLE ", DBI::dbQuoteIdentifier(con, table), ";"))
  DBI::dbExecute(
    con,
    paste0("ALTER TABLE ", DBI::dbQuoteIdentifier(con, temporary),
           " RENAME TO ", DBI::dbQuoteIdentifier(con, table), ";")
  )
  for (sql in indexes) DBI::dbExecute(con, sql)
  invisible(TRUE)
}

.wb_schema_fk <- function(columns, parent, parent_columns = columns) {
  paste0(
    "FOREIGN KEY (", paste(columns, collapse = ", "), ") REFERENCES ", parent,
    " (", paste(parent_columns, collapse = ", "), ") DEFERRABLE INITIALLY DEFERRED"
  )
}

.wb_schema_foreign_key_definitions <- function() {
  fk <- .wb_schema_fk
  list(
    space_coords = c(fk("space_id", "spaces"), fk("cell_id", "cells")),
    space_2d = c(fk("space_id", "spaces"), fk("cell_id", "cells")),
    features = c(fk("matrix_id", "matrices")),
    matrix_cells = c(fk("matrix_id", "matrices"), fk("cell_id", "cells")),
    cell_set_membership = c(fk("cell_id", "cells")),
    matrix_fragments = c(fk("matrix_id", "matrices")),
    matrix_fragment_cells = c(fk("fragment_id", "matrix_fragments"), fk("cell_id", "cells")),
    matrix_fragment_features = c(fk("fragment_id", "matrix_fragments")),
    cell_vector_values = c(fk("vector_id", "cell_vectors"), fk("cell_id", "cells")),
    feature_sets = c(fk("matrix_id", "matrices")),
    feature_set_membership = c(
      fk(c("feature_set", "matrix_id"), "feature_sets", c("feature_set", "matrix_id")),
      fk(c("matrix_id", "feature_id"), "features", c("matrix_id", "feature_id"))
    ),
    entity_supersessions = c(
      fk(c("successor_kind", "successor_id"), "entity_lifecycle", c("entity_kind", "entity_id")),
      fk(c("predecessor_kind", "predecessor_id"), "entity_lifecycle", c("entity_kind", "entity_id"))
    ),
    entity_tombstones = c(fk(c("entity_kind", "entity_id"), "entity_lifecycle", c("entity_kind", "entity_id"))),
    motifs = c(fk("motif_library", "motif_libraries")),
    motif_match_sets = c(fk("matrix_id", "matrices"), fk("motif_library", "motif_libraries")),
    motif_match_membership = c(fk("motif_match_set", "motif_match_sets"), fk("motif_key", "motifs")),
    space_models = c(fk("source_space_id", "spaces", "space_id")),
    artifacts = c(fk("provenance_snapshot_id", "prov_heads", "snapshot_id")),
    artifact_labels = c(fk("artifact_id", "artifacts"), fk("cell_id", "cells")),
    artifact_pseudotime = c(fk("artifact_id", "artifacts"), fk("cell_id", "cells")),
    artifact_relation_rows = c(fk("artifact_id", "artifacts"), fk("cell_id", "cells")),
    artifact_curves_2d = c(fk("artifact_id", "artifacts")),
    artifact_space_path_meta = c(fk("artifact_id", "artifacts")),
    artifact_space_path_rows = c(fk("artifact_id", "artifacts")),
    artifact_space_2d = c(fk("artifact_id", "artifacts"), fk("cell_id", "cells")),
    artifact_umap_model = c(fk("artifact_id", "artifacts")),
    artifact_model_ref = c(fk("artifact_id", "artifacts")),
    artifact_tables = c(fk("artifact_id", "artifacts")),
    artifact_table_rows = c(fk("artifact_id", "artifacts")),
    prov_heads = c(fk("commit_id", "prov_commits", "commit_id")),
    prov_runs = c(fk("snapshot_id", "prov_heads", "snapshot_id")),
    prov_run_edges = c(
      fk(c("snapshot_id", "parent_run_id"), "prov_runs", c("snapshot_id", "run_id")),
      fk(c("snapshot_id", "child_run_id"), "prov_runs", c("snapshot_id", "run_id"))
    ),
    prov_run_outputs = c(
      fk(c("snapshot_id", "run_id"), "prov_runs", c("snapshot_id", "run_id")),
      fk("artifact_id", "artifacts", "artifact_id")
    ),
    prov_run_entity_bindings = c(
      fk(c("snapshot_id", "run_id"), "prov_runs", c("snapshot_id", "run_id")),
      fk("commit_id", "prov_commits", "commit_id")
    ),
    prov_source_identities = c(
      fk(c("snapshot_id", "run_id"), "prov_runs", c("snapshot_id", "run_id")),
      fk("matrix_id", "matrices", "matrix_id")
    ),
    prov_source_inputs = c(fk(c("snapshot_id", "run_id"), "prov_runs", c("snapshot_id", "run_id"))),
    prov_replay_equivalence_results = c(
      fk("replay_snapshot_id", "prov_heads", "snapshot_id"),
      fk("replay_artifact_id", "artifacts", "artifact_id")
    ),
    prov_materializations = c(fk("commit_id", "prov_commits", "commit_id")),
    prov_registry_mutations = c(fk("commit_id", "prov_commits", "commit_id"))
  )
}

.wb_schema_migration_002 <- function(con, bundle_dir = NULL) {
  definitions <- .wb_schema_foreign_key_definitions()
  DBI::dbExecute(con, "PRAGMA defer_foreign_keys=ON;")
  # Rebuild referenced provenance parents before artifacts begin referring to
  # them. SQLite tracks a dropped referenced parent as a deferred violation
  # even when an equivalent table is recreated under the same name.
  table_order <- c("prov_heads", "prov_runs", setdiff(names(definitions), c("prov_heads", "prov_runs")))
  for (table in table_order) {
    tryCatch(
      .wb_schema_rebuild_with_foreign_keys(con, table, definitions[[table]]),
      error = function(e) stop("Foreign-key migration failed while rebuilding ", table, ": ", conditionMessage(e), call. = FALSE)
    )
  }
  violations <- DBI::dbGetQuery(con, "PRAGMA foreign_key_check;")
  if (nrow(violations)) {
    first <- violations[1L, , drop = FALSE]
    stop(
      "Schema migration found dangling durable references in table ", first$table[[1L]],
      " at rowid ", first$rowid[[1L]], ". Repair the source bundle or restore from the migration backup.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

.wb_schema_migration_003 <- function(con, bundle_dir = NULL) {
  bundle <- structure(
    list(dir = bundle_dir %||% .wb_bundle_dir_from_connection(con), con = con, read_only = FALSE),
    class = "scworkbench_bundle"
  )
  .wb_entity_lifecycle_migrate_locked(bundle)
  invisible(TRUE)
}

.wb_schema_backup_database <- function(con, bundle_dir, from_version, to_version) {
  root <- file.path(
    dirname(bundle_dir), paste0(".", basename(bundle_dir), ".schema-backups")
  )
  dir.create(root, recursive = TRUE, showWarnings = FALSE)
  token <- paste0(format(Sys.time(), "%Y%m%dT%H%M%OS6"), "-", Sys.getpid(), "-", sample.int(1e9, 1L))
  path <- file.path(root, paste0("app.sqlite.v", from_version, "-to-v", to_version, ".", token, ".bak"))
  destination <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(try(DBI::dbDisconnect(destination), silent = TRUE), add = TRUE)
  .wb_sqlite_configure_connection(destination, writable = TRUE)
  RSQLite::sqliteCopyDatabase(con, destination)
  check <- DBI::dbGetQuery(destination, "PRAGMA quick_check;")[[1L]]
  .wb_assert(identical(tolower(as.character(check)), "ok"), "Migration backup failed SQLite quick_check.")
  normalizePath(path, winslash = "/", mustWork = TRUE)
}

.wb_schema_migrate_connection <- function(con, bundle_dir = NULL, backup = TRUE) {
  .wb_sqlite_configure_connection(con, writable = TRUE)
  initial <- .wb_schema_status(con)
  if (initial$status %in% c("newer_schema", "invalid_ledger", "invalid_schema")) stop(initial$message, call. = FALSE)
  if (identical(initial$status, "current")) return(invisible(list(changed = FALSE, backup = NULL, status = initial)))
  backup_path <- if (isTRUE(backup) && !is.null(bundle_dir)) {
    .wb_schema_backup_database(con, bundle_dir, initial$observed, .wb_bundle_schema_version())
  } else NULL

  migrations <- .wb_bundle_schema_migrations()
  pending <- migrations[vapply(migrations, function(x) x$version > initial$observed, logical(1))]
  DBI::dbBegin(con)
  committed <- FALSE
  on.exit(if (!committed && DBI::dbIsValid(con) && RSQLite::sqliteIsTransacting(con)) try(DBI::dbRollback(con), silent = TRUE), add = TRUE)
  tryCatch({
    .wb_schema_create_ledger(con)
    for (migration in pending) {
      .wb_schema_migration_hook("before", migration$version, migration$id, con)
      migration$apply(con, bundle_dir = bundle_dir)
      .wb_schema_migration_hook("after_apply", migration$version, migration$id, con)
      DBI::dbExecute(
        con,
        "INSERT INTO bundle_schema_migrations(version,migration_id,applied_at,scworkbench_version) VALUES(?,?,?,?);",
        params = list(
          migration$version, migration$id, format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6%z"),
          tryCatch(as.character(utils::packageVersion("scworkbench")), error = function(e) "development")
        )
      )
      .wb_schema_migration_hook("after_ledger", migration$version, migration$id, con)
    }
    final <- .wb_schema_status(con)
    .wb_assert(identical(final$status, "current"), final$message)
    violations <- DBI::dbGetQuery(con, "PRAGMA foreign_key_check;")
    .wb_assert(!nrow(violations), "Schema migration cannot commit with foreign-key violations.")
    DBI::dbCommit(con)
    committed <- TRUE
  }, error = function(e) {
    if (RSQLite::sqliteIsTransacting(con)) DBI::dbRollback(con)
    stop(
      "Bundle schema migration rolled back completely", if (!is.null(backup_path)) paste0("; recovery backup: ", backup_path) else "",
      ". Cause: ", conditionMessage(e), call. = FALSE
    )
  })
  invisible(list(changed = TRUE, backup = backup_path, status = .wb_schema_status(con)))
}

#' Inspect Bundle Schema Migration Status
#'
#' Inspect the migration ledger without changing the bundle.
#'
#' @param bundle_or_dir Open bundle or bundle directory.
#' @return A named schema-status record.
#' @export
wb_bundle_schema_status <- function(bundle_or_dir) {
  if (inherits(bundle_or_dir, "scworkbench_bundle")) return(.wb_schema_status(bundle_or_dir$con))
  path <- normalizePath(bundle_or_dir, winslash = "/", mustWork = TRUE)
  lock <- wb_bundle_writer_lock_info(path)
  .wb_assert(!isTRUE(lock$locked), paste0(
    "Bundle schema status requires stable recipient state; ", .wb_writer_lock_diagnostic(lock)
  ))
  manifest <- jsonlite::read_json(file.path(path, "manifest.json"), simplifyVector = TRUE)
  db <- file.path(path, as.character(manifest$storage$sqlite$path)[1L])
  .wb_assert(!file.exists(paste0(db, "-wal")) && !file.exists(paste0(db, "-shm")),
             "Bundle schema status requires finalized SQLite state without WAL sidecars.")
  con <- DBI::dbConnect(RSQLite::SQLite(), paste0("file:", normalizePath(db, winslash = "/", mustWork = TRUE), "?immutable=1"), flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  .wb_sqlite_configure_connection(con, writable = FALSE)
  .wb_schema_status(con)
}

#' Migrate A Bundle To The Current Durable Schema
#'
#' Apply every pending ordered migration under the exclusive bundle-writer
#' lock and one SQLite transaction. Before upgrading an existing database, an
#' online SQLite backup is retained in a sibling hidden backup directory. A
#' failed migration rolls back the database completely; the backup can be
#' copied back while the bundle is closed if external recovery is required.
#'
#' @param bundle Open writable bundle.
#' @return Invisibly returns migration status and backup path.
#' @export
wb_migrate_bundle <- function(bundle) {
  .wb_assert_bundle_writable(bundle, "bundle schema migration")
  .wb_with_bundle_writer_lock(bundle, operation = "bundle schema migration", code = {
    .wb_schema_migrate_connection(bundle$con, bundle_dir = bundle$dir, backup = TRUE)
  })
}
