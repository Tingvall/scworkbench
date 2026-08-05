test_durable_resumable_sessions_contract <- function() {
  tmp <- tempfile("scwb_durable_session_bundle_")
  root <- tempfile("scwb_durable_session_workspace_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(tmp, recursive = TRUE, force = TRUE); unlink(root, recursive = TRUE, force = TRUE) }, add = TRUE)
  cells <- paste0("c", 1:3)
  wb_define_cells(b, cells)
  wb_attach_metadata(b, data.frame(cell_id = cells, group = c("a", "b", "a"), stringsAsFactors = FALSE))

  s <- wb_session_create(b, root, session_id = "resume_case")
  stopifnot(nrow(wb_session_list(root)) == 1L, dir.exists(s$staging_dir))
  rr <- wb_session_run_op(s, b, "metadata_cell_vector", inputs = list(
    source_column = "group", vector_name = "durable_group", value_type = "categorical",
    missing_policy = "error", overwrite = TRUE, cell_set = "all", min_cells = 1L
  ))
  # A process replacement has no in-memory connection or run graph; resume
  # reconstructs both from the atomic checkpoint and private stage.
  wb_close_bundle(b); b <- wb_open_bundle(tmp)
  resumed <- wb_session_resume(b, file.path(root, "resume_case"))
  stopifnot(identical(names(resumed$runs), rr$run$run_id), identical(resumed$head_run_id, rr$run$run_id))
  promoted <- wb_session_promote_current(b, resumed, outputs = "vector", created_by = "durable-session-test")
  stopifnot(identical(as.character(promoted$promoted$status[1]), "ok"))

  # A source mutation after a checkpoint is an incompatibility, not a new
  # completed provenance branch.
  changed <- wb_session_create(b, root, session_id = "changed_source")
  other <- wb_session_run_op(wb_session_new(), b, "metadata_cell_vector", inputs = list(
    source_column = "group", vector_name = "source_changed_group", value_type = "categorical",
    missing_policy = "error", overwrite = TRUE, cell_set = "all", min_cells = 1L
  ))
  wb_session_promote_current(b, other$session, outputs = "vector", created_by = "durable-session-test")
  bad <- try(wb_session_resume(b, changed$durable$workspace), silent = TRUE)
  stopifnot(inherits(bad, "try-error"), grepl("DURABLE_SESSION_SOURCE_CHANGED", as.character(bad), fixed = TRUE))
  wb_session_discard(resumed)
  wb_session_discard(changed)
  unsafe <- try(wb_session_create(b, root, session_id = "../escaped_session"), silent = TRUE)
  absolute <- try(wb_session_create(b, root, session_id = "/escaped_session"), silent = TRUE)
  stopifnot(inherits(unsafe, "try-error"), inherits(absolute, "try-error"),
            grepl("DURABLE_SESSION_UNSAFE_ID", as.character(unsafe), fixed = TRUE))
  finalized <- wb_session_create(b, root, session_id = "finalized_case")
  finalized <- wb_session_finalize(finalized)
  blocked <- try(wb_session_resume(b, finalized$durable$workspace), silent = TRUE)
  stopifnot(inherits(blocked, "try-error"), grepl("DURABLE_SESSION_FINALIZED", as.character(blocked), fixed = TRUE))
  wb_session_discard(finalized)
  owned <- wb_session_create(b, root, session_id = "ownership_case")
  impostor <- owned; impostor$durable$ownership_token <- "not-the-owner"
  refused <- try(wb_session_discard(impostor), silent = TRUE)
  stopifnot(inherits(refused, "try-error"), grepl("DURABLE_SESSION_OWNERSHIP", as.character(refused), fixed = TRUE), dir.exists(owned$durable$workspace))
  wb_session_discard(owned)
  TRUE
}
