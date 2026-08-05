.pybench_publication_residue <- function(root) {
  paths <- list.files(root, recursive = TRUE, all.files = TRUE, no.. = TRUE, full.names = FALSE)
  manifest <- jsonlite::read_json(file.path(root, "manifest.json"), simplifyVector = TRUE)
  db_rel <- gsub("\\\\", "/", as.character(manifest$storage$sqlite$path)[1])
  sidecars <- paths[grepl("-(wal|shm|journal)$", paths)]
  unexpected_sidecars <- setdiff(sidecars, paste0(db_rel, c("-wal", "-shm", "-journal")))
  sort(c(
    paths[grepl("(^|/)\\.scworkbench-pybench-publication-", paths)],
    paths[grepl("(^|/)(preimage\\.sqlite|incoming|preimages)(/|$)", paths)],
    unexpected_sidecars
  ))
}

.pybench_publication_fixture <- function() {
  destination_dir <- tempfile("scwb_publication_destination_")
  destination <- wb_init_bundle(destination_dir, overwrite = TRUE)
  wb_define_cells(destination, c("c1", "c2"))
  DBI::dbExecute(destination$con, "UPDATE cells SET dataset_id='before' WHERE cell_id='c1';")

  dir.create(file.path(destination_dir, "artifact_models", "replaced"), recursive = TRUE)
  writeLines("old model", file.path(destination_dir, "artifact_models", "replaced", "model.txt"))
  dir.create(file.path(destination_dir, "artifact_models", "deleted"), recursive = TRUE)
  writeBin(charToRaw("old deleted payload"), file.path(destination_dir, "artifact_models", "deleted", "stale.bin"))

  pre_db <- .wb_pybench_db_snapshot(destination$con)
  pre_payload <- .wb_pybench_payload_snapshot(destination_dir)
  source <- .wb_pybench_clone_bundle(destination)
  DBI::dbExecute(source$bundle$con, "UPDATE cells SET dataset_id='after' WHERE cell_id='c1';")
  writeLines("new model", file.path(source$root, "artifact_models", "replaced", "model.txt"))
  unlink(file.path(source$root, "artifact_models", "deleted"), recursive = TRUE, force = TRUE)
  dir.create(file.path(source$root, "artifact_models", "nested", "model", "tree"), recursive = TRUE)
  writeBin(charToRaw("nested weights"), file.path(source$root, "artifact_models", "nested", "model", "tree", "weights.bin"))
  writeBin(charToRaw("created payload"), file.path(source$root, "artifact_models", "created.bin"))
  post_db <- .wb_pybench_db_snapshot(source$bundle$con)
  post_payload <- .wb_pybench_payload_snapshot(source$root)

  list(
    destination = destination, destination_dir = destination_dir,
    source = source, pre_db = pre_db, pre_payload = pre_payload,
    post_db = post_db, post_payload = post_payload
  )
}

.pybench_close_publication_fixture <- function(x) {
  try(wb_close_bundle(x$source$bundle), silent = TRUE)
  try(wb_close_bundle(x$destination), silent = TRUE)
  unlink(x$source$root, recursive = TRUE, force = TRUE)
  unlink(x$destination_dir, recursive = TRUE, force = TRUE)
  invisible(TRUE)
}

.pybench_atomicity_atac_fixture <- function() {
  if (!requireNamespace("BPCells", quietly = TRUE) || !requireNamespace("Matrix", quietly = TRUE)) return(NULL)
  bundle_dir <- tempfile("scwb_publication_peakvi_bundle_")
  workspace <- tempfile("scwb_publication_peakvi_sessions_")
  bundle <- wb_init_bundle(bundle_dir, overwrite = TRUE)
  cells <- paste0("cell_", seq_len(12L))
  features <- paste0("peak_", seq_len(5L))
  wb_define_cells(bundle, cells, metadata = data.frame(cell_id = cells, batch = rep(c("a", "b"), each = 6L)))
  counts <- Matrix::Matrix(
    matrix(seq_len(60L) %% 4L, nrow = 5L, dimnames = list(features, cells)),
    sparse = TRUE
  )
  wb_attach_matrix(bundle, "ATAC_counts", counts, layer = "counts", feature_type = "peak")
  list(bundle = bundle, bundle_dir = bundle_dir, workspace = workspace)
}

