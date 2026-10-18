.engine_retained_graph_fixture <- function() {
  root <- tempfile("retained_graph_observation_")
  b <- wb_init_bundle(root)
  ok <- FALSE
  on.exit(if (!ok) wb_close_bundle(b), add = TRUE)
  graph <- wb_prim_graph(list(list(node_id = "isolated_雪")), list(), list())
  run <- wb_new_run("metadata_cell_vector", inputs = list(), params = list(),
    outputs = list(vector = graph),
    notes = "Synthetic storage fixture; no scientific method execution.")
  promoted <- wb_promote_analysis(b, setNames(list(run), run$run_id),
    head_run_id = run$run_id, outputs = "vector")
  scworkbench:::.wb_session_source_forget(b$con)
  ok <- TRUE
  list(root = root, b = b, id = promoted$promoted$artifact_id[[1L]])
}

.engine_retained_graph_replace <- function(name, replacement) {
  ns <- asNamespace("scworkbench")
  original <- get(name, ns, inherits = FALSE)
  unlockBinding(name, ns); assign(name, replacement, ns); lockBinding(name, ns)
  function() {
    unlockBinding(name, ns); assign(name, original, ns); lockBinding(name, ns)
  }
}

.engine_retained_graph_spy <- function() {
  state <- new.env(parent = emptyenv()); state$actual <- 0L; state$certificates <- 0L
  actual <- scworkbench:::.wb_graph_sql_identities
  certificate <- scworkbench:::.wb_graph_certificate_scan
  restore_actual <- .engine_retained_graph_replace(".wb_graph_sql_identities",
    function(...) { state$actual <- state$actual + 1L; actual(...) })
  restore_certificate <- .engine_retained_graph_replace(".wb_graph_certificate_scan",
    function(...) { state$certificates <- state$certificates + 1L; certificate(...) })
  list(state = state, close = function() { restore_certificate(); restore_actual() })
}

test_engine_retained_graph_warm_actual_and_fresh_claims_contract <- function() {
  f <- .engine_retained_graph_fixture(); on.exit(wb_close_bundle(f$b), add = TRUE)
  spy <- .engine_retained_graph_spy(); on.exit(spy$close(), add = TRUE)
  first <- wb_art_graph_info(f$b, f$id)
  second <- wb_art_graph_info(f$b, f$id)
  stopifnot(spy$state$actual == 1L, spy$state$certificates == 2L,
    identical(first$content_identity, second$content_identity),
    !is.null(f$b$con@ref$wb_graph_retained_observation),
    as.numeric(object.size(f$b$con@ref$wb_graph_retained_observation)) <= 65536)
  second$content_identity$sha256 <- "not_the_actual_digest"
  stopifnot(identical(wb_art_graph_info(f$b, f$id)$content_identity,
    first$content_identity), spy$state$actual == 1L)
  source <- scworkbench:::.wb_graph_sources_assert
  restore <- .engine_retained_graph_replace(".wb_graph_sources_assert",
    function(...) stop("fresh association fault"))
  on.exit(restore(), add = TRUE, after = FALSE)
  stopifnot(identical(wb_art_graph_info(f$b, f$id)$source_authority$status,
    "unverified"), spy$state$actual == 1L)
  TRUE
}

