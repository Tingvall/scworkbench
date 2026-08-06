.schema14a_copy <- function(source, target) {
  dir.create(target, recursive = TRUE, showWarnings = FALSE)
  entries <- list.files(source, recursive = TRUE, full.names = TRUE, all.files = TRUE, no.. = TRUE)
  for (path in entries[dir.exists(entries)]) {
    dir.create(file.path(target, substring(path, nchar(source) + 2L)), recursive = TRUE, showWarnings = FALSE)
  }
  for (path in entries[!dir.exists(entries)]) {
    destination <- file.path(target, substring(path, nchar(source) + 2L))
    dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
    stopifnot(file.copy(path, destination, overwrite = TRUE, copy.mode = TRUE, copy.date = TRUE))
  }
  invisible(target)
}

.schema14a_snapshot <- function(path) {
  con <- DBI::dbConnect(RSQLite::SQLite(), file.path(path, "db", "app.sqlite"))
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  list(
    schema = DBI::dbGetQuery(con, "SELECT type,name,tbl_name,sql FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name;"),
    ledger = DBI::dbGetQuery(con, "SELECT version,migration_id FROM bundle_schema_migrations ORDER BY version;"),
    rows = lapply(c("space_models", "artifact_umap_model", "artifact_space_path_rows"), function(table) {
      DBI::dbGetQuery(con, paste0("SELECT * FROM ", table, " ORDER BY rowid;"))
    })
  )
}

.schema14a_expect_fk_failure <- function(con, sql) {
  result <- try(DBI::dbExecute(con, sql), silent = TRUE)
  stopifnot(
    inherits(result, "try-error"),
    grepl("FOREIGN KEY constraint failed", as.character(result), fixed = TRUE)
  )
  invisible(TRUE)
}

