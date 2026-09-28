test_durable_session_source_payload_corruption_contract <- function() {
  contract_test_activate_phase5_conformance_pack()
  on.exit(contract_test_deactivate_phase5_conformance_pack(), add = TRUE)
  bundle_dir <- tempfile("scwb_durable_corruption_bundle_")
  workspace_root <- tempfile("scwb_durable_corruption_sessions_")
  b <- wb_init_bundle(bundle_dir, overwrite = TRUE)
  old_fault <- getOption("scworkbench.durable_session_fault_hook")
  on.exit({
    options(scworkbench.durable_session_fault_hook = old_fault)
    try(wb_close_bundle(b), silent = TRUE)
    unlink(bundle_dir, recursive = TRUE, force = TRUE)
    unlink(workspace_root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- paste0("cell_", seq_len(12L))
  wb_define_cells(b, cells, metadata = data.frame(
    cell_id = cells, group = rep(c("a", "b"), each = 6L), stringsAsFactors = FALSE
  ))
  coords <- matrix(seq_len(48L) / 10, nrow = 12L,
                   dimnames = list(cells, paste0("PC", seq_len(4L))))
  wb_add_space(b, "source.pca", coords, source = "contract")

  run_vector <- function(session, name) wb_session_run_op(session, b, "metadata_cell_vector", inputs = list(
    source_column = "group", vector_name = name, value_type = "categorical",
    missing_policy = "error", overwrite = TRUE, cell_set = "all", min_cells = 1L
  ))
  run_model <- function(session) wb_session_run_op(session, b,
    "scwbv3phase5::fit_sibling_model", inputs = list(
      source = "source.pca", cell_set = "all", min_cells = 1L,
      dims = 1:4
  ))

  # A clean close/manifest rewrite changes publication metadata only, not the
  # authoritative scientific-state fingerprint.
  clean <- wb_session_create(b, workspace_root, "manifest_refresh")
  clean_workspace <- clean$durable$workspace
  clean_fingerprint <- clean$durable$source_identity$scientific_state_fingerprint
  wb_close_bundle(b)
  b <- wb_open_bundle(bundle_dir)
  clean_resumed <- wb_session_resume(b, clean_workspace)
  stopifnot(identical(clean_fingerprint,
                      clean_resumed$durable$source_identity$scientific_state_fingerprint))
  wb_session_discard(clean_resumed)

  # Corrupt a real staged file tree. Both resume and promotion reject it, while
  # the source registry fingerprint remains byte-for-byte unchanged.
  file_case <- run_model(wb_session_create(b, workspace_root, "payload_corrupt"))
  source_before <- .wb_session_source_identity(b)$scientific_state_fingerprint
  model_path <- as.character(file_case$run$outputs$model$model_path)
  stopifnot(length(model_path) == 1L, nzchar(model_path))
  if (!.wb_path_is_absolute(model_path)) model_path <- file.path(file_case$session$staging_bundle$dir, model_path)
  stopifnot(file.exists(model_path) || dir.exists(model_path))
  victim <- if (dir.exists(model_path)) list.files(model_path, recursive = TRUE, full.names = TRUE)[1] else model_path
  writeBin(as.raw(c(0xde, 0xad, 0xbe, 0xef)), victim)
  bad_resume <- try(wb_session_resume(b, file_case$session$durable$workspace), silent = TRUE)
  bad_promote <- try(wb_session_promote_current(b, file_case$session, outputs = "model"), silent = TRUE)
  if (!inherits(bad_resume, "try-error")) stop("File-backed staged model corruption resumed successfully.", call. = FALSE)
  stopifnot(inherits(bad_resume, "try-error"), inherits(bad_promote, "try-error"),
            grepl("DURABLE_SESSION_PAYLOAD_CORRUPT", as.character(bad_resume), fixed = TRUE),
            grepl("DURABLE_SESSION_PAYLOAD_CORRUPT", as.character(bad_promote), fixed = TRUE),
            identical(source_before, .wb_session_source_identity(b)$scientific_state_fingerprint))
  wb_session_discard(file_case$session)

  # Bundle publication succeeds, then the injected crash prevents the terminal
  # session receipt. The old active checkpoint now disagrees with its source;
  # neither resume nor retry can repeat the already committed promotion.
  artifacts_before <- nrow(wb_art_list(b))
  crash_case <- run_vector(wb_session_create(b, workspace_root, "promotion_crash"), "crash_vector")
  options(scworkbench.durable_session_fault_hook = function(where) {
    if (identical(where, "after_bundle_promotion_before_session_receipt")) stop("injected promotion receipt crash")
  })
  crashed <- try(wb_session_promote_current(b, crash_case$session, outputs = "vector"), silent = TRUE)
  options(scworkbench.durable_session_fault_hook = old_fault)
  artifacts_after <- nrow(wb_art_list(b))
  failed_resume <- try(wb_session_resume(b, crash_case$session$durable$workspace), silent = TRUE)
  failed_retry <- try(wb_session_promote_current(b, crash_case$session, outputs = "vector"), silent = TRUE)
  stopifnot(inherits(crashed, "try-error"), artifacts_after == artifacts_before + 1L,
            inherits(failed_resume, "try-error"), inherits(failed_retry, "try-error"),
            grepl("DURABLE_SESSION_SOURCE_CHANGED", as.character(failed_resume), fixed = TRUE),
            grepl("DURABLE_SESSION_SOURCE_CHANGED", as.character(failed_retry), fixed = TRUE),
            nrow(wb_art_list(b)) == artifacts_after)
  wb_session_discard(crash_case$session)

  # Keep a second SQLite connection open with autocheckpoint disabled so the
  # committed mutation remains WAL-backed while resume computes source identity.
  wal_case <- wb_session_create(b, workspace_root, "wal_source_change")
  wal_con <- DBI::dbConnect(RSQLite::SQLite(), file.path(bundle_dir, "db", "app.sqlite"))
  on.exit(if (inherits(wal_con, "SQLiteConnection") && DBI::dbIsValid(wal_con)) try(DBI::dbDisconnect(wal_con), silent = TRUE), add = TRUE)
  DBI::dbExecute(wal_con, "PRAGMA journal_mode=WAL;")
  DBI::dbExecute(wal_con, "PRAGMA wal_autocheckpoint=0;")
  DBI::dbBegin(wal_con)
  DBI::dbExecute(wal_con, "UPDATE cells SET dataset_id = ? WHERE cell_id = ?;",
                 params = list("wal_mutated_dataset", cells[1]))
  DBI::dbCommit(wal_con)
  wal_path <- paste0(file.path(bundle_dir, "db", "app.sqlite"), "-wal")
  stopifnot(file.exists(wal_path), file.info(wal_path)$size > 0)
  wal_rejected <- try(wb_session_resume(b, wal_case$durable$workspace), silent = TRUE)
  stopifnot(inherits(wal_rejected, "try-error"),
            grepl("DURABLE_SESSION_SOURCE_CHANGED", as.character(wal_rejected), fixed = TRUE))
  DBI::dbDisconnect(wal_con)
  wal_con <- NULL
  wb_session_discard(wal_case)
  TRUE
}
