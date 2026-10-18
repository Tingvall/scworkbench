.engine_recipient_table_fixture <- function(meta = list(label = "ordinary")) {
  root <- tempfile("recipient_table_observation_")
  b <- wb_init_bundle(root)
  closed <- FALSE
  on.exit(if (!closed) wb_close_bundle(b), add = TRUE)
  value <- wb_prim_feature_table(data.frame(feature_id = c("f_2", "f_10", "f_1"),
    score = c(.2, NA_real_, .8)), table_type = "generic", meta = meta)
  run <- wb_new_run("metadata_cell_vector", outputs = list(vector = value),
    notes = "Synthetic table storage fixture; no scientific method execution.")
  promoted <- wb_promote_analysis(b, setNames(list(run), run$run_id),
    head_run_id = run$run_id, outputs = "vector")
  id <- promoted$promoted$artifact_id[[1L]]
  expected <- scworkbench:::.wb_prov_stored_table_content_sha256(b$con, id)
  db <- DBI::dbGetQuery(b$con, "PRAGMA database_list")$file[[1L]]
  stopifnot(wb_finalize_recipient_bundle(b)$ready)
  wb_close_bundle(b); closed <- TRUE
  list(root = root, db = db, id = id, expected = expected)
}

.engine_recipient_table_replace <- function(name, replacement) {
  ns <- asNamespace("scworkbench"); original <- get(name, ns, inherits = FALSE)
  unlockBinding(name, ns); assign(name, replacement, ns); lockBinding(name, ns)
  function() {
    unlockBinding(name, ns); assign(name, original, ns); lockBinding(name, ns)
  }
}

.engine_recipient_table_fingerprint <- function(root) {
  paths <- sort(list.files(root, recursive = TRUE, all.files = TRUE,
    full.names = TRUE, no.. = TRUE)); paths <- paths[!file.info(paths)$isdir]
  setNames(vapply(paths, function(path) digest::digest(file = path, algo = "sha256"),
    character(1)), substring(paths, nchar(root) + 2L))
}

test_engine_recipient_table_actual_once_and_report_fresh_contract <- function() {
  f <- .engine_recipient_table_fixture(); count <- 0L
  original <- scworkbench:::.wb_prov_stored_table_content_sha256
  restore <- .engine_recipient_table_replace(".wb_prov_stored_table_content_sha256",
    function(...) { count <<- count + 1L; original(...) })
  on.exit(restore(), add = TRUE, after = FALSE)
  before <- .engine_recipient_table_fingerprint(f$root)
  saw_ledger <- FALSE
  inspect <- function(event) {
    for (frame in sys.frames()) if (exists("table_observations", frame, inherits = FALSE)) {
      ledger <- get("table_observations", frame, inherits = FALSE)
      stopifnot(as.numeric(object.size(ledger)) <= 65536)
      if (length(ledger)) {
        saw_ledger <<- TRUE
        for (entry in ledger) stopifnot(identical(names(entry$value),
          c("content_sha256", "content_identity_scheme")),
          identical(entry$value$content_sha256, f$expected))
      }
    }
  }
  first <- wb_bundle_validation_report(f$root, level = "recipient", progress = inspect)
  stopifnot(isTRUE(first$ok), count == 1L,
    saw_ledger,
    identical(before, .engine_recipient_table_fingerprint(f$root)))
  second <- wb_bundle_validation_report(f$root, level = "recipient")
  stopifnot(isTRUE(second$ok), count == 2L,
    identical(first$diagnostics, second$diagnostics),
    identical(before, .engine_recipient_table_fingerprint(f$root)))
  count <- 0L
  content <- wb_bundle_validation_report(f$root, level = "content")
  stopifnot(isTRUE(content$ok), count >= 3L)
  TRUE
}

test_engine_recipient_table_all_independent_claims_contract <- function() {
  f <- .engine_recipient_table_fixture()
  con <- DBI::dbConnect(RSQLite::SQLite(), f$db)
  on.exit(if (DBI::dbIsValid(con)) DBI::dbDisconnect(con), add = TRUE)
  outputs <- DBI::dbGetQuery(con, "SELECT * FROM prov_run_outputs WHERE artifact_id=?",
    params = list(f$id))
  stopifnot(nrow(outputs) == 1L)
  outputs$output_name <- paste0(outputs$output_name, "_conflicting_claim")
  outputs$content_sha256 <- strrep("a", 64L)
  DBI::dbAppendTable(con, "prov_run_outputs", outputs)
  DBI::dbExecute(con, paste0("UPDATE prov_run_entity_bindings SET content_hash=? ",
    "WHERE entity_kind='artifact' AND entity_id=?"), params = list(strrep("b", 64L), f$id))
  DBI::dbDisconnect(con)
  count <- 0L; original <- scworkbench:::.wb_prov_stored_table_content_sha256
  restore <- .engine_recipient_table_replace(".wb_prov_stored_table_content_sha256",
    function(...) { count <<- count + 1L; original(...) })
  on.exit(restore(), add = TRUE, after = FALSE)
  before <- .engine_recipient_table_fingerprint(f$root)
  report <- wb_bundle_validation_report(f$root, level = "recipient")
  stopifnot(!isTRUE(report$ok), count == 1L,
    all(c("ARTIFACT_CONTENT_IDENTITY_MISMATCH", "ENTITY_CONTENT_IDENTITY_MISMATCH") %in%
      report$diagnostics$code),
    identical(before, .engine_recipient_table_fingerprint(f$root)))
  TRUE
}

