test_durable_session_subprocess_recovery_contract <- function() {
  tmp <- tempfile("scwb_durable_child_bundle_")
  root <- tempfile("scwb_durable_child_root_")
  flag <- tempfile("scwb_durable_child_ready_")
  log <- tempfile("scwb_durable_child_log_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(c(tmp, root, flag), recursive = TRUE, force = TRUE) }, add = TRUE)
  cells <- paste0("c", 1:3)
  wb_define_cells(b, cells)
  wb_attach_metadata(b, data.frame(cell_id = cells, group = c("a", "b", "a"), stringsAsFactors = FALSE))
  s <- wb_session_create(b, root, "child_kill")
  repo <- normalizePath(".", winslash = "/", mustWork = TRUE)
  code <- paste0(
    "devtools::load_all('", gsub("'", "\\\\'", repo), "',quiet=TRUE);",
    "b<-wb_open_bundle('", gsub("'", "\\\\'", tmp), "');",
    "s<-wb_session_resume(b,'", gsub("'", "\\\\'", s$durable$workspace), "');",
    "rr<-wb_session_run_op(s,b,'metadata_cell_vector',inputs=list(source_column='group',vector_name='child_completed',value_type='categorical',missing_policy='error',overwrite=TRUE,cell_set='all',min_cells=1L));",
    "writeLines('checkpointed','", gsub("'", "\\\\'", flag), "');Sys.sleep(60)"
  )
  pid <- suppressWarnings(as.integer(system(paste(shQuote(file.path(R.home("bin"), "Rscript")), "-e", shQuote(code), ">", shQuote(log), "2>&1 & echo $!"), intern = TRUE)))
  stopifnot(!is.na(pid) && pid > 1L)
  deadline <- Sys.time() + 30
  while (!file.exists(flag) && Sys.time() < deadline) Sys.sleep(0.1)
  stopifnot(file.exists(flag))
  tools::pskill(as.integer(pid), signal = 9L)
  Sys.sleep(0.5)
  # SIGKILL cannot execute on.exit handlers.  Recovery is explicit and only
  # accepted after the process identity is no longer live.
  for (target in c(tmp, s$durable$workspace)) {
    info <- wb_bundle_writer_lock_info(target, stale_after_seconds = 0)
    if (isTRUE(info$locked)) wb_recover_bundle_writer_lock(target, "RECOVER STALE SCWORKBENCH WRITER LOCK", stale_after_seconds = 0, allow_unknown_owner = TRUE)
  }
  wb_close_bundle(b); b <- wb_open_bundle(tmp)
  resumed <- wb_session_resume(b, s$durable$workspace)
  stopifnot(length(resumed$runs) == 1L, identical(resumed$head_run_id, names(resumed$runs)[1]))
  promoted <- wb_session_promote_current(b, resumed, outputs = "vector", created_by = "subprocess-kill")
  stopifnot(identical(as.character(promoted$promoted$status[1]), "ok"))
  wb_session_discard(resumed)
  TRUE
}
