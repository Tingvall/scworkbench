test_phase4e_rna_pca_knn_composite_contract <- function() {
  contract_test_activate_rna_pack()
  contract_test_activate_representation_pack()
  required <- c("BPCells", "irlba")
  missing <- required[!vapply(required, requireNamespace, logical(1),
    quietly = TRUE)]
  if (length(missing)) return(contract_test_skip(paste(
    "Missing runtime dependencies:", paste(missing, collapse = ", "))))
  root <- tempfile("scwb_phase4e_composite_")
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
  neighbors <- wb_session_run_op(pca$session, bundle, "knn_neighbors",
    inputs = list(space = "pca", query_cells = cells[1:2],
      candidate_cells = cells[3:8], k = 3L, include_query = FALSE,
      space_chunk_size = 2L, min_cells = 1L))
  pseudobulk <- wb_session_run_op(neighbors$session, bundle,
    "knn_pseudobulk", inputs = list(matrix = "RNA_log", space = "pca",
      query_cells = cells[1:2], candidate_cells = cells[3:8],
      features = features, k = 3L, include_query = FALSE,
      aggregate = "mean", space_chunk_size = 2L,
      matrix_chunk_size = 2L, min_cells = 1L))
  table <- pseudobulk$run$outputs$pseudobulk_table$table
  stopifnot(nrow(table) == 10L,
    identical(unique(table$query_cell_id), cells[1:2]),
    identical(unique(table$n_neighbors), 3L),
    identical(unique(table$aggregate), "mean"))
  promoted <- wb_session_promote_current(bundle, pseudobulk$session,
    outputs = "pseudobulk_table", created_by = "phase4e-composite")
  stopifnot(all(promoted$promoted$status %in% c("ok", "skipped")),
    any(promoted$promoted$op_name == "scwbrna::matrix_log_normalize"),
    any(promoted$promoted$op_name == "scwbrepresentation::pca_fit"),
    any(promoted$promoted$op_name == "scwbrepresentation::knn_pseudobulk"),
    "RNA_log" %in% wb_matrices(bundle)$matrix_id,
    "pca" %in% wb_spaces(bundle)$space_id)
  wb_close_bundle(bundle)
  registry <- scworkbench:::.wb_operation_pack_registry
  saved <- registry$packs[c("scwbrna", "scwbrepresentation")]
  saved_operations <- unlist(lapply(saved, function(pack)
    pack$operation_names), use.names = FALSE)
  saved_catalog <- registry$operations[saved_operations]
  on.exit({
    registry$packs[names(saved)] <- saved
    registry$operations[names(saved_catalog)] <- saved_catalog
  }, add = TRUE)
  for (name in saved_operations) registry$operations[[name]] <- NULL
  registry$packs$scwbrna <- NULL
  registry$packs$scwbrepresentation <- NULL
  stopifnot(!any(c("matrix_log_normalize", "pca_fit", "knn_neighbors",
    "knn_pseudobulk") %in% wb_list_ops()))
  bundle <- wb_open_bundle(root, read_only = TRUE)
  stopifnot(isTRUE(wb_bundle_validation_report(root, "content")$ok),
    identical(dim(wb_space(bundle, "pca")), c(8L, 3L)))
  TRUE
}
