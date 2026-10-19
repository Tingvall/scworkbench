# Owned-only source-order regressions. No frozen benchmark bundle is opened.
.engine_epoch_order_fixture <- function() {
  root <- tempfile("epoch_order_owned_"); b <- NULL; complete <- FALSE
  cleanup <- function() {
    if (!is.null(b) && DBI::dbIsValid(b$con)) wb_close_bundle(b)
    unlink(root, recursive = TRUE)
  }
  on.exit(if (!complete) cleanup(), add = TRUE)
  b <- wb_init_bundle(root); wb_define_cells(b, c("cell_2", "cell_1"))
  complete <- TRUE
  list(root = root, bundle = b, close = cleanup)
}
.engine_epoch_order_swap <- function(name, value, package = "DBI") {
  ns <- asNamespace(package); old <- get(name, ns)
  unlockBinding(name, ns); assign(name, value, ns); lockBinding(name, ns)
  function() { unlockBinding(name, ns); assign(name, old, ns); lockBinding(name, ns)
    stopifnot(identical(get(name, ns), old)) }
}
.engine_epoch_order_empty_temp <- function(con) {
  stopifnot(nrow(DBI::dbGetQuery(con, "SELECT name FROM temp.sqlite_schema")) == 0L)
  DBI::dbExecute(con, "PRAGMA temp_store=MEMORY")
  DBI::dbExecute(con, "PRAGMA temp_store=DEFAULT")
  stopifnot(nrow(DBI::dbGetQuery(con, "SELECT name FROM temp.sqlite_schema")) == 0L)
  invisible(NULL)
}
.engine_epoch_order_inventory <- function(root) {
  paths <- sort(list.files(root, full.names = TRUE, recursive = TRUE, all.files = TRUE, no.. = TRUE))
  paths <- paths[!file.info(paths)$isdir]
  setNames(vapply(paths, function(path) digest::digest(file = path, algo = "sha256"), ""),
    substring(paths, nchar(root) + 2L))
}

# An invocation may avoid repeating a successful manifest publication, but this
# never substitutes for payload authentication, recovery or explicit validation.
.engine_epoch_order_old_871 <- function(bundle) {
  con <- bundle$con
  if (!DBI::dbIsValid(con) || isTRUE(RSQLite::sqliteIsTransacting(con))) return(NULL)
  key <- .wb_writer_lock_key(bundle)
  if (!.wb_writer_lock_held(bundle)) return(NULL)
  entry <- get(key, envir = .wb_writer_lock_state$held, inherits = FALSE)
  owner <- .wb_writer_lock_read_metadata(entry$lock_path)
  if (is.null(owner) || !identical(as.character(owner$owner_token),
      as.character(entry$token))) return(NULL)
  exact <- function(x) {
    .wb_assert(is.numeric(x) && !is.object(x) && length(x) == 1L &&
      !is.na(x) && is.finite(x) && x >= 0 && x <= 2^53 - 1 && x == floor(x),
      "Publication witness SQL counter is unavailable or inexact.")
    x
  }
  databases <- DBI::dbGetQuery(con, "PRAGMA database_list;")
  # TEMP may not yet appear in database_list. Its real definitions must always
  # participate; schema_version alone can be reset by callers and DDL rollback.
  names <- unique(c("main", "temp", as.character(databases$name)))
  schemas <- setNames(lapply(names, function(name) {
    quoted <- as.character(DBI::dbQuoteIdentifier(con, name))
    list(version = exact(DBI::dbGetQuery(con,
      paste0("PRAGMA ", quoted, ".schema_version;"))[[1L]]),
      data = exact(DBI::dbGetQuery(con,
        paste0("PRAGMA ", quoted, ".data_version;"))[[1L]]),
      sql = DBI::dbGetQuery(con, paste0("SELECT type,name,tbl_name,sql FROM ",
        quoted, ".sqlite_schema ORDER BY type,name,tbl_name,sql;")))
  }), names)
  list(connection = con@ref, writer_key = key, writer_token = entry$token,
    changes = exact(DBI::dbGetQuery(con, "SELECT total_changes();")[[1L]]),
    data = exact(DBI::dbGetQuery(con, "PRAGMA main.data_version;")[[1L]]),
    databases = databases, schemas = schemas)
}

