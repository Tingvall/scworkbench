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

  TRUE
}
