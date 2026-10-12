.session_inspection_regular_file_inventory <- function(root) {
  paths <- list.files(root, recursive = TRUE, all.files = TRUE,
                      full.names = TRUE, include.dirs = FALSE, no.. = TRUE)
  paths <- paths[file.exists(paths) & !isTRUE(file.info(paths)$isdir)]
  relative <- substring(normalizePath(paths, winslash = "/", mustWork = TRUE),
                        nchar(normalizePath(root, winslash = "/", mustWork = TRUE)) + 2L)
  hashes <- vapply(paths, .wb_prov_sha256_file, character(1L))
  stats::setNames(hashes[order(relative)], relative[order(relative)])
}

test_session_inspection_and_ingest_integrity_contract <- function() {
  bundle_dir <- tempfile("scwb_session_inspection_bundle_")
  workspace_root <- tempfile("scwb_session_inspection_workspace_")
  b <- wb_init_bundle(bundle_dir, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(bundle_dir, recursive = TRUE, force = TRUE)
    unlink(workspace_root, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- sprintf("cell_%03d", seq_len(12L))
  metadata <- data.frame(
    cell_id = cells,
    reporter_signal = seq(0, 2.75, length.out = length(cells)),
    stringsAsFactors = FALSE
  )
  wb_define_cells(
    b, cells, metadata = metadata, dataset_id = "synthetic_fixture",
    set_name = "fixture_cells", source = "session-inspection-contract"
  )

  # Canonical ingestion owns lifecycle completion. Inspection must never be
  # required to prime this state.
  lifecycle <- DBI::dbGetQuery(
    b$con,
    "SELECT entity_kind, entity_id FROM entity_lifecycle ORDER BY entity_kind, entity_id;"
  )
  stopifnot(
    any(lifecycle$entity_kind == "cell_set" & lifecycle$entity_id == "set:fixture_cells"),
    any(lifecycle$entity_kind == "metadata_field")
  )

  session <- wb_session_create(
    b, workspace_root = workspace_root, session_id = "observational-inspection"
  )
  rr <- wb_session_run_op(session, b, "metadata_cell_vector", inputs = list(
    source_column = "reporter_signal", cell_ids = cells, min_cells = 10L,
    value_type = "continuous", missing_policy = "error",
    vector_name = "inspection_signal", overwrite = FALSE
  ))
  session <- rr$session

  state_before <- .wb_manifest_registry_snapshot(b$con)
  lifecycle_before <- DBI::dbGetQuery(
    b$con, "SELECT * FROM entity_lifecycle ORDER BY entity_kind, entity_id;"
  )
  files_before <- .session_inspection_regular_file_inventory(bundle_dir)

  for (i in seq_len(2L)) {
    invisible(wb_session_dag(session, bundle = b, include_artifacts = TRUE,
                             include_active = TRUE))
    invisible(wb_session_dag_run_details(session, rr$run$run_id, bundle = b))
    invisible(wb_entity_lifecycle(b, include_history = TRUE))
    invisible(wb_art_list(b, include_history = TRUE))
  }
  stopifnot(
    identical(lifecycle_before, DBI::dbGetQuery(
      b$con, "SELECT * FROM entity_lifecycle ORDER BY entity_kind, entity_id;"
    )),
    identical(state_before$fingerprint, .wb_manifest_registry_snapshot(b$con)$fingerprint),
    identical(files_before, .session_inspection_regular_file_inventory(bundle_dir))
  )

  wb_finalize_recipient_bundle(b)
  wb_close_bundle(b)
  b <- wb_open_bundle(bundle_dir, read_only = TRUE, validate = TRUE)
  read_only_state <- .wb_manifest_registry_snapshot(b$con)
  read_only_lifecycle <- DBI::dbGetQuery(
    b$con, "SELECT * FROM entity_lifecycle ORDER BY entity_kind, entity_id;"
  )
  read_only_files <- .session_inspection_regular_file_inventory(bundle_dir)
  for (i in seq_len(2L)) {
    invisible(wb_session_dag(session, bundle = b, include_artifacts = TRUE,
                             include_active = TRUE))
    invisible(wb_session_dag_run_details(session, rr$run$run_id, bundle = b))
    invisible(wb_entity_lifecycle(b, include_history = TRUE))
    invisible(wb_art_list(b, include_history = TRUE))
  }
  stopifnot(
    identical(read_only_lifecycle, DBI::dbGetQuery(
      b$con, "SELECT * FROM entity_lifecycle ORDER BY entity_kind, entity_id;"
    )),
    identical(read_only_state$fingerprint, .wb_manifest_registry_snapshot(b$con)$fingerprint),
    identical(read_only_files, .session_inspection_regular_file_inventory(bundle_dir))
  )
  wb_close_bundle(b)
  b <- wb_open_bundle(bundle_dir, validate = TRUE)

  promoted <- wb_session_promote_current(
    b, session, outputs = list(wb_ref_run(rr$run$run_id, "vector")),
    created_by = "session-inspection-contract"
  )
  stopifnot(
    identical(as.character(promoted$promoted$status[[1L]]), "ok"),
    nrow(wb_art_list(b)) == 1L
  )

  # A real committed source mutation remains a typed incompatibility.
  changed <- wb_session_create(b, workspace_root, session_id = "genuine-source-change")
  DBI::dbExecute(
    b$con,
    "UPDATE cell_set_membership SET description = ? WHERE cell_set = ?;",
    params = list("genuine committed source mutation", "set:fixture_cells")
  )
  changed_error <- tryCatch(
    wb_session_resume(b, changed$durable$workspace),
    error = identity
  )
  stopifnot(
    inherits(changed_error, "scworkbench_durable_session_source_changed"),
    inherits(changed_error, "scworkbench_durable_session_error"),
    inherits(changed_error, "scworkbench_error"),
    identical(changed_error$code, "DURABLE_SESSION_SOURCE_CHANGED"),
    "scientific_state_fingerprint" %in% changed_error$changed_fields
  )
  wb_session_discard(changed)
  wb_session_discard(promoted$session)
  TRUE
}

test_low_level_ingest_dataset_integrity_contract <- function() {
  bundle_dir <- tempfile("scwb_low_level_ingest_bundle_")
  rollback_dir <- tempfile("scwb_low_level_ingest_rollback_")
  b <- wb_init_bundle(bundle_dir, overwrite = TRUE)
  rollback <- wb_init_bundle(rollback_dir, overwrite = TRUE)
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    try(wb_close_bundle(rollback), silent = TRUE)
    unlink(bundle_dir, recursive = TRUE, force = TRUE)
    unlink(rollback_dir, recursive = TRUE, force = TRUE)
  }, add = TRUE)

  cells <- c("cell_1", "cell_2", "cell_3")
  stopifnot(nrow(DBI::dbGetQuery(b$con, "SELECT * FROM datasets;")) == 0L)
  wb_ingest_cells(b, set_name = "fixture_cells", cell_ids = cells,
                  source = "low-level-ingest-contract")
  dataset <- DBI::dbGetQuery(
    b$con, "SELECT dataset_id, n_cells FROM datasets WHERE dataset_id = ?;",
    params = list("fixture_cells")
  )
  lifecycle <- DBI::dbGetQuery(
    b$con,
    "SELECT lifecycle_state FROM entity_lifecycle WHERE entity_kind='cell_set' AND entity_id='set:fixture_cells';"
  )
  stopifnot(
    nrow(dataset) == 1L,
    identical(as.integer(dataset$n_cells[[1L]]), length(cells)),
    nrow(lifecycle) == 1L,
    identical(as.character(lifecycle$lifecycle_state[[1L]]), "current")
  )
  wb_close_bundle(b)
  stopifnot(isTRUE(wb_validate_bundle(bundle_dir)))
  b <- wb_open_bundle(bundle_dir)

  # Failure after cell/dataset writes has begun rolls the entire base ingest
  # transaction back, leaving no dangling or partial registry state.
  bad_metadata <- data.frame(
    cell_id = c("rollback_1", "rollback_1"), value = c(1, 2),
    stringsAsFactors = FALSE
  )
  failure <- tryCatch(
    wb_ingest_cells(
      rollback, set_name = "fixture_cells",
      cell_ids = c("rollback_1", "rollback_2"), metadata = bad_metadata,
      source = "low-level-ingest-contract"
    ),
    error = identity
  )
  stopifnot(
    inherits(failure, "error"),
    DBI::dbGetQuery(rollback$con, "SELECT COUNT(*) AS n FROM cells;")$n[[1L]] == 0L,
    DBI::dbGetQuery(rollback$con, "SELECT COUNT(*) AS n FROM datasets;")$n[[1L]] == 0L,
    DBI::dbGetQuery(rollback$con, "SELECT COUNT(*) AS n FROM cell_set_membership;")$n[[1L]] == 0L,
    DBI::dbGetQuery(rollback$con, "SELECT COUNT(*) AS n FROM entity_lifecycle;")$n[[1L]] == 0L
  )
  wb_close_bundle(rollback)
  stopifnot(isTRUE(wb_validate_bundle(rollback_dir)))
  rollback <- wb_open_bundle(rollback_dir)
  TRUE
}