test_engine_epoch_order_actual_final_list_and_old_literal_contract <- function() {
  f <- .engine_epoch_order_fixture(); b <- f$bundle; on.exit(f$close(), add = TRUE)
  old <- .engine_epoch_order_old_871; environment(old) <- asNamespace("scworkbench")
  epoch <- scworkbench:::.wb_manifest_publication_epoch
  .engine_epoch_order_empty_temp(b$con)
  before <- old(b)
  actual_state <- scworkbench:::.wb_manifest_registry_snapshot(b$con)
  after <- old(b)
  strip <- function(key) { key$databases <- NULL; key }
  stopifnot(!identical(before, after), identical(strip(before), strip(after)),
    identical(before$connection, b$con@ref), identical(after$connection, b$con@ref),
    identical(before$writer_key, scworkbench:::.wb_writer_lock_key(b)),
    identical(before$writer_token, after$writer_token),
    "temp" %in% before$databases$name, !"temp" %in% after$databases$name,
    identical(names(before), names(after)), identical(names(before$schemas), names(after$schemas)))
  .engine_epoch_order_empty_temp(b$con)
  current_before <- epoch(b)
  stopifnot(identical(current_before$databases, DBI::dbGetQuery(b$con, "PRAGMA database_list;")))
  actual_again <- scworkbench:::.wb_manifest_registry_snapshot(b$con)
  current_after <- epoch(b)
  stopifnot(identical(actual_state, actual_again), identical(current_before, current_after),
    identical(current_after$databases, DBI::dbGetQuery(b$con, "PRAGMA database_list;")),
    identical(strip(before), strip(current_before)),
    identical(current_after$schemas$temp, before$schemas$temp),
    all(c("main", "temp") %in% current_after$databases$name))
  TRUE
}

test_engine_epoch_order_real_schema_attachment_and_foreign_change_contract <- function() {
  f <- .engine_epoch_order_fixture(); b <- f$bundle; on.exit(f$close(), add = TRUE)
  epoch <- scworkbench:::.wb_manifest_publication_epoch
  DBI::dbExecute(b$con, "PRAGMA temp_store=FILE")
  original <- epoch(b)
  DBI::dbExecute(b$con, "CREATE TEMP TABLE epoch_actual_temp(x TEXT)")
  temp_changed <- epoch(b)
  stopifnot(!identical(original, temp_changed),
    "epoch_actual_temp" %in% temp_changed$schemas$temp$sql$name,
    identical(temp_changed$databases, DBI::dbGetQuery(b$con, "PRAGMA database_list;")))
  DBI::dbExecute(b$con, "DROP TABLE temp.epoch_actual_temp")
  original <- epoch(b); cookie <- original$schemas$main$version
  DBI::dbExecute(b$con, "CREATE TABLE epoch_actual_main(x TEXT)")
  DBI::dbExecute(b$con, paste0("PRAGMA main.schema_version=", cookie))
  reset_cookie <- epoch(b)
  stopifnot(identical(reset_cookie$schemas$main$version, cookie),
    !identical(original, reset_cookie), "epoch_actual_main" %in% reset_cookie$schemas$main$sql$name)
  attached <- file.path(f$root, "owned_attached.sqlite")
  original <- epoch(b)
  DBI::dbExecute(b$con, "ATTACH DATABASE ? AS epoch_attached", params = list(attached))
  with_attached <- epoch(b)
  stopifnot(!identical(original, with_attached), "epoch_attached" %in% names(with_attached$schemas),
    "epoch_attached" %in% with_attached$databases$name)
  DBI::dbExecute(b$con, "DETACH DATABASE epoch_attached")
  without_attached <- epoch(b)
  stopifnot(!identical(with_attached, without_attached), !"epoch_attached" %in% without_attached$databases$name)
  original <- epoch(b)
  foreign <- DBI::dbConnect(RSQLite::SQLite(), file.path(f$root, "db", "app.sqlite"))
  tryCatch(DBI::dbExecute(foreign, "INSERT INTO cells(cell_id) VALUES('foreign_actual')"),
    finally = DBI::dbDisconnect(foreign))
  changed <- epoch(b)
  stopifnot(!identical(original, changed), original$data != changed$data,
    identical(changed$connection, original$connection),
    identical(changed$writer_token, original$writer_token),
    "foreign_actual" %in% DBI::dbGetQuery(b$con, "SELECT cell_id FROM cells")$cell_id)
  TRUE
}

