#!/usr/bin/env Rscript
# Reconstruct the accepted Phase 7 root-test inventory from Git, not from the
# edited Phase 8 working tree. Usage: Rscript ... <inventory.csv> <references.csv>
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("Expected inventory.csv and references.csv")
baseline <- "0aaa68893e595993c2664e104f7e0dc20702f960"
git <- function(...) {
  out <- suppressWarnings(system2("git", c(...), stdout = TRUE, stderr = TRUE))
  if (!is.null(attr(out, "status")) && attr(out, "status") != 0L)
    stop(paste(out, collapse = "\n"))
  out
}
paths <- git("ls-tree", "-r", "--name-only", baseline, "tests")
paths <- sort(paths[grepl("^tests/test_.*\\.R$", paths)])
stopifnot(length(paths) == 139L)
walk <- function(x, fun) {
  if (is.call(x)) {
    fun(x)
    if (length(x) > 1L) for (i in seq.int(2L, length(x)))
      try(walk(x[[i]], fun), silent = TRUE)
  } else if (is.expression(x) || is.pairlist(x) || is.list(x)) {
    for (i in seq_along(x)) try(walk(x[[i]], fun), silent = TRUE)
  }
}
call_text <- function(x) paste(deparse(x, width.cutoff = 500L), collapse = " ")
op_names <- c("de_wilcox", "markers_topn", "cell_vector_assoc",
  "cell_vector_association", "cell_vector_compare", "feature_trend_spearman",
  "addmodulescore", "ucell", "cell_vector_family_reduce",
  "cell_vector_family_calibrate", "cell_vector_family_qc",
  "cell_vector_family_graph_smooth", "cell_vector_winners",
  "winner_cell_sets", "feature_set_overlap_qc", "pathway_enrich",
  "leiden", "pca_fit", "umap_fit", "umap_transform",
  "cell_suffix_label", "rna_qc_metrics", "hvg_select",
  "matrix_log_normalize", "knn_build", "knn_pseudobulk",
  "space_path_define", "trajectory_segment_from_artifacts",
  "trajectory_space_path_segment", "trajectory_segment_join",
  "trajectory_segment_path_join", "slingshot", "slingshot_fit",
  "slingshot_lineage_weights", "slingshot_project", "palantir",
  "scvi_train", "peakvi_train", "chromvar")
overrides <- list(
  test_immutable_history_state_machine_closure_contract = c(
    "pinned_composite", "retain_composite",
    "tests/composite/phase8/test_immutable_history_state_machine_closure_contract.R",
    "Real Representation UMAP/model historical lifecycle requires an exact pack."),
  test_durable_session_source_payload_corruption_contract = c(
    "core_engine", "replace_with_conformance",
    "tests/test_durable_session_source_payload_corruption_contract.R;tests/composite/phase8/test_durable_session_staged_space_registry_binding_contract.R",
    "Generic source/payload checks use synthetic model; real UMAP registry binding is pinned composite."),
  test_public_typed_run_branch_inputs_contract = c(
    "core_engine", "replace_with_conformance",
    "tests/test_public_typed_run_branch_inputs_contract.R",
    "Generic typed-branch and replay authority use synthetic G1 model fixture."),
  test_strict_operation_input_validation_contract = c(
    "core_engine", "replace_with_conformance",
    "tests/test_strict_operation_input_validation_contract.R",
    "Generic validation uses retained core metadata operation."),
  test_operation_pack_v3_pseudobulk_zero_neighbor_policy_contract = c(
    "pack_method", "move",
    "scwbRepresentation/tests/test_knn_sparse_contract.R:test_representation_knn_pseudobulk_zero_neighbor_contract",
    "Scientific kNN zero-neighbor policy belongs to Representation; generic sparse grant stays core."))
rows <- list(); refs <- list()
for (path in paths) {
  parsed <- parse(text = git("show", paste0(baseline, ":", path)))
  for (expr in parsed) {
    if (!is.call(expr) || !identical(expr[[1L]], as.name("<-")) ||
        !is.symbol(expr[[2L]]) || !startsWith(as.character(expr[[2L]]), "test_") ||
        !is.call(expr[[3L]]) || !identical(expr[[3L]][[1L]], as.name("function"))) next
    name <- as.character(expr[[2L]])
    body <- expr[[3L]][[3L]]
    assertions <- character(); strings <- character()
    walk(body, function(node) {
      if (identical(node[[1L]], as.name("stopifnot")))
        assertions <<- c(assertions, call_text(node))
      if (length(node) > 1L) for (i in seq.int(2L, length(node)))
        try(if (is.character(node[[i]])) strings <<- c(strings, node[[i]]),
          silent = TRUE)
    })
    strings <- unique(strings)
    fixtures <- strings[grepl("(fixtures/|\\.bundle$|\\.rds$|\\.h5$|\\.h5ad$|\\.json$)", strings)]
    found <- unique(c(op_names[op_names %in% strings],
      strings[grepl("^scwb[a-z]+::[a-z_]+$", strings)]))
    override <- overrides[[name]]
    if (is.null(override)) override <- c("core_engine", "retain_core", path,
      "Engine authority, catalog, schema, security, provenance, or historical inspection assertion.")
    rows[[length(rows) + 1L]] <- data.frame(
      baseline_commit = baseline, test_identity = name, source_path = path,
      assertion_count = length(assertions), key_assertions = paste(assertions, collapse = " || "),
      fixtures = paste(fixtures, collapse = " | "),
      owner = override[[1L]], disposition = override[[2L]],
      destination = override[[3L]], justification = override[[4L]],
      migrated_operation_references = paste(found, collapse = " | "))
    for (op in found) refs[[length(refs) + 1L]] <- data.frame(
      baseline_commit = baseline, source_path = path, test_identity = name,
      migrated_operation = op, owner = override[[1L]],
      disposition = override[[2L]], destination = override[[3L]],
      justification = override[[4L]])
  }
}
inventory <- do.call(rbind, rows)
stopifnot(nrow(inventory) == 242L, !anyDuplicated(inventory$test_identity),
  !anyNA(inventory$owner), !anyNA(inventory$disposition))
write.csv(inventory, args[[1L]], row.names = FALSE, na = "")
references <- do.call(rbind, refs)
write.csv(references, args[[2L]], row.names = FALSE, na = "")
cat(sprintf("PHASE8_TEST_INVENTORY tests=%d files=%d migrated_reference_rows=%d\n",
  nrow(inventory), length(unique(inventory$source_path)), nrow(references)))
