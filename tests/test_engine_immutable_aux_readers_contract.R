# Owned fixtures only. Never open or alter the frozen392 benchmark source.
.engine_immutable_aux_inventory <- function(root) {
  files <- sort(list.files(root, recursive = TRUE, full.names = TRUE,
    all.files = TRUE, no.. = TRUE))
  files <- files[!file.info(files)$isdir]
  data.frame(path = substring(files, nchar(root) + 2L),
    bytes = unname(file.info(files)$size),
    sha256 = unname(vapply(files, function(path)
      digest::digest(file = path, algo = "sha256"), "")))
}
.engine_immutable_aux_policy <- function() scworkbench:::.wb_graph_budgets(list(
  memory_bytes = "16777216", sqlite_cache_kib = 256L,
  partition_bytes = 65536L, partition_rows = 128L, collect_bytes = 1048576L))
.engine_immutable_aux_error <- function(code, expression) {
  error <- tryCatch(force(expression), error = identity)
  stopifnot(inherits(error, "error"), grepl(code, conditionMessage(error), fixed = TRUE))
  invisible(error)
}
.engine_immutable_aux_swap <- function(name, value, package = "scworkbench") {
  ns <- asNamespace(package); old <- get(name, ns)
  unlockBinding(name, ns); assign(name, value, ns); lockBinding(name, ns)
  function() {
    unlockBinding(name, ns); assign(name, old, ns); lockBinding(name, ns)
    stopifnot(identical(get(name, ns), old))
  }
}
.engine_immutable_aux_fixture <- function(special = FALSE) {
  owner <- tempfile("immutable_aux_owned_"); dir.create(owner)
  root <- file.path(owner, if (special) "space ? # %2F 雪.bundle" else "source.bundle")
  b <- NULL; complete <- FALSE
  close <- function() {
    if (!is.null(b) && DBI::dbIsValid(b$con)) wb_close_bundle(b)
    unlink(owner, recursive = TRUE)
  }
  on.exit(if (!complete) close(), add = TRUE)
  b <- wb_init_bundle(root)
  cells <- c("cell_3", "cell_1", "cell_2")
  values <- Matrix::sparseMatrix(i = c(1L, 2L, 1L), j = 1:3,
    x = c(2, 7, 0), dims = c(2L, 3L),
    dimnames = list(c("feature_B", "feature_A"), cells))
  wb_define_cells(b, cells); wb_attach_matrix(b, "counts", values)
  primitive <- wb_prim_cell_vector_family(rep(c("second", "first"), each = 3L),
    rep(cells, 2L), c(0, .25, NA_real_, -1, 2, 3), value_type = "continuous",
    meta = list(label = "Synthetic storage fixture; no method execution."))
  run <- wb_new_run("metadata_cell_vector", outputs = list(vector = primitive),
    notes = "Synthetic immutable-reader storage fixture; no scientific method execution.")
  promoted <- wb_promote_analysis(b, setNames(list(run), run$run_id),
    head_run_id = run$run_id, outputs = "vector")
  id <- promoted$promoted$artifact_id[[1L]]
  stopifnot(wb_finalize_recipient_bundle(b)$ready)
  wb_close_bundle(b); b <- NULL
  db <- file.path(root, "db", "app.sqlite")
  # Deliberately reproduce a CLOSED WAL-format main database on our OWN fixture.
  raw <- DBI::dbConnect(RSQLite::SQLite(), db)
  tryCatch({
    stopifnot(tolower(DBI::dbGetQuery(raw, "PRAGMA journal_mode=WAL;")[[1L]][1L]) == "wal")
    DBI::dbGetQuery(raw, "PRAGMA wal_checkpoint(TRUNCATE);")
  }, finally = DBI::dbDisconnect(raw))
  stopifnot(!file.exists(paste0(db, "-wal")), !file.exists(paste0(db, "-shm")))
  bytes <- file(db, "rb"); header <- tryCatch(readBin(bytes, "raw", 20L), finally = base::close(bytes))
  stopifnot(identical(as.integer(header[19:20]), c(2L, 2L)))
  complete <- TRUE
  list(root = root, db = db, values = values, primitive = primitive,
    artifact_id = id, close = close)
}