.schema14a_make_version3 <- function(path) {
  b <- wb_init_bundle(path, overwrite = TRUE)
  cells <- c("c1", "c2")
  wb_define_cells(b, cells)
  wb_attach_space(b, "source", data.frame(cell_id = cells, x = c(0, 1), y = c(1, 0)))
  wb_attach_space(b, "modeled", data.frame(cell_id = cells, x = c(1, 2), y = c(2, 1)))
  DBI::dbExecute(b$con, "
    INSERT INTO artifacts(artifact_id,type,created_at,provenance_json)
    VALUES('historical_artifact','fixture','2026-08-04','{}');
  ")
  DBI::dbExecute(b$con, "
    INSERT INTO space_models(space_id,model_type,source_space_id,cell_set,uwot_args_json,model_path,created_at)
    VALUES('modeled','fixture','source','core','{}','models/historical.rds','2026-08-04');
  ")
  DBI::dbExecute(b$con, "
    INSERT INTO artifact_umap_model(artifact_id,space_id,model_path)
    VALUES('historical_artifact','modeled','models/historical.rds');
  ")
  DBI::dbExecute(b$con, "
    INSERT INTO artifact_space_path_rows(artifact_id,space_id,path_id,point,dim,value)
    VALUES('historical_artifact','modeled','path',1,1,0.5);
  ")

  # Reproduce the accepted Request-14 v3 declaration: target tables had only
  # their pre-closure relationships while the ordered ledger was current.
  DBI::dbExecute(b$con, "DELETE FROM bundle_schema_migrations WHERE version>=4;")
  old <- list(
    space_models = c(scworkbench:::.wb_schema_fk("source_space_id", "spaces", "space_id")),
    artifact_umap_model = c(scworkbench:::.wb_schema_fk("artifact_id", "artifacts")),
    artifact_space_path_rows = c(scworkbench:::.wb_schema_fk("artifact_id", "artifacts"))
  )
  DBI::dbWithTransaction(b$con, {
    DBI::dbExecute(b$con, "PRAGMA defer_foreign_keys=ON;")
    for (table in names(old)) {
      scworkbench:::.wb_schema_rebuild_with_foreign_keys(b$con, table, old[[table]], force = TRUE)
    }
  })
  stopifnot(identical(wb_bundle_schema_status(b)$status, "upgrade_required"))
  wb_close_bundle(b)
  invisible(path)
}

test_central_schema_foreign_key_closure_contract <- function() {
  root <- tempfile("scwb_schema14a_")
  dir.create(root, recursive = TRUE)
  old_hook <- getOption("scworkbench.schema_migration_test_hook")
  on.exit({
    options(scworkbench.schema_migration_test_hook = old_hook)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  current_path <- file.path(root, "current.bundle")
  current <- wb_init_bundle(current_path, overwrite = TRUE)
  cells <- c("cell_1", "cell_2")
  wb_define_cells(current, cells)
  wb_attach_space(current, "source", data.frame(cell_id = cells, x = c(0, 1), y = c(1, 0)))
  exact <- lapply(names(scworkbench:::.wb_schema_foreign_key_contract()), function(table) {
    scworkbench:::.wb_schema_table_foreign_key_status(current$con, table)
  })
  stopifnot(
    identical(wb_bundle_schema_status(current)$status, "current"),
    all(vapply(exact, function(x) isTRUE(x$ok), logical(1)))
  )

  DBI::dbExecute(current$con, "
    INSERT INTO artifacts(artifact_id,type,created_at,provenance_json)
    VALUES('orphan_probe','fixture','2026-08-04','{}');
  ")
  .schema14a_expect_fk_failure(current$con, "
    INSERT INTO space_models(space_id,model_type,source_space_id,cell_set,uwot_args_json,model_path,created_at)
    VALUES('orphan_output','fixture','source','core','{}','models/orphan.rds','2026-08-04');
  ")
  .schema14a_expect_fk_failure(current$con, "
    INSERT INTO artifact_umap_model(artifact_id,space_id,model_path)
    VALUES('orphan_probe','orphan_output','models/orphan.rds');
  ")
  .schema14a_expect_fk_failure(current$con, "
    INSERT INTO artifact_space_path_rows(artifact_id,space_id,path_id,point,dim,value)
    VALUES('orphan_probe','orphan_output','path',1,1,0.5);
  ")
  wb_close_bundle(current)

  # Equal FK count with wrong child/parent identity is corruption, not an
  # upgrade. The public migrator must refuse to repair a current ledger.
  wrong_path <- file.path(root, "wrong-equal-count.bundle")
  wrong <- wb_init_bundle(wrong_path, overwrite = TRUE)
  DBI::dbExecute(wrong$con, "PRAGMA foreign_keys=OFF;")
  DBI::dbExecute(wrong$con, "DROP TABLE artifact_umap_model;")
  DBI::dbExecute(wrong$con, "
    CREATE TABLE artifact_umap_model (
      artifact_id TEXT PRIMARY KEY,
      space_id TEXT NOT NULL,
      model_path TEXT NOT NULL,
      FOREIGN KEY (artifact_id) REFERENCES artifacts(artifact_id) DEFERRABLE INITIALLY DEFERRED,
      FOREIGN KEY (space_id) REFERENCES matrices(matrix_id) DEFERRABLE INITIALLY DEFERRED
    );
  ")
  wrong_status <- wb_bundle_schema_status(wrong)
  wrong_schema <- DBI::dbGetQuery(wrong$con, "SELECT sql FROM sqlite_schema WHERE name='artifact_umap_model';")$sql
  refused <- try(wb_migrate_bundle(wrong), silent = TRUE)
  stopifnot(
    identical(wrong_status$status, "invalid_schema"),
    grepl("unexpected=", wrong_status$message, fixed = TRUE),
    inherits(refused, "try-error"),
    identical(wrong_schema, DBI::dbGetQuery(wrong$con, "SELECT sql FROM sqlite_schema WHERE name='artifact_umap_model';")$sql)
  )
  wb_close_bundle(wrong)

  # A representative accepted v3 schema migrates all three target tables and
  # preserves their rows. An injected v4 failure restores schema, data, and
  # ledger exactly.
  v3_path <- .schema14a_make_version3(file.path(root, "historical-v3.bundle"))
  failed_path <- file.path(root, "historical-v3-failed.bundle")
  .schema14a_copy(v3_path, failed_path)
  before <- .schema14a_snapshot(failed_path)
  options(scworkbench.schema_migration_test_hook = function(event, version, ...) {
    if (identical(event, "after_apply") && identical(as.integer(version), 4L)) {
      stop("schema14a injected version-4 failure", call. = FALSE)
    }
  })
  failed <- try(wb_open_bundle(failed_path), silent = TRUE)
  options(scworkbench.schema_migration_test_hook = old_hook)
  stopifnot(
    inherits(failed, "try-error"),
    grepl("rolled back completely", as.character(failed), fixed = TRUE),
    identical(before, .schema14a_snapshot(failed_path))
  )

  migrated <- wb_open_bundle(v3_path)
  stopifnot(
    identical(wb_bundle_schema_status(migrated)$status, "current"),
    nrow(DBI::dbGetQuery(migrated$con, "PRAGMA foreign_key_check;")) == 0L,
    DBI::dbGetQuery(migrated$con, "SELECT COUNT(*) n FROM space_models;")$n[[1L]] == 1L,
    DBI::dbGetQuery(migrated$con, "SELECT COUNT(*) n FROM artifact_umap_model;")$n[[1L]] == 1L,
    DBI::dbGetQuery(migrated$con, "SELECT COUNT(*) n FROM artifact_space_path_rows;")$n[[1L]] == 1L
  )
  migrated_exact <- lapply(names(scworkbench:::.wb_schema_foreign_key_contract()), function(table) {
    scworkbench:::.wb_schema_table_foreign_key_status(migrated$con, table)
  })
  stopifnot(all(vapply(migrated_exact, function(x) isTRUE(x$ok), logical(1))))
  wb_close_bundle(migrated)

  relationships <- scworkbench:::.wb_schema_identifier_relationships()
  stopifnot(
    identical(sort(unique(relationships$classification)),
              sort(c("sqlite_foreign_key", "application_validated", "symbolic_or_external"))),
    any(relationships$table == "matrix_fragment_features" & relationships$columns == "feature_id" & relationships$classification == "application_validated"),
    any(relationships$table == "motif_match_membership" & relationships$columns == "feature_id" & relationships$classification == "application_validated"),
    any(relationships$table == "artifact_model_ref" & relationships$columns == "model_space_id" & relationships$classification == "symbolic_or_external")
  )
  TRUE
}

test_normalized_membership_deep_validation_contract <- function() {
  root <- tempfile("scwb_schema14a_membership_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  cells <- c("c1", "c2")
  wb_define_cells(b, cells)
  matrix <- Matrix::Matrix(
    matrix(1:4, nrow = 2L, dimnames = list(c("gene_a", "gene_b"), cells)),
    sparse = TRUE
  )
  wb_attach_matrix(b, "RNA", matrix)
  fragment <- DBI::dbGetQuery(b$con, "SELECT fragment_id FROM matrix_fragments WHERE matrix_id='RNA' LIMIT 1;")$fragment_id[[1L]]
  DBI::dbExecute(
    b$con, "INSERT INTO matrix_fragment_features(fragment_id,feature_id) VALUES(?,?);",
    params = list(fragment, "orphan_fragment_feature")
  )
  DBI::dbExecute(b$con, "INSERT INTO motif_libraries(motif_library,source_type,created_at) VALUES('lib','fixture','2026-08-04');")
  DBI::dbExecute(b$con, "INSERT INTO motifs(motif_key,motif_library,created_at) VALUES('motif','lib','2026-08-04');")
  DBI::dbExecute(b$con, "INSERT INTO motif_match_sets(motif_match_set,matrix_id,motif_library,match_engine,created_at) VALUES('matches','RNA','lib','fixture','2026-08-04');")
  DBI::dbExecute(b$con, "INSERT INTO motif_match_membership(motif_match_set,motif_key,feature_id) VALUES('matches','motif','orphan_motif_feature');")
  scworkbench:::.wb_with_mutation_context(b, route = "ingestion", code = wb_refresh_manifest(b))
  wb_finalize_recipient_bundle(b)
  wb_close_bundle(b)
  report <- wb_bundle_validation_report(root, "content")
  stopifnot(
    "MATRIX_FRAGMENT_FEATURE_REGISTRY_MISMATCH" %in% report$diagnostics$code,
    "MOTIF_MATCH_DANGLING_MATRIX_FEATURE" %in% report$diagnostics$code
  )
  TRUE
}
