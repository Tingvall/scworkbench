.schema14_copy_bundle <- function(source, target) {
  dir.create(target, recursive = TRUE, showWarnings = FALSE)
  entries <- list.files(source, recursive = TRUE, full.names = TRUE, all.files = TRUE, no.. = TRUE)
  dirs <- entries[dir.exists(entries)]
  if (length(dirs)) for (path in dirs) {
    dir.create(file.path(target, substring(path, nchar(source) + 2L)), recursive = TRUE, showWarnings = FALSE)
  }
  files <- entries[!dir.exists(entries)]
  if (length(files)) for (path in files) {
    destination <- file.path(target, substring(path, nchar(source) + 2L))
    dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
    stopifnot(file.copy(path, destination, overwrite = TRUE, copy.mode = TRUE, copy.date = TRUE))
  }
  invisible(target)
}

.schema14_sql_snapshot <- function(path) {
  con <- DBI::dbConnect(RSQLite::SQLite(), file.path(path, "db", "app.sqlite"))
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  list(
    schema = DBI::dbGetQuery(
      con,
      "SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name;"
    ),
    ledger = if (DBI::dbExistsTable(con, "bundle_schema_migrations")) {
      DBI::dbGetQuery(con, "SELECT version,migration_id FROM bundle_schema_migrations ORDER BY version;")
    } else data.frame(version = integer(), migration_id = character())
  )
}

.schema14_expect_fk_failure <- function(con, sql, params = NULL) {
  result <- try(
    if (is.null(params)) DBI::dbExecute(con, sql) else DBI::dbExecute(con, sql, params = params),
    silent = TRUE
  )
  stopifnot(inherits(result, "try-error"), grepl("FOREIGN KEY constraint failed", as.character(result), fixed = TRUE))
  invisible(TRUE)
}

