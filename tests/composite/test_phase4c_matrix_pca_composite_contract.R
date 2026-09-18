test_phase4c_matrix_pca_composite_contract <- function() {
  contract_test_activate_rna_pack()
  contract_test_activate_representation_pack()
  required <- c("BPCells", "irlba")
  missing <- required[!vapply(required, requireNamespace, logical(1),
    quietly = TRUE)]
  if (length(missing)) return(contract_test_skip(paste(
    "Missing runtime dependencies:", paste(missing, collapse = ", "))))
  root <- tempfile("scwb_phase4c_composite_")
  bundle <- wb_init_bundle(root, overwrite = TRUE)
  on.exit({try(wb_close_bundle(bundle), silent = TRUE)
    unlink(root, recursive = TRUE, force = TRUE)}, add = TRUE)
  cells <- paste0("c", seq_len(8L)); features <- paste0("g", seq_len(5L))
  values <- matrix(seq_len(40L), nrow = length(features),
    dimnames = list(features, cells))
  wb_define_cells(bundle, cells)
  wb_attach_matrix(bundle, "RNA", values, feature_type = "gene")
  normalized <- wb_session_run_op(wb_session_new(), bundle,
    "matrix_log_normalize", inputs = list(matrix = "RNA",
      output_matrix_id = "RNA_log", scale_factor = 1000,
      chunk_size = 3L, overwrite = FALSE, min_cells = 1L))
  pca <- wb_session_run_op(normalized$session, bundle, "pca_fit",
    inputs = list(matrix = "RNA_log", feature_ids = features,
      n_components = 3L, center = TRUE, scale = FALSE,
      backend = "prcomp", seed = 1L, space_id_out = "pca",
      overwrite = FALSE, max_dense_gb = 1, chunk_size = 2L,
      min_cells = 1L))
  promoted <- wb_session_promote_current(bundle, pca$session,
    outputs = "fit_summary", created_by = "phase4c-composite")
  stopifnot(all(promoted$promoted$status[
      promoted$promoted$output == "fit_summary"] == "ok"),
    any(promoted$promoted$op_name == "scwbrna::matrix_log_normalize" &
      promoted$promoted$status == "skipped"),
    "RNA_log" %in% wb_matrices(bundle)$matrix_id,
    "pca" %in% wb_spaces(bundle)$space_id,
    identical(dim(wb_space(bundle, "pca")), c(8L, 3L)))
  wb_operation_pack_unload("scwbrna")
  wb_operation_pack_unload("scwbrepresentation")
  wb_close_bundle(bundle)
  bundle <- wb_open_bundle(root, read_only = TRUE)
  stopifnot(isTRUE(wb_bundle_validation_report(root, "content")$ok),
    identical(dim(wb_space(bundle, "pca")), c(8L, 3L)))
  TRUE
}