test_engine_recipient_table_actual_mutation_and_retry_contract <- function() {
  f <- .engine_recipient_table_fixture()
  stopifnot(wb_bundle_validation_report(f$root, level = "recipient")$ok)
  con <- DBI::dbConnect(RSQLite::SQLite(), f$db)
  on.exit(if (DBI::dbIsValid(con)) DBI::dbDisconnect(con), add = TRUE)
  original <- DBI::dbGetQuery(con,
    "SELECT row_idx,row_json FROM artifact_table_rows WHERE artifact_id=? ORDER BY row_idx LIMIT 1",
    params = list(f$id))
  DBI::dbExecute(con, "UPDATE artifact_table_rows SET row_json=? WHERE artifact_id=? AND row_idx=?",
    params = list('{"feature_id":"f_2","score":99}', f$id, original$row_idx[[1L]]))
  DBI::dbDisconnect(con)
  before <- .engine_recipient_table_fingerprint(f$root)
  report <- wb_bundle_validation_report(f$root, level = "recipient")
  stopifnot(!isTRUE(report$ok), "ARTIFACT_CONTENT_IDENTITY_MISMATCH" %in% report$diagnostics$code,
    identical(before, .engine_recipient_table_fingerprint(f$root)))
  con <- DBI::dbConnect(RSQLite::SQLite(), f$db)
  DBI::dbExecute(con, "UPDATE artifact_table_rows SET row_json=? WHERE artifact_id=? AND row_idx=?",
    params = list(original$row_json[[1L]], f$id, original$row_idx[[1L]]))
  DBI::dbDisconnect(con)
  stopifnot(wb_bundle_validation_report(f$root, level = "recipient")$ok)
  # Recipient's full filesystem proof remains the final authority for a
  # concurrent raw-file change to its otherwise immutable SQL view.
  changed <- FALSE
  mutate <- function(event) {
    if (!changed && event$event == "complete" && event$check_class == "provenance") {
      changed <<- TRUE
      writer <- DBI::dbConnect(RSQLite::SQLite(), f$db)
      on.exit(DBI::dbDisconnect(writer), add = TRUE)
      DBI::dbExecute(writer, "UPDATE artifact_table_rows SET row_json=? WHERE artifact_id=? AND row_idx=?",
        params = list('{"feature_id":"f_2","score":123}', f$id, original$row_idx[[1L]]))
    }
  }
  report <- wb_bundle_validation_report(f$root, level = "recipient", progress = mutate)
  stopifnot(changed, !isTRUE(report$ok), "VALIDATION_MUTATED_BUNDLE" %in% report$diagnostics$code)
  TRUE
}

test_engine_recipient_table_oversized_header_fallback_contract <- function() {
  f <- .engine_recipient_table_fixture(list(label = strrep("x", 70000L)))
  count <- 0L; original <- scworkbench:::.wb_prov_stored_table_content_sha256
  restore <- .engine_recipient_table_replace(".wb_prov_stored_table_content_sha256",
    function(...) { count <<- count + 1L; original(...) })
  on.exit(restore(), add = TRUE, after = FALSE)
  report <- wb_bundle_validation_report(f$root, level = "recipient")
  stopifnot(isTRUE(report$ok), count >= 3L)
  TRUE
}

test_engine_recipient_table_error_retries_actual_bytes_contract <- function() {
  f <- .engine_recipient_table_fixture(); count <- 0L
  original <- scworkbench:::.wb_prov_stored_table_content_sha256
  restore <- .engine_recipient_table_replace(".wb_prov_stored_table_content_sha256",
    function(...) {
      count <<- count + 1L
      if (count == 1L) stop("RECIPIENT_TABLE_ACTUAL_HASH_FAULT")
      original(...)
    })
  on.exit(restore(), add = TRUE, after = FALSE)
  # Existing report diagnostics own error disposition; a failed observation must
  # never become cached actual authority or prevent a later fresh actual fold.
  wb_bundle_validation_report(f$root, level = "recipient")
  stopifnot(count >= 2L)
  count <- 0L; restore()
  report <- wb_bundle_validation_report(f$root, level = "recipient")
  stopifnot(isTRUE(report$ok))
  TRUE
}