test_engine_retained_graph_mutation_transaction_and_certificate_contract <- function() {
  f <- .engine_retained_graph_fixture(); on.exit(wb_close_bundle(f$b), add = TRUE)
  spy <- .engine_retained_graph_spy(); on.exit(spy$close(), add = TRUE)
  wb_art_graph_info(f$b, f$id)
  DBI::dbExecute(f$b$con, "UPDATE artifacts SET description='changed' WHERE artifact_id=?",
    params = list(f$id))
  wb_art_graph_info(f$b, f$id)
  stopifnot(spy$state$actual == 2L)
  # Full verification's existing disk-backed sorter cannot change temp_store
  # inside a caller transaction. Admit that same policy before owning the TX.
  DBI::dbExecute(f$b$con, "PRAGMA temp_store=FILE")
  DBI::dbBegin(f$b$con)
  on.exit(if (DBI::dbIsValid(f$b$con) && RSQLite::sqliteIsTransacting(f$b$con))
    DBI::dbRollback(f$b$con), add = TRUE, after = FALSE)
  DBI::dbExecute(f$b$con, "SAVEPOINT observation_owner")
  wb_art_graph_info(f$b, f$id)
  stopifnot(spy$state$actual == 3L,
    is.null(f$b$con@ref$wb_graph_retained_observation),
    RSQLite::sqliteIsTransacting(f$b$con))
  DBI::dbExecute(f$b$con,
    "UPDATE prov_run_outputs SET content_sha256='corrupt' WHERE artifact_id=?",
    params = list(f$id))
  failure <- tryCatch(wb_art_graph_info(f$b, f$id), error = identity)
  stopifnot(inherits(failure, "wb_graph_error"),
    identical(failure$code, "GRAPH_CONTENT_IDENTITY_MISMATCH"),
    is.null(f$b$con@ref$wb_graph_retained_observation))
  DBI::dbExecute(f$b$con, "ROLLBACK TO observation_owner")
  DBI::dbRollback(f$b$con)
  wb_art_graph_info(f$b, f$id)
  stopifnot(spy$state$actual == 5L, !is.null(f$b$con@ref$wb_graph_retained_observation))
  # Even with an unchanged SQL epoch, every independent certificate is checked.
  certificate <- scworkbench:::.wb_graph_certificate_scan
  restore <- .engine_retained_graph_replace(".wb_graph_certificate_scan",
    function(con, artifact_id, callback, ...) certificate(con, artifact_id,
      function(row) { row$content_sha256 <- "different_independent_claim"; callback(row) }, ...))
  on.exit(restore(), add = TRUE, after = FALSE)
  failure <- tryCatch(wb_art_graph_info(f$b, f$id), error = identity)
  stopifnot(inherits(failure, "wb_graph_error"),
    identical(failure$code, "GRAPH_CONTENT_IDENTITY_MISMATCH"),
    spy$state$actual == 5L, is.null(f$b$con@ref$wb_graph_retained_observation))
  TRUE
}

test_engine_retained_graph_external_schema_and_unsafe_sql_contract <- function() {
  f <- .engine_retained_graph_fixture(); on.exit(wb_close_bundle(f$b), add = TRUE)
  spy <- .engine_retained_graph_spy(); on.exit(spy$close(), add = TRUE)
  wb_art_graph_info(f$b, f$id)
  path <- DBI::dbGetQuery(f$b$con, "PRAGMA database_list")$file[[1L]]
  other <- NULL
  on.exit(if (!is.null(other) && DBI::dbIsValid(other)) DBI::dbDisconnect(other), add = TRUE)
  other <- DBI::dbConnect(RSQLite::SQLite(), path)
  DBI::dbExecute(other, "UPDATE artifacts SET description='external commit' WHERE artifact_id=?",
    params = list(f$id))
  wb_art_graph_info(f$b, f$id)
  stopifnot(spy$state$actual == 2L)
  cookie <- DBI::dbGetQuery(f$b$con, "PRAGMA main.schema_version")[[1L]]
  DBI::dbExecute(f$b$con, "ALTER TABLE artifact_graph_meta ADD COLUMN observation_extra TEXT")
  DBI::dbExecute(f$b$con, paste0("PRAGMA main.schema_version=", cookie))
  wb_art_graph_info(f$b, f$id)
  stopifnot(spy$state$actual == 3L)
  # Changing temp_store with live TEMP objects would delete caller state and
  # must remain rejected by the existing generic verifier. Preselect FILE.
  DBI::dbExecute(f$b$con, "PRAGMA temp_store=FILE")
  DBI::dbExecute(f$b$con, "CREATE TEMP TABLE observation_temp(x INTEGER)")
  wb_art_graph_info(f$b, f$id)
  stopifnot(spy$state$actual == 4L, is.null(f$b$con@ref$wb_graph_retained_observation),
    nrow(DBI::dbGetQuery(f$b$con,
      "SELECT 1 FROM sqlite_temp_schema WHERE name='observation_temp'")) == 1L,
    DBI::dbGetQuery(f$b$con, "PRAGMA temp_store")[[1L]] == 1L)
  DBI::dbExecute(f$b$con, "DROP TABLE observation_temp")
  wb_art_graph_info(f$b, f$id)
  DBI::dbExecute(f$b$con, "ATTACH ':memory:' AS observation_other")
  wb_art_graph_info(f$b, f$id)
  stopifnot(spy$state$actual == 6L, is.null(f$b$con@ref$wb_graph_retained_observation))
  DBI::dbExecute(f$b$con, "DETACH observation_other")
  wb_art_graph_info(f$b, f$id)
  stopifnot(spy$state$actual == 7L)
  TRUE
}