test_engine_immutable_aux_public_closed_wal_full_purity_contract <- function() {
  f <- .engine_immutable_aux_fixture(); on.exit(f$close(), add = TRUE)
  before <- .engine_immutable_aux_inventory(f$root)
  b <- wb_open_bundle(f$root, read_only = TRUE, validate = FALSE)
  on.exit(wb_close_bundle(b), add = TRUE, after = FALSE)
  stopifnot(isTRUE(scworkbench:::.wb_sqlite_aux_read_target(b$con)$immutable))
  policy <- .engine_immutable_aux_policy()
  observer <- scworkbench:::.wb_matrix_native_byte_observer(b$con)
  tryCatch({
    row <- DBI::dbGetQuery(b$con, "SELECT rowid,cell_ids_json FROM matrix_fragments ORDER BY rowid LIMIT 1")
    size <- observer$column(as.character(row$rowid[[1L]]), "cell_ids_json")
    stopifnot(identical(observer$read(0, as.numeric(size)), charToRaw(row$cell_ids_json[[1L]])))
    observer$finish()
  }, finally = observer$close())
  resources <- scworkbench:::.wb_manifest_observation_resources(b$con, policy)
  tryCatch({
    stopifnot(isTRUE(scworkbench:::.wb_sqlite_aux_read_target(resources$windows)$immutable))
    actual <- scworkbench:::.wb_manifest_table_identity(b$con, "cells", observer = resources$observer,
      budgets = policy, windows = resources$windows)
    expected <- scworkbench:::.wb_manifest_table_identity_materialized(b$con, "cells")
    stopifnot(identical(actual, expected))
    resources$observer$finish()
  }, finally = resources$close())
  # Non-owned window fallback still needs its own actual immutable connection.
  observer <- scworkbench:::.wb_matrix_native_byte_observer(b$con)
  tryCatch({
    stopifnot(identical(scworkbench:::.wb_manifest_table_identity(b$con, "cells",
      observer = observer, budgets = policy, windows = NULL),
      scworkbench:::.wb_manifest_table_identity_materialized(b$con, "cells")))
    observer$finish()
  }, finally = observer$close())
  stopifnot(isTRUE(scworkbench:::.wb_matrix_bounded_source_verify(b, "counts", policy)),
    identical(as.matrix(wb_slice(b, "counts", features = rownames(f$values), cells = colnames(f$values))),
      as.matrix(f$values)), wb_recipient_readiness(f$root)$ready,
    identical(.engine_immutable_aux_inventory(f$root), before))
  schema <- wb_bundle_schema_status(f$root)
  stopifnot(is.list(schema), identical(schema$status, "current"), identical(.engine_immutable_aux_inventory(f$root), before),
    !file.exists(paste0(f$db, "-wal")), !file.exists(paste0(f$db, "-shm")))
  TRUE
}

test_engine_immutable_aux_legacy_selector_and_escaped_uri_contract <- function() {
  f <- .engine_immutable_aux_fixture(special = TRUE); on.exit(f$close(), add = TRUE)
  before <- .engine_immutable_aux_inventory(f$root)
  b <- wb_open_bundle(f$root, read_only = TRUE, validate = FALSE)
  on.exit(wb_close_bundle(b), add = TRUE, after = FALSE)
  target <- scworkbench:::.wb_sqlite_aux_read_target(b$con)
  stopifnot(target$immutable, grepl("%252F", target$dsn, fixed = TRUE),
    grepl("%3F", target$dsn, fixed = TRUE), grepl("%23", target$dsn, fixed = TRUE),
    grepl("%20", target$dsn, fixed = TRUE))
  actual <- scworkbench:::.wb_getter_legacy_object_identity(b, f$artifact_id,
    .engine_immutable_aux_policy())
  # Independent actual primitive preimage, not a retained expected header claim.
  expected <- scworkbench:::.wb_prov_payload_identity(NULL, f$primitive)$content_sha256
  stopifnot(identical(actual$content_sha256, expected),
    identical(wb_art_load(b, f$artifact_id), f$primitive),
    identical(.engine_immutable_aux_inventory(f$root), before))
  TRUE
}

