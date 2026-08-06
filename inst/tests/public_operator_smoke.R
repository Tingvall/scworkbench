#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) && identical(args[[1L]], "--installed")) {
  library(scworkbench)
  stopifnot(nzchar(system.file("onboarding", package = "scworkbench")),
            file.exists(system.file("protocol/pybench-op-v2.schema.json", package = "scworkbench")))
  root <- tempfile("scwb_public_operator_")
  b <- wb_init_bundle(root, overwrite = TRUE)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  wb_define_cells(b, c("c1", "c2", "c3"))
  wb_attach_matrix(b, "RNA_counts", matrix(c(1, 2, 3, 4, 5, 6), 2,
    dimnames = list(c("g1", "g2"), c("c1", "c2", "c3"))), feature_type = "gene")
  stopifnot(is.list(wb_op_interface("cells_counts_by", bundle = b)))
  result <- wb_session_run_op(wb_session_new(), b, "cells_counts_by",
    inputs = list(cell_set = "all", column = "dataset_id"))
  promoted <- wb_session_promote_current(b, result$session, outputs = "counts", created_by = "public-smoke")
  stopifnot(length(promoted$artifact_ids) >= 1L)
  wb_close_bundle(b)
  reopened <- wb_open_bundle(root, validate = TRUE)
  stopifnot(nrow(wb_prov_artifact_lineage(reopened, promoted$artifact_ids[[1L]])) >= 0L)
  wb_finalize_recipient_bundle(reopened)
  wb_close_bundle(reopened)
  recipient <- wb_open_bundle(root, read_only = TRUE, validate = TRUE)
  on.exit(try(wb_close_bundle(recipient), silent = TRUE), add = TRUE)
  stopifnot(isTRUE(recipient$read_only), is.list(wb_recipient_readiness(recipient)))
  cat("installed public operator smoke: OK\n")
  quit(status = 0L)
}
stop("Run this script through the source-package contract.", call. = FALSE)