test_engine_retained_graph_private_budgets_and_compact_cap_contract <- function() {
  f <- .engine_retained_graph_fixture(); on.exit(wb_close_bundle(f$b), add = TRUE)
  spy <- .engine_retained_graph_spy(); on.exit(spy$close(), add = TRUE)
  wb_art_graph_info(f$b, f$id)
  opaque <- structure(list(), opaque = new.env(parent = emptyenv()))
  wb_art_graph_info(f$b, f$id, opaque)
  stopifnot(spy$state$actual == 2L, is.null(f$b$con@ref$wb_graph_retained_observation))
  owned <- structure(list(), wb_graph_session_copy_bytes = 1)
  wb_art_graph_info(f$b, f$id, owned); wb_art_graph_info(f$b, f$id, owned)
  stopifnot(spy$state$actual == 3L)
  wb_art_graph_info(f$b, f$id)
  stopifnot(spy$state$actual == 4L)
  scworkbench:::.wb_session_source_forget(f$b$con)
  actual <- scworkbench:::.wb_graph_sql_identities
  restore <- .engine_retained_graph_replace(".wb_graph_sql_identities", function(...) {
    value <- actual(...); value$observation_test_padding <- strrep("x", 65536L); value
  })
  on.exit(restore(), add = TRUE, after = FALSE)
  wb_art_graph_info(f$b, f$id); wb_art_graph_info(f$b, f$id)
  stopifnot(spy$state$actual == 6L, is.null(f$b$con@ref$wb_graph_retained_observation))
  TRUE
}

test_engine_retained_graph_post_claim_epoch_full_retry_contract <- function() {
  f <- .engine_retained_graph_fixture(); on.exit(wb_close_bundle(f$b), add = TRUE)
  spy <- .engine_retained_graph_spy(); on.exit(spy$close(), add = TRUE)
  expected <- wb_art_graph_info(f$b, f$id)$content_identity
  certificate <- scworkbench:::.wb_graph_certificate_scan
  fired <- FALSE
  restore <- .engine_retained_graph_replace(".wb_graph_certificate_scan", function(...) {
    value <- certificate(...)
    if (!fired) {
      fired <<- TRUE
      DBI::dbExecute(f$b$con, "UPDATE artifacts SET description='between comparisons' WHERE artifact_id=?",
        params = list(f$id))
    }
    value
  })
  on.exit(restore(), add = TRUE, after = FALSE)
  got <- wb_art_graph_info(f$b, f$id)
  stopifnot(fired, identical(got$content_identity, expected), spy$state$actual == 2L,
    spy$state$certificates == 3L, !is.null(f$b$con@ref$wb_graph_retained_observation))
  TRUE
}

test_engine_retained_graph_reopen_deep_fresh_and_purity_contract <- function() {
  f <- .engine_retained_graph_fixture(); b <- f$b
  on.exit(if (DBI::dbIsValid(b$con)) wb_close_bundle(b), add = TRUE)
  spy <- .engine_retained_graph_spy(); on.exit(spy$close(), add = TRUE)
  expected <- wb_art_graph_info(b, f$id)$content_identity
  scworkbench:::.wb_session_source_forget(b$con)
  stopifnot(is.null(b$con@ref$wb_graph_retained_observation))
  wb_art_graph_info(b, f$id)
  stopifnot(spy$state$actual == 2L, wb_finalize_recipient_bundle(b)$ready)
  wb_close_bundle(b)
  b <- wb_open_bundle(f$root, read_only = TRUE)
  stopifnot(is.null(b$con@ref$wb_graph_retained_observation))
  fingerprint <- function() {
    paths <- sort(list.files(f$root, recursive = TRUE, full.names = TRUE, all.files = TRUE,
      no.. = TRUE)); paths <- paths[!file.info(paths)$isdir]
    setNames(vapply(paths, function(path) digest::digest(file = path, algo = "sha256"),
      character(1)), substring(paths, nchar(f$root) + 2L))
  }
  before <- fingerprint(); count <- spy$state$actual
  primitive <- wb_art_load(b, f$id)
  stopifnot(identical(wb_art_graph_info(b, f$id)$content_identity, expected),
    spy$state$actual == count + 1L, !any(c("key", "connection", "path") %in% names(primitive)))
  count <- spy$state$actual
  report <- wb_bundle_validation_report(f$root, level = "recipient")
  stopifnot(isTRUE(report$ok), spy$state$actual > count,
    identical(before, fingerprint()))
  TRUE
}
