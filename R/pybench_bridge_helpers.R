# Generic legacy PyBench bridge support retained for core-owned PeakVI, scVI,
# protocol-hello, and Python-pack transitions. No method registration lives here.
.wb_pybench_cleanup_staging_artifacts <- function(bundle, artifact_ids,
    keep_model_files = TRUE) {
  artifact_ids <- unique(as.character(artifact_ids %||% character(0)))
  artifact_ids <- artifact_ids[nzchar(artifact_ids)]
  if (!length(artifact_ids)) return(invisible(TRUE))

  con <- bundle$con
  params <- as.list(artifact_ids)
  qmarks <- paste(rep("?", length(artifact_ids)), collapse = ",")
  for (tbl in c("artifact_labels", "artifact_pseudotime",
      "artifact_relation_rows", "artifact_curves_2d",
      "artifact_table_rows", "artifact_tables", "artifact_model_ref")) {
    try(DBI::dbExecute(con, paste0("DELETE FROM ", tbl,
      " WHERE artifact_id IN (", qmarks, ");"), params = params),
      silent = TRUE)
  }
  if (!isTRUE(keep_model_files)) {
    model_dir <- file.path(bundle$dir, "artifact_models")
    for (aid in artifact_ids) {
      for (extension in c("pkl", "rds")) {
        path <- file.path(model_dir, paste0(aid, ".", extension))
        if (file.exists(path)) try(unlink(path, force = TRUE),
          silent = TRUE)
      }
    }
  }
  try(DBI::dbExecute(con, paste0("DELETE FROM artifacts WHERE artifact_id IN (",
    qmarks, ");"), params = params), silent = TRUE)
  invisible(TRUE)
}

.wb_pybench_bridge_run_or_stop <- function(bundle = NULL, ...) {
  bridge <- .wb_pybench_run_module(..., bundle = bundle)
  receipt <- bridge$receipt %||% list()
  if (!identical(as.character(receipt$status %||% "error"), "ok")) {
    stop(paste0("pybench op failed: ",
      as.character(receipt$error_class %||% "PybenchOpError"), ": ",
      as.character(receipt$message %||% "unknown error")), call. = FALSE)
  }
  bridge
}
