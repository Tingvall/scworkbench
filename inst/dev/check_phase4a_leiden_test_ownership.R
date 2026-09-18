#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
root <- normalizePath(if (length(args)) args[[1L]] else ".", mustWork = TRUE)
ledger_path <- file.path(root, "notes", "phase4a_leiden_test_ownership.csv")
ledger <- read.csv(ledger_path, stringsAsFactors = FALSE, check.names = FALSE)
required <- c("order", "source_path", "assertion_group", "reference_kind",
  "ownership", "destination", "action", "justification")
stopifnot(
  identical(names(ledger), required),
  nrow(ledger) == 21L,
  identical(ledger$order, seq_len(nrow(ledger))),
  !anyDuplicated(ledger$assertion_group),
  all(nzchar(as.matrix(ledger[, setdiff(required, "order")]))),
  all(file.exists(file.path(root, ledger$destination)))
)

default_files <- sort(list.files(file.path(root, "tests"),
  pattern = "^test_.*\\.R$", full.names = TRUE, recursive = FALSE))
composite_files <- sort(list.files(file.path(root, "tests", "composite"),
  pattern = "^test_.*\\.R$", full.names = TRUE, recursive = FALSE))
stopifnot(length(default_files) > 0L, length(composite_files) > 0L,
  !length(intersect(default_files, composite_files)))

literal_string <- function(value) {
  if (is.character(value) && length(value) == 1L) value else NA_character_
}
call_operation <- function(call, function_name) {
  if (!is.call(call) || !identical(as.character(call[[1L]]), function_name)) return(NA_character_)
  fields <- as.list(call)[-1L]
  field_names <- names(fields) %||% rep("", length(fields))
  named <- which(field_names == "op_name")
  value <- if (length(named)) fields[[named[[1L]]]] else if (
    identical(function_name, "wb_session_run_op") && length(fields) >= 3L
  ) fields[[3L]] else NULL
  literal_string(value)
}
`%||%` <- function(x, y) if (is.null(x)) y else x
find_calls <- function(node, function_name, path = "") {
  found <- list()
  if (is.call(node)) {
    operation <- call_operation(node, function_name)
    if (!is.na(operation)) found[[length(found) + 1L]] <- list(operation = operation, path = path)
  }
  if (is.recursive(node)) for (index in seq_along(node)) {
    found <- c(found, find_calls(node[[index]], function_name,
      paste0(path, if (nzchar(path)) "/" else "", index)))
  }
  found
}
scan_file <- function(path, function_name) {
  expressions <- parse(path, keep.source = TRUE)
  calls <- unlist(lapply(seq_along(expressions), function(index)
    find_calls(expressions[[index]], function_name, as.character(index))), recursive = FALSE)
  if (!length(calls)) return(data.frame(file = character(), operation = character(),
    stringsAsFactors = FALSE))
  operations <- vapply(calls, `[[`, character(1), "operation")
  data.frame(file = basename(path), operation = operations, stringsAsFactors = FALSE)
}
dispatches <- do.call(rbind, lapply(default_files, scan_file,
  function_name = "wb_session_run_op"))
leiden_dispatches <- dispatches[dispatches$operation == "leiden", , drop = FALSE]
stopifnot(
  nrow(leiden_dispatches) == 1L,
  identical(leiden_dispatches$file, "test_representation_extraction_contract.R")
)
synthetic_runs <- do.call(rbind, lapply(default_files, scan_file,
  function_name = "wb_new_run"))
stopifnot(!any(synthetic_runs$operation == "leiden"))
golden_runs <- scan_file(file.path(root, "inst", "golden_bundle",
  "create_golden_bundle.R"), "wb_new_run")
stopifnot(!any(golden_runs$operation == "leiden"))

negative <- paste(readLines(file.path(root, "tests",
  "test_representation_extraction_contract.R"), warn = FALSE), collapse = "\n")
stopifnot(
  grepl("OPERATION_PACK_REQUIRED", negative, fixed = TRUE),
  grepl("durable_before", negative, fixed = TRUE),
  grepl("wb_operation_catalog_identity", negative, fixed = TRUE)
)
expected_composite <- c(
  "test_scwb_representation_cell_vector_identity_contract.R",
  "test_scwb_representation_transitive_promotion_contract.R"
)
stopifnot(all(expected_composite %in% basename(composite_files)),
  !any(expected_composite %in% basename(default_files)))

cat("PHASE4A LEIDEN TEST OWNERSHIP OK ledger_rows=", nrow(ledger),
  " default_files=", length(default_files),
  " default_leiden_dispatches=", nrow(leiden_dispatches),
  " expected_negative_dispatches=1 composite_moved=2\n", sep = "")