test_pybench_transition_publication_atomicity_contract <- function() {
  old_hook <- getOption("scworkbench.pybench_transition_fault_hook", NULL)
  old_mock <- Sys.getenv("PYBENCH_TEST_MOCK_TRAINING", unset = NA_character_)
  on.exit({
    options(scworkbench.pybench_transition_fault_hook = old_hook)
    if (is.na(old_mock)) Sys.unsetenv("PYBENCH_TEST_MOCK_TRAINING") else Sys.setenv(PYBENCH_TEST_MOCK_TRAINING = old_mock)
  }, add = TRUE)

  boundaries <- c(
    "after_payload_preimages_before_visible_change",
    "after_first_payload_published",
    "after_payload_deletion",
    "after_all_payloads_before_sqlite",
    "after_sqlite_update_before_cleanup",
    "during_nested_model_directory_publication"
  )
  for (boundary in boundaries) {
    x <- .pybench_publication_fixture()
    options(scworkbench.pybench_transition_fault_hook = function(where) {
      if (identical(where, boundary)) stop(paste0("injected publication fault: ", boundary))
    })
    error <- tryCatch({
      .wb_pybench_publish_transition(
        x$source$bundle, x$destination, x$pre_payload, x$post_payload
      )
      NULL
    }, error = identity)
    options(scworkbench.pybench_transition_fault_hook = NULL)
    stopifnot(
      inherits(error, "scworkbench_pybench_publication_error"),
      inherits(error$parent, "error"),
      grepl(boundary, conditionMessage(error$parent), fixed = TRUE),
      identical(x$pre_db, .wb_pybench_db_snapshot(x$destination$con)),
      identical(x$pre_payload, .wb_pybench_payload_snapshot(x$destination_dir)),
      !length(.pybench_publication_residue(x$destination_dir))
    )

    # The identical audited transition remains retryable and is published once.
    .wb_pybench_publish_transition(
      x$source$bundle, x$destination, x$pre_payload, x$post_payload
    )
    stopifnot(
      identical(x$post_db, .wb_pybench_db_snapshot(x$destination$con)),
      identical(x$post_payload, .wb_pybench_payload_snapshot(x$destination_dir)),
      identical(DBI::dbGetQuery(
        x$destination$con, "SELECT dataset_id FROM cells WHERE cell_id='c1';"
      )$dataset_id, "after"),
      !length(.pybench_publication_residue(x$destination_dir))
    )
    .pybench_close_publication_fixture(x)
  }

  python <- .wb_pybench_default_python()
  if (!nzchar(python) || !file.exists(python)) {
    return(contract_test_skip("PyBench interpreter unavailable for registered-operation publication test"))
  }
  atac <- .pybench_atomicity_atac_fixture()
  if (is.null(atac)) return(contract_test_skip("BPCells/Matrix unavailable for registered-operation publication test"))
  b <- atac$bundle
  on.exit({
    try(wb_close_bundle(b), silent = TRUE)
    unlink(atac$bundle_dir, recursive = TRUE, force = TRUE)
    unlink(atac$workspace, recursive = TRUE, force = TRUE)
  }, add = TRUE)
  Sys.setenv(PYBENCH_TEST_MOCK_TRAINING = "1")

  session <- wb_session_create(b, atac$workspace, session_id = "publication_atomicity_peakvi")
  workspace <- session$durable$workspace
  generation_before <- session$durable$checkpoint_generation
  pointer_before <- readBin(.wb_session_pointer_file(workspace), "raw", n = file.info(.wb_session_pointer_file(workspace))$size)
  options(scworkbench.pybench_transition_fault_hook = function(where) {
    if (identical(where, "after_sqlite_update_before_cleanup")) stop("injected registered PeakVI publication fault")
  })
  failed <- try(wb_session_run_op(
    session, b, "peakvi_fit",
    inputs = list(
      matrix = "ATAC_counts", n_latent = 3L, max_epochs = 1L,
      space_id_out = "peakvi.atomic", cell_set = "all", min_cells = 2L
    )
  ), silent = TRUE)
  options(scworkbench.pybench_transition_fault_hook = NULL)
  pointer_after <- readBin(.wb_session_pointer_file(workspace), "raw", n = file.info(.wb_session_pointer_file(workspace))$size)
  resumed <- wb_session_resume(b, workspace)
  stage_roots <- list.files(.wb_session_stage_root(), full.names = TRUE, all.files = TRUE, no.. = TRUE)
  publication_residue <- unlist(lapply(stage_roots[dir.exists(stage_roots)], function(path) {
    list.files(path, recursive = TRUE, all.files = TRUE, no.. = TRUE, pattern = "^\\.scworkbench-pybench-publication-", full.names = TRUE)
  }), use.names = FALSE)
  stopifnot(
    inherits(failed, "try-error"),
    grepl("PYBENCH_PUBLICATION_FAILED", as.character(failed), fixed = TRUE),
    identical(pointer_before, pointer_after),
    identical(resumed$durable$checkpoint_generation, generation_before),
    length(resumed$runs) == 0L,
    !length(publication_residue)
  )

  retried <- wb_session_run_op(
    resumed, b, "peakvi_fit",
    inputs = list(
      matrix = "ATAC_counts", n_latent = 3L, max_epochs = 1L,
      space_id_out = "peakvi.atomic", cell_set = "all", min_cells = 2L
    )
  )
  stopifnot(
    !identical(retried$session$durable$checkpoint_generation, generation_before),
    identical(retried$result$params$pybench_runtime$protocol_version, "pybench-op-v2"),
    identical(length(retried$session$runs), 1L)
  )
  workspace <- retried$session$durable$workspace
  wb_close_bundle(b)
  b <- wb_open_bundle(atac$bundle_dir)
  promoted <- wb_session_promote_current(
    b, wb_session_resume(b, workspace), outputs = "model", created_by = "publication-atomicity-contract"
  )
  model_id <- as.character(promoted$promoted$artifact_id[promoted$promoted$output == "model"])[1]
  wb_close_bundle(b)
  b <- wb_open_bundle(atac$bundle_dir)
  terminal <- wb_session_open(workspace)
  model <- wb_art_load(b, model_id, expected_kind = "model_ref")
  persisted_runs <- DBI::dbGetQuery(
    b$con, "SELECT run_id FROM prov_runs WHERE run_id = ?;", params = list(retried$run$run_id)
  )
  stopifnot(
    identical(terminal$durable$state, "promoted"),
    identical(model$engine, "peakvi"),
    "peakvi.atomic" %in% wb_spaces(b)$space_id,
    nrow(persisted_runs) == 1L,
    !length(.pybench_publication_residue(terminal$staging_dir))
  )
  TRUE
}
