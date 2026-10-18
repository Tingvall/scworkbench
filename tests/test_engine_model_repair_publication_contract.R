.engine_model_repair_fixture <- function() {
  root <- tempfile("model_repair_publication_"); dir.create(root)
  b <- wb_init_bundle(file.path(root, "bundle"))
  ready <- FALSE
  on.exit(if (!ready) wb_close_bundle(b), add = TRUE)
  wb_define_cells(b, c("c2", "c1"))
  wb_add_space(b, "source", matrix(1:6, 2L,
    dimnames = list(c("c2", "c1"), c("PC1", "PC2", "PC3"))))
  source <- file.path(root, "external.rds")
  saveRDS(list(contract = "synthetic legacy model storage; no method execution"), source)
  DBI::dbExecute(b$con, paste(
    "INSERT INTO space_models(space_id,model_type,source_space_id,dims_json,cell_set,uwot_args_json,seed,model_path,created_at,provenance_json)",
    "VALUES(?,?,?,?,?,?,?,?,?,?)"), params = list("source", "legacy_rds", "source",
      "[1,2,3]", "all", "{}", NA_integer_, source, "2026-10-19", "{}"))
  target <- file.path(b$dir, "models", "imported", "source.rds")
  ready <- TRUE
  list(root = root, b = b, source = source, target = target,
    sha = digest::digest(file = source, algo = "sha256"))
}

.engine_model_repair_state <- function(b) {
  tables <- sort(DBI::dbListTables(b$con))
  tables <- tables[!startsWith(tables, "sqlite_")]
  setNames(lapply(tables, function(table) DBI::dbGetQuery(b$con,
    paste0("SELECT * FROM ", DBI::dbQuoteIdentifier(b$con, table)))), tables)
}

test_engine_model_repair_transaction_rollback_contract <- function() {
  f <- .engine_model_repair_fixture()
  on.exit(if (DBI::dbIsValid(f$b$con)) wb_close_bundle(f$b), add = TRUE)
  before <- .engine_model_repair_state(f$b)
  DBI::dbExecute(f$b$con, paste("CREATE TRIGGER reject_repair BEFORE UPDATE ON space_models",
    "BEGIN SELECT RAISE(ABORT,'repair transaction fault'); END"))
  error <- tryCatch(wb_repair_model_ref_paths(f$b, dry_run = FALSE,
    import_external = TRUE), error = identity)
  stopifnot(inherits(error, "error"), grepl("repair transaction fault", conditionMessage(error)),
    !file.exists(f$target), file.exists(f$source),
    identical(digest::digest(file = f$source, algo = "sha256"), f$sha),
    identical(before, .engine_model_repair_state(f$b)),
    !RSQLite::sqliteIsTransacting(f$b$con))
  DBI::dbExecute(f$b$con, "DROP TRIGGER reject_repair")
  wb_repair_model_ref_paths(f$b, dry_run = FALSE, import_external = TRUE)
  stopifnot(file.exists(f$target),
    identical(digest::digest(file = f$target, algo = "sha256"), f$sha))
  TRUE
}

test_engine_model_repair_postcommit_publication_retry_contract <- function() {
  f <- .engine_model_repair_fixture()
  on.exit(if (DBI::dbIsValid(f$b$con)) wb_close_bundle(f$b), add = TRUE)
  scworkbench:::.wb_with_mutation_context(f$b, route = "ingestion",
    code = wb_refresh_manifest(f$b))
  manifest <- digest::digest(file = file.path(f$b$dir, "manifest.json"), algo = "sha256")
  before <- .engine_model_repair_state(f$b)
  saw <- FALSE
  old <- options(scworkbench.manifest_test_hook = function(event, ...) {
    path <- DBI::dbGetQuery(f$b$con, "SELECT model_path FROM space_models WHERE space_id='source'")$model_path[[1L]]
    if (event == "before_publish" && identical(path, "models/imported/source.rds")) {
      stopifnot(!RSQLite::sqliteIsTransacting(f$b$con), file.exists(f$target))
      saw <<- TRUE
      stop("repair publication fault")
    }
  })
  on.exit(options(old), add = TRUE, after = FALSE)
  error <- tryCatch(wb_repair_model_ref_paths(f$b, dry_run = FALSE,
    import_external = TRUE), error = identity)
  options(old)
  stopifnot(inherits(error, "error"), grepl("repair publication fault", conditionMessage(error)),
    saw, !RSQLite::sqliteIsTransacting(f$b$con), file.exists(f$target),
    identical(digest::digest(file = f$target, algo = "sha256"), f$sha),
    identical(digest::digest(file = f$source, algo = "sha256"), f$sha),
    identical(digest::digest(file = file.path(f$b$dir, "manifest.json"), algo = "sha256"), manifest))
  committed <- .engine_model_repair_state(f$b)
  stopifnot(!identical(before, committed),
    nrow(committed$prov_runs) > nrow(before$prov_runs),
    identical(DBI::dbGetQuery(f$b$con,
      "SELECT model_path FROM space_models WHERE space_id='source'")$model_path[[1L]],
      "models/imported/source.rds"))
  scworkbench:::.wb_with_mutation_context(f$b, route = "ingestion",
    code = wb_refresh_manifest(f$b))
  stopifnot(identical(committed, .engine_model_repair_state(f$b)),
    !identical(digest::digest(file = file.path(f$b$dir, "manifest.json"), algo = "sha256"), manifest))
  path <- f$b$dir; wb_close_bundle(f$b)
  reopened <- wb_open_bundle(path, read_only = TRUE)
  on.exit(wb_close_bundle(reopened), add = TRUE)
  stopifnot(identical(committed, .engine_model_repair_state(reopened)),
    identical(digest::digest(file = f$target, algo = "sha256"), f$sha))
  TRUE
}

test_engine_model_repair_caller_transaction_rejection_contract <- function() {
  f <- .engine_model_repair_fixture()
  on.exit(if (DBI::dbIsValid(f$b$con)) wb_close_bundle(f$b), add = TRUE)
  DBI::dbBegin(f$b$con)
  on.exit(if (DBI::dbIsValid(f$b$con) && RSQLite::sqliteIsTransacting(f$b$con))
    DBI::dbRollback(f$b$con), add = TRUE, after = FALSE)
  before <- .engine_model_repair_state(f$b)
  error <- tryCatch(wb_repair_model_ref_paths(f$b, dry_run = FALSE,
    import_external = TRUE), error = identity)
  stopifnot(inherits(error, "error"), grepl("caller-owned transaction", conditionMessage(error)),
    RSQLite::sqliteIsTransacting(f$b$con), !file.exists(f$target),
    identical(before, .engine_model_repair_state(f$b)))
  DBI::dbRollback(f$b$con)
  TRUE
}
