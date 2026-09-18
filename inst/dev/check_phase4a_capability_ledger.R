#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
root <- normalizePath(if (length(args) && !startsWith(args[[1L]], "--"))
  args[[1L]] else ".", mustWork = TRUE)
write_json <- "--write" %in% args
csv_path <- file.path(root, "notes", "phase4a_rna_representation_capability_ledger.csv")
json_path <- file.path(root, "notes", "phase4a_rna_representation_capability_ledger.json")
ledger <- read.csv(csv_path, stringsAsFactors = FALSE, check.names = FALSE)
required <- c("order", "remedy_group", "issue_id", "methods", "target_pack",
  "classification", "focused_probe", "probe_result", "affected_primitive_grant",
  "authoritative_core_data", "pack_request_output", "atomicity_rule",
  "smallest_negative_fixture", "implementation_order", "source_anchors")
stopifnot(identical(names(ledger), required), nrow(ledger) == 8L,
  identical(ledger$order, seq_len(8L)), !anyDuplicated(ledger$issue_id),
  all(ledger$classification %in% c("demonstrated_gap",
    "unproven_runtime_surface")),
  identical(sort(unique(ledger$target_pack)), c("scwbRepresentation", "scwbRNA")),
  all(nzchar(as.matrix(ledger[, setdiff(required, "order")]))))
methods <- sort(unique(unlist(strsplit(ledger$methods, ";", fixed = TRUE))))
expected_methods <- sort(c("cell_suffix_label", "rna_qc_metrics", "hvg_select",
  "matrix_log_normalize", "pca_fit", "umap_fit", "umap_transform",
  "knn_neighbors", "knn_pseudobulk"))
stopifnot(identical(methods, expected_methods), !"leiden" %in% methods)
anchors <- unique(unlist(strsplit(ledger$source_anchors, ";", fixed = TRUE)))
stopifnot(all(file.exists(file.path(root, anchors))))
records <- lapply(seq_len(nrow(ledger)), function(i) {
  row <- as.list(ledger[i, , drop = FALSE])
  row$order <- as.integer(row$order)
  row$methods <- strsplit(row$methods, ";", fixed = TRUE)[[1L]]
  row$source_anchors <- strsplit(row$source_anchors, ";", fixed = TRUE)[[1L]]
  row
})
document <- list(schema = "scworkbench.phase4a.capability_ledger.v1",
  base_core_commit = "19b69bd99bccd81b4e62d839c7d4016984aeec36",
  source_survey_commit = "8799adcc41e41bc7e33f1a42a022e98f102de09e",
  scope = list(issue_count = 8L, method_count = 9L,
    implemented_in_phase4a = character(),
    excluded_pilot = "scwbrepresentation::leiden"),
  records = records)
canonical <- jsonlite::toJSON(document, auto_unbox = TRUE, pretty = TRUE,
  null = "null", digits = NA)
if (write_json) writeLines(canonical, json_path, useBytes = TRUE) else {
  stopifnot(file.exists(json_path),
    identical(paste(readLines(json_path, warn = FALSE), collapse = "\n"),
      paste(strsplit(canonical, "\n", fixed = TRUE)[[1L]], collapse = "\n")))
}
cat("PHASE4A LEDGER OK issues=8 methods=9 classifications=2 anchors=",
  length(anchors), "\n", sep = "")
