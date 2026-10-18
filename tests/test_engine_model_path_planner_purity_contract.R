.engine_model_planner_fixture <- function() {
  root <- tempfile("model_path_planner_")
  b <- wb_init_bundle(root)
  wb_define_cells(b, c("c2", "c1"))
  wb_add_space(b, "source", matrix(1:4, 2L,
    dimnames = list(c("c2", "c1"), c("PC1", "PC2"))))
  dir.create(file.path(root, "models"), showWarnings = FALSE)
  payload <- file.path(root, "models", "local.rds")
  saveRDS(list(contract = "generic planner fixture"), payload)
  DBI::dbExecute(b$con, paste(
    "INSERT INTO space_models(space_id,model_type,source_space_id,dims_json,cell_set,uwot_args_json,seed,model_path,created_at,provenance_json)",
    "VALUES(?,?,?,?,?,?,?,?,?,?)"), params = list("source", "legacy_rds", "source",
      "[1,2]", "all", "{}", NA_integer_, normalizePath(payload), "2026-10-19", "{}"))
  list(b = b, root = root)
}
.engine_model_planner_files <- function(root) {
  paths <- sort(list.files(root, recursive = TRUE, full.names = TRUE,
    all.files = TRUE, no.. = TRUE))
  paths <- paths[!file.info(paths)$isdir]
  data.frame(path = substring(paths, nchar(root) + 2L), bytes = file.info(paths)$size,
    sha256 = vapply(paths, function(p) digest::digest(file = p, algo = "sha256"), ""))
}
.engine_model_planner_observe <- function(b, expression) {
  ns <- asNamespace("scworkbench")
  names <- c("wb_migrate_artifacts", ".wb_manifest_publish_current_locked")
  originals <- mget(names, envir = ns)
  counts <- setNames(integer(length(names)), names)
  replace <- function(name, fn) {
    unlockBinding(name, ns); assign(name, fn, ns); lockBinding(name, ns)
  }
  on.exit(for (name in names) replace(name, originals[[name]]), add = TRUE)
  for (name in names) local({
    key <- name; original <- originals[[key]]
    replace(key, function(...) {
      counts[[key]] <<- counts[[key]] + 1L
      original(...)
    })
  })
  # Establish the SQL observer first: its initial WAL read can move SQLite's
  # shared-memory read marker without any scientific or registry mutation.
  # Keep both complete inventories strict; do not exclude the SHM file.
  sql_before <- DBI::dbGetQuery(b$con,
    "SELECT total_changes() AS changes, (SELECT * FROM pragma_data_version) AS version")
  before <- .engine_model_planner_files(b$dir)
  result <- tryCatch(force(expression), error = identity)
  sql_after <- DBI::dbGetQuery(b$con,
    "SELECT total_changes() AS changes, (SELECT * FROM pragma_data_version) AS version")
  after <- .engine_model_planner_files(b$dir)
  stopifnot(identical(before, after), identical(sql_before, sql_after), all(counts == 0L))
  result
}
test_engine_model_path_planner_writable_purity_contract <- function() {
  f <- .engine_model_planner_fixture(); b <- f$b
  on.exit({if (DBI::dbIsValid(b$con)) wb_close_bundle(b); unlink(f$root, recursive = TRUE)}, add = TRUE)
  expected <- data.frame(artifact_id = NA_character_, registry_table = "space_models",
    entity_id = "source", old_model_path = normalizePath(file.path(f$root, "models", "local.rds")),
    new_model_path = "models/local.rds", action = "repair_absolute_inside_bundle")
  result <- .engine_model_planner_observe(b, wb_repair_model_ref_paths(b, dry_run = TRUE))
  stopifnot(identical(result, expected))
  # Planning an explicitly authorized import still cannot probe/read an external
  # source: even a guaranteed absent source produces only a plan, not an error.
  absent <- file.path(dirname(f$root), paste0(basename(f$root), "_absent_external.rds"))
  stopifnot(!file.exists(absent))
  DBI::dbExecute(b$con, "UPDATE space_models SET model_path=?", params = list(absent))
  default <- .engine_model_planner_observe(b, wb_repair_model_ref_paths(b))
  authorized <- .engine_model_planner_observe(b,
    wb_repair_model_ref_paths(b, import_external = TRUE))
  stopifnot(identical(default$action, "legacy_external_nonportable"),
    identical(authorized$action, "import_legacy_external"), !file.exists(absent))
  TRUE
}
test_engine_model_path_planner_readonly_parity_contract <- function() {
  f <- .engine_model_planner_fixture(); b <- f$b
  on.exit({if (DBI::dbIsValid(b$con)) wb_close_bundle(b); unlink(f$root, recursive = TRUE)}, add = TRUE)
  writable <- .engine_model_planner_observe(b, wb_repair_model_ref_paths(b))
  wb_finalize_recipient_bundle(b); wb_close_bundle(b)
  b <- wb_open_bundle(f$root, read_only = TRUE)
  readonly <- .engine_model_planner_observe(b, wb_repair_model_ref_paths(b))
  stopifnot(identical(writable, readonly))
  TRUE
}
test_engine_model_path_planner_schema_rejection_contract <- function() {
  f <- .engine_model_planner_fixture(); b <- f$b
  on.exit({
    if (DBI::dbIsValid(b$con)) {
      if (RSQLite::sqliteIsTransacting(b$con)) DBI::dbRollback(b$con)
      wb_close_bundle(b)
    }
    unlink(f$root, recursive = TRUE)
  }, add = TRUE)
  for (statement in c("DELETE FROM bundle_schema_migrations WHERE version=(SELECT MAX(version) FROM bundle_schema_migrations)",
    "UPDATE bundle_schema_migrations SET migration_id='invalid-ledger-entry' WHERE version=1")) {
    DBI::dbBegin(b$con); DBI::dbExecute(b$con, statement)
    error <- .engine_model_planner_observe(b, wb_repair_model_ref_paths(b))
    stopifnot(inherits(error, "error"),
      grepl("BUNDLE_SCHEMA_(UPGRADE_REQUIRED|CORRUPT)", conditionMessage(error)),
      grepl("wb_migrate_bundle()", conditionMessage(error), fixed = TRUE),
      RSQLite::sqliteIsTransacting(b$con))
    DBI::dbRollback(b$con)
  }
  TRUE
}