test_engine_immutable_aux_mutable_wal_foreign_commit_contract <- function() {
  root <- tempfile("mutable_aux_owned_"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  path <- file.path(root, "source.sqlite")
  con <- DBI::dbConnect(RSQLite::SQLite(), path)
  on.exit(if (DBI::dbIsValid(con)) DBI::dbDisconnect(con), add = TRUE, after = FALSE)
  DBI::dbGetQuery(con, "PRAGMA journal_mode=WAL;")
  DBI::dbExecute(con, "CREATE TABLE members(value TEXT)")
  DBI::dbExecute(con, "INSERT INTO members VALUES('initial')")
  target <- scworkbench:::.wb_sqlite_aux_read_target(con)
  stopifnot(identical(target$immutable, FALSE), identical(target$dsn, target$path))
  aux <- scworkbench:::.wb_sqlite_aux_read_connect(con)
  tryCatch(stopifnot(is.null(aux@ref$wb_immutable_sqlite_reader)), finally = DBI::dbDisconnect(aux))
  observer <- scworkbench:::.wb_matrix_native_byte_observer(con)
  tryCatch({
    size <- observer$column("1", "value", "members")
    stopifnot(identical(observer$read(0, as.numeric(size)), charToRaw("initial")))
    foreign <- DBI::dbConnect(RSQLite::SQLite(), path)
    tryCatch(DBI::dbExecute(foreign, "UPDATE members SET value='foreign_committed'"),
      finally = DBI::dbDisconnect(foreign))
    .engine_immutable_aux_error("GRAPH_SOURCE", observer$finish())
    stopifnot(identical(DBI::dbGetQuery(con, "SELECT value FROM members")$value, "foreign_committed"))
  }, finally = observer$close())
  TRUE
}

test_engine_immutable_aux_admission_and_issuance_fail_closed_contract <- function() {
  f <- .engine_immutable_aux_fixture(); on.exit(f$close(), add = TRUE)
  before <- .engine_immutable_aux_inventory(f$root)
  wal <- paste0(f$db, "-wal")
  handle <- file(wal, "wb"); close(handle)
  .engine_immutable_aux_error("Immutable SQLite admission", scworkbench:::.wb_sqlite_connect_immutable(f$db))
  con <- scworkbench:::.wb_sqlite_connect_immutable(f$db, .admission = "empty_wal")
  tryCatch(stopifnot(scworkbench:::.wb_sqlite_aux_read_target(con)$immutable),
    finally = DBI::dbDisconnect(con))
  handle <- file(wal, "wb"); writeBin(as.raw(1:4), handle); close(handle)
  .engine_immutable_aux_error("Immutable SQLite admission", scworkbench:::.wb_sqlite_connect_immutable(f$db,
    .admission = "empty_wal"))
  unlink(wal)
  stopifnot(identical(.engine_immutable_aux_inventory(f$root), before))
  con <- scworkbench:::.wb_sqlite_connect_immutable(f$db)
  on.exit(if (DBI::dbIsValid(con)) DBI::dbDisconnect(con), add = TRUE, after = FALSE)
  original <- con@ref$wb_immutable_sqlite_reader
  opened <- 0L; connect <- get("dbConnect", asNamespace("DBI"))
  undo <- .engine_immutable_aux_swap("dbConnect", function(...) { opened <<- opened + 1L; connect(...) }, "DBI")
  tryCatch({
    for (field in c("path", "dsn", "dbname")) {
      bad <- original; bad[[field]] <- paste0(bad[[field]], "_stale")
      con@ref$wb_immutable_sqlite_reader <- bad
      .engine_immutable_aux_error("differs from its issuing connection",
        scworkbench:::.wb_sqlite_aux_read_connect(con))
    }
    stopifnot(opened == 0L)
  }, finally = { con@ref$wb_immutable_sqlite_reader <- original; undo() })
  peer <- scworkbench:::.wb_sqlite_connect_immutable(f$db)
  tryCatch({
    peer@ref$wb_immutable_sqlite_reader <- original
    .engine_immutable_aux_error("differs from its issuing connection",
      scworkbench:::.wb_sqlite_aux_read_connect(peer))
  }, finally = DBI::dbDisconnect(peer))
  observer <- scworkbench:::.wb_matrix_native_byte_observer(con)
  tryCatch({
    for (change in c("remove", "downgrade")) {
      altered <- original
      if (change == "remove") altered <- NULL else altered$admission <- "empty_wal"
      con@ref$wb_immutable_sqlite_reader <- altered
      .engine_immutable_aux_error("Immutable SQLite reader changed during observation", observer$finish())
      con@ref$wb_immutable_sqlite_reader <- original
    }
    observer$finish()
  }, finally = { con@ref$wb_immutable_sqlite_reader <- original; observer$close() })
  # Actual SQLITE_RO alone (even with an unrelated forged bundle-style flag)
  # cannot manufacture evidence of immutable URI construction.
  # A plain read-only open may itself create sidecars on a WAL-header database.
  # Exercise that negative authority case on an independent owned copy, not on
  # the fixture whose complete immutable-reader fingerprint we assert below.
  plain_path <- file.path(dirname(f$root), "plain_authority_probe.sqlite")
  stopifnot(file.copy(f$db, plain_path))
  plain <- DBI::dbConnect(RSQLite::SQLite(), plain_path, flags = RSQLite::SQLITE_RO)
  tryCatch({
    plain@ref$read_only <- TRUE
    stopifnot(!scworkbench:::.wb_sqlite_aux_read_target(plain)$immutable,
      is.null(plain@ref$wb_immutable_sqlite_reader))
  }, finally = DBI::dbDisconnect(plain))
  stopifnot(identical(.engine_immutable_aux_inventory(f$root), before))
  TRUE
}

test_engine_immutable_aux_native_rejection_and_resource_cleanup_contract <- function() {
  f <- .engine_immutable_aux_fixture(); on.exit(f$close(), add = TRUE)
  b <- wb_open_bundle(f$root, read_only = TRUE, validate = FALSE)
  on.exit(wb_close_bundle(b), add = TRUE, after = FALSE)
  ns <- asNamespace("scworkbench")
  scworkbench:::.wb_matrix_native_byte_api_initialize()
  open <- get("C_scwb_graph_bytes_open", ns)
  before <- .engine_immutable_aux_inventory(f$root)
  for (path in c(f$db, paste0("file:", f$db), paste0("file:", f$db, "?immutable=0")))
    .engine_immutable_aux_error("native immutable URI is not core-framed", .Call(open, path, TRUE))
  for (mode in list(NULL, 1L, NA, c(TRUE, FALSE)))
    .engine_immutable_aux_error("invalid native URI mode", .Call(open, f$db, mode))
  missing <- file.path(f$root, "missing_owned.sqlite")
  .engine_immutable_aux_error("native read-only database open", .Call(open,
    scworkbench:::.wb_sqlite_immutable_uri(missing), TRUE))
  stopifnot(!file.exists(missing))
  policy <- .engine_immutable_aux_policy()
  warm <- scworkbench:::.wb_manifest_observation_resources(b$con, policy); warm$close()
  fd <- function() if (dir.exists("/proc/self/fd")) length(list.files("/proc/self/fd")) else NA_integer_
  before_fd <- fd(); cache <- DBI::dbGetQuery(b$con, "PRAGMA cache_size")
  temp <- DBI::dbGetQuery(b$con, "PRAGMA temp_store")
  prior_policy <- b$con@ref$wb_graph_policy; prior_cap <- b$con@ref$wb_graph_cache_kib
  for (failure in c("window", "admission")) {
    if (failure == "window") {
      undo <- .engine_immutable_aux_swap(".wb_sqlite_aux_read_connect", function(...) stop("IMMUTABLE_WINDOW_FAULT"))
    } else {
      real <- get(".wb_graph_spill_admit", ns)
      undo <- .engine_immutable_aux_swap(".wb_graph_spill_admit", function(...) {
        real(...); stop("IMMUTABLE_ADMISSION_FAULT")
      })
    }
    tryCatch(.engine_immutable_aux_error("IMMUTABLE_", scworkbench:::.wb_manifest_observation_resources(b$con, policy)),
      finally = undo())
    stopifnot(identical(cache, DBI::dbGetQuery(b$con, "PRAGMA cache_size")),
      identical(temp, DBI::dbGetQuery(b$con, "PRAGMA temp_store")),
      identical(prior_policy, b$con@ref$wb_graph_policy),
      identical(prior_cap, b$con@ref$wb_graph_cache_kib),
      is.na(before_fd) || identical(before_fd, fd()),
      identical(.engine_immutable_aux_inventory(f$root), before))
  }
  tiny <- policy; tiny$memory_bytes <- "1"
  .engine_immutable_aux_error("GRAPH_RESOURCE", scworkbench:::.wb_manifest_observation_resources(b$con, tiny))
  stopifnot(identical(cache, DBI::dbGetQuery(b$con, "PRAGMA cache_size")),
    identical(temp, DBI::dbGetQuery(b$con, "PRAGMA temp_store")),
    identical(prior_policy, b$con@ref$wb_graph_policy), identical(prior_cap, b$con@ref$wb_graph_cache_kib))
  retry <- scworkbench:::.wb_manifest_observation_resources(b$con, policy)
  tryCatch(retry$observer$finish(), finally = retry$close())
  stopifnot(is.na(before_fd) || identical(before_fd, fd()),
    identical(.engine_immutable_aux_inventory(f$root), before))
  TRUE
}
