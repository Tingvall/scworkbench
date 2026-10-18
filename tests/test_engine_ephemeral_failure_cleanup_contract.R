test_engine_ephemeral_failure_cleanup_contract <- function() {
  root <- tempfile("scwb_ephemeral_cleanup_")
  b <- wb_init_bundle(root)
  on.exit({if (DBI::dbIsValid(b$con)) wb_close_bundle(b)
    unlink(root, recursive = TRUE, force = TRUE)}, add = TRUE)
  cells <- c("c2", "c1", "c3")
  wb_define_cells(b, cells, metadata = data.frame(cell_id = cells,
    group = c("A", "B", "A")))
  source_manifest <- readBin(file.path(root, "manifest.json"), "raw",
    file.info(file.path(root, "manifest.json"))$size)
  state <- scworkbench:::.wb_manifest_registry_snapshot(b$con)
  spy <- new.env(parent = emptyenv())
  old <- options(scworkbench.ephemeral_cleanup_spy = spy)
  on.exit(options(old), add = TRUE)
  trace(".wb_session_stage_bundle", where = asNamespace("scworkbench"),
    print = FALSE, exit = quote({
      s <- getOption("scworkbench.ephemeral_cleanup_spy")
      result <- returnValue()
      s$con <- result$bundle$con
      s$dir <- result$session$staging_dir
    }))
  on.exit(untrace(".wb_session_stage_bundle", where = asNamespace("scworkbench")),
    add = TRUE)
  inputs <- list(source_column = "missing", vector_name = "group",
    value_type = "categorical", missing_policy = "error", min_cells = 1L,
    cell_set = "all", overwrite = FALSE)
  initial <- wb_session_new()
  failed <- tryCatch(wb_session_run_op(initial, b, "metadata_cell_vector",
    inputs = inputs), error = identity)
  stopifnot(inherits(failed, "error"), !DBI::dbIsValid(spy$con),
    !dir.exists(spy$dir), length(initial$runs) == 0L,
    identical(state, scworkbench:::.wb_manifest_registry_snapshot(b$con)),
    identical(source_manifest, readBin(file.path(root, "manifest.json"), "raw",
      file.info(file.path(root, "manifest.json"))$size)))
  inputs$source_column <- "group"
  success <- wb_session_run_op(initial, b, "metadata_cell_vector", inputs = inputs)
  on.exit(if (DBI::dbIsValid(success$session$staging_bundle$con))
    wb_session_discard(success$session), add = TRUE)
  existing_con <- success$session$staging_bundle$con
  existing_dir <- success$session$staging_dir
  inputs$source_column <- "missing"
  failed <- tryCatch(wb_session_run_op(success$session, b,
    "metadata_cell_vector", inputs = inputs), error = identity)
  stopifnot(inherits(failed, "error"), DBI::dbIsValid(existing_con),
    dir.exists(existing_dir), length(success$session$runs) == 1L)
  wb_session_discard(success$session)
  stopifnot(!DBI::dbIsValid(existing_con), !dir.exists(existing_dir))
  TRUE
}
