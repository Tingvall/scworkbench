test_durable_session_generation_recovery_contract <- function() {
  tmp <- tempfile("scwb_durable_generation_bundle_")
  root <- tempfile("scwb_durable_generation_root_")
  b <- wb_init_bundle(tmp, overwrite = TRUE)
  on.exit({ try(wb_close_bundle(b), silent = TRUE); unlink(tmp, recursive = TRUE, force = TRUE); unlink(root, recursive = TRUE, force = TRUE) }, add = TRUE)
  cells <- paste0("c", 1:3)
  wb_define_cells(b, cells)
  wb_attach_metadata(b, data.frame(cell_id = cells, group = c("a", "b", "a"), score = 1:3, stringsAsFactors = FALSE))
  run_vector <- function(session, name, column = "group") wb_session_run_op(session, b, "metadata_cell_vector", inputs = list(
    source_column = column, vector_name = name, value_type = "auto", missing_policy = "error", overwrite = TRUE, cell_set = "all", min_cells = 1L))

  s <- wb_session_create(b, root, "generation_case")
  one <- run_vector(s, "one")
  old_pointer <- readLines(file.path(s$durable$workspace, "CURRENT.json"), warn = FALSE)
  old_run <- one$run$run_id
  old_hook <- getOption("scworkbench.durable_session_fault_hook")
  on.exit(options(scworkbench.durable_session_fault_hook = old_hook), add = TRUE)
  for (boundary in c("before_serialization", "after_serialized_bytes", "after_metadata", "before_generation_publication")) {
    options(scworkbench.durable_session_fault_hook = function(where) if (identical(where, boundary)) stop("injected checkpoint fault"))
    failed <- try(run_vector(one$session, paste0("fault_", boundary), "score"), silent = TRUE)
    stopifnot(inherits(failed, "try-error"), identical(readLines(file.path(s$durable$workspace, "CURRENT.json"), warn = FALSE), old_pointer))
    recovered <- wb_session_resume(b, s$durable$workspace)
    stopifnot(identical(names(recovered$runs), old_run))
  }
  options(scworkbench.durable_session_fault_hook = old_hook)
  two <- run_vector(wb_session_resume(b, s$durable$workspace), "two", "score")
  resumed <- wb_session_resume(b, s$durable$workspace)
  stopifnot(identical(names(resumed$runs), c(old_run, two$run$run_id)))
  promoted <- wb_session_promote_current(b, resumed, outputs = "vector", created_by = "durable-generation")
  stopifnot(identical(as.character(promoted$promoted$status[1]), "ok"))

  # A pointer publication is the commit point.  The injected error is returned
  # to the caller, but a stale pre-publication handle can never retry over it.
  pre_publication <- wb_session_resume(b, s$durable$workspace)
  options(scworkbench.durable_session_fault_hook = function(where) if (identical(where, "after_generation_publication")) stop("injected post-publication error"))
  post <- try(.wb_session_checkpoint(pre_publication, "active"), silent = TRUE)
  stopifnot(inherits(post, "try-error"), grepl("post-publication", as.character(post), fixed = TRUE))
  committed_after_error <- wb_session_resume(b, s$durable$workspace)
  stopifnot(identical(names(committed_after_error$runs), names(pre_publication$runs)))
  stale <- try(run_vector(pre_publication, "must_not_overwrite", "score"), silent = TRUE)
  stopifnot(inherits(stale, "try-error"), grepl("DURABLE_SESSION_STALE_GENERATION", as.character(stale), fixed = TRUE))
  options(scworkbench.durable_session_fault_hook = old_hook)

  # An operation marker is intentionally outside the completed generation: a
  # killed operation is listed as interrupted and resume returns its prior DAG.
  .wb_session_operation_marker(committed_after_error, "metadata_cell_vector", "run_interrupted")
  listed_marker <- wb_session_list(root)
  stopifnot(identical(as.character(listed_marker$state[listed_marker$session_id == "generation_case"]), "interrupted"))
  recovered_marker <- wb_session_resume(b, s$durable$workspace)
  stopifnot(identical(names(recovered_marker$runs), names(committed_after_error$runs)))
  cleared <- run_vector(recovered_marker, "marker_cleared", "score")
  stopifnot(!file.exists(file.path(s$durable$workspace, "OPERATION.json")), length(cleared$session$runs) == length(committed_after_error$runs) + 1L)

  # Publication metadata and bytes are independently integrity-bound before RDS is read.
  ptr <- .wb_session_pointer(s$durable$workspace)
  meta_path <- ptr$metadata_path
  original_meta <- readBin(meta_path, "raw", n = file.info(meta_path)$size)
  writeBin(as.raw(0L), meta_path)
  bad_meta <- try(wb_session_open(s$durable$workspace), silent = TRUE)
  stopifnot(inherits(bad_meta, "try-error"), grepl("DURABLE_SESSION_CORRUPT", as.character(bad_meta), fixed = TRUE))
  writeBin(original_meta, meta_path)
  # Re-publish a good generation instead of mutating the current one.
  resumed <- wb_session_resume(b, s$durable$workspace)
  resumed <- .wb_session_checkpoint(resumed, "active")
  ptr <- .wb_session_pointer(s$durable$workspace)
  rds_path <- file.path(dirname(ptr$metadata_path), "session.rds")
  original_rds <- readBin(rds_path, "raw", n = file.info(rds_path)$size)
  writeBin(head(original_rds, 8L), rds_path)
  bad_rds <- try(wb_session_open(s$durable$workspace), silent = TRUE)
  stopifnot(inherits(bad_rds, "try-error"), grepl("serialized-byte binding", as.character(bad_rds), fixed = TRUE))

  # A partial directory never becomes an active checkpoint and retention removes it only.
  partial <- file.path(s$durable$workspace, "checkpoints", "g_partial")
  dir.create(partial, recursive = TRUE)
  writeLines("partial", file.path(partial, "session.rds"))
  # restore the last generation and ensure cleanup does not traverse stage links.
  writeBin(original_rds, rds_path)
  listed <- wb_session_list(root)
  stopifnot(identical(as.character(listed$state[listed$session_id == "generation_case"]), "active"))
  recovered <- wb_session_resume(b, s$durable$workspace)
  wb_session_cleanup(recovered)
  stopifnot(!dir.exists(partial), dir.exists(file.path(recovered$durable$workspace, "stage")))
  wb_session_discard(recovered)
  TRUE
}