test_engine_epoch_order_between_observations_attach_detach_contract <- function() {
  f <- .engine_epoch_order_fixture(); b <- f$bundle; on.exit(f$close(), add = TRUE)
  epoch <- scworkbench:::.wb_manifest_publication_epoch
  attached <- file.path(f$root, "injected_owned.sqlite")
  real <- get("dbGetQuery", asNamespace("DBI"))
  for (action in c("attach", "detach")) {
    if (action == "detach") DBI::dbExecute(b$con,
      "ATTACH DATABASE ? AS epoch_between", params = list(attached))
    queries <- 0L; fired <- FALSE
    undo <- .engine_epoch_order_swap("dbGetQuery", function(conn, statement, ...) {
      if (identical(conn@ref, b$con@ref) && identical(statement, "PRAGMA database_list;")) {
        queries <<- queries + 1L
        if (queries == 2L) {
          if (action == "attach") DBI::dbExecute(conn,
            "ATTACH DATABASE ? AS epoch_between", params = list(attached)) else
            DBI::dbExecute(conn, "DETACH DATABASE epoch_between")
          fired <<- TRUE
        }
      }
      real(conn, statement, ...)
    })
    answer <- tryCatch(epoch(b), finally = undo())
    stopifnot(fired, queries == 2L, is.null(answer), !RSQLite::sqliteIsTransacting(b$con))
    if (action == "attach") DBI::dbExecute(b$con, "DETACH DATABASE epoch_between")
    retry <- epoch(b)
    stopifnot(!is.null(retry), identical(retry$connection, b$con@ref),
      identical(retry$databases, real(b$con, "PRAGMA database_list;")),
      !"epoch_between" %in% retry$databases$name,
      scworkbench:::.wb_writer_lock_held(b))
  }
  TRUE
}

test_engine_epoch_order_publication_authority_failure_and_readonly_contract <- function() {
  f <- .engine_epoch_order_fixture(); b <- f$bundle; old_hook <- getOption("scworkbench.manifest_test_hook")
  on.exit({ options(scworkbench.manifest_test_hook = old_hook)
    if (DBI::dbIsValid(b$con)) wb_close_bundle(b)
    f$close()
  }, add = TRUE)
  count <- 0L; observed_context <- list()
  options(scworkbench.manifest_test_hook = function(event, ...) {
    if (event == "published") {
      count <<- count + 1L
      observed_context[[length(observed_context) + 1L]] <<-
        list(context_is_null = is.null(scworkbench:::.wb_current_mutation_context(b$con)))
    }
  })
  wb_refresh_manifest(b); stopifnot(count == 1L)
  scworkbench:::.wb_with_bundle_writer_lock(b, code = TRUE)
  stopifnot(count == 1L)
  wb_migrate_bundle(b); stopifnot(count == 2L)
  path <- file.path(f$root, "manifest.json")
  before_bytes <- readBin(path, "raw", n = file.info(path)$size)
  owner <- scworkbench:::.wb_manifest_publication_epoch(b)
  options(scworkbench.manifest_test_hook = function(event, ...) {
    stopifnot(is.null(scworkbench:::.wb_current_mutation_context(b$con)))
    if (event == "before_publish") stop("EPOCH_ORDER_BEFORE_PUBLISH_FAULT")
  })
  failed <- tryCatch(wb_refresh_manifest(b), error = identity)
  stopifnot(inherits(failed, "error"), grepl("EPOCH_ORDER_BEFORE_PUBLISH_FAULT", conditionMessage(failed), fixed = TRUE),
    identical(before_bytes, readBin(path, "raw", n = file.info(path)$size)),
    scworkbench:::.wb_writer_lock_held(b),
    identical(scworkbench:::.wb_manifest_publication_epoch(b)$writer_token, owner$writer_token))
  options(scworkbench.manifest_test_hook = old_hook)
  wb_refresh_manifest(b)
  stopifnot(isTRUE(wb_finalize_recipient_bundle(b)$ready),
    all(vapply(observed_context, function(x) x$context_is_null, logical(1))))
  wb_close_bundle(b)
  stopifnot(is.null(scworkbench:::.wb_manifest_publication_epoch(b)))
  before <- .engine_epoch_order_inventory(f$root)
  b <- wb_open_bundle(f$root, read_only = TRUE, validate = FALSE)
  stopifnot(is.null(scworkbench:::.wb_manifest_publication_epoch(b)),
    identical(wb_cells(b), c("cell_2", "cell_1")), wb_recipient_readiness(f$root)$ready,
    identical(.engine_epoch_order_inventory(f$root), before))
  wb_close_bundle(b)
  stopifnot(identical(.engine_epoch_order_inventory(f$root), before))
  TRUE
}
