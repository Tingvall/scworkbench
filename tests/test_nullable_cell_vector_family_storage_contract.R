.nullable_family_copy <- function(source, target) {
  fs::dir_copy(source, target)
  invisible(target)
}

.nullable_family_run <- function(bundle, family) {
  run <- wb_new_run("slingshot_adopt",
    inputs = list(parents = character(), cell_set = "all"),
    outputs = list(pseudotime = family))
  session <- wb_session_add_run(wb_session_new(), run)
  wb_session_promote_current(bundle, session, outputs = "pseudotime",
    created_by = "nullable-family-contract")$promoted$artifact_id[[1L]]
}

.nullable_family_v9 <- function(path) {
  con <- DBI::dbConnect(RSQLite::SQLite(), file.path(path, "db", "app.sqlite"))
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  scworkbench:::.wb_sqlite_configure_connection(con, writable = TRUE)
  DBI::dbWithTransaction(con, {
    DBI::dbExecute(con, "PRAGMA defer_foreign_keys=ON;")
    DBI::dbExecute(con, "CREATE TABLE artifact_pseudotime_v9 (
      artifact_id TEXT NOT NULL, cell_id TEXT NOT NULL,
      lineage_id TEXT NOT NULL, pseudotime REAL NOT NULL,
      PRIMARY KEY (artifact_id, cell_id, lineage_id),
      FOREIGN KEY (artifact_id) REFERENCES artifacts (artifact_id) DEFERRABLE INITIALLY DEFERRED,
      FOREIGN KEY (cell_id) REFERENCES cells (cell_id) DEFERRABLE INITIALLY DEFERRED);")
    DBI::dbExecute(con, "INSERT INTO artifact_pseudotime_v9
      SELECT artifact_id,cell_id,lineage_id,pseudotime FROM artifact_pseudotime;")
    DBI::dbExecute(con, "DROP TABLE artifact_pseudotime;")
    DBI::dbExecute(con, "ALTER TABLE artifact_pseudotime_v9 RENAME TO artifact_pseudotime;")
    DBI::dbExecute(con, "CREATE INDEX idx_pt_artifact ON artifact_pseudotime(artifact_id);")
    DBI::dbExecute(con, "DELETE FROM bundle_schema_migrations WHERE version=10;")
  })
  DBI::dbExecute(con, "PRAGMA wal_checkpoint(TRUNCATE);")
  invisible(path)
}

.nullable_family_snapshot <- function(path) {
  con <- DBI::dbConnect(RSQLite::SQLite(), file.path(path, "db", "app.sqlite"))
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  list(
    schema = DBI::dbGetQuery(con, "SELECT type,name,tbl_name,sql FROM sqlite_schema
      WHERE name NOT LIKE 'sqlite_%' ORDER BY type,name;"),
    ledger = DBI::dbGetQuery(con, "SELECT version,migration_id FROM bundle_schema_migrations ORDER BY version;"),
    values = DBI::dbGetQuery(con, "SELECT * FROM artifact_pseudotime
      ORDER BY artifact_id,cell_id,lineage_id;")
  )
}

test_nullable_cell_vector_family_storage_contract <- function() {
  root <- tempfile("scwb-nullable-family-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  path <- file.path(root, "fresh.bundle")
  bundle <- wb_init_bundle(path)
  cells <- c("c3", "c1", "c4", "c2")
  wb_define_cells(bundle, cells)
  family <- wb_prim_cell_vector_family(
    key = c("K2", "K1", "K2", "K1"),
    cell_id = c("c4", "c3", "c2", "c1"),
    value = c(NA_real_, 1.5, 2.5, NA_real_),
    value_type = "continuous", meta = list(label = "finite or missing"))
  before_identity <- scworkbench:::.wb_prov_payload_identity(bundle, family)$content_sha256
  artifact_id <- .nullable_family_run(bundle, family)
  loaded <- wb_art_load(bundle, artifact_id)
  stopifnot(identical(unclass(loaded), unclass(family)),
    identical(which(is.na(loaded$value)), c(1L, 4L)),
    identical(scworkbench:::.wb_prov_payload_identity(bundle, loaded)$content_sha256,
      before_identity),
    identical(DBI::dbGetQuery(bundle$con,
      "PRAGMA table_info(artifact_pseudotime);")$notnull[[4L]], 0L))
  stopifnot(isTRUE(wb_finalize_recipient_bundle(bundle)$ready))
  wb_close_bundle(bundle)
  relocated <- file.path(root, "relocated.bundle")
  .nullable_family_copy(path, relocated)
  readonly <- wb_open_bundle(relocated, read_only = TRUE)
  stopifnot(identical(unclass(wb_art_load(readonly, artifact_id)),
    unclass(family)), isTRUE(wb_bundle_validation_report(relocated,
    level = "recipient")$ok), nrow(wb_art_list(readonly)) == 1L)
  wb_close_bundle(readonly)

  # A copied v9 recipient holds the exact finite historical rows and IDs.
  finite_path <- file.path(root, "finite.bundle")
  finite <- wb_init_bundle(finite_path)
  wb_define_cells(finite, cells)
  finite_family <- family
  finite_family$value[c(1L, 4L)] <- c(0.25, 0.75)
  finite_id <- .nullable_family_run(finite, finite_family)
  finite_identity <- scworkbench:::.wb_prov_payload_identity(finite,
    finite_family)$content_sha256
  stopifnot(isTRUE(wb_finalize_recipient_bundle(finite)$ready))
  wb_close_bundle(finite)
  old_path <- file.path(root, "copied-v9.bundle")
  .nullable_family_copy(finite_path, old_path)
  .nullable_family_v9(old_path)
  old_before <- .nullable_family_snapshot(old_path)
  old_hash <- digest::digest(file.path(old_path, "db", "app.sqlite"),
    file = TRUE, algo = "sha256")
  refused <- try(wb_open_bundle(old_path, read_only = TRUE), silent = TRUE)
  stopifnot(inherits(refused, "try-error"),
    grepl("BUNDLE_SCHEMA_UPGRADE_REQUIRED", as.character(refused), fixed = TRUE),
    identical(old_hash, digest::digest(file.path(old_path, "db", "app.sqlite"),
      file = TRUE, algo = "sha256")))

  fault_path <- file.path(root, "migration-fault.bundle")
  .nullable_family_copy(old_path, fault_path)
  old_option <- getOption("scworkbench.schema_migration_test_hook")
  options(scworkbench.schema_migration_test_hook = function(event, version, ...) {
    if (identical(event, "after_apply") && identical(as.integer(version), 10L))
      stop("injected nullable-family migration fault")
  })
  failed <- try(wb_open_bundle(fault_path), silent = TRUE)
  options(scworkbench.schema_migration_test_hook = old_option)
  stopifnot(inherits(failed, "try-error"),
    grepl("rolled back completely", as.character(failed), fixed = TRUE),
    identical(.nullable_family_snapshot(fault_path), old_before))
  backups <- list.files(file.path(root,
    ".migration-fault.bundle.schema-backups"), pattern = "[.]bak$",
    full.names = TRUE)
  stopifnot(length(backups) == 1L)

  upgraded <- wb_open_bundle(old_path)
  upgraded_rows <- .nullable_family_snapshot(old_path)$values
  stopifnot(identical(upgraded_rows, old_before$values),
    identical(as.character(wb_art_list(upgraded)$artifact_id), finite_id),
    identical(unclass(wb_art_load(upgraded, finite_id)),
      unclass(finite_family)),
    identical(scworkbench:::.wb_prov_payload_identity(upgraded,
      wb_art_load(upgraded, finite_id))$content_sha256, finite_identity),
    nrow(DBI::dbGetQuery(upgraded$con, "PRAGMA foreign_key_check;")) == 0L)
  stopifnot(isTRUE(wb_finalize_recipient_bundle(upgraded)$ready))
  wb_close_bundle(upgraded)
  strict <- wb_open_bundle(old_path, read_only = TRUE, validate = TRUE)
  wb_close_bundle(strict)

  # Every rejected family leaves an otherwise valid source-only bundle.
  negatives <- list(
    duplicate = wb_prim_cell_vector_family(c("K", "K"), c("c1", "c1"), c(1, 2)),
    foreign_cell = wb_prim_cell_vector_family("K", "foreign", 1),
    nan = wb_prim_cell_vector_family("K", "c1", NaN),
    infinite = wb_prim_cell_vector_family("K", "c1", Inf)
  )
  for (case in names(negatives)) {
    b <- wb_init_bundle(file.path(root, paste0(case, ".bundle")))
    wb_define_cells(b, cells)
    baseline <- c(artifacts = nrow(wb_art_list(b)),
      runs = nrow(DBI::dbGetQuery(b$con, "SELECT * FROM prov_runs;")),
      commits = nrow(DBI::dbGetQuery(b$con, "SELECT * FROM prov_commits;")))
    failed <- try(.nullable_family_run(b, negatives[[case]]), silent = TRUE)
    observed <- c(artifacts = nrow(wb_art_list(b)),
      runs = nrow(DBI::dbGetQuery(b$con, "SELECT * FROM prov_runs;")),
      commits = nrow(DBI::dbGetQuery(b$con, "SELECT * FROM prov_commits;")))
    stopifnot(inherits(failed, "try-error"), identical(observed, baseline))
    wb_close_bundle(b)
  }
  fault <- wb_init_bundle(file.path(root, "publication-fault.bundle"))
  wb_define_cells(fault, cells)
  fault_run <- wb_new_run("slingshot_adopt",
    inputs = list(parents = character(), cell_set = "all"),
    outputs = list(pseudotime = family, lineage_weights = family))
  fault_session <- wb_session_add_run(wb_session_new(), fault_run)
  baseline <- c(artifacts = nrow(wb_art_list(fault)),
    runs = nrow(DBI::dbGetQuery(fault$con, "SELECT * FROM prov_runs;")),
    commits = nrow(DBI::dbGetQuery(fault$con, "SELECT * FROM prov_commits;")))
  files_before <- sort(list.files(fault$dir, all.files = TRUE,
    recursive = TRUE, no.. = TRUE))
  old_hook <- getOption("scworkbench.promotion_transaction_test_hook")
  options(scworkbench.promotion_transaction_test_hook = function(event, ...) {
    if (identical(event, "after_first_private_terminal_write"))
      stop("injected after first private family terminal")
  })
  rejected <- try(wb_session_promote_current(fault, fault_session,
    outputs = c("pseudotime", "lineage_weights")), silent = TRUE)
  options(scworkbench.promotion_transaction_test_hook = old_hook)
  observed <- c(artifacts = nrow(wb_art_list(fault)),
    runs = nrow(DBI::dbGetQuery(fault$con, "SELECT * FROM prov_runs;")),
    commits = nrow(DBI::dbGetQuery(fault$con, "SELECT * FROM prov_commits;")))
  stopifnot(inherits(rejected, "try-error"),
    grepl("injected after first private family terminal", as.character(rejected),
      fixed = TRUE), identical(observed, baseline),
    identical(sort(list.files(fault$dir, all.files = TRUE,
      recursive = TRUE, no.. = TRUE)), files_before))
  retry <- wb_session_promote_current(fault, fault_session,
    outputs = c("pseudotime", "lineage_weights"))
  stopifnot(nrow(retry$promoted) == 2L,
    all(retry$promoted$status == "ok"))
  wb_close_bundle(fault)
  TRUE
}