test_central_schema_migration_foreign_keys_contract <- function() {
  root <- tempfile("scwb_schema14_")
  dir.create(root, recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)

  fresh_path <- file.path(root, "fresh.bundle")
  fresh <- wb_init_bundle(fresh_path, overwrite = TRUE)
  stopifnot(
    identical(wb_bundle_schema_status(fresh)$status, "current"),
    identical(as.integer(DBI::dbGetQuery(fresh$con, "PRAGMA foreign_keys;")[[1L]][1L]), 1L),
    nrow(DBI::dbGetQuery(fresh$con, "PRAGMA foreign_key_check;")) == 0L
  )
  cells <- paste0("cell_", 1:4)
  wb_define_cells(
    fresh, cells,
    metadata = data.frame(cell_id = cells, cluster = c("a", "a", "b", "b"), stringsAsFactors = FALSE),
    dataset_id = "fixture"
  )
  matrix <- Matrix::Matrix(
    matrix(seq_len(12L), nrow = 3L, dimnames = list(paste0("gene_", 1:3), cells)),
    sparse = TRUE
  )
  wb_attach_matrix(fresh, "RNA", matrix)
  wb_attach_space(fresh, "pca", data.frame(cell_id = cells, x = 1:4, y = 4:1))

  session <- wb_session_new()
  result <- wb_session_run_op(session, fresh, "metadata_cell_vector", inputs = list(
    source_column = "cluster", vector_name = "cluster", value_type = "categorical",
    missing_policy = "error", cell_set = "all", min_cells = 1L
  ))
  stopifnot(
    identical(as.integer(DBI::dbGetQuery(result$session$staging_bundle$con, "PRAGMA foreign_keys;")[[1L]][1L]), 1L)
  )
  wb_session_promote_current(
    fresh, result$session, outputs = list(wb_ref_run(result$run$run_id, "vector")),
    created_by = "schema14-contract"
  )
  stopifnot(nrow(wb_art_list(fresh)) == 1L, nrow(DBI::dbGetQuery(fresh$con, "PRAGMA foreign_key_check;")) == 0L)

  .schema14_expect_fk_failure(
    fresh$con,
    "INSERT INTO artifact_labels(artifact_id,cell_id,label) VALUES('missing_artifact','cell_1','x');"
  )
  .schema14_expect_fk_failure(
    fresh$con,
    "INSERT INTO matrix_fragments(fragment_id,matrix_id,storage,path,n_features,n_cells,feature_ids_json,cell_ids_json,created_at) VALUES('bad_fragment','missing_matrix','bpcells','mat/missing',1,1,'[\"g\"]','[\"c\"]','2026-08-04');"
  )
  .schema14_expect_fk_failure(
    fresh$con,
    "INSERT INTO cell_set_membership(cell_set,cell_id,created_at) VALUES('set:bad','missing_cell','2026-08-04');"
  )
  .schema14_expect_fk_failure(
    fresh$con,
    "INSERT INTO space_models(space_id,model_type,source_space_id,cell_set,uwot_args_json,model_path,created_at) VALUES('bad_model','fixture','missing_space','core','{}','models/bad','2026-08-04');"
  )
  .schema14_expect_fk_failure(
    fresh$con,
    "INSERT INTO prov_registry_mutations(commit_id,event_id,run_id,registry_type,action,registry_key_json) VALUES('missing_commit','bad_event','bad_run','cell_set','replace','{}');"
  )

  wb_finalize_recipient_bundle(fresh)
  wb_close_bundle(fresh)
  recipient <- wb_open_bundle(fresh_path, read_only = TRUE, validate = TRUE)
  stopifnot(identical(wb_bundle_schema_status(recipient)$status, "current"))
  wb_close_bundle(recipient)

  # A pre-ledger bundle must be diagnosed without any read-only mutation.
  readonly_old <- file.path(root, "readonly-old.bundle")
  .schema14_copy_bundle(fresh_path, readonly_old)
  old_con <- DBI::dbConnect(RSQLite::SQLite(), file.path(readonly_old, "db", "app.sqlite"))
  DBI::dbExecute(old_con, "PRAGMA journal_mode=DELETE;")
  source("tests/fixtures/historical_schema_payload_order_support.R", local = TRUE)
  fixture_restore_pre_graph_payload_layout(old_con)
  DBI::dbExecute(old_con, "DROP TABLE bundle_schema_migrations;")
  DBI::dbDisconnect(old_con)
  before_hash <- digest::digest(file.path(readonly_old, "db", "app.sqlite"), file = TRUE, algo = "sha256")
  rejected <- try(wb_open_bundle(readonly_old, read_only = TRUE), silent = TRUE)
  after_hash <- digest::digest(file.path(readonly_old, "db", "app.sqlite"), file = TRUE, algo = "sha256")
  stopifnot(
    inherits(rejected, "try-error"),
    grepl("BUNDLE_SCHEMA_UPGRADE_REQUIRED", as.character(rejected), fixed = TRUE),
    identical(before_hash, after_hash),
    "BUNDLE_SCHEMA_UPGRADE_REQUIRED" %in% wb_bundle_validation_report(readonly_old, "structural")$diagnostics$code
  )

  # Failure after structural application rolls the whole database back, while
  # retaining a verified sibling backup for external recovery.
  failure_path <- file.path(root, "failure.bundle")
  .schema14_copy_bundle(readonly_old, failure_path)
  before_failure <- .schema14_sql_snapshot(failure_path)
  old_hook <- getOption("scworkbench.schema_migration_test_hook")
  options(scworkbench.schema_migration_test_hook = function(event, version, ...) {
    if (identical(event, "after_apply") && identical(as.integer(version), 2L)) stop("schema14 injected failure")
  })
  failed <- try(wb_open_bundle(failure_path), silent = TRUE)
  options(scworkbench.schema_migration_test_hook = old_hook)
  after_failure <- .schema14_sql_snapshot(failure_path)
  backups <- list.files(
    file.path(dirname(failure_path), paste0(".", basename(failure_path), ".schema-backups")),
    pattern = "[.]bak$", full.names = TRUE
  )
  stopifnot(
    inherits(failed, "try-error"), grepl("rolled back completely", as.character(failed), fixed = TRUE),
    identical(before_failure, after_failure), length(backups) == 1L
  )
  backup_con <- DBI::dbConnect(RSQLite::SQLite(), backups[[1L]])
  stopifnot(identical(tolower(DBI::dbGetQuery(backup_con, "PRAGMA quick_check;")[[1L]][1L]), "ok"))
  DBI::dbDisconnect(backup_con)

  # Two historical states converge on the same current schema: an unledgered
  # pre-migration bundle and an explicit version-1 component schema.
  migrated_v0 <- wb_open_bundle(readonly_old)
  first_schema <- .schema14_sql_snapshot(readonly_old)$schema
  repeated <- wb_migrate_bundle(migrated_v0)
  stopifnot(!isTRUE(repeated$changed), identical(first_schema, .schema14_sql_snapshot(readonly_old)$schema))
  wb_finalize_recipient_bundle(migrated_v0)
  wb_close_bundle(migrated_v0)
  strict_v0 <- wb_open_bundle(readonly_old, read_only = TRUE, validate = TRUE)
  wb_close_bundle(strict_v0)

  version1_path <- file.path(root, "version1.bundle")
  dir.create(file.path(version1_path, "db"), recursive = TRUE)
  stopifnot(file.copy(file.path(fresh_path, "manifest.json"), file.path(version1_path, "manifest.json")))
  v1 <- DBI::dbConnect(RSQLite::SQLite(), file.path(version1_path, "db", "app.sqlite"))
  scworkbench:::.wb_sqlite_configure_connection(v1, writable = TRUE)
  DBI::dbWithTransaction(v1, {
    scworkbench:::.wb_schema_create_ledger(v1)
    scworkbench:::.wb_schema_migration_001(v1, version1_path)
    DBI::dbExecute(v1, "INSERT INTO bundle_schema_migrations VALUES(1,'001_consolidate_durable_schema','2026-08-04','fixture');")
  })
  DBI::dbDisconnect(v1)
  migrated_v1 <- wb_open_bundle(version1_path)
  v0_con <- DBI::dbConnect(RSQLite::SQLite(), file.path(readonly_old, "db", "app.sqlite"))
  v0_tables <- sort(DBI::dbListTables(v0_con))
  DBI::dbDisconnect(v0_con)
  stopifnot(
    identical(wb_bundle_schema_status(migrated_v1)$status, "current"),
    nrow(DBI::dbGetQuery(migrated_v1$con, "PRAGMA foreign_key_check;")) == 0L,
    identical(sort(DBI::dbListTables(migrated_v1$con)), v0_tables)
  )
  wb_close_bundle(migrated_v1)
  TRUE
}
