#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
root <- normalizePath(if (length(args)) args[[1L]] else ".", mustWork = TRUE)
moved <- c("cell_suffix_label", "rna_qc_metrics", "hvg_select",
  "matrix_log_normalize")
default_files <- sort(list.files(file.path(root, "tests"),
  pattern = "^test_.*[.]R$", full.names = TRUE, recursive = FALSE))
composite_files <- sort(list.files(file.path(root, "tests", "composite"),
  pattern = "^test_.*[.]R$", full.names = TRUE, recursive = TRUE))

file_text <- function(path) paste(readLines(path, warn = FALSE), collapse = "\n")
literal_dispatch_count <- function(operation, files) sum(vapply(files,
  function(path) {
    text <- file_text(path)
    pattern <- paste0("wb_session_run_op[\\s\\S]{0,160}(op_name[[:space:]]*=[[:space:]]*)?[\"']",
      operation, "[\"']")
    length(gregexpr(pattern, text, perl = TRUE)[[1L]][
      gregexpr(pattern, text, perl = TRUE)[[1L]] > 0L])
  }, integer(1)))
default_counts <- setNames(vapply(moved, literal_dispatch_count, integer(1),
  files = default_files), moved)
composite_counts <- setNames(vapply(moved, literal_dispatch_count, integer(1),
  files = composite_files), moved)
stopifnot(all(default_counts == 0L))

default_text <- paste(vapply(default_files, file_text, character(1)),
  collapse = "\n")
stopifnot(!any(vapply(paste0("wb_op_", moved), function(pattern)
  grepl(pattern, default_text, fixed = TRUE), logical(1))))
negative <- paste(readLines(file.path(root, "tests",
  "test_rna_extraction_contract.R"), warn = FALSE), collapse = "\n")
stopifnot(grepl("OPERATION_PACK_REQUIRED", negative, fixed = TRUE),
  grepl("durable_before", negative, fixed = TRUE),
  grepl("wb_operation_catalog_identity", negative, fixed = TRUE),
  composite_counts[["hvg_select"]] >= 1L,
  composite_counts[["matrix_log_normalize"]] >= 1L,
  file.exists(file.path(root, "tests", "composite",
    "test_scwbrna_targeted_reproduction_plan_contract.R")))

cat("PHASE4B RNA TEST OWNERSHIP OK default_files=", length(default_files),
  " default_moved_dispatches=0 default_removed_exports=0 composite_moved_dispatches=",
  sum(composite_counts), "\n", sep = "")
