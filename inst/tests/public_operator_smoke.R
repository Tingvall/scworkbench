#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) && identical(args[[1L]], "--installed")) {
  library(scworkbench)
  expected_library <- normalizePath(Sys.getenv("SCWORKBENCH_EXPECTED_LIBRARY"), winslash = "/", mustWork = TRUE)
  installed_package <- normalizePath(find.package("scworkbench"), winslash = "/", mustWork = TRUE)
  stopifnot(identical(dirname(installed_package), expected_library))
  manifest_path <- system.file("documentation_manifest.json", package = "scworkbench")
  stopifnot(nzchar(manifest_path))
  manifest <- jsonlite::read_json(manifest_path, simplifyVector = TRUE)
  installed_entries <- manifest$entries[manifest$entries$installed_package %in% TRUE, , drop = FALSE]
  stopifnot(nrow(installed_entries) > 0L)
  for (relative_path in installed_entries$installed_relative_path) {
    stopifnot(length(relative_path) == 1L, !is.na(relative_path), nzchar(relative_path),
              file.exists(system.file(relative_path, package = "scworkbench")))
  }
  stopifnot(nzchar(system.file("onboarding", package = "scworkbench")),
            file.exists(system.file("protocol/pybench-op-v2.schema.json", package = "scworkbench")))
  root <- tempfile("scwb_public_operator_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  cell_ids <- paste0("c", seq_len(12L))
  metadata <- data.frame(
    cell_id = cell_ids,
    condition = rep(c("control", "treated"), each = 6L),
    stringsAsFactors = FALSE
  )
  wb_define_cells(b, cell_ids, metadata = metadata)
  stopifnot(is.list(wb_op_interface("metadata_cell_vector", bundle = b)))
  result <- wb_session_run_op(
    wb_session_new(), b, "metadata_cell_vector",
    inputs = list(
      source_column = "condition", vector_name = "condition_smoke",
      value_type = "categorical", missing_policy = "error",
      cell_set = "all", min_cells = 1L
    )
  )
  promoted <- wb_session_promote_current(
    b, result$session, outputs = "vector", created_by = "public-smoke"
  )
  promoted_rows <- promoted$promoted[
    promoted$promoted$status == "ok" & promoted$promoted$output == "vector",
    , drop = FALSE
  ]
  stopifnot(nrow(promoted_rows) == 1L, nzchar(promoted_rows$artifact_id[[1L]]))
  artifact_id <- promoted_rows$artifact_id[[1L]]
  wb_close_bundle(b)
  reopened <- wb_open_bundle(root, validate = TRUE)
  stopifnot(artifact_id %in% wb_art_list(reopened)$artifact_id)
  vector <- wb_art_load(reopened, artifact_id, expected_kind = "cell_vector")
  stopifnot(length(vector$cell_id) == length(cell_ids),
            setequal(vector$cell_id, cell_ids))
  stopifnot(nrow(wb_prov_artifact_lineage(reopened, artifact_id)) > 0L)
  readiness <- wb_finalize_recipient_bundle(reopened)
  stopifnot(isTRUE(readiness$ready))
  wb_close_bundle(reopened)
  recipient <- wb_open_bundle(root, read_only = TRUE, validate = TRUE)
  on.exit(try(wb_close_bundle(recipient), silent = TRUE), add = TRUE)
  readiness <- wb_recipient_readiness(root)
  mutation_error <- tryCatch({
    wb_define_cells(recipient, "c4")
    NULL
  }, error = identity)
  stopifnot(isTRUE(recipient$read_only), isTRUE(readiness$ready), inherits(mutation_error, "error"))
  cat("installed public operator smoke: OK\n")
  quit(status = 0L)
}
stop("Run this script through the source-package contract.", call. = FALSE)
